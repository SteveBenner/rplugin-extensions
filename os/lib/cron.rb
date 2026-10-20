#!/usr/bin/env ruby
# SPDX-License-Identifier: MIT

module Rplugin
  module Adapters
    module Os
      class Cron
        CRONTAB_TAG_FORMAT = "# rplugin:%<id>s".freeze
        NOT_IMPLEMENTED = "cron adapter is declared and not implemented".freeze

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
