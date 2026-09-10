# frozen_string_literal: true

RSpec.describe "os ajudantes do agente" do
  let(:dispatcher) { use_fake_dispatcher }

  describe "instrument" do
    it "coloca o trecho medido na cascata" do
      dispatcher
      Railstools::Monitoring.config.sample_rate = 1.0

      Railstools::Monitoring.monitor("Tarefa#exemplo") do
        Railstools::Monitoring.instrument("calculo.frete", group: "custom") { sleep(0.01) }
      end

      span = dispatcher.traces.first[:spans].first

      expect(span[:name]).to eq("calculo.frete")
      expect(span[:duration_ms]).to be >= 10
    end

    # Código instrumentado não pode quebrar quando roda num console, onde não há transação.
    it "fora de uma transação, só executa o bloco" do
      expect(Railstools::Monitoring.instrument("x") { 42 }).to eq(42)
    end
  end

  describe "etiquetas e dados próprios" do
    it "viajam com a amostra" do
      dispatcher
      Railstools::Monitoring.config.sample_rate = 1.0

      Railstools::Monitoring.monitor("Tarefa#exemplo") do
        Railstools::Monitoring.add_tags(plano: "pro")
        Railstools::Monitoring.add_custom_data(itens: 3)
        Railstools::Monitoring.add_breadcrumb("cobranca", "tentou", message: "cartão recusado")
      end

      sample = dispatcher.traces.first[:sample]

      expect(sample[:tags]).to eq({ "plano" => "pro" })
      expect(sample[:custom_data]).to eq({ "itens" => 3 })
      expect(sample[:breadcrumbs].first[:action]).to eq("tentou")
    end
  end

  describe "send_error" do
    it "pendura o erro na transação em andamento" do
      dispatcher

      Railstools::Monitoring.monitor("Tarefa#exemplo") do
        Railstools::Monitoring.send_error(ArgumentError.new("tratado"))
      end

      expect(dispatcher.errors.first[:message]).to eq("tratado")
    end

    # Sem transação em andamento, o erro precisa de onde ser pendurado — senão erro em `rescue` de
    # tarefa de linha de comando não chegaria nunca.
    it "sem transação, abre uma de uma linha só" do
      dispatcher

      Railstools::Monitoring.send_error(ArgumentError.new("solto"), action: "Tarefa#solta")

      expect(dispatcher.errors.first[:action]).to eq("Tarefa#solta")
      expect(dispatcher.traces.first[:namespace]).to eq("background")
    end

    it "respeita a lista de erros ignorados" do
      dispatcher
      Railstools::Monitoring.config.ignore_errors = ["ArgumentError"]

      Railstools::Monitoring.send_error(ArgumentError.new("ignorado"))

      expect(dispatcher.errors).to be_empty
    end
  end

  describe "métricas" do
    it "os três tipos chegam com o tipo declarado" do
      dispatcher

      Railstools::Monitoring.gauge("carrinhos", 12, tags: { loja: "matriz" })
      Railstools::Monitoring.increment_counter("cupom")
      Railstools::Monitoring.add_distribution_value("gateway_ms", 412.5)

      expect(dispatcher.metrics.map { |metric| metric[:kind] }).to eq(%w[gauge counter measurement])
      expect(dispatcher.metrics.first[:tags]).to eq({ "loja" => "matriz" })
      expect(dispatcher.metrics.last[:value]).to eq(412.5)
    end

    it "log estruturado leva o rastro da transação junto" do
      dispatcher

      Railstools::Monitoring.monitor("Tarefa#exemplo") do
        Railstools::Monitoring.log("aconteceu", severity: :warn, group: "cobranca")
      end

      linha = dispatcher.logs.first

      expect(linha[:severity]).to eq("warn")
      expect(linha[:trace_token]).not_to be_nil
    end
  end
end
