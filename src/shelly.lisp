#|
  This file is a part of shelly project.
  Copyright (c) 2012 Eitarow Fukamachi (e.arrows@gmail.com)
|#

(in-package :cl-user)
(defpackage shelly
  (:use :cl)
  (:import-from :shelly.core
                :run-repl)
  (:import-from :shelly.install
                :install
                :dump-core
                :rm-core)
  (:import-from :shelly.versions
                :release-versions)
  (:export :run-repl
           :install
           :dump-core
           :rm-core))
(in-package :shelly)

(cl-annot:enable-annot-syntax)

(defun help ()
  "Show a list of Built-In Commands."
  (format t "~&Built-In Commands:~%")
  (do-external-symbols (symbol :shelly)
    (format t "~&    ~(~A~)~%        ~A~2%"
            symbol
            (documentation symbol 'function)))
  (values))

@export
(defun available-versions ()
  "Show all the possible Shelly versions."
  (format t "~{~&~A~%~}" (release-versions))
  (values))
