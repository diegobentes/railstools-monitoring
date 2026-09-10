# CLAUDE.md

Orientações para quem for mexer nesta gem — humano ou assistente.

## O que é

O agente do Monitoring: instrumenta uma aplicação Ruby e manda telemetria para uma instalação do
[monitoring](https://github.com/diegobentes/monitoring). Ruby puro, sem extensão nativa, sem exigir
Rails.

## Comandos

```bash
bundle install
bundle exec rspec          # a suíte (50 exemplos, sem rede — WebMock + despachante falso)
bundle exec rubocop
```

## As três promessas (e por que quase todo `rescue` largo existe)

1. **Não derrubar o app de quem instalou.** Todo caminho para rede, relógio ou `/proc` está dentro
   de `rescue`. Um erro nosso vira `Monitoring.internal_error`, que só escreve no log. **Não há
   `raise` fora da configuração**, e isso é regra, não estilo.
2. **Não segurar a requisição.** Nada vai para a rede dentro do ciclo da requisição: só para a fila
   do `Dispatcher`. A fila tem teto e descarta o dado NOVO quando enche.
3. **Medir tudo, guardar pouco.** `Sampler` decide de quais transações a amostra completa vai junto.

## Mapa

| Onde | O quê |
|---|---|
| `config.rb` | opções, variáveis de ambiente, listas de ignorar e de filtrar |
| `transaction.rb` | a transação em andamento, os eventos e o payload |
| `span.rb` | um evento na cascata |
| `sampler.rb` | de quais transações guardar amostra |
| `dispatcher.rb` | a fila em memória, a thread de envio, o fork e o `at_exit` |
| `transmitter.rb` | o HTTP, com gzip e uma retentativa |
| `rack/instrumentation_middleware.rb` | a requisição web, incluindo o tempo de fila |
| `hooks/` | `ActiveSupport::Notifications`, Active Job e Sidekiq |
| `probes/` | máquina (`/proc`), Ruby (`GC.stat`) e Puma |
| `check_in.rb`, `marker.rb`, `logger.rb` | processo, deploy e log |
| `cli/` | `install`, `diagnose`, `demo` |

## Coisas que não podem ser esquecidas

- **A transação vive em variável de FIBRA (`Fiber[]`), não de thread.** Em servidor com fibras, duas
  fibras da mesma thread são duas requisições — e guardar na thread misturaria as duas, fazendo uma
  consulta aparecer na cascata da requisição errada.
- **O despachante se reinicia depois de `fork`.** Puma, Unicorn e Resque forkam depois do boot e a
  thread não sobrevive; sem isso, o processo filho enche a fila e nunca envia nada.
- **Duração sai do relógio monotônico.** O de parede anda para trás (NTP, horário de verão) e
  produz duração negativa.
- **Nada de Active Support.** `String#first`, `camelize`, `try`, `blank?` e amigos não existem em app
  sem Rails — e a quebra só apareceria em quem não tem Rails, que é justamente quem não vai reportar.
  Já aconteceu com `String#first`; a suíte roda sem Rails carregado para pegar isso.
- **A `logger` não é mais gem padrão no Ruby 4.0.** Está declarada no gemspec. Tirar de lá quebra em
  Ruby 4 e continua passando em Ruby 3.
- **`Marker#deliver`, não `send`.** `send` é método do Object.
- **`Exception`, não `StandardError`, ao capturar erro de requisição e de transação**: um
  `SignalException` no meio de uma requisição é exatamente o que se quer saber.
- **O teto de spans** (`Transaction::MAX_SPANS`) existe para o caso patológico — a requisição com
  dezenas de milhares de consultas, que é o próprio N+1 que se quer flagrar.

## Protocolo

O formato do que sai daqui é o mesmo documentado em
[`docs/api.md`](https://github.com/diegobentes/monitoring/blob/main/docs/api.md) do servidor. Mudar
um nome de campo aqui exige mudar lá — o servidor lê com tolerância (campo ausente reprova a linha,
não o lote), mas campo renomeado vira dado que some sem erro nenhum.
