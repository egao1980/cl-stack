# audio-protocol (P2): PCM, mixing, synthesis, decoding, voice processing (outline)

**Issues:** to be filed
**Status:** **outline**. Planned repos: `audio-protocol`, `audio-backend-fluidsynth`, `audio-backend-ffmpeg`, `audio-backend-world`, `audio-backend-signalsmith`.
**Builds on:** [binary-protocol](binary-protocol.md), `midi-protocol` ([score.md](score.md)), [compute-protocol](confinement.md) (sandboxed ffmpeg), [process](process.md)

**Batch** audio for the music stack:
- PCM buffers, mixing and WAV;
- a small DSP module (FFT, windows, resampling);
- rendering MIDI to per-voice stems through a SoundFont synthesiser;
- decoding compressed uploads;
- voice analysis and resynthesis, used to correct a sung take's pitch or move it onto another line.

Everything runs as a batch job: there is no real-time audio I/O and no device access.

---

## Locked so far

| Decision | Choice |
|----------|--------|
| **Buffers** | `pcm-buffer`: sample rate, channels, frame count, interleaved `single-float` vector in −1…1 |
| **Pure-Lisp core** | WAV read and write (PCM 16/24-bit, float32); `mix` (per-input gain and pan); `normalize`; the **`dsp` module**: radix-2 complex and real FFT, Hann/Hamming windows, polyphase resampling, RMS and peak. If an existing CL FFT library turns out permissive and SBCL-clean, it's imported instead (to check). |
| **Synthesis** | `render-midi synth smf &key soundfont sample-rate stems` gives one buffer, or one per track/channel (stems). **fluidsynth backend**: libfluidsynth over CFFI (`asdf-native`). It's LGPL-2.1 native, so it ships as an overlay plus `NOTICE`. The SoundFont is FluidR3_GM (MIT), shipped as a separate data artifact. |
| **Decoding** | `decode-audio source &key format` / `encode-audio buffer format`. WAV is handled in Lisp. MP3/M4A/AAC/Opus/WebM use the **ffmpeg backend**: ffmpeg runs **out of process** in a podman sandbox (no network, limits), batch only. |
| **Voice processing** | `analyze-voice buffer` gives f0, spectral envelope and aperiodicity; `resynthesize analysis &key f0 envelope-scale` goes back to audio. **world backend**: the WORLD vocoder (Morise; modified BSD) over CFFI. |
| **Stretch / shift** | `pitch-shift buffer semitones &key formant-compensation` and `time-stretch buffer ratio`. **signalsmith backend**: Signalsmith Stretch (MIT, header-only C++) behind a small C shim, over CFFI. |
| **Licenses** | GPL plugins (Autotalent, Zita-AT1, x42-autotune, MXTune) are real-time LV2/JACK tools: study only, not used. |

---

## Protocol surface (sketch)

```lisp
(defstruct pcm-buffer sample-rate channels frames samples)
(defun read-wav (source)) (defun write-wav (buffer destination &key bits))
(defun mix (inputs &key gains pans)) (defun resample (buffer rate))
(defun fft (vector)) (defun rfft (vector)) (defun window (kind n))

(defclass synth () ())             (defgeneric synth-render-midi (synth smf &key soundfont sample-rate stems))
(defclass audio-codec () ())       (defgeneric codec-decode (codec source &key format)) (defgeneric codec-encode (codec buffer format &key))
(defclass voice-processor () ())   (defgeneric processor-analyze (p buffer)) (defgeneric processor-resynthesize (p analysis &key))
(defclass stretcher () ())         (defgeneric stretcher-pitch-shift (s buffer semitones &key)) (defgeneric stretcher-time-stretch (s buffer ratio &key))
```

Conditions: `audio-error` → `audio-format-error`, `audio-backend-unavailable`, `audio-limit-exceeded` (duration, size), `sandbox-failure` (ffmpeg).

---

## Open questions

- Opus/Ogg encoding for downloads: through ffmpeg (sandbox), or a libopus overlay?
- Stem rendering at several tempos: re-render with FluidSynth vs `time-stretch`, decided by measured quality.
- Quality limits of resynthesis over large shifts (more than an octave) for voice processing, to be measured with listening tests.

## Non-goals

Real-time audio I/O, device ports, streaming, plugin hosting (LV2/VST), DAW-style editing, speech recognition.
