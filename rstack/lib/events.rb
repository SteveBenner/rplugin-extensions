#!/usr/bin/env ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "json"
require "securerandom"
require_relative "emit_wire"

module Rplugin
  module Adapters
    module Rstack
      class Events < Rplugin::Ports::Base
        CATEGORIES = %w[component process config validation security system cost trace metric audit durability outcome].freeze
        LEVELS = %w[debug info warn error critical].freeze
        DEBUG_KINDS = %w[registry.resolved corpus.accessed].freeze

        def emit(kind, payload)
          return fallback.emit(kind, payload) if ENV["RLOGS_DISABLE"].to_s == "1" || level(kind, payload) == "debug"

          degrade(:emit, kind, payload) do
            wire = wire_body(kind, payload)
            outcome = emit_wire.deliver(wire)
            outcome == :posted ? { "id" => wire["id"], "link" => "#{ui_url}/events?id=#{wire['id']}" } : { "id" => wire["id"] }
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

        def summary(kind, payload)
          text = payload.is_a?(Hash) ? payload["summary"].to_s.strip : ""
          text.empty? ? kind.to_s : text[0, 500]
        end

        def wire_body(kind, payload)
          {
            "id" => "evt_#{SecureRandom.hex(16)}",
            "kind" => kind.to_s,
            "level" => level(kind, payload),
            "summary" => summary(kind, payload),
            "component" => plugin_id.to_s,
            "category" => field(payload, "category", CATEGORIES, "audit"),
            "data" => payload.is_a?(Hash) ? payload : { "value" => payload }
          }
        end

        def emit_wire
          @emit_wire ||= EmitWire.for(plugin_id)
        end

        def ui_url
          given = ENV["RLOGS_UI_URL"].to_s.strip
          (given.empty? ? emit_wire.base_url : given).to_s.chomp("/")
        end
      end
    end
  end
end
