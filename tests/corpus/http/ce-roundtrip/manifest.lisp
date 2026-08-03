;;;; CE round-trip manifest (original MIT). See ../../PROVENANCE.md.
((:id "ce-roundtrip-v1"
  :plaintext-file "plaintext.txt"
  :vectors
  ((:coding :gzip :file "plaintext.gz"
    :sha256 "d1c6e181884de6703ba7e01cae8cffa46034690d4e60ca75babf671e816fa566")
   (:coding :deflate :file "plaintext.zlib"
    :note "zlib-wrapped deflate (chipz/salza2)"
    :sha256 "d0550fa12e5c3bfe07a9ba98afa464677dc787261ccad49f53119cd97bb23b97"))))
