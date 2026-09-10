# frozen_string_literal: true

module Railstools
  module Monitoring
    module Hooks
      # O gancho principal em Rails: `ActiveSupport::Notifications`.
      #
      # O Rails já instrumenta tudo que interessa (controller, consulta, template, e-mail, cache) e
      # publica cada evento com começo, fim e payload. Assinar isso é como se instrumenta um app
      # Rails sem tocar em uma linha do código dele.
      #
      # A assinatura é por `subscribe` com um objeto, e não com bloco, porque o Rails entrega o
      # evento já terminado (`finish!`) e o objeto recebe começo e fim separados — é o que permite
      # calcular a posição do evento na cascata.
      module ActiveSupportNotifications
        # Nome do evento => grupo na cascata. O nome depois do último ponto é a biblioteca que
        # publicou, e é ele que dá o grupo.
        EVENTS = {
          "sql.active_record" => "active_record",
          "instantiation.active_record" => "active_record",
          "render_template.action_view" => "action_view",
          "render_partial.action_view" => "action_view",
          "render_collection.action_view" => "action_view",
          "render_layout.action_view" => "action_view",
          "deliver.action_mailer" => "action_mailer",
          "cache_read.active_support" => "cache",
          "cache_write.active_support" => "cache",
          "cache_delete.active_support" => "cache",
          "cache_fetch_hit.active_support" => "cache",
          "request.net_http" => "net_http",
          "perform.active_job" => "active_job"
        }.freeze

        # Consultas que só fazem barulho: o Rails emite `SCHEMA` para ler metadados e `TRANSACTION`
        # para cada BEGIN/COMMIT. Nenhuma das duas ajuda a entender uma requisição lenta, e juntas
        # são metade dos eventos de um app com muitas transações curtas.
        IGNORED_SQL = %w[SCHEMA TRANSACTION].freeze

        module_function

        def installable? = defined?(::ActiveSupport::Notifications)
        def installed? = @installed == true
        def name = "ActiveSupport::Notifications"

        def install
          EVENTS.each_key do |event|
            ::ActiveSupport::Notifications.subscribe(event) do |name, started, finished, _id, payload|
              record(name, started, finished, payload)
            end
          end

          @installed = true
        end

        def record(name, started, finished, payload)
          transaction = Transaction.current
          return if transaction.nil?
          return if ignored?(name, payload)

          duration_ms = (finished - started) * 1_000.0
          group = EVENTS.fetch(name, "custom")

          transaction.record_event(
            name: name, group: group, duration_ms: duration_ms, body: body_for(name, payload)
          )
        rescue StandardError => e
          Monitoring.internal_error("não consegui registrar o evento #{name}", e)
        end

        # `SCHEMA` e `TRANSACTION` são metade dos eventos de um app com muitas transações curtas, e
        # nenhum dos dois ajuda a entender uma requisição lenta.
        def ignored?(name, payload)
          return false unless name == "sql.active_record"
          return false unless payload.is_a?(::Hash)

          IGNORED_SQL.include?(payload[:name].to_s)
        end

        # O que aparece na linha da cascata. Em consulta é o SQL; em template é o caminho.
        def body_for(name, payload)
          return nil unless payload.is_a?(::Hash)

          case name
          when "sql.active_record" then payload[:sql]
          when /\Arender_/ then payload[:identifier] || payload[:virtual_path]
          when "deliver.action_mailer" then payload[:mailer]
          when /\Acache_/ then payload[:key].to_s
          end
        end
      end
    end
  end
end
