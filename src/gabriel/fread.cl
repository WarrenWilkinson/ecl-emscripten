;; $Header$
;; $Locker$

;;; FREAD -- Benchmark to read from a file.
;;; Pronounced "FRED".  Requires the existance of FPRINT.TST which is created
;;; by FPRINT.

(in-package "TESTING")

(defun fread ()
  (let ((stream (open "/tmp/fprint.tst" :direction :input)))
    (read stream)
    (close stream)))
	    
(defun testfread ()
  (fread))
