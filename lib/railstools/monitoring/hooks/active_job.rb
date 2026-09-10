# frozen_string_literal: true

module Railstools
  module Monitoring
    module Hooks
      # Jobs do Active Job: cada execução vira uma transação no namespace `background`.
      #
      # O **tempo de fila** aqui não vem de cabeçalho nenhum (não há requisição): é a diferença entre
      # `enqueued_at` e o instante em que a execução começou. É o número que diz que a fila está
      # atrasada mesmo com cada job rodando rápido.
      module ActiveJob
        module_function

        def installable? = defined?(::ActiveJob::Base)
        def installed? = @installed == true
        def name = "ActiveJob"

        def install
          ::ActiveJob::Base.include(Extension)
          @installed = true
        end

        module Extension
          def self.included(base)
            base.around_perform do |job, block|
              action = job.class.name

              if Monitoring.config.ignore_action?(action)
                block.call
              else
                Transaction.wrap(action: action, namespace: "background") do |transaction|
                  transaction.queue_time_ms = Extension.queue_time_for(job)
                  transaction.tags["queue"] = job.queue_name.to_s
                  transaction.tags["job_id"] = job.job_id.to_s
                  if job.respond_to?(:executions)
                    transaction.tags["executions"] =
                      job.executions.to_s
                  end
                  transaction.allocations_before = GC.stat(:total_allocated_objects)
                  block.call
                end
              end
            end
          end

          def self.queue_time_for(job)
            enqueued_at = job.respond_to?(:enqueued_at) ? job.enqueued_at : nil
            return nil if enqueued_at.nil?

            enqueued_at = Time.parse(enqueued_at.to_s) if enqueued_at.is_a?(String)
            ((Time.now - enqueued_at) * 1_000).round(3).clamp(0, 86_400_000)
          rescue StandardError
            nil
          end
        end
      end
    end
  end
end
