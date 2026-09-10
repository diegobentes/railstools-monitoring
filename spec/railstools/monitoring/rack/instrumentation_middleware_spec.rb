# frozen_string_literal: true

RSpec.describe Railstools::Monitoring::Rack::InstrumentationMiddleware do
  subject(:middleware) { described_class.new(app) }

  let(:dispatcher) { use_fake_dispatcher }
  let(:app) { ->(_env) { [200, {}, ["ok"]] } }

  def env(overrides = {})
    {
      "REQUEST_METHOD" => "GET", "PATH_INFO" => "/pedidos/42", "QUERY_STRING" => "",
      "HTTP_USER_AGENT" => "rspec", "SERVER_NAME" => "exemplo.com.br"
    }.merge(overrides)
  end

  it "mede a requisição e manda como transação" do
    dispatcher

    status, = middleware.call(env)

    expect(status).to eq(200)
    trace = dispatcher.traces.first
    expect(trace[:namespace]).to eq("web")
    expect(trace[:http_status]).to eq(200)
    expect(trace[:path]).to eq("/pedidos/42")
    expect(trace[:duration_ms]).to be >= 0
  end

  # Sem isto, `/pedidos/1` e `/pedidos/2` seriam duas séries — e a lista de desempenho viraria uma
  # linha por id.
  it "usa o nome do controller quando o Rails já resolveu a rota" do
    dispatcher

    middleware.call(env("action_dispatch.request.parameters" => {
                          "controller" => "admin/pedidos", "action" => "show", "id" => "42"
                        }))

    expect(dispatcher.traces.first[:action]).to eq("Admin::PedidosController#show")
  end

  it "sem rota resolvida, a ação é método e caminho" do
    dispatcher

    middleware.call(env)

    expect(dispatcher.traces.first[:action]).to eq("GET /pedidos/42")
  end

  it "tira controller e action dos parâmetros guardados" do
    dispatcher
    Railstools::Monitoring.config.sample_rate = 1.0

    middleware.call(env("action_dispatch.request.parameters" => {
                          "controller" => "pedidos", "action" => "show", "id" => "42", "senha" => "x"
                        }))

    params = dispatcher.traces.first[:sample][:params]

    expect(params.keys).to contain_exactly("id", "senha")
  end

  describe "tempo de fila" do
    it "lê o cabeçalho do nginx, em segundos com fração" do
      dispatcher
      started = Time.now.to_f - 0.25

      middleware.call(env("HTTP_X_REQUEST_START" => "t=#{started}"))

      expect(dispatcher.traces.first[:queue_time_ms]).to be_within(80).of(250)
    end

    it "lê o cabeçalho em milissegundos" do
      dispatcher
      started = (Time.now.to_f - 0.25) * 1_000

      middleware.call(env("HTTP_X_QUEUE_START" => started.round.to_s))

      expect(dispatcher.traces.first[:queue_time_ms]).to be_within(80).of(250)
    end

    # Meia hora de "espera" é relógio errado entre proxy e app, não fila. Reportar isso é pior que
    # não reportar nada: manda a equipe caçar capacidade que não falta.
    it "descarta valor absurdo, que é relógio errado e não fila" do
      dispatcher

      middleware.call(env("HTTP_X_REQUEST_START" => "t=#{Time.now.to_f - 7_200}"))

      expect(dispatcher.traces.first[:queue_time_ms]).to be_nil
    end

    it "sem cabeçalho, não inventa" do
      dispatcher

      middleware.call(env)

      expect(dispatcher.traces.first[:queue_time_ms]).to be_nil
    end
  end

  it "captura o erro, marca 500 e deixa subir" do
    dispatcher
    quebrado = ->(_env) { raise ArgumentError, "quebrou" }

    expect { described_class.new(quebrado).call(env) }.to raise_error(ArgumentError)

    expect(dispatcher.errors.first[:exception_class]).to eq("ArgumentError")
    expect(dispatcher.traces.first[:http_status]).to eq(500)
  end

  it "ação ignorada não vira nem métrica nem amostra" do
    dispatcher
    Railstools::Monitoring.config.ignore_actions = ["GET /up"]

    middleware.call(env("PATH_INFO" => "/up"))

    expect(dispatcher.traces).to be_empty
  end

  it "com o agente desligado, é só passagem" do
    Railstools::Monitoring.reset!

    status, _headers, body = middleware.call(env)

    expect([status, body]).to eq([200, ["ok"]])
  end

  it "não deixa transação vazando para a próxima requisição" do
    dispatcher

    middleware.call(env)

    expect(Railstools::Monitoring::Transaction.current).to be_nil
  end
end
