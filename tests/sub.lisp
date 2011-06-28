;;; -*- Mode:Lisp; Syntax:ANSI-Common-Lisp; Coding:utf-8 -*-

(in-package #:cl-num-utils-tests)

(deftestsuite sub-tests (cl-num-utils-tests)
  ()
  (:equality-test #'equalp))

(addtest (sub-tests)
  test-sub
  (let ((a (ia 3 4))
        (*lift-equality-test* #'equalp))
    (ensure-same (sub a (cons 0 -1) (cons 0 -1))
                 #2A((0 1 2)
                     (4 5 6)))
    (ensure-same (sub a (cons 1 -1) t)
                 #2A((4 5 6 7)))
    (ensure-same (sub a (incl 1 1) t)
                 #2A((4 5 6 7)))
    (ensure-same (sub a 1 t)
                 #(4 5 6 7))
    (ensure-same (sub a (rev t) (cat (cons 0 2) (cons 2 4)))
                 #2A((8 9 10 11)
                     (4 5 6 7)
                     (0 1 2 3)))
    (ensure-same (sub a t 2) #(2 6 10))
    (ensure (not (equalp (sub a 1 t)
                         #2A((4 5 6 7)))))))

(addtest (sub-tests)
  test-setf-sub
  (let ((b (ia 2 3))
        (*lift-equality-test* #'equalp))
    (let ((a (ia 3 4)))
      (ensure-same (setf (sub a (cons 1 nil) (cons 1 nil)) b) b)
      (ensure-same a #2A((0 1 2 3)
                         (4 0 1 2)
                         (8 3 4 5)))
      (ensure-same b (ia 2 3)))
    (let ((a (ia 3 4)))
      (ensure-same (setf (sub a (cons 0 -1) #(3 2 1)) b) b)
      (ensure-same a #2A((0 2 1 0)
                         (4 5 4 3)
                         (8 9 10 11)))
      (ensure-same b (ia 2 3))
      (ensure-error (setf (sub a 2 4) (list 3)))
      (ensure-error (setf (sub a 2 4) (vector 3))))))

(addtest (sub-tests)
  test-sub-ivec
  (let ((a (ivec 10)))
    (ensure-same (sub a (ivec* 0 nil)) a)
    (ensure-same (sub a (ivec* 0 nil 1)) a)
    (ensure-same (sub a (ivec* 0 nil 2)) #(0 2 4 6 8))
    (ensure-same (sub a (ivec* 0 9 2)) #(0 2 4 6 8))
    (ensure-same (sub a (ivec* 0 8 2)) #(0 2 4 6))
    (ensure-same (sub a (ivec* 1 9 2)) #(1 3 5 7))
    (ensure-same (sub a (ivec* 1 -1 2)) #(1 3 5 7))
    (ensure-same (sub a (ivec* 1 nil 2)) #(1 3 5 7 9))
    (ensure-same (sub a (ivec* 0 nil 3)) #(0 3 6 9))
    (ensure-same (sub a (ivec* 0 -1 3)) #(0 3 6))
    (ensure-same (sub a (ivec* 1 -1 3)) #(1 4 7))
    (ensure-same (sub a (ivec* 1 7 3)) #(1 4))
    (ensure-same (sub a (sub (rev (ivec* 0 nil 3)) #(0 1))) #(9 6))))

(addtest (sub-tests)
  test-asub
  (ensure-same (asub (ia 10) (mask #'evenp it)) #(0 2 4 6 8)))
