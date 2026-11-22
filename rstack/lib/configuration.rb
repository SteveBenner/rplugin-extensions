#!/usr/bin/env ruby
# SPDX-License-Identifier: MIT

module Rplugin
  module Adapters
    module Rstack
      class Configuration
        DEFAULT_RPROJECTMANAGER_PORT = "1091"

        def initialize(env: ENV)
          @registry_file_only = env["RPLUGIN_REGISTRY_FILE_ONLY"].to_s == "1"
          explicit = env["RPROJECTMANAGER_URL"]
          port = env["RSTACK_PORT_RPROJECTMANAGER"] || env["RPROJECTMANAGER_PORT"] || DEFAULT_RPROJECTMANAGER_PORT
          @rprojectmanager_url = explicit.nil? || explicit.empty? ? "http://127.0.0.1:#{port}" : explicit
        end

        def registry_file_only? = @registry_file_only

        attr_reader :rprojectmanager_url
      end
    end
  end
end
