# frozen_string_literal: true

module Railstools
  module Monitoring
    # O marcador de deploy.
    #
    # Enviado NA HORA, e não pela fila: quem chama isto é a tarefa de deploy, e o processo termina
    # em seguida — pela fila, o marcador iria embora junto com o processo.
    class Marker
      def self.deploy(revision: nil, user: nil, description: nil, config: Monitoring.config)
        new(config).deliver(kind: "deploy", revision: revision || config.revision, user: user,
                            description: description)
      end

      def self.custom(description:, user: nil, config: Monitoring.config)
        new(config).deliver(kind: "custom", revision: nil, user: user, description: description)
      end

      def initialize(config)
        @config = config
      end

      # `deliver`, e não `send`: `send` é método do Object, e redefinir aqui quebraria envio
      # dinâmico neste objeto.
      def deliver(kind:, revision:, user:, description:)
        return false unless @config.valid?

        marker = { kind: kind, revision: revision, user: user, description: description }.compact
        result = Transmitter.new(@config).post("markers", { marker: marker })

        result.ok?
      end
    end
  end
end
