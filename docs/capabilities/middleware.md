# middleware-protocol (P2): middleware for any handler, through method combination

**Issues:** [#427](https://github.com/egao1980/cl-stack/issues/427) (this brief; the analysis and D1 to D11 are recorded there) · consumers [#426](https://github.com/egao1980/cl-stack/issues/426) (session-protocol) and [rpc-backend-htmx#19](https://github.com/egao1980/rpc-backend-htmx/issues/19)
**Status:** M0 **implemented and published**: [`middleware-protocol`](https://github.com/egao1980/middleware-protocol) 0.1.0, [PR #1](https://github.com/egao1980/middleware-protocol/pull/1) (merged; team-solve, 112 tests, 356 assertions, green on ubuntu, macOS and Windows; follow-ups [#2](https://github.com/egao1980/middleware-protocol/issues/2), [#3](https://github.com/egao1980/middleware-protocol/issues/3)). Contract history: (`%m0-pending` stubs; a reference implementation passes all 356 assertions). M1 and later: decisions below, contracts written when each run starts.
**Repos:** `middleware-protocol` (nick `stack-middleware`) with the subsystems `middleware-protocol/clack` (nick `stack-middleware-clack`) and `middleware-protocol/blackbird`
**Builds on:** closer-mop and bordeaux-threads (core); [http-server-protocol](http-server.md)'s app contract, the Clack env (the `/clack` adapter, which loads no Clack system); blackbird (the `/blackbird` adapter, already a stack dependency through http-protocol)

Cross-cutting concerns of request handlers, such as sessions, request context, rate limits, auth, timing and logging, error mapping and security headers, are written once and applied to any handler: a Clack app, an rpc-protocol handler, an MCP or A2A server, the htmx transport.

The protocol is CLOS method combination:

- **One generic function**, `(handle handler request) → response`.
- **A middleware is a mixin class.** Its `:around` methods on `handle` take control: short-circuit, rewrite the request, map errors, transform the response. Its `:before` / `:after` methods only observe.
- **The class precedence list orders the layers.** The leftmost mixin is the outermost.

---

## Problem

The stack has no middleware protocol, so every server grows its own wrappers:

- **The http-server brief** pinned Lack as the middleware layer, which covers Clack apps only.
- **The http client** has named hooks and `:around` methods on `send` (cookbook [http-client §12](../cookbooks/http-client.md#12-hooks-via-clos-prepare-request--handle-response)), for outbound requests only.
- **rpc-backend-htmx's `htmx-app`** hard-codes a token gate, then the handler, then a CSP header added to whatever either answered.
- **rpc-protocol handlers, MCP and A2A servers** each map errors their own way.

Two consumers are waiting:

- [session-protocol](https://github.com/egao1980/session-protocol) needs a session middleware that loads the session before the handler and commits it on the way out, also when the response is streamed.
- rpc-backend-htmx#19 needs sessions, the client address and rate limits per request.

The stack's rule applies: reuse existing protocols, and extract one reusable protocol instead of depending on a third-party middleware layer.

---

## Why method combination, not a chain

Tower, Ring, Rack, ASGI and gRPC interceptors build an onion out of objects or closures because their languages have no method combination. CL has it:

- an `:around` method that calls `call-next-method` is exactly a middleware layer;
- `:before` / `:after` methods are observers;
- the class precedence list orders the layers.

The stack already works this way:

- **The http client** (cookbook §12): "specialize generic functions on a client mixin". The hooks are `prepare-request` / `handle-response`, extra `:around` methods on `send` compose through `call-next-method`, and the cookbook's "don't" list rejects `add-method` as public API and `hooks=[fn …]` lists.
- **llm-protocol and ai-agent-protocol telemetry**: `:around` methods on `generate`, `respond`, `stream-respond` and `embed` (`llm-protocol/src/telemetry/instrument.lisp`).
- **llm-protocol's router**: `select-backend :around` (`llm-protocol/src/router/router.lisp`).

**What method combination gives for free:**

- No chain data structure, and no closure per layer per request: the effective method is computed once and cached.
- Short-circuit: don't call `call-next-method`.
- Rewrite the request: `(call-next-method handler new-request)`.
- Specialization on the request type by multiple dispatch. A middleware that has no method for a request type simply doesn't apply, so it is a pass-through with no fallback rule.
- One mixin can serve several protocols by specializing each one's generic function (`handle` on servers, `send` on the http client).
- Introspection through `class-precedence-list` and `compute-applicable-methods`.

**What it costs, and the answers:**

| Cost | Answer |
|---|---|
| The order is fixed when the class is defined | The order is the CPL, written once in the `defclass`; tests assert it |
| Stacks chosen at run time (from configuration, per route) | `make-handler mixins &rest initargs` builds an anonymous class with those direct superclasses through closer-mop `ensure-class`, cached per mixin list. No runtime `add-method` |
| The same middleware twice with two configurations | Not supported: a mixin appears once in a CPL. A middleware that needs several configurations takes a list in one slot |
| Plain functions cannot carry mixins | `function-handler` wraps a function. Adapters turn any handler into the transport's shape: a Clack app is `(clack-app handler)` |
| Context for inner layers: dynamic variables end with the `:around`'s extent, before a streamed or asynchronous body runs | The canonical place for context is the request object |

---

## Prior art (intersection, not a clone)

| Source | Took | Left |
|--------|------|------|
| Rust Tower (`Service`, `Layer`) | Middleware generic over the request type; responses that complete later (a `Service` returns a future), handled here by `map-response`; one middleware applies to many services | The `Service` / `Layer` object chain and `ServiceBuilder` (method combination does this); `poll_ready` back-pressure (no slice yet); boxed futures |
| Clojure Ring | The handler as a plain function of the request; context added to the request (Ring assocs keys onto the request map; here, `request-property`); "transform the response on the way out" | Higher-order closures per layer (`wrap-*` returns a new function); the composition order of `->` threading, which reads innermost first |
| Rack / Lack (`call(env)`, `builder`) | The Clack env stays normative; any Lack app, including a Lack-built stack, can be the primary of a `clack-handler`; namespaced env keys (`:middleware.request`, like `:lack.session`) | Lack as the stack's middleware layer. It stays importable for apps that want it (D11) |
| ASGI middleware (Starlette) | Pass-through for request kinds a middleware does not handle (`if scope["type"] != "http": await self.app(...)`), which dispatch now does; headers added to a streamed response by wrapping its start message, which is the Clack responder wrapped by `map-response` | The scope dict as the only request shape |
| gRPC interceptors | Separate treatment of unary and streamed responses (here, response shapes under `map-response`); metadata carried with the call (the request's properties) | Interceptor chains registered as data; Go's `context.Context` as the only channel |
| Python requests `hooks=` / httpx `event_hooks` | Named hooks for the common cases (`prepare-request` / `finish-response`, as cl-stack-http's `prepare-request` / `handle-response`) | Callback lists |
| CLOS (CLHS 7.6.6, AMOP) | Standard method combination, the class precedence list, `ensure-class` for anonymous classes | A custom `define-method-combination` (D10) |

---

## Locked decisions

### D1 to D11 (#427)

| # | Decision |
|---|---|
| D1 | The protocol is one generic function, `(handle handler request) → response`, with standard method combination. A **middleware is a mixin class** whose methods on `handle` are `:around` (control: short-circuit, rewrite the request, map errors, transform the response) or `:before` / `:after` (observation only). There is no `call-middleware`, no `next` and no chain object. |
| D2 | **Order = class precedence list**: the leftmost mixin's `:around` runs outermost, as in `(defclass app (error-handler session-handler timing-handler clack-handler) ())`. A mixin that must sit outside another says so by inheriting from it, not by convention. |
| D3 | **Run-time composition**: `make-handler mixins &rest initargs` (closer-mop `ensure-class`, an anonymous class cached per mixin list) is the only dynamic API. No `add-method` as public API (the http-client rule). |
| D4 | **Configuration lives in slots** with initargs, slot names being symbols of the mixin's own package. A handler has one instance of a given mixin; several configurations go into one slot as a list. |
| D5 | **Request objects are classes** so middleware can dispatch on them: a `request` base class with a property bag, which adapters subclass (`clack-request` holds the Clack env, and the env stays normative). Inapplicable methods are the pass-through: there is no "unknown request type" rule. |
| D6 | **Context goes on the request** (`request-property` and its `setf`), visible to inner layers and to deferred bodies. A middleware may also bind a documented special variable for synchronous code, never as the only channel. |
| D7 | **Deferred responses**: `map-response response fn`, a generic function that adapters specialize (Clack responder functions, blackbird promises). An `:around` that transforms a response on the way out always goes through it, so it works for streamed and asynchronous responses. |
| D8 | **Named hooks for the common cases**, as in the http client: the base method calls `(prepare-request handler request) → request` before the primary and `(finish-response handler request response) → response` through `map-response` after it. Mixins specialize the hooks and chain with `call-next-method`. Raw `:around` stays for control flow. |
| D9 | **Errors**: inner conditions propagate unchanged by default. An `error-handler` mixin wraps the call with `handler-bind`, not `handler-case`, so the restarts and the backtrace survive until it decides, and it turns a condition into a response through `(handle-error handler request condition)`. CLHS 9 restarts where meaningful. |
| D10 | **Standard method combination only.** A custom `define-method-combination` (for example `:middleware` qualifiers with priorities) was considered and rejected: it is non-standard and surprises readers and tools, and the CPL already orders the layers. |
| D11 | Existing patterns are not replaced. The http client keeps its mixins and `:around` on `send`: outbound middleware is the same idea on its own generic function. Lack apps can be the primary of a `clack-handler`. Later slices: an rpc-protocol adapter, and moving rpc-backend-htmx's token gate and CSP header into mixins. |

### M0 contract decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Base method** | `handle :around` on `handler`, the innermost `:around` because `handler` is last among the protocol classes in every CPL. It calls `prepare-request`, then `(call-next-method handler request*)` (`:before`, primary, `:after`), then returns `(map-response response (lambda (r) (finish-response handler request* r)))` | D8, with the hooks around exactly the methods that answer the request |
| **Order** | Mixin `:around` enter (left to right) → `prepare-request` (left to right) → `:before` (left to right) → primary → `:after` (right to left) → `finish-response` (right to left) → `:around` exit (right to left) | Standard method combination; the tests assert it against the CPL |
| **Hooks and short-circuit** | A short-circuiting `:around` skips the base method, so **no** mixin's hooks run, those of outer mixins included. A layer that must see every response (timing, security headers) is an `:around` that maps the response | Hooks belong to requests that reach the primary. This matches rpc-backend-htmx, whose CSP header also goes on the gate's 403 |
| **Rewriting** | `(call-next-method handler new-request)`, or a `prepare-request` method that returns another request. CLOS requires the same applicable methods, so the new request is normally of the same class | CLHS `call-next-method` |
| **Plain functions** | `handle` on `function` is `funcall`, with no hooks. `function-handler` (`:function`, a function designator resolved on every call, so a redefinition applies to the next request) is the terminal for mixins | Ring's "a handler is a function", without losing mixins |
| **`make-handler` / `handler-class`** | MIXINS is a non-empty proper list of class designators, outermost first. The result is a finalized `standard-class` whose direct superclasses are exactly those classes; its name is NIL or an uninterned symbol. It is cached per list of classes under a lock, so equal lists give the `eq` class, also across threads. `invalid-mixins` for an empty or improper list, a non-designator or a duplicate. An inconsistent precedence order signals an `error` and caches nothing. No method is added to any generic function | D3; a redefined mixin keeps its class object, so cached classes follow it (image-first) |
| **Slot names** | A mixin's slot names are symbols of its own package, never shared names, and its initargs are keywords named after the mixin (`:timing-report`, `:error-function`, `:response-headers`) | Slots with the same name merge in CLOS. The M0 reference first had `function-handler` and `error-handler` sharing a `%function` slot, so `:function` and `:error-function` overwrote each other. A test now pins it |
| **Property bag** | `request` with `:properties` (copied at initialization). `request-property` (EQL keys; it returns the value and whether the key is present), `setf`, `remove-request-property`, `request-properties` (a fresh plist). Not synchronized. Requests of other types have no bag | D6. One object travels through every layer and into `finish-response`, also later for a deferred response |
| **Deferred shapes** | `map-response` on `t` calls FUNCTION now. `/clack` claims `function` as the Clack streaming response: FUNCTION sees the list given to the responder, and the writer comes back unchanged. No other adapter may claim `function`. `/blackbird` maps a promise to a new promise of `(map-response value fn)`, which is recursive, so a promise of a streaming response is mapped as streaming; a rejection passes through without calling FUNCTION | D7. Clack apps return raw functions, so wrapping them in objects would break every short-circuit that streams |
| **`error-handler`** | `:error-type` (default `error`), `:error-function` (request, condition → response). `handler-bind` on `condition` filtered by `:error-type`. `handle-error` runs inside the handler, so inner restarts such as `use-value` work and cleanup runs after the decision. When `handle-error` returns, that value is the layer's response. The `decline` restart (and function) lets the same condition go on; `decline` with no restart active signals `control-error`, as `muffle-warning` does. With no `:error-function`, the handler declines. Conditions from `handle-error` itself, and conditions raised while a deferred response is produced, are not handled | D9; CLHS 9 names first (`use-value`, `control-error`), one domain restart for the one decision that is the handler's |
| **`timing-handler`** | `:timing-report` (request, response, seconds) and `:timing-clock` (default: internal real time in seconds). The clock is read on entry and when the response is produced (for streaming, at the head; for a promise, at resolution). There is no report and no clock reading when the report is NIL. Errors are not reported; put it outside `error-handler` to time mapped errors | Logging and metrics to a function, with no logging dependency in the core |
| **Clack bridge** | `clack-app handler &key request-class` → `(lambda (env) …)`, a fresh `clack-request` per call, and the response returned as it is. `clack-handler` (`:app`) calls the app with `(list* :middleware.request request env)`; `env-request` reads it back. Layers that change the env install a new plist with `(setf clack-request-env)`. `/clack` loads no Clack system | http-server-protocol's app contract. Inner Clack apps reach the request's properties (a session) |
| **`response-headers-handler`** | An `:around` on `(response-headers-handler clack-request)`: it adds each configured header whose name (STRING-EQUAL) the response lacks, in order, to a new list, also to streamed heads and to short-circuit answers. It does not apply to other request classes | Security headers on every response, like htmx-app's CSP |
| **Dependencies** | Core: closer-mop, bordeaux-threads. `/clack`: none. `/blackbird`: blackbird. Tests: rove, blackbird, bordeaux-threads, closer-mop | "Nearly dependency-free"; promise support stays optional |

---

## Protocol surface (M0)

```lisp
;; middleware-protocol (stack-middleware)
(defgeneric handle (handler request))                      ; method on FUNCTION
(defclass handler () ())                                   ; base :around = hooks + MAP-RESPONSE
(defgeneric prepare-request (handler request))             ; → request
(defgeneric finish-response (handler request response))    ; → response
(defclass function-handler (handler) ())                   ; :function, HANDLER-FUNCTION
(defun handler-class (mixins))                             ; → cached anonymous class
(defun make-handler (mixins &rest initargs))

(defclass request () ())                                   ; :properties
(defgeneric request-property (request key &optional default)) ; → value, present-p; SETF
(defgeneric remove-request-property (request key))
(defgeneric request-properties (request))                  ; → fresh plist

(defgeneric map-response (response function))              ; T: now; adapters: deferred shapes

(defclass timing-handler (handler) ())                     ; :timing-report :timing-clock
(defclass error-handler (handler) ())                      ; :error-type :error-function
(defgeneric handle-error (handler request condition))      ; → response; may DECLINE
(defun decline (&optional condition))                      ; also the restart's name

;; middleware-protocol/clack (stack-middleware-clack)
(defclass clack-request (request) ())                      ; :env, CLACK-REQUEST-ENV
(defclass clack-handler (handler) ())                      ; :app, CLACK-HANDLER-APP
(defun clack-app (handler &key (request-class 'clack-request)))
(defun env-request (env))                                  ; :MIDDLEWARE.REQUEST
(defclass response-headers-handler (handler) ())           ; :response-headers
;; + MAP-RESPONSE on FUNCTION (Clack streaming)

;; middleware-protocol/blackbird
;; + MAP-RESPONSE on BLACKBIRD:PROMISE
```

A handler built two ways:

```lisp
(defclass app (stack-middleware-clack:response-headers-handler
               stack-middleware:timing-handler
               stack-middleware:error-handler
               stack-middleware-clack:clack-handler)
  ())

(stack-http-server:serve
 (stack-middleware-clack:clack-app
  (make-instance 'app :app #'my-clack-app
                      :response-headers '(:x-frame-options "DENY")
                      :timing-report #'log-request
                      :error-function #'error-page)))

;; or, chosen at run time:
(stack-middleware:make-handler '(response-headers-handler timing-handler
                                 error-handler clack-handler)
                               :app #'my-clack-app …)
```

A middleware, written once for immediate and streamed responses:

```lisp
(defclass session-handler (stack-middleware:handler)
  ((%store :initarg :session-store :reader session-store)))

(defmethod stack-middleware:prepare-request ((h session-handler) (r clack-request))
  (setf (stack-middleware:request-property r :session) (begin-session (session-store h) r))
  (call-next-method))

(defmethod stack-middleware:finish-response ((h session-handler) (r clack-request) response)
  ;; RESPONSE is the immediate response, or the head of a streamed one
  (finish-session (session-store h) (stack-middleware:request-property r :session)
                  (call-next-method)))
```

This is a sketch of the pattern. The real mixin is `session-handler` in `session-protocol/middleware` ([session.md](session.md), S0b). It takes `:session-manager`, calls `begin-session` on the request's Clack env and installs the env that `begin-session` returns.

### Conditions

```text
middleware-error (error)
└── invalid-mixins          ; slots: mixins, reason — HANDLER-CLASS / MAKE-HANDLER
restart: decline            ; established by ERROR-HANDLER around HANDLE-ERROR
```

Conditions from handlers and middleware are never wrapped: they reach outer layers and the caller as the same object.

### Cost

Dispatch is CLOS's cached effective method, with no chain object and no closure per layer. Per `handle` call on a `handler`:

- the base method makes one closure, FINISH-RESPONSE's continuation for `map-response`;
- each mixin `:around` that maps the response makes one more;
- the Clack bridge allocates one request object and two conses for `:middleware.request`.

`make-handler` builds a class once per mixin list (under a lock) and an instance per call. M0 has no benchmark (see the follow-ups).

---

## Slices

### M0: the protocol, the Clack and blackbird adapters (middleware-protocol 0.1.0)

**Given:** package and exports, the conditions, the classes with their slots, initargs and accessors, the generic functions.

**Stubbed:**

- the base method and the default hooks;
- `handle` on `function` and `function-handler`;
- `handler-class` and `make-handler`;
- the property bag;
- `map-response` (immediate, Clack streaming, promises);
- `timing-handler`;
- `error-handler`, `handle-error` and `decline`;
- the Clack bridge (`clack-handler`, `clack-app`, `env-request`) and `response-headers-handler`.

**Tests (112, Rove, `deftest-parametrize` for the tables):**

- **Handlers:** functions, stateful objects, `function-handler` with a late-bound symbol.
- **Order:** the onion of a `defclass` handler and of `make-handler` lists, asserted against the CPL; the order of hooks, `:before` and `:after`; short-circuit skipping every hook; rewriting by `:around` and by `prepare-request`; placement by inheritance.
- **Composition:** class caching (symbols and class objects), anonymity, direct superclasses, no added methods, thread safety, mixin redefinition, `invalid-mixins` cases, an inconsistent precedence order, no slot merging.
- **Dispatch:** pass-through for other request classes and for non-`request` requests, including the adapter's mixin.
- **Properties:** the bag; visibility in and out of inner layers, for immediate, streamed and promised responses.
- **`map-response`:** five shapes; laziness, the writer, a rejection, and an error in FUNCTION.
- **Timing:** clock order, the head of a stream, the resolution of a promise, errors.
- **Errors:** propagation unchanged, mapping, `:error-type`, `decline` to an outer handler, inner restarts before unwinding, cleanup after the decision, errors in inner hooks, `handle-error` specialization, warnings untouched.
- **The Clack round trip:**
  - immediate and streamed responses through the header and timing mixins (in both orders);
  - an error mapped inside the headers;
  - a gate's 403 still gets the headers;
  - env rewriting;
  - a Lack-style app as the primary;
  - the request read from inside the app;
  - the header merge table.

### M1: rpc-protocol adapter (middleware-protocol/rpc)

- An `rpc-request` (method, params, id, metadata) and a terminal around rpc-protocol's handler shape `(lambda (method params) → result)`.
- `rpc-handler handler` returns that shape for `rpc-serve`.
- An error mapping onto `rpc-error` codes through `handle-error`.
- Streaming handlers (`rpc-serve-stream`) follow the unary ones, with the stream as a deferred response shape.
- Unblocks the MCP and A2A servers' error mapping.

### M2: errors in deferred responses

- `error-handler` for conditions raised while a deferred response is produced: promise rejections through `bb:catcher` inside `/blackbird`'s shape; a streaming body that fails before its head.
- A micro-benchmark of the dispatch cost per layer against a hand-written closure chain.

### Not a slice: the http client

The http client keeps `prepare-request` / `handle-response` and `:around` on `send` (D11). A mixin that serves both inbound and outbound specializes `handle` and `send` (a cookbook note, no adapter).

### Consumers

- **session-protocol S0b** (contract: [session-protocol#4](https://github.com/egao1980/session-protocol/pull/4)): `session-handler` is a mixin. `prepare-request` begins the session (request property `:session`). `finish-response` commits it and sets the cookie through `map-response`, so a streamed response commits before its body. The two-phase functions (`begin-session` / `finish-session`) stay the transport-neutral core.
- **rpc-backend-htmx#19:** the app becomes a `clack-handler`. Sessions, the client address (#15) and rate limits are mixins, inside the token gate.
- **Migration** (follow-up [rpc-backend-htmx#20](https://github.com/egao1980/rpc-backend-htmx/issues/20)): `htmx-app`'s token gate becomes an `:around` mixin that short-circuits with 403, and its CSP header becomes `response-headers-handler`, outside the gate.

---

## Progress

### In progress

| Slice | Package | Notes |
|-------|---------|-------|
| M0 | middleware-protocol 0.1.0 | **Implemented, published 0.1.0** ([#1](https://github.com/egao1980/middleware-protocol/pull/1) merged; team-solve: 112 tests, 356 assertions). Contract, 112 tests. On the stubs, 108 tests fail; the 4 that pass cover the given parts (the condition tree, a user-defined CLOS handler, the required `:function` initarg). A throwaway reference implementation passes all 356 assertions, and ten mutations of it are each caught (2 to 16 failing assertions each) |

### Follow-ups

- [rpc-backend-htmx#20](https://github.com/egao1980/rpc-backend-htmx/issues/20): move the token gate and the CSP header into middleware-protocol mixins (after M0 ships).
- [middleware-protocol#2](https://github.com/egao1980/middleware-protocol/issues/2): M2, errors in deferred responses, and the dispatch benchmark.
