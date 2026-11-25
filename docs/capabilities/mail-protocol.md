# mail-protocol (P1)

**Status:** **shipped** — [`egao1980/mail-protocol`](https://github.com/egao1980/mail-protocol) OCI **0.3.0** (`stack-mail`) + `mail-backend-memory` / `mail-backend-smtp` **0.3.0** ([mail-protocol#6](https://github.com/egao1980/mail-protocol/pull/6), [#10](https://github.com/egao1980/mail-protocol/pull/10)), on [`mime-protocol`](mime-protocol.md) 0.3.3.

Compose / parse / send. Wire format is [`mime-protocol`](mime-protocol.md). **Not** a MUA; the protocol has an IMAP client (`imap-connect` / `imap-login` / `imap-select` / `imap-search` / `imap-fetch` / `imap-idle`, 0.2.0).

## Shipped (0.3.0)

| Python | cl-stack |
|---|---|
| `EmailMessage()` + `msg["From"]` … | `make-message :from :to :cc :bcc :subject :body` (writes `Date`, `Message-ID`; canonical header names; Bcc envelope-only) |
| `email.utils.formatdate()` / `make_msgid()` | `format-message-date` / `make-message-id` (fork- and thread-safe) |
| `email.utils.getaddresses()` | `address-list` / `parse-address` / `address-mailboxes` (quoted names, comments, groups) |
| `msg.add_alternative(html, subtype="html")` | `add-alternative msg html` |
| `msg.add_attachment(data, filename=…)` | `add-attachment msg data :filename … [:content-type …]` |
| `msg.get_body()` / `iter_attachments()` | `message-body [:subtype]` / `message-attachments` |
| `smtplib.SMTP(host, 587).starttls(); login()` | `make-smtp-backend :host :port 587 :starttls t :username :password` |
| `smtplib.SMTP_SSL(host)` | `make-smtp-backend :host :tls t` (port 465) |
| `smtplib.SMTP.send_message(msg)` | `send msg`: envelope = `envelope-sender` / `envelope-recipients` addr-specs |

Headers and bodies go out as Python's `EmailMessage` writes them: non-ASCII Subject words, display names, group names and comments as RFC 2047 encoded-words, read back decoded; lines folded at 78; text in its charset, quoted-printable when a line is over 998; a long non-ASCII filename as RFC 2231 continuations (mime-protocol 0.3.3). CR, LF or NUL in an address is `mail-address-error`, in another header mime-protocol's `mime-header-error`, and no SMTP command is written with CR or LF ([mail-protocol#8](https://github.com/egao1980/mail-protocol/issues/8)).

SMTP: EHLO, STARTTLS (EHLO again; a server without it is an error, never a plain send), AUTH PLAIN / LOGIN, MAIL / RCPT / DATA / QUIT over ISO-8859-1 streams (the message's octets go out once), `BODY=8BITMIME` / `SMTPUTF8` when needed, the null reverse-path `MAIL FROM:<>`. Once the server took the message, a lost QUIT reply is not a failed send. TLS is cl+ssl through [`cl-stack-ssl`](https://github.com/egao1980/cl-stack-ssl). Conditions: `mail-send-error` (`code`, `cause`; a refused connect too), `mail-auth-error`, `mail-address-error`; IMAP `imap-error`, `imap-auth-error`.

## Open

- [mail-protocol#9](https://github.com/egao1980/mail-protocol/issues/9): CR LF in an IMAP argument (login, select, search) ends the command
