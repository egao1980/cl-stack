# Agent evals: agent-eval (Track E)

**Status:** **planned**, locked 2026-11-22. Track **E** measures the [cl-stack-code](cl-stack-code.md) harness ([HARNESS-PLAN.md](https://github.com/egao1980/cl-workspace/blob/main/docs/HARNESS-PLAN.md)). **E0 is contracted**: [`egao1980/agent-eval`](https://github.com/egao1980/agent-eval), branch `agent/eval0-contract-c1bd`, version **0.1.0**. It is implemented through **team-solve** (`.team-solve/task.md`: `system: agent-eval`, `test-system: agent-eval/tests`, this brief).

| System | Repo | Role | Slice |
|--------|------|------|-------|
| `agent-eval` (nick `stack-agent-eval`) | [`egao1980/agent-eval`](https://github.com/egao1980/agent-eval) | An eval-protocol runner for agent tasks. It holds the agent adapter protocol, the Terminal-Bench task loader, the task environments on compute-protocol, grading through the task's tests, run records with pass@k, tokens, cost, time and transcripts, and run comparisons | **E0** → 0.1.0 |
| `agent-eval/podman` | same repo, separate system | The container environment: one podman container per trial, through compute-protocol | **E0** (needs compute-backend-podman 0.3.0) |
| `agent-eval-terminal-bench` | new, created when E1 starts | A Harbor agent (Python), so the Terminal-Bench number comes from Terminal-Bench's own runner; Harbor job import | **E1** |
| `agent-eval-cl-corpus` | new, created when E2 starts | The Common Lisp corpus mined from MIT / BSD CL repos' issues and PRs | **E2** (slot) |

**Repo name.** The repo is `agent-eval`, not `agent-eval-protocol`. It is not a second protocol: datasets, cases, scores, runs, reports and gates stay eval-protocol's own classes, and agent-eval adds what agents need. The adapter protocol lives inside it, as `ai-agent-protocol`'s tools live in `agent-tools`. Adapter repos take the prefix: `agent-eval-terminal-bench`, `agent-eval-cl-corpus`.

---

## Why

The harness has more than 1 000 contract tests and no measure of how well it does its job. Three questions need answers:

1. **How do we compare?** Terminal-Bench 2.x is the number labs and harness vendors report for terminal agents.
2. **Do we get better at Lisp?** No public benchmark targets Common Lisp, so the E2 corpus is the measure that matters for this stack.
3. **Which setting is better?** The same model can run under different harness settings (plan mode, system prompt, turn cap, sampling, tools). Comparing them needs stored runs with every config, transcript, token count and time.

eval-protocol 0.3.0 already has the evaluation core: content-hashed datasets with roles and holdouts, scorers with restarts (`skip-case`, `retry-case`, `score-as-failure`), reports, gates and paired trials. What it lacks is agents. That means tasks that run in an environment, an adapter that acts, a verifier, and runs kept on disk.

---

## Terminal-Bench facts this design relies on (checked 2026-11-22)

| Topic | Finding | Source |
|-------|---------|--------|
| Benchmark | **Terminal-Bench 2.0**: 89 task directories at `2fd12b88aafdd04a52c298e3940bcb189f9766d6`. **2.1** (`harbor-framework/terminal-bench-2-1`, last push 2026-11-05) is "a more verified iteration": 26 tasks were fixed | [terminal-bench-2](https://github.com/harbor-framework/terminal-bench-2), [terminal-bench-2-1](https://github.com/harbor-framework/terminal-bench-2-1) |
| Task format | One directory per task. `task.toml` has `[task]` (name, keywords), `[metadata]` (difficulty, category, tags, expert / junior time estimates), `[agent] timeout_sec`, `[verifier] timeout_sec`, and `[environment]` (`docker_image`, `build_timeout_sec`, `cpus`, `memory_mb`, `storage_mb`, `gpus`, `allow_internet`, `mcp_servers`). It also has `[environment.env]` and `[verifier.env]`. The other files are `instruction.md` (the prompt), `environment/Dockerfile` (`WORKDIR /app` is typical), `tests/test.sh` (plus e.g. `test_outputs.py`) and `solution/solve.sh` | e.g. [`cancel-async-tasks/`](https://github.com/harbor-framework/terminal-bench-2/tree/main/cancel-async-tasks) |
| Verifier | The tests are copied to `/tests` **after** the agent finishes. `test.sh` runs in the work dir and writes `/logs/verifier/reward.txt` (a number) or `reward.json` (an object of numbers). Stale reward files are removed first. An empty or non-numeric file is an error | [`verifier/verifier.py`](https://github.com/harbor-framework/harbor/blob/v0.26.0/src/harbor/verifier/verifier.py) |
| Runner | **Harbor** is the official harness. Releases: 0.26.0 (2026-11-13), 0.27.0 (2026-11-21). E1 pins **0.26.0** | [harbor releases](https://github.com/harbor-framework/harbor/releases) |
| Agent interface | `BaseAgent` (`harbor/agents/base.py`) has `name()` (static), `version()`, `async setup(environment)`, `async run(instruction, environment, context)` (fill the context as you go, so a timeout keeps what was known) and `populate_context_post_run(context)`. `nop` and `oracle` (uploads `solution/` and runs `solve.sh`) are built in | [`agents/base.py`](https://github.com/harbor-framework/harbor/blob/v0.26.0/src/harbor/agents/base.py), [`agents/oracle.py`](https://github.com/harbor-framework/harbor/blob/v0.26.0/src/harbor/agents/oracle.py) |
| Environment interface | `start(force_build)`, `stop(delete)`, `exec(command, cwd, env, timeout_sec, user)` (a bash command string), `upload_file` / `upload_dir` / `download_file` / `download_dir` | [`environments/base.py`](https://github.com/harbor-framework/harbor/blob/v0.26.0/src/harbor/environments/base.py) |
| Context | `AgentContext` has `n_input_tokens` (**including cache**), `n_cache_tokens`, `n_output_tokens`, `cost_usd`, `model_usage` and `metadata` | [`models/agent/context.py`](https://github.com/harbor-framework/harbor/blob/v0.26.0/src/harbor/models/agent/context.py) |
| Score | The job's score is the mean reward over trials, and `-k` sets attempts per task. 2.1 leaderboard runs need at least 5 trials per task (`-k 5`), uploaded publicly to Harbor Hub. Community submissions to 2.1 are closed for now | [terminal-bench-2-1 README](https://github.com/harbor-framework/terminal-bench-2-1#submitting-to-the-leaderboard) |

---

## Decisions (locked)

| Decision | Choice | Reason |
|----------|--------|--------|
| **Built on eval-protocol** | A TB task **is** a plain `stack-eval:eval-case`: `:input` is a canonical spec plist, and `:metadata` is `(:kind :tb-task :id … :files-sha256 …)`. A dataset is an `eval-dataset`. Each trial becomes an `eval-case-result` whose `actual` is the trial and whose score is the reward. `agent-eval-run` is a subclass of `eval-run`, so `eval-run-mean`, gates and `dump-dataset` work unchanged | One evaluation vocabulary across the stack. A subclass of `eval-case` would not survive eval-protocol's copies |
| **Adapter protocol** | `agent-adapter` with GFs `agent-name`, `agent-version`, `agent-config`, `agent-setup`, `agent-run` and `agent-populate-context`, plus an `agent-context` that matches Harbor's (input tokens include cache). Built-in adapters are `nop`, `oracle` and `command`. Adapters signal `agent-timeout` / `agent-failed` | It maps one to one onto Harbor's `BaseAgent`, so E1's Harbor wrapper is a thin shim and both runners mean the same thing by a trial |
| **First adapter** | `cl-stack-code-agent` runs `cl-stack-code -p INSTRUCTION --output-format stream-json --permission-mode bypassPermissions --cwd WORKDIR [--model] [--max-turns] [--append-system-prompt] [--model-param K=V]…` as a **command inside the environment**. Its stream goes to `/logs/agent/cl-stack-code.jsonl`, and the last `result` event gives `usage` (input / output / cache read / cache write), `num_turns`, `subtype` and `result`. Cost comes from `total_cost_usd` when present, else from configured prices, else NIL. `CL_STACK_CODE_CONFIG_DIR` points at `/logs/agent/config` (`settings.json` from the adapter) | Headless `-p` is what Terminal-Bench runs and what ships. agent-eval has no Lisp dependency on cl-stack-code. `bypassPermissions` is safe because the environment is the sandbox, which is also how Harbor's Claude Code adapter runs |
| **Task loader** | `load-tb-task` / `load-tb-dataset` read the TB 2.x layout above, parsing TOML through toml-protocol. Defaults: timeouts 600 s, cpus 1, memory 2048 MB, storage 10240 MB, gpus 0, internet on. The work dir is the Dockerfile's last absolute `WORKDIR`, else `/app`. Format errors are `task-format-error` with restarts `skip-task` and `use-value`. `files-sha256` hashes the task directory's content (through crypto-protocol). `dataset-digest` hashes the ids and content hashes, so it does not depend on where the checkout lives | Comparisons need a dataset identity that is the same on every machine. eval-protocol's version also hashes the host path |
| **Environments** | `task-environment` GFs: `start-environment`, `stop-environment`, `environment-exec` (a string runs under `bash -c`, a list is an argv; `:timeout` gives `timed-out-p`, not a condition), `upload-path`, `download-path`, `environment-command-path`. **Every command goes through compute-protocol.** `local-environment` is a trusted, path-mapped host directory on `native-process-backend`, for fixtures and CI. `container-environment` (`agent-eval/podman`) is one podman container per trial, kept alive from start to stop, with `/logs` bind-mounted from the trial directory | Terminal-Bench needs the verifier to see the agent's container as it was left. compute-protocol is the stack's sandbox layer, so no private podman driver is written |
| **Podman gap** | compute-backend-podman 0.2.0 runs `podman run --rm` per command with read-only mounts, so state does not survive between commands. **Filed:** [compute-backend-podman#3](https://github.com/egao1980/compute-backend-podman/issues/3) (warm sessions on `podman exec`, `:rw` mounts, copy in / out, image build) and [compute-protocol#10](https://github.com/egao1980/compute-protocol/issues/10) (`sandbox-spec :directory` / `:input`). `agent-eval/podman` is written against 0.3.0, and its test lane stays skipped until 0.3.0 is published | Fix the stack, don't work around it |
| **Grading** | `grade-trial`: delete stale reward files, upload `tests/` to `/tests` (after the agent), and run `bash /tests/test.sh` in the work dir with `[verifier.env]` and the verifier timeout. Then read `reward.txt` (a real), else `reward.json` (its `reward` member, else the mean of its numeric members). Pass means reward ≥ 1. A timeout gives reward 0. A missing or unparsable reward signals `reward-missing` with restarts `use-exit-code` and `score-zero`. The run policy `:on-missing-reward` is `:zero` (default), `:exit-code` or `:error` | Harbor's verifier semantics |
| **Trials** | `run-trial` times Harbor's phases (`:environment-setup`, `:agent-setup`, `:agent-execution`, `:verifier`). Statuses are `:completed`, `:agent-timeout`, `:agent-error` and `:environment-error`. Timeouts and agent errors are still graded; setup errors are not (reward 0). Compose tasks and tasks with `gpus > 0` signal `unsupported-task` | TB semantics: the verifier judges whatever the agent left |
| **Runs** | `run-agent-eval dataset agent &key attempts environment-factory directory on-unsupported on-missing-reward`. Trials run sequentially, task by task, attempts 1..k, under `trials/<id>/<attempt>/`. Errors escaping a trial become `stack-eval:scorer-error` with eval-protocol's restarts. `on-unsupported` is `:skip` (default), `:fail` or `:error` | One error contract for every eval |
| **Metrics** | Unbiased **pass@k** (Chen et al. 2021: 1 − C(n−c,k)/C(n,k)), exact rationals, averaged over tasks with n ≥ k. Accuracy is the mean clamped reward (TB's score). Totals cover tokens (input incl. cache, cache, output), cost (with a `cost-complete-p` flag), wall time and agent time | What reports quote |
| **Records** | `eval-report` (eval-protocol's GF) on an `agent-eval-run` gives `:sexp`, or `:json` with snake_case keys. `save-run` writes `run.sexp` (readable data plus the task specs), `result.json`, and per trial `trial.sexp` and `transcript.jsonl`. `load-run` rebuilds an equal run without touching task directories | Runs can be compared and audited later without re-running the model |
| **Comparison** | `compare-runs baseline candidate` pairs tasks by id. A digest mismatch signals `dataset-mismatch` with a `continue` restart (compare the common tasks). The result has per-task means and deltas, wins / ties / losses, mean delta, and token, cost and wall deltas. `comparison-report` gives `:markdown` (default), `:sexp` or `:json`. eval-protocol's gates (`gate-passes-p`) apply to agent runs directly | The Harness-Bench question, answered with stored runs |
| **Tests** | Tiny local fixture tasks in TB format (`hello-world` with `reward.txt`, `partial-credit` with `reward.json`), tasks generated per test for edge cases, and `fake-cl-stack-code`, a shell double that prints a recorded cl-stack-code 0.10.0 stream. **No network, no model.** The local lane needs `sh` + `bash` (skipped on Windows). The container lane is gated: podman answers `podman info`, the image is present locally, and the backend is ≥ 0.3.0. Otherwise it is skipped | CI stays deterministic and offline |
| **Live-run cost** | The Windows-box endpoint generates about 4–12 tok/s, so a full TB run (89 tasks × `-k 5`) is not a local job. Nightly: a fixed subset of ≤ 8 quick TB tasks at `-k 1`. Full runs use a hosted model, by explicit decision | Measured cost decides the schedule |

---

## Surface (E0, agent-eval 0.1.0)

```lisp
;; conditions (stack-eval:eval-error ⊃ agent-eval-error)
task-format-error (path field)  unsupported-task (task-id reason)  environment-error (task-id phase)
agent-timeout (task-id seconds)  agent-failed (task-id exit-code)  reward-missing (task-id reason)
dataset-mismatch (baseline candidate)  run-not-found (path)
;; restarts: skip-task use-value (loader) · use-exit-code score-zero (grading) · continue (compare)
;;           stack-eval:skip-case retry-case score-as-failure (runs)

;; Terminal-Bench tasks
(load-tb-task dir &key id) → eval-case     (load-tb-dataset dir &key name include exclude) → eval-dataset
tb-task-p task-spec find-task dataset-digest task-files-sha256 +default-workdir+
task-id task-name task-instruction task-directory task-image task-dockerfile-p task-compose-p task-workdir
task-agent-timeout task-verifier-timeout task-build-timeout task-cpus task-memory-mb task-storage-mb
task-gpus task-allow-internet-p task-env task-verifier-env task-solution-p task-difficulty task-category task-tags

;; environments (compute-protocol underneath)
task-environment start-environment stop-environment environment-started-p environment-task
environment-trial-directory (environment-exec env command &key timeout directory env) → exec-result
upload-path download-path environment-command-path with-environment +output-cap+
exec-result-exit-code -stdout -stderr -timed-out-p -duration-ms
local-environment (make-local-environment task &key directory backend) local-environment-root local-environment-host-path
;; agent-eval/podman: container-environment (make-container-environment task &key directory backend image)

;; adapters
agent-adapter agent-name agent-version agent-config agent-setup agent-run agent-populate-context
agent-context make-agent-context context-input-tokens context-cache-tokens context-output-tokens
context-cost-usd context-turns context-result-text context-status-detail context-transcript
context-metadata context-logs-directory
make-nop-agent make-oracle-agent (make-command-agent &key command env name)
(make-cl-stack-code-agent &key command model max-turns permission-mode append-system-prompt
                               model-params settings env prices version)
cl-stack-code-argv parse-stream-json context-from-stream-json usage-cost-usd

;; grading, trials, runs
(grade-trial task env &key timeout output-file) → grade: reward rewards passed-p source exit-code output timed-out-p duration-ms
(run-trial task agent &key environment-factory attempt directory on-missing-reward) → trial
trial-task-id trial-attempt trial-agent-name trial-agent-version trial-status trial-context trial-grade
trial-reward trial-passed-p trial-timings trial-wall-ms trial-started-at trial-finished-at trial-directory
trial-error trial-transcript make-trial +trial-statuses+ +trial-phases+
(run-agent-eval dataset agent &key attempts environment-factory directory on-unsupported on-missing-reward id label)
  → agent-eval-run (an eval-run): run-id run-label run-agent-name run-agent-config run-attempts run-trials
    run-started-at run-finished-at run-dataset-digest run-task-trials make-agent-eval-run

;; metrics, records, comparison
pass-at-k run-pass-at-k run-accuracy run-totals run-task-stats
trial-plist (stack-eval:eval-report run :format :sexp|:json) save-run load-run
compare-runs run-comparison comparison-rows -wins -ties -losses -mean-delta -token-delta -cost-delta
-wall-delta -only-baseline -only-candidate -baseline-id -candidate-id (comparison-report c &key format)
```

The exact rules are in the E0 contract's file headers (`src/*.lisp`, `src/podman/environment.lisp`), and the Rove tests in `tests/` are the spec.

**Dependencies:** `eval-protocol` ≥ 0.3.0, `compute-protocol` ≥ 0.2.0, `json-protocol` ≥ 0.2.1 + `json-backend-jzon`, `toml-protocol` ≥ 0.1.0 + `toml-backend-tomlet`, `crypto-protocol` ≥ 0.2.0 + `crypto-backend-ironclad`. `agent-eval/podman` adds `compute-backend-podman` (≥ 0.3.0 at run time). Tests use `rove`. All of these are cl-stack libraries; there are no new third-party dependencies.

---

## Slices

### E0: the runner (agent-eval 0.1.0, contracted)

Everything above. The contract has 75 Rove tests: 70 fail against the stubs, 4 (the container lane) are skipped, and 1 checks the given constants. The prerequisite for the container lane is compute-backend-podman 0.3.0 ([#3](https://github.com/egao1980/compute-backend-podman/issues/3)).

### E1: Terminal-Bench through Harbor (`agent-eval-terminal-bench`)

- A Harbor installed agent (Python, run with `uv run --with harbor==0.26.0`) that installs and runs the same `cl-stack-code -p … stream-json` command and fills `AgentContext` from the `result` line. It does this the same way `context-from-stream-json` does, with input tokens including cache. This is the only route to a comparable, publishable number. Until H6 ships a single binary, the installed agent ships a prebuilt cl-stack-code bundle per architecture.
- `import-harbor-job job-dir` → an `agent-eval-run`. Each trial's `result.json` reward, `agent_result` tokens and cost, timings and the `cl-stack-code.jsonl` transcript are mapped, so Harbor runs and local runs can be compared with `compare-runs`.
- Harbor 0.26 also has a generic ACP installed agent. That is an option once ACP-2 and H6 exist.

### E2: Common Lisp corpus (`agent-eval-cl-corpus`), slot

A separate agent is mining candidate tasks from popular **MIT / BSD-licensed** Common Lisp repos' issues and merged PRs. The base commit is the PR's base, the hidden tests come from the fix, and the verifier is `cl-repo test --system …`. This slice fixes the record format, the license allowlist, the gold check (fails at base, passes at fix) and ingestion into TB-format task directories, so E0's loader, environments, grading and comparison apply unchanged. Two rules are fixed now: **upstream references only** (no third-party source or issue text committed), and dependencies come from cl-repo / GHCR (a missing one makes the task `unsupported`, not an agent failure). The details are left to that agent's proposal.

### Later

| Slice | Scope | Needs |
|-------|-------|-------|
| **E3** | A SWE-bench Pro subset through the container environment | E0 + podman 0.3.0 |
| **E4** | Image-first tasks: the Lisp workbench vs bash on the same bug, restart choice, fix-in-frame | H5d, E0 |
| **E5** | A cl-stack-internal corpus in E2's format, from our own merged fixes | E2 |
| later | Parallel trials; docker-compose tasks; a run store in eval-protocol once a second consumer exists ([eval-protocol#3](https://github.com/egao1980/eval-protocol/issues/3)) | — |

---

## Non-goals (E0)

- Building Dockerfiles in the local environment. The local environment is trusted and path-mapped, and does not isolate anything.
- docker-compose tasks and GPUs (`unsupported-task`).
- Running the agent outside its environment, or through cl-stack-code's in-process SDK.
- Parallel trials, a price table, a web view.
