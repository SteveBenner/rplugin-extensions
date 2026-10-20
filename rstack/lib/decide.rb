#!/usr/bin/env ruby
# SPDX-License-Identifier: MIT

require "json"
require "net/http"
require "securerandom"
require "uri"

module Rplugin
  module Adapters
    module Rstack
      class Decide < Rplugin::Ports::Base
        PROFILE = "decision"
        QUESTION = "decision"
        CONNECT_TIMEOUT = 3
        DEADLINE_MS = 12_000
        MAX_ATTEMPTS = 2
        BASE_BACKOFF = 0.15
        MAX_BACKOFF = 1.5
        DEFAULT_TENANT = "rplugin-decide"
        TENANT_PATTERN = /\A[a-z0-9][a-z0-9._-]{0,63}\z/
        RETRYABLE_STATUS = [500, 502, 504].freeze
        RETRYABLE_OUTCOMES = %w[in_progress preempted interrupted].freeze
        BUSY_OUTCOMES = %w[capacity_exceeded tenant_quota_exceeded deadline_unachievable queue_expired].freeze
        NETWORK_ERRORS = [Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout, IOError, EOFError, Errno::ECONNRESET, Errno::ECONNREFUSED, Errno::EPIPE, SocketError].freeze
        MAX_CONTEXT_CHARS = 24_000

        class Retryable < StandardError
          attr_reader :retry_after_ms

          def initialize(message, retry_after_ms = nil)
            super(message)
            @retry_after_ms = retry_after_ms
          end
        end

        class Declined < StandardError; end
        private_constant :Retryable, :Declined

        def decide(question:, options:, context:, criteria: nil)
          raise Rplugin::PortUnavailable, "port decide is unavailable: RPLUGIN_DECIDE_DISABLED=1" if ENV["RPLUGIN_DECIDE_DISABLED"].to_s == "1"

          choices = normalize_options(options)
          degrade(:decide, question: question, options: options, context: context, criteria: criteria) do
            started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            body = JSON.generate(request_body(question.to_s, choices, context.to_s, criteria))
            answer = parse(post_with_retry(body), choices)
            answer.merge(provider: "rllm:#{answer.delete(:slot)}", latency_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round)
          end
        end

        private

        def normalize_options(options)
          list = Array(options).map(&:to_s)
          raise ArgumentError, "decide needs at least two distinct options" if list.length < 2 || list.uniq.length != list.length

          list
        end

        def request_body(question, choices, context, criteria)
          described = choices.to_h do |option|
            description = criteria.is_a?(Hash) ? (criteria[option] || criteria[option.to_sym]) : nil
            [option, description.to_s.empty? ? nil : description.to_s]
          end
          {
            selector: { by: "profile", profile: PROFILE },
            request: {
              state: context[0, MAX_CONTEXT_CHARS],
              questions: { QUESTION => { type: "choice", instructions: question, criteria: described } }
            }
          }
        end

        def post_with_retry(body)
          started = monotonic
          key = "rplugin-decide-#{SecureRandom.uuid}"
          attempt = 0
          begin
            attempt += 1
            remaining = DEADLINE_MS - elapsed_ms(started)
            raise Declined, "rllm decide deadline exhausted" if remaining <= 0

            post(body, key: key, remaining_ms: remaining)
          rescue Retryable, *NETWORK_ERRORS => e
            raise Declined, "rllm decide failed after #{attempt} attempts: #{e.message}" if attempt >= MAX_ATTEMPTS

            wait = retry_wait(e, attempt)
            raise Declined, "rllm decide cannot retry within its deadline" if wait * 1000 >= DEADLINE_MS - elapsed_ms(started)

            sleep(wait)
            retry
          end
        end

        def retry_wait(error, attempt)
          ms = error.respond_to?(:retry_after_ms) ? error.retry_after_ms : nil
          return (ms / 1000.0) * (1.0 + (rand * 0.2)) if ms

          rand * [BASE_BACKOFF * (2**(attempt - 1)), MAX_BACKOFF].min
        end

        def monotonic
          Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end

        def elapsed_ms(started)
          ((monotonic - started) * 1000).floor
        end

        def tenant
          value = ENV["RPLUGIN_DECIDE_TENANT"].to_s.strip
          value.match?(TENANT_PATTERN) ? value : DEFAULT_TENANT
        end

        def envelope(key, remaining_ms)
          {
            "x-rllm-contract" => "1",
            "x-rllm-tenant" => tenant,
            "x-rllm-qos" => "interactive",
            "x-rllm-priority" => "normal",
            "x-rllm-deadline-ms" => remaining_ms.to_s,
            "x-rllm-on-busy" => "reject",
            "x-rllm-idempotency-key" => key,
            "x-rllm-attempt-id" => SecureRandom.hex(8)
          }
        end

        def post(body, key:, remaining_ms:)
          uri = URI.parse("#{base_url}/api/decide")
          http = Net::HTTP.new(uri.host, uri.port)
          timeout = [remaining_ms / 1000.0, 1.0].max
          http.open_timeout = CONNECT_TIMEOUT
          http.read_timeout = timeout
          http.write_timeout = timeout
          request = Net::HTTP::Post.new(uri.request_uri)
          request["content-type"] = "application/json"
          request["accept"] = "application/json"
          envelope(key, remaining_ms).each { |name, value| request[name] = value }
          token = ENV["RLLM_AUTH_TOKEN"].to_s.strip
          request["authorization"] = "Bearer #{token}" unless token.empty?
          request.body = body
          response = http.start { |session| session.request(request) }
          status = response.code.to_i
          return response.body.to_s if status == 200

          refuse(status, response)
        end

        def refuse(status, response)
          code, admission = error_details(response.body)
          outcome = (admission["outcome"] || code).to_s
          ms = retry_after_ms(response, admission)
          raise Declined, "rllm is busy (#{outcome})" if BUSY_OUTCOMES.include?(outcome) || status == 429
          raise Declined, "rllm is unavailable (#{outcome.empty? ? status : outcome})" if status == 503
          raise Retryable.new("#{outcome} (http #{status})", ms) if RETRYABLE_OUTCOMES.include?(outcome) || RETRYABLE_STATUS.include?(status)

          raise Declined, "rllm decide answered #{status}"
        end

        def error_details(body)
          err = JSON.parse(body.to_s)["error"]
          return [nil, {}] unless err.is_a?(Hash)

          [err["code"], err["admission"].is_a?(Hash) ? err["admission"] : {}]
        rescue JSON::ParserError
          [nil, {}]
        end

        def retry_after_ms(response, admission)
          header = response["x-rllm-retry-after-ms"].to_s
          return header.to_i if header.match?(/\A\d+\z/)

          body = admission["retry_after_ms"]
          return body.to_i if body.is_a?(Numeric)

          secs = response["retry-after"].to_s
          secs.match?(/\A\d+\z/) ? secs.to_i * 1000 : nil
        end

        def parse(raw, choices)
          data = JSON.parse(raw)
          answer = data.dig("answers", QUESTION)
          choice = answer.is_a?(Hash) ? answer["choice"] : nil
          probability = answer.is_a?(Hash) ? answer.dig("probabilities", choice) : nil
          raise "rllm decide returned no valid choice" unless choices.include?(choice) && probability.is_a?(Numeric)

          { choice: choice, probability: probability.to_f, slot: data["slot"].to_s }
        rescue JSON::ParserError
          raise "rllm decide returned malformed JSON"
        end

        def base_url
          explicit = ENV["RLLM_URL"]
          return explicit.chomp("/") unless explicit.nil? || explicit.empty?

          port = ENV["RSTACK_PORT_RLLM"] || ENV["RLLM_PORT"] || "3090"
          "http://127.0.0.1:#{port}"
        end
      end
    end
  end
end
