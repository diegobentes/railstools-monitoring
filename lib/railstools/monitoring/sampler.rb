# frozen_string_literal: true

module Railstools
  module Monitoring
    # Decide de quais transações a AMOSTRA completa é guardada.
    #
    # A métrica é sempre de 100% do tráfego — isto só escolhe de quais requisições o retrato (com
    # eventos, parâmetros e etiquetas) vai junto. Três regras, nesta ordem:
    #
    # 1. **Deu erro:** sempre. É a amostra que alguém vai abrir.
    # 2. **Foi lenta:** sempre. Idem.
    # 3. **O resto:** sorteio por `sample_rate`.
    #
    # Sem a regra 2, o caso mais comum de investigação — "por que essa requisição levou 4 s?" —
    # dependeria de sorte: com 10% de amostragem, nove em cada dez requisições lentas não teriam
    # retrato nenhum.
    class Sampler
      def initialize(config)
        @config = config
      end

      def store?(transaction)
        return true if transaction.error
        return true if transaction.http_status.to_i >= 500
        return true if transaction.duration_ms >= @config.always_sample_over_ms.to_f

        rate = @config.sample_rate.to_f
        return true if rate >= 1.0
        return false if rate <= 0.0

        Random.rand < rate
      end
    end
  end
end
