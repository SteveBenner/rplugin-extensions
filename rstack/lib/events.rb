#!/usr/bin/env ruby
# SPDX-License-Identifier: MIT

require "json"
require "time"
require "securerandom"
require_relative "http"

module Rplugin
  module Adapters
    module Rstack
      class Events < Rplugin::Ports::Base
        CATEGORIES = %w[component process config validation security system cost trace metric audit durability outcome].freeze
        LEVELS = %w[debug info warn error critical].freeze
        RETAIN_CLASSES = %w[ephemeral session project durable].freeze
        DEBUG_KINDS = %w[registry.resolved corpus.accessed].freeze

        def emit(kind, payload)
          return fallback.emit(kind, payload) if ENV["RLOGS_DISABLE"].to_s == "1" || level(kind, payload) == "debug"

          degrade(:emit, kind, payload) do
            body = envelope(kind, payload)
            res = http.post("/api/v1/rlogs/events", body: JSON.generate(body))
            raise "rlogs post failed: #{res.code}" unless res.is_a?(Net::HTTPSuccess)

            { "id" => body["id"], "link" => "#{ui_url}/events?id=#{body['id']}" }
          end
        end

        private

        def field(payload, key, allowed, default)
          value = payload.is_a?(Hash) ? payload[key].to_s : ""
          allowed.include?(value) ? value : default
        end

        def level(kind, payload)
          field(payload, "level", LEVELS, DEBUG_KINDS.include?(kind.to_s) ? "debug" : "info")
        end

        def retain_class(payload)
          return "ephemeral" unless payload.is_a?(Hash)

          [payload["retain"], payload["retain_class"]].map(&:to_s).find { |v| RETAIN_CLASSES.include?(v) } || "ephemeral"
        end

        def summary(kind, payload)
          text = payload.is_a?(Hash) ? payload["summary"].to_s.strip : ""
          text.empty? ? kind.to_s : text[0, 500]
        end

        def envelope(kind, payload)
          now = Time.now.utc.iso8601(6)
          {
            "id" => "evt_#{SecureRandom.hex(16)}",
            "schema_version" => "rlogs.event.v1",
            "event_time" => now,
            "received_time" => now,
            "sequence" => { "partition" => "component:#{plugin_id}" },
            "source" => { "component" => plugin_id, "origin" => plugin_id },
            "classification" => { "category" => field(payload, "category", CATEGORIES, "audit"), "kind" => kind.to_s, "level" => level(kind, payload) },
            "message" => { "summary" => summary(kind, payload) },
            "payload" => { "data" => payload },
            "security" => { "redaction_state" => "raw", "sensitivity" => "internal" },
            "integrity" => { "payload_hash" => nil, "previous_event_hash" => nil, "chain_hash" => nil },
            "routing" => { "retain_class" => retain_class(payload) }
          }
        end

        def http
          @http ||= Http.new(base_url)
        end

        def ui_url
          given = ENV["RLOGS_UI_URL"].to_s.strip
          (given.empty? ? base_url : given).chomp("/")
        end

        def base_url
          url = env_value("RLOGS_URL") || env_value("RLOGS_API_URL") || env_value("RSTACK_URL_RLOGS")
          return url.sub(%r{/+\z}, "") if url

          port = valid_port(env_value("RSTACK_PORT_RLOGS")) || valid_port(env_value("RLOGS_PORT")) || leased_rlogs_port
          port ? "http://127.0.0.1:#{port}" : "http://127.0.0.1:9496"
        end

        def env_value(key)
          value = ENV[key].to_s.strip
          value.empty? ? nil : value
        end

        def valid_port(value)
          return nil unless value && value.match?(/\A\d+\z/)

          number = value.to_i
          number.between?(1, 65_535) ? number : nil
        end

        def leased_rlogs_port
          home = env_value("RSTACK_HOME")
          unless home
            user_home = env_value("HOME")
            return nil unless user_home

            home = File.join(user_home, ".rstack")
          end
          doc = JSON.parse(File.read(File.join(home, "ports", "leases.json")))
          leases = doc["leases"]
          return nil unless leases.is_a?(Array)

          rlogs = leases.select { |l| l.is_a?(Hash) && l["component"] == "rlogs" }
          chosen = rlogs.find { |l| l["endpoint_id"] == "api" } || rlogs.first
          return nil unless chosen

          port = chosen["port"]
          port.is_a?(Integer) && port.between?(1, 65_535) ? port : nil
        rescue StandardError
          nil
        end
      end
    end
  end
end
