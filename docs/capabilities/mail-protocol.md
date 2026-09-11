# mail-protocol (P1)

**Status:** **shipped** — [`egao1980/mail-protocol`](https://github.com/egao1980/mail-protocol) OCI **0.1.0** (`stack-mail`) + memory / SMTP backends **0.1.0**.

Compose / parse / send. Wire format is [`mime-protocol`](mime-protocol.md). **Not** IMAP / MUA.

Bcc is envelope-only (`print-message` strips it). SMTP is EHLO/MAIL/RCPT/DATA/QUIT — no AUTH or STARTTLS yet.
