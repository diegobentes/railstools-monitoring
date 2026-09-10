# frozen_string_literal: true

namespace :railstools_monitoring do
  desc "Escreve config/initializers/railstools_monitoring.rb"
  task :install do
    require "railstools/monitoring/cli/install"
    Railstools::Monitoring::CLI::Install.run(app_name: Rails.application.class.module_parent_name)
  end

  desc "Marca um deploy (REVISION=... USER=... DESCRIPTION=...)"
  task deploy: :environment do
    ok = Railstools::Monitoring::Marker.deploy(
      revision: ENV.fetch("REVISION", nil),
      user: ENV.fetch("USER", nil),
      description: ENV.fetch("DESCRIPTION", nil)
    )

    puts ok ? "Deploy marcado." : "Não consegui marcar o deploy — confira a chave e o endereço."
  end

  desc "Confere a configuração e a conexão com o servidor"
  task diagnose: :environment do
    require "railstools/monitoring/cli/diagnose"
    Railstools::Monitoring::CLI::Diagnose.run
  end

  desc "Manda uma transação, um erro e uma linha de log de exemplo"
  task demo: :environment do
    require "railstools/monitoring/cli/demo"
    Railstools::Monitoring::CLI::Demo.run
  end
end
