(in-package #:cl-stack/oci-corpus)

;;; Minimal cleartext HTTP/1.1 origin for OCI consumer redirect/CE checks.

(defvar *fixture-thread* nil)
(defvar *fixture-socket* nil)
(defvar *fixture-port* nil)

(defun %read-line-octets (stream)
  (let ((out (make-array 0 :element-type '(unsigned-byte 8)
                           :adjustable t :fill-pointer 0)))
    (loop for b = (read-byte stream nil nil)
          while b
          do (vector-push-extend b out)
             (when (and (>= (length out) 2)
                        (= (aref out (- (length out) 2)) 13)
                        (= (aref out (- (length out) 1)) 10))
               (return)))
    (when (plusp (length out))
      (babel:octets-to-string out :encoding :utf-8 :errorp nil))))

(defun %split-space (string)
  (loop for start = 0 then (1+ pos)
        for pos = (position #\Space string :start start)
        collect (subseq string start (or pos (length string)))
        while pos))

(defun %corpus-handler (method path headers body)
  "Serve corpus redirect-policy vectors + /ok + gzip CE."
  (declare (ignore method headers body))
  (cond
    ((string= path "/ok")
     (values 200 '(("content-type" . "text/plain"))
             (babel:string-to-octets "ok")))
    ((string= path "/echo")
     (values 200 '(("content-type" . "text/plain"))
             (babel:string-to-octets "echo")))
    ((string= path "/redirect/302")
     (values 302 '(("location" . "/ok") ("content-type" . "text/plain"))
             (babel:string-to-octets "go")))
    ((string= path "/redirect/301")
     (values 301 '(("location" . "/ok") ("content-type" . "text/plain"))
             (babel:string-to-octets "go")))
    ((string= path "/redirect/303")
     (values 303 '(("location" . "/ok") ("content-type" . "text/plain"))
             (babel:string-to-octets "go")))
    ((string= path "/redirect/307")
     (values 307 '(("location" . "/echo") ("content-type" . "text/plain"))
             (babel:string-to-octets "go")))
    ((string= path "/redirect/308")
     (values 308 '(("location" . "/echo") ("content-type" . "text/plain"))
             (babel:string-to-octets "go")))
    ((string= path "/gzip-corpus")
     (let* ((root (asdf:system-relative-pathname "cl-stack" "tests/corpus/"))
            (gz (alexandria:read-file-into-byte-vector
                 (merge-pathnames "http/ce-roundtrip/plaintext.gz" root))))
       (values 200
               '(("content-type" . "text/plain")
                 ("content-encoding" . "gzip"))
               gz)))
    (t
     (values 404 '(("content-type" . "text/plain"))
             (babel:string-to-octets "nope")))))

(defun %serve-one (stream)
  (handler-case
      (let* ((req-line (%read-line-octets stream))
             (content-length 0))
        (unless req-line (return-from %serve-one nil))
        (loop for line = (%read-line-octets stream)
              while (and line
                         (not (string= line (format nil "~C~C" #\Return #\Newline)))
                         (not (string= line (string #\Newline)))
                         (> (length line) 2))
              do (let* ((s (string-right-trim '(#\Return #\Newline) line))
                        (colon (position #\: s)))
                   (when colon
                     (let ((name (string-downcase (subseq s 0 colon)))
                           (val (string-trim '(#\Space #\Tab) (subseq s (1+ colon)))))
                       (when (string= name "content-length")
                         (setf content-length (or (parse-integer val :junk-allowed t) 0)))))))
        (let* ((parts (%split-space (string-right-trim '(#\Return #\Newline) req-line)))
               (method (first parts))
               (path (second parts))
               (body (when (plusp content-length)
                       (let ((buf (make-array content-length
                                              :element-type '(unsigned-byte 8))))
                         (read-sequence buf stream)
                         buf))))
          (multiple-value-bind (status hdrs resp-body)
              (%corpus-handler method path nil body)
            (let* ((body* (or resp-body #()))
                   (hdr-str
                    (with-output-to-string (s)
                      (format s "HTTP/1.1 ~D x~C~C" status #\Return #\Newline)
                      (dolist (h hdrs)
                        (format s "~A: ~A~C~C" (car h) (cdr h) #\Return #\Newline))
                      (format s "Content-Length: ~D~C~C" (length body*)
                              #\Return #\Newline)
                      (format s "Connection: close~C~C~C~C"
                              #\Return #\Newline #\Return #\Newline)))
                   (head (babel:string-to-octets hdr-str)))
              (write-sequence head stream)
              (write-sequence body* stream)
              (force-output stream)))))
    (error () nil)))

(defun start-fixture ()
  (when *fixture-thread* (stop-fixture))
  (let* ((server (usocket:socket-listen "127.0.0.1" 0
                                        :reuseaddress t
                                        :element-type '(unsigned-byte 8)))
         (port (usocket:get-local-port server)))
    (setf *fixture-socket* server
          *fixture-port* port
          *fixture-thread*
          (bt:make-thread
           (lambda ()
             (loop
               (when (null *fixture-socket*) (return))
               (handler-case
                   (let ((client (usocket:socket-accept
                                  server :element-type '(unsigned-byte 8))))
                     (unwind-protect
                          (%serve-one (usocket:socket-stream client))
                       (usocket:socket-close client)))
                 (error ()
                   (when (null *fixture-socket*) (return))))))
           :name "cl-stack-oci-corpus-fixture"))
    port))

(defun stop-fixture ()
  (let ((s *fixture-socket*))
    (setf *fixture-socket* nil *fixture-port* nil)
    (when s (ignore-errors (usocket:socket-close s)))
    (when (and *fixture-thread* (bt:thread-alive-p *fixture-thread*))
      (ignore-errors (bt:destroy-thread *fixture-thread*))
      (setf *fixture-thread* nil))))

(defun fixture-url (path)
  (format nil "http://127.0.0.1:~A~A" *fixture-port* path))

(defmacro with-fixture (() &body body)
  `(progn
     (start-fixture)
     (unwind-protect (progn ,@body)
       (stop-fixture))))
