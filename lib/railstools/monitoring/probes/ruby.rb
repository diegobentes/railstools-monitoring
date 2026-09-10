# frozen_string_literal: true

module Railstools
  module Monitoring
    module Probes
      # O processo Ruby por dentro: coleta de lixo, heap, threads e memória residente.
      #
      # Tudo sai de `GC.stat`, que o Ruby já mantém — custo perto de zero. `gc_count` e `gc_time` são
      # reportados como DIFERENÇA entre coletas, porque `GC.stat` devolve totais desde o boot, e
      # total desde o boot num gráfico é uma reta crescente que não diz nada.
      class Ruby
        NAMES = {
          heap_slots: "ruby_heap_slots",
          allocated: "ruby_allocated_objects",
          gc_count: "ruby_gc_count",
          gc_time: "ruby_gc_time",
          threads: "ruby_thread_count",
          rss: "ruby_process_rss_bytes"
        }.freeze

        def initialize(config)
          @config = config
          @previous = nil
        end

        def collect
          stats = GC.stat
          tags = { hostname: @config.hostname }
          metrics = [
            gauge(NAMES[:heap_slots], stats[:heap_live_slots], tags),
            gauge(NAMES[:allocated], stats[:total_allocated_objects], tags),
            gauge(NAMES[:threads], Thread.list.count(&:alive?), tags)
          ]

          rss = resident_memory
          metrics << gauge(NAMES[:rss], rss, tags) if rss

          previous = @previous
          @previous = { count: stats[:count], time: GC.total_time }

          if previous
            metrics << counter(NAMES[:gc_count], stats[:count] - previous[:count], tags)
            # `GC.total_time` vem em nanossegundos.
            metrics << gauge(NAMES[:gc_time], (GC.total_time - previous[:time]) / 1_000_000.0, tags)
          end

          metrics.compact
        end

        private

        def gauge(name, value, tags)
          { name: name, kind: "gauge", value: value.to_f, tags: tags }
        end

        def counter(name, value, tags)
          { name: name, kind: "counter", value: value.to_f, tags: tags }
        end

        # Memória residente do processo. `/proc/self/statm` dá em páginas.
        def resident_memory
          pages = File.read("/proc/self/statm").split[1].to_i
          pages * 4096
        rescue StandardError
          nil
        end
      end
    end
  end
end
