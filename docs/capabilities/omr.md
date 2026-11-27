# omr-protocol and transcribe-protocol (P2): recognising music from images and audio (outline)

**Issues:** to be filed
**Status:** **outline**. Planned repos:
- OMR: `omr-protocol`, `omr-backend-ensemble`, `omr-backend-audiveris`, `omr-backend-<photo>` (homr or oemer, picked by the spike), `omr-backend-llm`, `omr-parity`;
- transcription: `transcribe-protocol`, `transcribe-backend-pyin`, `transcribe-backend-basic-pitch`, `transcribe-parity`.

**Builds on:** [score-protocol](score.md), [music-theory](music-theory.md), [image](image.md), [llm](llm.md) (`llm-image-part`, `:output`), [logic](logic.md) (ensemble fusion), [compute-protocol](confinement.md) (sandboxed engines), `doc-extract-backend-pdf` (page rasterisation, a gap), [audio](audio.md)

Two recognisers produce [score-protocol](score.md) scores in which **every guess carries provenance and confidence**, so a review step can show exactly what to check:
- **OMR:** printed or photographed sheet music (PDF, JPG, PNG) → a score with chord symbols and lyrics.
- **Transcription:** a single-voice recording (sung or hummed) → note events → a score, through score-backend-midi's import path (quantisation, spelling).

Both accept **hints**: `:key`, `:meter`, `:tempo`.

---

## OMR: locked so far

| Decision | Choice |
|----------|--------|
| **Shape** | `recognize-page backend page &key hints` and `recognize-document backend source &key hints pages` return a score plus a `recognition-report`: per element, confidence, page and bounding box, and the readings from each backend |
| **Inputs** | JPG/PNG through image-protocol (`:orient t`). PDF pages are rasterised by doc-extract-backend-pdf (a gap: `FPDF_RenderPageBitmap`). Images are resized for LLM input through image-protocol (a gap: resize/crop/rotate). |
| **Ensemble** | `omr-backend-ensemble` runs several backends and aligns their results measure by measure. Fusion is a **logic-protocol (Datalog) program**: source precedence per element kind is facts (e.g. chord symbols and lyrics prefer the vision LLM, pitches and rhythm prefer the engine); `uncertain` is derived where readings differ; melody notes that clash with the chord symbol are flagged. No hand-written precedence code. |
| **Engines** | **Audiveris** (AGPL-3) runs **out of process** in a podman sandbox, as a batch CLI export to `.mxl`, read with score-backend-musicxml. It's not linked and not in the pin set. **Photo engine:** homr (license to verify) or oemer (MIT), ONNX/Python through `uv`, in podman. |
| **Vision LLM** | `omr-backend-llm` uses llm-protocol image parts and structured output (`:output` schema, or a forced tool call on wires without native structured output): measures, pitches/rhythms, chord symbols, lyrics. It works with any llm-protocol backend that supports `:vision`. |
| **Parity** | `omr-parity`: public-domain lead sheets and hymns (scans and phone photos), plus **synthetic pages**: ground-truth MusicXML rendered by `engrave-backend-verovio`, rasterised, then degraded (perspective, blur, noise, JPEG artefacts). Metrics: pitch/rhythm sequence edit distance, chord-symbol and lyric accuracy, measure count, flag precision and recall. Reported as a matrix per backend (`print-matrix`, like doc-extract-parity). |

## Transcription: locked so far

**Superseded** by [transcribe.md](transcribe.md), which locks the protocol (T0) and plans the pYIN backend (T1). Where the two differ, transcribe.md decides: note events carry onset and offset (not a duration); the key hint feeds a key fit after the take's tuning and drift are removed, and the hint distance reports a take in another key; and the Vocadito plan stands as below. The table is kept as the outline's history.

| Decision | Choice |
|----------|--------|
| **Shape** | `transcribe backend audio &key hints` returns note events (onset s, duration s, pitch as fractional MIDI, confidence) plus the f0 contour. `transcription->score` goes through score-backend-midi's import path (tempo/beat, quantisation, spelling). |
| **Key hint** | Used for: (1) the global tuning offset that best fits the key's scale; a tonic a semitone or more away from the hint is reported as **"sung in another key"** with a transposition suggestion, never snapped silently; (2) a pitch prior favouring scale degrees in note segmentation; (3) spelling. Without a hint, music-theory key detection runs and its result is flagged. |
| **pyin backend** | Pure Lisp: pYIN (FFT-based difference function from audio-protocol's `dsp`), HMM note segmentation, vibrato smoothing, per-phrase drift estimate. Monophonic. |
| **basic-pitch backend** | Spotify Basic Pitch (Apache-2.0; ONNX, Python through `uv`) in podman, batch. A second opinion and the parity oracle; also polyphonic later. |
| **Parity** | `transcribe-parity`: Vocadito (CC BY 4.0; **fetched at test time with checksums, not vendored**, because CC BY is outside the corpus allowlist), plus synthetic renders of public-domain melodies (audio-protocol synthesis, ground truth exact). Metric: note F-measure (onset ±50 ms, pitch ±50 cents), with and without the key hint. |

---

## Protocol surface (sketch)

```lisp
(defclass omr-backend () ())
(defgeneric backend-recognize-page (backend page &key hints))
(defun recognize-page (page &key backend hints))
(defun recognize-document (source &key backend hints pages))
(defstruct recognition-report elements readings backends)

(defclass transcribe-backend () ())
(defgeneric backend-transcribe (backend audio &key hints))
(defun transcribe (audio &key backend hints))     ; → note events, f0 contour
(defun transcription->score (result &key hints))  ; via score-backend-midi import
```

Conditions: `recognition-error` → `engine-unavailable`, `engine-failed` (with log), `unsupported-input`; warnings `low-confidence-result`, `hint-mismatch`.

---

## Spike (decides before slice 1)

An OMR smoke test: Audiveris plus one vision LLM on 10 public-domain lead sheets (scans and photos). It decides the ensemble's precedence facts and which photo engine to wrap.

## Open questions

- GPU passthrough for containerised engines (compute-backend-podman has no option for it today).
- Lyrics from singing (automatic speech recognition): no ASR backend exists in the stack, and llm-protocol has no audio parts yet. Deferred.
- Multi-page system stitching across page turns.

## Non-goals

Handwritten scores, tablature, orchestral scores beyond a few staves, real-time recognition, polyphonic transcription in wave 1.
