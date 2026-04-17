;;; real-backup-test.el --- Tests for real-backup  -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'real-backup)

(defmacro real-backup-test--with-temp-file (var &rest body)
  "Create temp file path bound to VAR and execute BODY."
  (declare (indent 1))
  `(let ((,var (make-temp-file "real-backup-test-")))
     (unwind-protect
         (progn ,@body)
       (when (file-exists-p ,var)
         (delete-file ,var)))))

(ert-deftest real-backup-test-compute-location-no-side-effects ()
  (let ((real-backup-directory (make-temp-file "real-backup-dir-" t)))
    (unwind-protect
        (real-backup-test--with-temp-file filename
          (let ((computed (real-backup-compute-location filename)))
            (should (string-prefix-p (expand-file-name real-backup-directory) computed))
            (should-not (file-directory-p (file-name-directory computed)))))
      (delete-directory real-backup-directory t))))

(ert-deftest real-backup-test-compute-location-remote-and-windows-path ()
  (let ((real-backup-directory "/tmp/real-backup-tests"))
    (let ((remote (real-backup-compute-location "/ssh:alice@example.com:/home/alice/a.txt")))
      (should (string-match-p "/ssh/example\\.com/alice/home/alice/" remote)))
    (let ((system-type 'windows-nt))
      (let ((win (real-backup-compute-location "C:/work/project/file.txt")))
        (should (string-match-p "/local/localhost/.*/C/work/project/" win))))))

(ert-deftest real-backup-test-backups-of-file-missing-dir ()
  (let ((real-backup-directory (make-temp-file "real-backup-dir-" t)))
    (unwind-protect
        (real-backup-test--with-temp-file filename
          (should-not (real-backup-backups-of-file filename)))
      (delete-directory real-backup-directory t))))

(ert-deftest real-backup-test-backup-discovery-sorts-and-parses ()
  (let ((real-backup-directory (make-temp-file "real-backup-dir-" t)))
    (unwind-protect
        (real-backup-test--with-temp-file filename
          (let* ((base (real-backup-compute-location filename))
                 (dir (file-name-directory base))
                 (name (file-name-nondirectory base)))
            (make-directory dir t)
            (dolist (f (list (concat name "#2026-01-01-00-00-00")
                             (concat name "#2025-12-31-23-59-59.gz")
                             (concat name "#not-a-date")
                             "other.txt"))
              (with-temp-file (expand-file-name f dir) (insert "x")))
            (let ((entries (real-backup--backup-entries filename)))
              (should (= 2 (length entries)))
              (should (string= "2025-12-31-23-59-59" (plist-get (car entries) :timestamp)))
              (should (string= "2026-01-01-00-00-00" (plist-get (cadr entries) :timestamp))))))
      (delete-directory real-backup-directory t))))

(ert-deftest real-backup-test-cleanup-keep-zero-deletes-all ()
  (let ((real-backup-directory (make-temp-file "real-backup-dir-" t))
        (real-backup-cleanup-keep 0))
    (unwind-protect
        (real-backup-test--with-temp-file filename
          (let* ((base (real-backup-compute-location filename))
                 (dir (file-name-directory base))
                 (name (file-name-nondirectory base)))
            (make-directory dir t)
            (dolist (stamp '("2026-01-01-00-00-00" "2026-01-01-00-00-01"))
              (with-temp-file (expand-file-name (concat name "#" stamp) dir) (insert "x")))
            (real-backup-cleanup filename)
            (should-not (directory-files dir nil "^[^.]" t))))
      (delete-directory real-backup-directory t))))

(ert-deftest real-backup-test-mode-hook-is-buffer-local ()
  (with-temp-buffer
    (let ((default-hooks (default-value 'after-save-hook)))
      (real-backup-mode 1)
      (should (local-variable-p 'after-save-hook))
      (should (memq #'real-backup after-save-hook))
      (should-not (memq #'real-backup default-hooks))
      (real-backup-mode -1)
      (should-not (memq #'real-backup after-save-hook)))))

(ert-deftest real-backup-test-global-excluded-modes-works-with-list ()
  (let ((real-backup-global-excluded-modes '(emacs-lisp-mode)))
    (with-temp-buffer
      (emacs-lisp-mode)
      (real-backup-turn-on)
      (should-not real-backup-mode))
    (with-temp-buffer
      (fundamental-mode)
      (real-backup-turn-on)
      (should real-backup-mode))))

(ert-deftest real-backup-test-open-errors-when-no-backups ()
  (let ((real-backup-directory (make-temp-file "real-backup-dir-" t)))
    (unwind-protect
        (real-backup-test--with-temp-file filename
          (with-temp-buffer
            (setq buffer-file-name filename)
            (should-error (real-backup-open filename) :type 'user-error)))
      (delete-directory real-backup-directory t))))

(ert-deftest real-backup-test-open-selects-single-candidate ()
  (let ((real-backup-directory (make-temp-file "real-backup-dir-" t))
        opened)
    (unwind-protect
        (real-backup-test--with-temp-file filename
          (let* ((base (real-backup-compute-location filename))
                 (dir (file-name-directory base))
                 (name (file-name-nondirectory base))
                 (backup-name (concat name "#2026-01-01-00-00-00")))
            (make-directory dir t)
            (with-temp-file (expand-file-name backup-name dir) (insert "x"))
            (cl-letf (((symbol-function 'completing-read)
                       (lambda (_prompt collection &rest _)
                         (car collection)))
                      ((symbol-function 'find-file)
                       (lambda (f) (setq opened f) (get-buffer-create " *real-backup-open*"))))
              (with-temp-buffer
                (setq buffer-file-name filename)
                (real-backup-open filename)))
            (should (string= (expand-file-name backup-name dir) opened))))
      (delete-directory real-backup-directory t))))

(ert-deftest real-backup-test-open-selects-from-multiple-candidates ()
  (let ((real-backup-directory (make-temp-file "real-backup-dir-" t))
        opened)
    (unwind-protect
        (real-backup-test--with-temp-file filename
          (let* ((base (real-backup-compute-location filename))
                 (dir (file-name-directory base))
                 (name (file-name-nondirectory base))
                 (older (concat name "#2026-01-01-00-00-00"))
                 (newer (concat name "#2026-01-01-00-00-01")))
            (make-directory dir t)
            (with-temp-file (expand-file-name older dir) (insert "x"))
            (with-temp-file (expand-file-name newer dir) (insert "x"))
            (cl-letf (((symbol-function 'completing-read)
                       (lambda (_prompt collection &rest _)
                         (cadr collection)))
                      ((symbol-function 'find-file)
                       (lambda (f) (setq opened f) (get-buffer-create " *real-backup-open*"))))
              (with-temp-buffer
                (setq buffer-file-name filename)
                (real-backup-open filename)))
            (should (string= (expand-file-name newer dir) opened))))
      (delete-directory real-backup-directory t))))

(provide 'real-backup-test)
;;; real-backup-test.el ends here
