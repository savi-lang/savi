# Mare support for coc.nvim

[![npm version](http://img.shields.io/npm/v/coc-mare.svg?style=flat)](https://npmjs.org/package/coc-mare "View this project on npm")

This extension adds various Intellisense features for the Mare Programming Language to the coc.nvim.

## Prerequisites

This extension doesn't provide mare language support to vim yet, so you need to install [mare-vim](https://github.com/teggotic/vim-mare)
This extension uses [Docker](https://docs.docker.com/install/) to run the Mare language server in the background, so you'll need to have a working installation of Docker and the ability to `docker run` as a non-root user.
