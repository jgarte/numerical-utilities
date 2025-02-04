;;; -*- Mode: LISP; Base: 10; Syntax: ANSI-Common-Lisp; Package: ASDF -*-
;;; Copyright (c) 2010 by Tamas K. Papp <tkpapp@gmail.com>
;;; Copyright (c) 2019-2022 by Symbolics Pte. Ltd. All rights reserved.

(defsystem "num-utils"
  :version "1.2.0"
  :license :MS-PL
  :author "Steven Nunez <steve@symbolics.tech>"
  :long-name "Numerical Utilities"
  :description "Numerical utilities for Common Lisp"
  :long-description  #.(uiop:read-file-string
			(uiop:subpathname *load-pathname* "description.text"))
  ;:homepage    "https://lisp-stat.dev/docs/tasks/plotting/"
  :source-control (:git "https://github.com/Lisp-Stat/numerical-utilities.git")
  :bug-tracker "https://github.com/Lisp-Stat/numerical-utilities/issues"

  :depends-on (#:anaphora
               #:alexandria
               #:array-operations
               #:select
               #:let-plus)
  :in-order-to ((test-op (test-op "num-utils/tests")))
  :pathname "src/"
  :serial t
  :components
  ((:file "packages")
   (:file "utilities")
   (:file "num=")
   (:file "arithmetic")
;;   (:file "arithmetic-type") ; now in src/old/ Looks like it was a WIP
   (:file "elementwise")
   (:file "extended-real")
   (:file "interval")
   (:file "print-matrix")
   (:file "matrix")
   (:file "matrix-shorthand")
   (:file "chebyshev")
   (:file "polynomial")
   (:file "rootfinding")
   (:file "quadrature")
   (:file "log-exp")
   (:file "test-utilities")
   (:file "pkgdcl")))

(defsystem "num-utils/tests"
  :version "1.0.0"
  :description "Unit tests for NUM-UTILS."
  :author "Steven Nunez <steve@symbolics.tech>"
  :license "Same as NUM-UTILS -- this is part of the NUM-UTILS library."
  #+asdf-unicode :encoding #+asdf-unicode :utf-8
  :depends-on (#:num-utils
               #:fiveam
	       #:select) ; matrix test needs this
  :pathname "tests/"
  :serial t
  :components
  ((:file "test-package")
   (:file "main")
   ;; in alphabetical order
   (:file "arithmetic")
;; (:file "arithmetic-type") ; No tests included in Papp's version
   (:file "chebyshev")
   (:file "polynomial")
   (:file "elementwise")
   (:file "extended-real")
   (:file "interval")
   (:file "matrix")
   (:file "matrix-shorthand")
   (:file "num=")
   (:file "quadrature")
   (:file "rootfinding")
   (:file "log-exp")
   (:file "utilities"))
  :perform (test-op (o s)
			 (uiop:symbol-call :fiveam :run!
					   (uiop:find-symbol* :all-tests
							      :num-utils-tests))))
