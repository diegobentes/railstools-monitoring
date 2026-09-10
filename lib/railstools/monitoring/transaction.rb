# frozen_string_literal: true

module Railstools
  module Monitoring
    # Uma transação em andamento: uma requisição, um job, uma tarefa.
    #
    # Vive numa variável de FIBRA (`Fiber[]`), não de thread. Em servidor com fibras (Falcon) ou
    # código com `Enumerator`, duas fibras da mesma thread são duas requisições diferentes — guardar
    # na thread misturaria as duas, e o sintoma seria uma consulta aparecendo na cascata da
    # requisição errada. Em servidor tradicional o comportamento é o mesmo de sempre.
    class Transaction
      KEY = :railstools_monitoring_transaction

      attr_reader :namespace, :spans, :started_at, :token, :correlation_id
      attr_accessor :action, :queue_time_ms, :http_status, :request_method, :path, :error,
                    :params, :session_data, :environment, :tags, :custom_data, :breadcrumbs,
                    :allocations_before, :parent_token

      class << self
        def current = Fiber[KEY]

        def current=(transaction)
          Fiber[KEY] = transaction
        end

        def start(action:, namespace: "web")
          self.current = new(action: action, namespace: namespace)
        end

        def clear! = self.current = nil

        # Roda o bloco dentro de uma transação e a envia no fim, mesmo se der erro.
        def wrap(action:, namespace: "web")
          previous = current
          transaction = start(action: action, namespace: namespace)

          begin
            yield(transaction)
          rescue Exception => e # rubocop:disable Lint/RescueException
            # `Exception` e não `StandardError`: `SignalException` e `SystemExit` também terminam a
            # transação, e perder a telemetria do desligamento é justamente perder a informação de
            # por que ele aconteceu.
            transaction.record_error(e)
            raise
          ensure
            transaction.finish
            self.current = previous
          end
        end
      end

      def initialize(action:, namespace: "web")
        @action = action
        @namespace = namespace
        @token = SecureRandom.uuid
        @correlation_id = nil
        @spans = []
        @open_spans = []
        @tags = {}
        @custom_data = {}
        @breadcrumbs = []
        @started_at = Monitoring.monotonic_ms
        @occurred_at = Time.now
        @finished = false
      end

      def duration_ms = (@duration_ms || (Monitoring.monotonic_ms - @started_at)).round(3)

      def finished? = @finished

      # --- eventos ----------------------------------------------------------------------

      def start_span(name:, group:, body: nil)
        span = Span.new(name: name, group: group, body: body, level: @open_spans.size + 1)
        span.start_offset_ms = Monitoring.monotonic_ms - @started_at
        @open_spans.push(span)
        span
      end

      def finish_span(span = nil, duration_ms: nil)
        span ||= @open_spans.last
        return if span.nil?

        @open_spans.delete(span)
        span.finish(duration_ms: duration_ms)
        add_span(span)
      end

      # Evento já medido por outro (o `ActiveSupport::Notifications` entrega começo e fim juntos).
      def record_event(name:, group:, duration_ms:, body: nil, started_at: nil)
        span = Span.new(name: name, group: group, body: body, level: 1)
        span.start_offset_ms =
          if started_at
            started_at - @started_at
          else
            Monitoring.monotonic_ms - @started_at - duration_ms
          end
        span.start_offset_ms = 0.0 if span.start_offset_ms.negative?
        span.finish(duration_ms: duration_ms)
        add_span(span)
      end

      # O teto existe para o caso patológico: uma requisição com dezenas de milhares de consultas
      # (o próprio N+1 que queremos flagrar) geraria um payload de megabytes. Guardamos as primeiras
      # e contamos o resto — o N+1 continua visível, e a memória não sobe.
      MAX_SPANS = 500

      def add_span(span)
        if @spans.size < MAX_SPANS
          @spans << span
        else
          @dropped_spans = @dropped_spans.to_i + 1
        end

        span
      end

      def dropped_spans = @dropped_spans.to_i

      # --- erro -------------------------------------------------------------------------

      def record_error(exception)
        return if exception.nil? || Monitoring.config.ignore_error?(exception)

        @error = exception
      end

      # --- fim --------------------------------------------------------------------------

      def finish
        return self if @finished

        @duration_ms = Monitoring.monotonic_ms - @started_at
        @open_spans.each { |span| finish_span(span) }
        @finished = true

        Monitoring.dispatcher.record(self) if Monitoring.active?
        self
      rescue StandardError => e
        Monitoring.internal_error("não consegui fechar a transação", e)
        self
      end

      # --- serialização -----------------------------------------------------------------

      def to_payload(store:)
        payload = {
          token: token,
          namespace: namespace,
          action: action,
          occurred_at: @occurred_at.utc.iso8601(3),
          duration_ms: duration_ms,
          queue_time_ms: queue_time_ms&.round(3),
          http_status: http_status,
          request_method: request_method,
          path: path,
          hostname: Monitoring.config.hostname,
          revision: Monitoring.config.revision,
          correlation_id: correlation_id,
          parent_token: parent_token,
          service_name: Monitoring.config.app_name,
          allocations: allocations,
          store: store
        }.compact

        return payload unless store

        payload.merge(
          spans: spans.sort_by(&:start_offset_ms).map(&:to_h),
          sample: sample_payload
        )
      end

      def error_payload
        return nil if error.nil?

        {
          exception_class: error.class.name,
          message: SampleData.truncate(error.message),
          namespace: namespace,
          action: action,
          occurred_at: @occurred_at.utc.iso8601(3),
          hostname: Monitoring.config.hostname,
          revision: Monitoring.config.revision,
          trace_token: token,
          backtrace: Array(error.backtrace).first(100),
          causes: causes_payload,
          sample: sample_payload
        }
      end

      private

      def sample_payload
        {
          params: Monitoring.config.send_params ? SampleData.sanitize(params || {}) : {},
          session_data: Monitoring.config.send_session_data ? SampleData.sanitize(session_data || {}) : {},
          environment: Monitoring.config.send_environment ? (environment || {}) : {},
          tags: SampleData.sanitize(tags),
          custom_data: SampleData.sanitize(custom_data),
          breadcrumbs: breadcrumbs.last(20)
        }
      end

      # As exceções encadeadas. Em Rails, o erro que interessa costuma ser a CAUSA — o que chega
      # ao topo é o embrulho do middleware.
      def causes_payload
        causes = []
        cause = error.cause
        while cause && causes.size < 5
          causes << { class: cause.class.name, message: SampleData.truncate(cause.message) }
          cause = cause.cause
        end
        causes
      end

      # Objetos alocados durante a transação. Sai de graça (`GC.stat` é um contador que o Ruby já
      # mantém) e é o número que aponta requisição que gera lixo demais.
      def allocations
        return nil if allocations_before.nil?

        total = GC.stat(:total_allocated_objects)
        total - allocations_before
      rescue StandardError
        nil
      end
    end
  end
end
