#!/usr/bin/env ruby
# SPDX-License-Identifier: MIT

module Rplugin
  module Adapters
    module Rstack
      class Schedule < Rplugin::Ports::Base
        MESSAGE = "rstack has no scheduler; the os extension installs timers"

        def install(_job)
          raise Rplugin::Ports::NotHandled, MESSAGE
        end

        def uninstall(_job_id)
          raise Rplugin::Ports::NotHandled, MESSAGE
        end

        def status(_job_id)
          raise Rplugin::Ports::NotHandled, MESSAGE
        end

        def jobs
          raise Rplugin::Ports::NotHandled, MESSAGE
        end
      end
    end
  end
end
