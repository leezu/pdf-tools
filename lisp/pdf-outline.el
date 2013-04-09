;;; pdf-outline.el --- Outline for PDF buffer -*- lexical-binding: t -*-

;; Copyright (C) 2013  Andreas Politz

;; Author: Andreas Politz <politza@fh-trier.de>
;; Keywords: files, pdf

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:
;; 

(require 'outline)
(require 'pdf-links)
(require 'cl-lib)
(require 'imenu)

;;; Code:

;;
;; User options
;; 

(defgroup pdf-outline nil
  "Display a navigatable outline of a PDF document."
  :group 'pdf-tools)

(defcustom pdf-outline-buffer-indent 2
  "The level of indent in the Outline buffer."
  :type 'integer
  :group 'pdf-outline)

(defcustom pdf-outline-enable-imenu t
  "Whether `imenu' should be enabled in PDF documents."
  :group 'pdf-outline
  :type '(choice (const :tag "Yes" t)
                 (const :tag "No" nil)))

(defcustom pdf-outline-imenu-keep-order t
  "Whether `imenu' should be advised not to reorder the outline."
  :group 'pdf-outline
  :type '(choice (const :tag "Yes" t)
                 (const :tag "No" nil)))

(defcustom pdf-outline-imenu-use-flat-menus nil
  "Whether the constructed Imenu should be a list, rather than a tree."
  :group 'pdf-outline
  :type '(choice (const :tag "Yes" t)
                 (const :tag "No" nil)))

(defcustom pdf-outline-display-buffer-action '(nil . nil)
  "The display action used, when displaying the outline buffer."
  :group 'pdf-outline
  :type display-buffer--action-custom-type)

(defvar pdf-outline-minor-mode-map
  (let ((km (make-sparse-keymap)))
    (define-key km (kbd "o") 'pdf-outline)
    km)
  "Keymap used for `pdf-outline-minor-mode'.")

(defvar pdf-outline-buffer-mode-map
  (let ((kmap (make-sparse-keymap)))
    (dotimes (i 10)
      (define-key kmap (vector (+ i ?0)) 'digit-argument))
    (define-key kmap "-" 'negative-argument)
    (define-key kmap (kbd "p") 'previous-line)
    (define-key kmap (kbd "n") 'next-line)
    (define-key kmap (kbd "b") 'outline-backward-same-level)
    (define-key kmap (kbd "d") 'hide-subtree)
    (define-key kmap (kbd "a") 'show-all)
    (define-key kmap (kbd "s") 'show-subtree)
    (define-key kmap (kbd "f") 'outline-forward-same-level)
    (define-key kmap (kbd "u") 'pdf-outline-up-heading)
    (define-key kmap (kbd "q") 'hide-sublevels)
    (define-key kmap (kbd "<") 'beginning-of-buffer)
    (define-key kmap (kbd ">") 'pdf-outline-end-of-buffer)
    (define-key kmap (kbd "TAB") 'outline-toggle-children)
    (define-key kmap (kbd "RET") 'pdf-outline-follow-link)
    (define-key kmap (kbd "C-o") 'pdf-outline-display-link)
    (define-key kmap (kbd "SPC") 'pdf-outline-display-link)
    (define-key kmap [mouse-1] 'pdf-outline-mouse-display-link)
    (define-key kmap (kbd "o") 'pdf-outline-select-pdf-window)
    (define-key kmap (kbd ".") 'pdf-outline-move-to-current-page)
    ;; (define-key kmap (kbd "Q") 'pdf-outline-quit)
    (define-key kmap (kbd "Q") 'pdf-outline-quit-and-kill)
    (define-key kmap (kbd "M-RET") 'pdf-outline-follow-link-and-quit)
    (define-key kmap (kbd "C-c C-f") 'pdf-outline-follow-mode)
    kmap)
  "Keymap used in `pdf-outline-buffer-mode'.")

;;
;; Internal Variables
;; 

(define-button-type 'pdf-outline
  'face nil
  'keymap nil)

(defvar-local pdf-outline-pdf-window nil
  "The PDF window corresponding to this outline buffer.")

(defvar-local pdf-outline-pdf-file nil
  "The PDF file corresponding to this outline buffer.")

(defvar-local pdf-outline-follow-mode-last-link nil)

;;
;; Functions
;; 

;;;###autoload
(define-minor-mode pdf-outline-minor-mode
  "Display an outline of a PDF document.

\\{pdf-outline-minor-mode-map}"
  nil nil nil
  (pdf-util-assert-pdf-buffer)
  (cond
   (pdf-outline-minor-mode
    (when pdf-outline-enable-imenu
      (pdf-outline-imenu-enable)))
   (t
    (when pdf-outline-enable-imenu
      (pdf-outline-imenu-disable)))))

(define-derived-mode pdf-outline-buffer-mode outline-mode "PDF Outline"
  "View and traverse the outline of a PDF file.

Press \\[pdf-outline-display-link] to display the PDF document,
\\[pdf-outline-select-pdf-window] to select it's window,
\\[pdf-outline-move-to-current-page] to move to the outline item
of the current page, \\[pdf-outline-follow-link] to goto the
corresponding page or \\[pdf-outline-follow-link-and-quit] to
additionally quit the Outline.

\\[pdf-outline-follow-mode] enters a variant of
`next-error-follow-mode'.  Most `outline-mode' commands are
rebound to their respective last character.

\\{pdf-outline-buffer-mode-map}"
  (setq outline-regexp "\\( *\\)."
        outline-level
        (lambda nil (1+ (/ (length (match-string 1))
                           pdf-outline-buffer-indent))))

  (toggle-truncate-lines 1)
  (setq buffer-read-only t)
  (when (> (count-lines 1 (point-max))
           (* 1.5 (frame-height)))
    (hide-sublevels 1))
  (message "%s"
           (substitute-command-keys
            (concat
             "Try \\[pdf-outline-display-link], "
             "\\[pdf-outline-select-pdf-window], "
             "\\[pdf-outline-move-to-current-page] or "
             "\\[pdf-outline-follow-link-and-quit]"))))

(define-minor-mode pdf-outline-follow-mode
  "Display links as point moves."
  nil nil nil
  (setq pdf-outline-follow-mode-last-link nil)
  (cond
   (pdf-outline-follow-mode
    (add-hook 'post-command-hook 'pdf-outline-follow-mode-pch nil t))
   (t
    (remove-hook 'post-command-hook 'pdf-outline-follow-mode-pch t))))

(defun pdf-outline-follow-mode-pch ()
  (let ((link (pdf-outline-link-at-pos (point))))
    (when (and link
               (not (eq link pdf-outline-follow-mode-last-link)))
      (setq pdf-outline-follow-mode-last-link link)
      (pdf-outline-display-link (point)))))
  
;;;###autoload
(defun pdf-outline (&optional buffer no-select-window-p)
  "Display an PDF outline of BUFFER.

BUFFER defaults to the current buffer.  Select the outline
buffer, unless NO-SELECT-WINDOW-P is non-nil."
  (interactive (list nil (or current-prefix-arg
                             (consp last-nonmenu-event))))
  (let ((win
         (display-buffer
          (pdf-outline-noselect buffer)
          pdf-outline-display-buffer-action)))
    (unless no-select-window-p
      (select-window win))))

(defun pdf-outline-noselect (&optional buffer)
  "Create an PDF outline of BUFFER, but don't display it."
  (save-current-buffer
    (and buffer (set-buffer buffer))
    (pdf-util-assert-pdf-buffer)
    (let* ((pdf-buffer (current-buffer))
           (pdf-file (or doc-view-buffer-file-name
                         (buffer-file-name)))
           (pdf-window (and (eq pdf-buffer (window-buffer))
                            (selected-window)))
           (bname (pdf-outline-buffer-name))
           (buffer-exists-p (get-buffer bname))
           (buffer (get-buffer-create bname)))
      (with-current-buffer buffer
        (unless buffer-exists-p
          (when (= 0 (save-excursion
                       (pdf-outline-insert-outline pdf-file)))
            (kill-buffer buffer)
            (error "PDF has no outline"))
          (pdf-outline-buffer-mode))
        (set (make-local-variable 'other-window-scroll-buffer)
             pdf-buffer)
        (setq pdf-outline-pdf-window pdf-window
              pdf-outline-pdf-file pdf-file)
        (current-buffer)))))

(defun pdf-outline-buffer-name (&optional pdf-buffer)
  (unless pdf-buffer (setq pdf-buffer (current-buffer)))
  (let ((buf (format "*Outline %s*" (buffer-name pdf-buffer))))
    ;; (when (buffer-live-p (get-buffer buf))
    ;;   (kill-buffer buf))
    buf))
  
(defun pdf-outline-insert-outline (pdf-file)
  (let ((outline (cl-remove-if-not
                  (lambda (type)
                    (eq type 'goto-dest))
                  (pdf-info-outline pdf-file)
                  :key 'cadr)))
    (dolist (item outline)
      (cl-destructuring-bind (lvl _type title page _top)
          item
        (insert-text-button
         (concat
          (make-string (* (1- lvl) pdf-outline-buffer-indent) ?\s)
          title
          (if (> page 0)
              (format " (%d)" page)
            "(invalid)"))
         'type 'pdf-outline
         'help-echo (pdf-links-action-to-string (cdr item))
         'pdf-outline-link (cdr item))
        (newline)))
    (length outline)))

(defun pdf-outline-get-pdf-window (&optional if-visible-p)
  (save-selected-window
    (let* ((buffer (or
                    (find-buffer-visiting
                     pdf-outline-pdf-file)
                    (find-file-noselect
                     pdf-outline-pdf-file)))
           (pdf-window
            (if (and (window-live-p pdf-outline-pdf-window)
                     (eq buffer
                         (window-buffer pdf-outline-pdf-window)))
                pdf-outline-pdf-window
              (or (get-buffer-window buffer)
                  (and (null if-visible-p)
                       (display-buffer
                        buffer
                        '(nil (inhibit-same-window . t))))))))
      (setq pdf-outline-pdf-window pdf-window))))


;;
;; Commands
;; 

(defun pdf-outline-move-to-current-page ()
  "Move to the item corresponding to the current page.

Open nodes as necessary."
  (interactive)
  (let (page)
    (with-selected-window (pdf-outline-get-pdf-window)
      (setq page (doc-view-current-page)))
    (pdf-outline-move-to-page page)))

(defun pdf-outline-quit-and-kill ()
  "Quit browing the outline and kill it's buffer."
  (interactive)
  (pdf-outline-quit t))

(defun pdf-outline-quit (&optional kill)
  "Quit browing the outline buffer."
  (interactive "P")
  (let ((win (selected-window)))
    (pdf-outline-select-pdf-window t)
    (quit-window kill win)))
  
(defun pdf-outline-up-heading (arg &optional invisible-ok)
  "Like `outline-up-heading', but `push-mark' first."
  (interactive "p")
  (let ((pos (point)))
    (outline-up-heading arg invisible-ok)
    (unless (= pos (point))
      (push-mark pos))))
   
(defun pdf-outline-end-of-buffer ()
  "Move to the end of the outline buffer."
  (interactive)
  (let ((pos (point)))
    (goto-char (point-max))
    (when (and (eobp)
               (not (bobp))
               (null (button-at (point))))
      (forward-line -1))
    (unless (= pos (point))
      (push-mark pos))))
  
(defun pdf-outline-link-at-pos (&optional pos)
  (unless pos (setq pos (point)))
  (let ((button (or (button-at pos)
                    (button-at (1- pos)))))
    (and button
         (button-get button
                     'pdf-outline-link))))
  
(defun pdf-outline-follow-link (&optional pos)
  "Select PDF window and move to the page corresponding to POS."
  (interactive)
  (unless pos (setq pos (point)))
  (let ((link (pdf-outline-link-at-pos pos)))
    (unless link
      (error "Nothing to follow here"))
    (select-window (pdf-outline-get-pdf-window))
    (pdf-links-do-action link)))

(defun pdf-outline-follow-link-and-quit (&optional pos)
  "Select PDF window and move to the page corresponding to POS.

Then quit the outline window."
  (interactive)
  (let ((link (pdf-outline-link-at-pos (or pos (point)))))
    (pdf-outline-quit)
    (unless link
      (error "Nothing to follow here"))
    (pdf-links-do-action link)))
  
(defun pdf-outline-display-link (&optional pos)
  "Display the page corresponding to the link at POS."
  (interactive)
  (unless pos (setq pos (point)))
  (let ((link (pdf-outline-link-at-pos pos)))
    (unless link
      (error "Nothing to follow here"))
    (with-selected-window (pdf-outline-get-pdf-window)
      (pdf-links-do-action link))))

(defun pdf-outline-mouse-display-link (event)
  "Display the page corresponding to the position of EVENT."
  (interactive "@e")
  (pdf-outline-display-link
   (posn-point (event-start event))))

(defun pdf-outline-select-pdf-window (&optional no-create-p)
  "Display and select the PDF document window."
  (interactive)
  (let ((win (pdf-outline-get-pdf-window no-create-p)))
    (and (window-live-p win)
         (select-window win))))

(defun pdf-outline-toggle-subtree ()
  "Toggel hidden state of the current complete subtree."
  (interactive)
  (save-excursion
    (outline-back-to-heading)
    (if (not (outline-invisible-p (line-end-position)))
	(hide-subtree)
      (show-subtree))))

(defun pdf-outline-move-to-page (page)
  "Move to an outline item corresponding to PAGE."
  (interactive
   (list (or (and current-prefix-arg
                  (prefix-numeric-value current-prefix-arg))
             (read-number "Page: "))))
  (goto-char (pdf-outline-position-of-page page))
  (save-excursion
    (while (outline-invisible-p)
      (outline-up-heading 1 t)
      (show-children)))
  (save-excursion
    (when (outline-invisible-p)
      (outline-up-heading 1 t)
      (show-children)))
  (back-to-indentation))
              
(defun pdf-outline-position-of-page (page)
  (let ((current 0)
        (pos (point-max)))
    (save-excursion
      (goto-char (point-min))
      (while (<= current page)
        (setq pos (point))
        (forward-line)
        (setq current (nth 2 (pdf-outline-link-at-pos))))
      pos)))
      
  

;;
;; Imenu Support
;; 
  

;;;###autoload
;; FIXME: Use existing menu entry ?
(defun pdf-outline-imenu-enable ()
  "Enable imenu in the current PDF buffer."
  (interactive)
  (pdf-util-assert-pdf-buffer)
  (setq-local imenu-create-index-function
              (if pdf-outline-imenu-use-flat-menus
                  'pdf-outline-imenu-create-index-flat
                'pdf-outline-imenu-create-index-tree))
  (imenu-add-to-menubar "PDF Outline"))

(defun pdf-outline-imenu-disable ()
  "Disable imenu in the current PDF buffer."
  (interactive)
  (pdf-util-assert-pdf-buffer)
  (setq-local imenu-create-index-function nil)
  (local-set-key [menu-bar index] nil)
  (when (eq doc-view-mode-map
            (keymap-parent (current-local-map)))
    (use-local-map (keymap-parent (current-local-map)))))
  

(defun pdf-outline-imenu-create-item (_lvl link)
  (cl-destructuring-bind ( _type title page _top)
      link
    (list (format "%s (%d)" title page)
          0
          'pdf-outline-imenu-activate-link
          link)))
  
(defun pdf-outline-imenu-create-index-flat ()
  (let ((outline (cl-remove-if-not
                  (lambda (type)
                    (eq type 'goto-dest))
                  (pdf-info-outline doc-view-buffer-file-name)
                  :key 'cadr))
        index)
    (dolist (o outline)
      (push (pdf-outline-imenu-create-item
             (car o) (cdr o))
            index))
    (nreverse index)))
        
    
(defun pdf-outline-imenu-create-index-tree ()
  (pdf-outline-imenu-create-index-tree-1
   (pdf-outline-treeify-outline-list
    (cl-remove-if-not
     (lambda (type)
       (eq type 'goto-dest))
     (pdf-info-outline doc-view-buffer-file-name)
     :key 'cadr))))

(defun pdf-outline-imenu-create-index-tree-1 (nodes)
  (mapcar (lambda (node)
            (let (children)
              (when (consp (car node))
                (setq children (cdr node)
                      node (car node)))
              (let ((title (nth 2 node))
                    (item
                     (pdf-outline-imenu-create-item
                      (car node) (cdr node))))
                (if children
                    (cons title
                          (cons item (pdf-outline-imenu-create-index-tree-1
                                     children)))
                  item))))
          nodes))

(defun pdf-outline-treeify-outline-list (list)
  (when list
    (let ((level (caar list))
          result)
      (while (and list
                  (>= (caar list)
                      level))
        (when (= (caar list) level)
          (let ((item (car list)))
            (when (and (cdr list)
                       (>  (car (cadr list))
                           level))
              (setq item
                    (cons
                     item
                     (pdf-outline-treeify-outline-list (cdr list)))))
            (push item result)))
        (setq list (cdr list)))
      (reverse result))))

(defun pdf-outline-imenu-activate-link (&rest args)
  ;; bug #14029
  (when (eq (nth 2 args) 'pdf-outline-imenu-activate-link)
    (setq args (cdr args)))
  (pdf-links-do-action (nth 2 args)))

(defadvice imenu--split-menu (around pdf-outline activate)
  "Advice to keep the original outline order.

 Calls `pdf-outline-imenu--split-menu' instead, if in a PDF
 buffer and `pdf-outline-imenu-keep-order' is non-nil."
  (if (not (and (pdf-util-pdf-buffer-p)
                pdf-outline-imenu-keep-order))
      ad-do-it
    (setq ad-return-value
          (pdf-outline-imenu--split-menu menulist title))))

(defvar imenu--rescan-item)
(defvar imenu-sort-function)
(defvar imenu-create-index-function)
(defvar imenu-max-items)

(defun pdf-outline-imenu--split-menu (menulist title)
  "Replacement function for `imenu--split-menu'.

This function does not move sub-menus to the top, therefore
keeping the original outline order of the document.  Also it does
not call `imenu-sort-function'."
  (let ((menulist (copy-sequence menulist))
        keep-at-top)
    (if (memq imenu--rescan-item menulist)
	(setq keep-at-top (list imenu--rescan-item)
	      menulist (delq imenu--rescan-item menulist)))
    (if (> (length menulist) imenu-max-items)
	(setq menulist
	      (mapcar
	       (lambda (menu)
		 (cons (format "From: %s" (caar menu)) menu))
	       (imenu--split menulist imenu-max-items))))
    (cons title
	  (nconc (nreverse keep-at-top) menulist))))

(provide 'pdf-outline)

;;; pdf-outline.el ends here
