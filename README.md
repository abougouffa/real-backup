<a href="https://github.com/abougouffa/real-backup"><img src="https://www.gnu.org/software/emacs/images/emacs.png" alt="Emacs Logo" width="80" height="80" align="right"></a>
## real-backup.el
*Make a copy at each savepoint of a file*

---

This is a fork and reviving of [`backup-each-save`](https://www.emacswiki.org/emacs/BackupEachSave).

Ever wish to go back to an older saved version of a file?  Then
this package is for you.  This package copies every file you save
in Emacs to a backup directory tree (which mirrors the tree
structure of the filesystem), with a timestamp suffix to make
multiple saves of the same file unique.  Never lose old saved
versions again.

To activate globally, place this file in your `load-path`, and add
the following lines to your init file:

    (require 'real-backup)
    (global-real-backup-mode 1)

To activate only for individual modes, add the require line as
above to your init.el and hook like this:

    (add-hook 'python-mode-hook 'real-backup-mode)


To filter out which files it backs up, use a custom function for
`real-backup-filter-function`.  For example, to filter out
the saving of GPG encypted files, do:

    (defun real-backup-no-gpg-files (filename)
      (not (equal (file-name-extension filename) "gpg")))
    (setq real-backup-filter-function #'real-backup-no-gpg-files)

### ChangeLog

- v1.1:  added `real-backup-filter-function`
- v1.2:
  - added real-backup-size-limit
  - fixed "Local Variables" docs, which was inadvertently being activated
- v1.3:  fix for some emacsen not having `file-remote-p`
- v1.4:  added footer and autoload
- v2.0:  refactor, deprecate old Emacs
- v2.1:
  - more features and tweaks
  - add `real-backup-cleanup` and `real-backup-auto-cleanup`
  - add `real-backup-open-backup`
- v3.0:  rebrand the package as `real-backup`
- v3.1:  add compression support
- v3.2:  add support for candidates preview
- v3.3:
  - jump to first changed position when switching between preview candidates
  - add optional split-window diff view when previewing candidates
- v3.4:
  - make `real-backup-open-backup` obsolete, use `real-backup-open` instead
  - better diffs
- v4.0:
  - make `real-backup-mode` local and add globalized mode
  - add `real-backup-global-excluded-modes`
  - update the documentation
- v4.1
  - add a separate file size limit for remote files
  - better cleanup with optional send to trash customization
  - reproducible window layout when previewing backups and diffs
  - better documentation
  - several bug fixes




### Customization Documentation

#### `real-backup-directory`

The root directory when to create backups.

#### `real-backup-remote-files`

Whether to backup remote files.

When non-nil, remote files will be saved locally.

#### `real-backup-filter-function`

Function which should return non-nil if the file should be backed up.

#### `real-backup-global-excluded-modes`

A list of modes to be excluded when enabling globally.

#### `real-backup-size-limit`

Maximum size of a file (in bytes) that should be copied at each savepoint.

If a file is greater than this size, don't make a backup of it.
Setting this variable to nil disables backup suppressions based
on size.

#### `real-backup-remote-size-limit`

Same as `real-backup-size-limit`, but for remote files.

Relevant when `real-backup-remote-files` is non-nil.

#### `real-backup-cleanup-keep`

Number of copies to keep for each file in `real-backup-cleanup`.

#### `real-backup-auto-cleanup`

Automatically cleanup after making a backup.

#### `real-backup-cleanup-to-trash`

Delete files to trash when cleaning up.

#### `real-backup-show-header`

Show a header when vienwing a backup file.

#### `real-backup-compression`

Compression extension to be used, set to nil to disable compression.

#### `real-backup-preview-jump-to-first-change`

When non-nil, jump to the first changed position when previewing a candidate.
The jump point is computed relative to the previously previewed candidate.

#### `real-backup-preview-show-diff`

When non-nil, show a diff window alongside the backup preview window.

#### `real-backup-preview-diff-against-current-file`

Controls what is compared in the diff window.
Only relevant when `real-backup-preview-show-diff` is non-nil.
When non-nil, the diff window shows changes between the saved file on disk
and the previewed candidate.
When nil (the default), the diff window shows changes between the
previously previewed candidate and the current one.

### Function and Macro Documentation

#### `(real-backup)`

Perform a backup of the current file if needed.

#### `(real-backup-compute-location FILENAME &optional UNIQUE)`

Compute backup location for FILENAME.
When UNIQUE is provided, add a unique timestamp after the file name.

#### `(real-backup-backups-of-file FILENAME)`

List of backups for FILENAME.

#### `(real-backup-cleanup FILENAME)`

Cleanup backups of FILENAME, keeping `real-backup-cleanup-keep` copies.

#### `(real-backup-open FILENAME)`

Open a backup of FILENAME or the current buffer.

-----
<div style="padding-top:15px;color: #d0d0d0;">
Markdown README file generated by
<a href="https://github.com/mgalgs/make-readme-markdown">make-readme-markdown.el</a>
</div>
