# frozen_string_literal: true

module Railstools
  module Monitoring
    module Integrations
      # A ligação com o Rails: middleware, configuração do `config/railstools_monitoring.yml`,
      # coleta de log e as tarefas de linha de comando.
      class Railtie < ::Rails::Railtie
        config.railstools_monitoring = ActiveSupport::OrderedOptions.new

        initializer "railstools_monitoring.middleware" do |app|
          # No TOPO da pilha: mede o que os outros middlewares gastam e captura o erro que qualquer
          # um deles levante.
          app.middleware.insert_before(0, Railstools::Monitoring::Rack::InstrumentationMiddleware)
        end

        initializer "railstools_monitoring.config" do |app|
          Monitoring.config.app_name ||= app.class.module_parent_name
          Monitoring.config.environment ||= ::Rails.env.to_s
        end

        # `after_initialize` e não `initializer`: aqui os inicializadores do app já rodaram, então o
        # `configure` que a pessoa escreveu em `config/initializers` já valeu.
        config.after_initialize do
          Monitoring.start

          Integrations::Railtie.attach_logger if Monitoring.config.valid? && Monitoring.config.log_collection
        end

        rake_tasks do
          load File.expand_path("tasks.rake", __dir__)
        end

        # Liga a coleta de log ao logger do Rails.
        #
        # Por `broadcast_to`, que ACRESCENTA um destino: o log continua indo para onde ia. Um agente
        # que substitui o logger é um agente que pode engolir a saída do app — e log é a última
        # coisa que alguém quer perder.
        def self.attach_logger
          logger = Monitoring::Logger.new(
            group: "rails",
            level: ::Logger.const_get(Monitoring.config.log_level.to_s.upcase)
          )

          if ::Rails.logger.respond_to?(:broadcast_to)
            ::Rails.logger.broadcast_to(logger)
          else
            Monitoring.internal_error(
              "este Rails não tem `broadcast_to`; a coleta de log ficou desligada"
            )
          end
        rescue StandardError => e
          Monitoring.internal_error("não consegui ligar a coleta de log", e)
        end
      end
    end
  end
end
