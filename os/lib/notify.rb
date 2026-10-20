#!/usr/bin/env ruby
# SPDX-License-Identifier: MIT

require "json"
require "open3"
require "fileutils"

module Rplugin
  module Adapters
    module Os
      class Notify < Rplugin::Ports::Base
        TIMEOUT_S = 10
        WAIT_SCRIPT = File.expand_path("notify_wait.js", __dir__)

        def send(message)
          degrade(:send, message) do
            ensure_daemon!(message)
            message[:actions].to_a.empty? ? send_plain(message) : send_with_actions(message)
            { status: "sent", id: message[:id], adapter: self.class.name }
          end
        end

        def capabilities
          { actions: true, persistence: true }
        end

        def await_choice(message, timeout_s)
          raise Rplugin::Ports::NotHandled, "os: gjs is not on PATH" unless command_on_path?("gjs")
          raise Rplugin::Ports::NotHandled, "os: no DBUS_SESSION_BUS_ADDRESS" if ENV["DBUS_SESSION_BUS_ADDRESS"].to_s.empty?

          spec_path = message[:spec_path].to_s
          argv = ["gjs", WAIT_SCRIPT, spec_path, timeout_s.to_i.to_s]
          Open3.popen2(*argv, pgroup: true) do |stdin, stdout, thread|
            stdin.close
            reader = Thread.new { stdout.read.to_s.strip }
            if thread.join(timeout_s + 30).nil?
              Process.kill("TERM", -thread.pid)
              reader.kill
              return nil
            end
            choice = reader.value.lines.last.to_s.strip
            choice.empty? ? nil : choice
          end
        end

        private

        def ensure_daemon!(message)
          raise Rplugin::Ports::NotHandled, "os: notify-send is not on PATH" unless command_on_path?("notify-send")
          raise Rplugin::Ports::NotHandled, "os: gjs is not on PATH, so action buttons cannot be caught" unless message[:actions].to_a.empty? || command_on_path?("gjs")
          raise Rplugin::Ports::NotHandled, "os: no DBUS_SESSION_BUS_ADDRESS" if ENV["DBUS_SESSION_BUS_ADDRESS"].to_s.empty?
        end

        def base_argv(message)
          argv = ["notify-send", "-a", message[:source].to_s, "-u", (message[:urgency] || "normal").to_s]
          argv.push("-i", message[:icon].to_s) if message[:icon]
          argv.push("-t", message[:expire_ms].to_s) if message[:expire_ms]
          argv
        end

        def send_plain(message)
          argv = base_argv(message) + ["--", message[:title].to_s, message[:body].to_s]
          Open3.popen2e(*argv, pgroup: true) do |stdin, output, thread|
            stdin.close
            reader = Thread.new { output.read }
            if thread.join(TIMEOUT_S).nil?
              Process.kill("KILL", -thread.pid)
              reader.kill
              raise "os: notify-send timed out after #{TIMEOUT_S}s"
            end
            text = reader.value.to_s.strip
            raise "os: notify-send failed (#{thread.value.exitstatus}): #{text}" unless thread.value.success?
          end
        end

        def send_with_actions(message)
          dir = File.join(Rplugin::Paths.state_home, "notify", "waiters")
          FileUtils.mkdir_p(dir)
          spec_path = File.join(dir, "#{message[:id]}.json")
          File.write(spec_path, JSON.generate({ "message" => message, "plugin_id" => plugin_id }))
          bin = File.join(Rplugin::Paths.home, "bin", "rnotify")
          pid = Process.spawn(bin, "__wait", spec_path, pgroup: true, in: :close, out: [File.join(dir, "#{message[:id]}.log"), "a"], err: [:child, :out])
          Process.detach(pid)
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
