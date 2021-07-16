# Savi support for coc.nvim

[![npm version](http://img.shields.io/npm/v/coc-savi.svg?style=flat)](https://npmjs.org/package/coc-savi "View this project on npm")

This extension adds various Intellisense features for the Savi Programming Language to the coc.nvim.

## Prerequisites

This extension doesn't provide savi language support to vim yet, so you need to install [savi-vim](https://github.com/teggotic/vim-savi)
This extension uses [Docker](https://docs.docker.com/install/) to run the Savi language server in the background, so you'll need to have a working installation of Docker and the ability to `docker run` as a non-root user.
