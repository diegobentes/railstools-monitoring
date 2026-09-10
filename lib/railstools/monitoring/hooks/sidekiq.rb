# frozen_string_literal: true

module Railstools
  module Monitoring
    module Hooks
      # Sidekiq puro — o job que não passa pelo Active Job.
      #
      # Entra como middleware de servidor, que é o único lugar onde dá para envolver a execução
      # inteira, inclusive o erro que o Sidekiq captura para reenfileirar.
      module Sidekiq
        module_function

        def installable? = defined?(::Sidekiq) && ::Sidekiq.respond_to?(:configure_server)
        def installed? = @installed == true
        def name = "Sidekiq"

        def install
          ::Sidekiq.configure_server do |config|
            config.server_middleware { |chain| chain.add(Middleware) }
          end

          @installed = true
        end

        class Middleware
          def call(_worker, job, _queue)
            action = job["wrapped"] || job["class"]

            return yield if Monitoring.config.ignore_action?(action)

            Transaction.wrap(action: action.to_s, namespace: "background") do |transaction|
              transaction.queue_time_ms = queue_time_for(job)
              transaction.tags["queue"] = job["queue"].to_s
              transaction.tags["retry_count"] = job["retry_count"].to_s if job["retry_count"]
              transaction.allocations_before = GC.stat(:total_allocated_objects)
              yield
            end
          end

          private

          # `enqueued_at` do Sidekiq é epoch em segundos, com fração.
          def queue_time_for(job)
            enqueued_at = job["enqueued_at"]
            return nil if enqueued_at.nil?

            ((Time.now.to_f - enqueued_at.to_f) * 1_000).round(3).clamp(0, 86_400_000)
          rescue StandardError
            nil
          end
        end
      end
    end
  end
end
