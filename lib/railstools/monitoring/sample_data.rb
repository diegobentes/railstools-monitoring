# frozen_string_literal: true

module Railstools
  module Monitoring
    # Prepara o que vai junto da amostra: parâmetros, etiquetas, dados próprios.
    #
    # Filtra segredo e corta tamanho ANTES de sair do processo. O servidor filtra de novo, mas o
    # segredo não pode nem viajar — se vazar na rede ou no log de um proxy pelo caminho, o estrago
    # já está feito.
    module SampleData
      MAX_STRING = 2_000
      MAX_DEPTH = 5
      MAX_KEYS = 60
      MAX_ITEMS = 60
      MASK = "[FILTRADO]"

      module_function

      def sanitize(value, filters: Monitoring.config.filter_parameters, depth: 0)
        return MASK if depth > MAX_DEPTH

        case value
        when ::Hash then sanitize_hash(value, filters, depth)
        when ::Array then value.first(MAX_ITEMS).map do |item|
          sanitize(item, filters: filters, depth: depth + 1)
        end
        when ::String then truncate(value)
        when ::Symbol then value.to_s
        when Numeric, TrueClass, FalseClass, NilClass then value
        when ::Time, ::DateTime then value.iso8601
        else truncate(value.to_s)
        end
      end

      def sanitize_hash(hash, filters, depth)
        hash.first(MAX_KEYS).to_h do |key, value|
          [key.to_s,
           filtered?(key, filters) ? MASK : sanitize(value, filters: filters, depth: depth + 1)]
        end
      end

      def filtered?(key, filters)
        name = key.to_s.downcase

        Array(filters).any? { |filter| name.include?(filter.to_s.downcase) }
      end

      def truncate(text)
        text = text.to_s
        unless text.valid_encoding?
          text = text.encode("UTF-8", invalid: :replace, undef: :replace,
                                      replace: "")
        end
        text.length > MAX_STRING ? "#{text[0, MAX_STRING]}…" : text
      end

      # O ambiente da requisição, só com o que ajuda a investigar. O `env` do Rack inteiro traz
      # objeto de conexão, corpo da requisição e a sessão — nada disso pode sair daqui.
      def request_environment(env)
        return {} unless env.is_a?(::Hash)

        {
          "REQUEST_METHOD" => env["REQUEST_METHOD"],
          "PATH_INFO" => env["PATH_INFO"],
          "QUERY_STRING" => truncate(env["QUERY_STRING"].to_s),
          "HTTP_USER_AGENT" => env["HTTP_USER_AGENT"],
          "HTTP_REFERER" => env["HTTP_REFERER"],
          "REMOTE_ADDR" => env["HTTP_X_FORWARDED_FOR"] || env["REMOTE_ADDR"],
          "SERVER_NAME" => env["SERVER_NAME"]
        }.compact
      end
    end
  end
end
