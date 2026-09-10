# frozen_string_literal: true

RSpec.describe Railstools::Monitoring::Sampler do
  subject(:sampler) { described_class.new(config) }

  let(:config) { Railstools::Monitoring::Config.new(sample_rate: 0.0, always_sample_over_ms: 1_000) }

  def transaction(duration_ms:, error: nil, status: 200)
    Railstools::Monitoring::Transaction.new(action: "A#b").tap do |item|
      item.instance_variable_set(:@duration_ms, duration_ms)
      item.http_status = status
      item.record_error(error) if error
    end
  end

  it "guarda amostra de tudo que deu erro, mesmo com amostragem em zero" do
    expect(sampler.store?(transaction(duration_ms: 10, error: ArgumentError.new))).to be(true)
    expect(sampler.store?(transaction(duration_ms: 10, status: 500))).to be(true)
  end

  # Sem esta regra, o caso mais comum de investigação — "por que essa requisição levou 4 s?" —
  # dependeria de sorte.
  it "guarda amostra de tudo que passou do limite de lentidão" do
    expect(sampler.store?(transaction(duration_ms: 1_500))).to be(true)
    expect(sampler.store?(transaction(duration_ms: 999))).to be(false)
  end

  it "no resto, obedece à taxa" do
    todas = described_class.new(Railstools::Monitoring::Config.new(sample_rate: 1.0))
    nenhuma = described_class.new(Railstools::Monitoring::Config.new(sample_rate: 0.0))

    expect(todas.store?(transaction(duration_ms: 5))).to be(true)
    expect(nenhuma.store?(transaction(duration_ms: 5))).to be(false)
  end
end
