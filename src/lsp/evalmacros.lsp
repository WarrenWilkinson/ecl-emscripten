;;;;  -*- Mode: Lisp; Syntax: Common-Lisp; Package: SYSTEM -*-
;;;;
;;;;  Copyright (c) 1984, Taiichi Yuasa and Masami Hagiya.
;;;;  Copyright (c) 1990, Giuseppe Attardi.
;;;;
;;;;    This program is free software; you can redistribute it and/or
;;;;    modify it under the terms of the GNU Library General Public
;;;;    License as published by the Free Software Foundation; either
;;;;    version 2 of the License, or (at your option) any later version.
;;;;
;;;;    See file '../Copyright' for full details.

(in-package "SYSTEM")

(defmacro defun (name vl &body body &aux doc-string)
  "Syntax: (defun name lambda-list {decl | doc}* {form}*)
Defines a global function named by NAME.
The complete syntax of a lambda-list is:
	({var}*
	 [&optional {var | (var [init [svar]])}*]
	 [&rest var]
	 [&key {var | ({var | (keyword var)} [init [svar]])}*
	       [&allow-other-keys]]
	 [&aux {var | (var [init])}*])
The doc-string DOC, if supplied, is saved as a FUNCTION doc and can be
retrieved by (documentation 'NAME 'function)."
  (multiple-value-setq (body doc-string) (remove-documentation body))
  (let* ((function `#'(ext::lambda-block ,name ,vl ,@body))
	 (global-function `#'(ext::lambda-block ,name ,vl
			       (declare (si::c-global))
			       ,@body)))
    (when *dump-defun-definitions*
      (print function)
      (setq function `(si::bc-disassemble ,function)))
  `(progn
     (eval-when (:execute)
       (si::fset ',name ,function))
     (eval-when (:load-toplevel)
       (si::fset ',name ,global-function))
    ,@(si::expand-set-documentation name 'function doc-string)
    ',name)))

(defmacro defmacro (name vl &body body &aux doc-string)
  "Syntax: (defmacro name defmacro-lambda-list {decl | doc}* {form}*)
Defines a global macro named by NAME.  The complete syntax of DEFMACRO-LAMBDA-
LIST is:
	( [&whole var] [&environment var] . pvar )
where PVAR may be a symbol,
	( {pvar}* [&optional {var | (pvar [init [pvar]])}*] . var )
or
	( {pvar}*
	  [&optional {var | (pvar [init [pvar]])}*]
	  [{&rest | &body} pvar]
	  [&key {var | ({var | (keyword pvar)} [init [pvar]])}*
	        [&allow-other-keys]]
	  [&aux {var | (pvar [init])}*] )
The doc-string DOC, if supplied, is saved as a FUNCTION doc and can be
retrieved by (documentation 'NAME 'function).  See LIST for the backquote
macro useful for defining macros."
  (multiple-value-bind (function pprint doc-string)
      (sys::expand-defmacro name vl body)
    (setq function `(function ,function))
    (when *dump-defun-definitions*
      (print function)
      (setq function `(si::bc-disassemble ,function)))
    `(eval-when (:compile-toplevel :load-toplevel :execute)
       (si::fset ',name ,function t ,pprint)
       ,@(si::expand-set-documentation name 'function doc-string)
       ',name)))

(defmacro defvar (var &optional (form nil form-sp) doc-string)
  "Syntax: (defvar name [form [doc]])
Declares the variable named by NAME as a special variable.  If the variable
does not have a value, then evaluates FORM and assigns the value to the
variable.  FORM defaults to NIL.  The doc-string DOC, if supplied, is saved
as a VARIABLE doc and can be retrieved by (documentation 'NAME 'variable)."
  `(LOCALLY (DECLARE (SPECIAL ,var))
    (SYS:*MAKE-SPECIAL ',var)
    ,@(when form-sp
	  `((UNLESS (BOUNDP ',var)
	      (SETQ ,var ,form))))
    ,@(si::expand-set-documentation var 'variable doc-string)
    #+PDE (SYS:RECORD-SOURCE-PATHNAME ',var 'defvar)
    (eval-when (:compile-toplevel)
      (si::register-global ',var))
    ',var))

(defmacro defparameter (var form &optional doc-string)
  "Syntax: (defparameter name form [doc])
Declares the global variable named by NAME as a special variable and assigns
the value of FORM to the variable.  The doc-string DOC, if supplied, is saved
as a VARIABLE doc and can be retrieved by (documentation 'NAME 'variable)."
  `(LOCALLY (DECLARE (SPECIAL ,var))
    (SYS:*MAKE-SPECIAL ',var)
    (SETQ ,var ,form)
    ,@(si::expand-set-documentation var 'variable doc-string)
    #+PDE (SYS:RECORD-SOURCE-PATHNAME ',var 'DEFPARAMETER)
    (eval-when (:compile-toplevel)
      (si::register-global ',var))
    ',var))

(defmacro defconstant (var form &optional doc-string)
  `(PROGN (SYS:*MAKE-CONSTANT ',var ,form)
    ,@(si::expand-set-documentation var 'variable doc-string)
    #+PDE (SYS:RECORD-SOURCE-PATHNAME ',var 'defconstant)
    (eval-when (:compile-toplevel)
      (si::register-global ',var))
    ',var))

;;;
;;; This is a no-op unless the compiler is installed
;;;
(defmacro define-compiler-macro (name vl &rest body)
  (multiple-value-bind (function pprint doc-string)
      (sys::expand-defmacro name vl body)
    (setq function `(function ,function))
    (when *dump-defun-definitions*
      (print function)
      (setq function `(si::bc-disassemble ,function)))
    `(progn
       (put-sysprop ',name 'sys::compiler-macro ,function)
       ,@(si::expand-set-documentation name 'function doc-string)
       ',name)))

(defun compiler-macro-function (name &optional env)
  (declare (ignore env))
  (get-sysprop name 'sys::compiler-macro))

;;; Each of the following macros is also defined as a special form,
;;; as required by CLtL. Some of them are used by the compiler (e.g.
;;; dolist), some not at all (e.g. defun).
;;; Thus their names need not be exported.

(let ()
  ;; We enclose the macro in a LET form so that it is no longer
  ;; a toplevel form. This solves the problem of this simple LOOP
  ;; replacing the more complex form in loop2.lsp when evalmacros.lsp
  ;; gets compiled.
(defmacro loop (&rest body &aux (tag (gensym)))
  "Syntax: (loop {form}*)
Establishes a NIL block and executes FORMs repeatedly.  The loop is normally
terminated by a non-local exit."
  `(BLOCK NIL (TAGBODY ,tag (PROGN ,@body) (GO ,tag))))
)

(defmacro lambda (&rest body)
  `(function (lambda ,@body)))

(defmacro lambda-block (name lambda-list &rest lambda-body)
  (multiple-value-bind (decl body doc)
      (si::process-declarations lambda-body)
    (when decl (setq decl (list (cons 'declare decl))))
    `(lambda ,lambda-list ,@doc ,@decl
      (block ,(si::function-block-name name) ,@body))))

; assignment

(defmacro psetq (&rest args)
  "Syntax: (psetq {var form}*)
Similar to SETQ, but evaluates all FORMs first, and then assigns each value to
the corresponding VAR.  Returns NIL."
   (do ((l args (cddr l))
        (forms nil)
        (bindings nil))
       ((endp l) (list* 'LET* (nreverse bindings) (nreverse (cons nil forms))))
       (let ((sym (gensym)))
            (push (list sym (cadr l)) bindings)
            (push (list 'setq (car l) sym) forms)))
   )

; conditionals

(defmacro cond (&rest clauses &aux (form nil))
  "Syntax: (cond {(test {form}*)}*)
Evaluates TESTs in order until one evaluates to non-NIL.  Then evaluates FORMs
in order that follow the TEST and returns all values of the last FORM.  If no
forms follow the TEST, then returns the value of the TEST.  Returns NIL, if no
TESTs evaluates to non-NIL."
  (dolist (l (reverse clauses) form)	; don't use nreverse here
    (if (endp (cdr l))
	(if (eq (car l) 't)
	    (setq form 't)
	    (let ((sym (gensym)))
	      (setq form `(LET ((,sym ,(car l)))
;			   (DECLARE (:READ-ONLY ,sym)) ; Beppe
			   (IF ,sym ,sym ,form)))))
	(if (eq (car l) 't)
	    (setq form (if (endp (cddr l))
			   (cadr l)
			   `(PROGN ,@(cdr l))))
	    (setq form (if (endp (cddr l))
			   `(IF ,(car l) ,(cadr l) ,form)
			   `(IF ,(car l) (PROGN ,@(cdr l)) ,form))))))
  )

(defmacro unless (pred &rest body)
  "Syntax: (unless test {form}*)
If TEST evaluates to NIL, then evaluates FORMs and returns all values of the
last FORM.  If not, simply returns NIL."
  `(IF (NOT ,pred) (PROGN ,@body)))

; program feature

(defmacro prog (vl &rest body &aux (decl nil))
  "Syntax: (prog ({var | (var [init])}*) {decl}* {tag | statement}*)
Establishes a NIL block, binds each VAR to the value of INIT (which defaults
to NIL) in parallel, and executes STATEMENTs.  Returns NIL."
  (multiple-value-setq (decl body)
    (find-declarations body))
  `(BLOCK NIL (LET ,vl ,@decl (TAGBODY ,@body)))
  )

(defmacro prog* (vl &rest body &aux (decl nil))
  "Syntax: (prog* ({var | (var [init])}*) {decl}* {tag | statement}*)
Establishes a NIL block, binds each VAR to the value of INIT (which defaults
to NIL) sequentially, and executes STATEMENTs.  Returns NIL."
  (multiple-value-setq (decl body)
    (find-declarations body))
  `(BLOCK NIL (LET* ,vl ,@decl (TAGBODY ,@body)))
  )

; sequencing

(defmacro prog1 (first &rest body &aux (sym (gensym)))
  "Syntax: (prog1 first-form {form}*)
Evaluates FIRST-FORM and FORMs in order.  Returns the value of FIRST-FORM."
  (if (null body) first
  `(LET ((,sym ,first))
;    (DECLARE (:READ-ONLY ,sym)) ; Beppe
    ,@body ,sym)))

(defmacro prog2 (first second &rest body &aux (sym (gensym)))
  "Syntax: (prog2 first-form second-form {forms}*)
Evaluates FIRST-FORM, SECOND-FORM, and FORMs in order.  Returns the value of
SECOND-FORM."
  `(PROGN ,first (LET ((,sym ,second))
;		       (DECLARE (:READ-ONLY ,sym)) ; Beppe
		       ,@body ,sym)))

; multiple values

(defmacro multiple-value-list (form)
  `(MULTIPLE-VALUE-CALL 'LIST ,form))

(defmacro multiple-value-setq (vars form)
  (do ((vl vars (cdr vl))
       (sym (gensym))
       (forms nil)
       (n 0 (1+ n)))
      ((endp vl) `(LET ((,sym (MULTIPLE-VALUE-LIST ,form))) ,@forms))
      (declare (fixnum n))
      (push `(SETQ ,(car vl) (NTH ,n ,sym)) forms))
  )

;; We do not use this macroexpanso, and thus we do not care whether
;; it is efficiently compiled by ECL or not.
(defmacro multiple-value-bind (vars form &rest body)
  `(multiple-value-call #'(lambda (&optional ,@(mapcar #'list vars)) ,@body) ,form))

(defun while-until (test body jmp-op)
  (declare (si::c-local))
  (let ((label (gensym))
	(exit (gensym)))
    `(TAGBODY
        (GO ,exit)
      ,label
        ,@body
      ,exit
	(,jmp-op ,test (GO ,label)))))

(defmacro sys::while (test &body body)
  (while-until test body 'when))

(defmacro sys::until (test &body body)
  (while-until test body 'unless))

(defmacro case (keyform &rest clauses &aux (form nil) (key (gensym)))
  (dolist (clause (reverse clauses)
	   `(LET ((,key ,keyform))
;	     (DECLARE (:READ-ONLY ,key)) ; Beppe
	     ,form))
    (if (or (eq (car clause) 'T) (eq (car clause) 'OTHERWISE))
	(setq form `(PROGN ,@(cdr clause)))
	(if (consp (car clause))
	    (setq form `(IF (MEMBER ,key ',(car clause))
			 (PROGN ,@(cdr clause))
			 ,form))
	    (if (car clause)
		(setq form `(IF (EQL ,key ',(car clause))
			     (PROGN ,@(cdr clause))
			     ,form))))))
  )

(defmacro return (&optional (val nil)) `(RETURN-FROM NIL ,val))

;; Declarations
(defmacro declaim (&rest decl-specs)
  (if (cdr decl-specs)
    `(eval-when (:compile-toplevel :load-toplevel :execute)
       (mapcar #'proclaim ',decl-specs))
    `(eval-when (:compile-toplevel :load-toplevel :execute)
       (proclaim ',(car decl-specs)))))

(defmacro c-declaim (&rest decl-specs)
  (if (cdr decl-specs)
    `(eval-when (:compile-toplevel)
       (mapcar #'proclaim ',decl-specs))
    `(eval-when (:compile-toplevel)
       (proclaim ',(car decl-specs)))))

(defmacro in-package (name)
  `(eval-when (:compile-toplevel :load-toplevel :execute)
     (si::select-package ,(string name))))

;; FIXME!
(defmacro the (type value)
  (declare (ignore type))
  value)

(defmacro define-symbol-macro (symbol expansion)
  (cond ((not (symbolp symbol))
	 (error "DEFINE-SYMBOL-MACRO: ~A is not a symbol"
		symbol))
	((specialp symbol)
	 (error "DEFINE-SYMBOL-MACRO: cannot redefine a special variable, ~A"
		symbol))
	(t
	 `(progn
	   (put-sysprop ',symbol 'si::symbol-macro (lambda (form env) ',expansion))
	   ',symbol))))

(defmacro nth-value (n expr)
  `(nth ,n (multiple-value-list ,expr)))

(defun maybe-unquote (form)
  (if (and (consp form) (eq (car form) 'quote))
      (second form)
      form))
