#!/usr/bin/env ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "fileutils"
require "json"
require "net/http"
require "timeout"
require "uri"

module Rplugin
  module Adapters
    module Rstack
      class EmitWire
        CONTRACT_VERSION = "1.2.0"
        OPEN_TIMEOUT = 0.5
        READ_TIMEOUT = 2
        MAX_IN_FLIGHT = 4
        BUCKET_RATE = 20
        BUCKET_BURST = 40
        FAILURE_THRESHOLD = 5
        COOLDOWN_SECONDS = 30
        SPOOL_CAP_BYTES = 256 * 1024 * 1024
        SIZE_CHECK_SECONDS = 5
        STDERR_REPEAT_SECONDS = 60
        MAX_LINE_BYTES = 256 * 1024
        DROP_STATUSES = [400, 413, 422].freeze
        POST_ERRORS = [SystemCallError, SocketError, IOError, EOFError, Timeout::Error, Net::ProtocolError, Net::HTTPBadResponse].freeze

        class Error < StandardError; end
        class Refused < Error; end
        class Oversize < Error; end
        class SpoolFull < Error; end

        REGISTRY = {}
        REGISTRY_LOCK = Mutex.new

        def self.for(plugin_id)
          REGISTRY_LOCK.synchronize { REGISTRY[plugin_id.to_s] ||= new(plugin_id) }
        end

        attr_reader :plugin_id

        def initialize(plugin_id)
          @plugin_id = plugin_id.to_s
          @lock = Mutex.new
          @tokens = BUCKET_BURST.to_f
          @refilled = nil
          @in_flight = 0
          @probing = false
          @size_checked = -Float::INFINITY
          @over_cap = false
        end

        def deliver(wire)
          line = JSON.generate(wire)
          raise Oversize, "event of #{line.bytesize} bytes is over #{MAX_LINE_BYTES}" if line.bytesize > MAX_LINE_BYTES

          return :posted if post_admitted(line)

          append(line)
          :spooled
        end

        def base_url
          url = env_value("RLOGS_URL") || env_value("RLOGS_API_URL") || env_value("RSTACK_URL_RLOGS")
          return url.sub(%r{/+\z}, "") if url

          port = valid_port(env_value("RSTACK_PORT_RLOGS")) || leased_rlogs_port
          port ? "http://127.0.0.1:#{port}" : nil
        end

        def spool_path
          given = env_value("RLOGS_SPOOL_PATH")
          return given if given

          File.join(stack_home, @plugin_id, "spool", "rlogs.jsonl")
        end

        private

        def clock
          Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end

        def post_admitted(line)
          base = base_url
          return false unless base

          kind = admit
          return false unless kind

          reached = false
          begin
            code = post(base, line)
            reached = code.between?(200, 299) || DROP_STATUSES.include?(code)
          ensure
            settle(kind, reached)
          end
          raise Refused, "rlogs refused the event with #{code}" if DROP_STATUSES.include?(code)

          reached
        end

        def admit
          @lock.synchronize do
            t = clock
            @refilled ||= t
            @tokens = [BUCKET_BURST.to_f, @tokens + ((t - @refilled) * BUCKET_RATE)].min
            @refilled = t
            next nil if @tokens < 1 || @in_flight >= MAX_IN_FLIGHT

            state = read_breaker
            probe = state["failures"] >= FAILURE_THRESHOLD
            next nil if probe && (@probing || cooling_down?(state["opened_at"]))

            @probing = true if probe
            @tokens -= 1
            @in_flight += 1
            probe ? :probe : :normal
          end
        end

        def cooling_down?(opened_at)
          elapsed = Time.now.to_f - opened_at
          elapsed >= 0 && elapsed < COOLDOWN_SECONDS
        end

        def settle(kind, reached)
          @lock.synchronize do
            @in_flight -= 1
            @probing = false if kind == :probe
            if reached
              clear_breaker
            else
              state = read_breaker
              failures = state["failures"] + 1
              opened_at = failures >= FAILURE_THRESHOLD ? Time.now.to_f : state["opened_at"]
              write_breaker("failures" => failures, "opened_at" => opened_at)
            end
          end
        end

        def post(base, line)
          uri = URI("#{base}/api/v1/rlogs/emit")
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = uri.scheme == "https"
          http.open_timeout = OPEN_TIMEOUT
          http.read_timeout = READ_TIMEOUT
          headers = { "Content-Type" => "application/json", "X-Rlogs-Contract" => CONTRACT_VERSION }
          http.post(uri.path, line, headers).code.to_i
        rescue *POST_ERRORS, URI::InvalidURIError
          0
        end

        def breaker_path
          File.join(File.dirname(spool_path), ".breaker")
        end

        def read_breaker
          path = breaker_path
          File.stat(path)
          doc = JSON.parse(File.read(path))
          failures = doc["failures"]
          opened_at = doc["opened_at"]
          return { "failures" => 0, "opened_at" => 0.0 } unless failures.is_a?(Integer) && opened_at.is_a?(Numeric)

          { "failures" => failures, "opened_at" => opened_at.to_f }
        rescue Errno::ENOENT, JSON::ParserError, TypeError
          { "failures" => 0, "opened_at" => 0.0 }
        end

        def write_breaker(state)
          path = breaker_path
          temporary = "#{path}.#{Process.pid}.tmp"
          FileUtils.mkdir_p(File.dirname(path), mode: 0o700)
          File.open(temporary, File::WRONLY | File::CREAT | File::TRUNC, 0o600) { |f| f.write(JSON.generate(state)) }
          File.rename(temporary, path)
        end

        def clear_breaker
          File.delete(breaker_path)
        rescue Errno::ENOENT
          nil
        end

        def append(line)
          path = spool_path
          raise SpoolFull, "rlogs emitter #{@plugin_id}: spool is at its #{SPOOL_CAP_BYTES} byte cap" if over_cap?(path)

          FileUtils.mkdir_p(File.dirname(path), mode: 0o700)
          File.open(path, File::WRONLY | File::APPEND | File::CREAT, 0o600) { |f| f.syswrite("#{line}\n") }
        end

        def over_cap?(path)
          @lock.synchronize do
            t = clock
            if t - @size_checked >= SIZE_CHECK_SECONDS
              @size_checked = t
              @over_cap = File.size?(path).to_i >= SPOOL_CAP_BYTES
            end
            notify_cap if @over_cap
            @over_cap
          end
        end

        def notify_cap
          notice = File.join(File.dirname(spool_path), ".cap-notice")
          age = begin
            Time.now - File.mtime(notice)
          rescue Errno::ENOENT
            Float::INFINITY
          end
          return if age < STDERR_REPEAT_SECONDS

          FileUtils.mkdir_p(File.dirname(notice), mode: 0o700)
          File.write(notice, "", perm: 0o600)
          warn("rlogs emitter #{@plugin_id}: spool is at its #{SPOOL_CAP_BYTES} byte cap, dropping events to the local log")
        end

        def stack_home
          env_value("RSTACK_HOME") || File.join(Dir.home, ".rstack")
        end

        def env_value(key)
          value = ENV[key].to_s.strip
          value.empty? ? nil : value
        end

        def valid_port(value)
          return nil unless value&.match?(/\A\d+\z/)

          number = value.to_i
          number.between?(1, 65_535) ? number : nil
        end

        def leased_rlogs_port
          doc = JSON.parse(File.read(File.join(stack_home, "ports", "leases.json")))
          leases = doc["leases"]
          return nil unless leases.is_a?(Array)

          rlogs = leases.select { |l| l.is_a?(Hash) && l["component"] == "rlogs" }
          chosen = rlogs.find { |l| l["endpoint_id"] == "api" } || rlogs.first
          port = chosen && chosen["port"]
          port.is_a?(Integer) && port.between?(1, 65_535) ? port : nil
        rescue Errno::ENOENT, Errno::EACCES, JSON::ParserError, TypeError
          nil
        end
      end
    end
  end
end
