# frozen_string_literal: true

RSpec.describe Railstools::Monitoring::CheckIn do
  let(:dispatcher) { use_fake_dispatcher }

  it "manda começo e fim com o mesmo digest" do
    dispatcher

    described_class.cron("faturamento", schedule: "0 * * * *") { :pronto }

    eventos = dispatcher.check_ins

    expect(eventos.map { |evento| evento[:event] }).to eq(%w[start finish])
    expect(eventos.first[:digest]).to eq(eventos.last[:digest])
    expect(eventos.first[:schedule]).to eq("0 * * * *")
  end

  it "devolve o valor do bloco" do
    dispatcher

    expect(described_class.cron("x") { 42 }).to eq(42)
  end

  # Um cron que estourou no meio é um cron que não rodou: o "terminei" não pode sair, senão o
  # monitor mostra tudo em ordem enquanto o trabalho não aconteceu.
  it "não manda o fim quando o bloco estoura" do
    dispatcher

    expect { described_class.cron("x") { raise "quebrou" } }.to raise_error("quebrou")
    expect(dispatcher.check_ins.map { |evento| evento[:event] }).to eq(%w[start])
  end

  it "pulso é um evento só" do
    dispatcher

    described_class.heartbeat("consumidor", expected_interval_seconds: 60)

    evento = dispatcher.check_ins.first

    expect(evento[:kind]).to eq("heartbeat")
    expect(evento[:expected_interval_seconds]).to eq(60)
  end

  it "com o agente desligado, não estoura nem manda nada" do
    Railstools::Monitoring.reset!

    expect { described_class.heartbeat("x") }.not_to raise_error
  end
end
