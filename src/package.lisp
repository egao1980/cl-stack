(defpackage #:cl-stack
  (:use #:cl)
  (:export #:apply-pins
           #:read-pins
           #:pin-systems
           #:pin-channel
           #:pin-registry
           #:platforms-match-p
           #:parse-system-entry
           #:*default-pins-path*))

(in-package #:cl-stack)

(defparameter *default-pins-path*
  nil
  "Set after ASDF load to pins/stable.pins under this system.")
