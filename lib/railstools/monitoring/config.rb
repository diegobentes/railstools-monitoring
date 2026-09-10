# frozen_string_literal: true

module Railstools
  module Monitoring
    # A configuração do agente.
    #
    # Cada opção existe em três lugares, nesta ordem de precedência: o que foi escrito no
    # `configure`, a variável de ambiente e o padrão. É por isso que a chave pode ficar fora do
    # código-fonte sem obrigar ninguém a escrever `ENV.fetch` no inicializador.
    class Config
      DEFAULTS = {
        active: true,
        endpoint: "http://localhost:3000",
        push_api_key: nil,
        app_name: nil,
        environment: nil,
        revision: nil,
        hostname: nil,
        # Que fração do tráfego guarda AMOSTRA completa. A métrica é sempre de 100% — isto só
        # decide de quais requisições o retrato é guardado.
        sample_rate: 0.1,
        # Toda transação acima disto vira amostra, independentemente do sorteio: quem investiga
        # quer justamente as lentas.
        always_sample_over_ms: 1_000,
        # Segundos entre envios. Abaixo disso o agente conversa demais; acima, o gráfico atrasa.
        flush_interval: 10,
        # Teto da fila em memória. Cheia, o dado NOVO é descartado — o agente não pode crescer sem
        # limite dentro do processo de quem instalou.
        max_queue_size: 5_000,
        # Quantas transações cabem num lote HTTP.
        batch_size: 200,
        open_timeout: 5,
        read_timeout: 10,
        # Manda o log do app junto. Desligado por padrão: é o que mais gera volume, e volume é o
        # que a cobrança mede.
        log_collection: false,
        log_level: :info,
        # Coletor de CPU/memória/disco da máquina, lendo /proc.
        host_metrics: true,
        # Coletor do processo Ruby (coleta de lixo, threads, memória).
        ruby_metrics: true,
        probe_interval: 60,
        # Ações que não viram telemetria — health check é o caso clássico: dezenas de milhares de
        # requisições por dia que ninguém vai olhar e que a cobrança contaria.
        ignore_actions: [],
        ignore_errors: [],
        # Chaves de parâmetro que nunca saem do app. O servidor filtra de novo; isto evita que o
        # segredo chegue a sair pela rede.
        filter_parameters: %w[password passwd secret token api_key access_key authorization
                              cookie session credit_card cvv],
        # Envia parâmetros da requisição junto da amostra.
        send_params: true,
        send_session_data: false,
        send_environment: true,
        debug: false
      }.freeze

      ENV_PREFIX = "RAILSTOOLS_MONITORING_"

      # Nome da variável de ambiente para as opções cujo nome não é o óbvio.
      ENV_ALIASES = {
        push_api_key: "KEY",
        app_name: "APP",
        environment: "ENV"
      }.freeze

      attr_accessor(*DEFAULTS.keys)
      attr_writer :logger

      def initialize(overrides = {})
        DEFAULTS.each { |key, value| public_send(:"#{key}=", value.dup) }
        load_environment
        overrides.each { |key, value| public_send(:"#{key}=", value) }
      end

      def logger
        @logger ||= defined?(::Rails) && ::Rails.respond_to?(:logger) ? ::Rails.logger : default_logger
      end

      # Está pronto para mandar dado? A ausência de chave não é erro: é o estado normal em
      # desenvolvimento e em teste, e o agente simplesmente fica quieto.
      def valid?
        return false unless active
        return false if push_api_key.to_s.empty?
        return false if app_name.to_s.empty?

        true
      end

      def problems
        [].tap do |list|
          list << "a coleta está desligada (config.active = false)" unless active
          list << "falta a chave de envio (config.push_api_key)" if push_api_key.to_s.empty?
          list << "falta o nome do app (config.app_name)" if app_name.to_s.empty?
          unless endpoint.to_s.match?(%r{\Ahttps?://})
            list << "o endereço precisa ser http ou https (config.endpoint)"
          end
        end
      end

      def environment
        @environment ||= detected_environment
      end

      def hostname
        @hostname ||= System.hostname
      end

      def revision
        @revision ||= System.revision
      end

      def push_url(path) = "#{endpoint.to_s.chomp('/')}/api/v1/#{path}"

      def ignore_action?(action)
        return false if action.nil?

        Array(ignore_actions).any? { |pattern| pattern === action } # rubocop:disable Style/CaseEquality
      end

      def ignore_error?(error)
        name = error.is_a?(String) ? error : error.class.name

        Array(ignore_errors).any? { |pattern| pattern === name } # rubocop:disable Style/CaseEquality
      end

      def to_h = DEFAULTS.keys.to_h { |key| [key, public_send(key)] }

      private

      # Lê `RAILSTOOLS_MONITORING_*` do ambiente. Booleano aceita "1", "true", "yes"; número vira
      # número; lista aceita valores separados por vírgula.
      def load_environment
        DEFAULTS.each do |key, default|
          name = "#{ENV_PREFIX}#{ENV_ALIASES.fetch(key, key.to_s.upcase)}"
          raw = ENV.fetch(name, nil)
          next if raw.nil?

          public_send(:"#{key}=", cast(raw, default))
        end
      end

      def cast(raw, default)
        case default
        when true, false then %w[1 true yes on].include?(raw.to_s.downcase)
        when Integer then raw.to_i
        when Float then raw.to_f
        when Array then raw.split(",").map(&:strip)
        when Symbol then raw.to_sym
        else raw
        end
      end

      def detected_environment
        return ::Rails.env.to_s if defined?(::Rails) && ::Rails.respond_to?(:env)

        ENV["RACK_ENV"] || ENV["RAILS_ENV"] || "development"
      end

      def default_logger
        require "logger"
        ::Logger.new($stdout, level: debug ? ::Logger::DEBUG : ::Logger::WARN)
      end
    end
  end
end
