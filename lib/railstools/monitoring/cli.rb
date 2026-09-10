# frozen_string_literal: true

require "railstools/monitoring"
require "railstools/monitoring/cli/install"
require "railstools/monitoring/cli/diagnose"
require "railstools/monitoring/cli/demo"

module Railstools
  module Monitoring
    # A linha de comando: `railstools-monitoring <comando>`.
    #
    # Existe para o que precisa acontecer ANTES de o app carregar (a instalação) e para o que se faz
    # quando o app não está reportando (o diagnóstico) — exatamente os dois momentos em que rodar
    # uma tarefa do Rails pode não ser possível.
    module CLI
      COMMANDS = {
        "install" => "escreve o inicializador",
        "diagnose" => "confere configuração e conexão",
        "demo" => "manda uma transação, um erro e um log de exemplo",
        "version" => "mostra a versão da gem"
      }.freeze

      module_function

      def run(argv)
        case argv.first
        when "install" then Install.run
        when "diagnose" then Diagnose.run
        when "demo" then Demo.run
        when "version", "-v", "--version" then puts VERSION
        else usage
        end
      end

      def usage
        puts "railstools-monitoring <comando>", ""
        COMMANDS.each { |name, description| puts format("  %-10s %s", name, description) }
        puts "", "A configuração vem do inicializador ou das variáveis #{Config::ENV_PREFIX}*."
      end
    end
  end
end
