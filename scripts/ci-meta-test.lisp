;;;; #22: load cl-stack/meta after pins; run meta-e2e Rove suite.
;;;; Top-level forms only after client load — package-qualified symbols need
;;;; CL-REPOSITORY-CLIENT/ASDF-INTEGRATION to exist at READ time (ros -l).

(setf *debugger-hook*
      (lambda (c h)
        (declare (ignore h))
        #+sbcl
        (when (typep c 'sb-ext:defconstant-uneql)
          (let ((r (find-restart 'continue c)))
            (when r (invoke-restart r))))
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

(call-with-ci-muffles (lambda () (asdf:load-system "cl-repository-client")))

(cl-repository-client/asdf-integration:configure-asdf-source-registry)
(call-with-ci-muffles
 (lambda ()
   (cl-repository-client/asdf-integration:load-system-init-files)))

(call-with-ci-muffles
 (lambda ()
   (dolist (n '("rove" "com.inuoe.jzon" "yason"))
     (unless (asdf:find-system n nil)
       (ql:quickload n :silent t)))
   (asdf:load-system "cl-stack/meta")
   (asdf:test-system "cl-stack/meta-e2e")))

(format t "~&; ci: meta-e2e ok~%")
(uiop:quit 0)
