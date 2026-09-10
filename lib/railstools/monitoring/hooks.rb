# frozen_string_literal: true

require "railstools/monitoring/hooks/active_support_notifications"
require "railstools/monitoring/hooks/active_job"
require "railstools/monitoring/hooks/sidekiq"

module Railstools
  module Monitoring
    # Onde o agente se pendura no que já existe.
    #
    # Cada gancho verifica se a biblioteca dele está carregada antes de instalar, e nenhum estoura
    # se ela não estiver. É isso que permite a mesma gem servir a um Rails completo e a um script
    # que só usa `Net::HTTP`.
    module Hooks
      ALL = [Hooks::ActiveSupportNotifications, Hooks::ActiveJob, Hooks::Sidekiq].freeze

      module_function

      def install
        ALL.each do |hook|
          next unless hook.installable?
          next if hook.installed?

          hook.install
        rescue StandardError => e
          Monitoring.internal_error("não consegui instalar o gancho #{hook.name}", e)
        end
      end
    end
  end
end
