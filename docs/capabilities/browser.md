# browser-protocol: headless browser over CDP

**Repo:** [`egao1980/browser-protocol`](https://github.com/egao1980/browser-protocol) · **0.3.0** (egao1980/browser-protocol#10: BR1 page recording with sound; 0.2.0: #4)
**Python counterparts:** Playwright (`chromium.launch()`, `page.goto(wait_until=)`, `connect_over_cdp`), Selenium WebDriver.

| System | Role |
|---|---|
| `browser-protocol` (`stack-browser`) | Page and session GFs, the CDP client (`cdp-browser-backend` over `send-fn` / `recv-fn`), the mock backend, the computer-use loop over `llm-protocol` |
| `browser-protocol/launch` | `launch-browser` / `with-browser` / `connect-cdp`: Chrome, Chromium or Edge over a CDP websocket |
| `browser-protocol/capability` | `:world` adapter |
| `browser-protocol/record` (`stack-browser/record`) | BR1 (0.3.0, merged and published: [#10](https://github.com/egao1980/browser-protocol/pull/10)): record a page with sound into one MP4 ([below](#br1-page-recording-with-sound-030)) |

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
| Waiting | `navigate` `:wait-until` `:load` (default) / `:domcontentloaded` / `:commit` and `:timeout`. `Page.enable` once per backend. It waits for the document its own navigation committed (main-frame `Page.frameNavigated` and its `loaderId`, or a document that replaced it), so the previous page's unread load event never ends it. `errorText` → `browser-error` with the URL. Every command has a deadline (`cdp-timeout`; `*cdp-receive-timeout*` for custom transports) |
| Errors | `browser-error` (`browser-error-cause` holds the JSON / ws / process condition), `browser-timeout`, `browser-disconnected`. Operations establish `retry` and `use-value` |

```lisp
(asdf:load-system "browser-protocol/launch")
(stack-browser:with-browser (b)                  ; headless, temporary profile
  (stack-browser:navigate b "https://example.com") ; waits for load
  (stack-browser:eval-js b "document.title")
  (stack-browser:screenshot b))                    ; PNG octets
```

The sandbox story is unchanged: Chromium can run inside a `compute-protocol` sandbox, and the backend accepts a compute backend slot. `launch-browser` is the local-process path.

---

## BR1: page recording with sound (0.3.0)

**Status:** implemented in [egao1980/browser-protocol#10](https://github.com/egao1980/browser-protocol/pull/10): the contract (stubs + Rove suite), then a team-solve run. CI is green on macOS, Windows and Ubuntu, both core and record jobs ([run 46064932023](https://github.com/egao1980/browser-protocol/actions/runs/46064932023)), with the live audio tests gated as [below](#tests-and-tolerances). Merged and published 0.3.0. **System:** `browser-protocol/record` (package `browser-protocol/record`, nickname `stack-browser/record`), so the core keeps its dependencies.

A program that drives a headless page records what the page shows **and what it plays** into one MP4 (H.264 + AAC). 0.2.0 has no screencast and no audio capture: a consumer hand-rolled `Page.startScreencast`, frame files and an ffmpeg concat call, and its videos were silent, because CDP's screencast carries no audio.

### Audio capture: a ScriptProcessorNode tap, not MediaRecorder, not an AudioWorklet

Probed on Chrome 158 headless (`--headless=new`, macOS, 2026-11-27) with a page whose CSP is `default-src 'self'; script-src 'self'; worker-src 'none'`, served over HTTP with the header and as a `file:` page with a `<meta>` element (both enforce it):

| Candidate | Result |
|---|---|
| AudioWorklet module from a `blob:` URL | Refused under the CSP (`AbortError: Failed to load worklet module script`); loads on the same page without the CSP. A `data:` module is refused too. Bypassing CSP (`Page.setBypassCSP`) would change the page under test. **Out.** |
| MediaRecorder on a `MediaStreamDestination` | Works (`audio/webm;codecs=opus`), but chunks are WebM/Opus: only the first carries the header, decoding needs ffmpeg (so the mix could not be tested without it), Opus adds encoder delay, and the recorder's start has no exact mapping to the page's clocks. **Not chosen.** |
| **ScriptProcessorNode** fed by a patched `AudioNode.prototype.connect` | Works under the CSP: CDP-injected scripts are not subject to it and the tap loads nothing. 16-bit PCM leaves the page as soon as each buffer is produced. **Chosen.** |

| Decision | Choice | Reason |
|---|---|---|
| Injection | The tap script goes in with `Page.addScriptToEvaluateOnNewDocument` (every later document, before its scripts) and `Runtime.evaluate` (the current one) | A recording started before a navigation, or after the page loaded, both capture |
| Tap | `AudioNode.prototype.connect` / `disconnect` patched: a connection to an `AudioContext`'s destination also feeds that context's tap, a `GainNode` bus (2 channels, explicit, speakers) → `createScriptProcessor(2048, 2, 2)` → destination (silent output). Offline contexts are left alone. The page's call behaves exactly as before; the tap's part is in `try`/`catch` | Captures what the graph sends to the speakers, mono sources on both sides as the destination plays them |
| Transport | `Runtime.addBinding` → `Runtime.bindingCalled` with a JSON payload: `v`, `track` (document id + context number), `seq`, `rate`, `channels`, `frame`, `contextTime`, `performanceTime`, `timeOrigin`, `pcm` (base64 S16LE). `Runtime.enable` is needed: without it Chrome 158 sends no `bindingCalled`. JSON through json-protocol, base64 through encoding-protocol. All-zero buffers are not sent | No polling, no page globals to read back; an idle AudioContext costs nothing |
| Chunk size | 2048 frames (42.7 ms at 48 kHz) | Small enough that a navigation loses at most the buffer being filled; large enough for main-thread scheduling |
| Sample frame of a chunk | Counted, not read from `playbackTime`. Chrome fills the processor's two buffers in turn with the frames the graph renders and fires one event per buffer (none skipped with handlers of up to 100 ms), so the k-th event since the processor was wired holds the frames from BASE + k · 2048. BASE comes from a spike train on the context's clock: one `ConstantSourceNode` per wiring on the tap's own bus, its `offset` automated with `setValueAtTime` to one single-frame spike per 2048 frames whose value (256 + 8 · (j mod 32)) names the spike; only the processor hears it and the tap takes it off again. `playbackTime` (Chrome's `currentTime + N/rate` when the main thread dispatches the event) only measures how late the event is: samples the audio thread may already have refilled count as silent. The rules are tap.lisp's header | Measured on the GitHub runners (2026-11-27, browser-protocol#10): the 0.3.0 contract's `round(playbackTime · rate) − 2 · 2048` was 1792 frames late for one event on macOS (a 37 ms hole in the tone) and 0 … +640 frames late from one event to the next on Windows at 44.1 kHz (pitch 433 Hz for 440). Chrome also renders quanta there without pulling the graph (the clock moves on 128 frames, the processor's frames do not; 128–256 frames within the first second), which the spikes follow. A node per marker instead stalled the page's main thread for 111–354 ms on macOS. On a Mac with an idle main thread the old rule is exact, which is what the contract measured |
| Clock mapping | Epoch seconds of a chunk's first sample = (`timeOrigin` + `performanceTime`) / 1000 + `frame` / `rate` − `contextTime`, from `getOutputTimestamp()` (`currentTime` / `performance.now()` when its `performanceTime` is still 0). **One mapping per track** (the chunk of smallest `seq`); within a track positions are exact context frames. Drift between the audio clock and the wall clock is not corrected | `getOutputTimestamp` gives the time a sample is *heard*, which is what lines up with the frames on screen; one mapping per track means no clicks from per-chunk jitter |
| Streaming | Each chunk is sent from its `audioprocess` event | A DOM swap (htmx) keeps the AudioContext and loses nothing; a navigation loses at most the chunk being filled (live test: the first document's tone lasts until within 0.1 s of the navigation; measured +11 ms, i.e. nothing lost) |
| Not captured | `<audio>` / `<video>` elements not routed through Web Audio; connections made before the tap was installed in a document; cross-origin out-of-process iframes | Web Audio only, as the slice says; recording before navigating covers the rest of a page's own graph |

### Video, mix and mux

| Decision | Choice | Reason |
|---|---|---|
| Screencast | `Page.startScreencast` `{format: "jpeg", quality, everyNthFrame: 1, maxWidth?, maxHeight?}`; each frame written to `frame-NNNNNN.jpg` with its `metadata.timestamp`, then acked (`Page.screencastFrameAck`), kept or not | Chrome sends the next frame only after the ack; acking after keeping numbers frames in arrival order even when the ack's wait reads the next frame; frames on disk keep memory flat |
| Event pump | While active, the recording reads the transport on its own thread (`wait-for-cdp-event` on a method no event has, 0.2 s at a time). Handlers run on whichever thread reads; the recording's own events leave the backend's event buffer | Frames and chunks keep coming while the caller sleeps; the 1000-event buffer never fills with frames |
| Clock | Time 0 is the earliest frame's timestamp (`recording-start-time`). Timestamps are taken as exact rationals | Everything (frames, page audio, clips) is placed on one clock |
| Constant frame rate | Slot k (0 ≤ k < N) at k/fps shows the last frame with t ≤ k/fps (a stable sort, so of equal timestamps the later arrival wins); N = max(⌈(t_last + tail)·fps⌉, ⌈t_last·fps⌉ + 1). The schedule is computed in Lisp; the ffconcat list has **one entry per slot**, each file with `option framerate <fps>`, durations from slot boundaries rounded to whole microseconds (no drift), the last file listed twice | Exact and testable without ffmpeg; the last frame always shows. A list of runs does not survive ffmpeg 9.0: the concat demuxer takes the first JPEG's 1/25 s time base (0.766667 s became 0.76 s) and the CFR conversion starts a frame at `llrint(pts − 0.6)`, so frames landed a slot early or late. With time base 1/fps and constant-rate input ffmpeg maps slots 1:1 (checked: 15/8/7 slots for frames at 0, 0.5, 0.75 s at 30 fps) |
| Tail | Default: until the recording stopped (`recording-stop-time`, the page's `performance.timeOrigin + performance.now()` at stop), else 0 | A static page sends no frames; the video still lasts as long as the recording |
| Mix | audio-protocol: tracks and clips resampled to 48 kHz (`resample`), mono duplicated at unity (no −3 dB pan law), placed at floor(start · rate + ½) (negative starts cut), summed by `mix … :channels 2 :clip :clip` (double-float sum in order, clamped to ±1, one `samples-clipped` warning), cut or padded to exactly the video's length | No private resampler or mixer; the clamp rule is audio-protocol's. Placing pads a copy of each input until `mix` takes start offsets (egao1980/audio-protocol#6) |
| No audio | No audio stream at all, not a silent track | ffprobe tells the truth; a consumer that wants a track adds a silent WAV |
| ffmpeg | Out of process through process-protocol: `-xerror` (a frame it cannot decode fails the run; without it ffmpeg skips it and exits 0), concat demuxer with `-safe 0 -reinit_filter 0`, `scale=trunc(iw/2)*2:trunc(ih/2)*2:eval=init:out_range=tv,format=yuv420p` (even dimensions from the first frame; later frames of another size scaled to it), `-r fps -fps_mode cfr -frames:v N`, libx264 `-pix_fmt yuv420p`, AAC 128k, `+faststart`. `find-ffmpeg`: `FFMPEG_PATH`, `PATH`, the usual install paths; `*ffmpeg-program*` overrides | Measured on ffmpeg 9.0: JPEG input gives full-range yuvj420p unless `out_range=tv`; the concat demuxer does not honour the last duration, so `-frames:v` caps the length; AAC decodes sample-aligned (edit list) |
| Known issues | egao1980/browser-protocol#6 (plist keys), #8 (`eval-js` does not await), #9 (file inputs) do not block BR1: the record system builds its params as string-key hash-tables, needs no promise results, and sets no files | Fixed in their own slices |

### Conditions (CLHS 9, on `browser-error`)

```text
browser-error
└── recording-error              recording
    ├── recording-stopped        stop-recording twice — restart CONTINUE (returns the recording)
    ├── recording-no-frames      write-video with no frames — USE-VALUE (frames), CONTINUE (write nothing)
    └── ffmpeg-error             program arguments exit-code stderr-tail (last 20 lines) — RETRY, USE-VALUE (program)
        └── ffmpeg-not-found     no ffmpeg, or the program is not a file — same restarts
recording-warning (warning)      recording reason — a frame or payload dropped; also kept in recording-warnings
```

A failure on the recording's reader thread (a frame that cannot be written) is kept and signalled by `stop-recording` as a `recording-error` with that cause. `stop-recording` is best effort: CDP errors are ignored, and after `browser-disconnected` the remaining calls are skipped; frames and audio received are kept.

### API (`browser-protocol/record`)

```lisp
(start-recording backend &key directory (audio t) max-width max-height (quality 80)) ; → recording
(stop-recording recording)                       ; → recording
(add-audio-file recording pathname &key at epoch) ; → audio-clip (seconds on the clock, or browser epoch)
(write-video recording output &key (fps 30) tail (sample-rate 48000)) ; → output pathname
(discard-recording recording)                    ; stop, delete a temporary directory
(with-recording (var backend &rest options) &body body)
;; accessors
recording-frames recording-audio-tracks recording-audio-clips recording-start-time
recording-stop-time recording-active-p recording-directory recording-warnings
;; pure parts, exported for tests and re-encoding saved frames
(make-recording &key directory frames)  (video-schedule frames &key fps tail)
(ffconcat-text frames &key fps tail)    (decode-pcm16 octets)  (parse-audio-chunk payload)
(chunk-epoch chunk)  (add-audio-chunk recording chunk)  (track-buffer track)
(mix-placed placements &key sample-rate frames)  (mix-recording recording &key sample-rate frames start)
(audio-tap-script)  (find-ffmpeg)  (ffmpeg-arguments concat output &key fps slots audio-file)
(run-ffmpeg arguments &key program)
```

```lisp
(asdf:load-system "browser-protocol/launch")
(asdf:load-system "browser-protocol/record")
(stack-browser:with-browser (b :args '("--autoplay-policy=no-user-gesture-required"))
  (let ((r (stack-browser/record:start-recording b)))
    (stack-browser:navigate b "https://example.test/page-with-sound")
    (sleep 5)
    (stack-browser/record:stop-recording r)
    (stack-browser/record:write-video r "page.mp4")
    (stack-browser/record:discard-recording r)))
```

### Tests and tolerances

Pure tests (no Chrome, no ffmpeg; a fake CDP peer whose receive blocks like a socket): frame timing and ffconcat (exact durations, tail, out-of-order and duplicate timestamps, microsecond boundaries), PCM decoding, payload parsing (24 malformed payloads), clock mapping, track assembly (gaps, overlaps, out-of-order chunks), mixing at exact sample positions (overlaps, clamping, resampling 16 → 48 kHz against audio-protocol's own `resample`), clip placement by `:at` and `:epoch`, the ffmpeg command line, `run-ffmpeg` with stand-in programs (stderr tail, `retry`, `use-value`), the CDP command sequence, frames and chunks read on the recording's thread, best-effort stop, the conditions and restarts. Live tests skip, saying why, without Chrome (or a running AudioContext), ffmpeg/ffprobe or, for those that check played page audio, an audio output device (rule below): a strict-CSP `file:` page playing a tone, a navigation mid-tone, saved frames and clips to MP4, ffprobe stream checks, the decoded AAC analysed with `audio-protocol/dsp`.

Tolerances, measured over 19 runs (Chrome 158, ffmpeg 9.0.2, macOS) and locked in the suite:

| Check | Measured | Locked |
|---|---|---|
| A page tone's onset in the recording vs the page's own `getOutputTimestamp` heard time | 0.0–0.2 ms | ±5 ms |
| The same in the decoded AAC | 0.0–0.2 ms | ±10 ms |
| A WAV clip's onset in the decoded AAC vs its `:at` (48 kHz and 16 kHz clips) | 0.0–0.1 ms | ±3 ms |
| First white video frame after the tone onset (the page turns white when it hears the tone: reaction, compositor, a 1/30 s slot) | +15 to +50 ms | −10 … +80 ms |
| A navigation mid-tone: the first document's audio kept until | 6–65 ms after the page left | no earlier than 100 ms before |
| Pitch (Hann window, RFFT, parabolic peak) | 440.04 Hz for 440 Hz | ±2 Hz |

Contract counts: 139 tests, 457 assertions; the throwaway reference passes all of them, 18 single-rule mutations of it are each caught, and on the stubs 129 tests fail (the 10 that pass cover the given parts and the fixture's CSP).

| Where | Rule |
|---|---|
| Tests | **No audio, no audio tests** (decided 2026-11-27). Some live tests play a tone through the page and check the captured audio: the strict-CSP capture, the tap installed in the current document, a navigation mid-tone, and a page with sound to MP4. They run only on a machine whose OS reports an audio output device, and skip, saying why, without one. A test that also checks video says so in its skip reason. Without an output device Chrome plays into a fake output whose timing stalls, so there is no page audio to check (egao1980/browser-protocol#15, #16). Detection is asked once and printed once: on macOS, `system_profiler SPAudioDataType -json` (a device with output channels or the default output, on a hardware transport; virtual, aggregate and unknown transports don't count, and under a hypervisor, `kern.hv_vmm_present`, neither does a builtin one); on Windows, the active MMDevices render endpoints; on Linux, `/proc/asound/cards`. **`BROWSER_PROTOCOL_AUDIO_TESTS=1`** runs these tests anyway, and `0` skips them. On a machine with a device every assertion and tolerance applies unchanged. Everything else runs regardless: the strict-CSP worklet check, the MP4 tests from saved frames and clips (ffmpeg only), the ffmpeg failure and find tests, and the pure tests |
| CI | The GitHub runners have Chrome on macOS and Windows (not in the Ubuntu ci-base container), no ffmpeg anywhere (egao1980/browser-protocol#12), and no audio output device. macos-latest is a VM: an "Apple Virtual Sound Device" (builtin transport) and a "Null Audio Device" (virtual). windows-latest has 0 render endpoints. So the strict-CSP worklet check runs on macOS and Windows, the audio tests skip on the gate, and the ffmpeg ones skip for lack of ffmpeg. `.github/workflows/test.yml` runs the record suite as its own job |

### Slices

| Slice | Content |
|---|---|
| **BR1** (0.3.0) | This section: `browser-protocol/record` |
| later | `<audio>` / `<video>` elements (`captureStream`), out-of-process iframes, ffmpeg in CI (#12), a public event pump and buffer opt-out in the core (#11, BR1 uses internals for both), #6 / #8 / #9 |
