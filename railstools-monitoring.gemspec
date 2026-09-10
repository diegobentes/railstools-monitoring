# frozen_string_literal: true

require_relative "lib/railstools/monitoring/version"

Gem::Specification.new do |spec|
  spec.name = "railstools-monitoring"
  spec.version = Railstools::Monitoring::VERSION
  spec.authors = ["Diego Bentes"]
  spec.email = ["diegopbentes@gmail.com"]

  spec.summary = "Agente do Monitoring: erros, desempenho, tempo de fila, logs e métricas de apps Ruby"
  spec.description = <<~TEXTO
    Instrumenta uma aplicação Ruby (Rails, Sinatra, job em fila, tarefa de linha de comando) e
    envia erros, tempo de resposta, tempo de fila, consultas, logs, métricas de máquina, deploys e
    avisos de processo para uma instalação do Monitoring.

    Ruby puro, sem extensão nativa e sem dependência fora da biblioteca padrão.
  TEXTO
  spec.homepage = "https://github.com/diegobentes/railstools-monitoring"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.metadata = {
    "source_code_uri" => spec.homepage,
    "changelog_uri" => "#{spec.homepage}/blob/main/CHANGELOG.md",
    "bug_tracker_uri" => "#{spec.homepage}/issues",
    "rubygems_mfa_required" => "true"
  }

  # `.rake` junto: as tarefas do Rails moram em lib/railstools/monitoring/integrations/tasks.rake, e
  # sem esta linha elas simplesmente não iriam no pacote — `rails railstools_monitoring:deploy`
  # falharia só depois de publicado.
  spec.files = Dir[
    "lib/**/*.rb", "lib/**/*.rake", "exe/*", "README.md", "CHANGELOG.md", "LICENSE"
  ]
  spec.bindir = "exe"
  spec.executables = ["railstools-monitoring"]
  spec.require_paths = ["lib"]

  # A `logger` saiu das gems padrão no Ruby 4.0 e virou dependência de verdade. Sem declarar aqui,
  # a gem quebra no `require` em Ruby 4 — e funciona em Ruby 3, que é o pior tipo de quebra: só
  # aparece em quem já atualizou.
  spec.add_dependency "logger", "~> 1.6"
end
