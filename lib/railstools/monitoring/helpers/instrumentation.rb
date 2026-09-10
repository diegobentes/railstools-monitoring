# frozen_string_literal: true

module Railstools
  module Monitoring
    module Helpers
      # O que o app de quem instalou chama para instrumentar o próprio código.
      #
      # Tudo aqui funciona **fora** de uma transação: chamar `add_tags` numa tarefa que não é
      # requisição nem job simplesmente não faz nada. É de propósito — código instrumentado não pode
      # quebrar quando roda num console.
      module Instrumentation
        # Mede um trecho e o coloca na cascata da transação atual.
        #
        #   Railstools::Monitoring.instrument("calculo.frete", group: "custom") do
        #     transportadora.cotar(pedido)
        #   end
        def instrument(name, group: "custom", body: nil)
          transaction = Transaction.current
          return yield if transaction.nil?

          span = transaction.start_span(name: name, group: group, body: body)
          begin
            yield
          ensure
            transaction.finish_span(span)
          end
        end

        # Abre uma transação onde não existe uma — tarefa de linha de comando, consumidor de fila
        # próprio, script.
        def monitor(action, namespace: "background", &)
          Transaction.wrap(action: action, namespace: namespace, &)
        end

        # Renomeia a ação da transação atual. Serve para juntar rotas que o roteador separa:
        # `/pedidos/1` e `/pedidos/2` são a mesma ação, e sem isto seriam duas séries.
        def set_action(action)
          Transaction.current&.action = action
        end

        def set_namespace(namespace)
          transaction = Transaction.current
          return if transaction.nil?

          transaction.instance_variable_set(:@namespace, namespace)
        end

        # Etiquetas viajam com a amostra e aparecem no detalhe do erro. Use para o que ajuda a
        # entender O CASO — plano do cliente, versão do app do celular, teste A/B.
        def add_tags(tags = {})
          transaction = Transaction.current
          return if transaction.nil?

          transaction.tags.merge!(tags.transform_keys(&:to_s))
        end

        def add_custom_data(data = {})
          transaction = Transaction.current
          return if transaction.nil?

          transaction.custom_data.merge!(data.transform_keys(&:to_s))
        end

        # Migalha: um passo do caminho até o erro. Aparece em ordem no detalhe da ocorrência.
        def add_breadcrumb(category, action, message: nil, metadata: {})
          transaction = Transaction.current
          return if transaction.nil?

          transaction.breadcrumbs << {
            time: Time.now.utc.iso8601, category: category, action: action,
            message: message, metadata: SampleData.sanitize(metadata)
          }.compact
        end

        # Manda um erro que você tratou — o que não sobe até o middleware.
        def send_error(exception, action: nil, namespace: "background", tags: {})
          return if exception.nil? || config.ignore_error?(exception)

          transaction = Transaction.current

          if transaction
            transaction.tags.merge!(tags.transform_keys(&:to_s))
            transaction.record_error(exception)
            return
          end

          # Sem transação em andamento, o erro vira uma transação de uma linha só: sem isso, erro em
          # `rescue` de tarefa de linha de comando não teria onde ser pendurado.
          monitor(action || "#{exception.class.name} (sem ação)",
                  namespace: namespace) do |new_transaction|
            new_transaction.tags.merge!(tags.transform_keys(&:to_s))
            new_transaction.record_error(exception)
          end
        end

        # Descarta a transação atual. É como se ignora health check e endpoint de métrica.
        def ignore_current_transaction!
          Transaction.clear!
        end

        # Milissegundos do relógio monotônico. Usado por tudo que mede duração aqui — o relógio de
        # parede pode andar para trás (NTP, horário de verão) e produzir duração negativa.
        def monotonic_ms = Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_millisecond)
      end
    end
  end
end
