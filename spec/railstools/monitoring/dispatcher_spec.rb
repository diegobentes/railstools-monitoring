# frozen_string_literal: true

RSpec.describe Railstools::Monitoring::Dispatcher do
  subject(:dispatcher) { described_class.new(config) }

  let(:config) do
    Railstools::Monitoring::Config.new(
      app_name: "Teste", push_api_key: "chave", endpoint: "http://monitoring.teste",
      flush_interval: 60, max_queue_size: 5, batch_size: 2, hostname: "maquina", revision: "abc"
    )
  end

  def stub_push
    stub_request(:post, "http://monitoring.teste/api/v1/push")
      .to_return(status: 202, body: '{"ok":true}', headers: { "Content-Type" => "application/json" })
  end

  it "acumula na fila sem tocar na rede" do
    dispatcher.push(:logs, { message: "oi" })
    dispatcher.push(:metrics, { name: "x", value: 1 })

    expect(dispatcher.size).to eq(2)
    expect(WebMock).not_to have_requested(:post, /monitoring/)
  end

  # Um agente que cresce sem limite dentro do processo derruba o app que deveria vigiar — e faz isso
  # justamente quando o servidor de telemetria está fora do ar, que é quando a fila enche.
  it "descarta o dado NOVO quando a fila enche, em vez de crescer" do
    10.times { |i| dispatcher.push(:logs, { message: "linha #{i}" }) }

    expect(dispatcher.size).to eq(5)
    expect(dispatcher.dropped).to eq(5)
  end

  it "envia o que estava na fila e a esvazia" do
    request = stub_push
    dispatcher.push(:logs, { message: "oi" })

    expect(dispatcher.flush).to eq(1)
    expect(dispatcher.size).to eq(0)
    expect(request).to have_been_requested
  end

  it "manda hostname, revisão e versão do agente no envelope" do
    request = stub_request(:post, "http://monitoring.teste/api/v1/push")
              .with do |req|
      body = JSON.parse(req.body)
      body["hostname"] == "maquina" && body["revision"] == "abc" &&
        body["agent_version"] == Railstools::Monitoring::VERSION
    end
      .to_return(status: 202)

    dispatcher.push(:logs, { message: "oi" })
    dispatcher.flush

    expect(request).to have_been_requested
  end

  it "quebra a fila acumulada em lotes" do
    stub_push
    5.times { |i| dispatcher.push(:traces, { token: "t#{i}" }) }

    dispatcher.flush

    expect(WebMock).to have_requested(:post, "http://monitoring.teste/api/v1/push").times(3)
  end

  it "fila vazia não gera requisição" do
    expect(dispatcher.flush).to eq(0)
    expect(WebMock).not_to have_requested(:post, /monitoring/)
  end

  # Servidor fora do ar não pode virar exceção no app de quem instalou.
  it "engole a falha de rede" do
    stub_request(:post, "http://monitoring.teste/api/v1/push").to_timeout
    dispatcher.push(:logs, { message: "oi" })

    expect { dispatcher.flush }.not_to raise_error
  end

  it "recusa do servidor não estoura, e vira aviso no log do app" do
    stub_request(:post, "http://monitoring.teste/api/v1/push")
      .to_return(status: 402, body: '{"error":"assinatura cancelada"}')
    logger = instance_double(Logger, warn: nil)
    allow(Railstools::Monitoring).to receive(:logger).and_return(logger)

    dispatcher.push(:logs, { message: "oi" })
    dispatcher.flush

    expect(logger).to have_received(:warn).with(/402.*cancelada/)
  end

  it "comprime lote grande" do
    request = stub_request(:post, "http://monitoring.teste/api/v1/push")
              .with(headers: { "Content-Encoding" => "gzip" }).to_return(status: 202)

    dispatcher.push(:logs, { message: "a" * 8_000 })
    dispatcher.flush

    expect(request).to have_been_requested
  end
end
