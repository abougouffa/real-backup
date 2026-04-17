;;; real-backup.el --- Make a copy at each savepoint of a file  -*- lexical-binding: t; -*-

;; Copyright (C) 2024-2026  Abdelhak BOUGOUFFA (rot13 "nobhtbhssn@srqbencebwrpg.bet")
;; Copyright (C) 2004  Benjamin RUTT (rot13 "oehgg@oybbzvatgba.va.hf")

;; Author: Abdelhak BOUGOUFFA
;; Maintainer: Abdelhak BOUGOUFFA
;; Keywords: files, convenience
;; Version: 4.0
;; URL: https://github.com/abougouffa/real-backup
;; Package-Requires: ((emacs "28.1"))

;;; Commentary:

;; This is a fork and reviving of [`backup-each-save'](https://www.emacswiki.org/emacs/BackupEachSave).

;; Ever wish to go back to an older saved version of a file?  Then
;; this package is for you.  This package copies every file you save
;; in Emacs to a backup directory tree (which mirrors the tree
;; structure of the filesystem), with a timestamp suffix to make
;; multiple saves of the same file unique.  Never lose old saved
;; versions again.

;; To activate globally, place this file in your `load-path', and add
;; the following lines to your init file:
;;
;;     (require 'real-backup)
;;     (global-real-backup-mode 1)

;; To activate only for individual modes, add the require line as
;; above to your init.el and hook like this:
;;
;;     (add-hook 'python-mode-hook 'real-backup-mode)


;; To filter out which files it backs up, use a custom function for
;; `real-backup-filter-function'.  For example, to filter out
;; the saving of GPG encypted files, do:
;;
;;     (defun real-backup-no-gpg-files (filename)
;;       (not (equal (file-name-extension filename) "gpg")))
;;     (setq real-backup-filter-function #'real-backup-no-gpg-files)

;;; ChangeLog
;; - v1.1:  added `real-backup-filter-function'
;; - v1.2:
;;   - added real-backup-size-limit
;;   - fixed "Local Variables" docs, which was inadvertently being activated
;; - v1.3:  fix for some emacsen not having `file-remote-p'
;; - v1.4:  added footer and autoload
;; - v2.0:  refactor, deprecate old Emacs
;; - v2.1:
;;   - more features and tweaks
;;   - add `real-backup-cleanup' and `real-backup-auto-cleanup'
;;   - add `real-backup-open-backup'
;; - v3.0:  rebrand the package as `real-backup'
;; - v3.1:  add compression support
;; - v3.2:  add support for candidates preview
;; - v3.3:
;;   - jump to first changed position when switching between preview candidates
;;   - add optional split-window diff view when previewing candidates
;; - v3.4:
;;   - make `real-backup-open-backup' obsolete, use `real-backup-open' instead
;;   - better diffs
;; - v4.0:
;;   - make `real-backup-mode' local and add globalized mode
;;   - add `real-backup-global-excluded-modes'
;;   - update the documentation

;;; Code:

(autoload 'cl-set-difference "cl-seq")
(autoload 'string-remove-prefix "subr-x")
(autoload 'diff-no-select "diff")

(defgroup real-backup nil
  "Real Backup."
  :group 'files)

(defcustom real-backup-directory (locate-user-emacs-file "real-backup/")
  "The root directory when to create backups."
  :group 'real-backup
  :type 'directory)

(defcustom real-backup-remote-files t
  "Whether to backup remote files at each save.

Defaults to nil."
  :group 'real-backup
  :type 'boolean)

(defcustom real-backup-filter-function #'identity
  "Function which should return non-nil if the file should be backed up."
  :group 'real-backup
  :type 'function)

(defcustom real-backup-global-excluded-modes nil
  "A list of modes to be excluded when enabling globally."
  :group 'real-backup
  :type '(repeat symbol))

(defcustom real-backup-size-limit (* 1 1024 1024)
  "Maximum size of a file (in bytes) that should be copied at each savepoint.

If a file is greater than this size, don't make a backup of it.
Setting this variable to nil disables backup suppressions based
on size."
  :group 'real-backup
  :type '(choice natnum (symbol nil)))

(defcustom real-backup-cleanup-keep 20
  "Number of copies to keep for each file in `real-backup-cleanup'."
  :group 'real-backup
  :type 'natnum)

(defcustom real-backup-auto-cleanup nil
  "Automatically cleanup after making a backup."
  :group 'real-backup
  :type 'boolean)

(defcustom real-backup-show-header t
  "Show a header when vienwing a backup file."
  :group 'real-backup
  :type 'boolean)

(defcustom real-backup-compression (if (executable-find "zstd") 'zst 'gz)
  "Compression extension to be used, set to nil to disable compression."
  :group 'real-backup
  :type '(choice
          (const :tag "BZip2" bz2)
          (const :tag "GZip" gz)
          (const :tag "Lzma" lz)
          (const :tag "XZ" xz)
          (const :tag "Z-Standard" zst)
          (const :tag "No Compression" nil)))

(defcustom real-backup-preview-jump-to-first-change t
  "When non-nil, jump to the first changed position when previewing a candidate.
The jump point is computed relative to the previously previewed candidate."
  :group 'real-backup
  :type 'boolean)

(defcustom real-backup-preview-show-diff nil
  "When non-nil, show a diff window alongside the backup preview window."
  :group 'real-backup
  :type 'boolean)

(defcustom real-backup-preview-diff-against-current-file nil
  "Controls what is compared in the diff window.
Only relevant when `real-backup-preview-show-diff' is non-nil.
When non-nil, the diff window shows changes between the saved file on disk
and the previewed candidate.
When nil (the default), the diff window shows changes between the
previously previewed candidate and the current one."
  :group 'real-backup
  :type 'boolean)

(defconst real-backup--time-format "%Y-%m-%d-%H-%M-%S"
  "Format given to `format-time-string' which is appended to the filename.")

(defconst real-backup--time-match-regexp "[[:digit:]]\\{4\\}\\(-[[:digit:]]\\{2\\}\\)\\{5\\}"
  "A regexp that matches `real-backup--time-format'.")

(defun real-backup--warn (fmt &rest args)
  "Show a warning message using FMT with ARGS."
  (display-warning 'real-backup (apply #'format fmt args) :warning))

(defun real-backup--make-a-copy (orig-filename backup-filename)
  "Make a copy for ORIG-FILENAME to BACKUP-FILENAME."
  (let ((target-filename (if-let* ((ext (and real-backup-compression (symbol-name real-backup-compression))))
                             (concat backup-filename "." ext)
                           backup-filename)))
    (condition-case err
        (if real-backup-compression
            (let ((jka-compr-verbose nil))
              (with-auto-compression-mode
                (with-temp-buffer
                  (insert-file-contents orig-filename)
                  (write-region nil nil target-filename nil 'silent))))
          (copy-file orig-filename target-filename t t t))
      (error
       (real-backup--warn "Failed to backup %s: %s"
                          (abbreviate-file-name orig-filename)
                          (error-message-string err))
       nil))))

(defun real-backup ()
  "Perform a backup of the current file if needed."
  (when-let* ((filename (buffer-file-name))
              (backup-filename (real-backup-compute-location filename 'unique)))
    (when (and (or real-backup-remote-files (not (file-remote-p filename)))
               (funcall real-backup-filter-function filename)
               (or (not real-backup-size-limit) (<= (buffer-size) real-backup-size-limit)))
      (real-backup--make-a-copy filename backup-filename)
      (when real-backup-auto-cleanup (real-backup-cleanup filename)))))

(defun real-backup-compute-location (filename &optional unique)
  "Compute backup location for FILENAME.

When UNIQUE is provided, add a unique timestamp after the file name."
  (let* ((localname (or (file-remote-p filename 'localname) filename))
         (method (or (file-remote-p filename 'method) "local"))
         (host (or (file-remote-p filename 'host) "localhost"))
         (user (or (file-remote-p filename 'user) user-real-login-name))
         (containing-dir (file-name-directory localname))
         ;; Better handling of Windows paths: C:/path/to/file -> real-backup/location/C/path/to/file
         (containing-dir (if (and (eq system-type 'windows-nt)
                                  (string-match "^\\([[:alpha:]]\\):\\([/\\].*\\)$" containing-dir))
                             (concat (upcase (match-string 1 containing-dir)) (match-string 2 containing-dir))
                           containing-dir))
         (backup-dir (file-name-concat real-backup-directory method host user containing-dir))
         (backup-basename (format "%s%s" (file-name-nondirectory localname) (if unique (concat "#" (format-time-string real-backup--time-format)) ""))))
    (unless (file-exists-p backup-dir)
      (make-directory backup-dir t))
    (expand-file-name backup-basename backup-dir)))

(defun real-backup-backups-of-file (filename)
  "List of backups for FILENAME."
  (let* ((backup-filename (real-backup-compute-location filename))
         (backup-dir (file-name-directory backup-filename)))
    (directory-files backup-dir nil (concat "^" (regexp-quote (file-name-nondirectory backup-filename)) "#" real-backup--time-match-regexp "\\(\\.[[:alnum:]]+\\)?" "$"))))

(defun real-backup--format-as-date (orig-name backup-name)
  "Format ORIG-NAME and BACKUP-NAME as a date."
  (let ((timestamp (file-name-sans-extension (string-remove-prefix (concat (file-name-nondirectory orig-name) "#") backup-name))))
    (cons (apply (apply-partially #'format "%s-%s-%s %s:%s:%s") (split-string timestamp "-")) backup-name)))

;;;###autoload
(defun real-backup-cleanup (filename)
  "Cleanup backups of FILENAME, keeping `real-backup-cleanup-keep' copies."
  (interactive (list buffer-file-name))
  (if (not filename)
      (user-error "This buffer is not visiting a file")
    (let* ((backup-dir (file-name-directory (real-backup-compute-location filename)))
           (backup-files (real-backup-backups-of-file filename)))
      (dolist (file (cl-set-difference backup-files (last backup-files real-backup-cleanup-keep) :test #'string=))
        (let ((fname (expand-file-name file backup-dir)))
          (delete-file fname t))))))

(defun real-backup--completing-read-candidate (candidates)
  "Return the currently highlighted candidate during `completing-read'.
CANDIDATES is the list of candidate strings.  When Vertico is active the
currently selected item is returned via its internal state; otherwise the
best match for the current minibuffer input is returned."
  (cond
   ;; `vertico': use the internally tracked index/candidates list
   ((and (bound-and-true-p vertico-mode)
         (boundp 'vertico--candidates)
         (boundp 'vertico--index)
         (>= vertico--index 0))
    (nth vertico--index vertico--candidates))
   ;; Fallback to builtin `icomplete'/`fido': match against what is typed
   (t
    (let ((input (minibuffer-contents-no-properties)))
      (or (car (member input candidates))
          (car (all-completions input candidates))
          ;; When nothing has been typed yet show the first candidate
          (car candidates))))))

(defun real-backup--find-first-diff-pos (old-text new-text)
  "Return the 0-based index of the first differing character between OLD-TEXT and NEW-TEXT.
Returns nil when the two strings are identical."
  (let ((result (compare-strings old-text nil nil new-text nil nil)))
    (unless (eq result t)
      (1- (abs result)))))

(defun real-backup--show-diff-preview (old-content new-content diff-buf orig-filename diff-label)
  "Update DIFF-BUF with a unified diff between OLD-CONTENT and NEW-CONTENT.
ORIG-FILENAME and DIFF-LABEL are used in the buffer's header line."
  (let* ((suffix (when-let* ((ext (file-name-extension orig-filename)))
                   (concat "." ext)))
         (old-tmp (make-temp-file "real-backup-diff-" nil suffix))
         (new-tmp (make-temp-file "real-backup-diff-" nil suffix)))
    (unwind-protect
        (progn
          (with-temp-file old-tmp (insert (or old-content "")))
          (with-temp-file new-tmp (insert new-content))
          (diff-no-select old-tmp new-tmp "-u" t diff-buf)
          (with-current-buffer diff-buf
            ;; Force synchronous fontification; diff-mode registers keywords but
            ;; jit-lock would otherwise defer rendering until display time.
            (font-lock-ensure)
            (when real-backup-show-header
              (setq header-line-format
                    (propertize (format "--- Diff%s: %s %%-" diff-label (file-name-nondirectory orig-filename))
                                'face 'warning))))
          (display-buffer diff-buf
                          '((display-buffer-reuse-window display-buffer-use-some-window))))
      (when (file-exists-p old-tmp) (delete-file old-tmp))
      (when (file-exists-p new-tmp) (delete-file new-tmp)))))

(defun real-backup--show-preview (backup-name backup-dir orig-mode preview-buf target-win label &optional prev-content)
  "Display a preview of BACKUP-NAME from BACKUP-DIR in PREVIEW-BUF.
ORIG-MODE is called to activate the appropriate major mode, LABEL is
shown in the buffer's header line, and TARGET-WIN is the window in which
the preview will be shown.  When PREV-CONTENT is non-nil and
`real-backup-preview-jump-to-first-change' is non-nil, point is moved to
the first position that differs from PREV-CONTENT.  Returns the buffer
contents as a string, or nil if the file is not readable."
  (let ((full-path (expand-file-name backup-name backup-dir)))
    (when (file-readable-p full-path)
      (with-current-buffer preview-buf
        (let ((inhibit-read-only t)
              (jka-compr-verbose nil))
          (erase-buffer)
          (with-auto-compression-mode
            (insert-file-contents full-path))
          (delay-mode-hooks (funcall orig-mode))
          (font-lock-ensure) ; Force synchronous fontification
          (display-line-numbers-mode 1)
          (setq buffer-read-only t)
          (let* ((new-content (buffer-string))
                 (jump-pos
                  (if (and real-backup-preview-jump-to-first-change prev-content)
                      (let ((diff-pos (real-backup--find-first-diff-pos prev-content new-content)))
                        ;; diff-pos is 0-based; buffer positions are 1-based
                        (if diff-pos (1+ diff-pos) (point-min)))
                    (point-min))))
            (goto-char jump-pos)
            (when real-backup-show-header
              (setq header-line-format (propertize label 'face 'warning)))
            (when-let* ((win (display-buffer preview-buf '((display-buffer-reuse-window display-buffer-same-window)))))
              (set-window-point win jump-pos)
              (when real-backup-preview-jump-to-first-change
                (with-selected-window win
                  (recenter)
                  (pulse-momentary-highlight-one-line (point)))))
            new-content))))))

;;;###autoload
(define-obsolete-function-alias 'real-backup-open-backup 'real-backup-open "3.4" "Open a backup of FILENAME or the current buffer.")

;;;###autoload
(defun real-backup-open (filename)
  "Open a backup of FILENAME or the current buffer."
  (interactive (list buffer-file-name))
  (unless filename
    (user-error "This buffer is not visiting a file"))
  (let* ((orig-mode major-mode)
         (orig-dir default-directory)
         (orig-buf (current-buffer))
         (orig-win (selected-window))
         (backup-dir (file-name-directory (real-backup-compute-location filename)))
         (backup-files (mapcar (apply-partially #'real-backup--format-as-date filename)
                               (real-backup-backups-of-file filename)))
         (candidates (mapcar #'car backup-files))
         (preview-buf (get-buffer-create " *real-backup-preview*"))
         (diff-buf (and real-backup-preview-show-diff (get-buffer-create " *real-backup-diff*")))
         (current-file-content
          (and diff-buf real-backup-preview-diff-against-current-file
               (with-temp-buffer (insert-file-contents filename) (buffer-string))))
         (last-preview nil)
         (last-preview-content nil)
         (do-preview
          (lambda ()
            (when-let* ((current (real-backup--completing-read-candidate candidates))
                        (backup-name (cdr (assoc current backup-files))))
              (unless (equal current last-preview)
                (let ((prev-content last-preview-content))
                  (setq last-preview current)
                  (setq last-preview-content
                        (real-backup--show-preview
                         backup-name backup-dir orig-mode preview-buf orig-win
                         (format "--- Preview: Real Backup of %s @ %s %%-"
                                 (file-name-nondirectory filename) current)
                         prev-content))
                  ;; Show the diff only when we have content to display, and either we're
                  ;; diffing against the current file (always available) or we have a
                  ;; previous candidate to compare against (not available on the first pick).
                  (when (and diff-buf last-preview-content
                             (or real-backup-preview-diff-against-current-file prev-content))
                    (real-backup--show-diff-preview
                     (if real-backup-preview-diff-against-current-file
                         current-file-content
                       prev-content)
                     last-preview-content diff-buf filename
                     (if real-backup-preview-diff-against-current-file
                         " (vs. current file)"
                       " (vs. previous candidate)"))))))))
         (selected
          (unwind-protect
              (minibuffer-with-setup-hook
                  (lambda () (add-hook 'post-command-hook do-preview nil t))
                (completing-read "Select version: " candidates nil t))
            (when (buffer-live-p preview-buf)
              (kill-buffer preview-buf))
            (when (and diff-buf (buffer-live-p diff-buf))
              (kill-buffer diff-buf))
            (when (window-live-p orig-win)
              (set-window-buffer orig-win orig-buf))))
         (backup-file (alist-get selected backup-files nil nil #'equal)))
    (if backup-file
        (with-current-buffer (find-file (expand-file-name backup-file backup-dir))
          (funcall orig-mode)
          (setq-local default-directory orig-dir)
          (when real-backup-show-header
            (setq header-line-format
                  (propertize (format "--- Real Backup of file %s @ %s %%-"
                                      (file-name-nondirectory filename)
                                      (car (real-backup--format-as-date filename backup-file)))
                              'face 'warning)))
          (read-only-mode 1))
      (user-error "No backup version selected"))))

(defun real-backup-turn-on ()
  (unless (derived-mode-p real-backup-global-excluded-modes)
    (real-backup-mode 1)))

;;;###autoload
(define-minor-mode real-backup-mode
  "Automatically backup files after saving them."
  :init-value nil
  :lighter " Backup"
  :global nil
  (if real-backup-mode
      (add-hook 'after-save-hook 'real-backup)
    (remove-hook 'after-save-hook 'real-backup)))

;;;###autoload
(define-globalized-minor-mode global-real-backup-mode real-backup-mode real-backup-turn-on)


(provide 'real-backup)
;;; real-backup.el ends here
