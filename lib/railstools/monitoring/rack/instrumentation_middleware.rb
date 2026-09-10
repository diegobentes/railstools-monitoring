# frozen_string_literal: true

module Railstools
  module Monitoring
    module Rack
      # O middleware que envolve cada requisição.
      #
      # Fica no TOPO da pilha (o Railtie o insere em primeiro): assim ele mede o que os outros
      # middlewares gastam e captura o erro que qualquer um deles levante. Embaixo, mediria só o que
      # sobra e perderia erro de autenticação, de CORS, de parser de parâmetro.
      #
      # O **tempo de fila** sai do cabeçalho que o proxy escreve. O Rails não estava lá no instante
      # em que a requisição chegou — sem o proxy contar, esse número não existe.
      class InstrumentationMiddleware
        # nginx escreve `t=1757468400.123`; Heroku e outros escrevem milissegundos direto.
        QUEUE_HEADERS = %w[HTTP_X_REQUEST_START HTTP_X_QUEUE_START].freeze

        def initialize(app)
          @app = app
        end

        def call(env)
          return @app.call(env) unless Monitoring.active?

          transaction = Transaction.start(action: initial_action(env), namespace: "web")
          transaction.queue_time_ms = queue_time(env)
          transaction.request_method = env["REQUEST_METHOD"]
          transaction.path = env["PATH_INFO"]
          transaction.environment = SampleData.request_environment(env)
          transaction.allocations_before = GC.stat(:total_allocated_objects)
          # O `correlation_id` vem do serviço que chamou, quando ele também é instrumentado — é o
          # que costura a cascata entre serviços. Sem cabeçalho, esta requisição é a origem.
          transaction.instance_variable_set(:@correlation_id,
                                            env["HTTP_X_CORRELATION_ID"] || transaction.token)
          transaction.parent_token = env["HTTP_X_PARENT_TOKEN"]

          status, headers, body = @app.call(env)
          transaction.http_status = status
          transaction.record_error(rescued_error(env, status))
          [status, headers, body]
        rescue Exception => e # rubocop:disable Lint/RescueException
          # `Exception`: um `SignalException` no meio de uma requisição também interessa, e ele não
          # é `StandardError`. O erro sobe intacto logo em seguida.
          transaction&.record_error(e)
          transaction&.http_status = 500
          raise
        ensure
          if transaction
            finish(transaction, env)
            Transaction.clear!
          end
        end

        private

        def finish(transaction, env)
          transaction.action = final_action(env) || transaction.action
          transaction.params = request_params(env)

          if Monitoring.config.ignore_action?(transaction.action)
            # Descartada: nem métrica, nem amostra. É como health check some da conta e da tela.
            return
          end

          transaction.finish
        end

        # Antes do roteador, a ação é o caminho. Vira "Controller#ação" no `finish`, quando o
        # Rails já resolveu a rota — usar só o caminho criaria uma série por id na URL.
        def initial_action(env) = "#{env['REQUEST_METHOD']} #{env['PATH_INFO']}"

        def final_action(env)
          params = env["action_dispatch.request.parameters"]
          return nil unless params.is_a?(::Hash)

          controller = params["controller"]
          action = params["action"]
          return nil if controller.nil? || action.nil?

          "#{camelize(controller)}Controller##{action}"
        rescue StandardError
          nil
        end

        # Em Rails, a exceção de um controller NÃO sobe até aqui. O `ActionDispatch::ShowExceptions`,
        # bem mais embaixo na pilha, captura, desenha a página 500 e devolve uma resposta comum: o
        # `rescue` do `call` nunca a vê. O que sobra dela está no `env`: a exceção e, desde o Rails
        # 7.1, a decisão de reportar, que é a mesma que o Rails usa para o `Rails.error`. Ela é
        # falsa para o que o Rails já trata como resposta: 404 de registro inexistente, 422 de
        # token inválido.
        def rescued_error(env, status)
          error = env["action_dispatch.exception"]
          return nil unless error.is_a?(Exception)

          # Rails anterior ao 7.1 não escreve a decisão: vale o status.
          report = env.fetch("action_dispatch.report_exception") { status.to_i >= 500 }
          report ? error : nil
        rescue StandardError
          nil
        end

        def request_params(env)
          params = env["action_dispatch.request.parameters"]
          return {} unless params.is_a?(::Hash)

          # `Hash#except` é do Ruby 3.0 em diante — não é Active Support.
          params.except("controller", "action")
        rescue StandardError
          {}
        end

        # `camelize` sem Active Support: a gem roda em app que não tem Rails carregado.
        def camelize(value)
          value.to_s.split("/").map { |part| part.split("_").map(&:capitalize).join }.join("::")
        end

        def queue_time(env)
          header = QUEUE_HEADERS.filter_map { |name| env[name] }.first
          return nil if header.nil?

          value = header.to_s.sub(/\At=/, "").to_f
          return nil if value <= 0

          # Segundos com fração (nginx) ou milissegundos (Heroku): acima de 10^12 só pode ser
          # milissegundo.
          started = value > 1_000_000_000_000 ? value / 1_000.0 : value
          elapsed = (Time.now.to_f - started) * 1_000

          # Fora dessa faixa é relógio errado entre proxy e app, não fila de verdade. Reportar
          # meia hora de espera por causa de fuso mal configurado é pior que não reportar.
          elapsed.between?(0, 600_000) ? elapsed.round(3) : nil
        rescue StandardError
          nil
        end
      end
    end
  end
end
