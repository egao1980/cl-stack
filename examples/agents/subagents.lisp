;;;; Background subagents: start returns an id at once, the child's reply
;;;; arrives in the parent's inbox (ai-agent-protocol 0.5+).

(in-package #:cl-stack-examples/agents)

(defun example-subagent ()
  "The lead starts a researcher in the background and ends its turn. The run
waits for the child; its report lands as <subagent …> and the lead answers.
Returns (:started \"Started subagent researcher with id sub-1. …\"
         :text \"Lead: <subagent id=\\\"sub-1\\\" …>…</subagent>\" :waited t)."
  (let* ((events (list nil))
         (researcher (make-ai-agent
                      :name "researcher"
                      :instructions "Find one source for the claim."
                      :backend (make-mock-llm-backend
                                :handler (lambda (b turns &key &allow-other-keys)
                                           (declare (ignore b))
                                           (sleep 0.1) ; the child takes a while
                                           (reply (format nil "Source for ~s: CLHS 9."
                                                          (turn-text (car (last turns)))))))))
         (lead-backend
           (make-mock-llm-backend
            :handler (lambda (b turns &key &allow-other-keys)
                       (declare (ignore b))
                       (let ((last (car (last turns))))
                         (cond
                           ((and (eq :user (llm-turn-role last))
                                 (search "<subagent " (turn-text last)))
                            (reply (format nil "Lead: ~a" (turn-text last))))
                           ((eq :tool (llm-turn-role last))
                            (reply "Waiting for the researcher."))
                           (t
                            (tool-call "c1" "subagent"
                                       "{\"agent\":\"researcher\",\"prompt\":\"conditions\"}")))))))
         (lead (make-ai-agent :name "lead" :backend lead-backend
                              :tools (list (make-subagent-tool (list researcher)))))
         (run (with-agent-loop
                (run-ai-agent lead "check the claim"
                              :on-event (collect-events events :waiting :inbox)))))
    (list :started (agent-invocation-result (first (agent-run-invocations run)))
          :text (agent-run-text run)
          :waited (and (assoc :waiting (car events)) t))))
