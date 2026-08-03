# Test corpus layout

Hub-owned license-clean fixtures for stack libraries (HTTP, WS, …).
Sibling repos may vendor a copy or point here via git submodule / CI checkout.

## Layout

```
tests/corpus/
  README.md                 ← this file
  PROVENANCE.md             ← required row for every non-original file
  <domain>/                 ← http | ws | …
    <slice>/                ← short kebab name (e.g. redirect-policy)
      *                     ← vectors (JSON, Lisp sexps, binary, …)
```

Rules:

1. **Prefer regenerate under MIT** over copying upstream test sources.
2. Every path that is not original MIT code/data needs a **PROVENANCE.md** row
   (source URL, commit/tag, SPDX). See [docs/LICENSE-POLICY.md](../../docs/LICENSE-POLICY.md).
3. Allowlist only: MIT, BSD-2/3, Apache-2.0, Unlicense, 0BSD, CC0.
   **No GPL / AGPL / LGPL** corpus material.
4. Keep slices small and purposeful; one behavioral area per directory.
5. Name files so a reader test can discover them without a registry
   (`vectors.lisp`, `manifest.json`, stable extensions).
6. CI: `python3 scripts/check-corpus-license.py` (provenance + license markers).
   False-positive process: [docs/LICENSE-POLICY.md](../../docs/LICENSE-POLICY.md).

## Adding a slice

1. Create `tests/corpus/<domain>/<slice>/`.
2. Drop vectors + a one-line note in that directory if non-obvious.
3. Update `PROVENANCE.md` (use `original MIT` for synthetic data).
4. Extend `cl-stack/corpus-smoke` (or the owning lib’s Rove suite) to read them.
5. PR links `Refs egao1980/cl-stack#32` (or parent epic) as appropriate.
