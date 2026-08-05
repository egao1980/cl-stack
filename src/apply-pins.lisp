(in-package #:cl-stack)

(defun apply-pins (path &key (load nil) force)
  "Install every applicable (:systems) entry from PATH via cl-repository.

   Requires CL-REPOSITORY-CLIENT loaded (system cl-stack/pins). Registry/namespace
   come from the pin file. Skips entries whose :platforms filter excludes this host.
   When LOAD is true, ASDF-loads each system after install.

   Returns the list of (name . version) pairs processed."
  (unless (find-package :cl-repo)
    (error "apply-pins needs cl-repository-client (load system \"cl-stack/pins\")"))
  (let* ((pins (read-pins path))
         (format-ver (first (pin-section pins :pin-format))))
    (unless (eql format-ver 1)
      (error "Unsupported :pin-format ~s (want 1) in ~a" format-ver path))
    (multiple-value-bind (registry namespace) (pin-registry pins)
      (unless (and registry namespace)
        (error "Pin file ~a missing :registry / :namespace" path))
      (uiop:symbol-call :cl-repo :add-registry
                        registry :namespace namespace :priority :prepend)
      (let ((installed '()))
        (dolist (entry (pin-systems pins))
          (multiple-value-bind (name version platforms) (parse-system-entry entry)
            (when (platforms-match-p platforms)
              (format t "~&; cl-stack: pin ~a:~a~%" name version)
              (uiop:symbol-call :cl-repo :ensure-systems
                                (list name) :version version :force force)
              (when load
                (asdf:load-system name))
              (push (cons name version) installed))))
        (nreverse installed)))))
