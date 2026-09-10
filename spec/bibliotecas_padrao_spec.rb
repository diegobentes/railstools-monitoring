# frozen_string_literal: true

# Quem usa biblioteca padrão traz o próprio `require`.
#
# É uma verificação de CÓDIGO-FONTE, e não de comportamento, porque comportamento não pega: basta
# um arquivo carregado antes ter pedido a biblioteca para a constante existir em toda a suíte,
# esconda-se ou não o esquecimento. O erro só aparece na ordem de carga de quem instalou a gem —
# e aí o `NameError` estoura dentro do app de outra pessoa.
#
# Aconteceu no servidor, com `Net::HTTP`: o Rails não carrega `net/http`, o WebMock carregava em
# teste, e a primeira varredura de uptime em produção morreu com `uninitialized constant`.
# Só o que não vem carregado sozinho num Ruby vazio.
BIBLIOTECAS_PADRAO = {
  "net/http" => /\bNet::HTTP\b/,
  "zlib" => /\bZlib\b/,
  "stringio" => /\bStringIO\b/,
  "socket" => /\bSocket\b/,
  "securerandom" => /\bSecureRandom\b/,
  "json" => /\bJSON\b/
}.freeze

# O arquivo de entrada carrega o que a gem inteira usa; um arquivo que ele já cobre não precisa
# repetir. O que este teste garante é que a biblioteca esteja pedida em ALGUM lugar da cadeia.
ENTRADA_DA_GEM = "lib/railstools/monitoring.rb"

RSpec.describe "requires de biblioteca padrão" do
  it "declara cada biblioteca que usa" do
    raiz = File.expand_path("..", __dir__)
    entrada = File.read(File.join(raiz, ENTRADA_DA_GEM))
    faltando = []

    Dir[File.join(raiz, "lib/**/*.rb")].each do |caminho|
      fonte = File.read(caminho)
      relativo = caminho.delete_prefix("#{raiz}/")

      BIBLIOTECAS_PADRAO.each do |biblioteca, uso|
        # Menção em comentário não conta: o que importa é o uso.
        next unless fonte.gsub(/^\s*#.*$/, "").match?(uso)

        pedido = /^require ["']#{Regexp.escape(biblioteca)}["']/
        next if fonte.match?(pedido) || entrada.match?(pedido)

        faltando << "#{relativo} usa #{uso.source} sem require \"#{biblioteca}\""
      end
    end

    expect(faltando).to be_empty, -> { faltando.join("\n") }
  end
end
