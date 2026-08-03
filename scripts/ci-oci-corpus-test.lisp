;;;; Load OCI-installed HTTP stack + run cl-stack/oci-corpus (#32).

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

(call-with-ci-muffles (lambda () (asdf:load-system "cl-repository-client")))
(cl-repository-client/asdf-integration:configure-asdf-source-registry)
(cl-repository-client/asdf-integration:load-system-init-files)

(call-with-ci-muffles
 (lambda ()
   (dolist (n '("rove" "babel" "alexandria" "ironclad" "usocket" "bordeaux-threads"
                "dexador" "trivial-gray-streams" "cl-cookie" "blackbird"))
     (unless (asdf:find-system n nil)
       (ql:quickload n :silent t)))
   (asdf:load-system "cl+ssl")
   (asdf:load-system "http-protocol")
   (asdf:load-system "http-encoding-chipz")
   (asdf:load-system "http-backend-dexador")
   ;; Hub test system from checkout (corpus files live here).
   (asdf:test-system "cl-stack/oci-corpus")))

(uiop:quit 0)
