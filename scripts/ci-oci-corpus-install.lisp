;;;; Install HTTP stack from GHCR for hub corpus consumer (#32).
;;;; Cleartext path — no cl-stack-ssl overlay (avoids SSL rewire / two-phase).

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

(defparameter *ci-ql-sources*
  '(("babel" :ql)
    ("trivial-features" :ql)
    ("cl-unicode" :ql)))

(cl-repo:add-registry "https://ghcr.io" :namespace "egao1980/cl-systems" :priority :prepend)

(defun ci-on-disk-p (name)
  (cl-repository-client/quickload::system-already-installed-p name))

(defun ci-fetch (name &key version)
  "Resolve + install NAME without ASDF-loading mid-flight."
  (format t "~&; ci: fetch ~a~@[:~a~]~%" name version)
  (cl-repository-client/source-policy:call-with-policy-overrides
   *ci-ql-sources* nil nil nil
   (lambda ()
     (cl-repository-client/protected-systems:ensure-snapshot)
     (cl-repository-client/digest-cache:load-digest-cache)
     (let ((plan (cl-repository-client/quickload::compute-install-plan
                  (list name) :version version)))
       (dolist (entry plan)
         (let ((n (car entry))
               (ver (cdr entry)))
           (unless (or (cl-repository-client/source-policy:system-denied-p n)
                       (and (ci-on-disk-p n)
                            (let ((iv (cl-repository-client/quickload::installed-system-version n)))
                              (and iv (string= iv (princ-to-string ver))))))
             (format t "~&; ci: ensure-installed ~a~@[:~a~]~%" n ver)
             (let ((result (cl-repository-client/quickload::ensure-system-installed
                            n :version ver)))
               (when result
                 (cl-repository-client/asdf-integration:configure-asdf-source-registry))))))
       (when cl-repository-client/quickload::*missing-deps-accumulator*
         (format t "~&; ci: deferring ql fallback: ~{~a~^, ~}~%"
                 cl-repository-client/quickload::*missing-deps-accumulator*)))))
  (cl-repository-client/asdf-integration:configure-asdf-source-registry)
  (unless (ci-on-disk-p name)
    (error "ci-fetch: ~a not on disk after install" name)))

(call-with-ci-muffles
 (lambda ()
   ;; System OpenSSL only (cleartext consumer). No cl-stack-ssl.
   (cl-repository-client/installer:install-system
    "https://ghcr.io" "egao1980/cl-systems/cl-plus-ssl" "latest")
   (cl-repository-client/asdf-integration:configure-asdf-source-registry)
   (ci-fetch "http-protocol" :version "0.1.0")
   (ci-fetch "http-encoding-chipz" :version "0.1.0")
   (ci-fetch "http-backend-dexador" :version "0.1.0")
   (ci-fetch "quri" :version "0.7.1")
   (ci-fetch "chipz" :version "0.8")
   (ci-fetch "salza2" :version "2.1")
   (dolist (n '("rove" "dexador" "babel" "alexandria" "ironclad" "usocket"
                "bordeaux-threads" "trivial-gray-streams" "cl-cookie" "cl-unicode"
                "blackbird"))
     (unless (or (ci-on-disk-p n) (asdf:find-system n nil))
       (format t "~&; ci: ql fallback ~a~%" n)
       (ql:quickload n :silent t)))))

(format t "~&; ci: oci-corpus install done~%")
(uiop:quit 0)
