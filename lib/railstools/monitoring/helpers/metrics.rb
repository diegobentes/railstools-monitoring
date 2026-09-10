# frozen_string_literal: true

module Railstools
  module Monitoring
    module Helpers
      # Métricas próprias do app: o que só quem escreveu o sistema sabe que vale medir.
      #
      #   Railstools::Monitoring.gauge("carrinhos_abandonados", Carrinho.abandonados.count)
      #   Railstools::Monitoring.increment_counter("cupom_aplicado", tags: { campanha: "natal" })
      #   Railstools::Monitoring.add_distribution_value("tempo_do_gateway", 412.5)
      #
      # Os três tipos existem porque a pergunta é diferente em cada caso: `gauge` responde "quanto é
      # AGORA", `counter` responde "quantas vezes", e `distribution` responde "como se distribui" —
      # e só esta última ganha percentil na tela.
      module Metrics
        def gauge(name, value, tags: {})
          record_metric(name, value, kind: "gauge", tags: tags)
        end

        def increment_counter(name, value = 1, tags: {})
          record_metric(name, value, kind: "counter", tags: tags)
        end

        def add_distribution_value(name, value, tags: {})
          record_metric(name, value, kind: "measurement", tags: tags)
        end

        # Log estruturado enviado direto, sem passar pelo logger do app.
        def log(message, severity: :info, group: nil, attributes: {})
          return unless active?

          dispatcher.push(:logs, {
            message: SampleData.truncate(message),
            severity: severity.to_s,
            group: group,
            hostname: config.hostname,
            revision: config.revision,
            trace_token: Transaction.current&.token,
            attributes: SampleData.sanitize(attributes),
            occurred_at: Time.now.utc.iso8601(3)
          }.compact)
        end

        private

        def record_metric(name, value, kind:, tags:)
          return unless active?
          return if value.nil?

          dispatcher.push(:metrics, {
                            name: name.to_s, kind: kind, value: value.to_f,
                            tags: tags.transform_keys(&:to_s).transform_values(&:to_s),
                            occurred_at: Time.now.utc.iso8601(3)
                          })
        rescue StandardError => e
          internal_error("não consegui registrar a métrica #{name}", e)
        end
      end
    end
  end
end
