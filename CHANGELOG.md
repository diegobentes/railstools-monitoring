# Changelog

## 1.0.1

- Erro de controller em Rails passa a chegar ao Monitoring. O `ActionDispatch::ShowExceptions`
  transforma a exceção em página 500 antes de ela subir até o middleware do agente, que via só o
  status. Agora o agente lê a exceção que o Rails deixa no `env` e segue a mesma decisão de reportar
  que o Rails usa: 404 de registro inexistente continua fora.

## 1.0.0

Primeira versão.

- Middleware Rack que mede a requisição inteira, captura o erro e lê o tempo de fila do
  `X-Request-Start` do proxy.
- Instrumentação automática em Rails por `ActiveSupport::Notifications`: consulta, renderização,
  cache e e-mail entram na cascata da requisição.
- Jobs do Active Job e do Sidekiq, com o tempo de fila calculado a partir de `enqueued_at`.
- Amostragem: métrica de 100% do tráfego, amostra completa das lentas, das que deram erro e da
  fração configurada.
- Coletores periódicos de máquina (`/proc`), do processo Ruby (`GC.stat`) e do Puma.
- Métricas próprias (`gauge`, `increment_counter`, `add_distribution_value`), log estruturado,
  avisos de processo (cron e pulso) e marcador de deploy.
- Coleta do log do Rails por `broadcast_to`, sem substituir o logger do app.
- Linha de comando: `install`, `diagnose`, `demo`, `version`.
