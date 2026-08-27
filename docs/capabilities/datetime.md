# datetime / TZ / calendars (P2)

**Issues:** [#105](https://github.com/egao1980/cl-stack/issues/105)  
**Status:** wave-1 **shipped** — first-party CLOS protocol + IANA data package + holiday/trading calendars. **Not** a `local-time` pin. Cookbook: [datetime.md](../cookbooks/datetime.md)

```text
cl-stack-calendars          ← holidays / business days / exchange sessions
        │
datetime-protocol           ← instant / duration / period / date / zone
datetime-protocol/calendars ← Easter, Hebrew, Islamic, Chinese, ritual times
        │
cl-stack-tzdata             ← IANA tzdb (TZif) — soft dep, auto-detected
```

Apps that only need “now + RFC 3339 + UTC” load `datetime-protocol`. Named zones need `cl-stack-tzdata`. Holiday / trading calendars are a **separate** facade.

Conventions: [API.md](../API.md). Gap: [STDLIB-GAP.md](../STDLIB-GAP.md). l10n date format: [l10n.md](l10n.md). Sample app: [`cl-stack-calendar-l10n`](https://github.com/egao1980/cl-stack-calendar-l10n).

---

## Prior art

| Source | Took | Left |
|--------|------|------|
| `local-time` / tzdata | IANA zone idea | Pin as the public API |
| `java.time` | instant / duration / period split | `LocalDateTime`, `plusDays`, `atZone` |
| Python `datetime` / zoneinfo | RFC 3339, IANA ids | Naive-as-default, `tzinfo` soup |
| CPython / dateutil / pyluach / IANA | gold vectors | Copying test source |

---

## Locked decisions

| Decision | Choice |
|----------|--------|
| **Shape** | First-party CLOS protocol. No `local-time` in the public DX. |
| **Vocab** | `instant` / `duration` / `period` / `date` / `time-of-day` / `moment` / `zoned-moment`. Not Java names. |
| **Date** | Rata Die (`date-rd`). RD 1 = proleptic Gregorian 0001-01-01. |
| **Arithmetic** | Shadowed `+ - < …`. `date-add` is `(date-add date field n &key overflow)` — `field` ∈ `:days :weeks :months :years`; `:overflow` ∈ `:error` (default) `:clamp` `:carry`. `with-fields` is the wither. |
| **Zones** | `+utc+` + fixed offsets always. Named IANA via `cl-stack-tzdata` (ASDF soft dep). `moment-in-zone` defaults `:on-gap :later` / `:on-overlap :earlier`; `:strict` signals. |
| **tzdata ship** | Lisp-loadable TZif + aliases — **no** OS zoneinfo package. OCI version tracks tzdb (`2026c` → `2026.3.0`). |
| **Calendars (computus)** | `datetime-protocol/calendars` — Easter / Hebrew / Islamic / Chinese. Enough to drive holiday rules. |
| **Holiday / trading** | [`cl-stack-calendars`](https://github.com/egao1980/cl-stack-calendars) — rule/data/composite, `:authority` citations, exchange MIC hours. |
| **Windows** | Required. tzdata + calendars data ship in-tree / zip; no `/usr/share/zoneinfo`. |

---

## Repos

| Layer | Repo | OCI |
|-------|------|-----|
| Protocol (`stack-datetime`) | [`datetime-protocol`](https://github.com/egao1980/datetime-protocol) | **0.1.1** |
| Computus subsystem | `datetime-protocol/calendars` | (same) |
| IANA data (`stack-tzdata`) | [`cl-stack-tzdata`](https://github.com/egao1980/cl-stack-tzdata) | **2026.3.0** |
| Holidays / sessions (`stack-calendars`) | [`cl-stack-calendars`](https://github.com/egao1980/cl-stack-calendars) | **0.4.0** |
| l10n demo | [`cl-stack-calendar-l10n`](https://github.com/egao1980/cl-stack-calendar-l10n) | **0.1.3** |

---

## Protocol surface (sketch)

```lisp
(defgeneric date-add (date field n &key overflow))
(defgeneric date-diff (date1 date2 field))
(defgeneric with-field (date field value &key overflow))
(defgeneric with-fields (object &key &allow-other-keys))
(defun moment-in-zone (moment zone &key (on-gap :later) (on-overlap :earlier)))
(defun instant-in-zone (instant zone))
(defun resolve-zone-id (id &optional repository))
(defgeneric clock-now (clock))
(defun now (&optional (clock *clock*)))
(defun today (&optional (zone +utc+) (clock *clock*)))
```

Parse/print: `parse-rfc3339` → `zoned-moment`; `parse-moment` is zone-naive; `parse-http-date` / `print-http-date` speak `instant` (IMF-fixdate).

Conditions: `datetime-error` → `datetime-parse-error`, `datetime-arithmetic-error`, `zone-not-found`, `nonexistent-local-time` (`:on-gap :strict`), `ambiguous-local-time` (`:on-overlap :strict`).

---

## Non-goals

- Pinning `local-time` as the facade
- Java `java.time` method names
- OS tzdata as the only source
- Holiday rules without a cited `:authority`
- Putting ICU `@calendar=` formatters in this package (that's `l10n-protocol`)
