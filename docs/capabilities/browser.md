# browser-protocol: headless browser over CDP

**Repo:** [`egao1980/browser-protocol`](https://github.com/egao1980/browser-protocol) · **0.2.0** (egao1980/browser-protocol#4: #1, #2, #3)
**Python counterparts:** Playwright (`chromium.launch()`, `page.goto(wait_until=)`, `connect_over_cdp`), Selenium WebDriver.

| System | Role |
|---|---|
| `browser-protocol` (`stack-browser`) | Page and session GFs, the CDP client (`cdp-browser-backend` over `send-fn` / `recv-fn`), the mock backend, the computer-use loop over `llm-protocol` |
| `browser-protocol/launch` | `launch-browser` / `with-browser` / `connect-cdp`: Chrome, Chromium or Edge over a CDP websocket |
| `browser-protocol/capability` | `:world` adapter |

## Locked decisions

| Decision | Choice |
|---|---|
| JSON | `json-protocol` + `json-backend-jzon` (objects → string-key hash-tables, `false` → `NIL`, `null` → `:null`). No private parser |
| Screenshot / PDF base64 | `encoding-protocol` `:base64` |
| Transport | `ws-protocol` (websocket-driver backend), one browser socket, page commands on a flattened `Target.attachToTarget` session |
| Process | `process-protocol` (`process-backend-uiop`), its own process group so close stops the helpers. Temporary `--user-data-dir`, `--remote-debugging-port=0`, port from `DevToolsActivePort` (no HTTP `/json` polling) |
| Replies | Matched by id. Whoever reads the transport files what it reads: a reply goes to the command waiting for its id (replies to abandoned commands are dropped), an event to a bounded buffer (`*cdp-event-buffer-limit*`) and then to its `on-cdp-event` handlers. `wait-for-cdp-event` takes from the buffer and looks again after every message |
| Re-entry and threads | Handlers run on the reading thread with no lock held, so a handler may send commands (`page.route` + `continue_()` as a `Fetch.requestPaused` handler). One thread reads at a time (bt2 lock + condition variable); other threads sharing the backend wait for what it files, each until its own deadline |
| JavaScript values | `eval-js` maps the RemoteObject: `false` / `undefined` → `NIL`, `null` → `:null`, BigInt → integer, `NaN` / `±Infinity` / `-0` → `:nan` / `:infinity` / `:-infinity` / `-0.0d0`; no value → the RemoteObject. A JS exception is a `browser-error` with its text (`click` / `type-text` on a missing selector too) |
| Waiting | `navigate` `:wait-until` `:load` (default) / `:domcontentloaded` / `:commit` and `:timeout`. `Page.enable` once per backend. `errorText` → `browser-error` with the URL. Every command has a deadline (`cdp-timeout`; `*cdp-receive-timeout*` for custom transports) |
| Errors | `browser-error` (`browser-error-cause` holds the JSON / ws / process condition), `browser-timeout`, `browser-disconnected`. Operations establish `retry` and `use-value` |

```lisp
(asdf:load-system "browser-protocol/launch")
(stack-browser:with-browser (b)                  ; headless, temporary profile
  (stack-browser:navigate b "https://example.com") ; waits for load
  (stack-browser:eval-js b "document.title")
  (stack-browser:screenshot b))                    ; PNG octets
```

The sandbox story is unchanged: Chromium can run inside a `compute-protocol` sandbox, and the backend accepts a compute backend slot. `launch-browser` is the local-process path.
