# frozen_string_literal: true

require "net/http"
require "uri"
require "zlib"
require "stringio"

module Railstools
  module Monitoring
    # O envio HTTP.
    #
    # Comprime quando vale a pena, tenta de novo uma vez em falha de rede, e **nunca deixa a
    # exceção subir**: quem chama é a thread de despacho, e uma exceção lá mata a thread e o agente
    # inteiro fica mudo — sem que ninguém perceba, que é a pior falha possível num agente.
    class Transmitter
      # Abaixo disto, comprimir custa mais CPU do que economiza rede.
      GZIP_THRESHOLD = 4_096
      RETRIABLE = [
        Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH, Errno::ETIMEDOUT,
        Net::OpenTimeout, Net::ReadTimeout, SocketError, IOError, EOFError
      ].freeze

      Result = Struct.new(:ok, :status, :body, :error, keyword_init: true) do
        def ok? = ok
      end

      def initialize(config)
        @config = config
      end

      def push(payload) = post("push", payload)

      def post(path, payload, retries: 1)
        uri = URI.parse(@config.push_url(path))
        body = JSON.generate(payload)
        request = build_request(uri, body)

        response = Net::HTTP.start(
          uri.hostname, uri.port,
          use_ssl: uri.scheme == "https",
          open_timeout: @config.open_timeout, read_timeout: @config.read_timeout
        ) { |http| http.request(request) }

        result(response)
      rescue *RETRIABLE => e
        return post(path, payload, retries: retries - 1) if retries.positive?

        Monitoring.internal_error("não consegui enviar para #{@config.endpoint}", e)
        Result.new(ok: false, error: e)
      rescue StandardError => e
        Monitoring.internal_error("erro inesperado ao enviar", e)
        Result.new(ok: false, error: e)
      end

      private

      def build_request(uri, body)
        request = Net::HTTP::Post.new(uri)
        request["Content-Type"] = "application/json"
        request["X-Push-Api-Key"] = @config.push_api_key
        request["User-Agent"] = "railstools-monitoring/#{VERSION} ruby/#{RUBY_VERSION}"

        if body.bytesize >= GZIP_THRESHOLD
          request["Content-Encoding"] = "gzip"
          request.body = gzip(body)
        else
          request.body = body
        end

        request
      end

      def gzip(body)
        io = StringIO.new
        io.set_encoding(Encoding::BINARY)
        writer = Zlib::GzipWriter.new(io)
        writer.write(body)
        writer.close
        io.string
      end

      def result(response)
        code = response.code.to_i
        ok = code.between?(200, 299)

        # 402 e 429 são a cobrança falando (assinatura cancelada, volume absurdo). O corpo explica,
        # e ele vai para o log do app — é lá que a pessoa vai procurar quando os gráficos pararem.
        unless ok
          Monitoring.internal_error("o servidor recusou o lote (HTTP #{code}): #{response.body.to_s[0,
                                                                                                    200]}")
        end

        Result.new(ok: ok, status: code, body: response.body)
      end
    end
  end
end
