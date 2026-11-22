# acp-protocol (ACP-0 … ACP-3): the Agent Client Protocol family

**Status:** ACP-0 **contracted** — branch `agent/acp0-contract-67a5` of [`egao1980/acp-protocol`](https://github.com/egao1980/acp-protocol), version **0.1.0**, through **team-solve** (`.team-solve/task.md`: `system: acp-protocol`, `test-system: acp-protocol/tests`, this brief). ACP-1 … ACP-3: [Slices](#slices).

[ACP](https://agentclientprotocol.com) is the editor ↔ agent protocol: Zed, JetBrains, Emacs agent-shell and others launch a coding agent as a subprocess and talk JSON-RPC 2.0 to it over stdio. The editor is the **client**; it owns the files, the terminals and the user. The agent runs prompt turns and streams their progress back. Our agent is [cl-stack-code](cl-stack-code.md) (through a new `cl-stack-code/acp` system over its SDK); our client side is for tests, conformance, and later a Lisp editor front end.

---

## Spec pin

| | |
|--|--|
| **Protocol version** | **1** (the integer `protocolVersion` of `initialize`; only bumped on breaking changes) |
| **Schema release** | **`schema-v1.34.1`** (2026-11-21) of [`agentclientprotocol/agent-client-protocol`](https://github.com/agentclientprotocol/agent-client-protocol) (moved from `zed-industries/`; Apache-2.0). Files: `schema/v1/schema.json` (stable), `schema/v1/meta.json` (stable method names) |
| **Implemented** | Everything in the **stable** v1 schema, nothing else |
| **Unstable v1** | `schema/v1/schema.unstable.json` / `meta.unstable.json` — deferred (below) |
| **v2** | **Preview** since 2026-11-20 (schema `2.0.0-beta.3`): prompts no longer own the turn, idle `state_update`, updates patched by id, background work, `tool_call/cancel` / `terminal/cancel`, `auth/login` / `auth/logout`, no `fs/*` / `terminal/*` client methods. Deferred: v2 changes the core lifecycle, so it is its own slice once it leaves Preview. Version negotiation already makes room: the agent answers `initialize` with the highest version it speaks |

### Stable v1 methods

Direction: **C→A** = the client sends, the agent handles (agent-side GF); **A→C** = the agent sends, the client handles (client-side GF). "Gate" = the capability the receiver must advertise at `initialize`; a sender refuses an unadvertised method locally (`acp-unsupported`, nothing sent).

| Method | Dir | Kind | Gate | GF |
|--------|-----|------|------|----|
| `initialize` | C→A | request | — | `acp-initialize` |
| `authenticate` | C→A | request | — | `acp-authenticate` |
| `logout` | C→A | request | `auth.logout` | `acp-logout` |
| `session/new` | C→A | request | — | `acp-new-session` |
| `session/load` | C→A | request | `loadSession` | `acp-load-session` |
| `session/list` | C→A | request | `sessionCapabilities.list` | `acp-list-sessions` |
| `session/delete` | C→A | request | `sessionCapabilities.delete` | `acp-delete-session` |
| `session/resume` | C→A | request | `sessionCapabilities.resume` | `acp-resume-session` |
| `session/close` | C→A | request | `sessionCapabilities.close` | `acp-close-session` |
| `session/set_mode` | C→A | request | — | `acp-set-session-mode` |
| `session/set_config_option` | C→A | request | — | `acp-set-session-config-option` |
| `session/prompt` | C→A | request | — | `acp-prompt` |
| `session/cancel` | C→A | notification | — | `acp-cancel` |
| `session/request_permission` | A→C | request | — | `acp-request-permission` |
| `session/update` | A→C | notification | (`plan_update` / `plan_removed`: `plan`) | `acp-session-update` |
| `fs/read_text_file` / `fs/write_text_file` | A→C | request | `fs.readTextFile` / `fs.writeTextFile` | `acp-read-text-file` / `acp-write-text-file` |
| `terminal/create` · `/output` · `/release` · `/wait_for_exit` · `/kill` | A→C | request | `terminal` | `acp-create-terminal` … `acp-kill-terminal` |
| `elicitation/create` | A→C | request | `elicitation.form` or `.url` | `acp-create-elicitation` |
| `elicitation/complete` | A→C | notification | — | `acp-complete-elicitation` |
| `$/cancel_request` | both | notification | — (optional to honour) | `acp-cancel-request` |
| `_…` (extension methods) | both | either | advertised in `_meta` | `acp-ext-method` / `acp-ext-notification` |

`session/update` kinds (all stable): `user_message_chunk`, `agent_message_chunk`, `agent_thought_chunk`, `tool_call`, `tool_call_update`, `plan`, `plan_update`, `plan_removed`, `available_commands_update`, `current_mode_update`, `config_option_update`, `session_info_update`, `usage_update`, `notice`, `compaction_update`, `compaction_summary_chunk`, `subagent_update`, `session_message`, `session_message_chunk`.

### Deferred (unstable v1, draft, v2)

| Item | Where |
|------|-------|
| `providers/list` · `providers/set` · `providers/disable`, `auth/status`, `auth/status_update` | unstable v1 |
| `session/fork` · `/archive` · `/unarchive` · `/status` · `/options` · `/set_title`; session cursors | unstable v1 |
| `mcp/message` (MCP over ACP), `proxy/initialize` · `proxy/successor` | unstable v1 |
| `cursor_update`, `prompt_suggestions_update` session updates and their capabilities | unstable v1 |
| Streamable HTTP / WebSocket transport | draft ([transport RFD](https://agentclientprotocol.com/rfds/streamable-http-websocket-transport)); our ws / http backends follow it when it lands (ACP-4) |
| The schema's `x-deserialize-default-on-error` / skip-invalid-items hints (malformed optional values → default) | not normative since 1.34.0 removed the text; ACP-0 answers malformed known fields with -32602 |
| ACP v2 | Preview |

## Prior art (intersection, not a clone)

| Source | Took | Left |
|--------|------|------|
| **ACP spec + SDKs** (Rust `agent-client-protocol`, TypeScript, Python, Kotlin) | The schema as the source of truth; the split into an `Agent` and a `Client` interface with one method per protocol method; the connection type that turns each into a proxy of the other | Generated code: our model is `schema-protocol` classes written against the schema and checked by round trips of the official examples |
| **Zed** (reference client) | What a client advertises in practice (`fs`, `terminal`), the permission dialog as `allow_once` / `allow_always` / `reject_once` / `reject_always` options, `session/load` replay before the response | Its UI concepts |
| **Emacs agent-shell** (`acp.el`) | A second, smaller client: unknown updates ignored, no `terminal` capability — the "client without X keeps working" case | — |
| **Autolith** (`lambda-symbolics/autolith`, its `agentcomms` library; ISC) | Symmetric JSON-RPC, a permission offered to **every attached client with the first answer winning** and everyone told how it was settled; a client declaring capabilities at `initialize` and unknown fields / kinds being ignored; extensions as `_name/…` methods returning a typed outcome (`ok` / unavailable / unsupported …); replay before following live events | Its world-server channels, durable replay store and reconnect protocol (cl-stack-code has H3c sessions); extension names without a reverse-DNS prefix |
| **MCP** ([mcp.md](mcp.md)) | JSON-RPC through [`rpc-protocol`](rpc.md), newline-delimited stdio, protocol GFs + transport backends; the reverse-DNS `_meta` naming ACP adopts | Its era dance (ACP has one integer version) |
| **cl-stack-code `--rpc`** ([H3d](cl-stack-code.md#h3d--locked)) | The SDK as the one core; `--rpc`'s methods map onto SDK functions, and so will ACP's | Its own method set and `event` notifications: ACP is a second protocol over the same SDK, not a change to `--rpc` |

## Locked decisions

Locked by the user unless marked *(ACP-0)* — those were decided when contracting ACP-0 and are locked with it.

| Decision | Choice | Reason |
|----------|--------|--------|
| **Shape** | A CLOS protocol plus backends, the mcp-* / ag-ui-* family shape: `egao1980/acp-protocol` (model, GFs, conditions; no transport), `egao1980/acp-backend-stdio`, later `acp-backend-ws` / `-http`, `egao1980/acp-parity` | Same as every wire family in the stack |
| **Model** | CLOS classes for the ACP schema (initialize and capabilities, auth, sessions, prompt, cancel, every `session/update` kind, permission, modes, config options, fs, terminals, elicitation) | — |
| **Scope** *(ACP-0)* | **All** of the stable v1 schema is modelled and has GFs, a superset of the list the user named (which adds logout, session list / delete / resume / close, config options, elicitation, `$/cancel_request` and the newer update kinds). Unstable v1 and v2 are deferred | "Implement only the stable parts": the stable schema is the unit the conformance suite checks, the official examples cover it, and a class + a GF per method is cheap. A harness implements what it advertises; the rest answers -32601 |
| **GFs, both roles** | Agent-side GFs a harness implements (`acp-initialize`, `acp-new-session`, `acp-prompt`, `acp-cancel`, …); client-side GFs the agent calls (`acp-request-permission`, `acp-session-update`, `acp-read-text-file`, `acp-create-terminal`, …) | — |
| **Proxies** *(ACP-0)* | The same GFs on both ends: `remote-agent` / `remote-client` are proxies of the other role whose methods send JSON-RPC, so an agent streams with `(acp-session-update remote-client n)`; while an agent GF runs, `*acp-remote*` is the client proxy | One vocabulary instead of a GF set plus a send API; the official SDKs' connection shape |
| **JSON / JSON-RPC** | JSON through json-protocol and schema-protocol (`defschema`, camelCase keys, `_meta` slot everywhere); JSON-RPC through `rpc-protocol` / `rpc-protocol-json` (the codec GFs with `*jsonrpc-codec*`, `rpc-call` / `rpc-notify` on an `rpc-transport`). **No second JSON-RPC** | — |
| **Conditions** | One condition per ACP error code: `acp-invalid-request` -32600, `acp-method-not-found` -32601 (`acp-unsupported` for an unadvertised capability, raised locally), `acp-invalid-params` -32602, `acp-internal-error` -32603, `acp-request-cancelled` -32800, `acp-auth-required` -32000, `acp-resource-not-found` -32002; an unknown code → plain `acp-error` with that code. A calling proxy re-signals the answer's condition inside `retry` / `use-value` restarts | CLHS 9; the spec's "unknown code = generic failure" |
| **Permission = restarts** | The default client method for `session/request_permission` signals `acp-permission-required` (not an error) with restarts `allow-once`, `allow-always`, `reject-once`, `reject-always` (each visible only when such an option is offered), `select-permission-option`, `cancel-permission`; unhandled → `cancelled`. The agent asks with `acp-ask-permission` → `(values kind option-id)` | As ai-agent-protocol's `agent-approval-required` with `approve` / `approve-always` / `deny` / `deny-all`; ACP-2 maps one onto the other |
| **Cancellation** *(ACP-0)* | `session/cancel` → `acp-cancel`; an `acp-request-cancelled` out of `acp-prompt` is answered `stopReason: "cancelled"`, not an error; a permission request of a session the client cancelled while it was pending is answered `cancelled` whatever the handler returned; `$/cancel_request` reaches `acp-cancel-request` (default: ignore, cancellation is optional) | The spec's prompt-turn cancellation rules |
| **Capabilities (Autolith)** | A client declares its capabilities at `initialize`; omitted = unsupported, `{}` = on (`client-supports-p` / `agent-supports-p`); a method gated on an unadvertised capability is refused by the sender | Spec MUST; a client without fs / terminal keeps working |
| **Tolerance (Autolith)** | Unknown fields are kept (`:extra :allow`) and re-emitted; unknown `session/update` kinds, content block types, tool-call content and plan content types decode to `unknown-…` classes and round-trip verbatim; open enums are strings; unknown notifications are ignored; unknown requests answer -32601; requests before `initialize` -32600 | Forward compatibility is the spec's extension model; a newer peer must never break an older one |
| **Version** *(ACP-0)* | This build speaks protocolVersion 1 and answers 1 to any `initialize`; a client receiving another version signals `acp-version-mismatch` | Spec version negotiation |
| **Loopback** *(ACP-0)* | `make-acp-loopback agent client` → `(values remote-agent remote-client)`: two connections over an in-memory `loopback-rpc-transport` that crosses every message as JSON-RPC text through `rpc-protocol-json`; synchronous and nested (a handler calls back on the same thread), with a wire log | Deterministic end-to-end tests with no threads and no backend; the real JSON on the wire |
| **stdio backend** | `acp-backend-stdio`: newline-delimited JSON-RPC over stdio via `rpc-backend-stdio` | The transport editors use |
| **Peer transport** *(ACP-0, for ACP-1)* | ACP is symmetric: the agent calls the client back while it handles `session/prompt`. `rpc-backend-stdio` 0.2.0 runs `:on-request` on its reader thread, so a handler that calls back deadlocks; **0.3.0** adds opt-in worker-thread request dispatch and a wait-for-close ([rpc-backend-stdio#11](https://github.com/egao1980/rpc-backend-stdio/issues/11)). ACP-1 ships it first | A stack gap is fixed in the stack |
| **Remote backends** | WebSocket and HTTP later, for remote clients: a bearer token, refusing plaintext off loopback | — |
| **Extensions** | Through `_meta` and extension methods: names start with `_` (spec), reverse-DNS — ours `_io.github.egao1980/<name>` *(ACP-0: the prefix)*, advertised as `_meta` capability keys `io.github.egao1980/<name>`. Each is more GFs in acp-protocol (e.g. an image-session list, unit views) returning a typed outcome: `ok`, `condition`, `busy`, `unsupported` or `cancelled`. Clients without the extension keep working. ACP-0 has the hooks (`acp-ext-method`, `acp-ext-notification`, `acp-call-ext`, `acp-notify-ext`, `capability-meta`); the outcome type and the first extensions are ACP-5 | Spec Extensibility; Autolith's typed outcomes |
| **Multi-client (Autolith)** | Later (ACP-M): a permission request is offered to every attached client and the first answer wins; the others get the settled outcome | Needs several connections per session, which ACP-0 to ACP-2 do not have |
| **Consumer** | cl-stack-code consumes it through a new `cl-stack-code/acp` system that implements the agent-side GFs over its SDK. The agent core never depends on ACP | H3d's one-core rule |

## Repo layout

| Layer | Repo | Version |
|-------|------|---------|
| Protocol | [`egao1980/acp-protocol`](https://github.com/egao1980/acp-protocol) | 0.0.0 skeleton on `main`; **0.1.0** contracted (ACP-0) |
| stdio | [`egao1980/acp-backend-stdio`](https://github.com/egao1980/acp-backend-stdio) | 0.0.0 skeleton; 0.1.0 = ACP-1 |
| RPC dependency | [`egao1980/rpc-backend-stdio`](https://github.com/egao1980/rpc-backend-stdio) | 0.2.0 → **0.3.0** (ACP-1) |
| Agent | `cl-stack-code/acp` in [`egao1980/cl-stack-code`](https://github.com/egao1980/cl-stack-code) | minor bump (ACP-2) |
| Conformance | `egao1980/acp-parity` | created **at ACP-3** (with its first tree, the same day, per the first-party rule): until a stdio agent exists there is nothing for it to run against |

## Protocol surface (ACP-0)

```lisp
;; model: one class per schema def (kebab-case), :key-style :camel, :extra :allow, _meta → META
initialize-request initialize-response client-capabilities agent-capabilities …
session-notification session-update            ; :tag sessionUpdate, UPDATE-<tag> variants
update-agent-message-chunk update-tool-call update-tool-call-update update-plan … unknown-session-update
content-block text-content … unknown-content-block   tool-call-content diff terminal … 
request-permission-request request-permission-response selected-permission-outcome cancelled-permission-outcome
(make-acp class &rest initargs)

;; codec (rpc-protocol-json underneath)
(parse-acp-object class source) (acp-object-table object) (encode-acp-object object)
acp-message (decode-acp-message source &key method) (encode-acp-message message)
(acp-error-for condition) → (values code message data)   (acp-condition-for code message &optional data)
(client-supports-p caps feature) (agent-supports-p caps feature) (capability-meta caps key)

;; peers
acp-agent acp-client remote-agent remote-client acp-connection (make-acp-connection &key role local transport)
(acp-connection-handler connection) → (lambda (method params))   (acp-handle-message connection text)
(remote-call remote method request &key timeout) (remote-notify remote method notification)
*acp-connection* *acp-remote* *acp-incoming-kind*
;; agent side
acp-initialize acp-authenticate acp-logout acp-new-session acp-load-session acp-list-sessions
acp-delete-session acp-resume-session acp-close-session acp-set-session-mode
acp-set-session-config-option acp-prompt acp-cancel
;; client side
acp-request-permission acp-session-update acp-read-text-file acp-write-text-file acp-create-terminal
acp-terminal-output acp-release-terminal acp-wait-for-terminal-exit acp-kill-terminal
acp-create-elicitation acp-complete-elicitation
;; both
acp-cancel-request acp-ext-method acp-ext-notification
(acp-send-update remote-client session-id update) (acp-ask-permission remote-client session-id tool-call options)
(acp-call-ext remote method params) (acp-notify-ext remote method params)
(make-acp-loopback agent client) → (values remote-agent remote-client)   (acp-loopback-log remote)
;; conditions
acp-error acp-invalid-request acp-method-not-found acp-unsupported acp-invalid-params acp-internal-error
acp-request-cancelled acp-auth-required acp-resource-not-found acp-version-mismatch acp-permission-required
```

The rules are in the headers of `src/model.lisp`, `src/codec.lisp`, `src/capabilities.lisp`, `src/peer.lisp` and `src/loopback.lisp` on the contract branch.

## Slices

The proposed split held, with one change: **ACP-1 starts with rpc-backend-stdio 0.3.0** (the peer transport), because the research showed the stack's stdio transport cannot carry a symmetric protocol (see *Peer transport*). ACP-0 is self-contained (in-memory loopback over `rpc-protocol-json`) and does not wait for it.

### ACP-0 — acp-protocol 0.1.0 (contracted)

The model, the GFs and the conditions; JSON round trip of every stable message against the official examples; the loopback pair.

**Given:** package and exports, the model (127 classes), constants and the method table, conditions and restart helpers, the GFs and their trivial defaults, the proxy methods. **Stubbed** (`%acp0-pending`): the codec, `acp-error-for` / `acp-condition-for`, the capability queries, the connection dispatcher, `acp-handle-message`, `remote-call` / `remote-notify` and the proxies' bookkeeping, the default permission method, the helpers, the loopback transport.

**Fixtures:** every JSON-RPC example of the v1 docs at `schema-v1.34.1` (100 messages, all valid against `schema.json`) plus 16 typed fragments, vendored under `tests/fixtures/v1/` with the upstream Apache-2.0 license and a `VENDOR.md`.

**Tests:** 233 Rove cases (66 deftests and 8 parametrized ones with 167 rows; 288 `ok` / `ng` forms).

| File | Covers |
|------|--------|
| `support` | fixtures, `json-equal`, a scripted test agent and a recording test client, pair helpers |
| `model-test` | constants; the method table against the vendored `meta.json`; **round trip of all 100 examples** (kind, typed payload class, JSON-equal re-encode) and **16 fragments**; typed fields of decoded initialize / prompt / tool calls / permission / errors / extensions; building every update kind, protocol notifications, outcomes, `_meta`, JSON null, false booleans from Lisp; envelope encoding; raw results without a method; absent params; bad envelopes (-32600) and bad params (-32602 with `issues`) |
| `tolerance-test` | unknown root and nested fields kept; unknown `session/update` kind, content block, tool-call content and plan content → `unknown-…`, verbatim round trip; unknown enum values kept; unknown capabilities and `_meta` capability keys; at the connection: unknown notifications ignored, unknown requests -32601, a client method sent to the agent -32601, extension notifications and requests, unknown fields in a live request, parse errors -32700 / non-objects -32600 with `id: null`, requests before `initialize` -32600 |
| `capability-test` | `client-supports-p` (12 features) and `agent-supports-p` (13) against rich, empty and absent capabilities; every listed feature; an unknown feature is a `type-error`; `capability-meta` |
| `error-test` | condition defaults; `acp-error-for` for every condition, other errors (-32603) and `rpc-error`s; `acp-condition-for` for every code and unknown ones |
| `loopback-test` | initialize records both sides (capabilities, info, version, `*acp-connection*` / `*acp-remote*`); the wire; version negotiation and mismatch; requests before initialize; **initialize → session/new → a prompt that streams message / thought / tool call / tool call update with diff and terminal content / plan / commands, asks permission, reads and writes files and runs a terminal**; updates before the prompt response on the wire; the six permission restarts, unhandled → cancelled, restarts follow the options, an unknown option id, option lists; **cancel while a permission is pending → `cancelled` outcome and stop reason**, per-session cancel; `acp-request-cancelled` → stop reason; `$/cancel_request`; set_mode's update; load replays before its response; new-session modes; authenticate / -32000; elicitation; unadvertised client (fs, terminal, plan operations) and agent (load, list) capabilities refused locally; plan operations with the capability; resource-not-found with data, internal errors, method-not-found, invalid params, -32800 from other methods; `retry` / `use-value` restarts; extension calls |

On the stubs: **5 of 233 pass** (the given constants, method table and condition defaults) and **228 fail, every one on a `%acp0-pending` error** or an assertion downstream of one; the system loads with no warnings (measured locally with `cl-repo test`). The model was checked once against the fixtures with a throwaway codec (all 100 examples and 16 fragments round-trip); that prototype is not committed, and the dispatcher / loopback tests have not been run against an implementation, so the solver may find test bugs: those go through a contract-fix commit.

### ACP-1 — rpc-backend-stdio 0.3.0, then acp-backend-stdio 0.1.0

- **rpc-backend-stdio 0.3.0** ([#11](https://github.com/egao1980/rpc-backend-stdio/issues/11)): opt-in `:request-dispatch :thread` for client-mode transports (each incoming request's handler on a worker, answer written when it returns; notifications stay ordered); `rpc-call` from inside a handler; wait-until-closed; the request id visible to the handler (for `$/cancel_request`). 0.2.0 behaviour stays the default.
- **acp-backend-stdio 0.1.0**: `serve-acp-stdio agent &key input output` (the agent process: both directions on its stdin / stdout, returns at EOF), `connect-acp-stdio client &key command` (launch an agent child, → `remote-agent`), `$/cancel_request` routed to the running handler, stderr left for logs, nothing but ACP on stdout.
- **Tests:** rpc-backend-stdio: a handler calling back, concurrent requests, notification order, close while a handler runs, the 0.2.0 suite unchanged. acp-backend-stdio: the ACP-0 loopback scenarios re-run over a `make-stdio-pipe` pair; a child SBCL agent driven over real pipes (initialize → new → prompt with updates and permission → cancel → EOF exit 0); a client that advertises nothing; garbage lines answered and survived.

### ACP-2 — `cl-stack-code/acp` (cl-stack-code minor, 0.10.0 at today's 0.9.1)

An ACP agent over the SDK: a `code-acp-agent` with methods on the agent GFs, mapping one-to-one onto `make-client`, `client-new-session` / `client-resume-session` (`session/load` replays the record as updates), `client-turn` (its events → `session/update`: `text_delta` → `agent_message_chunk`, thinking → `agent_thought_chunk`, `tool_use` / `tool_result` → `tool_call` / `tool_call_update` with diffs for edits, plan objects → `plan`), `client-interrupt` (`session/cancel`), the approval events → `acp-ask-permission` (allow-once / allow-always / reject-once / reject-always ↔ `:once` / `:always` / `:reject` / `:reject-all`), permission modes as ACP session modes (`session/set_mode`). File reads / writes and the shell go through the client's `fs/*` / `terminal/*` when it advertises them, else the local tools. A `--acp` flag (beside `--rpc`) serves it on stdio. Advertises `loadSession`, `promptCapabilities.embeddedContext`, `sessionCapabilities.list` / `close`; no auth methods.

- **Tests:** headless e2e with a scripted Lisp ACP client (acp-protocol's client side + acp-backend-stdio) over stdio against a child `cl-stack-code --acp` with the **mock LLM**: initialize, new, a turn with streamed chunks and a tool call that needs permission (each answer), cancel mid-turn, set_mode, load of a finished session, a client without fs / terminal (local tools used), the record on disk, exit 0 at EOF. In-process variants over the loopback for the mapping tables. A demo in `cl-stack-demos` (`harness/acp/`, `cl-repo run`) with its output committed.

### ACP-3 — acp-parity (created at this slice)

Conformance against the official schema and examples, plus a run against real clients.

- **Schema:** every message ACP-0 emits in the ACP-2 e2e validated against `schema/v1/schema.json` (the vendored copy) with `schema-protocol-json`; every vendored example decoded and re-encoded (ACP-0's suite, run against the pinned release, plus a refresh script for the next release).
- **Real clients, headless:** the official TypeScript SDK's example client and the Python SDK's client (`uv run`) driving `cl-stack-code --acp` with the mock LLM — the mcp-parity pattern. Zed has no headless mode; an **Emacs batch** run of agent-shell / `acp.el` (`emacs --batch`) is attempted and kept if it runs in CI on Linux, otherwise documented as a manual check.

### Later

| Row | Content |
|-----|---------|
| **ACP-4** | `acp-backend-ws` (ws-protocol) and `acp-backend-http` (http-server-protocol; Streamable HTTP when the transport RFD lands): bearer token, refuse plaintext off loopback, one connection per token |
| **ACP-5** | Extensions: the typed outcome (`ok` / `condition` / `busy` / `unsupported` / `cancelled`) as a class and `define-acp-extension`; the first ones: image sessions (H4b's Lisp image: list, events), unit views (H8d's `units/*`), steering (H3c) |
| **ACP-M** | Multi-client sessions: several connections attached to one session; permission offered to all, first answer wins, the rest told the outcome; replay on attach |
| **ACP-v2** | Protocol version 2 once it leaves Preview: negotiation of 1 and 2 side by side |

## Non-goals (ACP-0)

- Any transport but the in-memory loopback; threads.
- Unstable v1, v2, and the transport RFD.
- Mapping to cl-stack-code (ACP-2), multi-client (ACP-M), extension outcomes (ACP-5).
- Validating outgoing messages against the JSON Schema at run time (ACP-3 does it in tests).
