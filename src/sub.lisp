;;; -*- Mode:Lisp; Syntax:ANSI-Common-Lisp; Coding:utf-8 -*-

(in-package #:cl-num-utils)

;;; Generic functions for querying dimensions and element types.

(defgeneric dims (object)
  (:documentation "Return the dimensions of object as a list.")
  (:method ((array array))
    (array-dimensions array)))

(defgeneric dim (object axis-number)
  (:documentation "Return the dimension of object along axis-number.")
  (:method ((array array) axis-number)
    (array-dimension array axis-number)))

(defgeneric rank (object)
  (:documentation "Return the number of dimensions.")
  (:method ((array array))
    (array-rank array)))

(defgeneric element-type (object)
  (:documentation "Return the element type of object.  Accessors return and
  allow setting subtypes of this type."))

(defgeneric nrow (object)
  (:documentation "Return number of rows in object.  Signal an error if OBJECT
  doesn't have exactly two dimensions.")
  (:method ((array array))
    (assert (= 2 (array-rank array)) () "Array is not a matrix.")
    (array-dimension array 0)))

(defgeneric ncol (object)
  (:documentation "Return number of columns in object.  Signal an error if
  OBJECT doesn't have exactly two dimensions.")
  (:method ((array array))
    (assert (= 2 (array-rank array)) () "Array is not a matrix.")
    (array-dimension array 1)))

;;; SUB -- extracting subsets of objects with rectilinear indexing

(defgeneric sub (object &rest index-specifications)
  (:documentation "Return a subset of object for the given index
  specifications, one for each dimension.

  Index specifications have the following syntax (also see general notes below):

  fixnum - Addressing a single element, also, the dimension is dropped, ie rank
    decreases by 1.

  bit-vector - Addressing elements where the bit-vector is equal to 1.

  vector of fixnums - Elements at those coordinates.

  (si start end &optional by) - Sequence indexing, from START by BY, not
    including END.

  (rev index-specification) - Reverse index specification.

  (cat index-specification ...) - Concatenation of index specification.  FIXNUMs
    are treated as vectors of a single element.

  All fixnums are allowed to be negative, in which case they are counted from
  the end.  If END is 0, it includes the last element.  Because of these
  syntactic conveniences, resolution of index specifications may be delayed
  until the dimensions are known.

  See WITH-INDEXING for implementation details."))

(defgeneric (setf sub) (source target &rest index-specifications)
  (:documentation "Set the subset of TARGET (according to INDEX-SPECIFICATIONS)
  in SOURCE.  See SUB for the documentation on the syntax of index
  specifications."))

(define-condition sub-incompatible-dimensions (error)
  ()
  (:documentation "Rank or dimensions are incompatible."))

(define-condition sub-invalid-array-index (error)
  ((index :accessor index :initarg :index)
   (dimension :accessor dimension :initarg :dimension)))

(define-condition sub-invalid-index-specification (error)
  ((index-specification :accessor index-specification
                        :initarg :index-specification)))

(defstruct (si (:constructor si (start end &optional by strict-direction?)))
  "Sequence indexing: addresses elements from START to END, by BY.  Resolution
may be delayed until dimension is known, so any sign of BY can be used.  Unless
STRICT-DIRECTION?, the sign of BY is auto-adjusted at the time of resolution."
  (start 0 :type fixnum)
  (end 0 :type fixnum)
  (by 1 :type fixnum)
  (strict-direction? nil :type boolean))

(defstruct (resolved-si (:constructor resolved-si (start length by)))
  "Resolved range indexing."
  (start 0 :type fixnum)
  (length 0 :type fixnum)
  (by 1 :type fixnum))

(defstruct (delayed-index-specification
             (:constructor delayed-index-specification (type data)))
  "A index-specification with relayed resolution."
  type data)

(deftype simple-fixnum-vector ()
  '(simple-array fixnum (*)))

(defun cat (&rest index-specifications)
  "Concatenation of index-specifications."
  (if (cdr index-specifications)
      (if (every #'vectorp index-specifications)
          (apply #'concatenate 'simple-fixnum-vector index-specifications)
          (delayed-index-specification 'concatenation index-specifications))
      (car index-specifications)))

(defun rev (index-specification)
  "Reverse of index-specification."
  (typecase index-specification
    (fixnum index-specification)
    (vector (reverse index-specification))
    (otherwise (delayed-index-specification 'reverse index-specification))))

(defmethod sub ((index-specification si) &rest index-specifications)
  (assert (not (cdr index-specifications)) () 'sub-incompatible-dimensions)
  (delayed-index-specification 'sub index-specification))

(defun resolve-t (dimension)
  "Resolve a T index specification."
  (resolved-si 0 dimension 1))

(defun bit-vector-positions (bit-vector &optional dimension)
  "Convert a bit vector to a simple-fixnum-vector of positions.  If DIMENSION is
given, it will be checked."
  (check-type bit-vector bit-vector)
  (when dimension
    (assert (<= (length bit-vector) dimension)))
  (iter
    (for position :from 0)
    (for bit :in-vector bit-vector)
    (when (= bit 1)
      (collect position :result-type simple-fixnum-vector))))

(defun bitmap (predicate sequence)
  "Map sequence into a simple-bit-vector, using 1 when PREDICATE yields true, 0
otherwise."
  (map 'simple-bit-vector (lambda (element) (if (funcall predicate element) 1 0))
       sequence))

(defun resolve-index-specification (index-specification dimension
                                    &optional force-vector?)
  "Resolve delayed operations in INDEX-SPECIFICATION given the dimension.
Return either a FIXNUM, a RESOLVED-SI object, or a SIMPLE-FIXNUM-VECTOR.  When
FORCE-VECTOR?, a result that would be RESOLVED-SI is converted into a vector."
  (when dimension
    (check-type dimension (integer 0 #.most-positive-fixnum)))
  (bind (((:flet resolve-index (index &optional end?))
          (check-type index fixnum)
           (cond
             ((zerop index)
              (if end? 
                  (progn
                    (assert dimension () 
                            "Can't resolve 0 at the end without a dimension.")
                    dimension)
                  0))
             ((minusp index)
              (assert dimension () 
                      "Can't resolve a negative index without a dimension.")
              (aprog1 (+ dimension index)
                (assert (<= 0 it) () 'sub-invalid-array-index
                        :index index :dimension dimension)))
             (t index))))
    (etypecase index-specification
      ((eql t) (resolve-t dimension))
      (fixnum (resolve-index index-specification))
      (bit-vector (bit-vector-positions index-specification dimension))
      (vector (map 'simple-fixnum-vector #'resolve-index index-specification))
      (si (bind (((:slots-r/o start end by strict-direction?) index-specification)
                 (start (resolve-index start))
                 (end (resolve-index end t))
                 (span (- end start)))
            (if strict-direction?
                (assert (plusp (* span by)) ()
                        "Invalid indexing ~A->~A by ~A." start end by)
                (setf by (* (signum span) (abs by))))
            (let ((length (ceiling span by)))
              (if force-vector?
                  (let ((vector (make-array length :element-type 'fixnum)))
                    (loop
                      for index :from start :by by :below end
                      for vector-index :from 0
                      do (setf (aref vector vector-index) index))
                    vector)
                  (resolved-si start length by)))))
      (delayed-index-specification
         (bind (((:slots-r/o type data) index-specification))
           (ecase type
             (concatenation
                (apply #'concatenate 'simple-fixnum-vector
                       (mapcar (lambda (index-specification)
                                 (aetypecase (resolve-index-specification
                                              index-specification dimension t)
                                   (fixnum (vector it))
                                   (simple-fixnum-vector it)))
                               data)))
             (reverse
                (let ((index-specification
                       (resolve-index-specification data dimension)))
                  (etypecase index-specification
                    (fixnum index-specification)
                    (simple-fixnum-vector (reverse index-specification))
                    (resolved-si
                       (bind (((:slots-r/o start length by) index-specification))
                         (resolved-si (+ start (* (1- length) by))
                                      length (- by)))))))
             (sub (sub (resolve-index-specification (first data) dimension t)
                       (second data)))))))))

(defun resolve-index-specifications (index-specifications dimensions)
  "Resolve multiple index-specifications."
  (map 'vector #'resolve-index-specification index-specifications dimensions))

(defun row-major-coefficients (dimensions)
  "Calculate coefficients for row-major mapping."
  (let* ((cumprod 1)
         (rank (length dimensions))
         (coefficients (make-array rank :element-type 'fixnum)))
    (iter
      (for axis-number :from (1- rank) :downto 0)
      (setf (aref coefficients axis-number) cumprod
            cumprod (* cumprod (aref dimensions axis-number))))
    coefficients))

(defun column-major-coefficients (dimensions)
  "Calculate coefficients for a column-major mapping."
  (let* ((cumprod 1)
         (rank (length dimensions))
         (coefficients (make-array rank :element-type 'fixnum)))
    (iter
      (for axis-number :from 0 :below rank)
      (setf (aref coefficients axis-number) cumprod
            cumprod (* cumprod (aref dimensions axis-number))))
    coefficients))

(defun drop-dimensions (index-specifications coefficients)
  "Drop single dimensions.  Return (values OFFSET NEW-INDEX-SPECIFICATIONS
NEW-COEFFICIENTS)."
  (iter
    (with offset := 0)
    (for index-specification :in-vector index-specifications)
    (for coefficient :in-vector coefficients)
    (if (numberp index-specification)
        (incf offset (* index-specification coefficient))
        (progn
          (collect index-specification :into new-index-specifications
                   :result-type vector)
          (collect coefficient :into new-coefficients
                   :result-type simple-fixnum-vector)))
    (finally
     (return (values offset
                     new-index-specifications
                     new-coefficients)))))

(defun index-specification-dimension (index-specification)
  "Dimension of a index-specification."
  (etypecase index-specification
    (fixnum 1)
    (vector (length index-specification))
    (resolved-si (resolved-si-length index-specification))))

(defun index-specification-dimensions (index-specifications)
  "Dimensions of index-specifications."
  (map 'simple-fixnum-vector #'index-specification-dimension
       index-specifications))

(defun map-counter (index-specification counter)
  "Map an index (starting from zero) to an index within a index-specification.
No validity checks, this function is meant for internal use and always expects a
valid index."
  (etypecase index-specification
    (fixnum index-specification)
    (resolved-si (+ (resolved-si-start index-specification)
                    (* counter (resolved-si-by index-specification))))
    (vector (aref index-specification counter))))

(defun increment-index-counters (counters index-specification-dimensions)
  "Increment index counters, beginning from the end.  Return the index
of the last one that was changed.  The second value is T when the
first index has reached its limit, ie the array has been walked and
all the counters are zero again."
  (iter
    (for axis-number :from (1- (length index-specification-dimensions))
         :downto 0)
    (if (= (incf (aref counters axis-number))
           (aref index-specification-dimensions axis-number))
        (setf (aref counters axis-number) 0)
        (return-from increment-index-counters axis-number)))
  (values 0 t))


(defun map-counters (offset index-specifications coefficients counters cumsums
                     valid-end)
  "Recalculate cumsums, return flat index."
  (let ((cumsum (if (zerop valid-end)
                    offset
                    (aref cumsums (1- valid-end)))))
    (iter
      (for counter :in-vector counters :from valid-end
           :with-index axis-number)
      (for index-specification :in-vector index-specifications :from valid-end)
      (for coefficient :in-vector coefficients :from valid-end)
      (incf cumsum (* coefficient (map-counter index-specification counter)))
      (setf (aref cumsums axis-number) cumsum))
    cumsum))

(defun map-counters* (coefficients counters cumsums valid-end)
  "Recalculate cumsums, return flat index.  No offset, no index specification,
counters map to themselves."
  (let ((cumsum (if (zerop valid-end) 0 (aref cumsums (1- valid-end)))))
    (iter
      (for counter :in-vector counters :from valid-end
           :with-index axis-number)
      (for coefficient :in-vector coefficients :from valid-end)
      (incf cumsum (* coefficient counter))
      (setf (aref cumsums axis-number) cumsum))
    cumsum))

(defmacro with-indexing ((index-specifications dimensions next-index &key
                         (end? (gensym "END")) 
                         (effective-dimensions (gensym "EFFECTIVE-DIMENSIONS"))
                         (counters (gensym "COUNTERS")))
                         &body body)
  "Establish incrementation and index-calculation functions within BODY.  The
sequence INDEX-SPECIFICATIONS constains the index specifications, and DIMENSIONS
contains the dimensions of the object indexed.  NEXT-INDEX is function that
returns (and steps to) the next index.  END? is a boolean that can be used to
check termination.  EFFECTIVE-DIMENSIONS is a vector of fixnums that contains
the effective dimensions traversed (may be shorted than DIMENSIONS, or have
length zero, if dimensions are dropped).  It may be used to check for
termination by calculating its product (the number of elements traversed), but
END? is recommended.  COUNTERS gives access to counters.

The consequences are undefined if COUNTERS or END? are modified.  See source for
comments on implementation details."
;;; WITH-INDEXING is the user interface of an iteration construct that walks the
;;; (indexes of the) elements on an array.  Indexing can be row- or
;;; column-major, or even represent axis permutations, etc, but order of
;;; traversal is contiguous only for row-major arrays.
;;;
;;; Here is how it works:
;;;
;;; 0. RESOLVE-INDEX-SPECIFICATION(S) resolves index specifications to one of
;;;    the following: a FIXNUM, a SIMPLE-FIXNUM-VECTOR, or RESOLVED-SI.
;;;
;;; 1. An affine mapping is established, which is the sum of indexes multiplied
;;;    by corresponding coefficients.  This is general enough to permit row- and
;;;    colum-major mappings, or even axis permutations.
;;;
;;; 2. Dropped dimensions (denoted by a single integer) are removed, and the
;;;    corresponding partial sum is added as an offset.
;;;
;;; 3. An index counter (a vector of fixnums) is initialized with zeros, and
;;;    incremented with each step.  The set of indices changed is kept track of.
;;;    The sum of coefficients is calculated, using partial sums from previous
;;;    iterations to the extent it is possible.
  (check-type next-index symbol)
  (check-type end? symbol)
  (once-only (dimensions index-specifications)
    (with-unique-names (coefficients offset rank cumsums valid-end)
      `(bind ((,dimensions (coerce ,dimensions 'simple-fixnum-vector))
              (,rank (length ,index-specifications)))
         (assert (= ,rank (length ,dimensions)) () 'sub-incompatible-dimensions)
         (bind ((,index-specifications (resolve-index-specifications
                                        ,index-specifications ,dimensions))
                (,coefficients (row-major-coefficients ,dimensions))
                ((:values ,offset ,index-specifications ,coefficients)
                 (drop-dimensions ,index-specifications ,coefficients))
                (,effective-dimensions (index-specification-dimensions
                                        ,index-specifications))
                (,counters (make-array ,rank :element-type 'fixnum
                                       :initial-element 0))
                (,cumsums (make-array ,rank :element-type 'fixnum))
                (,valid-end 0)
                (,end? (every #'zerop ,effective-dimensions))
                ((:flet ,next-index ())
                 (aprog1 (map-counters ,offset ,index-specifications
                                       ,coefficients ,counters ,cumsums 
                                       ,valid-end)
                   (setf (values ,valid-end ,end?)
                         (increment-index-counters 
                          ,counters
                          ,effective-dimensions)))))
           ;; !!! dynamic extent & type declarations
           ;; !!! check optimizations
           ,@body)))))

(defmacro with-indexing* ((dimensions next-index &key (end? (gensym "END"))
                                      column-major? reverse?)
                          &body body)
  "A simpler version of WITH-INDEXING, with all index-specifications as T.  
COLUMN-MAJOR? uses column-major indexing, while REVERSE? reverses dimensions."
  (once-only (dimensions)
    (with-unique-names (coefficients rank counters cumsums valid-end)
      `(bind ((,dimensions (coerce ,dimensions 'simple-fixnum-vector))
              (,rank (length ,dimensions)))
         (when ,reverse?
           (setf ,dimensions (nreverse ,dimensions)))
         (bind ((,coefficients (if ,column-major?
                                   (column-major-coefficients ,dimensions)
                                   (row-major-coefficients ,dimensions)))
                (,counters (make-array ,rank :element-type 'fixnum
                                       :initial-element 0))
                (,cumsums (make-array ,rank :element-type 'fixnum))
                (,valid-end 0)
                (,end? (every #'zerop ,dimensions))
                ((:flet ,next-index ())
                 (aprog1 (map-counters* ,coefficients ,counters ,cumsums ,valid-end)
                   (setf (values ,valid-end ,end?)
                         (increment-index-counters ,counters ,dimensions)))))
           ,@body)))))

(defmethod sub ((array array) &rest index-specifications)
  (with-indexing (index-specifications (array-dimensions array) next-index
                               :end? end?
                               :effective-dimensions dimensions)
    (if (zerop (length dimensions))
        (row-major-aref array (next-index))
        (let ((result (make-array (coerce dimensions 'list)
                                  :element-type
                                  (array-element-type array))))
          (iter
            (for result-index :from 0)
            (setf (row-major-aref result result-index)
                  (row-major-aref array (next-index)))
            (until end?))
          result))))

(defmethod sub ((list list) &rest index-specifications)
  (with-indexing (index-specifications (vector (length list)) next-index
                                       :end? end?
                                       :effective-dimensions dimensions)
    (if (zerop (length dimensions))
        (nth (next-index) list)
        ;; not very efficient, but lists are not ideal for random access
        (iter
          (collecting (nth (next-index) list))
          (until end?)))))

;;; (setf sub) with array target

(defmethod (setf sub) (source (target array) &rest index-specifications)
  (with-indexing (index-specifications (array-dimensions target) next-index
                               :end? end? 
                               :effective-dimensions dimensions)
    (iter
      (setf (row-major-aref target (next-index)) source)
      (until end?)))
  source)

(defmethod (setf sub) ((source array) (target array) &rest index-specifications)
  (with-indexing (index-specifications (array-dimensions target) next-index
                                       :end? end? 
                                       :effective-dimensions dimensions)
    (assert (equalp dimensions (coerce (array-dimensions source) 'vector))
            () 'sub-incompatible-dimensions)
    (iter
      (for source-index :from 0)
      (setf (row-major-aref target (next-index))
            (row-major-aref source source-index))
      (until end?)))
  source)

(defmethod (setf sub) ((source list) (target array) &rest index-specifications)
  (with-indexing (index-specifications (array-dimensions target) next-index
                                       :end? end? 
                                       :effective-dimensions dimensions)
    (assert (equalp dimensions (vector (length source)))
            () 'sub-incompatible-dimensions)
    (iter
      (for element :in source)
      (setf (row-major-aref target (next-index)) element)
      (until end?)))
  source)

;;; (setf sub) with list target

(defmethod (setf sub) (source (list list) &rest index-specifications)
  (with-indexing (index-specifications (vector (length list)) next-index
                                       :end? end?)
    (iter
      (setf (nth (next-index) list) source)
      (until end?))))

(defmethod (setf sub) ((source list) (list list) &rest index-specifications)
  (with-indexing (index-specifications (vector (length list)) next-index
                                       :end? end?
                                       :effective-dimensions dimensions)
    (assert (equalp dimensions (vector (length source))) ()
            'sub-incompatible-dimensions)
    (iter
      (for element :in source)
      (setf (nth (next-index) list) element)
      (until end?))))

(defmethod (setf sub) ((source vector) (list list) &rest index-specifications)
  (with-indexing (index-specifications (vector (length list)) next-index
                                       :end? end?
                                       :effective-dimensions dimensions)
    (assert (equalp dimensions (vector (length source))) ()
            'sub-incompatible-dimensions)
    (iter
      (for element :in-vector source)
      (setf (nth (next-index) list) element)
      (until end?))))

;;; convenience functions 

(defgeneric map-columns (function matrix)
  (:documentation "Map columns of MATRIX using function.  FUNCTION is
  called with columns that are extracted as a vector, and the returned
  values are assembled into another matrix.  Element types and number
  of rows are established after the first function call, and are
  checked for conformity after that.  If function doesn't return a
  vector, the values are collected in a vector instead of a matrix."))

(defmethod map-columns (function (matrix array))
  (bind ((matrix (if (vectorp matrix)
                     (reshape matrix '(1 t) :row-major :copy? nil)
                     matrix))
         ((nil ncol) (array-dimensions matrix))
         result
         result-nrow)
    (iter
      (for col :from 0 :below ncol)
      (let ((mapped-col (funcall function (sub matrix t col))))
        (when (first-iteration-p)
          (if (vectorp mapped-col)
              (setf result-nrow (length mapped-col)
                    result (make-array (list result-nrow ncol)
                                       :element-type
                                       (array-element-type mapped-col)))
              (setf result (make-array ncol))))
        (if result-nrow
            (setf (sub result t col) mapped-col)
            (setf (aref result col) mapped-col))))
    result))

(defgeneric map-rows (function matrix)
  (:documentation "Similar to MAP-ROWS, mutatis mutandis."))

(defmethod map-rows (function (matrix array))
  (bind ((matrix (if (vectorp matrix)
                     (reshape matrix '(t 1) :row-major :copy? nil)
                     matrix))
         ((nrow nil) (array-dimensions matrix))
         result
         result-ncol)
    (iter
      (for row :from 0 :below nrow)
      (let ((mapped-row (funcall function (sub matrix row t))))
        (when (first-iteration-p)
          (if (vectorp mapped-row)
              (setf result-ncol (length mapped-row)
                    result (make-array (list nrow result-ncol)
                                       :element-type
                                       (array-element-type mapped-row)))
              (setf result (make-array nrow))))
        (if result-ncol
            (setf (sub result row t) mapped-row)
            (setf (aref result row) mapped-row))))
    result))

(defgeneric transpose (object)
  (:documentation "Transpose a matrix.")) 

(defmethod transpose ((matrix array))
  ;; transpose a matrix
  (bind (((nrow ncol) (array-dimensions matrix))
         (result (make-array (list ncol nrow)
                             :element-type (array-element-type matrix)))
         (result-index 0))
    (dotimes (col ncol)
      (dotimes (row nrow)
        (setf (row-major-aref result result-index) (aref matrix row col))
        (incf result-index)))
    result))

(defgeneric create (type element-type &rest dimensions)
  (:documentation "Create an object of TYPE with given DIMENSIONS and
  ELEMENT-TYPE (or a supertype thereof)."))

(defmethod create ((type (eql 'array)) element-type &rest dimensions)
  (make-array dimensions :element-type element-type))

(defmethod collect-rows (nrow function &optional (type 'array))
  (bind (result
         ncol)
    (iter
      (for row :from 0 :below nrow)
      (let ((result-row (funcall function)))
        (when (first-iteration-p)
          (setf ncol (length result-row)
                result (create type (array-element-type result-row) nrow ncol)))
        (setf (sub result row t) result-row)))
    result))

(defun collect-vector (n function &optional (element-type t))
  (bind (result)
    (iter
      (for index :from 0 :below n)
      (let ((element (funcall function)))
        (when (first-iteration-p)
          (setf result (make-array n :element-type element-type)))
        (setf (aref result index) element)))
    result))

(defun reshape-calculate-dimensions (dimensions size &optional list?)
  "If a single T is found among dimensions (a sequence), replace it with a
positive integer so that the product equals SIZE.  Otherwise check that the
product equals size.  Return a SIMPLE-FIXNUM-VECTOR, unless LIST?, in which case
it will return a list.  If dimensions is a single element, it is interpreted as
a sequence of length 1."
  (let* (missing-position
         (product 1)
         (position 0)
         (dimensions
          (map 'simple-fixnum-vector
               (lambda (dimension)
                 (aprog1
                     (cond
                       ((and (typep dimension 'fixnum) (<= 0 dimension))
                        (multf product dimension)
                        dimension)
                       ((eq dimension t)
                        (if missing-position
                            (error "Can't have more than one missing dimension.")
                            (progn (setf missing-position position) 0)))
                       (t (error "Can't interpret ~A as a dimension." dimension)))
                   (incf position)))
               (if (typep dimensions 'sequence) dimensions (vector dimensions)))))
    (if missing-position
        (setf (aref dimensions missing-position)
              (cond ((zerop size) 0)
                    ((zerop product) (error "Can't create a positive size ~
                                              with a zero dimension."))
                    (t (bind (((:values fraction remainder)
                               (floor size product)))
                         (assert (zerop remainder) ()
                                 "Substitution does not result in an integer.")
                         fraction))))
        (assert (= size product) () "Product of dimensions doesn't match size."))
    (if list?
        (coerce dimensions 'list)
        dimensions)))

(defgeneric reshape (object dimensions order &key copy? &allow-other-keys)
  (:documentation "Rearrange elements of an array-like object to new dimensions.
Order is :ROW-MAJOR or :COLUMN-MAJOR, the object will be treated as if it was
row- or column-major (but of course it does not have to be).  Unless COPY?, it
may share structure with the original.  Dimensions may can be a sequence, and
contain a single T, which is replaced to match sizes."))

(defmethod reshape ((array array) dimensions (order (eql :row-major)) &key copy?)
  (let* ((size (array-total-size array))
         (dimensions (reshape-calculate-dimensions dimensions size t)))
    (if copy?
        (aprog1 (make-similar-array array dimensions)
          (replace (displace-array it size) (displace-array array size)))
        (displace-array array dimensions))))

(defmethod reshape ((array array) dimensions (order (eql :column-major))
                    &key copy?)
  (declare (ignore copy?))
  (let* ((size (array-total-size array))
         (dimensions (reshape-calculate-dimensions dimensions size))
         (result (make-similar-array array (coerce dimensions 'list))))
    (with-indexing* ((array-dimensions array) array-index
                     :column-major? t :reverse? t)
      (with-indexing* (dimensions result-index :column-major? t :reverse? t)
        (loop 
          repeat size
          do (setf (row-major-aref result (result-index))
                   (row-major-aref array (array-index))))))
    result))

(defgeneric rows (matrix &optional vector?)
  (:documentation "Return the rows of MATRIX as separate vectors.  When VECTOR?,
  the result is a SIMPLE-VECTOR, otherwise a LIST.")
  (:method (matrix &optional vector?)
    (bind (((:accessors-r/o nrow) matrix)
           ((:flet row (row-index)) (sub matrix row-index t)))
      (if vector?
          (aprog1 (make-array nrow)
            (dotimes (row-index nrow)
              (setf (aref it row-index) (row row-index))))
          (loop
            for row-index :below nrow
            collecting (row row-index))))))

(defgeneric columns (matrix &optional vector?)
  (:documentation "Return the columns of MATRIX as separate vectors.  When
  VECTOR?, the result is a SIMPLE-VECTOR, otherwise a LIST.")
  (:method (matrix &optional vector?)
    (bind (((:accessors-r/o ncol) matrix)
           ((:flet col (col-index)) (sub matrix t col-index)))
      (if vector?
          (aprog1 (make-array ncol)
            (dotimes (col-index ncol)
              (setf (aref it col-index) (col col-index))))
          (loop
            for col-index :below ncol
            collecting (col col-index))))))

(defgeneric pref (object &rest indexes)
  (:documentation "Return a vector, with elements from OBJECT, extracted using
  INDEXES in parallel."))

(defmethod pref ((array array) &rest indexes)
  (let ((rank (array-rank array))
        (element-type (array-element-type array)))
    (assert (= rank (length indexes)))
    (when (zerop rank)
      (return-from pref (make-array 0 :element-type element-type)))
    (let* ((length (length (first indexes)))
           (result (make-array length :element-type element-type)))
      (assert (every (lambda (index) (= (length index) length)) (cdr indexes)))
      (loop
        :for element-index :below length
        :do (setf (aref result element-index)
                  (apply #'aref array
                                (mapcar (lambda (index) (aref index element-index))
                                        indexes))))
      result)))

(defun which (predicate sequence)
  "Return a simple-fixnum-vector for the indexes of elements that satisfy
predicate."
  (let (indexes
        (count 0)
        (index 0))
    (map nil (lambda (element)
               (when (funcall predicate element)
                 (push index indexes)
                 (incf count))
               (incf index))
         sequence)
    (let ((result (make-array count :element-type 'fixnum)))
      (loop
        :for i :from (1- count) :downto 0
        :for ix :in indexes
        :do (setf (aref result i) ix))
      result)))
