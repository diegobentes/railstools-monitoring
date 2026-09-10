# railstools-monitoring

O agente do [Monitoring](https://github.com/diegobentes/monitoring): instrumenta uma aplicação Ruby
e envia erros, tempo de resposta, tempo de fila, consultas, logs, métricas de máquina, deploys e
avisos de processo.

Ruby puro — sem extensão nativa, sem dependência fora da biblioteca padrão, sem exigir Rails.

```ruby
# Gemfile
gem "railstools-monitoring"
```

```bash
bundle install
bin/rails railstools_monitoring:install
```

O instalador escreve `config/initializers/railstools_monitoring.rb`. Falta só a chave, que está em
**Configuração**, na tela do app dentro do Monitoring:

```bash
export RAILSTOOLS_MONITORING_KEY=...
export RAILSTOOLS_MONITORING_ENDPOINT=https://seu-monitoring
```

Suba o app e confira:

```bash
bin/rails railstools_monitoring:diagnose   # configuração e conexão
bin/rails railstools_monitoring:demo       # manda uma transação, um erro e um log de exemplo
```

## O que ele mede sozinho

Em Rails, nada precisa ser instrumentado à mão:

| | de onde vem |
|---|---|
| Tempo de resposta, por ação | middleware Rack no topo da pilha |
| Consultas, renderização, cache, e-mail | `ActiveSupport::Notifications` |
| Erros, com backtrace e causas | o mesmo middleware, e `send_error` para o que você tratou |
| Jobs, com tempo de fila | `around_perform` do Active Job e middleware do Sidekiq |
| Tempo de fila da web | cabeçalho `X-Request-Start` do proxy |
| CPU, memória, swap, disco, carga | `/proc`, a cada minuto |
| Coleta de lixo, heap, threads, memória do processo | `GC.stat` |
| Backlog e capacidade do Puma | `Puma.stats` |
| Log do app | opcional, por `broadcast_to` no logger do Rails |

## As três promessas deste agente

**1. Não derrubar o app de quem instalou.** Todo caminho que sai daqui para a rede, para o relógio
ou para o `/proc` está dentro de `rescue`. Um erro nosso vira uma linha no log e nada mais.

**2. Não segurar a requisição.** Nada é enviado dentro do ciclo da requisição: tudo vai para uma
fila em memória e sai numa thread própria. A fila tem teto — cheia, o dado novo é descartado, porque
um agente que cresce sem limite dentro do processo derruba justamente o app que deveria vigiar.

**3. Medir tudo, guardar pouco.** Toda transação vira métrica; só uma fração vira amostra completa —
as lentas, as que deram erro e a porcentagem que você escolher. É o que permite medir 100% do
tráfego sem escrever uma linha por requisição.

## Configuração

```ruby
Railstools::Monitoring.configure do |config|
  config.app_name = "Loja"
  config.environment = Rails.env
  config.push_api_key = ENV["RAILSTOOLS_MONITORING_KEY"]
  config.endpoint = "https://seu-monitoring"

  config.active = Rails.env.production?

  # Amostragem. A MÉTRICA é sempre de 100% do tráfego; isto decide de quais requisições o retrato
  # completo (eventos, parâmetros, etiquetas) vai junto.
  config.sample_rate = 0.1
  config.always_sample_over_ms = 1_000   # toda transação acima disto é guardada

  # Envio
  config.flush_interval = 10             # segundos entre lotes
  config.max_queue_size = 5_000          # teto da fila em memória
  config.batch_size = 200

  # Log do app. É o que mais gera volume — e volume é o que a cobrança mede.
  config.log_collection = false
  config.log_level = :info

  # Coletores periódicos
  config.host_metrics = true
  config.ruby_metrics = true
  config.probe_interval = 60

  # O que não vira telemetria
  config.ignore_actions = [ "Rails::HealthController#show", /Admin::/ ]
  config.ignore_errors = [ "ActiveRecord::RecordNotFound" ]

  # Segredo não sai daqui. O servidor filtra de novo; isto evita que ele chegue a viajar.
  config.filter_parameters += %w[cpf cnpj]
  config.send_params = true
  config.send_session_data = false
end
```

Toda opção também vem do ambiente, com o prefixo `RAILSTOOLS_MONITORING_`
(`KEY`, `ENDPOINT`, `APP`, `ENV` são os atalhos). O que está escrito no `configure` ganha do
ambiente.

## Instrumentar o seu código

```ruby
# Um trecho, na cascata da requisição
Railstools::Monitoring.instrument("cotacao.frete", group: "custom") do
  transportadora.cotar(pedido)
end

# Onde não existe transação (tarefa, script, consumidor próprio)
Railstools::Monitoring.monitor("ImportacaoNoturna") do
  Importacao.rodar
end

# Contexto que ajuda a entender O CASO
Railstools::Monitoring.add_tags(plano: cliente.plano, loja: loja.slug)
Railstools::Monitoring.add_custom_data(itens: pedido.itens.size)
Railstools::Monitoring.add_breadcrumb("cobranca", "tentou", message: "cartão recusado")

# Um erro que você tratou
rescue Stripe::CardError => e
  Railstools::Monitoring.send_error(e, tags: { gateway: "stripe" })
end

# Juntar rotas que o roteador separa
Railstools::Monitoring.set_action("PedidosController#show")
```

## Métricas próprias

```ruby
Railstools::Monitoring.gauge("carrinhos_abandonados", Carrinho.abandonados.count)
Railstools::Monitoring.increment_counter("cupom_aplicado", tags: { campanha: "natal" })
Railstools::Monitoring.add_distribution_value("gateway_ms", duracao)
```

Os três tipos existem porque a pergunta é diferente em cada caso: `gauge` responde "quanto é agora",
`counter` responde "quantas vezes", `distribution` responde "como se distribui" — e só esta última
ganha percentil na tela.

## Processos que precisam avisar que rodaram

Um cron que morreu não levanta exceção, não gera requisição e não aparece em lugar nenhum. O único
sinal é o silêncio:

```ruby
# Em config/schedule.rb, no rake, onde a tarefa roda
Railstools::Monitoring::CheckIn.cron("faturamento", schedule: "0 3 * * *") do
  Faturamento.rodar
end

# Serviço de longa duração
Railstools::Monitoring::CheckIn.heartbeat("consumidor-da-fila", expected_interval_seconds: 60)
```

O par começo/fim compartilha um identificador — é ele que dá a duração do ciclo sem o agente
precisar guardar estado entre as duas chamadas. Se o bloco estourar, o "terminei" não é enviado: um
cron que quebrou no meio é um cron que não rodou.

## Deploy

No fim do seu processo de deploy:

```bash
bin/rails railstools_monitoring:deploy REVISION=$(git rev-parse --short HEAD) USER=$(whoami)
```

É o que põe a linha vertical nos gráficos e permite comparar antes e depois.

## Tempo de fila

O tempo de fila da web é a diferença entre a hora em que o **proxy** recebeu a requisição e a hora
em que o Rails começou a processá-la. O Rails não estava lá no primeiro instante, então quem conta é
o proxy:

```nginx
proxy_set_header X-Request-Start "t=${msec}";
```

```apache
RequestHeader set X-Request-Start "%t"
```

Em job não precisa de nada: o agente compara `enqueued_at` com o instante em que a execução começou.

## Fora do Rails

O middleware é Rack puro:

```ruby
require "railstools-monitoring"

Railstools::Monitoring.configure { |config| config.app_name = "API"; config.push_api_key = ENV["..."] }
Railstools::Monitoring.start

use Railstools::Monitoring::Rack::InstrumentationMiddleware
```

Em script ou tarefa, envolva o trabalho em `monitor` e chame `flush` no fim (o `at_exit` também
cuida disso).

## Linha de comando

```bash
railstools-monitoring install    # escreve o inicializador
railstools-monitoring diagnose   # por que não está chegando nada
railstools-monitoring demo       # manda um exemplo de cada coisa
railstools-monitoring version
```

## Desenvolvimento

```bash
bin/setup        # ou bundle install
bundle exec rspec
bundle exec rubocop
```

A suíte não fala com a rede: usa um despachante falso e o WebMock.

## Licença

MIT.
