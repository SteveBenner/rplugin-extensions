### Added

- slice_2b_ports_rstack: `rstack/lib/http.rb`, a retrying `Net::HTTP` wrapper
  (open/read timeouts, bounded jittered backoff, retry-after honoured,
  idempotency-key on POST) shared by the fleet adapters.
- slice_2b_ports_rstack: `rstack/lib/secrets.rb`, leasing a credential from
  rvault (`POST /api/v1/leases`, `GET /api/v1/secrets/<path>`) and degrading
  to the fallback on any failure.
- slice_2b_ports_rstack: `rstack/lib/events.rb`, posting an `rlogs.event.v1`
  envelope to rlogs (`POST /api/v1/rlogs/events`) and degrading to the
  fallback on any failure.
- slice_2b_ports_rstack: `rstack/lib/registry.rb`, resolving, registering,
  retiring and listing corpora against rprojectmanager's `/api/corpora`
  routes, always also writing the standalone fallback record.
- slice_2b_ports_rstack: `rstack/lib/schedule.rb`, answering every call with
  `Rplugin::Ports::NotHandled` so the os extension installs the timer.
