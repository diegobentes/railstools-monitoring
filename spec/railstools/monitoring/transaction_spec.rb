# frozen_string_literal: true

RSpec.describe Railstools::Monitoring::Transaction do
  let(:dispatcher) { use_fake_dispatcher }

  it "mede a duração e envia ao terminar" do
    dispatcher

    described_class.wrap(action: "PedidosController#create") do |transaction|
      transaction.http_status = 200
      sleep(0.01)
    end

    expect(dispatcher.traces.size).to eq(1)
    trace = dispatcher.traces.first

    expect(trace[:action]).to eq("PedidosController#create")
    expect(trace[:namespace]).to eq("web")
    expect(trace[:duration_ms]).to be >= 10
    expect(trace[:http_status]).to eq(200)
  end

  it "guarda os eventos na ordem em que aconteceram" do
    dispatcher
    Railstools::Monitoring.config.sample_rate = 1.0

    described_class.wrap(action: "A#b") do |transaction|
      transaction.record_event(name: "sql.active_record", group: "active_record", duration_ms: 5,
                               body: "SELECT 1")
      transaction.record_event(name: "render_template.action_view", group: "action_view",
                               duration_ms: 3)
    end

    spans = dispatcher.traces.first[:spans]

    expect(spans.map { |span| span[:group] }).to eq(%w[active_record action_view])
    expect(spans.first[:body]).to eq("SELECT 1")
  end

  # `Exception` e não `StandardError`: perder a telemetria de um desligamento é perder justamente a
  # informação de por que ele aconteceu.
  it "captura o erro, deixa ele subir e manda como ocorrência" do
    dispatcher

    expect do
      described_class.wrap(action: "A#b") { raise ArgumentError, "quebrou" }
    end.to raise_error(ArgumentError, "quebrou")

    expect(dispatcher.errors.size).to eq(1)
    error = dispatcher.errors.first

    expect(error[:exception_class]).to eq("ArgumentError")
    expect(error[:message]).to eq("quebrou")
    expect(error[:trace_token]).to eq(dispatcher.traces.first[:token])
    expect(error[:backtrace]).to be_an(Array)
  end

  it "manda as causas encadeadas, que é onde costuma estar o erro de verdade" do
    dispatcher

    begin
      begin
        raise "a causa"
      rescue RuntimeError
        raise ArgumentError, "o embrulho"
      end
    rescue ArgumentError => e
      described_class.wrap(action: "A#b") { |transaction| transaction.record_error(e) }
    end

    expect(dispatcher.errors.first[:causes].first[:message]).to eq("a causa")
  end

  it "não deixa uma requisição patológica virar payload de megabytes" do
    dispatcher
    Railstools::Monitoring.config.sample_rate = 1.0

    described_class.wrap(action: "A#b") do |transaction|
      1_000.times do
        transaction.record_event(name: "sql.active_record", group: "active_record", duration_ms: 1)
      end
      expect(transaction.dropped_spans).to be_positive
    end

    expect(dispatcher.traces.first[:spans].size).to eq(described_class::MAX_SPANS)
  end

  it "filtra segredo antes de sair do processo" do
    dispatcher
    Railstools::Monitoring.config.sample_rate = 1.0

    described_class.wrap(action: "A#b") do |transaction|
      transaction.params = { "pedido" => { "total" => 10 }, "password" => "123", "api_key" => "x" }
    end

    params = dispatcher.traces.first[:sample][:params]

    expect(params["password"]).to eq("[FILTRADO]")
    expect(params["api_key"]).to eq("[FILTRADO]")
    expect(params.dig("pedido", "total")).to eq(10)
  end

  it "transação aninhada devolve a de fora ao terminar" do
    dispatcher
    externa = described_class.start(action: "Externa#a")

    described_class.wrap(action: "Interna#b") { nil }

    expect(described_class.current).to eq(externa)
  end
end
