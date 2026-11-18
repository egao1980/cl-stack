# Tutorials

Step-by-step walkthroughs that build one thing end to end. For short task recipes, see the [cookbooks](../cookbooks/README.md).

| Tutorial | Builds | Runnable code |
|----------|--------|---------------|
| [An agent that survives long runs](agent-harness.md) | `ai-agent-protocol` **0.6.0** agent: retries, compaction (agent and API side), max-steps wrap-up, typed tool failures, permissions, background subagents, `AGENTS.md` discovery | [`examples/agents/`](../../examples/agents/) · `cl-repo test --system cl-stack/examples` |
| [A token-thrifty lisp-mcp session](lisp-mcp-session.md) | fix a failing test via `lisp-mcp` **0.4.1**: terse output, stored long output, edit + compile, background jobs | MCP transcript |
