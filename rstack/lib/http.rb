#!/usr/bin/env ruby
# SPDX-License-Identifier: MIT

require "net/http"
require "uri"
require "securerandom"

module Rplugin
  module Adapters
    module Rstack
      class Http
        CONNECT_TIMEOUT = 3
        READ_TIMEOUT = 5
        MAX_RETRIES = 2
        BASE_BACKOFF = 0.2
        MAX_BACKOFF = 2.0
        RETRYABLE_STATUS = [429, 502, 503, 504].freeze

        class RetrySignal < StandardError; end
        private_constant :RetrySignal

        def initialize(base_url)
          @base_url = base_url
        end

        def get(path, headers: {})
          request(:get, path, headers: headers)
        end

        def post(path, body:, headers: {})
          request(:post, path, body: body, headers: headers)
        end

        def delete(path, headers: {})
          request(:delete, path, headers: headers)
        end

        private

        def request(verb, path, body: nil, headers: {})
          uri = URI.parse(@base_url)
          http = Net::HTTP.new(uri.host, uri.port)
          http.open_timeout = CONNECT_TIMEOUT
          http.read_timeout = READ_TIMEOUT
          http.start

          begin
            request_with_retry(http, verb, path, body: body, headers: headers)
          ensure
            http.finish if http.started?
          end
        end

        def request_with_retry(http, verb, path, body:, headers:)
          attempt = 0
          begin
            attempt += 1
            res = perform(http, verb, path, body, headers)
            return res if res.is_a?(Net::HTTPSuccess)

            status = res.code.to_i
            if RETRYABLE_STATUS.include?(status) && attempt <= MAX_RETRIES
              sleep(backoff_for(attempt, res["retry-after"]))
              raise RetrySignal
            end
            res
          rescue RetrySignal
            retry
          rescue Net::OpenTimeout, Net::ReadTimeout, IOError, Errno::ECONNRESET, Errno::ECONNREFUSED, SocketError
            raise if attempt > MAX_RETRIES

            sleep(backoff_for(attempt, nil))
            retry
          end
        end

        def perform(http, verb, path, body, headers)
          req = build_request(verb, path)
          req["content-type"] = "application/json"
          req["accept"] = "application/json"
          req["idempotency-key"] = SecureRandom.uuid if verb == :post
          headers.each { |k, v| req[k] = v }
          req.body = body if body
          http.request(req)
        end

        def build_request(verb, path)
          case verb
          when :post then Net::HTTP::Post.new(path)
          when :delete then Net::HTTP::Delete.new(path)
          else Net::HTTP::Get.new(path)
          end
        end

        def backoff_for(attempt, retry_after)
          return [retry_after.to_i, MAX_BACKOFF].min if retry_after && !retry_after.to_s.strip.empty?

          window = [BASE_BACKOFF * (2**(attempt - 1)), MAX_BACKOFF].min
          rand * window
        end
      end
    end
  end
end
