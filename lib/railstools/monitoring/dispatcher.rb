# frozen_string_literal: true

module Railstools
  module Monitoring
    # A fila em memória e a thread que a esvazia.
    #
    # É o que garante o segundo compromisso do agente: **nada é enviado dentro da requisição**. A
    # requisição só empurra um hash para um array e segue; a rede acontece noutra thread, a cada
    # `flush_interval` segundos.
    #
    # Três detalhes que não são óbvios e que, sem eles, isto quebra em produção:
    #
    # - **A fila tem teto.** Cheia, o dado NOVO é descartado. Um agente que cresce sem limite dentro
    #   do processo derruba o app que ele deveria vigiar — e derruba justamente quando o app já está
    #   em apuros (o servidor de telemetria fora do ar é o caso comum).
    # - **Fork.** Puma, Unicorn e Resque forkam depois do boot, e a thread NÃO sobrevive ao fork: o
    #   filho fica com a fila do pai e sem ninguém para esvaziá-la. O despachante compara o pid a
    #   cada escrita e se reinicia no filho.
    # - **Saída do processo.** Um `at_exit` manda o que sobrou. Sem isso, tarefa de linha de comando
    #   e job curto nunca reportariam nada — terminam antes do primeiro intervalo.
    class Dispatcher
      KINDS = %i[traces errors logs metrics markers check_ins].freeze

      def initialize(config)
        @config = config
        @sampler = Sampler.new(config)
        @transmitter = Transmitter.new(config)
        @mutex = Mutex.new
        @buffer = empty_buffer
        @size = 0
        @dropped = 0
        @pid = Process.pid
        @thread = nil
      end

      def start
        @mutex.synchronize do
          @pid = Process.pid
          spawn_thread
        end
        install_at_exit
        self
      end

      def stop
        thread = @mutex.synchronize { @thread.tap { @thread = nil } }
        thread&.kill
        flush
      end

      def running? = @thread&.alive? == true

      def size = @mutex.synchronize { @size }
      def dropped = @mutex.synchronize { @dropped }

      # --- entrada ----------------------------------------------------------------------

      def record(transaction)
        store = @sampler.store?(transaction)
        push(:traces, transaction.to_payload(store: store))

        error = transaction.error_payload
        push(:errors, error) if error
      rescue StandardError => e
        Monitoring.internal_error("não consegui registrar a transação", e)
      end

      def push(kind, payload)
        return if payload.nil?

        @mutex.synchronize do
          restart_after_fork

          if @size >= @config.max_queue_size
            @dropped += 1
            return false
          end

          @buffer[kind] << payload
          @size += 1
        end

        true
      end

      # --- saída ------------------------------------------------------------------------

      # Manda tudo o que está na fila. Volta o número de itens enviados.
      #
      # Sem parâmetro de prazo: quem limita o tempo de rede é a configuração
      # (`open_timeout`/`read_timeout`), aplicada no `Transmitter`.
      def flush
        batch = @mutex.synchronize do
          current = @buffer
          @buffer = empty_buffer
          sent = @size
          @size = 0
          [current, sent]
        end

        payloads, count = batch
        return 0 if count.zero?

        deliver(payloads)
        count
      rescue StandardError => e
        Monitoring.internal_error("não consegui esvaziar a fila", e)
        0
      end

      private

      def empty_buffer = KINDS.to_h { |kind| [kind, []] }

      def spawn_thread
        return if @thread&.alive?

        @thread = Thread.new do
          Thread.current.name = "railstools-monitoring"
          # `abort_on_exception` desligado: um erro aqui não pode derrubar o processo de quem
          # instalou. O `rescue` de dentro do laço já cuida de manter a thread viva.
          Thread.current.abort_on_exception = false

          loop do
            sleep(@config.flush_interval)
            flush
          rescue StandardError => e
            Monitoring.internal_error("erro no laço de envio", e)
          end
        end
      end

      # Depois de um fork, a thread do pai não existe aqui. Sem isto, o processo filho enche a
      # fila e nunca envia nada — o sintoma é "só uma parte dos workers reporta".
      def restart_after_fork
        return if @pid == Process.pid

        @pid = Process.pid
        @buffer = empty_buffer
        @size = 0
        @thread = nil
        spawn_thread
      end

      def install_at_exit
        return if @at_exit_installed

        @at_exit_installed = true
        at_exit { flush }
      end

      # O lote sai em pedaços para não montar um POST gigante quando a fila acumulou (servidor
      # fora do ar por minutos, e depois volta).
      # Os prazos de rede vêm da configuração (`open_timeout`/`read_timeout`), aplicados no
      # `Transmitter` — por isso não há `timeout` aqui.
      def deliver(payloads)
        traces = payloads[:traces]
        slices = traces.each_slice(@config.batch_size).to_a
        slices = [[]] if slices.empty?

        slices.each_with_index do |slice, index|
          body = { hostname: @config.hostname, revision: @config.revision, agent_version: VERSION,
                   traces: slice }

          # Erros, logs, métricas e marcadores viajam junto do primeiro pedaço.
          if index.zero?
            body[:errors] = payloads[:errors]
            body[:logs] = payloads[:logs]
            body[:metrics] = payloads[:metrics]
            body[:markers] = payloads[:markers]
            body[:check_ins] = payloads[:check_ins]
          end

          body.compact!
          next if body.values_at(:traces, :errors, :logs, :metrics, :markers,
                                 :check_ins).compact.all?(&:empty?)

          @transmitter.push(body)
        end
      end
    end
  end
end
