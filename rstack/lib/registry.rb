#!/usr/bin/env ruby
# SPDX-License-Identifier: MIT

require "json"
require "uri"
require_relative "http"
require_relative "configuration"

module Rplugin
  module Adapters
    module Rstack
      class Registry < Rplugin::Ports::Base
        REMOTE_ERRORS = [Net::OpenTimeout, Net::ReadTimeout, Net::HTTPBadResponse, Net::ProtocolError, IOError, SystemCallError, SocketError,
                         JSON::ParserError, URI::InvalidURIError].freeze

        def resolve(corpus_id)
          return fallback.resolve(corpus_id) if file_only?

          degrade(:resolve, corpus_id) do
            res = http.get("/api/corpora/#{URI.encode_www_form_component(corpus_id)}")
            raise "rprojectmanager: no corpus #{corpus_id}" if res.is_a?(Net::HTTPNotFound)
            raise "rprojectmanager registry lookup failed: #{res.code}" unless res.is_a?(Net::HTTPSuccess)

            entry = checked_entry(normalize(JSON.parse(res.body.to_s)))
            events&.emit("registry.resolved", { plugin_id: plugin_id, corpus_id: corpus_id, source: entry[:source], path: entry[:path] })
            entry
          end
        end

        def register(id:, path:, owner:, protocol:)
          register_remote(id: id, path: path, owner: owner, protocol: protocol) unless file_only?
          fallback.register(id: id, path: path, owner: owner, protocol: protocol)
        end

        def retire(id)
          retire_remote(id) unless file_only?
          fallback.retire(id)
        end

        def plugins
          fallback.plugins
        end

        def corpora
          return fallback.corpora if file_only?

          merge_by_id(fallback.corpora, remote_corpora)
        end

        private

        def config = @config ||= Configuration.new

        def file_only?
          config.registry_file_only?
        end

        def register_remote(id:, path:, owner:, protocol:)
          res = http.post("/api/corpora", body: JSON.generate(id: id, path: path, owner: owner, protocol: protocol, status: "active"))
          return unless res.is_a?(Net::HTTPSuccess) && owner

          http.post("/api/corpora/#{URI.encode_www_form_component(id)}/relationships",
                     body: JSON.generate(entity_type: "plugin", entity_id: owner, ownership_status: "owner"))
        rescue *REMOTE_ERRORS => e
          emit_remote_failure(:register, e)
          nil
        end

        def retire_remote(id)
          http.delete(["/api/corpora", URI.encode_www_form_component(id), "relationships", URI.encode_www_form_component(plugin_id)].join("/"))
        rescue *REMOTE_ERRORS => e
          emit_remote_failure(:retire, e)
          nil
        end

        def remote_corpora
          res = http.get("/api/corpora")
          return [] unless res.is_a?(Net::HTTPSuccess)

          body = JSON.parse(res.body.to_s)
          return [] unless body.is_a?(Hash)

          Array(body["corpora"]).grep(Hash).map { |data| normalize(data) }
        rescue *REMOTE_ERRORS => e
          emit_remote_failure(:corpora, e)
          []
        end

        def emit_remote_failure(operation, error)
          events&.emit("registry.remote_failed", { plugin_id: plugin_id, operation: operation.to_s, error: error.class.name, message: error.message })
        rescue StandardError
          nil
        end

        def merge_by_id(local, remote)
          merged = {}
          Array(local).each { |entry| merged[entry_id(entry)] = entry }
          Array(remote).each { |entry| merged[entry_id(entry)] = entry }
          merged.values
        end

        def entry_id(entry)
          entry[:id] || entry["id"]
        end

        def normalize(data)
          { id: data["id"], path: data["path"], owner: data["owner"], protocol: data["protocol"], source: "rprojectmanager" }
        end

        def checked_entry(entry)
          Rplugin::Ports::Standalone::Registry.check(entry)
        end

        def http
          @http ||= Http.new(base_url)
        end

        def base_url
          config.rprojectmanager_url
        end
      end
    end
  end
end
