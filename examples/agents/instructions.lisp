;;;; Path-scoped AGENTS.md found as the agent reaches them, and the base
;;;; system prompt builder (steer-protocol 0.3+, ai-agent-protocol 0.6+).

(in-package #:cl-stack-examples/agents)

(defun %write-file (path text)
  (ensure-directories-exist path)
  (with-open-file (s path :direction :output :if-exists :supersede
                          :external-format :utf-8)
    (write-string text s)))

(defmacro with-demo-project ((root) &body body)
  "Bind ROOT to a temporary project with AGENTS.md at the top and in src/."
  `(let ((,root (uiop:ensure-directory-pathname
                 (merge-pathnames (format nil "cl-stack-example-~36r/" (random (expt 36 6)))
                                  (uiop:temporary-directory)))))
     (unwind-protect
          (progn
            (%write-file (merge-pathnames "AGENTS.md" ,root) "Run the tests before you finish.")
            (%write-file (merge-pathnames "src/AGENTS.md" ,root) "src/: no global state.")
            (%write-file (merge-pathnames "src/net.lisp" ,root) "(in-package :net)")
            (setf ,root (truename ,root))
            ,@body)
       (uiop:delete-directory-tree ,root :validate t :if-does-not-exist :ignore))))

(defun example-instructions ()
  "The model reads src/net.lisp, then src/tls.lisp. Before the second
generate the run injects the root and src/ AGENTS.md as one turn; the second
read adds nothing (already in context).
Returns (:injected (\"AGENTS.md\" \"src/AGENTS.md\") :instruction-turns 1)."
  (with-demo-project (root)
    (let* ((events (list nil))
           (agent (make-ai-agent
                   :name "coder"
                   :backend (scripted-backend '(("read" . "{\"path\":\"src/net.lisp\"}")
                                                ("read" . "{\"path\":\"src/tls.lisp\"}")
                                                "Read both files."))
                   :settings (make-agent-settings
                              :extra (list :instructions-discovery root)))))
      (define-agent-tool agent "read" (:description "Read a file.") (args)
        (declare (ignore args))
        "(contents)")
      (let ((run (with-agent-loop
                   (run-ai-agent agent "review src"
                                 :on-event (collect-events events :instructions)))))
        (list :injected (loop for (nil . directives) in (reverse (car events))
                              append (mapcar #'stack-steer:steer-directive-name directives))
              :instruction-turns (count-if (lambda (turn)
                                             (search "<instructions " (turn-text turn)))
                                           (agent-run-turns run))
              :finish (agent-run-finish-reason run))))))

(defun example-system-prompt ()
  "A short system prompt that mentions only the tools the agent has, worded
for the model family. Returns the prompt string."
  (stack-steer:build-system-prompt :tools '("read" "edit" "bash")
                                   :model "claude-opus-5-5"))
