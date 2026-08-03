(defsystem "cl-stack"
  :version "0.1.0"
  :description "cl-stack hub — docs, corpus, and smoke tests (no runtime library)"
  :author "egao1980"
  :license "MIT"
  :pathname "."
  :components ((:static-file "README.md")
               (:static-file "LICENSE"))
  :in-order-to ((test-op (test-op "cl-stack/corpus-smoke"))))

(defsystem "cl-stack/corpus-smoke"
  :description "Rove smoke: corpus layout + first MIT HTTP slice"
  :depends-on ("rove" "uiop" "alexandria" "babel" "ironclad")
  :pathname "tests/corpus-smoke"
  :serial t
  :components ((:file "package")
               (:file "corpus-test"))
  :perform (test-op (o c)
             (unless (symbol-call :rove :run c)
               (error "corpus-smoke failed"))))

(defsystem "cl-stack/oci-corpus"
  :description "OCI consumer: decode/redirect corpus via GHCR-installed HTTP stack"
  :depends-on ("rove" "uiop" "alexandria" "babel" "ironclad"
               "usocket" "bordeaux-threads"
               "http-protocol" "http-encoding-chipz" "http-backend-dexador"
               "cl-repository-client")
  :pathname "tests/oci-corpus"
  :serial t
  :components ((:file "package")
               (:file "fixture")
               (:file "oci-test"))
  :perform (test-op (o c)
             (unless (symbol-call :rove :run c)
               (error "oci-corpus failed"))))
