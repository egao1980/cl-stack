(defsystem "cl-stack"
  :version "0.1.0"
  :description "cl-stack hub — docs, pin parse, corpus (metapackage = cl-stack/meta)"
  :author "egao1980"
  :license "MIT"
  :pathname "."
  :depends-on ("uiop")
  :components ((:static-file "README.md")
               (:static-file "LICENSE")
               (:module "src"
                :serial t
                :components ((:file "package")
                             (:file "read-pins"))))
  :in-order-to ((test-op (test-op "cl-stack/corpus-smoke")
                         (test-op "cl-stack/pins-test"))))

(defsystem "cl-stack/pins"
  :description "Install cl-stack.pins via cl-repository-client (apply-pins)"
  :license "MIT"
  :version "0.1.0"
  :depends-on ("cl-stack" "cl-repository-client" "uiop")
  :pathname "src"
  :serial t
  :components ((:file "apply-pins")))

(defsystem "cl-stack/meta"
  :description "Curated cl-stack metapackage — stable channel defaults (ASDF roots)"
  :author "egao1980"
  :license "MIT"
  :version "0.1.0"
  :depends-on ("cl-stack-pathlib"
               "event-protocol"
               "event-backend-libuv"
               "cl-stack-ssl"
               "json-protocol"
               "json-backend-jzon"
               "http-protocol"
               "http-encoding-chipz"
               "http-encoding-brotli"
               "http-encoding-zstd"
               "http-backend-dexador"
               "http-backend-async"
               "cl-stack-http"
               "cl-stack-jwt"
               "cl-stack-oauth2"
               "ws-protocol")
  ;; Pure dependency umbrella (Anaconda-style metapackage) — no Lisp sources.
  :components ())

(defsystem "cl-stack/pins-test"
  :description "Rove: pin file parse + platform filter (no network)"
  :depends-on ("rove" "cl-stack" "uiop")
  :pathname "tests/pins"
  :serial t
  :components ((:file "package")
               (:file "pins-test"))
  :perform (test-op (o c)
             (unless (symbol-call :rove :run c)
               (error "pins-test failed"))))

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

(defsystem "cl-stack/meta-e2e"
  :description "E2E: after apply-pins, assert cl-stack/meta loads (CI)"
  :depends-on ("rove" "cl-stack" "cl-stack/meta")
  :pathname "tests/meta-e2e"
  :serial t
  :components ((:file "package")
               (:file "meta-e2e-test"))
  :perform (test-op (o c)
             (unless (symbol-call :rove :run c)
               (error "meta-e2e failed"))))
