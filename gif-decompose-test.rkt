#lang racket

(require rackunit
         rackunit/text-ui
         "gif-decompose.rkt")

(define cwd (string->path "/Users/chris/Projects/gif-image/"))

(define sunflower "images/Sunflower_as_gif_websafe.gif")
(define sample "images/sample.gif")
(define earth "images/Rotating_earth_(large).gif")
(define earth-small "images/200px-Rotating_earth_(large).gif")
(define newton "images/Newtons_cradle_animation_book_2.gif")
(define my "images/my.gif")

(define/provide-test-suite
  
  gif-decompose-tests
  
  (test-case
   "gif? recognises gifs"
   (for-each
    (lambda (x) (check-equal? (gif? (build-path "images" x)) #t))
    (filter (lambda (x) (regexp-match "gif" x)) (directory-list "images")))
   (check-equal? (gif? (build-path cwd "images/kif.png")) #f))
  
  (test-case
   "gif-dimensions gives correct logical size"
   (check-equal? (gif-dimensions earth) (cons 400 400))
   (check-equal? (gif-dimensions sunflower) (cons 250 297))
   (check-equal? (gif-dimensions sample) (cons 3 3)))
  
  (test-case
   "gif-images returns 44 valid images for earth"
   (let ([stills (gif-images earth)]) ; don't change
     (check-equal? (stream-length stills) 44)
     (stream-for-each (lambda (x) (check-equal? (gif? x) #t)) stills)
     (check-equal? (stream-length (gif-images sample)) 1)
     (check-equal? (gif? (stream-first (gif-images sample))) #t)
     (check-equal? (stream-length (gif-images sunflower)) 1)
     (check-equal? (gif? (stream-first (gif-images sunflower))) #t)))
  
  (test-case
   "gif: animated? knows whether a gif is animated"
   (check-equal? (gif-animated? earth) #t)
   (check-equal? (gif-animated? newton) #t)
   (check-equal? (gif-animated? earth-small) #t)
   (check-equal? (gif-animated? sample) #f)
   (check-equal? (gif-animated? sunflower) #f))
  
  (test-case
   "gif-timings returns 44 ninety millisecond delays from earth"
   (let ([delays (gif-timings earth)])
     (check-equal? (stream-length delays) 44)
     (stream-for-each (lambda (x) (check-equal? x 9/100)) delays)))
  
  (test-case
   "gif-comments returns 1 comment from sample, containing my name"
   (let ([cmts (gif-comments sample)])
     (check-equal? (stream-length cmts) 1)
     (check-equal? (stream-first cmts) #"Chris Bowdon"))))