# frozen_string_literal: true

require "railstools/monitoring/probes/host"
require "railstools/monitoring/probes/ruby"
require "railstools/monitoring/probes/puma"

module Railstools
  module Monitoring
    # Os coletores periódicos: o que não vem de requisição nenhuma.
    #
    # Uma thread só, acordando a cada `probe_interval`. Cada coletor é isolado: um que estoure (uma
    # máquina sem `/proc`, um Puma numa versão que mudou a API de estatísticas) não pode levar os
    # outros junto.
    module Probes
      module_function

      def start(dispatcher, config)
        return if @thread&.alive?
        return unless config.host_metrics || config.ruby_metrics

        @probes = build(config)
        return if @probes.empty?

        @thread = Thread.new do
          Thread.current.name = "railstools-monitoring-probes"
          Thread.current.abort_on_exception = false

          loop do
            sleep(config.probe_interval)
            collect(dispatcher, config)
          end
        end
      end

      def stop
        @thread&.kill
        @thread = nil
      end

      def running? = @thread&.alive? == true

      def collect(dispatcher, _config)
        @probes.each do |probe|
          probe.collect.each do |metric|
            dispatcher.push(:metrics, metric.merge(occurred_at: Time.now.utc.iso8601(3)))
          end
        rescue StandardError => e
          Monitoring.internal_error("coletor #{probe.class.name} falhou", e)
        end
      end

      def build(config)
        [].tap do |probes|
          probes << Probes::Host.new(config) if config.host_metrics && System.linux?
          probes << Probes::Ruby.new(config) if config.ruby_metrics
          probes << Probes::Puma.new(config) if defined?(::Puma)
        end
      end
    end
  end
end
