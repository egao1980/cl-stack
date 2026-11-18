;;;; Long runs: retry by failure class, compaction, max-steps wrap-up,
;;;; typed tool failures (ai-agent-protocol 0.4+, llm-protocol 0.4+).

(in-package #:cl-stack-examples/agents)

(defun example-retry ()
  "The first two generates fail with 529 (overloaded). The retry policy
reschedules them on the event loop; the third succeeds.
Returns (:text … :attempts 3 :retries (:overloaded :overloaded))."
  (let* ((attempts 0)
         (events (list nil))
         (backend (make-mock-llm-backend
                   :handler (lambda (b turns &key &allow-other-keys)
                              (declare (ignore b turns))
                              (when (< (incf attempts) 3)
                                (error 'llm-http-error :status 529 :message "overloaded"))
                              (reply "back online"))))
         (agent (make-ai-agent
                 :name "retrying" :backend backend
                 :settings (make-agent-settings
                            ;; Real runs keep the defaults (2 s base, doubled
                            ;; when overloaded, Retry-After honoured); zero
                            ;; delays keep the example instant.
                            :extra (list :retry-policy
                                         (make-retry-policy :base-delay 0 :max-delay 0)))))
         (run (with-agent-loop
                (run-ai-agent agent "hi" :on-event (collect-events events :retry)))))
    (list :text (agent-run-text run)
          :attempts attempts
          :retries (mapcar (lambda (e) (getf (cdr e) :reason)) (reverse (car events))))))

(defun %summarizer ()
  "Stands in for the model that writes the compaction summary."
  (make-mock-llm-backend
   :handler (lambda (b turns &key &allow-other-keys)
              (declare (ignore b turns))
              (reply "## Objective
Answer the user.
## Work State
Old question answered."))))

(defun example-compaction ()
  "The model rejects the full history as too long (LLM-CONTEXT-OVERFLOW).
The run compacts once with a summary memory, keeping the newest turn
verbatim, and retries the step.
Returns (:text … :compacted t :turns-sent (3 2))."
  (let* ((sent '())
         (events (list nil))
         (backend (make-mock-llm-backend
                   :handler (lambda (b turns &key &allow-other-keys)
                              (declare (ignore b))
                              (push (length turns) sent)
                              (if (find-if #'conversation-protocol:summary-turn-p turns)
                                  (reply "fits now")
                                  (error 'llm-context-overflow
                                         :status 400 :message "prompt is too long")))))
         (memory (conversation-protocol:make-summary-memory
                  :backend (%summarizer)
                  ;; Keep ~15k tokens verbatim in real use; 1 keeps just the
                  ;; last turn here.
                  :tail-tokens 1))
         (agent (make-ai-agent :name "compacting" :backend backend
                               :settings (make-agent-settings
                                          :extra (list :compaction memory))))
         (history (list (user-turn "old question")
                        (assistant-turn "old answer")
                        (user-turn "new question")))
         (run (with-agent-loop
                (run-ai-agent agent history :on-event (collect-events events :compacted)))))
    (list :text (agent-run-text run)
          :compacted (and (car events) t)
          :turns-sent (reverse sent))))

(defun example-max-steps ()
  "A model that would call tools forever. At :max-steps the run makes one
more generate with tool-choice :none (tools stay in the request, so the
cached prefix holds) and ends with a summary.
Returns (:finish :max-steps :text … :last-tool-choice :none)."
  (let* ((choices '())
         (backend (make-mock-llm-backend
                   :handler (lambda (b turns &key tool-choice &allow-other-keys)
                              (declare (ignore b turns))
                              (push tool-choice choices)
                              (if (eq tool-choice :none)
                                  (reply "Done: 2 searches. Left: none. Next: read the hits.")
                                  (tool-call (format nil "c~d" (length choices))
                                             "search" "{\"q\":\"more\"}")))))
         (agent (make-ai-agent :name "looping" :backend backend
                               :settings (make-agent-settings :max-steps 2))))
    (define-agent-tool agent "search" (:description "Search the notes.") (args)
      (declare (ignore args))
      "one more hit")
    (let ((run (with-agent-loop (run-ai-agent agent "find everything"))))
      (list :finish (agent-run-finish-reason run)
            :text (agent-run-text run)
            :last-tool-choice (first choices)))))

(defun example-typed-tool-failure ()
  "A tool signals TOOL-INPUT-ERROR. The model gets a tool result that says
what to fix, not a crash, and calls again with good arguments.
Returns (:first-result \"Tool lookup rejected its arguments: …\" :text …)."
  (let* ((agent (make-ai-agent
                 :name "lookup-user"
                 :backend (scripted-backend '(("lookup" . "{}")
                                              ("lookup" . "{\"id\":\"42\"}")
                                              "User 42 is Ada.")))))
    ;; ARGS is the raw JSON string the model sent; parse it with a
    ;; json-protocol backend in real code.
    (define-agent-tool agent "lookup" (:description "Look up a user by id.") (args)
      (unless (search "\"id\"" args)
        (error 'tool-input-error :message "id is required"))
      "user 42: Ada")
    (let ((run (with-agent-loop (run-ai-agent agent "who is 42?"))))
      (list :first-result (agent-invocation-result (first (agent-run-invocations run)))
            :text (agent-run-text run)))))
