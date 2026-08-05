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
                    (declare (ignore c))
                    (let ((r (find-restart 'continue)))
                      (when r (invoke-restart r))))))
    (funcall fn))
  #-sbcl
  (funcall fn))

(call-with-ci-muffles (lambda () (asdf:load-system "cl-repository-client")))
(call-with-ci-muffles (lambda () (asdf:load-system "cl-stack/pins")))

(let ((pins (or (uiop:getenv "CL_STACK_PINS")
                (namestring
                 (merge-pathnames "pins/stable.pins"
                                  (asdf:system-source-directory "cl-stack"))))))
  (format t "~&; ci: apply-pins ~a~%" pins)
  (call-with-ci-muffles
   (lambda ()
     (cl-stack:apply-pins pins))))

(format t "~&; ci: meta install done~%")
(uiop:quit 0)
