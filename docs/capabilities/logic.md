# Logic, SAT and policy: logic-protocol, sat-protocol, policy-protocol (Track L)

**Status:** **planned**, locked 2026-11-22. Track **L** (slices L0–L6) of [HARNESS-PLAN.md](https://github.com/egao1980/cl-workspace/blob/main/docs/HARNESS-PLAN.md). Repos are created the day their slice starts (`scripts/create-first-party-repo.sh`).

| System | Repo | Role | Slice |
|--------|------|------|-------|
| `logic-protocol` (nick `stack-logic`) | new `egao1980/logic-protocol` | Facts, relations, rules, queries; assert / retract; incremental `update` returning the delta of derived facts; proofs and traces; conditions + restarts. No backend inside | **L0** → 0.1.0 |
| `logic-backend-datalog` | new `egao1980/logic-backend-datalog` | Default backend: pure Lisp, semi-naive incremental evaluation, stratified negation, optional time-step rules (Dedalus-style) | **L0** → 0.1.0 |
| `policy-protocol` (nick `stack-policy`) | new `egao1980/policy-protocol` | permit / forbid / ask, layers, obligations, `evaluate-policy` + trace, `defpolicy`, settings JSON/TOML loading; analysis GFs (bodies land in L2) | **L1** → 0.1.0, **L2** → 0.2.0 |
| `sat-protocol` (nick `stack-sat`) | new `egao1980/sat-protocol` | Propositional formulas and CNF, `solve`, `solve-all`, `minimize`, unsat cores. No backend inside | **L2** → 0.1.0 |
| `sat-backend-dpll` | new `egao1980/sat-backend-dpll` | cl-repository's solver algorithm (naive backtracking, constant folding) ported, plus unit propagation. cl-repository itself is not changed (deferred) | **L2** → 0.1.0 |
| `logic-protocol/sat` | in `egao1980/logic-protocol` (separate system) | **The bridge**: grounds a finite Datalog program into clauses; reachability, conflict and widening queries | **L2** |
| `canvas-protocol` minor | [`egao1980/canvas-protocol`](https://github.com/egao1980/canvas-protocol) | Rule-driven forms: fact deltas → htmx out-of-band swaps | **L3** |
| migrations | ai-agent-protocol, cl-stack-code, agent-tools, compute-protocol, lisp-mcp, cl-stack-pathlib, others | Every rule or logic computation in the stack moves onto these protocols ([L4 migrations](#l4--migrations-expected-not-optional)); Quint export + MBT replay for plan mode | **L4a–L4f** |
| `logic-backend-asp` | new `egao1980/logic-backend-asp` | Answer-set programming: ground, then search on sat-protocol (choice rules, integrity constraints, optimisation) | **L5** (scheduled, after L2) |
| `logic-backend-prolog` | new `egao1980/logic-backend-prolog` + a cl-stack-systems import | Full Prolog through an existing CL Prolog, imported unmodified | **L6** (when a consumer needs it) |
| `sat-backend-cdcl` | later | Conflict-driven clause learning (MiniSat-style) | **later** |

**`decision-protocol` stays separate.** It makes probabilistic LLM decisions, not rule decisions. A policy may take its answer as one context fact (`(decision :looks-destructive 0.9)`), never the other way round.

---

## Why

Rule logic lives in at least five places today, each with its own semantics, conflict rule and data format:

| Where | What it decides | Its semantics |
|-------|-----------------|---------------|
| [ai-agent-protocol](https://github.com/egao1980/ai-agent-protocol) `src/permissions.lisp` | Whether a tool call is `:allow`, `:ask` or `:deny` | `permission-rule` = action glob + resource glob + effect (+ `feedback`). Per resource the **last matching rule wins** (`permission-rules-effect`); across resources a deny wins, then an ask. A policy layer (`*permission-policy*`, `permission-policy-effect`: NIL, a rule list or a function) **only tightens**. Saved "always" rules go through `permission-rule-store` (`save-permission-rule` / `list-permission-rules`). No match → the tool's own default |
| [agent-tools](https://github.com/egao1980/agent-tools) `src/shell-scan.lisp` | Which resources a shell command touches | `shell-command-resources`: a conservative scanner (POSIX / cmd / opaque); anything not modelled appends `"*"`. Feeds `tool-permission-resources` |
| [compute-protocol](https://github.com/egao1980/compute-protocol) `confinement-decide` | Whether a confined process may `:read` / `:write` a path or `:connect` | The reference model and test oracle for the confinement backends ([confinement.md](confinement.md)) |
| [cl-stack-code](https://github.com/egao1980/cl-stack-code) `src/permissions.lisp`, `src/settings.lisp` | Settings layering and permission modes | `settings-permission-rules` concatenates mode base rules, then every allow, ask and deny, so that "last match wins" yields deny > ask > allow. Plan mode is a separate deny-list policy (`settings-permission-policy`). R4d-4b adds sandbox states on top. **R4d-4b's ideator found a bug here:** switching permission mode rebuilt plan mode's bash allow rules after a sandbox refusal. Hand-rebuilt rule lists break easily |
| [cl-repository](https://github.com/egao1980/cl-repository) `src/client/source-policy.lisp` | Where a system may come from (OCI registry, Quicklisp, nowhere) | `*source-policy*` (system → `:oci` / `:ql` / `:any` / `:deny`) plus ordered `*source-rules*` (`(:deny NAME [:from R])`, `(:allow NAME :from R)` as a whitelist), `*default-source*` |

Each has its own glob matcher, its own conflict rule ("last match", "rank", "whitelist") and no way to answer "can this rule ever fire?", "do these two rules conflict?" or "does the project layer loosen the user layer?". The rules are data with a fixed meaning, so they belong in one logic with one evaluator, explanations and static analysis.

Separately, cl-repository embeds a SAT solver (`src/client/solver.lisp`: formulas as structs, naive backtracking with constant folding and a latest-version-first variable order). It is useful beyond package resolution and should be a stack library.

---

## Layering

**SAT and logic are independent; only the bridge depends on both.**

```
                 policy-protocol ──────────────┐ (analysis, L2)
                      │                        ▼
 canvas forms ──► logic-protocol ◄── logic-protocol/sat ──► sat-protocol ◄┄┄ cl-repository (resolver, deferred)
   (L3)            ▲     ▲     ▲                              ▲      ▲
                   │     │     └ logic-backend-asp ───────────┘      │
                   │     └ logic-backend-prolog (import)             sat-backend-dpll, sat-backend-cdcl
                   └ logic-backend-datalog (default)
```

- `sat-protocol` knows nothing about rules. `logic-protocol` knows nothing about SAT.
- `logic-backend-asp` is the only backend that needs a SAT solver; it depends on sat-protocol, not on a SAT backend.
- `policy-protocol` depends on `logic-protocol` (evaluation). Its analysis functions load `logic-protocol/sat` lazily: a policy evaluated at run time never loads a SAT solver.

---

## Prior art

| Prior art | Take | Leave |
|-----------|------|-------|
| **Datalog** (Soufflé; Datomic / Datascript queries) | Horn rules over relations, stratified negation, semi-naive evaluation, queries as patterns with logic variables; Datascript's "facts in, query out" use in an application | Soufflé's compilation to C++; Datomic's time model (we use Dedalus time steps) |
| **Dedalus** (Alvaro et al.) | Time as a rule argument: `next` rules derive state at t+1 from t, deductive rules within t | Asynchronous (`async`) rules and distribution |
| **Cedar** (AWS) | permit / forbid, **forbid overrides permit**, default deny, policies as analysable data, SMT-verified analysis (subsumption, equivalence, conflicts) — closest to policy-protocol | Its own language and parser, entity type schemas in 0.1.0, SMT (we stay propositional over a finite grounding) |
| **OPA / Rego** | Policy as code over a JSON context, decision + explanation trace | Full Datalog-with-functions generality: it makes analysis hard |
| **Casbin** | The PERM model (Policy, Effect, Request, Matchers): the effect combiner is a parameter | Its string matcher DSL |
| **XACML** | Combining algorithms (deny-overrides, permit-overrides, first-applicable) as an explicit layer property; obligations attached to decisions | XML, the PDP/PEP/PIP vocabulary |
| **Zanzibar / SpiceDB** | Nothing yet: relationship-based access is **out of scope**. Relation tuples are facts, so it fits later | Tuple stores, zookies, consistency tokens |
| **clingo / ASP** | Choice rules, integrity constraints, `#minimize`, ground-then-solve, stable-model semantics | gringo's full input language (aggregates beyond count / sum, external atoms) |
| **PAIP Prolog**, **Screamer** | Candidates to import for `logic-backend-prolog` (L6) and for nondeterministic search | Writing our own WAM |
| **MiniSat / CDCL** | Two-watched-literal propagation, clause learning, assumptions-based unsat cores (for `sat-backend-cdcl`) | Preprocessing and inprocessing in the first version |
| cl-repository `solver.lisp` | Formula structs, simplifying constructors, the latest-version-first order (as a variable order / phase hook) | Re-substitution of the whole formula per branch (replaced by CNF + unit propagation) |

---

## Locked decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Shape** | Usual cl-stack shape: protocol repos with no backend inside, backend repos, `*logic-backend*` / `*sat-backend*` specials plus a `:backend` argument | One model, several engines |
| **Independence** | sat-protocol and logic-protocol do not depend on each other; the bridge `logic-protocol/sat` depends on both; logic-backend-asp depends on sat-protocol | Package resolution needs no rules; evaluating a policy needs no solver |
| **Dependencies** | sat-protocol, sat-backend-dpll, logic-protocol, logic-backend-datalog: **no dependencies** (pure Lisp). policy-protocol: logic-protocol + serdes for settings data (`json-protocol`, `toml-protocol`) in a separate `policy-protocol/settings` system | Small, loadable anywhere, including a package manager's bootstrap if cl-repository migrates later |
| **Terms** | Atoms are lists `(relation arg…)`; constants are strings, integers, keywords and symbols; logic variables are symbols starting with `?`. No function symbols in the Datalog backend | Plain data compared with `EQUAL`; no function symbols keeps evaluation finite |
| **Rules** | `(rule HEAD :- BODY…)`; body literals are atoms, `(not ATOM)` and built-ins (`(= ?x ?y)`, `(< …)`, `(glob PATTERN ?s)`, `(prefix …)`). **Range restriction** is checked when a rule is added (`logic-unsafe-rule`) | Safe rules give finite answers |
| **Negation** | Stratified. A cycle through `not` signals **`logic-unstratifiable`** with restarts **`drop-rule`** (add the program without the offending rule) and **`use-backend`** (retry on a backend that accepts it, e.g. ASP) | Unstratified negation needs stable models, which is ASP's job |
| **Incremental update** | `update` takes asserted and retracted base facts and returns a **delta** (`added`, `removed` derived facts). Semi-naive for additions, delete-and-rederive (DRed) for retractions | Canvas forms and long-lived policies re-evaluate on every input; the delta is what to re-render |
| **Budget** | Every query and update runs under a budget (derivation steps, wall time). Exceeding it signals **`logic-budget-exceeded`** with **`continue`** (raise the budget once) and **`use-value`** (return the partial result) | Total by default; agents write rules too |
| **Proofs** | `explain` returns a proof tree (rule + the facts it used, down to base facts) for a derived fact, and a "why not" trace (the first failing body literal per candidate rule) for a fact that does not hold | Self-explaining decisions and form fields |
| **Time-step rules** | Optional, Dedalus-style: `(rule (next (state ?s2)) :- (state ?s1) (event ?e) (step ?s1 ?e ?s2))`. `tick` moves facts derived by `next` into time t+1; base facts persist only through explicit persistence rules. A time-step program exports to Quint / TLA+ through spec-dsl (state = the relations at t, actions = events) | Wizards and plan / sandbox state machines are the same program the model checker sees |
| **Analysable subset** | Stratified Datalog, no function symbols, built-ins limited to `=`, `/=`, comparison on finite constants, `glob`, `prefix`. policy-protocol only produces this subset | The bridge can ground it over a finite domain |
| **Bridge grounding** | Domain = the constants in the program and context, plus **one witness string per glob pattern and per non-empty pairwise pattern intersection**, plus one fresh constant ("anything else"). Ground atom = variable, rule = clause; derived atoms get Clark completion (their value is fixed by their rules) | Glob languages over `*` and `?` are regular; one witness per intersection cell is enough to decide overlap and subsumption. The fresh constant covers "no rule mentions it" |
| **Bridge queries** | `can-hold-p` (is a goal ever true under any context), `conflicting` (contexts where a permit and a forbid both apply), `widens-p` (does program B allow a request A denies), each with a **witness** (the context and request that show it) | Answers with a counterexample are actionable |
| **SAT model** | Formula constructors with constant folding (as cl-repository's) + `to-cnf` (Tseitin). `solve` → a model (alist) or NIL; `solve-all` → a lazy sequence of models, optionally projected on given variables; `minimize` → an optimal model for a linear objective over literals (iterated solving with a tightened bound); `unsat-core` → a subset of assumptions / named clauses | What cl-repository and ASP need |
| **SAT heuristics hook** | `solve :order` (variable order function) and `:phase` (preferred polarity) | Keeps cl-repository's latest-version-first preference without a special solver |
| **SAT backends** | `sat-backend-dpll` first: cl-repository's search over CNF with **unit propagation** and pure-literal elimination. `sat-backend-cdcl` later, behind the same GFs | Correct and small first; CDCL when a measured consumer needs it |
| **cl-repository** | **Deferred** (2026-11-22): cl-repository is left alone for now, both `solver.lisp` and `source-policy.lisp`. sat-protocol keeps the `:order` / `:phase` decision-order hook so the migration stays possible later (then: egao1980 fork only, never CommonLispNext) | Not on the critical path; the hook keeps the door open |
| **Migrations are expected** | Every other rule or logic computation in the stack moves onto logic-protocol / policy-protocol / sat-protocol once they exist (L4a–L4f). Acceptance per migration: **behaviour unchanged**, shown by the repo's existing tests passing **untouched**, plus **one new explanation / proof test** that shows the gain | One logic, one explanation format, analysis everywhere; no new hand-written rule tables |
| **Prolog** | `logic-backend-prolog` wraps an **existing** CL Prolog imported **unmodified** through cl-stack-systems. Candidates evaluated in L6: PAIP Prolog, Allegro Prolog, Screamer. Criteria: portable (SBCL, CCL, ECL), licence, runs unmodified, cut and assert. **No own WAM** | We don't reinvent the wheel |
| **ASP** | `logic-backend-asp`: ground (reusing the Datalog backend for the definite part), Clark completion, lazy loop formulas for non-tight programs (ASSAT-style), search on sat-protocol. Choice rules `{…}` with bounds, integrity constraints `(:- …)`, `#minimize` / `#maximize` via `minimize`, `count` and `sum` aggregates | clingo's surface on our own solver protocol |
| **policy-protocol** | A thin DSL that compiles to the analysable subset. Effects `:permit` / `:ask` / `:forbid`. A request is facts (`action`, `resource`, context such as `(sandbox :confined)`, `(setting :sandbox.failIfUnavailable)`) | One evaluator, analysis for free |
| **Policy combining** | Within a layer: **`:forbid-overrides`** (default; forbid > ask > permit, Cedar / XACML deny-overrides) or **`:last-match`** (last matching rule decides, then forbid > ask > permit across resources, exactly `permission-rules-effect`). Across layers: **inner layers only tighten** (the result is the strictest of the layers' effects), whatever the inner layer says | `:last-match` exists so L1 reproduces ai-agent-protocol's semantics as golden tests; new policies use the default |
| **No decision** | No rule applies → `:no-decision` (the caller applies its default, as ai-agent-protocol uses the tool's own default). A policy can state its own default with `(default :forbid)` | Same contract as today |
| **Obligations** | A decision carries obligations: `(permit :action "bash" :when … :obligation (:run :confined))`. The caller must honour each one or treat the decision as forbid; unknown obligations → forbid | XACML: "permit, provided"; fail closed |
| **Feedback** | `ask` and `forbid` carry `:feedback` text (what the model sees, as `permission-rule-feedback`) | Matches the existing denial feedback |
| **Data loading** | The same model loads from settings JSON / TOML as data (`load-policy`), read with **`*read-eval*` NIL** and no `intern` into user packages (relation and setting names stay strings or keywords) | Settings files are untrusted input |
| **Errors** | Roots `logic-error`, `sat-error`, `policy-error`; all CLHS 9 conditions with restarts (above). `policy-syntax-error` carries the offending form and offers `skip-rule` and `use-value` | No error dialect ([conditions.md](conditions.md)) |

---

## Surface sketches

Names are locked; argument details are settled in each slice's contract.

### logic-protocol (L0)

```lisp
*logic-backend*  logic-backend  (make-program &key backend) → program
(add-rule program rule) (add-rules program rules)            ; logic-unsafe-rule, logic-unstratifiable
(assert-fact program atom) (retract-fact program atom)
(update program &key assert retract) → delta                 ; delta-added delta-removed
(query program pattern &key limit budget) → list of bindings  ; pattern = atom or (and …)
(holds-p program atom) → generalized boolean
(explain program atom) → proof | why-not
(tick program) → delta                                       ; time-step programs
(program-facts program &key relation) (program-rules program)
;; conditions: logic-error logic-unsafe-rule logic-unstratifiable logic-budget-exceeded logic-no-backend
;; restarts: drop-rule use-backend continue use-value
```

### sat-protocol (L2)

```lisp
*sat-backend*  sat-backend
(sat-var name) (sat-not f) (sat-and &rest fs) (sat-or &rest fs) (sat-implies p q) (sat-iff p q)
(to-cnf formula) → cnf
(solve formula &key assumptions order phase budget backend) → model | NIL
(solve-all formula &key project limit) → lazy sequence of models
(minimize formula objective &key backend) → model, cost        ; objective = ((weight . literal) …)
(unsat-core formula &key assumptions) → list of named clauses / assumptions
;; conditions: sat-error sat-budget-exceeded sat-no-backend
```

### policy-protocol (L1 / L2)

```lisp
(defpolicy plan-mode (:combining :forbid-overrides)
  (permit :action "bash" :when (sandbox :confined)
          :obligation (:run :confined))
  (ask    :action "bash" :when (not (sandbox :confined))
          :feedback "The sandbox is unavailable; this command runs unconfined.")
  (forbid :action "bash"
          :when (and (setting :sandbox.failIfUnavailable) (not (sandbox :confined)))
          :feedback "Sandbox required (sandbox.failIfUnavailable) and unavailable."))

(make-layered-policy &rest layers)          ; outer first; inner layers only tighten
(evaluate-policy policy request) → decision ; decision-effect decision-obligations
                                            ; decision-feedback decision-trace
(policy-explain decision) → text
(load-policy source &key format)            ; :json | :toml | :sexp, *read-eval* NIL
;; analysis (L2, via logic-protocol/sat)
(policy-conflicts policy) → list of (permit-rule forbid-rule witness)
(policy-unreachable-rules policy) → rules
(policy-subsumes-p a b) → boolean, witness  ; every request B permits, A permits
(policy-equivalent-p a b) → boolean, witness
```

---

## UI rules (canvases)

A canvas form ([canvas.md](canvas.md), H4h) is **facts plus rules in the session image**:

```lisp
(rule (enabled :submit) :- (valid :email) (checked :terms))
(rule (visible :company) :- (value :account-type "business"))
(rule (valid :email) :- (value :email ?v) (glob "*@*.*" ?v))
```

- An `hx-post` from a field asserts its input fact (`(value :email "…")`) through `update`.
- The returned **delta** names the derived facts that changed; the handler re-renders only the fragments that depend on them and returns them as htmx **out-of-band swaps** (`hx-swap-oob`). The request path is an ordinary [rpc-backend-htmx](canvas.md) handler (H4h-1b).
- Result: server-driven reactive forms with no JS framework, fields that explain themselves (`explain` → "Submit is disabled because terms are not checked"), and static checks through the bridge (a field that can never be visible, a submit that can never be enabled).
- Wizards are **time-step rules**: the step is state, `next` rules move it, and the same program exports to Quint.

---

## Policy correctness (in L4)

Plan-mode and sandbox invariants, for example **"bash never runs unconfined in plan mode without an approval"**, are checked by exporting the policy together with the plan / sandbox state machine (a time-step program) to Quint through spec-dsl / spec-backend-quint, model-checking the invariant, and replaying the generated ITF traces against cl-stack-code with spec-protocol's MBT driver (skills **spec-dsl**, **quint-modeling**, **spec-mbt-conformance**). The bridge's `widens-p` checks, in addition, that a project or local settings layer never loosens the user layer.

---

## The split (each its own team-solve run)

| Slice | Repo · version | Delivers | Depends on |
|-------|----------------|----------|------------|
| **L0** | logic-protocol **0.1.0**, logic-backend-datalog **0.1.0** | Terms, rules, safety and stratification checks, semi-naive + DRed incremental `update`, queries, proofs / why-not, budgets, time-step rules + `tick` | R4d-4b done (ordering only) |
| **L1** | policy-protocol **0.1.0** | `defpolicy`, effects, layers, combining (`:forbid-overrides`, `:last-match`), obligations, feedback, `evaluate-policy`, `policy-explain`, `load-policy` (JSON / TOML / sexp) | L0 published |
| **L2** | sat-protocol **0.1.0**, sat-backend-dpll **0.1.0**, `logic-protocol/sat`, policy-protocol **0.2.0** | Formulas, Tseitin CNF, DPLL with unit propagation, `solve-all`, `minimize`, unsat cores; bridge grounding and queries; `policy-conflicts`, `policy-unreachable-rules`, `policy-subsumes-p`, `policy-equivalent-p` | L1 published |
| **L3** | canvas-protocol minor | Rule-driven forms: field facts, delta → fragments, `hx-swap-oob` responses, `explain` tooltips, bridge checks on a form | L0, H4h-0, H4h-1b |
| **L4a–L4f** | one minor per migrated repo | The migration list [below](#l4--migrations-expected-not-optional), one sub-slice each | L1 (policy) or L2 (analysis); L4d's backend selection by ASP after L5 |
| **L5** (scheduled) | logic-backend-asp **0.1.0** | Grounding, completion + loop formulas, choice rules, integrity constraints, `count` / `sum`, `#minimize` / `#maximize`; first consumer: choosing a compute backend that satisfies a requirement set | L2 |
| **L6** | logic-backend-prolog **0.1.0** + cl-stack-systems import | Evaluation of PAIP Prolog / Allegro Prolog / Screamer, one imported unmodified, wrapped as a logic backend | a consumer that needs full Prolog |

Order: **L0 after R4d-4b**; L1 → L2; **L5 scheduled right after L2**; L3 after L0 and H4h-1b; L4a → L4b first (after L2), the other L4 rows after them; L6 on demand.

### L4 — migrations (expected, not optional)

Checked against each repo's `origin/main` on 2026-11-22. Acceptance for every row: the repo's existing tests pass **untouched**, plus one new explanation / proof test.

| Sub-slice | Repo · file | What it decides today | Target | New explanation test |
|-----------|-------------|-----------------------|--------|----------------------|
| **L4a** | ai-agent-protocol `src/permissions.lisp` | `permission-rules-effect` (last match per resource, deny > ask across resources), `permission-policy-effect` (a policy only tightens), `%resources-effect` / `%denied-resources`, saved "always" rules in `permission-rule-store` | policy-protocol (`:last-match` layer per rule list, policy as an outer layer); the store saves policy rules | `policy-explain` names the deciding rule and resource for a denied call |
| **L4b** | cl-stack-code `src/permissions.lisp`, `src/settings.lisp` | `settings-permission-rules` (mode base rules + allow / ask / deny ordered so deny wins), `%mode-base-rules`, `settings-permission-policy` (plan-mode deny list), `%merge-rules` layering of user / project / local settings, `hidden-tool-names`; plus R4d-4b's plan-mode sandbox states | One conditional layered policy: modes and sandbox states are context facts (`(mode :plan)`, `(sandbox :confined)`), settings files are layers. Removes R4d-4b's hand-rebuilt permission lists. Quint export + MBT replay of the plan-mode invariants ([Policy correctness](#policy-correctness-in-l4)) | Switching mode after a sandbox refusal keeps plan mode's bash rules, and the trace says why; `widens-p` on a project layer |
| **L4c** | agent-tools `src/shell-scan.lisp`, `src/shell-tools.lisp`, `src/file-tools.lisp` | `shell-command-resources` (which programs write which operands: `+writes-every-operand+`, `+writes-last-operand+`, `+find-actions+`, `+indirect-programs+`, the starred cmd programs); confined vs unconfined tool selection (`shell-tools-confinement`, `make-shell-tools :confinement`); the path jail (`resolve-tool-path :allow-root`) | The lexer stays Lisp; the program tables become facts (`(writes-operand "cp" :last)`) and rules deriving resources; tool selection and the jail become policy rules | A resource list with a proof of which table entry produced each resource |
| **L4d** | compute-protocol `src/confinement.lisp` | `confinement-decide` (the `:read` / `:write` / `:connect` reference model); `confinement-requirements` + `check-confinement` (requirements ⊆ `confinement-features`, else `confinement-unsupported` with the missing list) | `confinement-decide` → policy-protocol; feature checks → logic-protocol rules; choosing a backend that satisfies requirements → logic-backend-asp once L5 lands | `explain` for a denied `:write`; an unsat core naming the missing features |
| **L4e** | lisp-mcp `src/scan-forms.lisp`, `src/agent/source.lisp` | The form scanner's classification (`lisp:defines`, `lisp:mutates`, `lisp:read-eval`, I/O, pure) feeding permission resources (`%code-resources`, `%resources`); observe mode (`observe-safe-resources-p`, `%observe-gate`, `observe-mode-refused`) | Scanner output as facts; observe mode and the permission mapping as a policy over them | An observe-mode refusal explained down to the scanned form |
| **L4f** | cl-stack-pathlib `src/ignore.lisp` | gitignore-style matcher: rules in precedence order, last match wins, `!` negation, directory-only rules, a forced `.git` rule | logic-protocol rules (`:last-match` semantics, negation as re-include) behind the same `ignore-matcher` API; the hot path may stay compiled if the rule form measures slower | "Why is this path ignored?" names the rule and file |
| **L4f** | mcp-backend-streamable-http `src/backend.lisp` | Origin check: a missing Origin is accepted, a present one must match the allowlist or Host | policy-protocol (a small permit / forbid policy over request facts) | A refused Origin explained |
| **L4f** | cl-stack-oauth2 `src/oidc.lisp` | `%alg-allowed-p`: ID-token `alg` against an allowlist | policy-protocol (same policy shape as the Origin check) | A refused `alg` explained |
| deferred | cl-repository `src/client/source-policy.lisp`, `src/client/solver.lisp` | Source policy (`*source-policy*`, ordered `*source-rules*`, `*default-source*`) and package resolution | policy-protocol and sat-protocol, **later** | — |

The grep (hand-written rule tables, precedence / layering, allow / deny logic) also hit mcp-protocol `src/features.lisp`, schema-protocol `src/defschema.lisp`, sql-migrate `src/target.lisp` and diff-backend-lisp-source `src/align.lisp`; those are CLOS precedence lists and algorithm priorities, not rule logic, and stay as they are.

### Tests per slice (Rove)

**L0 — logic-protocol + logic-backend-datalog**
- `term-test`: variables, constants, `EQUAL` comparison; atoms with keywords, strings, integers.
- `safety-test`: an unsafe head variable or a negated-only variable → `logic-unsafe-rule`.
- `stratify-test`: a negative cycle → `logic-unstratifiable`; `drop-rule` adds the rest; `use-backend` retries.
- `eval-test`: transitive closure, same-generation, stratified negation; results equal a naive fixpoint on random graphs (`deftest-parametrize`).
- `incremental-test`: random assert / retract sequences; `update`'s delta equals the difference of two full recomputations (semi-naive and DRed agree with naive).
- `explain-test`: proof trees bottom out in base facts; why-not names the failing literal.
- `budget-test`: a large closure under a small budget → `logic-budget-exceeded`; `continue` finishes; `use-value` returns a partial answer.
- `time-step-test`: a three-state wizard; `tick` sequences; persistence only through explicit rules.
- `backend-test`: no backend → `logic-no-backend` with `use-backend`.

**L1 — policy-protocol**
- `golden-permissions-test`: every case in ai-agent-protocol's permission tests, re-expressed as `:last-match` policies, gives the same effect and deciding rule (including "undecided resource + allow → no decision").
- `combining-test`: forbid overrides permit and ask; first / last match; inner layer cannot loosen (permit inside, forbid outside → forbid; forbid inside, permit outside → forbid).
- `glob-test`: `*` matches any run including `/`, `?` one character, whole-value match (the ai-agent-protocol glob contract).
- `obligation-test`: obligations returned; an unknown obligation → forbid.
- `plan-mode-test`: the `plan-mode` example over every combination of `(sandbox :confined)` and `(setting :sandbox.failIfUnavailable)`.
- `load-test`: the same policy from sexp, JSON and TOML evaluates identically; `#.` in a sexp source is refused; settings names are not interned.
- `explain-test`: `policy-explain` names the deciding rule and its condition.

**L2 — sat-protocol, sat-backend-dpll, bridge, policy analysis**
- `formula-test`: constant folding; Tseitin CNF is equisatisfiable (random formulas against truth tables).
- `solve-test`: random 3-SAT near the threshold against brute force; `solve-all` enumerates exactly the models (projected); `:order` / `:phase` respected.
- `minimize-test`: small weighted problems against brute force.
- `core-test`: unsat cores are unsatisfiable and drawn from the given assumptions.
- `order-hook-test`: a latest-version-first `:order` / `:phase` (the cl-repository heuristic) selects the highest versions on package-style fixtures.
- `bridge-test`: grounding of small programs against the Datalog backend's answers on every context; witness generation for glob intersections.
- `analysis-test`: seeded conflicts, unreachable rules, subsumption and equivalence pairs, each with the expected witness; `widens-p` catches a project layer that permits what the user layer forbids.

**L3 — canvas forms**
- A sign-up form: asserting `(checked :terms)` returns exactly the submit button fragment with `hx-swap-oob`; unchanged fields are not re-rendered.
- `explain` text for a disabled field; a field that can never be visible is reported by the bridge check.
- A three-step wizard driven by time-step rules; frozen output has no `hx-*` attributes.

**L4a–L4f — migrations**
- Each migrated repo's existing tests pass **untouched**; plus the explanation test in its row of the table above.
- L4b: plan / sandbox settings matrix; the Quint plan-mode invariant holds in `quint run` / `quint verify`; ITF traces replay against cl-stack-code with no divergence.
- L4d: the confinement suite gives the same results with the policy-based `confinement-decide` as the oracle.

**L5 — logic-backend-asp**
- Graph colouring, n-queens, a small scheduling problem: stable models equal brute-force stable models on small instances.
- Non-tight programs (positive loops) need loop formulas; tests with and without them.
- `#minimize` returns an optimal model; integrity constraints prune.
- Compute-backend choice: requirements (OS, network, confinement level) → the chosen backend, with an unsat core naming the conflicting requirements when none fits.

**L6 — logic-backend-prolog**
- The evaluation report (portability, licence, cut, assert) committed in the repo.
- Classic Prolog programs (append, naive reverse, zebra) through the logic-protocol query surface; the Datalog backend's L0 suite on the subset both support.

---

## Non-goals

- Our own WAM or Prolog compiler; SMT; first-order theorem proving.
- Relationship-based access control (Zanzibar / SpiceDB) in 0.1.0. Relation tuples are facts, so a later backend or index can add it.
- Probabilistic decisions: those are decision-protocol's; a policy may consume one as a fact.
- Replacing confinement: `confinement-decide` stays compute-protocol's oracle; a policy decides *whether* to run confined, the backend enforces it.

## Checklist

- [ ] **L0** logic-protocol + logic-backend-datalog 0.1.0 (after R4d-4b)
- [ ] **L1** policy-protocol 0.1.0 (golden ai-agent-protocol semantics)
- [ ] **L2** sat-protocol + sat-backend-dpll 0.1.0, bridge, policy analysis (cl-repository deferred)
- [ ] **L3** canvas forms on fact deltas
- [ ] **L4a** ai-agent-protocol · **L4b** cl-stack-code (+ Quint / MBT) · **L4c** agent-tools · **L4d** compute-protocol · **L4e** lisp-mcp · **L4f** cl-stack-pathlib, mcp-backend-streamable-http, cl-stack-oauth2
- [ ] **L5** logic-backend-asp 0.1.0 (scheduled after L2)
- [ ] **L6** logic-backend-prolog (import, on demand)
