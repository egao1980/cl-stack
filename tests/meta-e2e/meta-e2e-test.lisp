(in-package #:cl-stack/meta-e2e-test)

(deftest meta-loads
  "cl-stack/meta must be loadable after CI apply-pins (no grovel)."
  (ok (asdf:find-system "cl-stack/meta" nil))
  (ok (not (uiop:featurep :cl-stack-meta-grovel))
      "no grovel feature required")
  (asdf:load-system "cl-stack/meta")
  (ok (asdf:component-loaded-p (asdf:find-system "cl-stack/meta")))
  ;; Spot-check a few roots from the metapackage.
  (dolist (sys '("http-protocol" "cl-stack-http" "event-protocol"
                 "event-backend-libuv" "ws-protocol"))
    (ok (asdf:component-loaded-p (asdf:find-system sys))
        (format nil "~a loaded" sys))))
