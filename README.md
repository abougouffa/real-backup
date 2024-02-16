<img src="https://www.gnu.org/software/emacs/images/emacs.png" alt="Emacs Logo" width="80" height="80" align="right">
## real-backup.el
*Real Backup, make a copy at each savepoint of a file*

---

This is a fork and reviving of `backup-each-save`.

Ever wish to go back to an older saved version of a file?  Then
this package is for you.  This package copies every file you save
in Emacs to a backup directory tree (which mirrors the tree
structure of the filesystem), with a timestamp suffix to make
multiple saves of the same file unique.  Never lose old saved
versions again.

To activate globally, place this file in your `load-path`, and add
the following lines to your ~/.emacs file:

    (require 'real-backup)
    (add-hook 'after-save-hook 'real-backup)

To activate only for individual files, add the require line as
above to your ~/.emacs, and place a local variables entry at the
end of your file containing the statement:

    (add-hook (make-local-variable 'after-save-hook) 'real-backup)

NOTE:  I would give a full example of how to do this here, but it
would then try to activate it for this file since it is a short
file and the docs would then be within the "end of the file" local
variables region.  :)

To filter out which files it backs up, use a custom function for
`real-backup-filter-function`.  For example, to filter out
the saving of gnus .newsrc.eld files, do:

    (defun real-backup-no-newsrc-eld (filename)
      (cond
       ((string= (file-name-nondirectory filename) ".newsrc.eld") nil)
       (t t)))
    (setq real-backup-filter-function 'real-backup-no-newsrc-eld)

### ChangeLog

- v1.0 -> v1.1:  added `real-backup-filter-function`
- v1.1 -> v1.2:
  - added real-backup-size-limit
  - fixed "Local Variables" docs, which was inadvertently being activated
- v1.2 -> v1.3:  fix for some emacsen not having `file-remote-p`
- v1.3 -> v1.4:  added footer and autoload
- v1.4 -> v2.0:  refactor, deprecate old Emacs
- v2.0 -> v2.1:
  - more features and tweaks
  - add `real-backup-cleanup` and `real-backup-auto-cleanup`
  - add `real-backup-open-backup`
- v2.1 -> v3.0:  rebrand the package as `real-backup`
- v3.0 -> v3.1:  add compression support



### Customization Documentation

#### `real-backup-directory`

The root directory when to create backups.

#### `real-backup-remote-files`

Whether to backup remote files at each save.

Defaults to nil.

#### `real-backup-filter-function`

Function which should return non-nil if the file should be backed up.

#### `real-backup-size-limit`

Maximum size of a file (in bytes) that should be copied at each savepoint.

If a file is greater than this size, don't make a backup of it.
Setting this variable to nil disables backup suppressions based
on size.

#### `real-backup-cleanup-keep`

Number of copies to keep for each file in `real-backup-cleanup`.

#### `real-backup-auto-cleanup`

Automatically cleanup after making a backup.

#### `real-backup-compress`

Compress the backup files.

#### `real-backup-compression-program`

Compression program to be used when `real-backup-compress` is enabled.

#### `real-backup-compression-program-args`

Extra arguments to pass to `real-backup-compression-program`.

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

#### `(real-backup-open-backup FILENAME)`

Open a backup of FILENAME or the current buffer.

-----
<div style="padding-top:15px;color: #d0d0d0;">
Markdown README file generated by
<a href="https://github.com/mgalgs/make-readme-markdown">make-readme-markdown.el</a>
</div>
