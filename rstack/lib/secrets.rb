#!/usr/bin/env ruby
# SPDX-License-Identifier: MIT

require "json"
require "uri"
require_relative "http"

module Rplugin
  module Adapters
    module Rstack
      class Secrets < Rplugin::Ports::Base
        def get(name)
          return fallback.get(name) if ENV["RVAULT_DISABLE"].to_s == "1"

          degrade(:get, name) do
            lease_id = acquire_lease(name)
            raise Rplugin::MissingSecret, "no lease for #{name.inspect}" unless lease_id

            value = fetch_secret(name, lease_id)
            raise Rplugin::MissingSecret, "no value for #{name.inspect}" if value.nil? || value.to_s.empty?

            value
          end
        end

        private

        def acquire_lease(name)
          res = http.post("/api/v1/leases", body: JSON.generate(secret_path: name.to_s, lessee: plugin_id))
          return nil unless res.is_a?(Net::HTTPSuccess)

          JSON.parse(res.body.to_s)["id"]
        end

        def fetch_secret(name, lease_id)
          encoded = name.to_s.split("/").map { |segment| URI.encode_www_form_component(segment) }.join("/")
          res = http.get("/api/v1/secrets/#{encoded}", headers: { "X-Lease-Id" => lease_id, "X-Lessee" => plugin_id })
          return nil unless res.is_a?(Net::HTTPSuccess)

          JSON.parse(res.body.to_s)["value"]
        end

        def http
          @http ||= Http.new(base_url)
        end

        def base_url
          explicit = ENV["RVAULT_URL"]
          return explicit unless explicit.nil? || explicit.empty?

          port = ENV["RSTACK_PORT_RVAULT"] || ENV["RVAULT_PORT"] || "9085"
          "http://127.0.0.1:#{port}"
        end
      end
    end
  end
end
