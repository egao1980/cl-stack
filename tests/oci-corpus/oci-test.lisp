(in-package #:cl-stack/oci-corpus)

(defun %corpus-root ()
  (asdf:system-relative-pathname "cl-stack" "tests/corpus/"))

(defun %corpus-file (relative)
  (merge-pathnames relative (%corpus-root)))

(defun %read-form (path)
  (with-open-file (in path) (read in)))

(defun %file-bytes (path)
  (alexandria:read-file-into-byte-vector path))

(defun system-installed-via-oci-p (name)
  "True when ASDF locates NAME under the cl-repository systems root."
  (let* ((sys (asdf:find-system name nil))
         (path (and sys (asdf:system-source-directory sys)))
         (root (ignore-errors (cl-repository-client/installer:systems-root))))
    (unless (and sys path root)
      (return-from system-installed-via-oci-p nil))
    (let ((p (namestring (uiop:ensure-directory-pathname path)))
          (r (namestring (uiop:ensure-directory-pathname root))))
      (and (>= (length p) (length r))
           (string= r p :end2 (length r))))))

(deftest oci-packages-from-ghcr
  "http-protocol / encoding / dexador resolve under cl-repository systems root."
  (dolist (n '("http-protocol" "http-encoding-chipz" "http-backend-dexador"))
    (testing n
      (ok (asdf:find-system n nil))
      (ok (system-installed-via-oci-p n)
          (format nil "~a not under ~a (got ~a)"
                  n
                  (ignore-errors (cl-repository-client/installer:systems-root))
                  (ignore-errors
                   (asdf:system-source-directory (asdf:find-system n))))))))

(deftest oci-ce-roundtrip-decode
  "Decode corpus gzip/zlib via OCI-installed http-encoding-chipz."
  (let* ((manifest (%read-form (%corpus-file "http/ce-roundtrip/manifest.lisp")))
         (entry (first manifest))
         (plain (%file-bytes
                 (%corpus-file (format nil "http/ce-roundtrip/~A"
                                       (getf entry :plaintext-file)))))
         (expected (babel:string-to-octets
                    (format nil "cl-stack corpus slice v1 - MIT synthetic~%")
                    :encoding :utf-8)))
    (ok (equalp expected plain))
    (dolist (vec (getf entry :vectors))
      (testing (format nil "~A" (getf vec :coding))
        (let* ((octets (%file-bytes
                        (%corpus-file (format nil "http/ce-roundtrip/~A"
                                              (getf vec :file)))))
               (decoded (decode-content-coding (getf vec :coding) octets)))
          (ok (equalp plain decoded)))))))

(deftest oci-dexador-cleartext-ok
  "OCI http-backend-dexador GET against local fixture."
  (with-fixture ()
    (let ((*http-backend* (make-dexador-backend)))
      (let ((res (http:get (fixture-url "/ok"))))
        (ok (= 200 (response-status res)))
        (ok (equalp (babel:string-to-octets "ok") (response-body res)))))))

(deftest oci-redirect-policy-corpus
  "Drive redirect-policy vectors through OCI dexador (follow / max-redirects)."
  (let ((rows (%read-form (%corpus-file "http/redirect-policy/vectors.lisp"))))
    (with-fixture ()
      (let ((*http-backend* (make-dexador-backend)))
        (dolist (row rows)
          (testing (princ-to-string (getf row :id))
            (let* ((status (getf row :status))
                   (follow (getf row :follow-method))
                   (path (format nil "/redirect/~A" status))
                   (max (if (eq follow :none) 0 5))
                   (res (http:get (fixture-url path) :max-redirects max)))
              (ecase follow
                (:none
                 (ok (= status (response-status res))))
                ((:get :preserve)
                 (ok (= 200 (response-status res))))))))))))
