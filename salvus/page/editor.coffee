##################################################
# Editor for files in a project
##################################################

async = require('async')

message = require('message')

{salvus_client} = require('salvus_client')
{EventEmitter}  = require('events')
{alert_message} = require('alerts')

misc = require('misc')
# TODO: undo doing the import below -- just use misc.[stuff] is more readable.
{copy, trunc, from_json, to_json, keys, defaults, required, filename_extension, len, path_split, uuid} = require('misc')

top_navbar =  $(".salvus-top_navbar")

codemirror_associations =
    c      : 'text/x-c'
    'c++'  : 'text/x-c++src'
    cpp    : 'text/x-c++src'
    cc     : 'text/x-c++src'
    csharp : 'text/x-csharp'
    'c#'   : 'text/x-csharp'
    java   : 'text/x-java'
    coffee : 'coffeescript'
    php    : 'php'
    py     : 'python'
    pyx    : 'python'
    css    : 'css'
    diff   : 'diff'
    ecl    : 'ecl'
    h      : 'text/x-c++hdr'
    html   : 'htmlmixed'
    js     : 'javascript'
    lua    : 'lua'
    md     : 'markdown'
    r      : 'r'
    rst    : 'rst'
    sage   : 'python'
    scala  : 'text/x-scala'
    sh     : 'shell'
    spyx   : 'python'
    sql    : 'mysql'
    txt    : 'text'
    tex    : 'stex'
    xml    : 'xml'
    yaml   : 'yaml'
    ''     : 'text'

file_associations = exports.file_associations = {}
for ext, mode of codemirror_associations
    file_associations[ext] =
        editor : 'codemirror'
        opts   : {mode:mode}

file_associations['tex'] =
    editor : 'latex'
    icon   : 'icon-edit'
    opts   : {mode:'stex', indent_unit:4, tab_size:4}

file_associations['html'] =
    editor : 'codemirror'
    icon   : 'icon-edit'
    opts   : {mode:'htmlmixed', indent_unit:4, tab_size:4}

file_associations['css'] =
    editor : 'codemirror'
    icon   : 'icon-edit'
    opts   : {mode:'css', indent_unit:4, tab_size:4}

file_associations['salvus-terminal'] =
    editor : 'terminal'
    icon   : 'icon-credit-card'
    opts   : {}

file_associations['salvus-worksheet'] =
    editor : 'worksheet'
    icon   : 'icon-list-ul'
    opts   : {}

file_associations['salvus-spreadsheet'] =
    editor : 'spreadsheet'
    opts   : {}

file_associations['salvus-slideshow'] =
    editor : 'slideshow'
    opts   : {}

for ext in ['png', 'jpg', 'gif', 'svg']
    file_associations[ext] =
        editor : 'image'
        opts   : {}

file_associations['pdf'] =
    editor : 'pdf'
    opts   : {}

# Given a text file (defined by content), try to guess
# what the extension should be.
guess_file_extension_type = (content) ->
    content = $.trim(content)
    i = content.indexOf('\n')
    first_line = content.slice(0,i).toLowerCase()
    if first_line.slice(0,2) == '#!'
        # A script.  What kind?
        if first_line.indexOf('python') != -1
            return 'py'
        if first_line.indexOf('bash') != -1 or first_line.indexOf('sh') != -1
            return 'sh'
    if first_line.indexOf('html') != -1
        return 'html'
    if first_line.indexOf('/*') != -1 or first_line.indexOf('//') != -1   # kind of a stretch
        return 'c++'
    return undefined


_local_storage_key = (project_id, filename, key) ->
    return project_id + filename + "\uFE10" + key

local_storage = exports.local_storage = (project_id, filename, key, value) ->
    storage = window.localStorage
    if storage?
        if value?
            storage[_local_storage_key(project_id, filename, key)] = misc.to_json(value)
        else
            x = storage[_local_storage_key(project_id, filename, key)]
            if not x?
                return x
            else
                return misc.from_json(x)

templates = $("#salvus-editor-templates")

class exports.Editor
    constructor: (opts) ->
        opts = defaults opts,
            project_id    : required
            initial_files : undefined # if given, attempt to open these files on creation
            counter       : undefined # if given, is a jQuery set of DOM objs to set to the number of open files

        @counter = opts.counter

        @project_id = opts.project_id
        @element = templates.find(".salvus-editor").clone().show()
        @nav_tabs = @element.find(".nav-pills")

        @tabs = {}   # filename:{useful stuff}

        if opts.initial_files?
            for filename in opts.initial_files
                @open(filename)

        that = @
        # Enable the save/close/commit buttons
        @element.find("a[href=#save]").addClass('disabled').click () ->
            if not $(@).hasClass("disabled")
                that.save(that.active_tab.filename)
            return false

        @element.find("a[href=#close]").addClass('disabled').click () ->
            if not $(@).hasClass("disabled")
                that.close(that.active_tab.filename)
            return false

        @element.find("a[href=#reload]").addClass('disabled').click () ->
            if not $(@).hasClass("disabled")
                that.reload(that.active_tab.filename)
            return false

        @element.find("a[href=#commit]").addClass('disabled').click () ->
            if not $(@).hasClass("disabled")
                filename = that.active_tab.filename
                that.commit(filename, "save #{filename}")
            return false

    update_counter: () =>
        if @counter?
            @counter.text(len(@tabs))

    open: (filename) =>
        if not @tabs[filename]?   # if it is defined, then nothing to do -- file already loaded
            @tabs[filename] = @create_tab(filename:filename)

    create_tab: (opts) =>
        opts = defaults opts,
            filename     : required
            content      : undefined
            session_uuid : undefined

        filename = opts.filename
        ext = filename_extension(opts.filename)
        if not ext? and opts.content?   # no recognized extension
            ext = guess_file_extension_type(content)
        x = file_associations[ext]
        if not x?
            x = file_associations['']
        extra_opts = copy(x.opts)
        if opts.session_uuid?
            extra_opts.session_uuid = opts.session_uuid
        content = opts.content

        switch x.editor
            # codemirror is the default... TODO: JSON, since I have that jsoneditor plugin.
            when 'codemirror', undefined
                editor = new CodeMirrorSessionEditor(@, filename, "", extra_opts)
                editor.init_autosave()
                #editor = new CodeMirrorEditor(@, filename, content, extra_opts)
            when 'terminal'
                editor = new Terminal(@, filename, content, extra_opts)
            when 'worksheet'
                editor = new Worksheet(@, filename, content, extra_opts)
            when 'spreadsheet'
                editor = new Spreadsheet(@, filename, content, extra_opts)
            when 'slideshow'
                editor = new Slideshow(@, filename, content, extra_opts)
            when 'image'
                editor = new Image(@, filename, content, extra_opts)
            when 'latex'
                editor = new LatexEditor(@, filename, content, extra_opts)
            when 'pdf'
                editor = new PDF_Preview(@, filename, content, extra_opts)
            else
                throw("Unknown editor type '#{x.editor}'")


        link = templates.find(".super-menu").clone().show()
        link_filename = link.find(".salvus-editor-tab-filename")
        link_filename.text(filename) #trunc(filename,15))
        link.find(".salvus-editor-close-button-x").click () =>
            @close(link_filename.text())
        link.find("a").click () => @display_tab(link_filename.text())
        @nav_tabs.append(link)
        @tabs[filename] =
            link     : link
            editor   : editor
            filename : filename

        #@display_tab(filename)
        #setTimeout(editor.focus, 250)

        @element.find(".salvus-editor-content").append(editor.element.hide())
        @update_counter()
        return @tabs[filename]


    # Close this tab.
    close: (filename) =>
        tab = @tabs[filename]
        if not tab? # nothing to do -- tab isn't opened anymore
            return

        # Disconnect from remote session (if relevant)
        tab.editor.disconnect_from_session()
        tab.link.remove()
        tab.editor.remove()
        delete @tabs[filename]
        @update_counter()

        names = keys(@tabs)
        if names.length > 0
            # select new tab
            @display_tab(names[0])

    # Reload content of this tab.  Warn user if this will result in changes.
    reload: (filename) =>
        tab = @tabs[filename]
        if not tab? # nothing to do
            return
        salvus_client.read_text_file_from_project
            project_id : @project_id
            timeout    : 5
            path       : filename
            cb         : (err, mesg) =>
                if err
                    alert_message(type:"error", message:"Communications issue loading new version of #{filename} -- #{err}")
                else if mesg.event == 'error'
                    alert_message(type:"error", message:"Error loading new version of #{filename} -- #{to_json(mesg.error)}")
                else
                    current_content = tab.editor.val()
                    new_content = mesg.content
                    if current_content != new_content
                        @warn_user filename, (proceed) =>
                            if proceed
                                tab.editor.val(new_content)

    # Warn user about unsaved changes (modal)
    warn_user: (filename, cb) =>
        cb(true)

    # Make the give tab active.
    display_tab: (filename) =>
        if not @tabs[filename]?
            return
        for name, tab of @tabs
            if name == filename
                @active_tab = tab
                tab.link.addClass("active")
                tab.editor.show()
                setTimeout(tab.editor.focus, 100)
                @element.find(".btn-group").children().removeClass('disabled')
            else
                tab.link.removeClass("active")
                tab.editor.hide()

    onshow: () =>  # should be called when the editor is shown.
        @active_tab?.editor.show()

    # Save the file to disk/repo
    save: (filename, cb) =>       # cb(err)
        if not filename?  # if filename not given, save all files
            tasks = []
            for filename in keys(@tabs)
                f = (c) =>
                    @save(arguments.callee.filename, c)
                f.filename = filename
                tasks.push(f)
            async.parallel(tasks, cb)
            return

        tab = @tabs[filename]
        if not tab?
            cb?()
            return

        if not tab.editor.has_unsaved_changes()
            # nothing to save
            cb?()
            return

        tab.editor.save(cb)

    change_tab_filename: (old_filename, new_filename) =>
        tab = @tabs[old_filename]
        if not tab?
            # TODO -- fail silently or this?
            alert_message(type:"error", message:"change_tab_filename (bug): attempt to change #{old_filename} to #{new_filename}, but there is no tab #{old_filename}")
            return
        tab.filename = new_filename
        tab.link.find(".salvus-editor-tab-filename").text(new_filename)
        delete @tabs[old_filename]
        @tabs[new_filename] = tab


###############################################
# Abstract base class for editors
###############################################
# Derived classes must:
#    (1) implement the _get and _set methods
#    (2) show/hide/remove
#
# Events ensure that *all* users editor the same file see the same
# thing (synchronized).
#

class FileEditor extends EventEmitter
    constructor: (@editor, @filename, content, opts) ->
        @val(content)

    init_autosave: () =>
        if @_autosave_interval?
            # This function can safely be called again to *adjust* the
            # autosave interval, in case user changes the settings.
            clearInterval(@_autosave_interval)

        # Use the most recent autosave value.
        autosave = require('account').account_settings.settings.autosave
        if autosave
            save_if_changed = () =>
                if not @editor.tabs[@filename]?
                    # don't autosave anymore if the doc is closed
                    clearInterval(@_autosave_interval)
                    return
                if @has_unsaved_changes()
                    if @click_save_button?
                        # nice gui feedback
                        @click_save_button()
                    else
                        @save()
            @_autosave_interval = setInterval(save_if_changed, autosave * 1000)

    val: (content) =>
        if not content?
            # If content not defined, returns current value.
            return @_get()
        else
            # If content is defined, sets value.
            @_set(content)

    # has_unsaved_changes() returns the state, where true means that
    # there are unsaved changed.  To set the state, do
    # has_unsaved_changes(true or false).
    has_unsaved_changes: (val) =>
        if not val?
            return @_has_unsaved_changes
        else
            @_has_unsaved_changes = val

    focus: () => # TODO in derived class

    _get: () =>
        throw("TODO: implement _get in derived class")

    _set: (content) =>
        throw("TODO: implement _set in derived class")

    restore_cursor_position : () =>
        # implement in a derived class if you need this

    disconnect_from_session : (cb) =>
        # implement in a derived class if you need this

    local_storage: (key, value) =>
        return local_storage(@editor.project_id, @filename, key, value)

    show: () =>
        @element.show()

    hide: () =>
        @element.hide()

    remove: () =>
        @element.remove()

    terminate_session: () =>
        # If some backend session on a remote machine is serving this session, terminate it.

    save: (cb) =>
        content = @val()
        if not content?
            # do not overwrite file in case editor isn't initialized
            alert_message(type:"error", message:"Editor of '#{filename}' not initialized, so nothing to save.")
            cb?()
            return

        salvus_client.write_text_file_to_project
            project_id : @editor.project_id
            timeout    : 10
            path       : @filename
            content    : content
            cb         : (err, mesg) =>
                # TODO -- on error, we *might* consider saving to localStorage...
                if err
                    alert_message(type:"error", message:"Communications issue saving #{filename} -- #{err}")
                    cb?(err)
                else if mesg.event == 'error'
                    alert_message(type:"error", message:"Error saving #{filename} -- #{to_json(mesg.error)}")
                    cb?(mesg.error)
                else
                    cb?()

###############################################
# Codemirror-based File Editor
###############################################
class CodeMirrorEditor extends FileEditor
    constructor: (@editor, @filename, content, opts) ->
        opts = @opts = defaults opts,
            mode              : required
            delete_trailing_whitespace : true   # delete all trailing whitespace on save
            line_numbers      : true
            indent_unit       : 4
            tab_size          : 4
            smart_indent      : true
            electric_chars    : true
            undo_depth        : 1000
            match_brackets    : true
            line_wrapping     : true
            theme             : "solarized"  # see static/codemirror*/themes or head.html
            # I'm making the times below very small for now.  If we have to adjust these to reduce load, due to lack
            # of capacity, then we will.  Or, due to lack of optimization (e.g., for big documents). These parameters
            # below would break editing a huge file right now, due to slowness of applying a patch to a codemirror editor.
            cursor_interval   : 150   # minimum time (in ms) between sending cursor position info to hub -- used in sync version
            sync_interval     : 150   # minimum time (in ms) between synchronizing text with hub. -- used in sync version below

        @element = templates.find(".salvus-editor-codemirror").clone()
        elt = @element.find(".salvus-editor-codemirror-input-box").find("textarea")
        elt.text(content)
        @codemirror = CodeMirror.fromTextArea elt[0],
            firstLineNumber : 1
            autofocus       : false
            mode            : opts.mode
            lineNumbers     : opts.line_numbers
            indentUnit      : opts.indent_unit
            tabSize         : opts.tab_size
            smartIndent     : opts.smart_indent
            electricChars   : opts.electric_chars
            undoDepth       : opts.undo_depth
            matchBrackets   : opts.match_brackets
            theme           : opts.theme
            lineWrapping    : opts.line_wrapping
            extraKeys       :
                "Shift-Enter"  : (editor)   => @click_save_button()
                "Ctrl-S"       : (editor)   => @click_save_button()
                "Cmd-S"        : (editor)   => @click_save_button()
                "Shift-Tab"    : (editor)   => editor.unindent_selection()
                "Ctrl-Space"  : "indentAuto"
                "Tab"          : (editor)   =>
                    c = editor.getCursor(); d = editor.getCursor(true)
                    if c.line==d.line and c.ch == d.ch
                        editor.tab_as_space()
                    else
                        CodeMirror.commands.defaultTab(editor)

        @init_save_button()
        @init_change_event()
        @init_chat_toggle()

    init_chat_toggle: () =>
        title = @element.find(".salvus-editor-chat-title")
        title.click () =>
            if @_chat_is_hidden? and @_chat_is_hidden
                @show_chat_window()
            else
                @hide_chat_window()
        @hide_chat_window()  #start hidden for now, until we have a way to save this.

    show_chat_window: () =>
        # SHOW the chat window
        @_chat_is_hidden = false
        @element.find(".salvus-editor-chat-show").hide()
        @element.find(".salvus-editor-chat-hide").show()
        @element.find(".salvus-editor-codemirror-input-box").removeClass('span12').addClass('span9')
        @element.find(".salvus-editor-codemirror-chat-column").show()
        @new_chat_indicator(false)

    hide_chat_window: () =>
        # HIDE the chat window
        @_chat_is_hidden = true
        @element.find(".salvus-editor-chat-hide").hide()
        @element.find(".salvus-editor-chat-show").show()
        @element.find(".salvus-editor-codemirror-input-box").removeClass('span9').addClass('span12')
        @element.find(".salvus-editor-codemirror-chat-column").hide()

    new_chat_indicator: (new_chats) =>
        # Show a new chat indicator of the chat window is closed.
        # if new_chats, indicate that there are new chats
        # if new_chats, don't indicate new chats.
        elt = @element.find(".salvus-editor-chat-new-chats")
        if new_chats and @_chat_is_hidden
            elt.show()
        else
            elt.hide()

    init_save_button: () =>
        @save_button = @element.find("a[href=#save]").click(@click_save_button)
        @save_button.find(".spinner").hide()

    click_save_button: () =>
        if not @save_button.hasClass('disabled')
            @save_button.find('span').text("Saving...")
            spin = setTimeout((() => @save_button.find(".spinner").show()), 100)
            @editor.save @filename, (err) =>
                clearTimeout(spin)
                @save_button.find(".spinner").hide()
                @save_button.find('span').text('Save')
                if not err
                    @save_button.addClass('disabled')
                    @has_unsaved_changes(false)
        return false

    init_change_event: () =>
        @codemirror.on 'change', (instance, changeObj) =>
            @has_unsaved_changes(true)
            @save_button.removeClass('disabled')

    _get: () =>
        return @codemirror.getValue()

    _set: (content) =>
        {from} = @codemirror.getViewport()
        @codemirror.setValue(content)
        @codemirror.scrollIntoView(from)

    show: () =>
        if not (@element? and @codemirror?)
            console.log('skipping show because things not defined yet.')
            return
        height = $(window).height() - 2.5*top_navbar.height() #todo

        @element.height(height+5).show()

        scroller = $(@codemirror.getScrollerElement())
        scroller.css('height':height-25)  #todo

        window.scrollTo(0, document.body.scrollHeight); $(".salvus-top-scroll").show()

        @codemirror.refresh()

        chat = @element.find(".salvus-editor-codemirror-chat")
        chat.height(height-25)  #todo
        output = chat.find(".salvus-editor-codemirror-chat-output")
        output.scrollTop(output[0].scrollHeight)

        @restore_cursor_position()

    focus: () =>
        if not @codemirror?
            return

        width = @element.width(); height = @element.height()
        $(@codemirror.getWrapperElement()).css
            'max-height' : height
            'max-width'  : width

        @codemirror.focus()
        @codemirror.refresh()

##############################################################################
# CodeMirrorSession Editor
#
# A map
#
#     [client]s.. ---> [hub] ---> [local hub] <--- [hub] <--- [client] <--- YOU ARE HERE
#                                   |
#                                  \|/
#                              [a file on disk]
##############################################################################

diffsync = require('diffsync')

class CodeMirrorDiffSyncDoc
    # Define exactly one of cm or string.
    #     cm     = a live codemirror editor
    #     string = a string
    constructor: (opts) ->
        @opts = defaults opts,
            cm     : undefined
            string : undefined
        if not ((opts.cm? and not opts.string?) or (opts.string? and not opts.cm?))
            console.log("BUG -- exactly one of opts.cm and opts.string must be defined!")

    copy: () =>
        # always degrades to a string
        if @opts.cm?
            return new CodeMirrorDiffSyncDoc(string:@opts.cm.getValue())
        else
            return new CodeMirrorDiffSyncDoc(string:@opts.string)

    string: () =>
        if @opts.string?
            return @opts.string
        else
            return @opts.cm.getValue()

    diff: (v1) =>
        # TODO: when either is a codemirror object, can use knowledge of where/if
        # there were edits as an optimization
        return diffsync.dmp.patch_make(@string(), v1.string())

    patch: (p) =>
        return new CodeMirrorDiffSyncDoc(string: diffsync.dmp.patch_apply(p, @string())[0])

    checksum: () =>
        return @string().length

    patch_in_place: (p) =>
        if @opts.string
            console.log("patching string in place")  # should never need to happen
            @opts.string = diffsync.dmp.patch_apply(p, @string())[0]
        else
            cm = @opts.cm

            # We maintain our cursor position using the following trick:
            #    1. Insert a non-used unicode character where the cursor is.
            #    2. Apply the patches.
            #    3. Find the unicode character,, remove it, and put the cursor there.
            #       If the unicode character vanished, just put the cursor at the coordinates
            #       where it used to be (better than nothing).
            # There is a more sophisticated approach described at http://neil.fraser.name/writing/cursor/
            # but it is harder to implement given that we'll have to dive into the details of his
            # patch_apply implementation.  This thing below took only a few minutes to implement.
            scroll = cm.getScrollInfo()
            pos0 = cm.getCursor()
            cursor = "\uFE10"   # chosen from http://billposer.org/Linguistics/Computation/UnicodeRanges.html
                                # since it is (1) undefined, and (2) looks like a cursor..
            cm.replaceRange(cursor, pos0)
            t = misc.walltime()
            s = @string()
            #console.log(1, misc.walltime(t)); t = misc.walltime()
            new_value = diffsync.dmp.patch_apply(p, s)[0]
            #console.log(2, misc.walltime(t)); t = misc.walltime()
            v = new_value.split('\n')
            #console.log(3, misc.walltime(t)); t = misc.walltime()
            line = pos0.line
            line1 = undefined
            # We first try an interval around the cursor, since that is where the cursor is most likely to be.
            for k in [Math.max(0, line-10)...Math.max(0,Math.min(line-10, v.length))].concat([0...v.length])
                ch = v[k].indexOf(cursor)
                if ch != -1
                    line1 = k
                    break

            if line1?
                v[line1] = v[line1].slice(0,ch) + v[line1].slice(ch+1)
                pos = {line:line1, ch:ch}
                console.log("Found cursor again at ", pos)
            else
                pos = pos0
                console.log("LOST CURSOR!")
            #console.log(4, misc.walltime(t)); t = misc.walltime()
            s = v.join('\n')
            #console.log(5, misc.walltime(t)); t = misc.walltime()
            # Benchmarking reveals that this line 'cm.setValue(s)' is by far the dominant time taker.
            # This can be optimized by taking into account the patch itself (and maybe stuff returned
            # when applying it) to instead only change a small range of the editor.  This is TODO
            # for later though.  For reference, a 200,000 line doc on a Samsung chromebook takes < 1s still, and about .4 s
            # on a fast intel laptop.
            cm.setValue(s)
            #console.log(6, misc.walltime(t)); t = misc.walltime()
            cm.setCursor(pos)
            cm.scrollTo(scroll.left, scroll.top)
            cm.scrollIntoView(pos)  # just in case

codemirror_setValue_less_moving = (cm, value) ->
    scroll = cm.getScrollInfo()
    pos = cm.getCursor()
    cm.setValue(value)
    cm.setCursor(pos)
    cm.scrollTo(scroll.left, scroll.top)
    cm.scrollIntoView(pos)


codemirror_diffsync_client = (cm_session, content) ->
    # This happens on initialization and reconnect.  On reconnect, we could be more
    # clever regarding restoring the cursor and the scroll location.
    codemirror_setValue_less_moving(cm_session.codemirror, content)

    return new diffsync.CustomDiffSync
        doc            : new CodeMirrorDiffSyncDoc(cm:cm_session.codemirror)
        copy           : (s) -> s.copy()
        diff           : (v0,v1) -> v0.diff(v1)
        patch          : (d, v0) -> v0.patch(d)
        checksum       : (s) -> s.checksum()
        patch_in_place : (p, v0) -> v0.patch_in_place(p)

# The CodeMirrorDiffSyncHub class represents a global hub viewed as a
# remote server for this client.
class CodeMirrorDiffSyncHub
    constructor: (@cm_session) ->

    connect: (remote) =>
        @remote = remote

    recv_edits: (edit_stack, last_version_ack, cb) =>
        @cm_session.call
            message : message.codemirror_diffsync(edit_stack:edit_stack, last_version_ack:last_version_ack)
            timeout : 30
            cb      : (err, mesg) =>
                if err
                    cb(err)
                else if mesg.event == 'error'
                    cb(mesg.error)
                else if mesg.event == 'codemirror_diffsync_retry_later'
                    cb('retry')
                else
                    @remote.recv_edits(mesg.edit_stack, mesg.last_version_ack, cb)



class CodeMirrorSessionEditor extends CodeMirrorEditor
    constructor: (@editor, @filename, ignored, opts) ->
        if opts.session_uuid
            @session_uuid = opts.session_uuid
            delete opts.session_uuid

        super(@editor, @filename, "Loading '#{@filename}'...", opts)

        @init_cursorActivity_event()

        @init_chat()

        # by default we will auto-reopen a file unless we explicitly close it.
        @local_storage('auto_open', true)

        @connect (err,resp) =>
            if err
                @_set(err)
                alert_message(type:"error", message:err)
            else
                @init_autosave()
                @codemirror.on 'change', (instance, changeObj) =>
                    if changeObj.origin? and changeObj.origin != 'setValue'
                        @sync_soon()

    _add_listeners: () =>
        salvus_client.on 'codemirror_diffsync_ready', @_diffsync_ready
        salvus_client.on 'codemirror_bcast', @_receive_broadcast

    _remove_listeners: () =>
        salvus_client.removeListener 'codemirror_diffsync_ready', @_diffsync_ready
        salvus_client.removeListener 'codemirror_bcast', @_receive_broadcast

    disconnect_from_session: (cb) =>
        @_remove_listeners()
        salvus_client.call
            timeout : 10
            message : message.codemirror_disconnect(session_uuid : @session_uuid)
            cb      : cb

        # store pref in localStorage to not auto-open this file next time
        @local_storage('auto_open', false)

    connect: (cb) =>
        @_remove_listeners()
        salvus_client.call
            timeout : 60     # a reasonable amount of time, since file could be *large*
            message : message.codemirror_get_session
                path         : @filename
                project_id   : @editor.project_id
                session_uuid : @session_uuid
            cb      : (err, resp) =>
                #console.log("new session: ", resp)
                if err
                    cb(err); return
                if resp.event == 'error'
                    cb(resp.event); return

                @session_uuid = resp.session_uuid

                # Render the chat
                @element.find(".salvus-editor-codemirror-chat-output").html('')
                for m in resp.chat
                    @_receive_chat(m)
                @new_chat_indicator(false)  # not necessarily new

                # If our content is already set, we'll end up doing a merge.
                resetting = @_previous_successful_set? and @_previous_successful_set

                if not resetting
                    # very easy
                    @_previous_successful_set = true
                    @_set(resp.content)
                    live_content = resp.content
                else
                    # Doing a reset -- apply all the edits to the current version of the document.
                    edit_stack = @dsync_client.edit_stack
                    # Apply our offline edits to the new live version of the document.
                    live_content = resp.content
                    for p in edit_stack
                        live_content =  diffsync.dmp.patch_apply(p.edits, live_content)[0]

                @dsync_client = codemirror_diffsync_client(@, resp.content)
                @dsync_server = new CodeMirrorDiffSyncHub(@)
                @dsync_client.connect(@dsync_server)
                @dsync_server.connect(@dsync_client)
                @_add_listeners()

                if resetting
                    codemirror_setValue_less_moving(@codemirror, live_content)
                    # Force a sync.
                    @_syncing = false
                    @sync()

                cb()

    _diffsync_ready: (mesg) =>
        if mesg.session_uuid == @session_uuid
            @sync_soon()

    call: (opts) =>
        opts = defaults opts,
            message     : required
            timeout     : 60
            cb          : undefined
        opts.message.session_uuid = @session_uuid
        salvus_client.call
            message : opts.message
            timeout : opts.timeout
            cb      : (err, result) =>
                if result? and result.event == 'reconnect'
                    console.log("codemirror sync session #{@session_uuid}: reconnecting ")
                    do_reconnect = () =>
                        @connect (err) =>
                            if err
                                console.log("codemirror sync session #{@session_uuid}: failed to reconnect")
                                opts.cb?(err)
                            else
                                console.log("codemirror sync session #{@session_uuid}: successful reconnect")
                                opts.cb?('reconnect')  # still an error condition
                    setTimeout(do_reconnect, 1000)  # give server some room
                else
                    opts.cb?(err, result)

    sync_soon: (wait) =>
        if not wait?
            wait = @opts.sync_interval
        if @_sync_soon?
            # We have already set a timer to do a sync soon.
            console.log("not sync_soon since -- We have already set a timer to do a sync soon.") 
            return
        do_sync = () =>
            delete @_sync_soon
            @sync (didnt_sync) =>
                if didnt_sync
                    @sync_soon(Math.min(5000, wait*1.5))
        @_sync_soon = setTimeout(do_sync, wait)

    sync: (cb) =>    # cb(false if a sync occured; true-ish if anything prevented a sync from happening)
        if @_syncing? and @_syncing
            # can only sync once a complete cycle is done, or declared failure.
            cb?()
            console.log('skipping since already syncing')
            return

        @_syncing = true
        if @_sync_soon?
            clearTimeout(@_sync_soon)
            delete @_sync_soon
        before = @dsync_client.live.string()
        @dsync_client.push_edits (err) =>
            console.log("dsync_client result: ", err)
            if err
                @_syncing = false
                if not @_sync_failures?
                    @_sync_failures = 1
                else
                    @_sync_failures += 1
                if @_sync_failures % 6 == 0 and not err == 'retry'
                    alert_message(type:"error", message:"Unable to synchronize '#{@filename}' with server; changes not saved until you next connect to the server.  Do not close your browser (offline mode not yet implemented).")

                setTimeout(@sync, 45000)  # try again soon...
                cb?(err)
            else
                @_sync_failures = 0
                @_syncing = false
                cb?()

    init_cursorActivity_event: () =>
        @codemirror.on 'cursorActivity', (instance) =>
            @send_cursor_info_to_hub_soon()
            @local_storage('cursor', @codemirror.getCursor())

    restore_cursor_position: () =>
        if @_cursor_previously_restored
            return
        @_cursor_previously_restore = true
        pos = @local_storage('cursor')
        if pos? and @codemirror?
            @codemirror.setCursor(pos)

    init_chat: () =>
        console.log('init_chat')
        chat = @element.find(".salvus-editor-codemirror-chat")
        input = chat.find(".salvus-editor-codemirror-chat-input")
        input.keydown (evt) =>
            if evt.which == 13 # enter
                content = $.trim(input.val())
                if content != ""
                    input.val("")
                    @send_broadcast_message({event:'chat', content:content}, true)
                return false

    _receive_chat: (mesg) =>
        @new_chat_indicator(true)
        output = @element.find(".salvus-editor-codemirror-chat-output")
        date = new Date(mesg.date)
        entry = templates.find(".salvus-chat-entry").clone()
        output.append(entry)
        header = entry.find(".salvus-chat-header")
        if (not @_last_chat_name?) or @_last_chat_name != mesg.name or ((date.getTime() - @_last_chat_time) > 60000)
            header.find(".salvus-chat-header-name").text(mesg.name).css(color:"#"+mesg.color)
            header.find(".salvus-chat-header-date").attr('title', date.toISOString()).timeago()
        else
            header.hide()
        @_last_chat_name = mesg.name
        @_last_chat_time = new Date(mesg.date).getTime()
        entry.find(".salvus-chat-entry-content").text(mesg.mesg.content).mathjax()
        output.scrollTop(output[0].scrollHeight)

    send_broadcast_message: (mesg, self) ->
        m = message.codemirror_bcast
            session_uuid : @session_uuid
            mesg         : mesg
            self         : self    #if true, then also send include this client to receive message
        salvus_client.send(m)

    send_cursor_info_to_hub: () =>
        delete @_waiting_to_send_cursor
        if not @session_uuid # not yet connected to a session
            return
        @send_broadcast_message({event:'cursor', pos:@codemirror.getCursor()})

    send_cursor_info_to_hub_soon: () =>
        if @_waiting_to_send_cursor?
            return
        @_waiting_to_send_cursor = setTimeout(@send_cursor_info_to_hub, @opts.cursor_interval)

    _receive_broadcast: (mesg) =>
        if mesg.session_uuid != @session_uuid
            return
        switch mesg.mesg.event
            when 'cursor'
                @_receive_cursor(mesg)
            when 'chat'
                @_receive_chat(mesg)

    _receive_cursor: (mesg) =>
        # If the cursor has moved, draw it.  Don't bother if it hasn't moved, since it can get really
        # annoying having a pointless indicator of another person.
        if not @_last_cursor_pos?
            @_last_cursor_pos = {}
        else
            pos = @_last_cursor_pos[mesg.color]
            if pos? and pos.line == mesg.mesg.pos.line and pos.ch == mesg.mesg.pos.ch
                return
        # cursor moved.
        @_last_cursor_pos[mesg.color] = mesg.mesg.pos   # record current position
        @_draw_other_cursor(mesg.mesg.pos, '#' + mesg.color, mesg.name)

    # Move the cursor with given color to the given pos.
    _draw_other_cursor: (pos, color, name) =>
        if not @codemirror?
            return
        if not @_cursors?
            @_cursors = {}
        id = color + name
        cursor_data = @_cursors[id]
        if not cursor_data?
            cursor = templates.find(".salvus-editor-codemirror-cursor").clone().show()
            inside = cursor.find(".salvus-editor-codemirror-cursor-inside")
            inside.css
                'background-color': color
            label = cursor.find(".salvus-editor-codemirror-cursor-label")
            label.css('color':color)
            label.text(name)
            cursor_data = {cursor: cursor, pos:pos}
            @_cursors[id] = cursor_data
        else
            cursor_data.pos = pos

        # first fade the label out
        cursor_data.cursor.find(".salvus-editor-codemirror-cursor-label").stop().show().animate(opacity:100).fadeOut(duration:8000)
        # Then fade the cursor out (a non-active cursor is a waste of space).
        cursor_data.cursor.stop().show().animate(opacity:100).fadeOut(duration:60000)
        #console.log("Draw #{name}'s #{color} cursor at position #{pos.line},#{pos.ch}", cursor_data.cursor)
        @codemirror.addWidget(pos, cursor_data.cursor[0], false)

    _apply_changeObj: (changeObj) =>
        @codemirror.replaceRange(changeObj.text, changeObj.from, changeObj.to)
        if changeObj.next?
            @_apply_changeObj(changeObj.next)

    click_save_button: () =>
        if not @save_button.hasClass('disabled')
            @save_button.find('span').text("Saving...")
            spin = setTimeout((() => @save_button.find(".spinner").show()), 100)
            @save (err) =>
                clearTimeout(spin)
                @save_button.find(".spinner").hide()
                @save_button.find('span').text('Save')
                if not err
                    @save_button.addClass('disabled')
                    @has_unsaved_changes(false)
                else
                    alert_message(type:"error", message:"Error saving '#{@filename}' to disk -- #{err}")
        return false

    save: (cb) =>
        if @opts.delete_trailing_whitespace
            @delete_trailing_whitespace()
        if @dsync_client?
            @sync () =>
                @call
                    message: message.codemirror_write_to_disk()
                    cb : cb
        else
            cb("Unable to save '#{@filename}' since it is not yet loaded.")

    delete_trailing_whitespace: () =>
        changeObj = undefined
        val = @codemirror.getValue()
        text1 = val.split('\n')
        text2 = misc.delete_trailing_whitespace(val).split('\n')
        if text1.length != text2.length
            alert_message(type:"error", message:"Internal error -- there is a bug in misc.delete_trailing_whitespace; please report.")
            return
        for i in [0...text1.length]
            if text1[i].length != text2[i].length
                obj = {from:{line:i,ch:text2[i].length}, to:{line:i,ch:text1[i].length}, text:[""]}
                if not changeObj?
                    changeObj = obj
                    currentObj = changeObj
                else
                    currentObj.next = obj
                    currentObj = obj

        if changeObj?
            @_apply_changeObj(changeObj)



###############################################
# LateX Editor
###############################################

# Make a temporary uuid-named directory in path.
tmp_dir = (project_id, path, cb) ->      # cb(err, directory_name)
    name = uuid()
    salvus_client.exec
        project_id : project_id
        path       : path
        command    : "mkdir"
        args       : [name]
        cb         : (err, output) =>
            if err
                cb("Problem creating temporary PDF preview path.")
            else
                cb(false, name)

remove_tmp_dir = (project_id, path, tmp_dir, cb) ->
    salvus_client.exec
        project_id : project_id
        path       : path
        command    : "rm"
        args       : ['-rf', tmp_dir]
        cb         : (err, output) =>
            cb?(err)

class PDF_Preview extends FileEditor
    # Compute single page
    constructor: (@editor, @filename, contents, opts) ->
        @element = templates.find(".salvus-editor-pdf-preview").clone()
        @spinner = @element.find(".salvus-editor-pdf-preview-spinner")

        @page_number = 1
        @density = 300  # impacts the clarity

        s = path_split(@filename)
        @path = s.head
        if @path == ''
            @path = './'
        @file = s.tail

        #@element.find("a[href=#prev]").click(@prev_page)
        #@element.find("a[href=#next]").click(@next_page)
        #@element.find("a[href=#zoom-in]").click(@zoom_in)
        #@element.find("a[href=#zoom-out]").click(@zoom_out)

        @element.css('height':$(window).height()*.8)
        @output = @element.find(".salvus-editor-pdf-preview-page")
        @update () =>
            @element.resizable(handles: "e,w,s,sw,se").on('resize', @focus)

    focus: () =>
        @output.height(@element.height())
        @output.width(@element.width())

    update: (cb) =>
        @output.height(@element.height())
        @output.width(@element.width())
        @spinner.show().spin(true)
        tmp_dir @editor.project_id, @path, (err, tmp) =>
            if err
                @spinner.hide().spin(false)
                alert_message(type:"error", message:err)
                cb?(err)
                return
            # Update the PNG's which provide a preview of the PDF
            salvus_client.exec
                project_id : @editor.project_id
                path       : @path
                command    : 'gs'
                args       : ["-dBATCH", "-dNOPAUSE",
                              "-sDEVICE=pngmono",
                              "-sOutputFile=#{tmp}/%d.png", "-r#{@density}", @file]

                timeout    : 20
                err_on_exit: false
                cb         : (err, output) =>
                    if err
                        alert_message(type:"error", message:err)
                        remove_tmp_dir(@editor.project_id, @path, tmp)
                        cb?(err)
                    else
                        i = output.stdout.indexOf("Page")
                        s = output.stdout.slice(i)
                        pages = {}
                        tasks = []
                        while s.length>4
                            i = s.indexOf('\n')
                            if i == -1
                                break
                            page_number = s.slice(5,i)
                            s = s.slice(i+1)

                            png_file = @path + "/#{tmp}/" + page_number + '.png'
                            f = (cb) =>
                                num  = arguments.callee.page_number
                                salvus_client.read_file_from_project
                                    project_id : @editor.project_id
                                    path       : arguments.callee.png_file
                                    cb         : (err, result) =>
                                        if err
                                            cb(err)
                                        else
                                            if result.url?
                                                pages[num] = result.url
                                            cb()

                            f.png_file = png_file
                            f.page_number = parseInt(page_number)
                            tasks.push(f)

                        async.parallel tasks, (err) =>
                            remove_tmp_dir(@editor.project_id, @path, tmp)
                            if err
                                alert_message(type:"error", message:"Error downloading png preview -- #{err}")
                                @spinner.spin(false).hide()
                                cb?(err)
                            else
                                if len(pages) == 0
                                    @output.html('')
                                else
                                    children = @output.children()
                                    # We replace existing pages if possible, which nicely avoids all nasty scrolling issues/crap.
                                    for n in [0...len(pages)]
                                        url = pages[n+1]
                                        if n < children.length
                                            $(children[n]).attr('src', url)
                                        else
                                            @output.append($("<img src='#{url}' class='salvus-editor-pdf-preview-image'>"))
                                    # Delete any remaining pages from before (if doc got shorter)
                                    for n in [len(pages)...children.length]
                                        $(children[n]).remove()
                                @spinner.spin(false).hide()
                                cb?()

    next_page: () =>
        @page_number += 1   # TODO: !what if last page?
        @update()

    prev_page: () =>
        if @page_number >= 2
            @page_number -= 1
            @update()

    zoom_out: () =>
        if @density >= 75
            @density -= 25
            @update()

    zoom_in: () =>
        @density += 25
        @update()

    show: () =>
        @element.show()
        @focus()

    hide: () =>
        @element.hide()


class LatexEditor extends FileEditor
    constructor: (@editor, @filename, content, opts) ->
        # The are three components:
        #     * latex_editor -- a CodeMirror editor
        #     * preview -- display the images (page forward/backward/resolution)
        #     * log -- log of latex command
        opts.mode = 'stex'

        @_current_page = 'latex_editor'
        @element = templates.find(".salvus-editor-latex").clone()

        # initialize the latex_editor
        @latex_editor = new CodeMirrorSessionEditor(@editor, @filename, "", opts)
        @element.find(".salvus-editor-latex-latex_editor").append(@latex_editor.element)

        v = path_split(@filename)
        @_path = v.head
        @_target = v.tail

        # initialize the preview
        n = @filename.length
        @preview = new PDF_Preview(@editor, @filename.slice(0,n-3)+"pdf", undefined, {})
        @element.find(".salvus-editor-latex-preview").append(@preview.element)

        # initalize the log
        @log = @element.find(".salvus-editor-latex-log")

        @_init_buttons()

        @preview.update()

    _init_buttons: () =>
        @element.find("a[href=#latex_editor]").click () =>
            @show_page('latex_editor')
            @latex_editor.focus()
            return false

        @element.find("a[href=#preview]").click () =>
            @compile_and_update()
            @show_page('preview')
            return false

        #@element.find("a[href=#log]").click () =>
            #@show_page('log')
            return false

        @element.find("a[href=#latex]").click () =>
            @show_page('log')
            @compile_and_update()
            return false

        @element.find("a[href=#pdf]").click () =>
            @download_pdf()
            return false

    click_save_button: () =>
        @latex_editor.click_save_button()

    save: (cb) =>
        @latex_editor.save(cb)

    compile_and_update: (cb) =>
        async.series([
            (cb) =>
                @editor.save(@filename, cb)
            (cb) =>
                @run_latex (err) =>
                    # latex prefers to be run twice...
                    if err
                        cb(err)
                    else
                        @run_latex(cb)

            (cb) =>
                @preview.update(cb)
        ], (err) -> cb?(err))

    _get: () =>
        return @latex_editor._get()

    _set: (content) =>
        @latex_editor._set(content)

    show: () =>
        @element?.show()
        @latex_editor?.show()

    focus: () =>
        @latex_editor?.focus()

    has_unsaved_changes: (val) =>
        return @latex_editor?.has_unsaved_changes(val)

    show_page: (name) =>
        if name == @_current_page
            return
        for n in ['latex_editor', 'preview', 'log']
            e = @element.find(".salvus-editor-latex-#{n}")
            button = @element.find("a[href=#" + n + "]")
            if n == name
                e.show()
                button.addClass('btn-primary')
            else
                e.hide()
                button.removeClass('btn-primary')
        @_current_page = name

    run_latex: (cb) =>
        @save (err) =>
            # TODO -- what about error?
            salvus_client.exec
                project_id : @editor.project_id
                path       : @_path
                command    : 'pdflatex'
                args       : ['-interaction=nonstopmode', '\\input', @_target]
                timeout    : 5
                err_on_exit : false
                cb         : (err, output) =>
                    if err
                        alert_message(type:"error", message:err)
                    else
                        @log.find("textarea").text(output.stdout + '\n\n' + output.stderr)
                        # Scroll to the bottom of the textarea
                        f = @log.find('textarea')
                        f.scrollTop(f[0].scrollHeight)

                    cb?()

    download_pdf: () =>
        # TODO: THIS replicates code in project.coffee
        salvus_client.read_file_from_project
            project_id : @editor.project_id
            path       : @filename.slice(0,@filename.length-3)+"pdf"
            cb         : (err, result) =>
                if err
                    alert_message(type:"error", message:"Error downloading PDF: #{err} -- #{misc.to_json(result)}")
                else
                    url = result.url + "&download"
                    iframe = $("<iframe>").addClass('hide').attr('src', url).appendTo($("body"))
                    setTimeout((() -> iframe.remove()), 1000)



class Terminal extends FileEditor
    constructor: (@editor, @filename, content, opts) ->
        # TODO: content currently ignored.
        opts = @opts = defaults opts,
            session_uuid : undefined
            rows         : 24
            cols         : 80
        elt = $("<div>").salvus_console
            title   : "Terminal"
            cols    : @opts.cols
            rows    : @opts.rows
            resizable: false
        @console = elt.data("console")
        @element = @console.element
        @connect_to_server()
        @local_storage("auto_open", true)

    connect_to_server: (cb) =>
        mesg =
            timeout    : 30  # just for making the connection; not the timeout of the session itself!
            type       : 'console'
            project_id : @editor.project_id
            cb : (err, session) =>
                if err
                    alert_message(type:'error', message:err)
                else
                    @console.set_session(session)
                cb?(err)

        if @opts.session_uuid?
            #console.log("Connecting to an existing session.")
            mesg.session_uuid = @opts.session_uuid
            salvus_client.connect_to_session(mesg)
        else
            #console.log("Opening a new session.")
            mesg.params  = {command:'bash', rows:@opts.rows, cols:@opts.cols}
            salvus_client.new_session(mesg)

        # TODO
        #@filename_tab.set_icon('console')

    _get: () =>  # TODO
        return 'history saving not yet implemented'

    _set: (content) =>  # TODO

    focus: () =>
        @console?.focus()

    terminate_session: () =>
        #@console?.terminate_session()
        @local_storage("auto_open", false)

    show: () =>
        @element.show()
        if @console?
            e = $(@console.terminal.element)
            #e.height((@console.opts.rows * 1.1) + "em")
            e.height($(window).height() - 3*top_navbar.height())
            @console.focus()
            window.scrollTo(0, document.body.scrollHeight); $(".salvus-top-scroll").show()

class Worksheet extends FileEditor
    constructor: (@editor, @filename, content, opts) ->
        opts = @opts = defaults opts,
            session_uuid : undefined
        @element = $("<div>Opening worksheet...</div>")  # TODO -- make much nicer
        if content?
            @_set(content)
        else
            salvus_client.read_text_file_from_project
                project_id : @editor.project_id
                timeout    : 30
                path       : filename
                cb         : (err, mesg) =>
                    if err
                        alert_message(type:"error", message:"Communications issue loading worksheet #{@filename} -- #{err}")
                    else if mesg.event == 'error'
                        alert_message(type:"error", message:"Error loading worksheet #{@filename} -- #{to_json(mesg.error)}")
                    else
                        @_set(mesg.content)

    connect_to_server: (session_uuid, cb) =>
        if @session?
            cb('already connected or attempting to connect')
            return
        @session = "init"
        async.series([
            (cb) =>
                # If the worksheet specifies a specific session_uuid,
                # try to connect to that one, in case it is still
                # running.
                if session_uuid?
                    salvus_client.connect_to_session
                        type         : 'sage'
                        timeout      : 60
                        project_id   : @editor.project_id
                        session_uuid : session_uuid
                        cb           : (err, _session) =>
                            if err
                                # NOPE -- try to make a new session (below)
                                cb()
                            else
                                # Bingo -- got it!
                                @session = _session
                                cb()
                else
                    # No session_uuid requested.
                    cb()
            (cb) =>
                if @session? and @session != "init"
                    # We successfully got a session above.
                    cb()
                else
                    # Create a completely new session on the given project.
                    salvus_client.new_session
                        timeout    : 60
                        type       : "sage"
                        project_id : @editor.project_id
                        cb : (err, _session) =>
                            if err
                                @element.text(err)  # TODO -- nicer
                                alert_message(type:'error', message:err)
                                @session = undefined
                            else
                                @session = _session
                            cb(err)
        ], cb)

    _get: () =>
        if @worksheet?
            obj = @worksheet.to_obj()
            # Make JSON nice, so more human readable *and* more diff friendly (for git).
            return JSON.stringify(obj, null, '\t')
        else
            return undefined

    _set: (content) =>
        content = $.trim(content)
        if content.length > 0
            {title, description, content, session_uuid} = from_json(content)
        else
            title = "Untitled"
            description = "No description"
            content = undefined
            session_uuid = undefined

        @connect_to_server session_uuid, (err) =>
            if err
                return
            @element.salvus_worksheet
                title       : title
                description : description
                content     : content
                path        : @filename
                session     : @session
                project_id  : @editor.project_id

            @worksheet = @element.data("worksheet")
            @element   = @worksheet.element
            @worksheet.on 'save', (new_filename) =>
                if new_filename != @filename
                    @editor.change_tab_filename(@filename, new_filename)
                    @filename = new_filename

            @worksheet.on 'change', () =>
                @has_unsaved_changes(true)

    focus: () =>
        @worksheet?.focus()

class Image extends FileEditor
    constructor: (@editor, @filename, url, opts) ->
        opts = @opts = defaults opts,{}
        @element = $("<img>")
        if url?
            @element.attr('src', url)
        else
            salvus_client.read_file_from_project
                project_id : @editor.project_id
                timeout    : 30
                path       : @filename
                cb         : (err, mesg) =>
                    if err
                        alert_message(type:"error", message:"Communications issue loading #{@filename} -- #{err}")
                    else if mesg.event == 'error'
                        alert_message(type:"error", message:"Error getting #{@filename} -- #{to_json(mesg.error)}")
                    else
                        @element.attr('src', mesg.url)

class Spreadsheet extends FileEditor
    constructor: (@editor, @filename, content, opts) ->
        opts = @opts = defaults opts,{}
        @element = $("<div>Salvus spreadsheet not implemented yet.</div>")

class Slideshow extends FileEditor
    constructor: (@editor, @filename, content, opts) ->
        opts = @opts = defaults opts,{}
        @element = $("<div>Salvus slideshow not implemented yet.</div>")
