# score-protocol (P2): music notation model, MusicXML and MIDI

**Issues:** follow-ups in [Progress](#progress)
**Status:** SC0 to SC4 **shipped**: [`score-protocol`](https://github.com/egao1980/score-protocol) 0.1.0 (SC0) and 0.2.0 (SC1), [`score-backend-musicxml`](https://github.com/egao1980/score-backend-musicxml) 0.1.0 (SC2), [`midi-protocol`](https://github.com/egao1980/midi-protocol) 0.1.0 (SC3), [`score-backend-midi`](https://github.com/egao1980/score-backend-midi) 0.1.0 (SC4). SC5 [`score-parity`](https://github.com/egao1980/score-parity) 0.1.0 **in progress**: contract [score-parity#3](https://github.com/egao1980/score-parity/pull/3). Decisions made on the way and open follow-ups: [Progress](#progress).
**Repos:** `score-protocol` (nick `stack-score`) · `score-backend-musicxml` · `score-backend-midi` · `midi-protocol` (nick `stack-midi`) · `score-parity`
**Builds on:** [music-theory](music-theory.md), [serdes-protocol](serdes.md), [xml-protocol](xml-protocol.md) + `xml-backend-native`, [binary-protocol](binary-protocol.md), FSet (a `cl-stack-systems` import), [compression-protocol](https://github.com/egao1980/compression-protocol) + `compression-backend-chipz` (`.mxl` zip archives), [sat-protocol](logic.md) (MIDI quantisation)

A canonical, immutable model of a notated score, from lead sheets to choral and small-ensemble scores, together with:
- a closed **edit-operation algebra**;
- **views** (condensed, unfolded, extracted part);
- formats through serdes-protocol: MusicXML 4.0 (`.musicxml`, `.mxl`) and Standard MIDI Files.

Every element carries a **stable id** and optional **provenance and confidence**, so recognisers (OMR, audio transcription, MIDI import) can mark what they guessed. Editors and renderers ([engrave.md](engrave.md)) can then point back at exact elements.

---

## Prior art (intersection, not a clone)

| Source | Took | Left |
|--------|------|------|
| MusicXML 4.0 (W3C Community Group) | Element coverage for lead sheets and choral scores: `<harmony>`, `<lyric>` with `<syllabic>` and verse numbers, `<barline>` repeats and endings, `<direction>`, `id` attributes | Layout and appearance attributes (engraving's job), timewise writing |
| music21 streams (BSD-3) | Offset-in-measure positions, measure maps, `expandRepeats` as a view, voice splitting | Mutable streams; float offsets |
| MuseScore / Dorico edit semantics | Overflowing durations tie across barlines; re-barring re-flows | UI state |
| MNX (W3C draft) | Explicit ids; separating notated content from rendering | It's a draft: watch only |
| Gsharp (LGPL), slippery-chicken (GPL), OpenMusic / OM# (GPL) | **Prior art only** (study, never copy): buffer and editing model; MusicXML mappings | Code (license policy) |
| `midi` CL library (LGPL), cl-smf (Apache-2.0) | Prior art for the SMF event model | Not used: `midi` is LGPL Lisp (not on the [allowlist](../LICENSE-POLICY.md)); cl-smf needs an unpublished dependency |
| mido (Python, MIT) | **Test oracle** (out of process, `uv run --with mido`) for our SMF codec | — |

No reusable CL MusicXML library exists (survey 2026-11).

---

## Locked decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Immutable model** | A score is an FSet-backed value. Every edit returns a new score that shares structure with the old one. | Undo and redo are pointers; concurrent readers are safe; diffs are cheap |
| **Shape** | `score` = metadata + a global **measure map** + `parts`. A part has `staves` and `voices`. Voices hold **events**: `note`, `chord` (simultaneous notes in one voice), `rest`, plus grace notes, which don't count toward rhythm sums. | The MusicXML partwise shape, minus layout |
| **Measure map** | Shared by all parts. Per measure: number label, time and key signature (changes allowed), pickup flag, barline type, repeat start/end, volta numbers, jumps (D.C., D.S., Coda, Fine), rehearsal mark, tempo marks. | Bars are global in a score; key and time changes live in one place |
| **Positions** | `(bar . offset)` with a rational offset in whole notes (music-theory). A pickup is **bar 0** (implicit measure), and the final bar may complete it. `absolute-offset` comes from the measure map. | Exact; pickups are first-class |
| **Stable ids** | Every element (event, note in a chord, lyric, chord symbol, spanner, measure) has an id string, unique in the score and **preserved by every edit and by MusicXML round trips** (written as MusicXML 4.0 `id` attributes). MIDI import mints fresh ids. | Click-to-select, locks, renderer maps, diffs |
| **Provenance and confidence** | Optional on every element: `provenance` (source `:user :musicxml :midi :omr :transcription …`, backend name, page plus bounding box, or audio time range) and `confidence` (0…1). An edit resets the edited element to `:user` / 1. `uncertain-elements score &key below` is the uncertainty report. | Recognisers flag their guesses; review UIs query them |
| **Notes** | Spelled pitch (music-theory), duration (rational) and tuplet ratio; ties as start/stop links by id; accidental display (`:auto` / forced / cautionary); articulations, fermata, breath mark; stem and beam left to the renderer. | Notation content, not layout |
| **Text and expression** | Lyrics: verse number → syllable + syllabic type (single / begin / middle / end) + extender (melisma). Dynamics (point) and hairpins (spanners); slurs (spanners by id); tempo text and metronome marks. | Choral and lead-sheet needs |
| **Chord-symbol track** | Chord symbols (music-theory `chord-symbol`, N.C. allowed) anchored to positions **independently of note onsets** (a chord under a held or rest note is valid). | Lead sheets change chords where the melody doesn't |
| **Edit algebra** | A closed set of operation classes as data. `apply-edit score op` returns the new score plus a **change set** (ids touched). `invert-edit` gives the inverse; ops serialise (for logs) and compose. Ops: `insert-event`, `delete-event`, `set-pitch`, `set-duration` (**overflow ties across the barline**; underflow fills with rests), `set-accidental`, `transpose` (music-theory semantics, chord symbols included), `set-lyric`, `set-chord-symbol`, `add-spanner` / `remove-spanner`, `set-dynamic`, `set-articulation`, `set-key`, `set-time` (re-bars by re-flowing with ties), `insert-measures` / `delete-measures`. | Every UI edit is one replayable value; MBT-friendly |
| **Invariants** | `check-score` reports: voice durations sum to the measure length (or the measure is flagged incomplete); ties connect equal pitches; ids are unique; spanner endpoints exist; lyrics sit on notes. Edits keep them or signal. | Consumers can trust any score they hold |
| **Views** | Pure functions returning a new score plus an id map to the source: `condensed-view` (four voices on two staves, voices 1/2 per staff with stem directions), `unfold` (repeats, voltas and jumps expanded into **playback order**, mapping `(pass . position)` to source ids), `extract-part`. | Rendering, playback and parts don't need their own model |
| **Formats** | Backends register serdes-protocol formats `:musicxml`, `:mxl` and `:midi`. `(serdes:decode src :format :musicxml)` returns a score. `read-score` and `write-score` are conveniences that take a pathname and pick the format from its extension. | The stack's one format mechanism |
| **MusicXML** | Write 4.0 **partwise** only; read partwise and timewise. `.mxl` through compression-protocol's zip archives (`META-INF/container.xml` rootfile; stored and deflate). The LGPL `zip` import is not used (LICENSE-POLICY: no LGPL Lisp at runtime). XML through xml-protocol (XXE-safe: the DOCTYPE is written, never fetched). Layout attributes are dropped on read. | Interop with MuseScore, Dorico, Sibelius, Finale |
| **Voice splitting** | Reading a staff that holds two voices (hymnal layout: `<voice>` 1/2, or shared-stem chords) gives separate logical voices. Option `:split-voices :auto` decides from `<voice>`, stem direction and pitch order, and records low confidence where it had to guess. | Hymnals and choral reductions |
| **Validation** | The MusicXML 4.0 XSD needs `xs:import`, `xs:group`, `xs:attributeGroup` and `simpleContent`, which schema-protocol-xsd doesn't support yet (gap to be filed). Until then tests validate with `xmllint` when it's installed (out of process). | Stay honest about schema coverage |
| **midi-protocol** | A MIDI 1.0 **event model plus an SMF codec** on binary-protocol: header (format 0/1, ticks per quarter; SMPTE division rejected in wave 1), tracks, delta times, running status, channel messages, meta events (tempo, time and key signature, text, lyric `FF 05`, marker, track name, end of track), sysex passthrough. **Files only**: real-time ports are a non-goal. | The codec has nothing score-specific; other consumers reuse it |
| **MIDI export** | One track and channel per voice, program per part, tempo map, unfolded repeats, lyrics as `FF 05`, chord symbols as text events with a documented prefix, velocity from dynamics. `:mix` options set per-voice velocity, volume (CC7) and pan, which is how practice files emphasise one voice. | Playback and practice files |
| **MIDI import** | Tempo, time and key meta events build the measure map. **Quantisation** picks a grid per beat (straight vs triplet subdivisions): a selection problem solved with `sat-protocol:minimize` (cost = onset deviation + notation complexity). Spelling uses music-theory with a key hint. The track → part mapping is given or guessed (default melody: the highest monophonic track). Every guess carries confidence and provenance `:midi`. | Imported performances are unquantised; selection goes through the logic family |
| **Hints** | Importers accept `:key`, `:meter` and `:tempo` hints. A hint that disagrees with the content gives a low-confidence flag, never a silent override. | Shared with transcription and OMR ([omr.md](omr.md)) |

---

## Repo layout

| Repo / system | Role |
|---------------|------|
| `score-protocol` | Model, ids, provenance, measure map, positions, the edit algebra, invariants, views, serdes registration helpers, `read-score` / `write-score` |
| `score-backend-musicxml` | `:musicxml` and `:mxl` read and write; voice splitting; MusicXML ↔ model mapping tables |
| `midi-protocol` | MIDI 1.0 messages, SMF read and write (`stack-midi`) |
| `score-backend-midi` | `:midi` export and import (quantisation, spelling, track mapping) |
| `score-parity` | Public-domain corpus (re-encoded by us, MIT, with provenance), round-trip and cross-format suites, external oracles (MuseScore CLI, mido). It hard-depends only on score-protocol and soft-loads the backends, as doc-extract-parity does. |

---

## Protocol surface

```lisp
(defclass score () ())          ; immutable; accessors below
(defgeneric score-parts (score))           (defgeneric score-measure-map (score))
(defgeneric score-chord-symbols (score))   (defgeneric score-metadata (score))
(defgeneric find-element (score id))       (defgeneric element-position (score id))
(defgeneric element-provenance (element))  (defgeneric element-confidence (element))
(defun uncertain-elements (score &key (below 0.8)))

(defstruct measure-info number time key pickup-p barline repeat volta jump
           rehearsal tempo)
(defclass note-event () ())  (defclass chord-event () ())  (defclass rest-event () ())
(defclass lyric () ())  (defclass chord-symbol-anchor () ())  (defclass spanner () ())

(defclass edit-operation () ())            ; insert-event, set-pitch, set-duration, …
(defgeneric apply-edit (score op))         ; → new score, change-set
(defgeneric invert-edit (score op))
(defun check-score (score))                ; → list of score-issue

(defun condensed-view (score &key voices))
(defun unfold (score))                     ; → score, playback-map
(defun extract-part (score part-id))

(defun read-score (source &key format split-voices hints))
(defun write-score (score destination &key format))

;; midi-protocol
(defstruct smf format division tracks)
(defstruct midi-event delta status data)   ; + meta-event, sysex-event
(defun read-smf (source))  (defun write-smf (smf destination))
```

### Conditions

```text
score-error (error)
├── invalid-edit                 ; slots: op, reason — restarts skip-edit, use-value
├── score-invariant-violation    ; slots: issues
├── unknown-element              ; slots: id
└── score-format-error           ; slots: format, position, cause
    ├── musicxml-unsupported     ; element outside the mapping — restart skip-element
    └── smf-malformed            ; restart use-partial-smf
score-warning (warning)
├── lossy-conversion             ; e.g. ids lost writing MIDI
└── low-confidence-guess         ; slots: element-id, what, confidence — muffled by default
```

---

## Slices

### SC0: model, ids, measure map, positions (score-protocol 0.1.0)

**Given:** package and exports, classes, conditions. **Stubbed:** constructors, accessors over FSet, id minting, `find-element`, `absolute-offset`, `check-score`, `uncertain-elements`. **Fixtures:** 10 hand-built scores (a pickup, a 6/8 carol, repeats with voltas, three-verse lyrics, a mid-score key change, chord symbols under rests). **Tests:** invariants catch each class of bad score; ids are unique and stable under copies; pickup arithmetic; `uncertain-elements` thresholds.

### SC1: edit algebra and views (score-protocol 0.2.0)

**Stubbed:** every op's `apply-edit` / `invert-edit`; `condensed-view`, `unfold`, `extract-part`. **Tests:**
- Property tests over random op sequences: `invert` ∘ `apply` = id; invariants hold after every op; untouched ids are unchanged (change sets are exact).
- Overflow ties across barlines; re-barring 4/4 → 3/4.
- Transposition respells chord symbols.
- `unfold` order for D.S. al Coda; the condensed view's voice and stem mapping.

### SC2: MusicXML (score-backend-musicxml 0.1.0)

**Stubbed:** reader, writer, `.mxl` container, voice splitting. **Fixtures:** the SC0 scores; 20 public-domain pieces re-encoded by us (lead sheets with chord symbols and lyrics, four-part hymns on two staves); MusicXML files exported by MuseScore 4 for the same pieces (generated by us; provenance recorded). **Tests:**
- Round trip read → write → read is equal under model equality, with ids preserved.
- Hymnal voice splitting matches hand-split versions.
- `.mxl` read and write.
- Unknown elements signal `musicxml-unsupported`, and its restart works.
- `xmllint --schema` passes when available.

### SC3: SMF codec (midi-protocol 0.1.0)

**Stubbed:** `read-smf`, `write-smf`, running status, meta events. **Fixtures:** SMF files generated with mido (MIT) by a committed script; malformed files (truncated, bad lengths). **Tests:** byte-exact round trip; a mido cross-read (out of process, skipped when `uv` is absent); malformed input → `smf-malformed` with `use-partial-smf`.

### SC4: score ↔ MIDI (score-backend-midi 0.1.0)

**Stubbed:** export (tracks, channels, tempo map, unfold, lyrics, chord text, `:mix`), import (measure map, quantisation via sat-protocol, spelling, track mapping, confidence). **Fixtures:** the SC2 corpus; 10 unquantised human performances of corpus melodies (recorded, MIT) with the notated ground truth. **Tests:**
- Export → import equals the source in pitches, onsets and lyrics for quantised content.
- Performances recover the notated rhythm within a flagged-uncertainty budget.
- A key hint improves spelling.
- `:mix` velocity and volume per voice.

### SC5: score-parity

The corpus, the shape matrix across formats (`print-matrix`), and the MuseScore CLI oracle: `mscore` opens every exported MusicXML and MIDI file, and its re-export is semantically equal. Out of process, skipped when absent, and run in a nightly job.

---

## Progress

### Shipped

| Slice | Package | Notes |
|-------|---------|-------|
| SC0 | score-protocol 0.1.0 | model, ids, measure map, positions, `check-score` |
| SC1 | score-protocol 0.2.0 | edit algebra, `condensed-view`, `unfold`, `extract-part` |
| SC2 | score-backend-musicxml 0.1.0 | MusicXML 4.0 partwise read and write, `.mxl`, hymnal voice splitting, serdes formats `:musicxml` and `:mxl` |
| SC3 | midi-protocol 0.1.0 | MIDI 1.0 events and the SMF codec |
| SC4 | score-backend-midi 0.1.0 | export (tracks per voice, tempo map, unfolded repeats, lyrics, chord text, rehearsal mixes) and import (measure map, quantisation, spelling, track mapping, confidence) |
| SC5 | score-parity 0.1.0 | **in progress**: contract [score-parity#3](https://github.com/egao1980/score-parity/pull/3). 34 MusicXML files of 30 public-domain tunes; checks for the MusicXML and `.mxl` round trips, the hymnal split, MIDI round trips with and without unfolding, and the MuseScore and XSD oracles |

### Decisions made in SC1 to SC4

| Decision | Choice | Slice |
|----------|--------|-------|
| **Endings after a jump** | Once a D.C. or D.S. is taken, `unfold` plays only the last ending of each group, and repeats are not taken again | SC1 |
| **`.mxl` archives** | Through compression-protocol's zip archives (`compression-backend-chipz` inflates). Every entry is stored with no timestamp, so the bytes depend on the score only. The LGPL `zip` import is not used. | SC2 |
| **MIDI quantisation** | The per-beat grid (straight or tuplet subdivisions) is chosen by `sat-protocol:minimize`: cost is onset deviation plus notation complexity | SC4 |
| **Ids of built scores** | Readers whose ties and spanners name elements not minted yet (MusicXML reading, voice splitting, MIDI import) build the score in several passes and keep the ids `make-score` mints, until a builder with forward references lands ([score-protocol#8](https://github.com/egao1980/score-protocol/issues/8)) | SC2, SC4 |

### Follow-ups

- [score-protocol#4](https://github.com/egao1980/score-protocol/issues/4): two `unfold` wordings: the header's step 1 should say that only the last ending is played after a jump, and the pass of an ending's measures.
- [score-protocol#6](https://github.com/egao1980/score-protocol/issues/6): SC1 follow-ups (the undocumented `unfold` step limit, the op named in conditions after a REFLOW restart, cost per edit).
- [score-protocol#7](https://github.com/egao1980/score-protocol/issues/7): `invert-edit` turns small edits into a restore of the whole score.
- [score-protocol#8](https://github.com/egao1980/score-protocol/issues/8): a builder with forward references for tie and spanner ends.
- [score-protocol#5](https://github.com/egao1980/score-protocol/issues/5) (`logic-migration`): move the `unfold` navigation rules to the logic family.
- [score-backend-midi#2](https://github.com/egao1980/score-backend-midi/issues/2): SC4 contract follow-ups (serdes `:midi`, recorded performances, chord guesses from accompaniment tracks, hairpins and articulations in velocity).
- [score-backend-midi#3](https://github.com/egao1980/score-backend-midi/issues/3): a last note that snaps onto the end of the last bar; register `:midi` with serdes-protocol.
- [score-backend-midi#4](https://github.com/egao1980/score-backend-midi/issues/4): the spelling confidence flags chromatic notes that a spelling rule already decided.
- [score-backend-musicxml#2](https://github.com/egao1980/score-backend-musicxml/issues/2): run the XSD validation rows in CI (fetch the MusicXML 4.0 schema).
- [score-backend-musicxml#4](https://github.com/egao1980/score-backend-musicxml/issues/4): the hymnal split leaves a measure of unisons in one voice (found building the SC5 corpus).
- [score-parity#1](https://github.com/egao1980/score-parity/issues/1): the nightly job with MuseScore and the XSD; [score-parity#2](https://github.com/egao1980/score-parity/issues/2): the MuseScore oracle for exported MIDI files.

---

## Non-goals (wave 1)

- Engraving, layout and page formatting ([engrave.md](engrave.md))
- MEI, ABC, LilyPond and MNX import or export
- Real-time MIDI, MIDI 2.0 / UMP, SMPTE time division
- Tablature, percussion maps, figured bass
- Audio ([audio.md](audio.md))
