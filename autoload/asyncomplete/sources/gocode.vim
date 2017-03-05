let s:current_ctx = {}
let s:current_opt = {}
let s:startcol = 0

let s:counter = 0
let s:counter_tempfiles = {}
let s:job_counter_mappings = {}

function! asyncomplete#sources#gocode#get_source_options(opts)
    return extend(extend({}, a:opts), {
            \ 'refresh_pattern': '\(\k\+$\|\.$\)',
            \ })
endfunction

function! asyncomplete#sources#gocode#completor(opt, ctx) abort
    let l:matches = []

    let l:col = a:ctx['col']
    let l:typed = a:ctx['typed']

    let l:kw = matchstr(l:typed, '\v\S+$')
    let l:kwlen = len(l:kw)

    let s:counter += 1
    let l:file = s:write_buffer_to_tempfile(a:ctx, s:counter)

    let l:config = get(a:opt, 'config', {})
    let l:gocode_path = get(l:config, 'gocode_path', 'gocode')
    let l:cmd = [l:gocode_path, '-f=vim', '--in='.l:file, 'autocomplete', expand('%:p'), s:gocodeCursor()]

    let s:current_ctx = a:ctx
    let s:current_opt = a:opt
    let s:startcol = l:col
    let l:jobid = async#job#start(l:cmd, {
        \ 'on_stdout': function('s:handler'),
        \ 'on_exit': function('s:handler'),
        \ })

    if l:jobid > 0
        " job started
        let s:counter_tempfiles[l:jobid] = s:counter
    else
        " gocode failed to start
        call s:delete_tempfile(s:counter)
    endif
endfunction

let s:buffer_stdout = {}
function! s:handler(id, data, event) abort
    if a:event == 'stdout'
        if !has_key(s:buffer_stdout, a:id)
            let s:buffer_stdout[a:id] = ''
        endif
        let s:buffer_stdout[a:id] = s:buffer_stdout[a:id] . join(a:data, "\n")
    elseif a:event == 'exit'
        if a:data == 0 && s:current_ctx == asyncomplete#context()
            let l:response = eval(s:buffer_stdout[a:id])
            let l:matches = l:response[1]
            let l:startcol = s:startcol - l:response[0]
            unlet s:buffer_stdout[a:id]
            call asyncomplete#complete(s:current_opt['name'], s:current_ctx, l:startcol, l:matches)
        endif
        if has_key(s:job_counter_mappings, a:id)
            call s:delete_tempfile(s:job_counter_mappings[a:id])
        endif
    endif
endfunction

function! s:write_buffer_to_tempfile(ctx, counter) abort
    let l:buf = getline(1, '$')
    if &encoding != 'utf-8'
        let l:buf = map(l:buf, 'iconv(v:val, &encoding, "utf-8")')
    endif

    if &l:fileformat == 'dos'
        " line2byte() depend on 'fileformat' option.
        " so if fileformat is 'dos', 'buf' must include '\r'.
        let l:buf = map(l:buf, 'v:val."\r"')
    endif

    let l:file = tempname()
    let s:counter_tempfiles[a:counter] = l:file
    call writefile(l:buf, l:file)
    return l:file
endfunction

function! s:delete_tempfile(counter) abort
    if has_key(s:counter_tempfiles, a:counter)
        call deletefile(s:counter_tempfiles[a:counter])
        unlet s:counter_tempfiles[a:counter]
    endif
endfunction

function! s:gocodeCursor() abort
    if &encoding != 'utf-8'
        let c = col('.')
        let buf = line('.') == 1 ? "" : (join(getline(1, line('.')-1), "\n") . "\n")
        let buf .= c == 1 ? "" : getline('.')[:c-2]
        return printf('%d', len(iconv(buf, &encoding, "utf-8")))
    endif
    return printf('%d', line2byte(line('.')) + (col('.')-2))
endf
