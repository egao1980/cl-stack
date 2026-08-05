(in-package #:cl-stack)

(setf *default-pins-path*
      (merge-pathnames "pins/stable.pins"
                       (asdf:system-source-directory "cl-stack")))

(defun read-pins (path)
  "Read a cl-stack.pins S-expression from PATH. Returns the top-level list."
  (with-open-file (in path)
    (let ((*read-eval* nil))
      (read in))))

(defun pin-section (pins key)
  "Return the body of section KEY in PINS (e.g. :systems → list of entries)."
  (let ((cell (assoc key pins :test #'eq)))
    (when cell (rest cell))))

(defun pin-channel (pins)
  (first (pin-section pins :channel)))

(defun pin-systems (pins)
  (pin-section pins :systems))

(defun pin-registry (pins)
  "Values: registry URL and :namespace string from the pin file."
  (let ((sec (assoc :registry pins :test #'eq)))
    (values (second sec)
            (getf (cddr sec) :namespace))))

(defun platforms-match-p (platforms)
  "T when PLATFORMS is NIL (all) or matches the current OS."
  (cond ((null platforms) t)
        ((and (member :unix platforms) (not (uiop:os-windows-p))) t)
        ((and (member :windows platforms) (uiop:os-windows-p)) t)
        (t nil)))

(defun parse-system-entry (entry)
  "ENTRY → (values name version platforms). Platforms may be NIL."
  (destructuring-bind (name version &rest opts) entry
    (values (string-downcase (string name))
            (princ-to-string version)
            (getf opts :platforms))))
