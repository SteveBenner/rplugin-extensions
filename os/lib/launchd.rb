#!/usr/bin/env ruby
# SPDX-License-Identifier: MIT

module Rplugin
  module Adapters
    module Os
      class Launchd
        AGENTS_DIR = File.expand_path("~/Library/LaunchAgents").freeze
        PLIST_NAME_FORMAT = "%<id>s.plist".freeze
        NOT_IMPLEMENTED = "launchd adapter is declared and not implemented".freeze

        def initialize(plugin_id: nil, root: nil)
          @plugin_id = plugin_id
          @root = root
        end

        def install(_job)
          raise Rplugin::Ports::NotHandled, NOT_IMPLEMENTED
        end

        def uninstall(_job_id)
          raise Rplugin::Ports::NotHandled, NOT_IMPLEMENTED
        end

        def status(_job_id)
          raise Rplugin::Ports::NotHandled, NOT_IMPLEMENTED
        end

        def jobs
          raise Rplugin::Ports::NotHandled, NOT_IMPLEMENTED
        end
      end
    end
  end
end
