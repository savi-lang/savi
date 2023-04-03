# `savi-mode` for Emacs

This major mode provides the following features for Savi:
- Syntax highlighting
- `savi server` support via eglot
    - Hovers
    - Diagnostics
    - Formatting
    - etc.
- Indentation similar to other editors
- Hopefully many more in the future...

### Setup

This is not yet packaged on MELPA, but it could be in the future if there's enough interest.

For a quick setup, add this to your config file:

```lisp
(load-file "~/location/of/this/directory/savi-mode.el")
(savi-configure-server "~/path/to/savi")
```
This provides the default configuration and sets up hooks to start the language server.  Make sure you have eglot installed if your Emacs version is old enough.

If you would like more control, read "savi-mode.el".  It should be pretty easy to make it do what you want it to.
