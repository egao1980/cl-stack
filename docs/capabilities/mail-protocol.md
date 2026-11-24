# mail-protocol (P1)

**Status:** **shipped** — [`egao1980/mail-protocol`](https://github.com/egao1980/mail-protocol) OCI **0.2.0** (`stack-mail`) + `mail-backend-memory` / `mail-backend-smtp` **0.2.0**. **0.3.0** of all three (compose helpers, SMTP AUTH / STARTTLS / TLS, below) is merged in [mail-protocol#6](https://github.com/egao1980/mail-protocol/pull/6); publish pending.

Compose / parse / send. Wire format is [`mime-protocol`](mime-protocol.md). **Not** a MUA; the protocol has an IMAP client (`imap-connect` / `imap-login` / `imap-select` / `imap-search` / `imap-fetch` / `imap-idle`, 0.2.0).

## Shipped (0.2.0)

`make-message :from :to :cc :bcc :subject :body` / `print-message` / `parse-message` / `send`. Bcc is envelope-only (`print-message` strips it). SMTP backend: EHLO / MAIL / RCPT / DATA / QUIT, **no** AUTH or STARTTLS. Conditions: `mail-send-error`; IMAP `imap-error`, `imap-auth-error`.

## 0.3.0 (merged, publish pending)

| Python | cl-stack |
|---|---|
| `EmailMessage()` + `msg["From"]` … | `make-message :from :to :cc :bcc :subject :body` (writes `Date`, `Message-ID`; canonical header names) |
| `email.utils.formatdate()` / `make_msgid()` | `format-message-date` / `make-message-id` |
| `msg.add_alternative(html, subtype="html")` | `add-alternative msg html` |
| `msg.add_attachment(data, filename=…)` | `add-attachment msg data :filename … [:content-type …]` |
| `msg.get_body()` / `iter_attachments()` | `message-body [:subtype]` / `message-attachments` |
| `smtplib.SMTP(host, 587).starttls(); login()` | `make-smtp-backend :host :port 587 :starttls t :username :password` |
| `smtplib.SMTP_SSL(host)` | `make-smtp-backend :host :tls t` (port 465) |

SMTP: EHLO, STARTTLS (EHLO again; a server without it is an error, never a plain send), AUTH PLAIN / LOGIN, MAIL / RCPT / DATA / QUIT. TLS is cl+ssl through [`cl-stack-ssl`](https://github.com/egao1980/cl-stack-ssl). Conditions: `mail-send-error` (`code`, `cause`; a refused connect too), `mail-auth-error`. Needs mime-protocol 0.3.0 (nested multiparts round-trip, canonical header names).

## Open

- [mail-protocol#4](https://github.com/egao1980/mail-protocol/issues/4): the SMTP envelope uses the raw header text, so display-name addresses are rejected (501); no RFC 5322 address parsing
- [mail-protocol#5](https://github.com/egao1980/mail-protocol/issues/5): UTF-8 bodies double-encoded over SMTP, non-ASCII `Subject` sent as raw 8-bit (no RFC 2047)
- [mail-protocol#8](https://github.com/egao1980/mail-protocol/issues/8): CR LF in an envelope address sends an extra SMTP command
- [mail-protocol#9](https://github.com/egao1980/mail-protocol/issues/9): CR LF in an IMAP argument (login, select, search) ends the command
