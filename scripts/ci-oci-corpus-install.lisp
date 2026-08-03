;;;; Install HTTP stack from GHCR for hub corpus consumer (#32).
;;;; Cleartext path — no cl-stack-ssl overlay (avoids SSL rewire / two-phase).
;;;; Always oras-install pinned packages (do not skip when a sibling ASDF tree exists).

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

(cl-repo:add-registry "https://ghcr.io" :namespace "egao1980/cl-systems" :priority :prepend)

(defun ci-on-disk-p (name)
  (cl-repository-client/quickload::system-already-installed-p name))

(defun ci-install (oci-name &key (version "latest"))
  (format t "~&; ci: install ~a:~a~%" oci-name version)
  (cl-repository-client/installer:install-system
   "https://ghcr.io" (format nil "egao1980/cl-systems/~a" oci-name) version)
  (cl-repository-client/asdf-integration:configure-asdf-source-registry)
  (unless (ci-on-disk-p oci-name)
    ;; Some packages register under a different ASDF name (cl-plus-ssl → cl+ssl).
    (format t "~&; ci: note: ~a install finished (on-disk=~a)~%"
            oci-name (ci-on-disk-p oci-name))))

(call-with-ci-muffles
 (lambda ()
   ;; System OpenSSL only (cleartext consumer). No cl-stack-ssl.
   (ci-install "cl-plus-ssl" :version "latest")
   (ci-install "cl-idna" :version "0.1.0")
   (ci-install "quri" :version "0.7.1")
   (ci-install "http-protocol" :version "0.1.0")
   (ci-install "http-encoding-chipz" :version "0.1.0")
   (ci-install "http-backend-dexador" :version "0.1.0")
   (ci-install "chipz" :version "0.8")
   (ci-install "salza2" :version "2.1")
   (dolist (n '("cl-idna" "quri" "http-protocol" "http-encoding-chipz"
                "http-backend-dexador" "chipz" "salza2"))
     (unless (ci-on-disk-p n)
       (error "ci: ~a missing from cl-repository systems root after install" n)))
   (dolist (n '("rove" "dexador" "babel" "alexandria" "ironclad" "usocket"
                "bordeaux-threads" "trivial-gray-streams" "cl-cookie" "cl-unicode"
                "blackbird"))
     (unless (or (ci-on-disk-p n) (asdf:find-system n nil))
       (format t "~&; ci: ql fallback ~a~%" n)
       (ql:quickload n :silent t)))))

(format t "~&; ci: oci-corpus install done~%")
(uiop:quit 0)
