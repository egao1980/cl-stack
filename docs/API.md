# cl-stack API conventions

**Style:** CLOS protocols + Python-grade DX. Not Java SPI, not Boost policies.

## Layers

1. **`foo-protocol`** — tiny ASDF system: generic functions, conditions, value types. Almost no deps.
2. **`cl-stack/foo` facade** — keyword-heavy helpers with sane defaults. What cookbooks teach.
3. **`foo-backend-*`** — `defmethod`s; selected by ASDF / pins, not a plugin DSL.

## Rules

- Keywords over positionals for user-facing APIs.
- Conditions (+ restarts where useful), not status-code-only errors.
- One app-level async DX (promise xor callback xor await-macro); **multiple event-loop backends** via `event-protocol`.
- `with-` macros + `unwind-protect` for resources.
- No god base classes.
- Escape hatches for experts (`raw-*` or inject upstream objects).

## Wave-1 protocol set

- `event-protocol` — run / defer / cancel / sleep / register-io; multi-backend + default pin
- `http-protocol` — sync + async send; request/response values
- `ws-protocol` — connect, send, on-message, ping, close

Capability issues must include a **Protocol surface** section before coding backends.
