Go source for asyncomplete.vim via gocode
=========================================

Provide [Go](golang.org) autocompletion source for [asyncomplete.vim](https://github.com/prabirshrestha/asyncomplete.vim)
via [gocode](https://github.com/nsf/gocode)

### Installing

```vim
Plug 'prabirshrestha/asyncomplete.vim'
Plug 'prabirshrestha/asyncomplete-gocode.vim'
```

#### Registration

```vim
call asyncomplete#register_source(asyncomplete#sources#gocode#get_source_options({
    \ 'name': 'gocode',
    \ 'whitelist': ['go'],
    \ 'completor': function('asyncomplete#sources#gocode#completor'),
    \ 'config': {
    \    'gocode_path': expand('~/go/bin/gocode')
    \  },
    \ }))
```

Note: `config` is optional. `gocode_path` defaults to `gocode` i.e., `gocode` binary should exist in the `PATH` if config is not specified.

### Credits
* [https://github.com/nsf/gocode](https://github.com/nsf/gocode)
