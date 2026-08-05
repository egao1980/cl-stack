;;;; #22: load cl-stack/meta after pins; run meta-e2e Rove suite.

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
                    (declare (ignore c))
                    (let ((r (find-restart 'continue)))
                      (when r (invoke-restart r))))))
    (funcall fn))
  #-sbcl
  (funcall fn))

;; Overlays (ssl/brotli/zstd) already installed by apply-pins; load init if present.
(call-with-ci-muffles
 (lambda ()
   (when (asdf:find-system "cl-repository-client" nil)
     (uiop:symbol-call :cl-repository-client/asdf-integration
                       :configure-asdf-source-registry)
     (ignore-errors
       (uiop:symbol-call :cl-repository-client/asdf-integration
                         :load-system-init-files)))))

(call-with-ci-muffles
 (lambda ()
   (unless (asdf:find-system "rove" nil)
     (ql:quickload "rove" :silent t))
   (asdf:load-system "cl-stack/meta")
   (asdf:test-system "cl-stack/meta-e2e")))

(format t "~&; ci: meta-e2e ok~%")
(uiop:quit 0)
