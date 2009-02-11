#!/usr/bin/env python

# Hamster Whisper text editor for the HamsterSpeak scripting language
# for OHRRPGCE Plotscripting.
# -----------------------------------------------------------------------------
#
# Copyright (C) 2009 James Paige & Hamster Republic Productions
# Copyright (C) 2007 Micah Carrick <email@micahcarrick.com>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
# -----------------------------------------------------------------------------
#
# This file is derived from Micah Carrick's Linux GUI Programming with
# GTK+ and Glade3 tutorial script from
# http://www.micahcarrick.com/12-24-2007/gtk-glade-tutorial-part-1.html
# -----------------------------------------------------------------------------

import sys
import os
import gtk
import pango
import subprocess
from xml.etree import ElementTree
import re

import version

# -----------------------------------------------------------------------------

class HWhisper:

    # We use the initialization of the HWhisper class to establish
    # references to the widgets we'll need to work with in the callbacks for
    # various signals. This is done using the XML file we created with Glade
    # Convert the glade file to the XML file with the following command:
    ### gtk-builder-convert hwhisper.glade hwhisper.xml
    def __init__(self):
        # Configuration
        self.version_number = version.version
        self.xml_file = "hwhisper.xml"
        self.app_name = version.app_name
        self.copyright = version.copyright
        self.website = version.website
        self.authors = version.authors
        self.description = version.description
        
        # Default values
        self.filename = None
        self.about_dialog = None
        self.setup_filetypes()
        self.config = ConfigManager()
        
        # use GtkBuilder to build our interface from the XML file 
        try:
            builder = gtk.Builder()
            builder.add_from_file(self.xml_file) 
        except:
            self.error_message("Failed to load UI XML file: " + self.xml_file)
            sys.exit(1)
        
        # get the widgets which will be referenced in callbacks
        self.window = builder.get_object("window")
        self.statusbar = builder.get_object("statusbar")
        self.text_view = builder.get_object("text_view")
        self.menu = builder.get_object("menu_bar")
        self.search_bar = builder.get_object("search_bar")
        self.search_entry = builder.get_object("search_entry")
        self.search_status = builder.get_object("search_status")
        # widgets for search option buttons
        self.backward_button = builder.get_object("search_backward_button")
        self.wrap_button = builder.get_object("search_wrap_button")
        self.case_button = builder.get_object("search_case_button")
        self.backward_image = builder.get_object("search_backward_button_image")
        self.wrap_image = builder.get_object("search_wrap_button_image")
        self.case_image = builder.get_object("search_case_button_image")
        # widgets for the console
        self.console_scroll = builder.get_object("scrolledconsole")
        self.console = builder.get_object("console")
        self.toggle_console_menu_item = builder.get_object("toggle_console_menu_item")
        self.splitpanes = builder.get_object("splitpanes")
        
        # create the undo manager
        self.undo = UndoManager()
        
        # connect signals
        builder.connect_signals(self)
        buff = self.text_view.get_buffer()
        buff.connect("changed", self.on_text_changed)
        
        # set the text view font
        self.text_view.modify_font(pango.FontDescription("monospace 14"))
        
        # set the default icon to the GTK "edit" icon
        gtk.window_set_default_icon_name(gtk.STOCK_EDIT)
        
        # setup and initialize our statusbar
        self.statusbar_cid = self.statusbar.get_context_id(self.app_name)
        self.reset_default_status()
        
        # Load config file
        self.config.load()
        self.update_search_buttons()
        
        # Set up recent files menu
        self.reload_recent_menu()
        
        # The plotdict will be loaded when first requested
        self.plotdict_tree = None
        self.shortname_cache = None
        self.help_history = []
        
        # Searchbar is hidden by default
        self.search_bar.hide_all()
        
        # Set up the console
        self.darken_widget(self.console)
        self.setup_console_tags()
        # Restore the remembered size for the console
        console_size = self.config.getint("console", "size")
        if console_size is not None:
            if console_size < 32:
                # prevent crazy-small console sizes
                console_size = 45
            self.splitpanes.set_position(console_size)
        # Console is hidden by default
        self.toggle_console(False)

    def cleanup(self):
        console_size = self.splitpanes.get_position()
        self.config.set("console", "size", console_size)
        self.config.save()
        gtk.main_quit()

    #-------------------------------------------------------------------

    def setup_filetypes(self):
        hss = gtk.FileFilter()
        hss.set_name("HamsterSpeak Scripts")
        hss.add_pattern("*.hss")
        hss.add_pattern("*.txt")
        hss.add_pattern("*.hsi")
        hss.add_pattern("*.hsd")
        all = gtk.FileFilter()
        all.set_name("All Files")
        all.add_pattern("*")
        self.file_filters = (hss, all)

    def move_cursor_to_offset(self, offset):
        if offset is None: return
        buff = self.text_view.get_buffer()
        iter = buff.get_iter_at_offset(offset)
        self.move_selection(iter, iter)

    def cursor_offset(self):
        buff = self.text_view.get_buffer()
        mark = buff.get_insert()
        iter = buff.get_iter_at_mark(mark)
        offset = iter.get_offset()
        return offset

    def find_hspeak_token(self, iter, use_ref_tags=False):
        # Find start of token
        start = iter.copy()
        if start.backward_find_char(_find_hspeak_token_start, (start, use_ref_tags)):
            while start.get_char() in _hspeak_whitespace:
                start.forward_char()
        # find end of token
        stop = start.copy()
        stop.forward_find_char(_find_hspeak_token_stop, (stop, use_ref_tags))
        if stop.backward_find_char(_find_hspeak_non_whitespace):
            stop.forward_char()
            # special voodoo for := operators, since : is not usually a separator
            while stop.get_char() in "=":
                test = stop.copy()
                test.backward_char()
                if self.iter_prev_char(stop) in ":":
                    stop.backward_char()
                    while self.iter_prev_char(stop) in _hspeak_whitespace:
                        stop.backward_char()
        return (start, stop)

    def iter_prev_char(self, iter):
        test = iter.copy()
        if test.backward_char():
            return test.get_char()
        return False

    def move_selection(self, start, stop):
        buff = self.text_view.get_buffer()
        insert = buff.get_insert()
        buff.move_mark(insert, start)
        selection_bound = buff.get_selection_bound()
        buff.move_mark(selection_bound, stop)
        self.text_view.scroll_to_mark(insert, 0.1)

    def find_named_menu(self, menu, name):
        for item in menu:
            sub = item.get_submenu()
            if sub is not None:
                if sub.get_name() == name:
                    return sub
                recurse = self.find_named_menu(sub, name)
                if recurse is not None:
                    return recurse
        return None
                

    def reload_recent_menu(self):
        recent_list = self.config.get_list("files", "recent", "|")
        menu = self.find_named_menu(self.menu, "recent_menu_top")
        for item in menu:
            menu.remove(item)
        for name in recent_list:
            if os.path.exists(name):
                item = gtk.MenuItem(name)
                item.set_name(name)
                item.connect("activate", self.on_recent_menu_item_activate, name)
                menu.append(item)
                item.show()

    def add_recent(self, filename):
        old_list = self.config.get_list("files", "recent", "|")
        new_list = []
        for item in old_list:
            if item != filename:
                new_list.append(item)
        new_list = [filename] + new_list
        self.config.set_list("files", "recent", "|", new_list)
        self.reload_recent_menu()

    def search(self, text):
        status = self.search_status
        status.set_text("")
        if text == "": return

        buff = self.text_view.get_buffer()
        mark = buff.get_insert()
        iter = buff.get_iter_at_mark(mark)

        self.search_from_iter(text, iter)

    def search_from_iter(self, text, iter):
        status = self.search_status
        if text == "": return

        backward = self.config.getboolean("search", "backward")

        match = self.iter_search_in_direction(iter, text, backward)
        if match is None:
            self.search_wrap_or_give_up(text, backward)
            return
        (start, stop) = match
        if iter.get_offset() == start.get_offset():
            # already at the current cursor position
            self.iter_advance_in_direction(iter, backward)
            match = self.iter_search_in_direction(iter, text, backward)
            if match is None:
                self.search_wrap_or_give_up(text, backward)
                return
            (start, stop) = match
                
        self.move_selection(start, stop)
        status.set_text('Found "%s"' % (text))

    def search_wrap_or_give_up(self, text, backward):
        status = self.search_status
        buff = self.text_view.get_buffer()
        wrap = self.config.getboolean("search", "wrap")
        if wrap:
            if backward:
                match = self.iter_search_in_direction(buff.get_end_iter(), text, backward)
            else:
                match = self.iter_search_in_direction(buff.get_start_iter(), text, backward)
            if match is not None:
                (start, stop) = match
                self.move_selection(start, stop)
                status.set_text('Wrapped and found "%s"' % (text))
                return
        status.set_text('"%s" not found. (searching %s)' % (text, self.direction_as_text(backward)))

    def direction_as_text(self, backward):
        if backward:
            return "backward"
        else:
            return "forward"

    def iter_search_in_direction(self, iter, s, backward=False):
        buff = self.text_view.get_buffer()
        text = buff.get_text(buff.get_start_iter(), buff.get_end_iter())
        case_sensitive = self.config.getboolean("search", "case_sensitive")
        if not case_sensitive:
            text = text.lower()
            s = s.lower()
        offset = iter.get_offset()
        try:
            if backward:
                found = text.rindex(s, 0, offset)
            else:
                found = text.index(s, offset)
        except ValueError:
            return None
        start = buff.get_iter_at_offset(found)
        stop = buff.get_iter_at_offset(found + len(s))
        return (start, stop)

    def iter_advance_in_direction(self, iter, backward=False):
        if backward:
            iter.backward_char()
        else:
            iter.forward_char()

    def update_search_buttons(self):
        self.update_search_backward_button()
        self.update_search_wrap_button()
        self.update_search_case_button()
        self.search_status.set_text("")

    def update_search_backward_button(self):
        img = self.backward_image
        tog = self.config.getboolean("search", "backward")
        if tog:
            img.set_from_stock(gtk.STOCK_GO_UP, 4)
        else:
            img.set_from_stock(gtk.STOCK_GO_DOWN, 4)
        self.backward_button.set_active(tog)
        
    def update_search_wrap_button(self):
        img = self.wrap_image
        tog = self.config.getboolean("search", "wrap")
        if tog:
            img.set_from_stock(gtk.STOCK_REFRESH, 4)
        else:
            img.set_from_stock(gtk.STOCK_GOTO_LAST, 4)
        self.wrap_button.set_active(tog)

    def update_search_case_button(self):
        img = self.case_image
        tog = self.config.getboolean("search", "case_sensitive")
        if tog:
            img.set_from_stock(gtk.STOCK_BOLD, 4)
        else:
            img.set_from_stock(gtk.STOCK_SELECT_FONT, 4)
        self.case_button.set_active(tog)

    def browse_for_plotdict_xml(self):
        filter = gtk.FileFilter()
        filter.set_name("Plotscripting Dictionary (plotdict.xml)")
        filter.add_pattern("plotdict.xml")
        filename = self.get_filename("Locate plotdict.xml...", None, [filter],
                                 gtk.FILE_CHOOSER_ACTION_OPEN, gtk.STOCK_OPEN)
        if filename is not None:
            self.config.set("help", "plotdict", filename)
        return filename

    def browse_for_hspeak(self):
        filter = gtk.FileFilter()
        if is_windows():
            filter.set_name("HamsterSpeak Compiler (hspeak.exe)")
            filter.add_pattern("hspeak.exe")
            filter.add_pattern("hspeak.bat")
        else:
            filter.set_name("HamsterSpeak Compiler (hspeak)")
            filter.add_pattern("hspeak")
            filter.add_pattern("hspeak.sh")
        filename = self.get_filename("Locate hspeak compiler...", None, [filter],
                                 gtk.FILE_CHOOSER_ACTION_OPEN, gtk.STOCK_OPEN)
        if filename is not None:
            self.config.set("hspeak", "compiler", filename)
        return filename

    def find_hspeak(self):
        hspeak = self.config.get("hspeak", "compiler", None)
        if hspeak is None or not os.path.exists(hspeak):
            hspeak = self.browse_for_hspeak()
        return hspeak

    def compile(self):
        self.toggle_console(True)
        if self.filename is None:
            self.set_console("no file to compile")
            return
        # find hspeak
        hspeak = self.find_hspeak()
        if hspeak is None:
            self.set_console("unable to find hspeak compiler")
            return
        # remember the old working directory
        remember_dir = os.getcwdu()
        # Notify the user that compilation is starting
        self.set_console("compiling...")
        self.statusbar_push("Compiling " + self.filename)
        self.window.set_sensitive(False)
        # switch working directory
        os.chdir(os.path.dirname(hspeak))
        # call the compiler
        if is_windows():
            command_line = [hspeak, "-ykc", self.filename]
            p = subprocess.Popen(command_line, stdout=subprocess.PIPE)
        else:
            # I have no dang idea why the win32 method above doesn't work on Linux :(
            command_line = "'%s' -ykc '%s'" % (hspeak, self.filename)
            p = subprocess.Popen(command_line, shell=True, stdout=subprocess.PIPE)
        while p.returncode is None:
          #sts = os.waitpid(p.pid, 0)
          p.poll()
          if gtk.events_pending():
              gtk.main_iteration()
        # Done
        os.chdir(remember_dir)
        compiler_output = p.stdout.read()
        if p.returncode != 0:
            compiler_output += "Compiler returned error code (%d)" % (p.returncode)
        self.set_console(compiler_output)
        self.move_console_to_end()
        # Done, re-enable window and reset status bar
        self.window.set_sensitive(True)
        self.statusbar_pop()
        self.reset_default_status()

    def get_plotdict_filename(self):
        plotdict = self.config.get("help", "plotdict")
        if plotdict is None or not os.path.exists(plotdict):
            plotdict = self.browse_for_plotdict_xml()
            if plotdict is None or not os.path.exists(plotdict):
                self.plotdict_xml_fail("unable to find plotdict.xml file")
        return plotdict

    def get_plotdict_tree_root(self):
        # get the help file
        plotdict = self.get_plotdict_filename()
        # get the tree
        if self.plotdict_tree is None:
            self.plotdict_tree = ElementTree.parse(plotdict)
        # get the root of the tree
        root = self.plotdict_tree.getroot()
        # verify that the root is sane
        if root.tag != "plotscript":
            self.plotdict_xml_fail("no plotscript tag")
        # cache the shortnames
        self.build_shortname_cache(root)
        return root

    def show_help_index(self, info_string=None):
        # Get the buffer
        buff = self.console.get_buffer()
        # Start building the text
        buff.set_text("")
        if info_string is not None:
            buff.insert(buff.get_end_iter(), info_string + "\n")
        # Parse the help file
        root = self.get_plotdict_tree_root()
        for section in root.getiterator("section"):
            buff.insert_with_tags_by_name(buff.get_end_iter(), section.get("title") + "\n", "section")
            for command in section.getiterator("command"):
                ref = command.get("id")
                if self.shortname_cache.has_key(ref):
                    ref = self.shortname_cache[ref]
                buff.insert_with_tags_by_name(buff.get_end_iter(), ref, "ref", "linespacing")
                buff.insert(buff.get_end_iter(), " ")
            buff.insert(buff.get_end_iter(), "\n")
        # Show the text
        self.toggle_console(True)

    def build_shortname_cache(self, xml_root):
        if self.shortname_cache is None:
            self.shortname_cache = {}
            for section in xml_root.getiterator("section"):
                for command in section.getiterator("command"):
                    key = command.get("id")
                    shortname = command.find("shortname").text
                    self.shortname_cache[key] = shortname

    def show_context_help(self, text, depth=0):
        if depth > 100:
            self.plotdict_xml_fail("alias recursion went too deep, probably an alias loop?")
        # Calculate the short text
        key = text.lower().replace(" ", "").replace("\t", "")
        # Parse the help file
        root = self.get_plotdict_tree_root()
        for section in root.getiterator("section"):
            for command in section.getiterator("command"):
                id = command.get("id")
                altkey = None
                if self.shortname_cache.has_key(id):
                    altkey = self.shortname_cache[id].lower().replace(" ", "").replace("\t", "")
                if id == key or altkey == key:
                    alias = command.find("alias")
                    if alias is not None:
                        self.show_context_help(alias.text, depth + 1)
                        return
                    self.show_help_page(command)
                    return
        # Help not found
        warning = self.help_warning_text(text)
        self.show_help_index(warning)

    def help_warning_text(self, notfound):
        if notfound == "" or notfound == "INDEX":
            return None
        if re.match("^\d+$", notfound) is not None:
            return '%s is a numeric value' % (notfound)
        if re.match("^#", notfound) is not None:
            return '"%s" is a comment. It is only for information and is not actually executed as part of your script.' % (notfound)
        if re.match("^(tag|song|sfx|hero|item|stat|atk|enemy):.+", notfound, re.I) is not None:
            return '"%s" is a constant of the variety that is normally defined in your .hsi file' % (notfound)
        return 'No match for "%s" found in help.' % (notfound)

    def setup_console_tags(self):
        # set up tags for color the help text
        buff = self.console.get_buffer()
        buff.create_tag("plain")
        buff.create_tag("linespacing", pixels_inside_wrap=2)
        buff.create_tag("section", scale=1.4, foreground="pink")
        buff.create_tag("canon", scale=1.4, foreground="yellow")
        buff.create_tag("param", foreground="orange", weight=700)
        buff.create_tag("example", background="pink", foreground="black", indent=16, family="Monospace")
        buff.create_tag("seealso", foreground="green", weight=600, scale=1.2)
        buff.create_tag("divider", foreground="lightblue", underline=True)
        # Ref is special because it needs to be clickable
        tag = gtk.TextTag("ref")
        tag.set_property("foreground","lightblue")
        tag.set_property("background","darkblue")
        tag.set_property("weight", 600)
        tag.connect("event", self.on_help_ref_event)
        tagtable = buff.get_tag_table()
        tagtable.add(tag)
 
    def show_help_page(self, elem):
        key = elem.get("id")
        # if this key is already in history, remove it
        for history in self.help_history:
            if history == key:
                self.help_history.remove(history)
        # get all the relevant elements
        canon = elem.find("canon")
        if canon is None: canon = elem.find("cannon") # hack to work with old plotdict.xml files
        shortname = elem.find("shortname")
        description = elem.find("description")
        example = elem.find("example")
        seealso = elem.find("seealso")
        # Get the buffer
        buff = self.console.get_buffer()
        # Start building the text
        buff.set_text("")
        # Link to the index
        buff.insert_with_tags_by_name(buff.get_end_iter(), "INDEX", "ref", "divider")
        buff.insert_with_tags_by_name(buff.get_end_iter(), " ", "divider")
        # Show the history
        for history in self.help_history:
            if self.shortname_cache.has_key(history):
                history = self.shortname_cache[history]
            buff.insert_with_tags_by_name(buff.get_end_iter(), history, "ref", "divider")
            buff.insert_with_tags_by_name(buff.get_end_iter(), " ", "divider")
        buff.insert(buff.get_end_iter(), "\n")
        self.parse_help(canon)
        buff.insert(buff.get_end_iter(), "\n")
        self.parse_help(description)
        buff.insert(buff.get_end_iter(), "\n")
        self.parse_help(example)
        buff.insert(buff.get_end_iter(), "\n")
        self.parse_help(seealso)
        # Show the text
        self.toggle_console(True)
        # update history
        self.help_history.append(key)
        if len(self.help_history) > 5:
            self.help_history = self.help_history[1:]

    def parse_help(self, elem):
        if elem is None: return
        buff = self.console.get_buffer()
        text = elem.text
        if text is not None:
            tagstyle = "plain"
            if elem.tail != "" and text.strip() == "": text = " "
            if elem.tag == "example":
                tagstyle = "example"
                text = self.pad_help_example(text)
            elif elem.tag == "canon" or elem.tag == "cannon":
                tagstyle = "canon"
            elif elem.tag == "p":
                tagstyle = "param"
            elif elem.tag == "ref":
                tagstyle = "ref"
                if self.shortname_cache.has_key(text):
                    text = self.shortname_cache[text]
            elif elem.tag == "seealso":
                tagstyle = "seealso"
                text = "See Also\n"
            buff.insert_with_tags_by_name(buff.get_end_iter(), text, tagstyle)
        for sub in elem.getchildren():
            self.parse_help(sub)
        if elem.tail is not None:
            tail = elem.tail
            if elem.tail != "" and tail.strip() == "": tail = " "
            buff.insert(buff.get_end_iter(), tail)

    def pad_help_example(self, text):
        text = text.replace("\t", "  ")
        lines = text.split("\n")
        longest = 0
        for line in lines:
            if len(line) > longest:
                longest = len(line)
        format = "%%-%ds" % (longest)
        for i in xrange(len(lines)):
            lines[i] = format % (lines[i])
        return "\n".join(lines)

    def plotdict_xml_fail(self, text):
        self.toggle_console(True)
        self.set_console("Parsing of plotdict.xml failed.\n" + text)

    def toggle_console(self, state=None):
        menuitem = self.toggle_console_menu_item
        if state is None:
            state = not menuitem.get_active()
        menuitem.set_active(state)
        if state:
            self.console_scroll.show_all()
        else:
            self.console_scroll.hide_all()

    def set_console(self, text):
        buff = self.console.get_buffer()
        buff.set_text(text)

    def darken_widget(self, widget):
        black = gtk.gdk.color_parse("black")
        white = gtk.gdk.color_parse("white")
        for state in [gtk.STATE_NORMAL, gtk.STATE_ACTIVE,
                      gtk.STATE_PRELIGHT, gtk.STATE_SELECTED,
                      gtk.STATE_INSENSITIVE]:
            widget.modify_base(state, black)
            widget.modify_text(state, white)

    def move_console_to_end(self):
        buff = self.console.get_buffer()
        iter = buff.get_end_iter()
        self.move_console(iter, iter)

    def move_console(self, start, stop):
        buff = self.console.get_buffer()
        insert = buff.get_insert()
        buff.move_mark(insert, start)
        selection_bound = buff.get_selection_bound()
        buff.move_mark(selection_bound, stop)
        self.console.scroll_to_mark(insert, 0.0)

    def statusbar_push(self, text):
        self.statusbar.push(self.statusbar_cid, text)

    def statusbar_pop(self):
        self.statusbar.pop(self.statusbar_cid)
        
    #-------------------------------------------------------------------

    # When our window is destroyed, we want to break out of the GTK main loop. 
    # We do this by calling gtk_main_quit(). We could have also just specified 
    # gtk_main_quit as the handler in Glade!
    def on_window_destroy(self, widget, data=None):
        self.cleanup()
    
    # When the window is requested to be closed, we need to check if they have 
    # unsaved work. We use this callback to prompt the user to save their work 
    # before they exit the application. From the "delete-event" signal, we can 
    # choose to effectively cancel the close based on the value we return.
    def on_window_delete_event(self, widget, event, data=None):
    
        if self.check_for_save(): self.on_save_menu_item_activate(None, None)
        return False # Propogate event

    # This is called whenever the user starts to change text
    def on_text_changed(self, buff):
        text = buff.get_text(buff.get_start_iter(), buff.get_end_iter())
        self.undo.remember(text, self.cursor_offset())

    def on_text_view_key_press_event(self, textview, event):
        if event.keyval == keyconst.F3:
            entry = self.search_entry
            self.search(entry.get_text())

    def on_text_view_key_release_event(self, textview, event):
        if event.keyval in (keyconst.ENTER, keyconst.SPACE):
            self.undo.snap()

    def on_text_view_move_cursor(self, textview, stepsize, count, extended):
        # snap off undo timeout on any keyboard cursor navigation
        self.undo.snap()
    
    def on_text_view_button_press_event(self, textview, event):
        # snap off undo timeout on any mouse click
        self.undo.snap()

    # Called when the user clicks the 'New' menu. We need to prompt for save if 
    # the file has been modified, and then delete the buffer and clear the  
    # modified flag.    
    def on_new_menu_item_activate(self, menuitem, data=None):
    
        if self.check_for_save(): self.on_save_menu_item_activate(None, None)
        
        # clear editor for a new file
        buff = self.text_view.get_buffer()
        buff.set_text("")
        buff.set_modified(False)
        self.filename = None
        self.reset_default_status()
        self.undo.reset("")
    
    # Called when the user clicks the 'Open' menu. We need to prompt for save if 
    # thefile has been modified, allow the user to choose a file to open, and 
    # then call load_file() on that file.    
    def on_open_menu_item_activate(self, menuitem, data=None):
        if self.check_for_save(): self.on_save_menu_item_activate(None, None)
        
        filename = self.get_open_filename()
        if filename: self.load_file(filename)

    # Called when the user clicks on a name in the Recent submenu. 
    def on_recent_menu_item_activate(self, menuitem, filename):
        if self.check_for_save(): self.on_save_menu_item_activate(None, None)
        
        self.load_file(filename)
       
    # Called when the user clicks the 'Save' menu. We need to allow the user to choose 
    # a file to save if it's an untitled document, and then call write_file() on that 
    # file.
    def on_save_menu_item_activate(self, menuitem, data=None):
        
        if self.filename == None: 
            filename = self.get_save_filename()
            if filename: self.write_file(filename)
        else: self.write_file(None)
        
    # Called when the user clicks the 'Save As' menu. We need to allow the user 
    # to choose a file to save and then call write_file() on that file.
    def on_save_as_menu_item_activate(self, menuitem, data=None):
        
        filename = self.get_save_filename()
        if filename: self.write_file(filename)
    
    # Called when the user clicks the 'Quit' menu. We need to prompt for save if 
    # the file has been modified and then break out of the GTK+ main loop          
    def on_quit_menu_item_activate(self, menuitem, data=None):
    
        if self.check_for_save(): self.on_save_menu_item_activate(None, None)
        self.cleanup()

    # Called when the user clicks the 'Undo' menu.
    def on_undo_menu_item_activate(self, menuitem, data=None):
        buff = self.text_view.get_buffer()
        (text, offset) = self.undo.pop()
        if text is not None:
            self.undo.pause = True
            buff.set_text(text)
            self.move_cursor_to_offset(offset)
            self.undo.pause = False

    # Called when the user clicks the 'Redo' menu.
    def on_redo_menu_item_activate(self, menuitem, data=None):
        buff = self.text_view.get_buffer()
        (text, offset) = self.undo.redo()
        if text is not None:
            self.undo.pause = True
            buff.set_text(text)
            self.move_cursor_to_offset(offset)
            self.undo.pause = False

    # Called when the user clicks the 'Cut' menu.
    def on_cut_menu_item_activate(self, menuitem, data=None):

        buff = self.text_view.get_buffer()
        buff.cut_clipboard (gtk.clipboard_get(), True)
        
    # Called when the user clicks the 'Copy' menu.    
    def on_copy_menu_item_activate(self, menuitem, data=None):
    
        buff = self.text_view.get_buffer()
        buff.copy_clipboard (gtk.clipboard_get())
    
    # Called when the user clicks the 'Paste' menu.    
    def on_paste_menu_item_activate(self, menuitem, data=None):
    
        buff = self.text_view.get_buffer()
        buff.paste_clipboard (gtk.clipboard_get(), None, True)
    
    # Called when the user clicks the 'Delete' menu.    
    def on_delete_menu_item_activate(self, menuitem, data=None):
        
        buff = self.text_view.get_buffer()
        buff.delete_selection (False, True)
    
    # Called when the user clicks the 'About' menu. We use gtk_show_about_dialog() 
    # which is a convenience function to show a GtkAboutDialog. This dialog will
    # NOT be modal but will be on top of the main application window.    
    def on_about_menu_item_activate(self, menuitem, data=None):
    
        if self.about_dialog: 
            self.about_dialog.present()
            return
        
        authors = self.authors

        about_dialog = gtk.AboutDialog()
        about_dialog.set_transient_for(self.window)
        about_dialog.set_destroy_with_parent(True)
        about_dialog.set_name(self.app_name)
        about_dialog.set_version(self.version_number)
        about_dialog.set_copyright(self.copyright)
        about_dialog.set_website(self.website)
        about_dialog.set_comments(self.description)
        about_dialog.set_authors(authors)
        about_dialog.set_logo_icon_name(gtk.STOCK_EDIT)
        
        # callbacks for destroying the dialog
        def close(dialog, response, editor):
            editor.about_dialog = None
            dialog.destroy()
            
        def delete_event(dialog, event, editor):
            editor.about_dialog = None
            return True
                    
        about_dialog.connect("response", close, self)
        about_dialog.connect("delete-event", delete_event, self)
        
        self.about_dialog = about_dialog
        about_dialog.show()

    def on_help_menu_item_activate(self, menuitem, data=None):
        buff = self.text_view.get_buffer()
        #Move beginning of selection
        cursor = buff.get_insert()
        iter = buff.get_iter_at_mark(cursor)
        (start, stop) = self.find_hspeak_token(iter)
        # Get the text
        text = buff.get_text(start, stop)
        self.show_context_help(text)
        # Actually move the cursor
        self.move_selection(start, stop)

    def on_search_activate(self, button, data=None):
        entry = self.search_entry
        self.search(entry.get_text())

    def on_find_menu_item_activate(self, menuitem, data=None):
        self.update_search_buttons()
        self.search_bar.show_all()
        self.search_entry.grab_focus()

    def on_search_hide_button_clicked(self, button, data=None):
        self.search_bar.hide_all()
    
    def on_search_backward_button_toggled(self, button, data=None):
        tog = button.get_active()
        status = self.search_status
        if tog:
            status.set_text("search backward.")
        else:
            status.set_text("search forward.")
        self.config.setboolean("search", "backward", tog)
        self.update_search_backward_button()
    
    def on_search_wrap_button_toggled(self, button, data=None):
        tog = button.get_active()
        status = self.search_status
        if tog:
            status.set_text("wrap search at the end of the document.")
        else:
            status.set_text("stop search at the end of the document.")
        self.config.setboolean("search", "wrap", tog)
        self.update_search_wrap_button()

    def on_search_case_button_toggled(self, button, data=None):
        tog = button.get_active()
        status = self.search_status
        if tog:
            status.set_text("case sensitive search.")
        else:
            status.set_text("case insensitive search.")
        self.config.setboolean("search", "case_sensitive", tog)
        self.update_search_case_button()

    def on_search_entry_key_release_event(self, textedit, event):
        if event.keyval == keyconst.ESC:
            self.search_bar.hide_all()
            self.text_view.grab_focus()

    def on_run_menu_item_activate(self, menuitem, data=None):
        if self.check_for_save():
            self.on_save_menu_item_activate(None, None)
        self.compile()

    def on_locate_compiler_menu_item_activate(self, menuitem, data=None):
        self.browse_for_hspeak()

    def on_locate_plotdict_menu_item_activate(self, menuitem, data=None):
        self.browse_for_plotdict_xml()
        self.plotdict_tree = None
        self.shortname_cache = None
    
    def on_toggle_console_menu_item_toggled(self, menuitem, data=None):
        state = menuitem.get_active()
        self.toggle_console(state)

    def on_help_ref_event(self, tag, widget, event, iter, data=None):
        if event.type == gtk.gdk.BUTTON_RELEASE:
            (start, stop) = self.find_hspeak_token(iter, True)
            if start is not None:
                buff = self.console.get_buffer()
                text = buff.get_text(start, stop, True)
                self.show_context_help(text)
                self.text_view.grab_focus()

    def on_help_index_menu_item_activate(self, menuitem, data=None):
        self.show_help_index()

    #-------------------------------------------------------------------
    
    # We call error_message() any time we want to display an error message to 
    # the user. It will both show an error dialog and log the error to the 
    # terminal window.
    def error_message(self, message):
    
        # log to terminal window
        print message
        
        # create an error message dialog and display modally to the user
        dialog = gtk.MessageDialog(None,
                                   gtk.DIALOG_MODAL | gtk.DIALOG_DESTROY_WITH_PARENT,
                                   gtk.MESSAGE_ERROR, gtk.BUTTONS_OK, message)
        
        dialog.run()
        dialog.destroy()
        
    # This function will check to see if the text buffer has been
    # modified and prompt the user to save if it has been modified.
    def check_for_save (self):
    
        ret = False
        buff = self.text_view.get_buffer()
        
        if buff.get_modified():

            # we need to prompt for save
            message = "Do you want to save the changes you have made?"
            dialog = gtk.MessageDialog(self.window,
                                       gtk.DIALOG_MODAL | gtk.DIALOG_DESTROY_WITH_PARENT,
                                       gtk.MESSAGE_QUESTION, gtk.BUTTONS_YES_NO, 
                                       message)
            dialog.set_title("Save?")
            
            if dialog.run() == gtk.RESPONSE_NO: ret = False
            else: ret = True
            
            dialog.destroy()
        
        return ret    
    
    def get_filename(self, window_caption, config_key, filters, gtk_file_chooser_action, gtk_stock_icon):
        
        filename = None
        chooser = gtk.FileChooserDialog(window_caption, self.window,
                                        gtk_file_chooser_action,
                                        (gtk.STOCK_CANCEL, gtk.RESPONSE_CANCEL, 
                                         gtk_stock_icon, gtk.RESPONSE_OK))
        # Get a reasonable default folder
        if is_windows():
            folder = os.path.join(os.environ["USERPROFILE"], "My Documents")
        else:
            folder = os.environ["HOME"]
        # ... unless of course we want to remember a previously stored default path
        if config_key is not None:
            folder = self.config.get("files", config_key)
        if folder is not None and os.path.isdir(folder):
            chooser.set_current_folder(folder)
        chooser.resize(640, 400)
        for filter in filters:
            chooser.add_filter(filter)
        
        response = chooser.run()
        if response == gtk.RESPONSE_OK:
            filename = chooser.get_filename()
            if config_key is not None:
                self.config.set("files", config_key, os.path.dirname(filename))
        chooser.destroy()
        
        return filename


    # We call get_open_filename() when we want to get a filename to open from the
    # user. It will present the user with a file chooser dialog and return the 
    # filename or None.    
    def get_open_filename(self):
        filename = self.get_filename("Open File...", "last_load_dir", self.file_filters,
                                 gtk.FILE_CHOOSER_ACTION_OPEN, gtk.STOCK_OPEN)
        if filename is not None:
            self.config.set("files", "last_save_dir", os.path.dirname(filename))
        return filename
    
    # We call get_save_filename() when we want to get a filename to save from the
    # user. It will present the user with a file chooser dialog and return the 
    # filename or None.    
    def get_save_filename(self):
        return self.get_filename("Save File...", "last_save_dir", self.file_filters,
                                 gtk.FILE_CHOOSER_ACTION_SAVE, gtk.STOCK_SAVE)
        
    # We call load_file() when we have a filename and want to load it into the 
    # buffer for the GtkTextView. The previous contents are overwritten.    
    def load_file(self, filename):
    
        # add Loading message to status bar and ensure GUI is current
        self.statusbar_push("Loading %s" % filename)
        while gtk.events_pending(): gtk.main_iteration()
        
        try:
            # get the file contents
            fin = open(filename, "r")
            text = fin.read()
            fin.close()
            
            # disable the text view while loading the buffer with the text
            self.text_view.set_sensitive(False)
            buff = self.text_view.get_buffer()
            buff.set_text(text)
            buff.set_modified(False)
            self.text_view.set_sensitive(True)
            
            # now we can set the current filename since loading was a success
            self.filename = filename
            
            
        except:
            # error loading file, show message to user
            self.error_message ("Could not open file: %s" % filename)
        else:
            # this stuff is done when the load succeeds.
            # Move the cursor to the top
            top_iter = buff.get_start_iter()
            self.move_cursor_to_offset(top_iter.get_offset())
            # reset the undo buffer
            self.undo.reset(text)
            # Save filename in the recent menu
            self.add_recent(filename)
        
        self.text_view.grab_focus()
        
        # clear loading status and restore default 
        self.statusbar_pop()
        self.reset_default_status()

    def write_file(self, filename):
    
        # add Saving message to status bar and ensure GUI is current
        if filename: 
            self.statusbar_push("Saving %s" % filename)
        else:
            self.statusbar_push("Saving %s" % self.filename)
            
        while gtk.events_pending(): gtk.main_iteration()
        
        try:
            # disable text view while getting contents of buffer
            buff = self.text_view.get_buffer()
            self.text_view.set_sensitive(False)
            text = buff.get_text(buff.get_start_iter(), buff.get_end_iter())
            self.text_view.set_sensitive(True)
            buff.set_modified(False)
            
            # set the contents of the file to the text from the buffer
            if filename: fout = open(filename, "w")
            else: fout = open(self.filename, "w")
            fout.write(text)
            fout.close()
            
            if filename: self.filename = filename

        except:
            # error writing file, show message to user
            self.error_message ("Could not save file: %s" % filename)
        
        # clear saving status and restore default     
        self.statusbar_pop()
        self.reset_default_status()
        
    def reset_default_status(self):
        
        if self.filename: status = "File: %s" % os.path.basename(self.filename)
        else: status = "File: (UNTITLED)"
        
        self.statusbar_pop()
        self.statusbar_push(status)

    # Run main application window
    def main(self):
        self.window.show()
        gtk.main()

# -----------------------------------------------------------------------------

_hspeak_separators = "\n,()[]{}^/*-+=<>&|$"
_hspeak_whitespace = "\t "

def _find_hspeak_token_start(char, data):
    (iter, use_ref_tags) = data
    if use_ref_tags:
        tag = iter.get_buffer().get_tag_table().lookup("ref")
        # First try the right side of the cursor
        fwd = iter.copy()
        fwd.forward_char()
        if fwd.begins_tag(tag):
            return True
    else:
        back = iter.copy()
        back.backward_char()
        char = back.get_char()
        if char in _hspeak_separators:
            return True
    return False

def _find_hspeak_token_stop(char, data):
    (iter, use_ref_tags) = data
    if use_ref_tags:
        tag = iter.get_buffer().get_tag_table().lookup("ref")
        if iter.ends_tag(tag):
            return True
    else:
        if char in _hspeak_separators + "#":
            return True
    return False

def _find_hspeak_non_whitespace(char, data):
    if char in _hspeak_whitespace:
        return False
    return True

# -----------------------------------------------------------------------------

class keyconst(object):
    ESC   = 65307
    ENTER = 65293
    SPACE = 32
    LEFT  = 65361
    UP    = 65362
    RIGHT = 65363
    DOWN  = 65364
    PGUP  = 65365
    PGDN  = 65365
    F3    = 65472

# -----------------------------------------------------------------------------

from datetime import datetime
from datetime import timedelta

class UndoManager(object):

    # Undo manager handles keeping an undo/redo history of the text buffer
    def __init__(self):
        self.minimim_levels = 3
        self.maximum_size = 1024 * 1000 
        self.merge_seconds = 1.5
        self.reset("")

    def reset(self, starting_text):
        self._history = [(starting_text, None)]
        self._redo = []
        self._one_char = False
        self.timestamp = None
        self.pause = False

    # Use to stop the undo system from combinging simple edits
    def snap(self):
        self.timestamp = None
        self._one_char = False

    def remember(self, text, offset):
        if self.pause:
            return
        self._redo = []
        if self.count() > 0:
            last_len = len(self._history[-1][0])
        else:
            last_len = 0
        if self.timestamp is not None:
          if self.timestamp + timedelta(seconds=self.merge_seconds) < datetime.now():
              self._one_char = False
        if abs(len(text) - last_len) == 1:
            # Only one char changed
            if self._one_char:
              # Last time was only one char too, so just update the last history push
              self.repush(text, offset)
            else:
              # Last time was a full push, so start push a new history entry
              self.push(text, offset)
            self._one_char = True
        else:
          self._one_char = False
          self.push(text, offset)
        self.__expire()
        self.timestamp = datetime.now()

    # Replace the last text on the stack
    def repush(self, text, offset):
        if len(self._history):
            self._history[-1] = (text, offset)
        else:
            self.push(text, offset)

    # Add new text to the stack
    def push(self, text, offset):
        entry = (text, offset)
        self._history.append(entry)

    # Throws the top of the stack to the redo buffer
    # and returns the next one down
    def pop(self):
        if self.count() == 0:
            return None
        if self.count() == 1:
            return self._history[0]
        self._redo.append(self._history[-1])
        self._history = self._history[:-1]
        return self._history[-1]

    # Pops and returns the top of the redo buffer (if possible)
    def redo(self):
        if len(self._redo) == 0:
            return (None, None)
        entry = self._redo[-1]
        (text, offset) = entry
        self.push(text, offset)
        self._redo = self._redo[:-1]
        return entry

    def size(self):
        n = 0
        for entry in self._history:
            (s, cursor) = entry
            n += len(s)
        return n

    def count(self):
        return len(self._history)

    # Remove old stuff from the undo buffer if it gets too big
    def __expire(self):
        # Always keep a minimum number of undo entries, even if they are gigantic
        if self.count() > self.minimim_levels:
            # If undo size is too large, expire the oldest one.
            if self.size() > self.maximum_size:
                self._history = self._history[1:]

    def __str__(self):
        return "(Undo:%d,%d)" % (self.count(), self.size())

# -----------------------------------------------------------------------------

import sys
import os
from ConfigParser import RawConfigParser

class ConfigManager(object):

    def __init__(self):
        self.parser = RawConfigParser()
        if is_windows():
            config_base = os.path.join(os.environ["USERPROFILE"], "Application Data")
            if not os.path.isdir(config_base):
                config_base = os.path.dirname(sys.argv[0])
                if config_base == "":
                    print "Unable to find config_base folder, sorry."
            self.config_dir = os.path.join(config_base, "HWhisper")
        else:
            config_base = os.environ["HOME"]
            self.config_dir = os.path.join(config_base, ".hwhisper")
        self.filename = os.path.join(self.config_dir, "hwhisper.ini")
    
    def load(self):
        self.parser.read(self.filename)
        
    def save(self):
        if not os.path.isdir(self.config_dir):
            os.mkdir(self.config_dir)
        f = open(self.filename, 'wb')
        self.parser.write(f)
        f.close()

    def make_section(self, section):
        if not self.parser.has_section(section):
            self.parser.add_section(section)

    def get(self, section, option, default=None):
        self.make_section(section)
        if not self.parser.has_option(section, option):
            return default
        return self.parser.get(section, option)

    def set(self, section, option, value):
        self.make_section(section)
        self.parser.set(section, option, value)

    def getboolean(self, section, option, default=False):
        self.make_section(section)
        if not self.parser.has_option(section, option):
            return default
        return self.parser.getboolean(section, option)

    def setboolean(self, section, option, value):
        self.make_section(section)
        if value:
            str = "yes"
        else:
            str = "no"
        self.parser.set(section, option, str)

    def getint(self, section, option, default=None):
        self.make_section(section)
        if not self.parser.has_option(section, option):
            return default
        return self.parser.getint(section, option)

    def get_list(self, section, option, separator):
        str = self.get(section, option, "")
        return str.split(separator)

    def set_list(self, section, option, separator, list):
        str = separator.join(list)
        self.set(section, option, str)

# -----------------------------------------------------------------------------

def is_windows():
  return sys.platform in ["win32", "cygwin"]

# -----------------------------------------------------------------------------
    
if __name__ == "__main__":
    editor = HWhisper()
    editor.main()
    
