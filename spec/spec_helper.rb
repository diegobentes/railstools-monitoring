# frozen_string_literal: true

require "railstools-monitoring"
require "webmock/rspec"

RSpec.configure do |config|
  config.expect_with(:rspec) do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end
  config.mock_with(:rspec) do |mocks|
    mocks.verify_partialled_doubles = true if mocks.respond_to?(:verify_partialled_doubles=)
  end
  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand(config.seed)

  # Cada exemplo começa com o agente zerado: o módulo guarda configuração, despachante e thread, e
  # estado vazando entre exemplos é o que faz suíte de agente ficar intermitente.
  config.before do
    Railstools::Monitoring.reset!
    Railstools::Monitoring.configure do |settings|
      settings.app_name = "Teste"
      settings.push_api_key = "chave-de-teste"
      settings.endpoint = "http://monitoring.teste"
      settings.environment = "test"
      settings.hostname = "maquina-de-teste"
      settings.revision = "abc1234"
      settings.host_metrics = false
      settings.ruby_metrics = false
      settings.flush_interval = 60
    end
  end

  config.after { Railstools::Monitoring.reset! }
end

# Um despachante que não fala com a rede: guarda o que receberia. É como quase todo exemplo aqui
# confere o que o agente teria enviado.
class FakeDispatcher
  attr_reader :items

  def initialize
    @items = Hash.new { |hash, key| hash[key] = [] }
  end

  def start = self
  def stop = self
  def flush(**) = @items.values.sum(&:size)

  def push(kind, payload)
    @items[kind] << payload
    true
  end

  def record(transaction)
    store = Railstools::Monitoring::Sampler.new(Railstools::Monitoring.config).store?(transaction)
    push(:traces, transaction.to_payload(store: store))
    error = transaction.error_payload
    push(:errors, error) if error
  end

  def traces = @items[:traces]
  def errors = @items[:errors]
  def logs = @items[:logs]
  def metrics = @items[:metrics]
  def check_ins = @items[:check_ins]
end

module DispatcherHelper
  def use_fake_dispatcher
    fake = FakeDispatcher.new
    Railstools::Monitoring.instance_variable_set(:@dispatcher, fake)
    Railstools::Monitoring.instance_variable_set(:@active, true)
    fake
  end
end

RSpec.configure { |config| config.include(DispatcherHelper) }
