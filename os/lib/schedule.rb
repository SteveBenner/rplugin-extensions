#!/usr/bin/env ruby
# SPDX-License-Identifier: MIT

require "shellwords"
require_relative "systemd"
require_relative "launchd"
require_relative "cron"

module Rplugin
  module Adapters
    module Os
      class Schedule < Rplugin::Ports::Base
        def install(job)
          backend.install(job)
        end

        def uninstall(job_id)
          backend.uninstall(job_id)
        end

        def status(job_id)
          backend.status(job_id)
        end

        def jobs
          backend.jobs
        end

        private

        def backend
          @backend ||= select_backend
        end

        def select_backend
          return Systemd.new(plugin_id: plugin_id, root: root) if systemd_present?
          return Launchd.new(plugin_id: plugin_id, root: root) if command_on_path?("launchctl")
          return Cron.new(plugin_id: plugin_id, root: root) if command_on_path?("crontab")

          raise Rplugin::Ports::NotHandled, "os: no schedule backend available (systemd, launchd and crontab are all absent)"
        end

        def systemd_present?
          system(*systemctl_argv, "show-environment", out: File::NULL, err: File::NULL)
        end

        def systemctl_argv
          value = ENV["RPLUGIN_SYSTEMCTL"]
          value = "systemctl" if value.nil? || value.empty?
          Shellwords.split(value) + ["--user"]
        end

        def command_on_path?(name)
          ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? do |dir|
            candidate = File.join(dir, name)
            File.file?(candidate) && File.executable?(candidate)
          end
        end
      end
    end
  end
end
