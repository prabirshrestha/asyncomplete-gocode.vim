function! asyncomplete#sources#gocode#get_source_options(opts)
    return extend(extend({}, a:opts), {
            \ 'refresh_pattern': '\(\k\+$\|\.$\)',
            \ })
endfunction

function! asyncomplete#sources#gocode#completor(opt, ctx) abort
    let l:file = s:write_buffer_to_tempfile(a:ctx)

    let l:config = get(a:opt, 'config', {})
    let l:gocode_path = get(l:config, 'gocode_path', 'gocode')
    let l:cmd = [l:gocode_path, '-f=vim', '--in='.l:file, 'autocomplete', expand('%:p'), s:gocode_cursor()]

    let l:params = { 'stdout_buffer': '', 'file': l:file }
    let l:jobid = async#job#start(l:cmd, {
        \ 'on_stdout': function('s:handler', [a:opt, a:ctx, l:params]),
        \ 'on_exit': function('s:handler', [a:opt, a:ctx, l:params]),
        \ })

    if l:jobid <= 0
        " gocode failed to start so delete the file
        call delete(l:file)
    endif
endfunction

function! s:handler(opt, ctx, params, id, data, event) abort
    if a:event ==? 'stdout'
        let a:params['stdout_buffer'] = a:params['stdout_buffer'] . join(a:data, "\n")
    elseif a:event ==? 'exit'
        if a:data == 0 && a:ctx == asyncomplete#context()
            let l:response = eval(a:params['stdout_buffer'])
            let l:matches = l:response[1]
            let l:startcol = a:ctx['col'] - l:response[0]
            unlet a:params['stdout_buffer']
            call asyncomplete#complete(a:opt['name'], a:ctx, l:startcol, l:matches)
        endif
        call delete(a:params['file'])
    endif
endfunction

function! s:write_buffer_to_tempfile(ctx) abort
    let l:buf = getline(a:ctx['bufnr'], '$')
    if &encoding !=? 'utf-8'
        let l:buf = map(l:buf, 'iconv(v:val, &encoding, "utf-8")')
    endif

    if &l:fileformat ==? 'dos'
        " line2byte() depend on 'fileformat' option.
        " so if fileformat is 'dos', 'buf' must include '\r'.
        let l:buf = map(l:buf, 'v:val."\r"')
    endif

    let l:file = tempname()
    call writefile(l:buf, l:file)
    return l:file
endfunction

function! s:gocode_cursor() abort
    if &encoding !=? 'utf-8'
        let l:c = col('.')
        let l:buf = line('.') == 1 ? '' : (join(getline(1, line('.')-1), "\n") . "\n")
        let l:buf .= l:c == 1 ? '' : getline('.')[:l:c-2]
        return printf('%d', len(iconv(l:buf, &encoding, 'utf-8')))
    endif
    return printf('%d', line2byte(line('.')) + (col('.')-2))
endfunction
