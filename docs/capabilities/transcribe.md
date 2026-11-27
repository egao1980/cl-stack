# transcribe-protocol (P2): monophonic audio-to-notes transcription

**Issues:** [#425](https://github.com/egao1980/cl-stack/issues/425) (the two repos and what the protocol returns) · follow-ups in [Progress](#progress)
**Status:** T0 [`transcribe-protocol`](https://github.com/egao1980/transcribe-protocol) 0.1.0 **implemented and published**: [transcribe-protocol#1](https://github.com/egao1980/transcribe-protocol/pull/1) (merged; team-solve, 225 tests, 804 assertions, green on ubuntu, macOS and Windows; contract history: `%t0-pending` stubs, a team-solve run implements it). T1 [`transcribe-backend-pyin`](https://github.com/egao1980/transcribe-backend-pyin) 0.1.0 **implemented and published**: [transcribe-backend-pyin#1](https://github.com/egao1980/transcribe-backend-pyin/pull/1) (merged; team-solve, 77 tests, 332 assertions, green on ubuntu, macOS and Windows; a 3-minute take in 1.95 s, 1.66x the YIN baseline). T2 and T3: later.
**Repos:** `transcribe-protocol` (nick `stack-transcribe`), with the system `transcribe-protocol/testing` (nick `stack-transcribe/testing`) · `transcribe-backend-pyin` (T1) · `transcribe-backend-basic-pitch` (T2, later) · `transcribe-parity` (T3, later)
**Builds on:** [audio-protocol](audio.md) 0.2.0 (AU0 `pcm-buffer`, `read-wav`, `resample`; AU3 `audio-protocol/dsp`: `downmix`, `peak`, `rms`, `frame-count`, `yin-cmndf`) · [music-theory](music-theory.md) 0.6.0 (MT5 `fit-key`, `key-fit`; `parse-key`, `parse-meter`, `tempo`) · consumer: [score-backend-midi](score.md) 0.2.0 SC6 `notes-to-score` (no dependency)

Monophonic transcription: one sung or hummed line in, notes out. The first consumer is the transcription of sung or hummed melodies, a recorded take at 16 kHz mono. A take becomes:
- note events, with onset and offset in seconds and pitch as a MIDI number with cents;
- the f0 contour with voicing;
- the take's tuning offset and its drift per phrase;
- a key fit that says how the take relates to an expected key.

score-backend-midi's `notes-to-score` then turns the notes into a score.

This brief replaces the transcription part of the [omr.md](omr.md) outline.

---

## Problem

Sung melodies are the most natural input there is, and the hardest to read:
- singers are rarely at A440;
- unaccompanied singers drift, usually flat, a few cents per phrase;
- vibrato swings the pitch by up to a semitone;
- breath noise, room hum and phone microphones blur the onsets.

A transcriber must therefore give more than rounded MIDI notes. It must give the measurements behind them, so that the next step (quantisation and spelling in SC6, a review screen) can tell a wrong note from a singer who went flat.

The stack has the pieces: audio-protocol reads and resamples audio, and its DSP package computes YIN's d′ through the FFT (AU3); music-theory fits a key together with a global tuning offset (MT5); score-backend-midi turns timed notes into a score (SC6). There is no protocol joining them, no shared rule for tuning and drift, and no way to grade a transcriber.

Two repos ([#425](https://github.com/egao1980/cl-stack/issues/425)):
- **transcribe-protocol** owns the contract, the result model, the steps every backend would otherwise repeat (audio preparation, tuning, drift, the key fit), the evaluation, and test synthesis;
- **transcribe-backend-pyin** (T1) is the first real backend.

---

## Prior art (intersection, not a clone)

| Source | Took | Left |
|--------|------|------|
| **YIN** (de Cheveigné and Kawahara 2002, *JASA* 111(4), 1917–1930) | The difference function d and its cumulative mean normalization d′ (already AU3's `yin-cmndf`), the absolute threshold (step 4), parabolic interpolation (step 5). The T0 baseline is steps 1–5 | Step 6 (best local estimate); the fallback to the global minimum when nothing is under the threshold (the baseline calls such a frame unvoiced) |
| **pYIN** (Mauch and Dixon 2014, "pYIN: a fundamental frequency estimator using probabilistic threshold distributions", ICASSP 2014, 659–663) | T1: a distribution of thresholds (a beta prior over 100 thresholds, the first trough below each, p_a = 0.01 to the deepest when none is), candidate f0s with probabilities, a hidden Markov model over pitch and voicing decoded by Viterbi (25 bins a frame at 5.8 ms, rescaled), voicing probabilities | The Vamp plugin's code (c4dm/pyin, GPL-2.0): study only |
| **Tony** (Mauch et al. 2015, "Computer-aided melody note transcription using the Tony software: accuracy and efficiency", TENOR 2015) | T1: note segmentation by an HMM over pYIN's pitch track (attack and stable states on a 1/3-semitone grid, the prior pitched probability 0.7 at weight 1/2, a minimum distance between notes, 0.1 s as the shortest note), splitting a repeated pitch where the level rises, the note-level evaluation of sung melodies. Simplified in T1: one silent state, the attack as a chain that sets the minimum length, legato changes, a dip cue | The application and its code (GPL-2.0) |
| **librosa** 0.10 (ISC) `pyin`, `pitch_tuning`, `estimate_tuning` | Conventions: pyin's defaults (β = (2, 18), 100 thresholds, 10-cent pitch bins, switch probability 0.01, a maximum transition rate of 35.92 octaves a second), a tuning offset read as a deviation in fractions of a semitone around A440 | Its histogram-mode tuning estimate (T0 uses a circular weighted median on a 1-cent grid, exact); its frames of 2048 at 22.05 kHz (T1: 1024 at 16 kHz, the same 64 ms); its Boltzmann prior over trough ranks (the Vamp code's, not the paper's) |
| **Basic Pitch** (Bittner et al. 2022, "A lightweight instrument-agnostic model for polyphonic note transcription and multipitch estimation", ICASSP 2022; spotify/basic-pitch, Apache-2.0) | T2: a second opinion and a parity oracle; its notes (onset, offset, MIDI pitch, amplitude, pitch bends) map onto `note-event` | In-process ONNX or TensorFlow; it runs out of process, in a container |
| **mir_eval** 0.8 (Raffel et al., ISMIR 2014; MIT) `transcription.precision_recall_f1_overlap`, `match_notes` | The note metrics and their defaults: onset ±50 ms, pitch ±50 cents, offsets within max(0.2 · duration, 50 ms), `<=` unless strict, **maximum bipartite matching** (Hopcroft–Karp in `util._bipartite_match`), zeros when either side is empty | The rounding of time distances to 4 decimals (T0's arithmetic is exact); the average overlap ratio; β ≠ 1 |
| MIREX note tracking (the Su dataset, 2015) | The criteria mir_eval adopts | Its greedy matching and its 2-decimal time truncation (mir_eval documents both differences) |
| **Vocadito** (Bittner, Pasalo, Bosch, Meseguer-Brocal and Rubinstein 2021, arXiv:2110.05580) | T3: 40 short excerpts of solo singing in seven languages, f0 and two note annotations each. Its two annotators agree poorly, so its scores have a ceiling | Vendoring (below) |
| CREPE (Kim et al. 2018; marl/crepe, MIT) | A later neural f0 option, behind the same `detect-notes` | Not planned |
| aubio (GPL-3), Melodia (non-commercial licence) | Study only | Code (licence policy) |

**Vocadito's licence.** Zenodo record [10.5281/zenodo.5578807](https://doi.org/10.5281/zenodo.5578807) (v3, 2021-10-11) is one file, `vocadito.zip`: 58.5 MB, MD5 `dea40fd18f14d899643c4ba221b33a46`. It is licensed CC BY 4.0. CC BY allows redistribution with attribution, but it is not on the stack's corpus allowlist ([LICENSE-POLICY.md](../LICENSE-POLICY.md): MIT, BSD, Apache-2.0, Unlicense, 0BSD, CC0, public domain). So the clips are **not redistributed**: T3 fetches the archive at test time, checks a pinned SHA-256 (recorded when T3 starts) and caches it. Without the network, T3 skips. Every committed fixture is synthetic, from `transcribe-protocol/testing`, with exact ground truth.

---

## Locked decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Division of work** | A backend subclasses `transcriber` and writes **`detect-notes transcriber audio hints` → (values notes contour)**, notes as sung. The method on `transcriber` of the generic function `transcribe` does the rest, in order: check the audio, `normalize-hints`, `prepare-audio`, `detect-notes`, check the contour, `finish-transcription`. Callers may add `:around` methods on `transcribe` (caching, timing). | Tuning, drift and the key fit are computed one way for every backend, so backends compare on what they detect |
| **Audio** | An audio-protocol `pcm-buffer`, of any rate and channel count. `prepare-audio` does the following, and the backend's method receives the result: <br>1. A buffer of several channels becomes their mean (`downmix`). <br>2. It is checked for length and silence (below). <br>3. It is resampled to `(transcriber-sample-rate transcriber)`, by default **16000**, with audio-protocol's `resample`. NIL keeps the audio's own rate (the oracle uses NIL). | One documented resampler, in the protocol. A stereo phone recording of one voice is fine as its mean |
| **Too short, silent** | Duration below `*minimum-duration*` (1/10 s) → `audio-too-short`. Then the downmix's peak below `(db-to-gain *silence-peak-db*)` (−60 dBFS) → `silent-audio`. A peak of exactly that level is not silent. Each is signalled with `error` inside two CLHS restarts: <br>• **`continue`** waives that check (the next one still runs); <br>• **`use-value`** takes another buffer, checked again from the start. <br>Backends cope with any length, 0 frames included. | Simple numeric thresholds (special variables), not rules. Silence through `continue` gives a transcription with no notes |
| **Hints** | A plist of `:key` (a music-theory KEY, or a string `parse-key` reads), `:meter` (a METER, or a string for `parse-meter`), `:tempo` (a TEMPO, or a positive real taken as quarter-note bpm) and `:pitch-range (low high)` (MIDI reals, 0 ≤ low < high < 128; default **(36 84)**, C2 to C6). `normalize-hints` returns them in that order as music-theory values, the types SC6's `notes-to-score` takes. An unknown key or a wrong value signals `invalid-hint` (KEY, VALUE, REASON, and CAUSE: the music-theory condition of a failed parse), with `use-value` (another value, checked again; not offered for an unknown key) and `continue` (drop the hint). Of a key given twice, the first counts. | Hints are what the caller knows about the music; backend options are initargs. A typo such as `:tempi` is an error, not silence |
| **Time** | Onset and offset in seconds, **exact rationals**, 0 ≤ onset < offset. Contour frame i sits at **i · hop / rate** (centred, audio-protocol's `:center`). The frame rate is **reported** (`contour-frame-rate` = rate / hop), not fixed: 125 frames a second for the YIN baseline and for T1. | Frame times are exact, and SC6 and the metrics compute with rationals |
| **Note event** | `note-event`: onset, offset, **pitch** (a double MIDI number with cents in its fraction, 0 ≤ p < 128) and **confidence** (a double, 0 to 1). Immutable, compared with `equalp`. A backend's notes form **one line**: in onset order, none overlapping, touching allowed (`check-notes`, else `invalid-notes` with the index). Nothing is sorted or cut silently. `note-plists` gives SC6's event plists. | Monophony is the contract, not a cleanup step. A pitch from an f0 is a logarithm, and its exact rational feeds `fit-key` |
| **Contour** | `f0-contour`: sample rate, hop, f0 per frame (Hz as a double, or **NIL when unvoiced**) and the voicing probability per frame (a double vector, 0 to 1). `notes-contour` gives the contour a perfect tracker would report for given notes. | The raw evidence for review screens and for parity with other trackers |
| **Tuning offset** | `estimate-tuning`: the integer g in −50 … 49 cents above A440 that minimizes Σ duration · \|r(q, g)\|. Here r(q, m) = x − 100·⌊x/100 + ½⌋ with x = 100q − m, the residual of pitch q from the nearest semitone of a tuning m cents sharp. This is a **duration-weighted circular median**. Ties go to the first in `+tuning-offsets+`: 0 −1 1 … −49 49 −50, the smallest correction and then the flatter one (MT5's order). Arithmetic is exact, on the pitches' rationals. | A median ignores a few notes sung out of tune. Being circular, it has no wrap-around problem near a half semitone. As in MT5, a take more than 50 cents off reads a semitone away |
| **Phrases** | `segment-phrases`: a new phrase starts at a rest of at least **`+phrase-gap+` (1/4 s)**, a breath. Phrases of fewer than **`+min-phrase-notes+` (3)** notes join the phrase before them, or the one after them at the start of the take. | One or two notes are too little evidence for a drift of their own |
| **Drift** | **One offset per phrase** (`estimate-drift` → `phrase-drift`: start, end, first, count, cents). The cents are the phrase's own circular median, searched in the window **g − 50 … g + 49**, so the drift is −50 … 49 relative to the take's tuning and **the window is its clamp**. `remove-drift notes drift :tuning g` subtracts (g + cents) / 100 from each pitch, exactly, rounding once. A smooth drift curve was not chosen: it would need a model of its own, and per-phrase steps are what a singer's re-tuning at a breath looks like. | Synthetic takes that drift by up to 64 cents over 8 s come back within ±20 cents of their written pitches (tested) |
| **Key fit** | Computed by the **protocol**, never by a backend: in `finish-transcription`, music-theory's `fit-key` over the corrected notes as `(pitch . duration)` conses, with `:hint` the key hint. Its `no-key-evidence` (no notes, or twelve equal chromatic notes) is answered with `use-value` NIL, so `key-fit` is NIL. With a hint, `key-fit-hint-distance` is −1 for a take a semitone flat of it and 0 for one 30 cents flat. The fit's own offset is what remains after the correction, about 0. | One fit for every backend; the tuning has already been removed. Whether to keep the hint or move to the sung key is the caller's policy (MT5) |
| **Result** | `transcription`: <br>• `notes`: corrected, at A440; <br>• `raw-notes`: as sung; <br>• `contour`; <br>• `tuning-offset` (g); <br>• `drift` (a vector of `phrase-drift`); <br>• `key-fit`; <br>• `hints`: normalized and echoed; <br>• `backend`: `transcriber-info`, a plist, by default `(:name "<class>")`; <br>• `duration`: of the buffer prepared, rational. | Everything the review step and SC6 need, the measurements included |
| **Evaluation** | `note-f-measure reference estimate &key (onset-tolerance 1/20) (pitch-tolerance-cents 50) offset-ratio (offset-min-tolerance 1/20) strict` → (values f precision recall matched), mir_eval's rules (above). OFFSET-RATIO NIL ignores offsets; 1/5 is mir_eval's default with offsets. **Matching rule: a maximum bipartite matching** (as mir_eval; a greedy one can leave a matchable note unmatched). The values are exact rationals, with no rounding at the tolerance. `match-notes` returns a maximum matching as (i . j) pairs; which maximum matching is not specified. Either side may be polyphonic. | Public and generic, for backend tests and T3 parity |
| **Test support** | The system `transcribe-protocol/testing`: <br>• `make-park-miller` (the minimal standard generator, seeded, integer arithmetic); <br>• `melody-notes` (a list of (pitch duration) with NIL rests); <br>• `detune-notes` (offset, a linear drift at each note's midpoint, seeded jitter); <br>• `synthesize-notes` → a mono `pcm-buffer`, with a sine or a **band-limited** sawtooth (partials below 0.45 of the rate), a global offset in cents, a linear drift in cents per second from time 0, sinusoidal vibrato (rate and peak depth in cents) from each onset, linear attack and release, and seeded uniform noise. Each note is its own oscillator, starting at phase 0. | Backends test against known notes on every implementation; no fixture files |
| **Reference backends** | **`oracle-transcriber`** (`:notes`) returns its notes and their `notes-contour` (hop 256), whatever the audio, at the audio's own rate, for consumers' tests. <br>**`yin-transcriber`**, a plain YIN baseline: <br>• frames of 1024 every 128 at 16 kHz, each integration window centred on its frame time; <br>• `yin-cmndf`, the first dip below 1/5 within the pitch range, then its bottom and parabolic interpolation; <br>• a level gate 40 dB under the loudest frame; <br>• notes as runs of voiced frames within 3/4 semitone of the run's running median, at least 60 ms long, pitch the median. <br>It documents its limits: vibrato deeper than about 50 cents splits notes, and a repeated pitch without a rest merges. | The oracle tests consumers; the baseline shows the protocol end to end and gives T1 a floor. Smoothing is pYIN's job |
| **Conditions** | See [below](#conditions). CLHS restarts only (`use-value`, `continue`, and `store-value` from `check-type`). `invalid-notes` and `transcriber-error` mark bugs and have no restart. | [conditions.md](conditions.md): the protocol owns the types, backends signal them |
| **No rules** | The thresholds (silence level, minimum duration, phrase gap, minimum phrase size, the YIN baseline's parameters) are plain numbers in special variables, constants and initargs. There is no rule table and no precedence logic. | Logic-family policy ([logic.md](logic.md)) applies to rules; these are measurements |
| **Dependencies** | audio-protocol 0.2.0 and music-theory 0.6.0; tests use rove 0.11.1. No third-party DSP. score-backend-midi is a consumer, not a dependency. | Own stack first |

---

## Repo layout

| Repo / system | Role |
|---------------|------|
| `transcribe-protocol` | The protocol (T0): the model, hints, tuning and drift, `finish-transcription`, `transcribe`, the evaluation, `oracle-transcriber`, `yin-transcriber` |
| `transcribe-protocol/testing` | Melodies, detuned takes, synthesis; used by this repo's tests and by every backend's |
| `transcribe-backend-pyin` | T1: `pyin-transcriber`, its steps exported (`pitch-candidates`, `decode-pitch`, `pyin-contour`, `onset-frames`, `smooth-pitches`, `contour-notes`) |
| `transcribe-backend-basic-pitch` | T2 (later): Basic Pitch out of process, in a container (compute-backend-podman) |
| `transcribe-parity` | T3 (later): Vocadito (fetched) and synthetic renders, a matrix of F-measures per backend |

---

## Protocol surface (T0)

```lisp
;; package transcribe-protocol (stack-transcribe)
(defstruct note-event onset offset pitch confidence)           ; MAKE-NOTE-EVENT checks
(defun note-event-duration (note))  (defun midi-to-hz (m))  (defun hz-to-midi (f))
(defun check-notes (notes))         (defun note-plists (notes)) ; one line; SC6 event plists

(defstruct f0-contour sample-rate hop f0 voicing)              ; MAKE-F0-CONTOUR checks
(defun contour-length (c))  (defun contour-frame-time (c i))  (defun contour-frame-rate (c))
(defun notes-contour (notes &key (sample-rate 16000) (hop 256) frames))

(defparameter +hint-keys+ '(:key :meter :tempo :pitch-range))
(defparameter +default-pitch-range+ '(36 84))
(defun normalize-hints (hints))  (defun hint-pitch-range (hints))

(defparameter +tuning-offsets+ '(0 -1 1 ... -49 49 -50))
(defparameter +phrase-gap+ 1/4)  (defparameter +min-phrase-notes+ 3)
(defstruct phrase-drift start end first count cents)            ; MAKE-PHRASE-DRIFT checks
(defun estimate-tuning (notes))                                 ; → -50 .. 49
(defun segment-phrases (notes &key gap min-notes))              ; → ((first . end) ...)
(defun estimate-drift (notes &key tuning gap min-notes))        ; → #(phrase-drift ...)
(defun remove-drift (notes drift &key (tuning 0)))              ; → fresh notes

(defstruct transcription notes raw-notes contour tuning-offset drift key-fit
                         hints backend duration)
(defun finish-transcription (notes contour &key hints backend duration
                                                phrase-gap min-phrase-notes))

(defconstant +default-sample-rate+ 16000)
(defvar *minimum-duration* 1/10)  (defvar *silence-peak-db* -60)
(defclass transcriber () ())
(defgeneric transcribe (transcriber audio &key hints))          ; → transcription
(defgeneric detect-notes (transcriber audio hints))             ; backends: → notes, contour
(defgeneric transcriber-sample-rate (transcriber))              ; default 16000; NIL = own rate
(defgeneric transcriber-info (transcriber))                     ; default (:name "<class>")
(defun prepare-audio (transcriber audio))                       ; → buffer, duration

(defun match-notes (reference estimate &key onset-tolerance pitch-tolerance-cents
                                            offset-ratio offset-min-tolerance strict))
(defun note-f-measure (reference estimate &key ...))            ; → f precision recall matched

(defclass oracle-transcriber (transcriber) ())                  ; :notes
(defclass yin-transcriber (transcriber) ())                     ; :frame-size :hop :threshold
                                                                ; :gate-db :jump :min-duration
;; package transcribe-protocol/testing (stack-transcribe/testing)
(defun make-park-miller (seed))  (defun melody-notes (spec &key start confidence))
(defun detune-notes (notes &key offset drift-rate jitter seed))
(defparameter +synthesis-waveforms+ '(:sine :sawtooth))
(defun synthesize-notes (notes &key sample-rate waveform amplitude offset drift-rate
                                    vibrato-rate vibrato-depth attack release noise seed
                                    duration))
```

### Conditions

```text
transcribe-error (error)          reason
├── unusable-audio                duration — restarts continue, use-value (PREPARE-AUDIO)
│   ├── audio-too-short           minimum
│   └── silent-audio              peak
├── invalid-hint                  key, value, cause — restarts use-value, continue (NORMALIZE-HINTS)
├── invalid-notes                 index (not a note event, out of order, overlapping)
└── transcriber-error             transcriber (no DETECT-NOTES method, not a contour, bad rate)
```

Argument checks are `check-type` (`type-error` with `store-value`). music-theory's `no-key-evidence` is answered inside `finish-transcription`. Backends define no tree of their own.

---

## Slices

### T0: the protocol (transcribe-protocol 0.1.0)

**Contract:** [transcribe-protocol#1](https://github.com/egao1980/transcribe-protocol/pull/1) (draft).

**Given:**
- the package and its exports;
- the conditions;
- `note-event`, `f0-contour`, `phrase-drift` and `transcription` with their checking constructors;
- `midi-to-hz` and `hz-to-midi`;
- the data;
- `transcriber` with `transcriber-sample-rate` and `transcriber-info`;
- the two backend classes with their initarg checks.

**Stubbed:**
- `check-notes`, `note-plists`, `notes-contour`;
- `normalize-hints`, `hint-pitch-range`;
- `estimate-tuning`, `segment-phrases`, `estimate-drift`, `remove-drift`, `finish-transcription`;
- `transcribe`, the default `detect-notes`, `prepare-audio`;
- `match-notes`, `note-f-measure`;
- the oracle's note check and both backends' `detect-notes`;
- all of `transcribe-protocol/testing`.

**Fixtures:** none. Every take is synthesized in the tests.

**Tests** (225, Rove with `deftest-parametrize`):
- Model types and checks, and the conditions (given).
- `check-notes` cases with indices, `note-plists`, `notes-contour` frame by frame.
- Hints: every type and error, both restarts, re-checking, CAUSE.
- Tuning: hand-computed costs, the weighted median, ties, the wrap-around at a half semitone, exact boundaries.
- Phrases: splits, the exact 1/4 s gap, merging forward and back.
- Drift: values, the window and its clamp.
- `remove-drift`: exact subtraction, with and without the take's tuning.
- Five drifting takes come back within ±20 cents.
- `finish-transcription`: the key fit equals `fit-key` over the corrected notes. Hint distance is 0, −1 and +1, and 30 cents or 25 cents off still reads 0. No key evidence is answered.
- The F-measure: boundaries with and without STRICT, offsets, asymmetric precision and recall, a case where greedy matching fails, and 25 random instances against a brute-force maximum.
- Synthesis:
  - the Park–Miller check value;
  - exact sine samples and the envelope;
  - offset, drift and vibrato depth by zero crossings;
  - the sawtooth's 28 partials at exact bins, and nothing above;
  - seeded noise.
- The protocol: downmix, resampling, backend checks, and both audio conditions with both restarts, also through `transcribe`.
- The oracle, end to end.
- The YIN baseline:
  - steady sine and sawtooth tones, within 5 cents and 30 ms;
  - silence, white noise and empty audio;
  - the level gate;
  - the pitch range hint;
  - six synthesized melodies (sine and sawtooth, 40-cent vibrato, drift, offset, noise) at note F ≥ 0.9, every matched note within 20 cents after correction;
  - the hint distance through audio;
  - resampling from 22.05 kHz.

### T1: pYIN (transcribe-backend-pyin 0.1.0)

**Contract:** [transcribe-backend-pyin#1](https://github.com/egao1980/transcribe-backend-pyin/pull/1) (draft).

`pyin-transcriber` writes `detect-notes` only. The protocol's audio preparation, tuning, drift, key fit and evaluation are reused as T0 locks them, and a backend computes none of them.

#### Locked decisions (T1)

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Frames** | **1024 samples every 128** at 16 kHz (64 ms every 8 ms, **125 frames a second**), as the YIN baseline. YIN's integration window is W = 512 (32 ms), centred on the frame time; lags up to W. Initargs `:frame-size` and `:hop`. | pYIN's own time scale (2048 every 256 at 44.1 kHz: 46 and 5.8 ms). librosa's 2048 is at 22.05 kHz; at 16 kHz it would be 128 ms, and a 64 ms integration window starts voicing up to 32 ms early on a clean attack (d′ is scale-free), most of the 50 ms onset tolerance |
| **Level gate** | A frame whose integration window's RMS is more than 40 dB under the loudest frame's has no candidates (initarg `:gate-db`, the baseline's −40). The gate reads the integration window, not the whole frame. | d′ is scale-free: without a gate, bleed and room noise 50 dB down read as notes |
| **Threshold prior** | 100 thresholds s_j = j/100 under **Beta(2, 18)** (mean 1/10), masses P_j = I(j/100) − I((j−1)/100) as **exact rationals** (I in closed form for integer parameters). Troughs: lags in the hint's range with d′(τ) < d′(τ−1) and d′(τ) ≤ d′(τ+1). Each threshold gives its mass to the **first trough strictly below it**; with none below, the deepest trough gets **1/100** of it (pYIN's p_a). A trough with mass becomes a candidate at YIN's parabolic period. The frame's voicing is the sum. | The paper's rule, exact, so tests pin the probabilities. librosa's Boltzmann spread over trough ranks comes from the Vamp code, not the paper, and was left out |
| **Pitch HMM** | **10-cent bins** over the hint's pitch range (481 for C2 to C6), each voiced and unvoiced (2n states, the unvoiced ones keep the pitch through a voiceless stretch). Observations: voiced, the candidate mass in the bin; unvoiced, (1 − voicing)/n. Transitions: a **triangular band** of B = round(35.92 octaves/s × 120 × hop/rate) = **34 bins** (3.4 semitones a frame; pYIN's 25 bins at 44.1 kHz), times **1/100** for a change of voicing. Uniform start; Viterbi in logarithms with probabilities floored at 1e-300; ties to the smallest state index. The f0 of a voiced frame is its best candidate's in the decoded bin. | librosa's conventions, rescaled to the hop. The per-frame maximum factors into two triangular max-convolutions, O(n·B) |
| **Onset cue** | An **energy dip**, not a voicing dip: the RMS of 8 ms windows every 2 ms (one hop and a quarter hop); a dip is a strict local minimum at least **6 dB** under the loudest level within **50 ms** on each side, placed in the nearest frame. A rise alone (a note after a rest) or a fall alone (a note's end) is not one. | Consonants and fresh attacks dip in level. The pitch track stays voiced through a 20 ms dip (its window is 32 ms), so a voicing dip would miss the synthesized takes' re-articulations; their 10 ms ramps dip more than 10 dB, which no steady tone does (sine, sawtooth, vibrato of ±100 cents, noise 20 dB down) |
| **Vibrato smoothing** | `smooth-pitches`: within segments (voiced runs, also cut at onset frames), a **200 ms median**, then the **mean** of the frames whose median lies within 1/2 semitone of the frame's and whose pitch lies within 3/2 semitone of it (initarg `:vibrato-window`). | A 200 ms mean leaves 9 % of a 5.5 Hz vibrato but blurs a step into a ramp, and the note HMM then put a note into each ramp (Twinkle on a sine: F = 0.55). A median keeps steps sharp but leaves about a third of the depth (±100 cents split notes). The median-guided mean does both; the second band keeps octave errors out; the cut at onsets keeps one note's vibrato out of the next note's boundary |
| **Note HMM** | States every **1/3 semitone** (K = 145 for C2 to C6): per pitch a chain of **M_min − 1 attack states** and a **stable state**, and **one silent state**. Observations: π = (voicing + 7/10)/2 (Tony's prior 0.7 at weight 1/2); silent 1 − π; a note state π · exp(−(y − μ)²/2σ²) with **σ = 1/2 semitone**; unvoiced frames are silent. Transitions per frame: silent → a note **1/100** (shared over K), a note → silent **1/100**, a legato change to a pitch at least **2/3 semitone** away **1/1000** (shared). At an onset frame: a change **3/10** (shared) and a **re-attack** of the same or a neighbouring pitch **3/5** (shared among the three), leaving about 0.09 to staying. | Tony's model, simplified: one silent state; the attack chain is the minimum length; legato changes go note to note. σ = 1/2 balances semitone neighbours (σ = 3/4 merged a 71–72–71 figure on a legato take) and deep vibrato (σ = 1/3 split notes at ±80 cents). A re-attack more likely than staying makes the dip decide a repeated pitch |
| **Minimum note length** | **1/10 s** (Tony's pruning threshold; initarg `:min-duration`): M_min = max(2, ⌈0.1 · 125⌉) = **13 frames** (104 ms), enforced inside the HMM by the attack chain. | Pruning short notes afterwards would leave a gap that splits the note around it |
| **Repeated pitches** | Split at an onset frame when both parts last M_min frames; a legato repeated pitch (no dip) stays one note. | The cue is the singer's re-articulation, as in Tony |
| **Note pitch and confidence** | Pitch: the **mean** of the note's raw frame pitches within 3/2 semitone of their median. Confidence: the mean voicing of its frames. | A vibrato's median over part of its period sits up to 0.6 of the depth off centre (eighth notes at ±100 cents missed the 50-cent tolerance); the mean sits about 0.2 off. The band drops a leap's first frames and octave errors. A posterior would need a forward-backward pass for no measurable gain |
| **Cost** | A 3-minute take within **20 s** on the laptop; measured **2.5 s** (SBCL 2.4.11, arm64), the YIN baseline 1.2 s. Tested as ratios on one machine: pYIN within **8×** the baseline on the same take (measured 2.1) and within 8× a take of 33 s (measured 5.3, linear growth). | Ratios hold on slow CI runners; a quadratic step would show as about 30× |
| **Conditions** | None new: transcribe-protocol's tree, and `check-type` for arguments. | [conditions.md](conditions.md) |
| **Vocadito** | **Not in 0.1.0**: it stays T3's (fetched at test time by checksum, skipped offline). | A backend's unit suite stays offline and exact; parity is T3's job |
| **Glides** | Deferred: transcribe-protocol/testing 0.1.0 synthesizes no glides. A glide test waits for a `:glide` option there (or T3's recordings). | Its notes start at phase 0, so a synthetic glide would be a new synthesis rule in the protocol |
| **Dependencies** | transcribe-protocol 0.1.0 and audio-protocol 0.2.0; tests rove 0.11.1 and transcribe-protocol/testing. No third-party DSP. | Own stack first |

#### Surface (T1)

```lisp
;; package transcribe-backend-pyin
(defclass pyin-transcriber (transcriber) ())   ; :frame-size 1024 :hop 128 :gate-db -40
                                               ; :min-duration 1/10 :vibrato-window 1/5
(defmethod transcriber-info ((p pyin-transcriber)))   ; (:name "pyin-transcriber" :frame-size ...)
(defmethod detect-notes ((p pyin-transcriber) audio hints))   ; -> notes, contour

(defconstant +threshold-count+ 100)  (defparameter +beta-prior+ '(2 18))
(defconstant +no-trough-probability+ 1/100)
(defun threshold-prior ())                              ; -> #(P_1 .. P_100), exact
(defun pitch-candidates (cmndf tau-lo tau-hi))          ; -> ((tau* . p) ...), voicing

(defconstant +bins-per-semitone+ 10)  (defconstant +max-transition-rate+ 898/25)
(defconstant +switch-probability+ 1/100)  (defconstant +probability-floor+ 1d-300)
(defun pitch-bin-count (pitch-range))  (defun pitch-max-jump (hop sample-rate))
(defun decode-pitch (observations bin-count max-jump &key switch-probability)) ; -> #(bin|NIL ...)
(defun pyin-contour (audio &key frame-size hop gate-db pitch-range))  ; -> f0-contour

(defconstant +dip-db+ 6)  (defconstant +dip-span+ 1/20)
(defun onset-frames (audio &key hop))                   ; -> (frame ...)

(defconstant +note-steps-per-semitone+ 3)  (defconstant +smoothing-band+ 1/2)
(defconstant +note-sigma+ 1/2)  (defconstant +prior-pitched+ 7/10)
(defconstant +note-on-probability+ 1/100)  (defconstant +note-off-probability+ 1/100)
(defconstant +note-change-probability+ 1/1000)  (defconstant +min-change-steps+ 2)
(defconstant +onset-change-probability+ 3/10)  (defconstant +reattack-probability+ 3/5)
(defconstant +pitch-band+ 3/2)
(defun smooth-pitches (contour &key onsets vibrato-window))         ; -> #(y|NIL ...)
(defun contour-notes (contour &key onsets pitch-range min-duration vibrato-window)) ; -> #(note-event ...)
```

**Given:** the package and its exports, `pyin-transcriber` with its initarg checks and `transcriber-info`, the data, and the argument predicates. **Stubbed** (`%t1-pending`): `threshold-prior`, `pitch-candidates`, `pitch-bin-count`, `pitch-max-jump`, `decode-pitch`, `pyin-contour`, `onset-frames`, `smooth-pitches`, `contour-notes` and the `detect-notes` method.

#### Tests (77, Rove with `deftest-parametrize`)

Every take is synthesized with `transcribe-protocol/testing` (no fixtures). Melodies: three public-domain tunes (the Ode to Joy, Ah ! vous dirai-je, maman as Twinkle, Twinkle, Frère Jacques: 30, 14 and 32 notes, repeated pitches included, eighths of 1/4 s) and two figures written for the tests (a scale and semitone steps, for legato takes). Pass marks were calibrated on the reference implementation; the measured value follows each.

- **Given (12):** the class, the ten initarg checks, the data.
- **Exact rules:** the prior's 100 masses against the closed form; candidate masses, periods and voicing on hand-made d′ (two troughs, a later shallower one, a trough exactly at a threshold, equal troughs, none below 1, none at all, the lag range); `decode-pitch` paths (the band, continuity among candidates, voicing, the triangular weights, ties); dips (the hop, 4 dB against 12 dB, rises, falls, crescendos, legato); smoothing (an exact vibrato mean, sharp steps, an octave error, the cut at an onset); notes on hand-made contours (exact frames of steps and leaps, a 71–72–71 figure, drift, vibrato of ±60 and ±100 cents at 5 to 7 Hz as one note, onsets and the minimum length, voicing, the range, the robust mean).
- **Contour:** steady sine and sawtooth within 3 cents, voiced throughout; silence, the gate, the range, 22.05 kHz; on the Ode to Joy (clean, detuned, vibrato, noise) the median voiced-frame error ≤ **20 cents** (measured 0.1 to 3.0), voicing recall ≥ 0.99 (1.000), false voicing in rests ≤ 1/5 (0.000).
- **Takes, end to end through `transcribe`** (note F: onsets ±50 ms, pitches ±50 cents):
  - six melodies, sine and sawtooth: F ≥ **0.95** (1.000), every matched note within 10 cents (worst 3.5);
  - four legato takes: F ≥ 0.9 (1.000);
  - vibrato ±60 and ±100 cents at 5.5 Hz: F ≥ **0.9** (1.000) and at least the baseline + 0.4 (the baseline: 0.35, 0.32, 0 and 0); two seconds of one note: one note (the baseline: 22);
  - repeated pitches (Twinkle): F ≥ 0.95 (1.000), the baseline ≤ 0.75 (0.727);
  - drift and offset (+10 and −4 cents a second, −10 and +4, −35): F ≥ 0.95, every matched note within **20 cents** after the protocol's correction (worst 16.2), the tuning within 3 cents, two phrases;
  - noise 20 dB under the sine (uniform, 3/50): F ≥ 0.9 (1.000);
  - silence and white noise give no notes; a 60 ms note is dropped and a 160 ms one kept (with 1/4 s: 160 ms dropped, 300 ms kept); A1 only with a range hint;
  - a take sung a semitone flat of its `:key` hint: `key-fit-hint-distance` −1 (and 0, +1, 0 at −30 cents);
  - resampling from 22.05 kHz, the backend info in the result, a stereo take.
- **Cost:** the 3-minute take (330 notes) and its ratios.

### T2 (later): Basic Pitch in a container

`transcribe-backend-basic-pitch`: spotify/basic-pitch (Apache-2.0) run in a container through compute-backend-podman, as a batch job, on audio written with `write-wav`. Its note events are mapped to `note-event`; for a monophonic line, the loudest note at each time is kept. It is a second opinion and a parity oracle, and later also polyphonic.

### T3 (later): parity

`transcribe-parity`: a matrix of note F-measures (onset only and with offsets) per backend, with and without the key hint. It runs on synthetic renders of public-domain melodies (synthesized and, when AU1 lands, rendered by FluidSynth), and on Vocadito, fetched at test time ([above](#prior-art-intersection-not-a-clone)), against both of its annotators.

---

## Progress

| Slice | Package | State |
|-------|---------|-------|
| T0 | transcribe-protocol 0.1.0 | **implemented, published 0.1.0**: [transcribe-protocol#1](https://github.com/egao1980/transcribe-protocol/pull/1) (merged; team-solve: 225 tests, 804 assertions). Contract: Of its 225 tests, 173 fail on the stubs and 52 pass (the given model and conditions). A throwaway reference implementation, not committed, passes all 225 tests (804 assertions). Each of 18 mutations of it is caught, failing 1 to 14 tests: <br>• tie order, the drift window, the phrase gap, merging and duration weights; <br>• the tuning in `remove-drift` and the key fit on raw notes; <br>• the downmix, the silence boundary and re-checking a `use-value` replacement; <br>• greedy matching, strict comparisons and equal onsets; <br>• the YIN run rule and its level gate; <br>• the drift midpoint, the sawtooth's band limit and the tempo check |
| T1 | transcribe-backend-pyin 0.1.0 | **implemented, published 0.1.0**: [transcribe-backend-pyin#1](https://github.com/egao1980/transcribe-backend-pyin/pull/1) (merged; team-solve: 77 tests, 332 assertions; the 3-minute take in 1.95 s, 1.66x the YIN baseline). Contract: Of its 77 tests, 65 fail on the stubs and 12 pass (the given class, initarg checks and data). A throwaway reference implementation, not committed, passes all 77 tests (332 assertions), the 3-minute take in 2.5 s. Each of 21 mutations of it is caught, failing 1 to 18 tests: <br>• the beta prior, the parabolic period, strict thresholds and p_a; <br>• the unvoiced observation's 1/n, the triangular band, tie order, the level gate and the window it reads; <br>• the dip depth and its frame; <br>• no smoothing, a median only, the outlier band and the cut at onsets; <br>• re-attacks, the onset change, the minimum length, the mean pitch, the pitched prior and the confidence |
| T2 | transcribe-backend-basic-pitch | later |
| T3 | transcribe-parity | later |

### Decisions made in the T0 contract

| Decision | Choice |
|----------|--------|
| **The protocol prepares the audio** | Downmixing and resampling happen in `prepare-audio`, at the backend's declared rate, instead of in each backend |
| **Two generic functions** | `transcribe` (the entry point, open to `:around` methods) and `detect-notes` (the backend's job), so a primary method of `transcribe` never returns something other than a transcription |
| **Notes are corrected in the result** | `notes` are at A440 with the drift removed, and `raw-notes` keep the pitches as sung. SC6 rounds `key-fit-midis` after its own fit, so a drifting take would otherwise misplace notes late in the take |
| **A circular median, not a histogram mode** | Exact, robust, and free of the wrap-around at a half semitone. librosa's histogram mode depends on its bin width and is unstable over a handful of notes |
| **A per-phrase drift, not a curve** | Steps at breaths, each a circular median, with the window around the take's tuning as the clamp |
| **The YIN run rule** | Distance from the run's running median, not a step between frames: a glide between notes moves a little each frame, and the step rule merged semitone steps on sine takes (F = 0.74). The jump is 3/4 semitone, because early in a note the median sits about 0.38 of the vibrato depth off centre |
| **Test takes avoid ±50 cents** | Takes whose overall tuning lies near a half semitone read a semitone away (as in MT5), so the tests' detuned takes keep their average within about ±45 cents |

### Decisions made in the T1 contract

| Decision | Choice |
|----------|--------|
| **Frames of 1024, not 2048** | The brief's first plan (2048 every 256) was librosa's at 22.05 kHz. At 16 kHz, 1024 every 128 is pYIN's own time scale, and the contour runs at 125 frames a second like the baseline's |
| **The steps are exported** | `pitch-candidates`, `decode-pitch`, `onset-frames`, `smooth-pitches` and `contour-notes` each have an exact header and their own tests, so an implementation is pinned step by step and not only by F-measures on takes |
| **An energy dip as the onset cue** | Not a voicing dip (the pitch track stays voiced through a short re-articulation) and not Tony's rise alone (a note after a rest rises too; voicing already handles it) |
| **A median-guided mean for vibrato** | A plain mean put notes into the ramps between notes; a plain median left enough vibrato to split notes at ±100 cents. The suite pins the difference: a vibrato whose period is the window comes back exact |
| **The cut at onsets** | Without it, the vibrato at the end of one note pulled the next note's boundary up to 70 ms early (±80 cents at 5 Hz across a semitone) |
| **Mean pitch, not median** | Over part of a vibrato period the median is off centre by up to 0.6 of the depth, the mean by about 0.2 |
| **Ratios for the cost** | As AU3: against the baseline on the same take, and against a shorter take, so the test holds on any machine; the absolute time is recorded here |

---

## Open questions

- A sharper hint policy ("keep F or move to G?") belongs to consumers, through the logic family, as in MT5 and SC6.
- Whether T1 should also report per-note pitch deviations as provenance in the score, waiting for [score-protocol#13](https://github.com/egao1980/score-protocol/issues/13).
- GPU passthrough for T2's container (compute-backend-podman has no option for it today).
- Lyrics from singing need speech recognition, which the stack doesn't have.
- Glides between notes are not tested in T1: transcribe-protocol/testing has no glide synthesis. A `:glide` option there (a later transcribe-protocol slice) or T3's recordings would cover them.
- Note confidence from the note HMM's posteriors (a forward-backward pass) instead of the mean voicing, if review screens need it.

## Non-goals

Polyphonic transcription (until T2), real-time or streaming transcription, instruments other than voice as a goal (they work when monophonic), speech recognition, beat tracking and meter detection (SC6 estimates the tempo), and editing audio.
