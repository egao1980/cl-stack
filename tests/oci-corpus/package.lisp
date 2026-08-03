(defpackage #:cl-stack/oci-corpus
  (:use #:cl #:rove)
  (:import-from #:http-protocol
                #:decode-content-coding
                #:response-status
                #:response-body
                #:*http-backend*)
  (:import-from #:http-backend-dexador
                #:make-dexador-backend))

(in-package #:cl-stack/oci-corpus)
