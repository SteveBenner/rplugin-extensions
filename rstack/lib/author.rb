#!/usr/bin/env ruby
# SPDX-License-Identifier: MIT

require "json"
require "net/http"
require "securerandom"
require "uri"

module Rplugin
  module Adapters
    module Rstack
      class Author < Rplugin::Ports::Base
        ROUTE = "/api/dispatch/stream"
        DEFAULT_PROFILE = "analysis"
        DEFAULT_TENANT = "rplugin-decide"
        TENANT_PATTERN = /\A[a-z0-9][a-z0-9._-]{0,63}\z/
        CONNECT_TIMEOUT = 3
        READ_TIMEOUT = 120
        DEADLINE_MS = 120_000
        MAX_RETRIES = 2
        BASE_BACKOFF = 0.25
        MAX_BACKOFF = 2.0
        MAX_RETRY_AFTER = 5.0
        BUCKET_LIMIT = 10
        BUCKET_WINDOW = 60.0
        MAX_TOKENS = 4096
        RETRYABLE_STATUS = [429, 500, 502, 503, 504].freeze
        NETWORK_ERRORS = [Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout, IOError, EOFError, Errno::ECONNRESET, Errno::ECONNREFUSED, Errno::EPIPE, Errno::EHOSTUNREACH, SocketError].freeze

        class Retryable < StandardError
          attr_reader :retry_after

          def initialize(message, retry_after = nil)
            super(message)
            @retry_after = retry_after
          end
        end

        class Failed < StandardError; end
        private_constant :Retryable, :Failed

        BUCKET = []
        BUCKET_LOCK = Mutex.new
        private_constant :BUCKET, :BUCKET_LOCK

        def open(context = nil)
          guard!
          { id: SecureRandom.uuid, context: context, messages: [], closed: false }
        end

        def turn(session, text, &on_event)
          guard!
          raise Rplugin::PortUnavailable, "port author is unavailable: session is closed" if session.nil? || session[:closed]

          prompt = text.to_s
          raise ArgumentError, "author turn needs text" if prompt.strip.empty?

          messages = session[:messages] + [{ "role" => "user", "content" => [{ "type" => "text", "text" => prompt }] }]
          result = stream_with_retry(session, messages, &on_event)
          session[:messages] = messages + [{ "role" => "assistant", "content" => [{ "type" => "text", "text" => result[:text] }] }]
          done = result.merge(type: "done", session: session[:id])
          on_event&.call(done)
          done
        end

        def close(session)
          return false if session.nil?

          session[:closed] = true
          session[:messages] = []
          true
        end

        private

        def guard!
          return unless ENV["RPLUGIN_AUTHOR_DISABLED"].to_s == "1"

          raise Rplugin::PortUnavailable, "port author is unavailable: RPLUGIN_AUTHOR_DISABLED=1"
        end

        def stream_with_retry(session, messages, &on_event)
          key = "rplugin-author-#{SecureRandom.uuid}"
          body = JSON.generate(request_body(session, messages))
          attempt = 0
          begin
            attempt += 1
            take_token!
            stream_once(body, key, &on_event)
          rescue Retryable, *NETWORK_ERRORS => e
            raise Rplugin::PortUnavailable, "port author is unavailable: rllm failed after #{attempt} attempts: #{e.message}" if attempt > MAX_RETRIES

            sleep(retry_wait(e, attempt))
            retry
          rescue Failed => e
            raise Rplugin::PortUnavailable, "port author is unavailable: #{e.message}"
          end
        end

        def take_token!
          now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          BUCKET_LOCK.synchronize do
            BUCKET.shift while !BUCKET.empty? && now - BUCKET.first >= BUCKET_WINDOW
            raise Rplugin::PortUnavailable, "port author is unavailable: rate limit of #{BUCKET_LIMIT} requests a minute is spent" if BUCKET.length >= BUCKET_LIMIT

            BUCKET << now
          end
        end

        def retry_wait(error, attempt)
          hinted = error.respond_to?(:retry_after) ? error.retry_after : nil
          return [hinted, MAX_RETRY_AFTER].min * (1.0 + (rand * 0.2)) if hinted

          window = [BASE_BACKOFF * (2**(attempt - 1)), MAX_BACKOFF].min
          window * (0.5 + (rand * 0.5))
        end

        def request_body(session, messages)
          system = system_text(session[:context])
          lead = system ? [{ "role" => "system", "content" => [{ "type" => "text", "text" => system }] }] : []
          {
            selector: { by: "profile", profile: profile },
            request: {
              messages: lead + messages,
              tools: [],
              params: { max_tokens: MAX_TOKENS, temperature: 0.2 }
            }
          }
        end

        def system_text(context)
          return nil unless context.respond_to?(:[]) && !context.is_a?(String)

          value = context[:system] || context["system"]
          value.to_s.empty? ? nil : value.to_s
        rescue StandardError
          nil
        end

        def profile
          value = ENV["RPLUGIN_AUTHOR_PROFILE"].to_s.strip
          value.empty? ? DEFAULT_PROFILE : value
        end

        def tenant
          value = ENV["RPLUGIN_AUTHOR_TENANT"].to_s.strip
          value.match?(TENANT_PATTERN) ? value : DEFAULT_TENANT
        end

        def envelope(key)
          {
            "x-rllm-contract" => "1",
            "x-rllm-tenant" => tenant,
            "x-rllm-qos" => "interactive",
            "x-rllm-priority" => "normal",
            "x-rllm-deadline-ms" => DEADLINE_MS.to_s,
            "x-rllm-on-busy" => "reject",
            "x-rllm-idempotency-key" => key,
            "x-rllm-attempt-id" => SecureRandom.hex(8)
          }
        end

        def stream_once(body, key, &on_event)
          uri = URI.parse("#{base_url}#{ROUTE}")
          http = Net::HTTP.new(uri.host, uri.port)
          http.open_timeout = CONNECT_TIMEOUT
          http.read_timeout = READ_TIMEOUT
          http.write_timeout = READ_TIMEOUT
          request = Net::HTTP::Post.new(uri.request_uri)
          request["content-type"] = "application/json"
          request["accept"] = "text/event-stream"
          envelope(key).each { |name, value| request[name] = value }
          token = ENV["RLLM_AUTH_TOKEN"].to_s.strip
          request["authorization"] = "Bearer #{token}" unless token.empty?
          request.body = body
          state = { text: +"", delivered: false, done: nil }
          http.start do |session|
            session.request(request) do |response|
              refuse(response) unless response.code.to_i == 200
              parser = Parser.new
              response.read_body { |chunk| parser.feed(chunk) { |event| handle(event, state, &on_event) } }
              parser.finish { |event| handle(event, state, &on_event) }
            end
          end
          raise Retryable, "stream ended without a done event" unless state[:done]

          state[:done].merge(text: state[:text])
        rescue Retryable, Failed
          raise
        rescue *NETWORK_ERRORS => e
          raise Failed, "stream interrupted after output: #{e.class}: #{e.message}" if state && state[:delivered]

          raise
        end

        def handle(event, state, &on_event)
          case event["event"]
          when "text_delta"
            text = event["text"].to_s
            state[:text] << text
            state[:delivered] = true
            on_event&.call({ type: "delta", text: text })
          when "done"
            summary = event["summary"].is_a?(Hash) ? event["summary"] : {}
            state[:done] = { slot: summary["slot"], stop_reason: summary["stop_reason"], usage: summary["usage"], duration_ms: summary["duration_ms"] }
          when "error"
            message = "rllm stream error: #{event["error"]}"
            raise Failed, message if state[:delivered] || event["retryable"] != true

            raise Retryable, message
          end
        end

        def refuse(response)
          status = response.code.to_i
          retry_after = retry_after_seconds(response)
          raise Retryable.new("rllm answered #{status}", retry_after) if RETRYABLE_STATUS.include?(status)

          raise Failed, "rllm answered #{status}"
        end

        def retry_after_seconds(response)
          ms = response["x-rllm-retry-after-ms"].to_s
          return ms.to_i / 1000.0 if ms.match?(/\A\d+\z/)

          secs = response["retry-after"].to_s
          secs.match?(/\A\d+\z/) ? secs.to_i.to_f : nil
        end

        def base_url
          explicit = ENV["RLLM_URL"]
          return explicit.chomp("/") unless explicit.nil? || explicit.empty?

          port = ENV["RSTACK_PORT_RLLM"] || ENV["RLLM_PORT"] || "3090"
          "http://127.0.0.1:#{port}"
        end

        class Parser
          def initialize
            @buffer = String.new(encoding: Encoding::BINARY)
            @data = []
          end

          def feed(chunk, &block)
            @buffer << chunk.b
            while (index = @buffer.index("\n"))
              line = @buffer.slice!(0..index).chomp.force_encoding(Encoding::UTF_8)
              consume(line, &block)
            end
          end

          def finish(&block)
            flush(&block)
          end

          private

          def consume(line, &block)
            if line.empty?
              flush(&block)
            elsif line.start_with?("data:")
              @data << line[5..].sub(/\A /, "")
            end
          end

          def flush
            return if @data.empty?

            payload = @data.join("\n")
            @data = []
            parsed = JSON.parse(payload)
            yield parsed if parsed.is_a?(Hash)
          rescue JSON::ParserError
            nil
          end
        end
        private_constant :Parser
      end
    end
  end
end
