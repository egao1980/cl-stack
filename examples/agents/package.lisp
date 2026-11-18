;;;; Runnable examples for the agent harness tutorial
;;;; (docs/tutorials/agent-harness.md). Every example uses the mock LLM
;;;; backend, so it runs offline; swap in a real backend to try it live.

(defpackage #:cl-stack-examples/agents
  (:use #:cl #:ai-agent-protocol #:llm-protocol)
  (:export #:with-agent-loop
           #:scripted-backend
           #:example-retry
           #:example-compaction
           #:example-max-steps
           #:example-typed-tool-failure
           #:example-permissions
           #:example-permission-ask
           #:example-subagent
           #:example-instructions
           #:example-system-prompt))

(in-package #:cl-stack-examples/agents)

(defmacro with-agent-loop (&body body)
  "Run BODY with a libuv event loop bound, as sync RUN-AI-AGENT expects."
  `(let* ((eb (event-backend-libuv:make-libuv-backend))
          (el (event-protocol:make-event-loop eb)))
     (event-protocol:with-event-backend (eb)
       (event-protocol:with-event-loop-var (el)
         ,@body))))

(defun reply (text)
  "A final text response."
  (make-llm-response :parts (list (make-llm-text-part :text text))
                     :finish-reason :stop))

(defun tool-call (id name arguments)
  "A response that calls tool NAME with the JSON string ARGUMENTS."
  (make-llm-response
   :parts (list (make-llm-tool-call-part :id id :name name :arguments arguments))
   :finish-reason :tool-use))

(defun scripted-backend (steps)
  "Mock backend that plays STEPS in order, repeating the last one.
A step is a string (final reply), a cons (tool-name . json-arguments), or a
function of the turns that returns a response (or signals)."
  (let ((n 0))
    (make-mock-llm-backend
     :handler (lambda (backend turns &key &allow-other-keys)
                (declare (ignore backend))
                (let ((step (nth (min n (1- (length steps))) steps)))
                  (incf n)
                  (etypecase step
                    (string (reply step))
                    (cons (tool-call (format nil "c~d" n) (car step) (cdr step)))
                    (function (funcall step turns))))))))

(defun collect-events (box &rest kinds)
  "An :on-event callback that pushes (kind . payload) of KINDS onto BOX's car."
  (lambda (kind payload)
    (when (member kind kinds)
      (push (cons kind payload) (car box)))))
