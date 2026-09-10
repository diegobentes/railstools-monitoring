# frozen_string_literal: true

module Railstools
  module Monitoring
    module CLI
      # O relatório de "por que não está chegando nada".
      #
      # Responde, em ordem, as perguntas que se faz nessa hora: a configuração está completa? o
      # servidor responde? a chave é aceita? um lote de teste passa? Cada uma delas é uma linha, e a
      # primeira que falha é a resposta.
      module Diagnose
        module_function

        def run(config: Monitoring.config)
          puts "railstools-monitoring #{VERSION} · ruby #{RUBY_VERSION} · #{System.framework}"
          puts

          report_config(config)
          return false unless config.valid?

          report_auth(config)
        end

        def report_config(config)
          puts "Configuração"
          puts "  app:        #{config.app_name || '(faltando)'}"
          puts "  ambiente:   #{config.environment}"
          puts "  endereço:   #{config.endpoint}"
          chave = config.push_api_key.to_s
          resumo = chave.empty? ? "(faltando)" : "#{chave[0, 6]}… (#{chave.length} caracteres)"
          puts "  chave:      #{resumo}"
          puts "  máquina:    #{config.hostname}"
          puts "  revisão:    #{config.revision || '(desconhecida)'}"
          puts "  amostragem: #{(config.sample_rate * 100).round}% do tráfego"
          puts "  log:        #{config.log_collection ? "ligado (#{config.log_level})" : 'desligado'}"
          puts "  máquina/ruby: #{config.host_metrics ? 'sim' : 'não'}/#{config.ruby_metrics ? 'sim' : 'não'}"
          puts

          problems = config.problems
          if problems.any?
            puts "Impedimentos:"
            problems.each { |problem| puts "  - #{problem}" }
            puts
          end

          problems.empty?
        end

        def report_auth(config)
          require "net/http"
          uri = URI.parse("#{config.endpoint.to_s.chomp('/')}/api/v1/auth")
          request = Net::HTTP::Get.new(uri)
          request["X-Push-Api-Key"] = config.push_api_key

          response = Net::HTTP.start(
            uri.hostname, uri.port, use_ssl: uri.scheme == "https",
                                    open_timeout: config.open_timeout, read_timeout: config.read_timeout
          ) { |http| http.request(request) }

          case response.code.to_i
          when 200
            body = JSON.parse(response.body)
            puts "Conexão: ok — #{body['app']} (#{body['environment']}) na conta #{body['account']}"
            true
          when 401
            puts "Conexão: o servidor respondeu, mas RECUSOU a chave."
            puts "  Confira se a chave é a do app certo (cada app tem a sua) e se ele não foi arquivado."
            false
          else
            puts "Conexão: o servidor respondeu HTTP #{response.code}."
            puts "  #{response.body.to_s[0, 200]}"
            false
          end
        rescue StandardError => e
          puts "Conexão: não consegui falar com #{config.endpoint}"
          puts "  #{e.class}: #{e.message}"
          puts "  Confira o endereço, o DNS e se a rede do contêiner alcança esse host."
          false
        end
      end
    end
  end
end
