(in-package #:cl-stack/corpus-smoke)

(defun %corpus-root ()
  (asdf:system-relative-pathname "cl-stack" "tests/corpus/"))

(defun %corpus-file (relative)
  (merge-pathnames relative (%corpus-root)))

(defun %read-form (path)
  (with-open-file (in path)
    (read in)))

(defun %file-bytes (path)
  (alexandria:read-file-into-byte-vector path))

(defun %sha256-hex (octets)
  (ironclad:byte-array-to-hex-string
   (ironclad:digest-sequence :sha256 octets)))

(defun %provenance-paths ()
  "Backtick-quoted relative paths from the PROVENANCE.md table."
  (let* ((text (uiop:read-file-string (%corpus-file "PROVENANCE.md")))
         (paths nil)
         (start 0))
    (loop
      (let ((a (search "`" text :start2 start)))
        (unless a (return))
        (let ((b (search "`" text :start2 (1+ a))))
          (unless b (return))
          (let ((p (subseq text (1+ a) b)))
            (when (and (find #\/ p) (not (search ".." p)))
              (pushnew p paths :test #'string=))
            (setf start (1+ b))))))
    (nreverse paths)))

(deftest corpus-layout-files-exist
  "Every PROVENANCE path exists on disk (#23 / #26)."
  (let ((paths (%provenance-paths)))
    (ok (plusp (length paths)))
    (dolist (p paths)
      (testing p
        (ok (probe-file (%corpus-file p)))))))

(deftest redirect-policy-vectors
  "Synthetic redirect policy table is well-formed."
  (let ((rows (%read-form (%corpus-file "http/redirect-policy/vectors.lisp"))))
    (ok (consp rows))
    (ok (>= (length rows) 5))
    (dolist (row rows)
      (testing (princ-to-string (getf row :id))
        (ok (or (stringp (getf row :id)) (keywordp (getf row :id))))
        (ok (integerp (getf row :status)))
        (ok (stringp (getf row :location)))
        (ok (member (getf row :follow-method)
                    '(:get :preserve :none) :test #'eq))
        (ok (integerp (getf row :history-len)))))))

(deftest ce-roundtrip-manifest-hashes
  "CE binaries match manifest SHA-256 (original MIT regenerates)."
  (let* ((manifest (%read-form (%corpus-file "http/ce-roundtrip/manifest.lisp")))
         (entry (first manifest))
         (plain-name (getf entry :plaintext-file))
         (plain (%file-bytes
                 (%corpus-file (format nil "http/ce-roundtrip/~A" plain-name))))
         (expected-plain (babel:string-to-octets
                          (format nil "cl-stack corpus slice v1 - MIT synthetic~%")
                          :encoding :utf-8)))
    (ok (equal "ce-roundtrip-v1" (getf entry :id)))
    (ok (equalp expected-plain plain))
    (dolist (vec (getf entry :vectors))
      (testing (format nil "~A" (getf vec :coding))
        (let* ((file (getf vec :file))
               (expected (getf vec :sha256))
               (octets (%file-bytes
                        (%corpus-file (format nil "http/ce-roundtrip/~A" file))))
               (got (%sha256-hex octets)))
          (ok (plusp (length octets)))
          (ok (string-equal expected got))
          (when (eq (getf vec :coding) :gzip)
            (ok (= #x1f (aref octets 0)))
            (ok (= #x8b (aref octets 1)))))))))

(deftest ws-echo-frames-vectors
  "Synthetic WS echo/framing table is well-formed (#4 wave-1 corpus)."
  (let ((rows (%read-form (%corpus-file "ws/echo-frames/vectors.lisp"))))
    (ok (consp rows))
    (ok (>= (length rows) 6))
    (dolist (row rows)
      (testing (princ-to-string (getf row :id))
        (ok (or (stringp (getf row :id)) (keywordp (getf row :id))))
        (ok (member (getf row :opcode)
                    '(:text :binary :close :ping :pong) :test #'eq))
        (let ((payload (getf row :payload)))
          (ok (or (stringp payload) (listp payload))))
        (when (eq (getf row :opcode) :close)
          (ok (integerp (getf row :close-code)))
          (ok (stringp (getf row :close-reason))))))))
