# frozen_string_literal: true

RSpec.describe Railstools::Monitoring::Config do
  it "usa o padrão quando nada foi dito" do
    config = described_class.new

    expect(config.sample_rate).to eq(0.1)
    expect(config.flush_interval).to eq(10)
    expect(config.active).to be(true)
  end

  it "lê variáveis de ambiente, com o tipo do padrão" do
    ENV["RAILSTOOLS_MONITORING_KEY"] = "chave-do-ambiente"
    ENV["RAILSTOOLS_MONITORING_SAMPLE_RATE"] = "0.5"
    ENV["RAILSTOOLS_MONITORING_LOG_COLLECTION"] = "true"
    ENV["RAILSTOOLS_MONITORING_IGNORE_ACTIONS"] = "A#b, C#d"

    config = described_class.new

    expect(config.push_api_key).to eq("chave-do-ambiente")
    expect(config.sample_rate).to eq(0.5)
    expect(config.log_collection).to be(true)
    expect(config.ignore_actions).to eq(["A#b", "C#d"])
  ensure
    %w[KEY SAMPLE_RATE LOG_COLLECTION IGNORE_ACTIONS].each do |name|
      ENV.delete("RAILSTOOLS_MONITORING_#{name}")
    end
  end

  it "o que foi escrito no configure ganha do ambiente" do
    ENV["RAILSTOOLS_MONITORING_KEY"] = "do-ambiente"

    config = described_class.new(push_api_key: "escrita-no-codigo")

    expect(config.push_api_key).to eq("escrita-no-codigo")
  ensure
    ENV.delete("RAILSTOOLS_MONITORING_KEY")
  end

  # Sem chave o agente fica quieto em vez de reclamar: é o estado normal em desenvolvimento e em
  # teste, e um agente que grita no boot de todo mundo vira um agente desinstalado.
  it "sem chave ou sem nome de app, não é válido — e diz por quê" do
    config = described_class.new(push_api_key: nil, app_name: nil)

    expect(config).not_to be_valid
    expect(config.problems).to include(/chave de envio/, /nome do app/)
  end

  it "reconhece ação e erro ignorados por texto e por padrão" do
    config = described_class.new(
      ignore_actions: ["Rails::HealthController#show", /Admin::/],
      ignore_errors: ["ActiveRecord::RecordNotFound"]
    )

    expect(config.ignore_action?("Rails::HealthController#show")).to be(true)
    expect(config.ignore_action?("Admin::UsersController#index")).to be(true)
    expect(config.ignore_action?("PedidosController#create")).to be(false)
    expect(config.ignore_error?(ActiveRecord::RecordNotFound.new)).to be(true) if defined?(ActiveRecord)
    expect(config.ignore_error?("ActiveRecord::RecordNotFound")).to be(true)
  end

  it "monta a URL de envio sem barra dobrada" do
    config = described_class.new(endpoint: "https://monitoring.exemplo/")

    expect(config.push_url("push")).to eq("https://monitoring.exemplo/api/v1/push")
  end
end
