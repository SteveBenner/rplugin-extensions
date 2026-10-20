#!/usr/bin/env ruby
# SPDX-License-Identifier: MIT

require "shellwords"
require "json"
require "time"
require "fileutils"

module Rplugin
  module Adapters
    module Os
      class Systemd
        def initialize(plugin_id:, root: nil)
          @plugin_id = plugin_id
          @root = root
        end

        def install(job)
          job.validate!
          validate_calendar!(job.on_calendar)
          unit = "#{job.id}.timer"
          write_unit(service_path(job.id), render_service(job))
          write_unit(timer_path(job.id), render_timer(job))
          run_systemctl!("daemon-reload")
          run_systemctl!("enable", "--now", unit)
          append_state(job: job.to_h, adapter: "systemd", action: "install", at: Time.now.utc.iso8601, unit: unit)
          { adapter: "systemd", unit: unit }
        end

        def uninstall(job_id)
          run_systemctl!("disable", "--now", "#{job_id}.timer")
          [service_path(job_id), timer_path(job_id)].each { |path| move_to_backup(path) if File.file?(path) }
          run_systemctl!("daemon-reload")
          append_state(job: { id: job_id }, adapter: "systemd", action: "uninstall", at: Time.now.utc.iso8601, unit: "#{job_id}.timer")
          true
        end

        def status(job_id)
          output = capture_systemctl("list-timers", "--all", "--no-legend", "#{job_id}.timer").to_s.strip
          { installed: !output.empty?, adapter: "systemd", next: output.empty? ? nil : parse_next(output) }
        end

        def jobs
          path = state_path
          return [] unless File.file?(path)

          latest = {}
          File.foreach(path) do |line|
            trimmed = line.strip
            next if trimmed.empty?

            record = JSON.parse(trimmed)
            job_id = record.dig("job", "id")
            latest[job_id] = record if job_id
          end
          latest.values
        end

        private

        def dir
          value = ENV["RPLUGIN_SYSTEMD_DIR"]
          return File.expand_path(value) if value && !value.empty?

          config_home = ENV["XDG_CONFIG_HOME"]
          base = config_home && !config_home.empty? ? config_home : File.expand_path("~/.config")
          File.expand_path(File.join(base, "systemd", "user"))
        end

        def service_path(job_id)
          File.join(dir, "#{job_id}.service")
        end

        def timer_path(job_id)
          File.join(dir, "#{job_id}.timer")
        end

        def render_service(job)
          lines = ["[Unit]", "Description=#{job.description}", "", "[Service]", "Type=oneshot", "ExecStart=#{job.command}"]
          job.environment.each { |key, value| lines << "Environment=#{key}=#{value}" }
          "#{lines.join("\n")}\n"
        end

        def render_timer(job)
          lines = ["[Unit]", "Description=#{job.description} timer", "", "[Timer]", "OnCalendar=#{job.on_calendar}", "Persistent=#{job.persistent}"]
          lines << "OnStartupSec=#{job.startup_sec}" if job.startup_sec && !job.startup_sec.to_s.empty?
          lines += ["", "[Install]", "WantedBy=timers.target"]
          "#{lines.join("\n")}\n"
        end

        def write_unit(path, content)
          backup_if_changed(path, content)
          Rplugin::AtomicFile.write(path, content)
        end

        def backup_if_changed(path, content)
          return unless File.file?(path)
          return if File.read(path) == content

          move_to_backup(path)
        end

        def move_to_backup(path)
          backup_dir = File.join(dir, ".backup")
          FileUtils.mkdir_p(backup_dir)
          stamp = Time.now.utc.strftime("%Y%m%d-%H%M%S")
          target = File.join(backup_dir, "#{File.basename(path)}-#{stamp}")
          serial = 1
          while File.exist?(target)
            target = File.join(backup_dir, "#{File.basename(path)}-#{stamp}-#{serial}")
            serial += 1
          end
          FileUtils.mv(path, target)
        end

        def validate_calendar!(expression)
          analyze = ENV["RPLUGIN_SYSTEMD_ANALYZE"]
          return if analyze == "true"

          analyze = "systemd-analyze" if analyze.nil? || analyze.empty?
          command = Shellwords.split(analyze)
          return unless command_on_path?(command.first)

          ok = system(*command, "calendar", expression, out: File::NULL, err: File::NULL)
          raise Rplugin::Refused, "systemd: `#{command.join(' ')} calendar #{expression}` rejected the OnCalendar expression" unless ok
        end

        def run_systemctl!(*args)
          command = systemctl_argv + args
          ok = system(*command, out: File::NULL, err: File::NULL)
          raise Rplugin::Refused, "systemd: `#{command.join(' ')}` failed" unless ok
        end

        def capture_systemctl(*args)
          command = systemctl_argv + args
          IO.popen(command, err: File::NULL, &:read)
        rescue StandardError
          ""
        end

        def systemctl_argv
          value = ENV["RPLUGIN_SYSTEMCTL"]
          value = "systemctl" if value.nil? || value.empty?
          Shellwords.split(value) + ["--user"]
        end

        def command_on_path?(name)
          ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? do |entry|
            candidate = File.join(entry, name)
            File.file?(candidate) && File.executable?(candidate)
          end
        end

        def parse_next(line)
          match = line.match(/\A\S+\s+(\d{4}-\d{2}-\d{2})\s+(\d{2}:\d{2}:\d{2})\s+(\S+)/)
          return nil unless match

          date, time, zone = match.captures
          Time.parse("#{date} #{time} #{zone}").utc.iso8601
        rescue StandardError
          nil
        end

        def append_state(record)
          path = state_path
          FileUtils.mkdir_p(File.dirname(path))
          File.open(path, "a") { |file| file.puts(JSON.generate(record)) }
        end

        def state_path
          File.join(Rplugin::Paths.state_home, @plugin_id.to_s, "schedule.jsonl")
        end
      end
    end
  end
end
