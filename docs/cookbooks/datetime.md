# Cookbook: date / time / TZ / calendars

**Audience:** Python `datetime` + `zoneinfo` / Java `java.time` — without those names.

| Piece | Package | OCI |
|-------|---------|-----|
| Protocol (`stack-datetime`) | [`datetime-protocol`](https://github.com/egao1980/datetime-protocol) | **0.1.1** |
| Easter / Hebrew / Islamic / Chinese | `datetime-protocol/calendars` | (same) |
| IANA tzdb (`stack-tzdata`) | [`cl-stack-tzdata`](https://github.com/egao1980/cl-stack-tzdata) | **2026.3.0** |
| Holidays / sessions (`stack-calendars`) | [`cl-stack-calendars`](https://github.com/egao1980/cl-stack-calendars) | **0.4.0** |

Brief: [datetime.md](../capabilities/datetime.md) (#105). Localized print → [unicode.md](unicode.md) (`l10n-protocol`).

```lisp
(cl-repo:load-system "datetime-protocol" :version "0.1.1")
(cl-repo:load-system "cl-stack-tzdata" :version "2026.3.0")   ; named IANA zones
```

---

## 1. Dates and arithmetic

`date-add` is `(date-add date field n &key overflow)` — `field` is `:days` / `:weeks` / `:months` / `:years`. `:overflow` is `:error` (default) / `:clamp` / `:carry`.

```lisp
(use-package :stack-datetime)

(+ (make-date 2024 1 31) (months 1))   ; DATETIME-ARITHMETIC-ERROR (plus → date-add, :overflow :error)
(date-add (make-date 2024 1 31) :months 1 :overflow :clamp)  ; => #<DATE 2024-02-29>
(- (make-date 2024 1 11) (make-date 2024 1 1))               ; => 10 (days)
(with-fields (make-date 2024 2 29) :year 2023 :overflow :clamp)  ; => #<DATE 2023-02-28>
```

`date+` / `date-` if you don't want the shadowed package. `+` on a date + integer is days; date + `period` walks years/months/days via `date-add`.

---

## 2. RFC 3339 / HTTP-date

`parse-rfc3339` → `zoned-moment`. `parse-http-date` / `print-http-date` speak `instant` (IMF-fixdate only).

```lisp
(print-rfc3339 (parse-rfc3339 "2024-10-27T08:00:00-04:00"))
(print-http-date (parse-http-date "Sun, 06 Nov 1994 08:49:37 GMT"))
(now)                      ; instant from *clock* (system-clock)
(today)                    ; date in +UTC+ (pass a zone as the first arg)
(today (resolve-zone-id "America/New_York"))
```

---

## 3. IANA zones (needs tzdata)

`+utc+` and `make-fixed-offset-zone` work without the data package. Named zones load when `cl-stack-tzdata` is visible to ASDF (`tzdata-available-p`).

`moment-in-zone` defaults are **`:on-gap :later`** and **`:on-overlap :earlier`**. `:strict` signals `nonexistent-local-time` / `ambiguous-local-time`.

```lisp
(asdf:load-system "cl-stack-tzdata")
(moment-in-zone (parse-moment "2024-03-10T02:30:00")
                (resolve-zone-id "America/New_York"))
;; default :on-gap :later — resolves the spring-forward hole, does not signal

(moment-in-zone (parse-moment "2024-03-10T02:30:00")
                (resolve-zone-id "America/New_York")
                :on-gap :strict)
;; => NONEXISTENT-LOCAL-TIME

(tzdata:find-zone "Europe/Kiev")   ; → canonical Europe/Kyiv
```

`parse-moment` is zone-naive (`YYYY-MM-DDTHH:MM:SS`). Instant → wall clock is `instant-in-zone` (always defined).

No `/usr/share/zoneinfo`. Windows is a first-class consumer.

---

## 4. Computus / festivals

```lisp
(asdf:load-system "datetime-protocol/calendars")
(easter-western 2024)    ; => #<DATE 2024-03-31>
(easter-orthodox 2024)   ; => #<DATE 2024-05-05>
(rosh-hashanah 5785)     ; => #<DATE 2024-10-03>
(passover 5785)
```

---

## 5. Holiday + trading calendars

```lisp
(asdf:load-system "cl-stack-calendars")
(use-package :stack-calendars)

(holiday-p (country-calendar "DE") (make-date 2024 10 3))
(let ((cal (us-federal-holidays-calendar)))
  (business-day-p cal (make-date 2024 7 4))
  (add-business-days cal (make-date 2024 7 3) 1))

(exchange-session-bounds "XNYS" (make-date 2024 6 3))
(exchange-open-p "XHKG" some-instant)   ; lunch excluded
```

`set-data-root` points the sexp corpus at a directory, a zip, or a `zip://` URI.

Demo that also hits ICU l10n: [`cl-stack-calendar-l10n`](https://github.com/egao1980/cl-stack-calendar-l10n).

---

## What not to do

- Don't teach `local-time` as the stack API.
- Don't copy `java.time` names (`LocalDateTime`, `plusDays`).
- Don't write `(date-add d :months 1)` as keyword-only — `field` and `n` are positional.
- Don't claim DST gaps signal by default — pass `:on-gap :strict`.
- Don't depend on OS tzdata for CI / Windows.
- Don't put holiday observance hacks in `datetime-protocol` — that's `cl-stack-calendars`.
