;;; savi-mode.el --- Major mode for Savi  -*- lexical-binding: t; -*-

(defvar savi-server-executable-path ""
  "A string with a path to the executable you want to use for all things language server - related.  Gets set in `savi-configure-server'")

(defvar savi-indentation-size 2
  "If you want to configure this, it's a good idea to set it before calling `savi-configure-server'.")

;; Unfortunately, this is the best we can do for syntax highlighting right now.
;; The author attempted to make a tree-sitter grammar, but failed because the
;; meaning of some parts of Savi's syntax are not known at parse-time.  This
;; makes it extremely difficult to create a tree that is meaningful to tree-
;; sitter.  Overall, the syntax highlighting wouldn't be much better than
;; what this does, though.
(defconst savi-font-lock-defaults
  '(
    ;; Heredocs:
    ("<<<.*?>>>" . (1 'font-lock-string-face))

    ;; Keywords:
	(":[a-z_]+" . 'font-lock-keyword-face)
	
	;; Capabilities when used after a type (e.g. `String'iso`):
    ("\\('\\(iso\\|val\\|ref\\|box\\|tag\\|trn\\|non\\)\\)" . (1 'font-lock-constant-face))
	
    ;; Characters (absolutely hilarious):
    ("\\('\\(\\\\'\\|\\\\\"\\|\\\\\\\\\\|\\\\b\\|\\\\f\\|\\\\n\\|\\\\r\\|\\\\t\\|\\b\\|\\f\\|\\n\\|\\r\\|\\t\\|\\\\x[0-9a-fA-F][0-9a-fA-F]\\|\\\\u[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]\\|\\\\U[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]\\|[^'\\\\]\\)'\\)" . (1 'font-lock-string-face))

	;; Capabilities when used without a type (e.g. `myVar iso = 42`):
    ("\\(?:^\\| \\|\\t\\|\\n\\|\\r\\|\\r\\n\\)\\(iso\\|val\\|ref\\|box\\|tag\\|trn\\|non\\)\\( \\|\\t\\|\\n\\|\\r\\|\\r\\n\\|$\\)" . (1 'font-lock-constant-face))
	
	;; Any function/type with an error:
	("\\(@?_?\\<[a-zA-Z0-9_]+?!\\)" . (1 'font-lock-warning-face))
	
	;; Known function names (doesn't capture all of them, but does a pretty good job):
	("\\(@?_?\\<[a-z][a-zA-Z0-9_]*\\)(" . (1 'font-lock-function-name-face))

    ;; Other identifier names:
    ("\\(@?_?\\<[a-z][a-zA-Z0-9_]*\\)" . (1 'font-lock-variable-name-face))
	
    ;; Types:
    ("\\([A-Z][a-zA-Z0-9_]*\\)" . (1 'font-lock-type-face))
   ))

(defconst savi-mode-syntax-table
  (let ((table (make-syntax-table)))
	;; Strings
	(modify-syntax-entry ?\" "\"" table)

	;; Parentheses
	(modify-syntax-entry ?\( "()" table)
	(modify-syntax-entry ?\) ")(" table)
	(modify-syntax-entry ?\[ "(]" table)
	(modify-syntax-entry ?\] ")[" table)

	;; Comments
	(modify-syntax-entry ?/ ". 12" table)
	(modify-syntax-entry ?: ". 12" table)
	(modify-syntax-entry ?\n ">" table)
	table))



(defun savi-configure-server (executable-path)
  "The quick way to set up this extension.  Takes a string with a path to the Savi executable you would like to use for the language server.  It uses eglot, so be sure that you have it installed if your Emacs version is old enough; modern versions have it by default.  It sets up a hook that runs the language server and sets the correct indentation behavior when you open a .savi file.  If you would like more control over your configuration, don't use this function; do it manually!"
  (add-to-list 'eglot-server-programs
			   `(savi-mode . (,executable-path "s")))
  (add-hook 'savi-mode-hook 'eglot-ensure)
  (add-hook 'savi-mode-hook (lambda ()
							  (setq-local indent-tabs-mode nil)
							  (setq-local tab-width savi-indentation-size)))
)



;;;###autoload
(define-derived-mode savi-mode prog-mode "savi"
  "Major mode for the Savi language."
  (setq font-lock-defaults '(savi-font-lock-defaults))
  (setq-local comment-start "[ \t]*\\(//\\|\\:\\:\\)")
  )

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.savi" . savi-mode))
