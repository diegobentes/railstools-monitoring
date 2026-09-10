# frozen_string_literal: true

module Railstools
  module Monitoring
    module Probes
      # As estatísticas do Puma.
      #
      # `backlog` é a métrica que justifica este coletor: requisição esperando thread livre. Ela
      # aparece ANTES do tempo de resposta subir — quando o backlog passa de zero com frequência, a
      # capacidade acabou, e nenhuma otimização de código conserta isso.
      class Puma
        NAMES = {
          backlog: "puma_backlog",
          running: "puma_running",
          pool_capacity: "puma_pool_capacity",
          max_threads: "puma_max_threads"
        }.freeze

        def initialize(config)
          @config = config
        end

        def collect
          stats = puma_stats
          return [] if stats.nil?

          tags = { hostname: @config.hostname }
          workers = stats["worker_status"]

          # Em modo cluster as estatísticas vêm por worker; somamos, porque o que interessa é a
          # capacidade da MÁQUINA.
          if workers.is_a?(Array)
            summed = workers.filter_map { |worker| worker["last_status"] }
            return [] if summed.empty?

            NAMES.to_h { |key, name| [name, summed.sum { |status| status[key.to_s].to_i }] }
                 .map { |name, value| gauge(name, value, tags) }
          else
            NAMES.filter_map do |key, name|
              value = stats[key.to_s]
              gauge(name, value, tags) if value
            end
          end
        end

        private

        def gauge(name, value, tags)
          { name: name, kind: "gauge", value: value.to_f, tags: tags }
        end

        def puma_stats
          return nil unless defined?(::Puma) && ::Puma.respond_to?(:stats)

          JSON.parse(::Puma.stats)
        rescue StandardError
          nil
        end
      end
    end
  end
end
