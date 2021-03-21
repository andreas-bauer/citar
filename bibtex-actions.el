;;; bibtex-actions.el --- Description -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2021 Bruce D'Arcus
;;
;; Author: Bruce D'Arcus <https://github.com/bdarcus>
;; Maintainer: Bruce D'Arcus <https://github.com/bdarcus>
;; Created: February 27, 2021
;; License: GPL-3.0-or-later
;; Version: 0.1
;; Keywords: bib, files
;; Homepage: https://github.com/bdarcus/bibtex-actions
;; Package-Requires: ((emacs "26.3") (bibtex-completion "1.0"))
;;
;; This file is not part of GNU Emacs.
;;
;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.
;;
;;; Commentary:
;;
;;  This package turns bibtex-completion functions into completing-read-based
;;  Emacs commands.  When used with selectrum/icomplete-vertical, embark, and
;;  marginalia, it provides similar functionality to helm-bibtex and ivy-bibtex:
;;  quick filtering and selecting of bibliographic entries from the minibuffer,
;;  and the option to run different commands against them.
;;
;;; Code:

(require 'bibtex-completion)

;;; Variables

;; REVIEW: is this the correct way to ensure we use the custom separator in
;;         'bibtex-actions--completing-read'?
(defvar crm-separator)

(defcustom bibtex-actions-rich-ui t
  "Adds prefix symbols or icons and secondary metadata for suffix UI.
Affixation was first introduced in Emacs 28, and will be ignored
in previous versions."
  :group 'bibtex-actions
  :type 'boolean)

(defcustom bibtex-actions-suffix-display-formats
  '((t . "${=type=:7} ${tags:24}"))
  "Alist for displaying entries in the suffix of the results list.
This is intended to mirror 'bibtex-completion-display-formats'."
  :group 'bibtex-actions
  :type '(alist :key-type symbol :value-type string))

(defcustom bibtex-actions-link-symbol "🔗"
  "Symbol to indicate a DOI or URL link is available for a publication.
This should be a single character."
  :group 'bibtex-actions
  :type 'string)

(defcustom bibtex-actions-icon
  `((pdf .      (,bibtex-completion-pdf-symbol . " "))
    (note .     (,bibtex-completion-notes-symbol . " "))
    (link .     (,bibtex-actions-link-symbol . " ")))
  "Configuration alist specifying which symbol or icon to pick for a bib entry.
This leaves room for configurations where the absense of an item
may be indicated with the same icon but a different face."
  :group 'bibtex-actions
  :type '(alist :key-type string
                :value-type (choice (string :tag "Icon"))))

(defcustom bibtex-actions-icon-separator " "
  "When using rich UI, the padding between prefix icons."
  :group 'bibtex-actions
  :type 'string)

(when bibtex-actions-rich-ui
  (setq bibtex-completion-display-formats
        '((t . "${author:24}   ${title:64}   ${year:4}"))))

;;; Keymap

(defvar bibtex-actions-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "o") 'bibtex-actions-open)
    (define-key map (kbd "p") 'bibtex-actions-open-pdf)
    (define-key map (kbd "l") 'bibtex-actions-open-link)
    (define-key map (kbd "c") 'bibtex-actions-insert-citation)
    (define-key map (kbd "r") 'bibtex-actions-insert-reference)
    (define-key map (kbd "k") 'bibtex-actions-insert-key)
    (define-key map (kbd "b") 'bibtex-actions-insert-bibtex)
    (define-key map (kbd "t") 'bibtex-actions-add-pdf-attachment)
    (define-key map (kbd "n") 'bibtex-actions-open-notes)
    (define-key map (kbd "e") 'bibtex-actions-open-entry)
    (define-key map (kbd "a") 'bibtex-actions-add-pdf-to-library)
    map)
  "Keymap for 'bibtex-actions'.")

;;; Faces



;;; Completion functions

(defun bibtex-actions-read ()
  "Read bibtex-completion entries for completion using 'completing-read-multiple'."
  (bibtex-completion-init)
  (when-let ((crm-separator "\\s-*&\\s-*")
             (candidates (bibtex-actions--get-candidates))
             (chosen
              (completing-read-multiple
               "BibTeX entries: "
               (lambda (string predicate action)
                 (if (eq action 'metadata)
                     `(metadata
                       ,(when bibtex-actions-rich-ui
                          '(affixation-function . bibtex-actions--affixation))
                       (category . bibtex))
                   (complete-with-action action candidates string predicate))))))
    (cl-loop for choice in chosen
             ;; collect citation keys of selected candidate(s)
             collect (cdr (assoc "=key=" (cdr (assoc choice candidates)))))))

(defun bibtex-actions--get-candidates ()
  "Propertize the candidates from 'bibtex-completion-candidates'."
  (cl-loop
   for candidate in (bibtex-completion-candidates)
   collect
   (let* ((pdf (if (assoc "=has-pdf=" (cdr candidate)) " has:pdf"))
          (note (if (assoc "=has-note=" (cdr candidate)) "has:note"))
          (link (if (assoc "doi" (cdr candidate)) "has:link"))
          (add (s-join " " (list pdf note link))))
   (cons
    ;; Here use one string for display, and the other for search.
    ;; The candidate string we use is very long, which is a bit awkward
    ;; when using TAB-completion style multi selection interfaces.
    (propertize
     (s-append add (car candidate)) 'display (bibtex-completion-format-entry
     candidate (1- (frame-width))))
    (cdr candidate)))))

(defun bibtex-actions--affixation (cands)
  "Add affixes to CANDS."
  (cl-loop
   for candidate in cands
   collect
   (let ((pdf (if (string-match "has:pdf" candidate)
                  (car (cdr (assoc 'pdf bibtex-actions-icon)))
                (cdr (cdr (assoc 'pdf bibtex-actions-icon)))))
         (link (if (string-match "has:link" candidate)
                  (car (cdr (assoc 'link bibtex-actions-icon)))
                (cdr (cdr (assoc 'link bibtex-actions-icon)))))
         (note
          (if (string-match "has:note" candidate)
                  (car (cdr (assoc 'note bibtex-actions-icon)))
                (cdr (cdr (assoc 'note bibtex-actions-icon))))))
   (list candidate (concat
                    (s-join bibtex-actions-icon-separator
                            (list pdf note link))"	") ""))))

(defun bibtex-actions--make-suffix (entry)
  "Create the formatted ENTRY suffix string for the 'rich-ui'."
    ;;TODO make use of 'bibtex-completion' so as simple and flexible as possible.
    )

;;; Command wrappers for bibtex-completion functions

(defun bibtex-actions-open (keys)
 "Open PDF, or URL or DOI link.
Opens the PDF(s) associated with the KEYS.  If multiple PDFs are
found, ask for the one to open using ‘completing-read’.  If no
PDF is found, try to open a URL or DOI in the browser instead."
  (interactive (list (bibtex-actions-read)))
  (bibtex-completion-open-any keys))

(defun bibtex-actions-open-pdf (keys)
 "Open PDF associated with the KEYS.
If multiple PDFs are found, ask for the one to open using
‘completing-read’."
  (interactive (list (bibtex-actions-read)))
  (bibtex-completion-open-pdf keys))

(defun bibtex-actions-open-link (keys)
 "Open URL or DOI link associated with the KEYS in a browser."
 (interactive (list (bibtex-actions-read)))
 (bibtex-completion-open-url-or-doi keys))

(defun bibtex-actions-insert-citation (keys)
 "Insert citation for the KEYS."
 (interactive (list (bibtex-actions-read)))
 (bibtex-completion-insert-citation keys))

(defun bibtex-actions-insert-reference (keys)
 "Insert formatted reference(s) associated with the KEYS."
  (interactive (list (bibtex-actions-read)))
  (bibtex-completion-insert-reference keys))

(defun bibtex-actions-insert-key (keys)
 "Insert BibTeX KEYS."
 (interactive (list (bibtex-actions-read)))
 (bibtex-completion-insert-key keys))

(defun bibtex-actions-insert-bibtex (keys)
 "Insert BibTeX entry associated with the KEYS."
 (interactive (list (bibtex-actions-read)))
 (bibtex-completion-insert-bibtex keys))

(defun bibtex-actions-add-pdf-attachment (keys)
 "Attach PDF(s) associated with the KEYS to email."
 (interactive (list (bibtex-actions-read)))
 (bibtex-completion-add-PDF-attachment keys))

(defun bibtex-actions-open-notes (keys)
 "Open notes associated with the KEYS."
 (interactive (list (bibtex-actions-read)))
 (bibtex-completion-edit-notes keys))

(defun bibtex-actions-open-entry (keys)
 "Open BibTeX entry associated with the KEYS."
 (interactive (list (bibtex-actions-read)))
 (bibtex-completion-show-entry keys))

(defun bibtex-actions-add-pdf-to-library (keys)
 "Add PDF associated with the KEYS to library.
The PDF can be added either from an open buffer, a file, or a
URL."
  (interactive (list (bibtex-actions-read)))
  (bibtex-completion-add-pdf-to-library keys))

(provide 'bibtex-actions)
;;; bibtex-actions.el ends here