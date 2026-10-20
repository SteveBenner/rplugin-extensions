### Added

- slice_2c_os_extension: `os/lib/schedule.rb`, the os extension's
  `schedule` adapter (`Rplugin::Adapters::Os::Schedule`). It picks systemd,
  launchd or cron by probing `systemctl --user show-environment`,
  `launchctl` and `crontab`, and delegates `install`, `uninstall`, `status`
  and `jobs`; when none of the three is present it raises `NotHandled` so
  the chain falls through to the standalone `none` adapter.
- slice_2c_os_extension: `os/lib/systemd.rb`
  (`Rplugin::Adapters::Os::Systemd`) renders a `<id>.service` and
  `<id>.timer` unit pair from a `Rplugin::ScheduleJob`, validates
  `on_calendar` with `systemd-analyze calendar` when it is available,
  backs up a changed unit under `<dir>/.backup/<unit>-<UTC stamp>` before
  rewriting it through `Rplugin::AtomicFile`, drives
  `systemctl --user daemon-reload` / `enable --now` / `disable --now` /
  `list-timers`, and records every install and uninstall to
  `${XDG_STATE_HOME}/rplugin/<plugin>/schedule.jsonl`, which `#jobs` also
  reads back from.
- slice_2c_os_extension: `os/lib/launchd.rb` and `os/lib/cron.rb`
  (`Rplugin::Adapters::Os::Launchd`, `Rplugin::Adapters::Os::Cron`) declare
  the launchd and cron adapter shapes (the `~/Library/LaunchAgents`
  plist path and the `# rplugin:<id>` crontab tag, each as a string
  constant); every method raises `NotHandled` naming the adapter as
  declared and not implemented.
