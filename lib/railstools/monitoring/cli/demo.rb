# frozen_string_literal: true

module Railstools
  module Monitoring
    module CLI
      # Manda uma transação, um erro, uma métrica e uma linha de log de exemplo.
      #
      # É o "funciona?" que não depende de esperar tráfego real chegar — e é o que se roda logo
      # depois de instalar, antes de ir dormir achando que ficou configurado.
      module Demo
        module_function

        def run
          unless Monitoring.config.valid?
            puts "Configuração incompleta:"
            Monitoring.config.problems.each { |problem| puts "  - #{problem}" }
            return false
          end

          Monitoring.start

          Monitoring.monitor("Demonstracao#exemplo", namespace: "background") do |transaction|
            transaction.tags["origem"] = "railstools-monitoring:demo"

            Monitoring.instrument("consulta.exemplo", group: "active_record",
                                                      body: "SELECT * FROM pedidos WHERE id = $1") do
              sleep(0.05)
            end

            Monitoring.instrument("chamada.externa", group: "net_http",
                                                     body: "GET api.exemplo.com/v1") do
              sleep(0.12)
            end

            begin
              raise ArgumentError, "erro de exemplo mandado por railstools-monitoring:demo"
            rescue ArgumentError => e
              transaction.record_error(e)
            end
          end

          Monitoring.gauge("exemplo_de_metrica", 42, tags: { origem: "demo" })
          Monitoring.log("linha de log de exemplo", severity: :info, group: "demo")
          Monitoring.flush

          puts "Mandei: uma transação com dois eventos, um erro, uma métrica e uma linha de log."
          puts "Abra o app #{Monitoring.config.app_name} no Monitoring — deve aparecer em segundos."
          true
        end
      end
    end
  end
end
