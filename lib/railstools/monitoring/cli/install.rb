# frozen_string_literal: true

require "fileutils"

module Railstools
  module Monitoring
    module CLI
      # Escreve `config/initializers/railstools_monitoring.rb`.
      #
      # Nunca sobrescreve: quem já configurou tem coisa escrita ali, e um instalador que apaga
      # configuração é um instalador que ninguém roda duas vezes.
      module Install
        PATH = "config/initializers/railstools_monitoring.rb"

        module_function

        def run(app_name: nil)
          if File.exist?(PATH)
            puts "#{PATH} já existe — não mexi nele."
            return false
          end

          FileUtils.mkdir_p(File.dirname(PATH))
          File.write(PATH, template(app_name || File.basename(Dir.pwd)))

          puts <<~FIM
            Escrevi #{PATH}.

            Falta a chave: pegue em Configuração, na tela do app dentro do Monitoring, e exporte

              #{Config::ENV_PREFIX}KEY=...
              #{Config::ENV_PREFIX}ENDPOINT=https://seu-monitoring

            Depois suba o app e rode `rails railstools_monitoring:diagnose`.
          FIM

          true
        end

        def template(app_name)
          <<~RUBY
            # Agente do Monitoring. Documentação: https://github.com/diegobentes/railstools-monitoring
            Railstools::Monitoring.configure do |config|
              config.app_name = #{app_name.inspect}
              config.environment = Rails.env

              # A chave é secreta: quem a tiver consegue mandar telemetria para este app.
              config.push_api_key = ENV["#{Config::ENV_PREFIX}KEY"]
              config.endpoint = ENV.fetch("#{Config::ENV_PREFIX}ENDPOINT", "http://localhost:3000")

              # Fora de produção, medir costuma só poluir o gráfico.
              config.active = Rails.env.production?

              # Que fração do tráfego guarda AMOSTRA completa. A métrica é sempre de 100%.
              config.sample_rate = 0.1

              # Manda o log do Rails junto. É o que mais gera volume — e volume é o que a cobrança
              # mede —, então comece com o nível em :info ou :warn.
              config.log_collection = false
              config.log_level = :info

              # Ações que não viram telemetria. Health check é o caso clássico.
              config.ignore_actions = [ "Rails::HealthController#show" ]
            end
          RUBY
        end
      end
    end
  end
end
