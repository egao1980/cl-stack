;;;; Every tutorial example runs and returns what the tutorial says.

(defpackage #:cl-stack-examples/tests
  (:use #:cl #:rove #:cl-stack-examples/agents))

(in-package #:cl-stack-examples/tests)

(deftest retry-example
  (let ((r (example-retry)))
    (ok (equal "back online" (getf r :text)))
    (ok (= 3 (getf r :attempts)))
    (ok (equal '(:overloaded :overloaded) (getf r :retries)))))

(deftest compaction-example
  (let ((r (example-compaction)))
    (ok (equal "fits now" (getf r :text)))
    (ok (getf r :compacted))
    (ok (equal '(3 2) (getf r :turns-sent)) "full history, then summary + newest turn")))

(deftest max-steps-example
  (let ((r (example-max-steps)))
    (ok (eq :max-steps (getf r :finish)))
    (ok (search "Done: 2 searches" (getf r :text)))
    (ok (eq :none (getf r :last-tool-choice)))))

(deftest typed-tool-failure-example
  (let ((r (example-typed-tool-failure)))
    (ok (search "rejected its arguments: id is required" (getf r :first-result)))
    (ok (search "Fix the arguments" (getf r :first-result)))
    (ok (equal "User 42 is Ada." (getf r :text)))))

(deftest permissions-example
  (let ((r (example-permissions)))
    (ok (equal '(:done :denied :denied) (getf r :statuses)))
    (ok (getf r :feedback-seen))
    (ok (= 1 (getf r :ran)) "only the allowed edit ran")
    (ok (eq :stop (getf r :finish)) "denials do not abort the run")))

(deftest permission-ask-example
  (let ((r (example-permission-ask)))
    (ok (eq :approval (getf r :paused)))
    (ok (eq :stop (getf r :finish)))
    (ok (search "Use docs/ instead" (getf r :result)))
    (ok (zerop (getf r :ran)))))

(deftest subagent-example
  (let ((r (example-subagent)))
    (ok (search "Started subagent researcher with id sub-1" (getf r :started)))
    (ok (search "<subagent id=\"sub-1\" name=\"researcher\">" (getf r :text)))
    (ok (search "CLHS 9" (getf r :text)))
    (ok (getf r :waited))))

(deftest instructions-example
  (let ((r (example-instructions)))
    (ok (equal '("AGENTS.md" "src/AGENTS.md") (getf r :injected)))
    (ok (= 1 (getf r :instruction-turns)))
    (ok (eq :stop (getf r :finish)))))

(deftest system-prompt-example
  (let ((prompt (example-system-prompt)))
    (ok (stringp prompt))
    (ok (plusp (length prompt)))))
