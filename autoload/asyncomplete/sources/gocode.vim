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

    let l:info = { 'stdout_buffer': '', 'tmpfile': l:file, 'opt': a:opt, 'ctx': a:ctx }
    let l:jobid = s:exec(l:cmd, 1, function('s:on_exec_events', [l:info]))
    if l:jobid <= 0
    " gocode failed to start, so delete the file
        call s:delete_file(l:file)
    endif
endfunction

function! s:on_exec_events(info, id, data, event) abort
    " data is string
    let l:ctx = a:info['ctx']
    if a:event ==? 'stdout'
        let a:info['stdout_buffer'] = a:info['stdout_buffer'] . a:data
    elseif a:event ==? 'exit'
        if a:data == 0 && l:ctx == asyncomplete#context()
            let l:response = eval(a:info['stdout_buffer'])
            let l:matches = l:response[1]
            let l:startcol = l:ctx['col'] - l:response[0]
            unlet a:info['stdout_buffer']
            call asyncomplete#complete(a:info['opt']['name'], l:ctx, l:startcol, l:matches)
        endif
        call s:delete_file(a:info['tmpfile'])
    endif
endfunction

function! s:write_buffer_to_tempfile(ctx) abort
    let l:buf = getbufline(a:ctx['bufnr'], 1, '$')
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
    call asyncomplete#log('asyncomplete-gocode.vim', 'created tmp file', l:file)
    return l:file
endfunction

function! s:delete_file(file) abort
    call delete(a:file)
    call asyncomplete#log('asyncomplete-gocode.vim', 'deleted temp file ', a:file)
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

" vim8/neovim jobs wrapper {{{
function! s:exec(cmd, str, callback) abort
    call asyncomplete#log('asyncomplete-gocode.vim', 's:exec', a:cmd)
    if has('nvim')
        return jobstart(a:cmd, {
                \ 'on_stdout': function('s:on_nvim_job_event', [a:str, a:callback]),
                \ 'on_stderr': function('s:on_nvim_job_event', [a:str, a:callback]),
                \ 'on_exit': function('s:on_nvim_job_event', [a:str, a:callback]),
            \ })
    else
        let l:info = { 'close': 0, 'exit': 0, 'exit_code': -1 }
        let l:job = job_start(a:cmd, {
                \ 'out_cb': function('s:on_vim_job_event', [l:info, a:str, a:callback, 'stdout']),
                \ 'err_cb': function('s:on_vim_job_event', [l:info, a:str, a:callback, 'stderr']),
                \ 'exit_cb': function('s:on_vim_job_event', [l:info, a:str, a:callback, 'exit']),
                \ 'close_cb': function('s:on_vim_job_close_cb', [l:info, a:str, a:callback]),
            \ })
        let l:channel = job_getchannel(l:job)
        return ch_info(l:channel)['id']
    endif
endfunction

function! s:on_nvim_job_event(str, callback, id, data, event) abort
    if (a:event == 'exit')
        call asyncomplete#log('asyncomplete-gocode.vim', 'exit', a:data, a:id)
        call a:callback(a:id, a:data, a:event)
    elseif a:str
        " convert array to string since neovim uses array split by \n by default
        call a:callback(a:id, join(a:data, "\n"), a:event)
    else
        call a:callback(a:id, a:data, a:event)
    endif
endfunction

function! s:on_vim_job_event(info, str, callback, event, id, data) abort
    if a:event == 'exit'
        call asyncomplete#log('asyncomplete-gocode.vim', 'exit', a:data, a:info['close'])
        let a:info['exit'] = 1
        let a:info['exit_code'] = a:data
        let a:info['id'] = a:id
        if a:info['close'] && a:info['exit']
            " for more info refer to :h job-start
            " job may exit before we read the output and output may be lost.
            " in unix this happens because closing the write end of a pipe
            " causes the read end to get EOF.
            " close and exit has race condition, so wait for both to complete
            call a:callback(a:id, a:data, a:event)
        endif
    elseif a:str
        call a:callback(a:id, a:data, a:event)
    else
        " convert string to array since vim uses string by default
        call a:callback(a:id, split(a:data, "\n", 1), a:event)
    endif
endfunction

function! s:on_vim_job_close_cb(info, str, callback, channel) abort
    call asyncomplete#log('asyncomplete-gocode.vim', 'close_cb', a:info['exit'])
    let a:info['close'] = 1
    if a:info['close'] && a:info['exit']
        call a:callback(a:info['id'], a:info['exit_code'], 'exit')
    endif
endfunction
" }}}
