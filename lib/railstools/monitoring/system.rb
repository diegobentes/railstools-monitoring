# frozen_string_literal: true

module Railstools
  module Monitoring
    # O que dá para saber sobre a máquina e o processo sem depender de nada.
    #
    # Tudo aqui pode falhar em contêiner mínimo, em macOS, em máquina sem `/proc` ou sem git — e
    # nenhuma dessas falhas pode chegar ao app de quem instalou. Por isso todo método devolve `nil`
    # em vez de estourar.
    module System
      module_function

      def hostname
        ENV["RAILSTOOLS_MONITORING_HOSTNAME"] ||
          ENV["DYNO"] ||           # Heroku
          ENV["HOSTNAME"] ||       # Kubernetes e Docker costumam preencher
          Socket.gethostname
      rescue StandardError
        "desconhecida"
      end

      # A revisão do código rodando. Ordem: o que a pessoa configurou, o que a plataforma expõe, e
      # só então o git — que em contêiner de produção geralmente nem existe.
      def revision
        ENV["RAILSTOOLS_MONITORING_REVISION"] ||
          ENV["HEROKU_SLUG_COMMIT"] ||
          ENV["GIT_REVISION"] ||
          ENV["SOURCE_VERSION"] ||
          git_revision
      end

      def git_revision
        revision = `git rev-parse HEAD 2>/dev/null`.strip
        revision.empty? ? nil : revision
      rescue StandardError
        nil
      end

      def linux? = RUBY_PLATFORM.include?("linux")

      def container?
        File.exist?("/.dockerenv") || File.read("/proc/1/cgroup").include?("docker")
      rescue StandardError
        false
      end

      def ruby_version = RUBY_VERSION

      def framework
        return "Rails #{::Rails::VERSION::STRING}" if defined?(::Rails::VERSION::STRING)
        return "Sinatra #{::Sinatra::VERSION}" if defined?(::Sinatra::VERSION)

        "Ruby #{RUBY_VERSION}"
      end

      # Segundos desde o boot da máquina, para calcular uso de CPU entre duas leituras.
      def uptime
        File.read("/proc/uptime").split.first.to_f
      rescue StandardError
        nil
      end
    end
  end
end
