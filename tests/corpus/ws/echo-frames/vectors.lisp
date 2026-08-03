;;;; Synthetic WebSocket echo / framing vectors (original MIT).
;;;; See ../../PROVENANCE.md. Consumed by cl-stack/corpus-smoke and
;;;; optionally by egao1980/ws-protocol Rove suites.
;;;;
;;;; Each plist describes an echo round-trip expectation (client → server → client).
;;;; :OPCODE is the logical WS opcode keyword; :PAYLOAD is a UTF-8 string or
;;;; unsigned-byte list; :CLOSE-CODE / :CLOSE-REASON optional for close frames.
((:id "text-ascii"
  :opcode :text
  :payload "ping-echo"
  :expect-echo t)
 (:id "text-empty"
  :opcode :text
  :payload ""
  :expect-echo t)
 (:id "text-utf8"
  :opcode :text
  :payload "こんにちは"
  :expect-echo t)
 (:id "binary-small"
  :opcode :binary
  :payload (1 2 3 4 5)
  :expect-echo t)
 (:id "binary-empty"
  :opcode :binary
  :payload ()
  :expect-echo t)
 (:id "close-normal"
  :opcode :close
  :close-code 1000
  :close-reason "bye"
  :expect-echo nil)
 (:id "ping-empty"
  :opcode :ping
  :payload ()
  :expect-pong t)
 (:id "ping-payload"
  :opcode :ping
  :payload (120)
  :expect-pong t))
