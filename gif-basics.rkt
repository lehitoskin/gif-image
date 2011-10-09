#lang racket

(provide header?
         header-size
         img?
         img-size
         gce?
         gce-size
         appn?
         appn-size
         comment?
         comment-size
         plain-text?
         plain-text-size
         trailer?
         stream-reverse         
         has-n-subblocks?
         subblocks)

(require "bits-and-bytes.rkt")

; could achieve much more efficiency by jumping over recognised extensions

; return all instances of a particular kind of subblock
(define (subblocks data pred? size)
  (define (sbs-iter byte sbs)
    (cond [(trailer? data byte) (stream-reverse sbs)]
          [(pred? data byte)
           (let ([s (size data byte)])
             (sbs-iter (+ byte s) (stream-cons (subbytes data byte (+ byte s)) sbs)))]
          [else (sbs-iter (+ byte 1) sbs)]))
  (sbs-iter 0 '()))

; not efficient 
; and
; only tested implicitly
(define (has-n-subblocks? data pred? size n)
  (define (h-iter byte count)
    (cond [(equal? count n) #t]
          [(trailer? data byte) #f]
          [(pred? data byte)
           (h-iter (+ byte (size data byte)) (+ count 1))]
          [else (h-iter (+ byte 1) count)]))
  (h-iter 0 0))


; traverse data sub-blocks
(define (subblocks-size data b)
  (let ([len (bytes-length data)])
    (cond [(> b len) (error "subblocks-size: exceeded EOF")]
          [(or
            (trailer? data b)
            (img? data b)
            (extn? data b))
           b]
          ; termination byte?
          [(null-byte? data b) (+ b 1)]
          [else 
           ; jumps over subblocks
           (subblocks-size data (+ b (bytes-ref data b) 1))])))

; stream-reverse
; not convinced of benefits, but works
(define (stream-reverse x)
  (define (stream-reverse-iter x y)
    (if [stream-empty? x]
        y
        (stream-reverse-iter (stream-rest x) (stream-cons (stream-first x) y))))
  (stream-reverse-iter x empty-stream))

; size of logical screen
(define (logical-size data)
  (bytes->coord data 6))

; size of global color table
(define (gct-size data)
  (let* ([packed-field (byte->bits (bytes-ref data 10))]
         [flag (first packed-field)]
         [i (+ 1
               (* flag ; could be b&w
                  (+ 
                   (* 4 (sixth packed-field)) 
                   (* 2 (seventh packed-field))
                   (eighth packed-field))))])
    (expt 2 i)))

(define (header? data [byte 0])
  (if [< (+ byte 6) (bytes-length data)]
      (let ([title (subbytes data byte (+ byte 3))]
            [version (subbytes data (+ byte 3) (+ byte 6))])
        (and   
         (equal? title #"GIF")
         (or
          (equal? version #"87a")
          (equal? version #"89a"))))
      #f))

(define (header-size data)
  (+ 13 (* 3 (gct-size data))))

(define (extn? data byte)
  (or
   (gce? data byte)
   (comment? data byte)
   (appn? data byte)
   (plain-text? data byte)))

; data on image descriptors
(define (img-dimensions data byte)
  (bytes->coord data (+ byte 5)))

(define (img-corner data byte)
  (bytes->coord data (+ byte 1)))

(define (img? data byte)
  (if [< (+ byte 9) (bytes-length data)]
      (let* (; img descriptor marker (should be 0x2C)
             [id-0 (bytes-ref data byte)]
             ; gif dimensions
             [gdims (logical-size data)]
             ; image corner
             [corner (img-corner data byte)]
             ; image dimensions 
             [idims (img-dimensions data byte)])
        (and
         (equal? id-0 44)
         (<= (car idims) (car gdims))
         (<= (cdr idims) (cdr gdims))
         (<= (car corner) (car gdims))
         (<= (cdr corner) (cdr gdims))))
      #f))

(define (img-size data byte)
  (let* (; packed fields in img descriptor
         [id-9 (byte->bits (bytes-ref data (+ byte 9)))]
         ; size of local color table
         [lct-size (if (equal? (first id-9) 1)
                       (expt 2 (+ 1 
                                  (* 4 (sixth id-9)) 
                                  (* 2 (seventh id-9))
                                  (eighth id-9)))
                       0)]
         ; LZW-min-size 
         [LZW-min (+ byte 9 lct-size 1)]
         ; first byte of data subblocks
         [data-first (+ byte 9 lct-size 2)]
         ; length of file
         [len (bytes-length data)])
    ; loop through data until not data
    (- (subblocks-size data data-first) byte)))

(define (gce? data byte)
  (if [< (+ byte 6) (bytes-length data)]
      (let (; first byte should be extn marker
            [id-0 (bytes-ref data byte)]
            ; graphic control extension marker
            [id-1 (bytes-ref data (+ byte 1))]
            ; size marker is always 4
            [id-2 (bytes-ref data (+ byte 2))]
            ; termination byte
            [id-6 (bytes-ref data (+ byte 6))])
        (and
         (equal? id-0 33)
         (equal? id-1 249)
         (equal? id-2 4)
         (equal? id-6 0)))
      #f))

(define (gce-size data byte) 8)

(define (comment? data byte)
  (if [< (+ byte 2) (bytes-length data)]
      (let (; img descriptor marker (should be 0x21)
            [id-0 (bytes-ref data byte)]
            ; 2nd byte labels extension type
            [id-1 (bytes-ref data (+ byte 1))])
        (and 
         (equal? id-0 33)
         (equal? id-1 254)))
      #f))

(define (appn? data byte)
  (if [< (+ byte 16) (bytes-length data)]
      (let (; first byte should be extn marker
            [id-0 (bytes-ref data byte)]
            ; application extension marker
            [id-1 (bytes-ref data (+ byte 1))]
            ; size marker is always 11
            [id-2 (bytes-ref data (+ byte 2))])
        (and
         (equal? id-0 33)
         (equal? id-1 255)
         (equal? id-2 11)))
      #f))

(define (appn-size data byte)
  (let* (; data sub-blocks start at 15th byte
         [data-first (+ byte 14)]
         [sb-size (subblocks-size data data-first)])
    (- sb-size byte)))

(define (comment-size data byte)
  (let* (; data sub-blocks start at 3rd byte
         [data-first (+ byte 2)]
         [sb-size (subblocks-size data data-first)])
    (- sb-size byte)))

; untested!
(define (plain-text? data byte)
  (if [< (+ byte 16) (bytes-length data)]
      (let (; first byte should be extn marker
            [id-0 (bytes-ref data byte)]
            ; plain-text extension marker
            [id-1 (bytes-ref data (+ byte 1))]
            ; size marker is always 12
            [id-2 (bytes-ref data (+ byte 2))])
        (and
         (equal? id-0 33)
         (equal? id-1 1)
         (equal? id-2 12)))
      #f))

; untested!
(define (plain-text-size data byte)
  (let* (; data sub-blocks start at 16th byte
         [data-first (+ byte 15)]
         [sb-size (subblocks-size data data-first)])
    (- sb-size byte)))

(define (trailer? data byte) 
  (and
   (equal? byte (- (bytes-length data) 1))
   (equal? (bytes-ref data byte) 59)))




