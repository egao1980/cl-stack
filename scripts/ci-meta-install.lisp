;;;; #22: install stable pins from GHCR (no sibling checkouts, no grovel).

(setf *debugger-hook*
      (lambda (c h)
        (declare (ignore h))
        (format *error-output* "~&UNHANDLED: ~A~%" c)
        (uiop:quit 1)))

(setf asdf:*compile-file-failure-behaviour* :warn)

(defun call-with-ci-muffles (fn)
  #+sbcl
  (handler-bind ((sb-ext:defconstant-uneql
                  (lambda (c)
                    (let ((r (find-restart 'continue c)))
                      (when r (invoke-restart r))))))
    (funcall fn))
  #-sbcl
  (funcall fn))

(defun ci-record-installed-version (system env-var)
  (let ((ver (uiop:symbol-call :cl-repo :installed-system-version system))
        (env (uiop:getenv "GITHUB_ENV")))
    (when (and ver env)
      (with-open-file (out env :direction :output :if-exists :append :if-does-not-exist :create)
        (format out "~a=~a~%" env-var ver))
      (format t "~&; ci: ~a=~a~%" env-var ver))))

(call-with-ci-muffles (lambda () (asdf:load-system "cl-repository-client")))
(call-with-ci-muffles (lambda () (asdf:load-system "cl-stack/pins")))

(let ((pins (or (uiop:getenv "CL_STACK_PINS")
                (namestring
                 (merge-pathnames "pins/stable.pins"
                                  (asdf:system-source-directory "cl-stack"))))))
  (format t "~&; ci: apply-pins ~a~%" pins)
  (call-with-ci-muffles
   (lambda ()
     (cl-stack:apply-pins pins)
     ;; Fill QL-only transitive deps of pinned systems (e.g. com.inuoe.jzon).
     ;; cl-repo :sources QL policy still fails dotted names not on GHCR — force QL.
     (dolist (n '("com.inuoe.jzon" "yason"))
       (unless (asdf:find-system n nil)
         (format t "~&; ci: ql:quickload ~a~%" n)
         (ql:quickload n :silent t)))
     (cl-repo:ensure-system-dependencies "cl-stack/meta"
       :also-tests nil
       :sources '(("babel" :ql)
                  ("com.inuoe.jzon" :ql)
                  ("yason" :ql)
                  ("trivial-features" :ql)
                  ("cl-unicode" :ql)))
     (ci-record-installed-version "cl-stack-ssl" "CL_STACK_SSL_VERSION"))))

(format t "~&; ci: meta install done~%")
(uiop:quit 0)
