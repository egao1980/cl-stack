;;;; Synthetic redirect-policy vectors (original MIT). See ../../PROVENANCE.md.
;;;; Each plist: :ID :STATUS :LOCATION :FOLLOW-METHOD (:get|:preserve) :HISTORY-LEN
((:id "302-relative-get" :status 302 :location "/ok" :follow-method :get :history-len 1)
 (:id "301-relative-get" :status 301 :location "/ok" :follow-method :get :history-len 1)
 (:id "303-relative-get" :status 303 :location "/ok" :follow-method :get :history-len 1)
 (:id "307-preserve" :status 307 :location "/echo" :follow-method :preserve :history-len 1)
 (:id "308-preserve" :status 308 :location "/echo" :follow-method :preserve :history-len 1)
 (:id "max-redirects-zero" :status 302 :location "/ok" :follow-method :none :history-len 0))
