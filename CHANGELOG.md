# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.7.1] - 2026-10-20

### Changed

- The catalogue is published on GitHub at https://github.com/SteveBenner/rplugin-extensions. The README links there, and the changelog names a consuming service in generic terms.

### Unchanged

- No adapter, `extension.yml` content other than `catalogue_version`, or `harnesses.yml` entry changed from 2.7.0.

## [2.7.0] - 2026-10-20

### Added

- `rstack` author adapter (`rstack/lib/author.rb`, `Rplugin::Adapters::Rstack::Author`) for a plugin-declared `author` port: `open(context)` starts a conversation, `turn(session, text, &on_event)` streams the reply from rllm's `POST /api/dispatch/stream` on the `analysis` profile (`RPLUGIN_AUTHOR_PROFILE`) with the rllm-admission/1 envelope (tenant `RPLUGIN_AUTHOR_TENANT`, default `rplugin-decide`, qos interactive, 120000 ms deadline, `on_busy` reject) and emits `delta` and `done` events, `close(session)` drops the conversation. Bounds: 3 s connect, 120 s read, at most 2 jittered retries on 429, 5xx and network errors before the first output, 10 requests a minute per process; an unreachable or refusing rllm raises `PortUnavailable`, and `RPLUGIN_AUTHOR_DISABLED=1` raises before any request. `rstack/extension.yml` provides `author`, maps the adapter and declares the `author` rllm surface.

## [2.6.3] - 2026-10-17

### Changed

- `rstack` decide adapter speaks rllm-admission/1: every `/api/decide` call carries `x-rllm-contract`, `x-rllm-tenant` (`RPLUGIN_DECIDE_TENANT`, default `rplugin-decide`), qos interactive, a 12000 ms deadline, `x-rllm-on-busy: reject`, one idempotency key per decision and a fresh attempt id per attempt. A busy answer (429) or an unavailable answer (503) takes the standalone form at once instead of being retried; `in_progress`, `preempted`, `interrupted`, 500, 502, 504 and network faults get at most two attempts, waiting the answer's `retry_after_ms` plus up to 20% jitter and only while the wait fits the deadline.
- `rstack/extension.yml` declares the `rllm_contract` block for surface `decide` (busy and unavailable fall back to the standalone form).

## [2.6.2] - 2026-10-16

### Added

- `rstack` events adapter: category `outcome` (rlogs 0.24.0 outcome ledger) passes through instead of being coerced to `audit`, and the envelope's `routing.retain_class` comes from the event's `retain` (or `retain_class`) when it is ephemeral, session, project or durable, else ephemeral as before. A consuming service's desk outcome events arrive durable.

## [2.6.1] - 2026-10-16

### Fixed

- `rstack` events adapter: `base_url` read `RLOGS_URL`, then `RSTACK_PORT_RLOGS`/`RLOGS_PORT`, then 9496. A host process the rstack supervisor did not start (a consuming service's systemd services emitting through `rplugin events emit`) has none of these, so every event failed on 9496 and landed in the standalone `events.jsonl` fallback instead of rLogs. It now resolves `RLOGS_URL`, `RLOGS_API_URL`, `RSTACK_URL_RLOGS`, `RSTACK_PORT_RLOGS`, `RLOGS_PORT`, the `rlogs` entry of `${RSTACK_HOME:-~/.rstack}/ports/leases.json`, then 9496, trimming values and dropping trailing slashes.

## [2.6.0] - 2026-10-15

### Added

- Claude Code rules surface: `claude-code/plan.sh` links each `PLUGIN_RULES` entry to `<home>/rules/rplugin/<plugin id>/<basename>`,
  a directory Claude Code reads recursively and follows symlinks in, and `harnesses.yml` declares it as `rules_dir`. The links are
  kept in native mode. Codex, Hermes, Pi and the DeepSeek TUI have no rules directory.

## [2.5.0] - 2026-10-08

### Added

- `rstack/lib/decide.rb`, the rstack adapter for the `decide` port: posts one choice question to rllm's
  `POST /api/decide` on the `decision` profile, keeps the options in the order given, and returns the chosen option with its
  probability, the answering slot and the latency. Timeouts are 3 s to connect and 12 s to read, with at most 2 jittered
  retries; any failure degrades to the standalone Anthropic form. `RPLUGIN_DECIDE_DISABLED=1` raises
  `Rplugin::PortUnavailable` before any request.

## [2.4.3] - 2026-10-06

### Changed

- The rstack events adapter keeps debug events out of rLogs and writes them to the plugin's local events file. `registry.resolved` and
  `corpus.accessed` are debug unless the payload sets a level. Since 2.4.2 they made up about 98% of the roughly 365 events
  a minute rLogs received.

## [2.4.2] - 2026-10-06

### Fixed

- The rstack `events` adapter sent a bare UUID as the event id, which rLogs refuses with 422, so every plugin event fell
  back to the local file. It now sends `evt_<32 hex>`, takes `level`, `category` (from rLogs' closed taxonomy, never
  `decision`) and `summary` from the event when they are valid, and returns the stored id with a link
  (`RLOGS_UI_URL`, else the rLogs base URL) for `rplugin events emit`.

## [2.4.1] - 2026-10-06

### Fixed

- `claude-code`: the native install also runs `claude plugin marketplace update <id>` and `claude plugin update
  <id>@<id> --scope user`, so reinstalling a newer version replaces Claude Code's cached copy. Both exit 0 when the
  plugin is current (claude plugin update reported "already at the latest version" on this machine).

## [2.4.0] - 2026-10-05

### Added

- `codex`: the link plan carries a plugin's Codex profile. When a plugin has built `build/codex/<id>.config.toml` (rplugin 1.8.0, `rplugin persona build`), `plan.sh` links it to `${CODEX_HOME:-$HOME/.codex}/<id>.config.toml`, where `codex --profile <id>` layers it over `config.toml`. Measured with codex-cli 0.160.0 in a scratch `CODEX_HOME`: `codex --profile <id> debug prompt-input` showed the profile's `developer_instructions` as the first developer message, and the same command without `--profile` did not.

## [2.3.1] - 2026-10-03

### Fixed

- `codex` `root_variable_verified` claimed `${PLUGIN_ROOT}` expands in any plugin MCP server. Measured with codex-cli 0.160.0 in a scratch `CODEX_HOME`: it expands only in the root Agent Plugins `mcp.json` (and in hooks); a server in `.codex-plugin/plugin.json` gets the literal text, no `PLUGIN_ROOT` and the session's folder, while a relative `cwd` resolves to the installed copy. The note now says so, and rplugin 1.6.4 renders Codex servers that way.

## [2.3.0] - 2026-10-03

### Added

- `os` extension provides `notify` (`os/lib/notify.rb`): plain messages through `notify-send` with a 10 s timeout; messages with actions through `os/lib/notify_wait.js` under `gjs`, which sends over D-Bus and waits on the same connection for `ActionInvoked` or `NotificationClosed`, because GNOME 50 delivers action signals only to the creating connection and libnotify 0.8.8 reports it as action-less. Answers not-handled without `notify-send`, `gjs` (for actions) or a session bus.
- Every extension's `catalogue_version` is 2.3.0.

## [2.2.1] - 2026-10-01

### Fixed

- `codex` `root_variable` is `${PLUGIN_ROOT}`, verified against codex-cli 0.159.3: Codex installs a plugin into `<home>/plugins/cache`, expands `${PLUGIN_ROOT}` in a plugin MCP server's args to that copy, runs the server there, and sets `PLUGIN_ROOT` and `CLAUDE_PLUGIN_ROOT` for plugin hooks. A generated Codex package no longer carries the packaging machine's absolute path.

## [2.2.0] - 2026-10-01

### Added

- `antigravity` extension: native install through `agy` when present, otherwise a link into `{home}/config/plugins/{id}`.
- `cowork` extension: a remote harness; `check.sh` refuses a plugin that claims cowork support and ships a top-level `bin/`.
- `harnesses.yml` records each harness's hook events, native package files, MCP file, root variable and limits.
- A `native` block on `claude-code` (marketplace add, then `plugin install <id>@<id> --scope user`) and `codex` (marketplace add, then `plugin add`), with uninstall steps that remove the plugin and its marketplace.
- `claude-code/plan.sh` links each `contents.commands` file into `~/.claude/commands/`.
- `hermes` merges a plugin's block into the profile `config.yaml`.

### Fixed

- The deepseek home search order, and the `os` and `rstack` notes. Each extension's `provides` lists only what it implements.

## [2.1.1] - 2026-09-29

### Fixed

- The rstack extension's rLogs events carried no `source.origin`, so rLogs rejected every event they raised for a plugin (two downstream plugins were counted) since it made the field mandatory on 2026-09-25. `rstack/lib/events.rb` now sets `source.origin` to the plugin id, alongside `source.component`.

## [2.1.0] - 2026-09-25

### Changed

- Every harness `plan.sh` (`claude-code`, `codex`, `hermes`, `pi`,
  `deepseek-tui`) links every skill directory in `PLUGIN_SKILLS` and, for
  `claude-code`, every agent file in `PLUGIN_AGENTS` - both newline-joined
  lists the rplugin installer now exports - falling back to the single
  `skills/$PLUGIN_ID` (and, for `claude-code`, `agents/$PLUGIN_ID.md`) block
  when the list is empty (`rplugin install --self`, or a manifest that lists
  neither). `codex/plan.sh` links a `codex/agents/<n>.toml` per
  `PLUGIN_AGENTS` entry, plus the existing `codex/agents/$PLUGIN_ID.toml`
  line, deduped when the two names coincide. A plugin with several skills, or
  an agent named differently from the plugin, now installs in full instead of
  only its own id's skill and agent. See `specs/plugin-extension.yml`'s
  `plan_sh_env` in rplugin for the full environment contract.

### Fixed

- The `rstack` registry adapter no longer requires `rplugin/ports/standalone/registry` by load path, which failed outside the SDK's own load path; the runtime already loads it.
- `claude-code` linked skills to `<home>/claude/skills` and agents to `<home>/agents` under a default home of `~/.ai`, a single machine's private layout; on a standard install that put skills where Claude Code never reads them. The home is now `RPLUGIN_CLAUDE_HOME`, then `CLAUDE_CONFIG_DIR`, then `~/.claude`; skills link to `<home>/skills/<id>` and agents to `<home>/agents/<id>.md`. The legacy `RSTACK_HARNESS_HOME` resolves to `$RSTACK_HARNESS_HOME/claude`. `detect.sh` also recognises `CLAUDE_CONFIG_DIR` and a `claude` binary on `PATH`.

## [2.0.0] - 2026-09-24

### Changed

- slice_1a_rplugin_extensions_repo: catalogue moved to its own repository
  (rplugin-extensions), out from under the rStack superproject.
- slice_1a_rplugin_extensions_repo: schema line on every `extension.yml`
  moved from `rstack.plugin-extension/v1` to `rplugin.extension/v1`.
- slice_1a_rplugin_extensions_repo: `claude-code`'s `RSTACK_HARNESS_HOME`
  reads renamed to `RPLUGIN_CLAUDE_HOME`, with `RSTACK_HARNESS_HOME` kept as
  a deprecated legacy fallback.
- slice_1a_rplugin_extensions_repo: `rstack/plan.sh` now emits nothing; the
  bin-entry-point link moves to the SDK installer.
- slice_1a_rplugin_extensions_repo: `rstack/extension.yml`'s `provides`
  drops `state` (`secrets, events, registry, schedule`) and gains a declared
  `adapters` map naming the lib files slice_2b_ports_rstack adds.

### Added

- slice_1a_rplugin_extensions_repo: the `os` extension (`detect.sh`,
  `check.sh`, `plan.sh`, `extension.yml`) declaring the `schedule` port over
  systemd, with launchd and cron as declared shapes; `lib/schedule.rb` is
  not shipped by this slice.
- slice_1a_rplugin_extensions_repo: `harnesses.yml`, naming each harness's
  home env var, default home path, skills/agents/commands directories,
  interface file, skill format, confidence and docs URL.

### Removed

- slice_1a_rplugin_extensions_repo: `install.sh` and `lib/ports.rb` are not
  carried into this repository; both are superseded by the SDK runtime
  (`rplugin install`, `lib/rplugin/ports.rb`).
