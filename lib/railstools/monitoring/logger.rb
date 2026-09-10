# frozen_string_literal: true

require "logger"

module Railstools
  module Monitoring
    # Um `Logger` que manda cada linha para o Monitoring **além** de escrever onde já escrevia.
    #
    # Entra por `broadcast_to` (Rails 7.1+) ou envolvendo o logger existente. Nunca substitui: log é
    # a última coisa que alguém quer perder, e um agente no meio do caminho que engula a saída seria
    # exatamente isso.
    class Logger < ::Logger
      SEVERITIES = {
        ::Logger::DEBUG => "debug", ::Logger::INFO => "info", ::Logger::WARN => "warn",
        ::Logger::ERROR => "error", ::Logger::FATAL => "fatal", ::Logger::UNKNOWN => "unknown"
      }.freeze

      def initialize(group: "rails", level: ::Logger::INFO)
        # Escreve em lugar nenhum: quem escreve no arquivo é o logger original. Este só encaminha.
        super(nil)
        @group = group
        self.level = level
      end

      def add(severity, message = nil, progname = nil)
        severity ||= ::Logger::UNKNOWN
        return true if severity < level

        text = message || (block_given? ? yield : progname)
        forward(severity, text)
        true
      rescue StandardError
        true
      end

      private

      def forward(severity, text)
        return if text.nil?
        return unless Monitoring.active?

        Monitoring.dispatcher.push(:logs, {
          message: SampleData.truncate(text.to_s),
          severity: SEVERITIES.fetch(severity, "info"),
          group: @group,
          hostname: Monitoring.config.hostname,
          revision: Monitoring.config.revision,
          trace_token: Transaction.current&.token,
          occurred_at: Time.now.utc.iso8601(3)
        }.compact)
      end
    end
  end
end
