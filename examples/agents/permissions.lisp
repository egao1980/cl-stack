;;;; Permission rules: {action, resource, effect}, last match wins, a deny on
;;;; any resource wins, a policy layer only tightens (ai-agent-protocol 0.5+).

(in-package #:cl-stack-examples/agents)

(defun %path-tool (agent name ran)
  "Register tool NAME whose resource is the \"path\" in its JSON arguments.
RAN's car collects the paths the tool really touched."
  (register-agent-tool
   agent
   (make-function-tool
    :name name
    :description (format nil "~:(~a~) a file." name)
    :permission-resources (lambda (arguments)
                            (let* ((start (+ (search "\"path\":\"" arguments) 8))
                                   (end (position #\" arguments :start start)))
                              (list (subseq arguments start end))))
    :handler (lambda (arguments)
               (push arguments (car ran))
               "done"))))

(defun example-permissions ()
  "Agent layer: ask for everything, allow edits under src/, deny secrets/
with feedback. Run layer (settings) comes last. A policy denies .pem files
whatever the layers say. Denials reach the model as tool errors and the run
goes on.
Returns (:statuses (:done :denied :denied) :feedback-seen t :ran 1)."
  (let* ((ran (list nil))
         (agent (make-ai-agent
                 :name "coder"
                 :backend (scripted-backend
                           '(("edit" . "{\"path\":\"src/a.lisp\"}")
                             ("edit" . "{\"path\":\"secrets/key\"}")
                             ("edit" . "{\"path\":\"src/cert.pem\"}")
                             "Edited src/a.lisp; secrets and certificates are off limits."))
                 :permissions (list '("*" "*" :ask)
                                    '("edit" "src/*" :allow)
                                    (make-permission-rule
                                     "edit" "secrets/*" :deny
                                     :feedback "Secrets are off limits; edit src/ only."))
                 :settings (make-agent-settings
                            :extra (list :permission-policy '(("edit" "*.pem" :deny)))))))
    (%path-tool agent "edit" ran)
    (let ((run (with-agent-loop (run-ai-agent agent "tidy the project"))))
      (list :statuses (mapcar #'agent-invocation-status (agent-run-invocations run))
            :feedback-seen (and (search "Secrets are off limits"
                                        (agent-invocation-result
                                         (second (agent-run-invocations run))))
                                t)
            :ran (length (car ran))
            :finish (agent-run-finish-reason run)))))

(defun example-permission-ask ()
  "An :ask rule pauses the run for approval. The host rejects with
feedback; after RESUME-AI-AGENT the model reads that feedback as a tool error.
Returns (:paused :approval :finish :stop :result \"…Use docs/ instead…\")."
  (let* ((ran (list nil))
         (agent (make-ai-agent
                 :name "writer"
                 :backend (scripted-backend '(("write" . "{\"path\":\"README.md\"}")
                                              "Understood, I will use docs/."))
                 :permissions '(("write" "*" :ask)))))
    (%path-tool agent "write" ran)
    (with-agent-loop
      (let* ((run (run-ai-agent agent "document it"))
             (paused (agent-run-finish-reason run)))
        (deny-invocation run (first (agent-run-pending run))
                         :feedback "Use docs/ instead of the README.")
        (let ((run (resume-ai-agent run)))
          (list :paused paused
                :finish (agent-run-finish-reason run)
                :result (agent-invocation-result (first (agent-run-invocations run)))
                :ran (length (car ran))))))))
