#lang racket

(require "../api/main.rkt")

;TODO:
;  Analog pin down/up events
;  Reenable sound.  Memory allocation error!

(define (flash c1 c2)
  (repeat 10
          (set-brightness (random))
          (set-lights c1)
          (play-tone (+ 100 (* 300 (random))) 0.08)
          (set-lights c2)
          (play-tone (+ 100 (* 300 (random))) 0.08)
          ))

(define (destroy-effect)
  (flash red white)
  (flash orange yellow)
  (set-lights black))

;SETUP
(define (setup)
  ;(pin-write PIN_A7 #t)
  ;(set-lights green)
  (set state.memory.beam-start #f)
 )

;MAIN FUNCTION
(define (update)
  (if (shake 20)
      (destroy-effect)
      #f))

(on-down touch_A4
         (set-lights green)
         (play-tone 0.1 G4)
         (play-tone 0.1 C5)
         (pin-write PIN_A7 #t))

(on-down touch_A5
         (set-lights red)
         (play-tone 0.1 G4)
         (play-tone 0.1 C5)
         (pin-write PIN_A7 #f))

(on-down touch_A6
         (repeat 10
                 (pin-write PIN_A7 #t)
                 (play-tone 0.1 C5)
                 (pin-write PIN_A7 #f)
                 (play-tone 0.1 C4)))

(on-down touch_A3
         (loop n 100
                 (play-tone 0.05 (* 2 (+ 200 n)))
                 (set-brightness (random))  
                 (set-lights green))
         (play-riff jingle1)
         (set state.memory.beam-start #t))

(on-down touch_A1
         (if (get state.memory.beam-start)
             (begin
               (play-riff jingle1)
               (loop n 10
                       (set-light n black)
                       (wait 0.25)))
             #f))



(run) ;WART!
