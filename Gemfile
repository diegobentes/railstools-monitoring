# frozen_string_literal: true

source "https://rubygems.org"

gemspec

# A `json` presa na série 2.x pelo mesmo motivo do app: a 3.0 aceita opções só como argumentos
# nomeados, e código que passa hash posicional (o Active Support do Rails 8.1, entre outros)
# estoura. A gem em si não depende disso — é a suíte que roda com Rails carregado.
gem "json", "~> 2.15"

gem "rake", "~> 13.0"

group :development, :test do
  gem "rspec", "~> 3.13"
  gem "rubocop", "~> 1.79"
  gem "webmock", "~> 3.25"
end
