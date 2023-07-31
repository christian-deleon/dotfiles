" General settings
set number              " Enable line numbers
set tabstop=2           " Number of spaces a tab counts for
set shiftwidth=2        " Number of spaces used for each step of auto-indent
set expandtab           " Use spaces instead of tabs
syntax on               " Enable syntax highlighting
filetype plugin indent on " Enable file type detection and plugins and indentation rules

" YAML specific settings
augroup yaml
    autocmd!
    autocmd FileType yaml setlocal ai ts=2 sw=2 et
augroup END
