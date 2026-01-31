;;; real-backup.el --- Make a copy at each savepoint of a file  -*- lexical-binding: t; -*-

;; Copyright (C) 2024-2026  Abdelhak BOUGOUFFA (rot13 "nobhtbhssn@srqbencebwrpg.bet")
;; Copyright (C) 2004  Benjamin RUTT (rot13 "oehgg@oybbzvatgba.va.hf")

;; Author: Abdelhak BOUGOUFFA
;; Maintainer: Abdelhak BOUGOUFFA
;; Keywords: files, convenience
;; Version: 3.1
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
;; the following lines to your ~/.emacs file:
;;
;;     (require 'real-backup)
;;     (add-hook 'after-save-hook 'real-backup)

;; To activate only for individual files, add the require line as
;; above to your ~/.emacs, and place a local variables entry at the
;; end of your file containing the statement:
;;
;;     (add-hook (make-local-variable 'after-save-hook) 'real-backup)
;;
;; NOTE:  I would give a full example of how to do this here, but it
;; would then try to activate it for this file since it is a short
;; file and the docs would then be within the "end of the file" local
;; variables region.  :)

;; To filter out which files it backs up, use a custom function for
;; `real-backup-filter-function'.  For example, to filter out
;; the saving of gnus .newsrc.eld files, do:
;;
;;     (defun real-backup-no-newsrc-eld (filename)
;;       (cond
;;        ((string= (file-name-nondirectory filename) ".newsrc.eld") nil)
;;        (t t)))
;;     (setq real-backup-filter-function 'real-backup-no-newsrc-eld)

;;; ChangeLog
;; - v1.0 -> v1.1:  added `real-backup-filter-function'
;; - v1.1 -> v1.2:
;;   - added real-backup-size-limit
;;   - fixed "Local Variables" docs, which was inadvertently being activated
;; - v1.2 -> v1.3:  fix for some emacsen not having `file-remote-p'
;; - v1.3 -> v1.4:  added footer and autoload
;; - v1.4 -> v2.0:  refactor, deprecate old Emacs
;; - v2.0 -> v2.1:
;;   - more features and tweaks
;;   - add `real-backup-cleanup' and `real-backup-auto-cleanup'
;;   - add `real-backup-open-backup'
;; - v2.1 -> v3.0:  rebrand the package as `real-backup'
;; - v3.0 -> v3.1:  add compression support

;;; Code:

(autoload 'cl-set-difference "cl-seq")
(autoload 'string-remove-prefix "subr-x")

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

(defconst real-backup--time-format "%Y-%m-%d-%H-%M-%S"
  "Format given to `format-time-string' which is appended to the filename.")

(defconst real-backup--time-match-regexp "[[:digit:]]\\{4\\}\\(-[[:digit:]]\\{2\\}\\)\\{5\\}"
  "A regexp that matches `real-backup--time-format'.")

(defun real-backup--make-a-copy (orig-filename backup-filename)
  "Make a copy for ORIG-FILENAME to BACKUP-FILENAME."
  (let ((jka-compr-verbose nil))
    (with-auto-compression-mode
      (with-temp-buffer
        (insert-file-contents orig-filename)
        (write-region nil nil (concat backup-filename
                                      (if (symbolp real-backup-compression)
                                          (concat "." (symbol-name real-backup-compression))
                                        ""))
                      nil 0)))))

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
    (when (not (file-exists-p backup-dir))
      (make-directory backup-dir t))
    (expand-file-name backup-basename backup-dir)))

(defun real-backup-backups-of-file (filename)
  "List of backups for FILENAME."
  (let* ((backup-filename (real-backup-compute-location filename))
         (backup-dir (file-name-directory backup-filename)))
    (directory-files backup-dir nil (concat "^" (regexp-quote (file-name-nondirectory backup-filename)) "#" real-backup--time-match-regexp "\\(\\.[[:alnum:]]+\\)?" "$"))))

(defun real-backup--format-as-date (orig-name backup-name)
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

;;;###autoload
(defun real-backup-open-backup (filename)
  "Open a backup of FILENAME or the current buffer."
  (interactive (list buffer-file-name))
  (if (not filename)
      (user-error "This buffer is not visiting a file")
    (let* ((current-major-mode major-mode)
           (default-dir default-directory)
           (backup-dir (file-name-directory (real-backup-compute-location filename)))
           (backup-files (mapcar (apply-partially #'real-backup--format-as-date filename) (real-backup-backups-of-file filename)))
           (backup-file (alist-get (completing-read "Select file: " (mapcar #'car backup-files)) backup-files nil nil #'equal)))
      (with-current-buffer (find-file (expand-file-name backup-file backup-dir))
        ;; Apply the same major mode and the same default directory as the original file
        (funcall current-major-mode)
        (setq-local default-directory default-dir)
        (when real-backup-show-header
          (setq header-line-format
                (propertize (format "--- Real Backup of file %s @ %s %%-" (file-name-nondirectory filename) (car (real-backup--format-as-date filename backup-file)))
                            'face 'warning)))
        (read-only-mode 1)))))

;;;###autoload
(define-minor-mode real-backup-mode
  "Automatically backup files after saving them."
  :init-value nil
  :lighter " Backup"
  :global t
  (if real-backup-mode
      (add-hook 'after-save-hook 'real-backup)
    (remove-hook 'after-save-hook 'real-backup)))


(provide 'real-backup)
;;; real-backup.el ends here
