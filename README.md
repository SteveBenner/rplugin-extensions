# rplugin-extensions

> **Agents:** this catalogue is a submodule of rplugin. Read rplugin's
> `AGENTS.md` (section "Extend rplugin") before adding or changing an extension.

The extension catalogue for [rplugin](https://github.com/SteveBenner/rplugin),
the free-software plugin SDK. This is the canonical copy and nothing vendors it: a
plugin reaches it through the SDK install at `~/.rplugin/extensions`
(`Rplugin::Paths.catalogue`).

## What an extension is

A plugin's core (`bin`, `lib`, `skills`, `agents`, `specs`, `docs`) knows
nothing about any host. An extension is a drop-in package that adapts that
core to exactly one host: it owns that host's detection, its link plan, its
install-time safety check, and, for a `fleet` or `os` kind extension, the
host's own ports under `lib/`. A plugin enables the subset of the catalogue
it needs under `extensions.enabled` in its `<id>.rplugin.yml` manifest
(`specs/plugin.yml`, schema `rplugin/v1`).

Every extension directory `<id>/` carries exactly four files:

- `extension.yml` - conforms to `specs/plugin-extension.yml`
  (`rplugin.extension/v1`): id, kind, what it provides, its detect rule,
  its confidence in the host paths it links into, and, for `fleet` and `os`
  kinds, the `adapters` map naming its port implementation files.
- `detect.sh` - exit 0 when the host is present on this machine, 1
  otherwise. Never writes anything.
- `check.sh` - exit 0 when it is safe to install for this host, prints why
  not and exits non-zero otherwise. A non-zero exit here aborts the whole
  install before any extension links anything.
- `plan.sh` - prints `<relative-source>|<absolute-target>` lines, one per
  link this extension wants installed. Reads `PLUGIN_ID` and `PACKAGE_ROOT`
  from the environment, both exported by the installer. Emits nothing for a
  source that does not exist in the package, rather than a link the
  installer will then reject.

A `fleet` or `os` extension additionally carries `lib/<port>.rb` for each
port named in its `extension.yml`'s `adapters` map, defining
`Rplugin::Adapters::<CamelId>::<CamelPort> < Rplugin::Ports::Base`
(`Rplugin::Adapters::Rstack::Secrets`, `Rplugin::Adapters::Os::Schedule`,
and so on). A port named in `adapters` with no matching file on disk is
reported by `rplugin doctor`, never raised by the SDK's port resolver.

## The catalogue today

| id | kind | provides | confidence |
| --- | --- | --- | --- |
| `rstack` | fleet | secrets, events, registry, schedule, decide, author | verified |
| `claude-code` | harness | skills, agents, commands, hooks, mcp (hooks and mcp natively) | verified |
| `codex` | harness | agents, interface; skills, hooks, mcp natively | verified |
| `hermes` | harness | skills; hooks, mcp by config merge | verified |
| `pi` | harness | skills | unverified |
| `deepseek-tui` | harness | skills | unverified |
| `antigravity` | harness | skills, agents, rules, mcp (natively only) | unverified |
| `cowork` | harness (remote) | nothing; checks the package rules | verified |
| `os` | os | schedule (systemd user timers; launchd and cron declared, not implemented) | verified for systemd |

Every link-mode harness `plan.sh` links every skill directory (not `codex`,
which links none) and (`claude-code` and `codex`) every agent file, and
`claude-code` every command file, a plugin's manifest lists, under that entry's own
name, falling back to the single `skills/<plugin-id>` (and
`agents/<plugin-id>.md`/`.toml`) link only when the manifest lists none - see
rplugin's `specs/plugin-extension.yml` (`plan_sh_env`) for the
`PLUGIN_SKILLS`/`PLUGIN_AGENTS` contract every `plan.sh` here reads.

`pi` and `deepseek-tui` link into the `.agents/skills` cross-tool convention
under their own home directory rather than a guessed host-specific
directory name, because neither host documents its own skills path
upstream. Their `extension.yml` says so under `confidence: unverified`; see
`harnesses.yml` for every host's declared paths.

`claude-code`, `codex`, `antigravity` and `hermes` may carry a `native` block
in `extension.yml`: how the harness installs a whole plugin package (CLI runs,
a package link, or a config merge). `antigravity` installs only natively, so
its `plan.sh` emits nothing. `cowork` is a `remote` harness: it installs from a
marketplace URL, its `plan.sh` emits nothing, and its `check.sh` refuses a
plugin with a top-level `bin/` that claims cowork support.

`rstack` and `os` are the two extensions with port adapters under `lib/`:
`rstack` backs secrets, events and the registry with a fleet's services and
answers "not handled" for schedule, and backs decide and a plugin-declared author port
with rllm; `os` installs schedule jobs as systemd
user timers.

## `harnesses.yml`

One entry per harness id (`claude-code`, `codex`, `hermes`, `pi`,
`deepseek-tui`, `antigravity`, `cowork`): its home env var (and, for `claude-code`, the deprecated
legacy var), its default home path or fallback chain, its skills/agents/
commands directories, an interface file a harness reads from inside the
package itself, its skill file format, its confidence, and a docs URL. Every
harness `extension.yml`'s `notes` field points here rather than restating
the paths.

## Installing

The install driver lives in the SDK, not here: `~/.rplugin/bin/rplugin
install <plugin-path>` globs this catalogue's `extension.yml` files, runs
each extension's `detect.sh`, `check.sh` and `plan.sh`, validates the
combined plan, and links everything with relative symlinks. This repository
only declares the four files per extension that driver reads; see rplugin's
`docs/reference/installer.md` for the install contract and
`docs/guides/extending.md` for writing an extension.

## Sandbox variables

Every host's install root can be overridden, so a test run can sandbox an
entire install into a scratch directory without touching the live `$HOME`:

| host | override |
| --- | --- |
| claude-code | `RPLUGIN_CLAUDE_HOME`, then Claude Code's `CLAUDE_CONFIG_DIR` (legacy: `RSTACK_HARNESS_HOME`) |
| codex | `CODEX_HOME` |
| hermes | `HERMES_HOME` |
| pi | `PI_HOME` |
| deepseek-tui | `DSH_HOME` (else `~/.dsh`, else `~/.deepseek`) |
| antigravity | `RPLUGIN_ANTIGRAVITY_HOME` |
| rstack | `RSTACK_BIN_HOME` |
| os | `RPLUGIN_SYSTEMD_DIR` (systemd only; launchd and cron are not overridable) |

## Adding an extension

1. Create `<id>/` with the four files above (plus `lib/<port>.rb` for each
   port a `fleet` or `os` extension's `adapters` map names).
2. Add a row to the table in this README and an entry to `harnesses.yml`
   when `<id>` is a harness.
3. Bump `VERSION` and this repository's `CHANGELOG.md`.
