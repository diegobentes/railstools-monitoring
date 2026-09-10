# frozen_string_literal: true

require "securerandom"
require "socket"
require "json"

require "railstools/monitoring/version"
require "railstools/monitoring/config"
require "railstools/monitoring/system"
require "railstools/monitoring/sample_data"
require "railstools/monitoring/span"
require "railstools/monitoring/transaction"
require "railstools/monitoring/sampler"
require "railstools/monitoring/transmitter"
require "railstools/monitoring/dispatcher"
require "railstools/monitoring/marker"
require "railstools/monitoring/check_in"
require "railstools/monitoring/logger"
require "railstools/monitoring/probes"
require "railstools/monitoring/hooks"
# O middleware é Rack puro: serve a Sinatra, Roda, Hanami e a qualquer app Rack, não só Rails. Por
# isso é carregado aqui, e não junto do Railtie.
require "railstools/monitoring/rack/instrumentation_middleware"
require "railstools/monitoring/helpers/instrumentation"
require "railstools/monitoring/helpers/metrics"

module Railstools
  # O agente do Monitoring.
  #
  # Três compromissos guiam este código, e explicam quase toda decisão estranha que houver nele:
  #
  # 1. **Nunca derrubar o app de quem instalou.** Todo caminho que sai daqui para a rede, para o
  #    relógio ou para o `/proc` está dentro de `rescue StandardError`. Um erro nosso vira uma linha
  #    de log e nada mais. É por isso que não há `raise` em lugar nenhum fora da configuração.
  # 2. **Nunca segurar a requisição.** Nada é enviado dentro do ciclo da requisição: tudo vai para
  #    uma fila em memória e sai numa thread própria. Se a fila encher, o dado NOVO é descartado —
  #    monitoramento que consome a memória do app é pior que monitoramento nenhum.
  # 3. **Medir tudo, guardar pouco.** Toda transação vira métrica; só uma fração vira amostra
  #    completa (as lentas, as com erro e uma porcentagem do resto).
  module Monitoring
    class << self
      include Helpers::Instrumentation
      include Helpers::Metrics

      attr_writer :config

      def config
        @config ||= Config.new
      end

      def configure
        yield(config) if block_given?
        config
      end

      # Liga o agente. Chamado pelo Railtie depois da inicialização, ou à mão em app sem Rails.
      def start
        return false unless config.valid?
        return false if active?

        dispatcher.start
        Probes.start(dispatcher, config)
        Hooks.install
        @active = true
      rescue StandardError => e
        internal_error("não consegui iniciar", e)
        false
      end

      def stop
        Probes.stop
        dispatcher.stop
        @active = false
      end

      def active? = @active == true

      def dispatcher
        @dispatcher ||= Dispatcher.new(config)
      end

      # Manda o que estiver na fila agora. Usado no `at_exit`, em tarefa de linha de comando e nos
      # testes de quem instalou.
      def flush = dispatcher.flush

      def logger
        @logger ||= config.logger
      end

      # Erro NOSSO, do agente. Vai para o log do app com prefixo, e nunca sobe.
      def internal_error(message, error = nil)
        detail = error ? " #{error.class}: #{error.message}" : ""
        logger&.warn("[monitoring] #{message}#{detail}")
        nil
      end

      # Só para teste: zera o estado do módulo.
      def reset!
        @dispatcher&.stop
        @dispatcher = nil
        @config = nil
        @logger = nil
        @active = false
        Transaction.clear!
      end
    end
  end
end

require "railstools/monitoring/integrations/railtie" if defined?(Rails::Railtie)
