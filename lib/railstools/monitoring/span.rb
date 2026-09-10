# frozen_string_literal: true

module Railstools
  module Monitoring
    # Um evento dentro de uma transação: uma consulta, a renderização de um template, uma chamada
    # HTTP. O tempo é medido no relógio MONOTÔNICO — o relógio de parede pode andar para trás
    # (NTP, horário de verão) e produzir duração negativa.
    class Span
      attr_reader :name, :group, :level, :body
      attr_accessor :duration_ms, :start_offset_ms

      def initialize(name:, group:, level: 1, body: nil, started_at: nil)
        @name = name
        @group = group
        @level = level
        @body = body && SampleData.truncate(body)
        @started_at = started_at || Monitoring.monotonic_ms
        @duration_ms = nil
        @start_offset_ms = 0.0
      end

      def finish(duration_ms: nil)
        @duration_ms = duration_ms || (Monitoring.monotonic_ms - @started_at)
        self
      end

      def finished? = !@duration_ms.nil?

      def to_h
        {
          name: name, group: group, level: level,
          start_offset_ms: start_offset_ms.round(3),
          duration_ms: (duration_ms || 0).round(3),
          count: 1, body: body
        }.compact
      end
    end
  end
end
