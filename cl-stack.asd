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
