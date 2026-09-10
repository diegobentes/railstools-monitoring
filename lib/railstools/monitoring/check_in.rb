# frozen_string_literal: true

module Railstools
  module Monitoring
    # Avisos de processo: "comecei", "terminei", "estou vivo".
    #
    # Serve para o que NÃO avisa quando falha. Um cron que morreu não levanta exceção, não gera
    # requisição e não aparece em lugar nenhum: o único sinal é o silêncio, e é isto que transforma
    # esse silêncio em alarme.
    #
    #   Railstools::Monitoring::CheckIn.cron("faturamento") do
    #     Faturamento.rodar
    #   end
    #
    #   Railstools::Monitoring::CheckIn.heartbeat("consumidor-da-fila")
    module CheckIn
      module_function

      # Envolve a execução: manda "comecei" antes e "terminei" depois, com o mesmo `digest`. O par
      # é o que dá a DURAÇÃO do ciclo sem o agente guardar estado entre as duas chamadas — elas
      # podem até acontecer em processos diferentes.
      #
      # Se o bloco levantar, o "terminei" NÃO é enviado: o ciclo não terminou, e o monitor vai
      # acusar o atraso. É o comportamento certo — um cron que estourou no meio é um cron que não
      # rodou.
      def cron(identifier, schedule: nil, expected_interval_seconds: nil)
        digest = SecureRandom.hex(8)
        send_event(identifier, kind: "cron", event: "start", digest: digest,
                               schedule: schedule, expected_interval_seconds: expected_interval_seconds)

        result = yield

        send_event(identifier, kind: "cron", event: "finish", digest: digest,
                               schedule: schedule, expected_interval_seconds: expected_interval_seconds)
        result
      end

      def heartbeat(identifier, expected_interval_seconds: nil)
        send_event(identifier, kind: "heartbeat", event: "heartbeat",
                               expected_interval_seconds: expected_interval_seconds)
      end

      def send_event(identifier, kind:, event:, digest: nil, schedule: nil,
                     expected_interval_seconds: nil)
        return false unless Monitoring.active?

        Monitoring.dispatcher.push(:check_ins, {
          identifier: identifier.to_s, kind: kind, event: event, digest: digest,
          schedule: schedule, expected_interval_seconds: expected_interval_seconds,
          hostname: Monitoring.config.hostname,
          occurred_at: Time.now.utc.iso8601(3)
        }.compact)
      rescue StandardError => e
        Monitoring.internal_error("não consegui avisar o check-in #{identifier}", e)
        false
      end
    end
  end
end
