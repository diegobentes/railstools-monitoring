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

  # Em Rails, quem responde pelo erro é o ShowExceptions, mais embaixo na pilha: a exceção vira
  # página 500 e não sobe. O que chega aqui é uma resposta comum com a exceção guardada no env.
  describe "erro que o Rails já transformou em resposta" do
    def rails_response(error, status:, report: nil)
      lambda do |env|
        env["action_dispatch.exception"] = error
        env["action_dispatch.report_exception"] = report unless report.nil?
        [status, {}, ["página de erro"]]
      end
    end

    it "pega o erro que virou página 500" do
      dispatcher
      app = rails_response(RuntimeError.new("quebrou no controller"), status: 500, report: true)

      status, = described_class.new(app).call(env)

      expect(status).to eq(500)
      expect(dispatcher.errors.first[:exception_class]).to eq("RuntimeError")
      expect(dispatcher.errors.first[:message]).to eq("quebrou no controller")
    end

    # Registro inexistente vira 404: o Rails decide não reportar, e o agente segue a decisão.
    it "não reporta o que o Rails trata como resposta" do
      dispatcher
      app = rails_response(KeyError.new("não achei"), status: 404, report: false)

      described_class.new(app).call(env)

      expect(dispatcher.errors).to be_empty
      expect(dispatcher.traces.first[:http_status]).to eq(404)
    end

    it "em Rails sem a decisão no env, reporta só o que deu 5xx" do
      dispatcher

      described_class.new(rails_response(RuntimeError.new("antigo"), status: 500)).call(env)
      described_class.new(rails_response(KeyError.new("antigo"), status: 404)).call(env)

      expect(dispatcher.errors.map { |error| error[:exception_class] }).to eq(["RuntimeError"])
    end
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
