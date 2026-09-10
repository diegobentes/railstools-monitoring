# frozen_string_literal: true

module Railstools
  module Monitoring
    module Probes
      # CPU, memória, swap, disco e carga, lidos do `/proc`.
      #
      # Sem gem de sistema operacional de propósito: `/proc` é arquivo de texto, e ler arquivo de
      # texto não traz dependência nativa nem quebra em atualização de kernel. Fora do Linux, este
      # coletor não é sequer construído (`System.linux?`).
      #
      # A CPU é a única que exige estado: `/proc/stat` traz TOTAIS desde o boot, e o que interessa é
      # a diferença entre duas leituras. Por isso a primeira coleta não reporta CPU — ela só guarda
      # a referência.
      class Host
        NAMES = {
          cpu: "host_cpu_percent",
          memory: "host_memory_percent",
          memory_used: "host_memory_used_bytes",
          memory_total: "host_memory_total_bytes",
          swap: "host_swap_percent",
          disk: "host_disk_percent",
          load: "host_load_average"
        }.freeze

        def initialize(config)
          @config = config
          @previous_cpu = nil
        end

        def collect
          tags = { hostname: @config.hostname }

          [cpu(tags), memory(tags), swap(tags), disk(tags), load(tags)].compact.flatten
        end

        private

        def gauge(name, value, tags)
          { name: name, kind: "gauge", value: value.round(3), tags: tags }
        end

        # Percentual por estado (user, system, iowait, idle...). A tela soma tudo menos `idle`
        # para dizer "ocupado" — somar todos daria 100% sempre.
        def cpu(tags)
          fields = File.read("/proc/stat").lines.first.split[1..].map(&:to_i)
          user, nice, system, idle, iowait, irq, softirq, steal = fields
          current = { user: user + nice, system: system + irq.to_i + softirq.to_i,
                      iowait: iowait.to_i, steal: steal.to_i, idle: idle }

          previous = @previous_cpu
          @previous_cpu = current
          return nil if previous.nil?

          deltas = current.to_h { |key, value| [key, value - previous[key]] }
          total = deltas.values.sum
          return nil if total <= 0

          deltas.map do |state, value|
            gauge(NAMES[:cpu], value.to_f / total * 100, tags.merge(state: state.to_s))
          end
        rescue StandardError
          nil
        end

        def memory(tags)
          info = meminfo
          total = info["MemTotal"]
          available = info["MemAvailable"] || info["MemFree"]
          return nil if total.nil? || available.nil? || total.zero?

          used = total - available

          [
            gauge(NAMES[:memory], used.to_f / total * 100, tags),
            gauge(NAMES[:memory_used], used * 1024, tags),
            gauge(NAMES[:memory_total], total * 1024, tags)
          ]
        rescue StandardError
          nil
        end

        def swap(tags)
          info = meminfo
          total = info["SwapTotal"]
          free = info["SwapFree"]
          return nil if total.nil? || free.nil? || total.zero?

          gauge(NAMES[:swap], (total - free).to_f / total * 100, tags)
        rescue StandardError
          nil
        end

        # `df` em vez de ler `/proc`: o uso de disco depende do ponto de montagem, e reconstruir
        # isso a partir de `/proc/mounts` seria reescrever o `df`.
        def disk(tags)
          `df -P 2>/dev/null`.lines.drop(1).filter_map do |line|
            columns = line.split
            next if columns.size < 6
            next unless columns[0].start_with?("/")

            percent = columns[4].to_i
            gauge(NAMES[:disk], percent, tags.merge(mount: columns[5]))
          end.first(6)
        rescue StandardError
          nil
        end

        def load(tags)
          average = File.read("/proc/loadavg").split.first.to_f
          gauge(NAMES[:load], average, tags)
        rescue StandardError
          nil
        end

        def meminfo
          File.read("/proc/meminfo").lines.to_h do |line|
            name, value = line.split(":")
            [name.to_s.strip, value.to_s.strip.split.first.to_i]
          end
        rescue StandardError
          {}
        end
      end
    end
  end
end
