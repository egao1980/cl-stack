(in-package #:cl-stack/pins-test)

(deftest stable-pins-parse
  (let* ((path (merge-pathnames "pins/stable.pins"
                                (asdf:system-source-directory "cl-stack")))
         (pins (read-pins path))
         (systems (pin-systems pins)))
    (ok (probe-file path) "stable.pins exists")
    (ok (eq :stable (pin-channel pins)))
    (ok (plusp (length systems)) "has systems")
    (multiple-value-bind (reg ns) (pin-registry pins)
      (ok (equal "https://ghcr.io" reg))
      (ok (equal "egao1980/cl-systems" ns)))
    (multiple-value-bind (name ver platforms)
        (parse-system-entry (find "http-protocol" systems
                                  :key #'first :test #'string-equal))
      (ok (equal "http-protocol" name))
      (ok (equal "0.3.4" ver))
      (ok (null platforms)))
    (multiple-value-bind (name ver platforms)
        (parse-system-entry (find "event-backend-libev" systems
                                  :key #'first :test #'string-equal))
      (ok (equal "event-backend-libev" name))
      (ok (equal "0.1.3" ver))
      (ok (equal '(:unix) platforms)))))

(deftest platforms-filter
  (ok (platforms-match-p nil))
  #+win32
  (progn
    (ok (platforms-match-p '(:windows)))
    (ng (platforms-match-p '(:unix))))
  #-win32
  (progn
    (ok (platforms-match-p '(:unix)))
    (ng (platforms-match-p '(:windows)))))

(deftest meta-system-registered
  (ok (asdf:find-system "cl-stack/meta" nil)
      "cl-stack/meta ASDF system is visible"))
