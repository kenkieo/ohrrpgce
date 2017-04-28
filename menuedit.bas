'OHRRPGCE CUSTOM - The Menus Editor (not to be confused with menu slices editors)
'(C) Copyright 1997-2017 James Paige and Hamster Republic Productions
'Please read LICENSE.txt for GPL License details and disclaimer of liability

#include "config.bi"
#include "allmodex.bi"
#include "common.bi"
#include "customsubs.bi"
#include "cglobals.bi"
#include "scrconst.bi"
#include "sliceedit.bi"

'--Local SUBs
DECLARE SUB update_menu_editor_menu(byval record as integer, edmenu as MenuDef, menu as MenuDef)
DECLARE SUB update_detail_menu(detail as MenuDef, mi as MenuDefItem)
DECLARE SUB menu_editor_keys (state as MenuState, mstate as MenuState, menudata as MenuDef, byref record as integer, menu_set as MenuSet)
DECLARE SUB menu_editor_menu_keys (mstate as MenuState, dstate as MenuState, menudata as MenuDef, byval record as integer)
DECLARE SUB menu_editor_detail_keys(dstate as MenuState, mstate as MenuState, detail as MenuDef, mi as MenuDefItem)


SUB menu_editor ()

DIM menu_set as MenuSet
menu_set.menufile = workingdir & SLASH & "menus.bin"
menu_set.itemfile = workingdir & SLASH & "menuitem.bin"

DIM record as integer = 0

DIM state as MenuState 'top level
state.active = YES
state.need_update = YES
DIM mstate as MenuState 'menu
mstate.active = NO
mstate.need_update = YES
DIM dstate as MenuState 'detail state
dstate.active = NO

DIM edmenu as MenuDef
ClearMenuData edmenu
WITH edmenu
 .textalign = alignLeft
 .alignhoriz = alignLeft
 .alignvert = alignTop
 .anchorhoriz = alignLeft
 .anchorvert = alignTop
 .boxstyle = 3
 .translucent = YES
 .min_chars = 38
END WITH
DIM menudata as MenuDef
LoadMenuData menu_set, menudata, record
DIM detail as MenuDef
ClearMenuData detail
WITH detail
 .textalign = alignLeft
 .anchorhoriz = alignLeft
 .anchorvert = alignBottom
 .offset.x = -152
 .offset.y = 92
 .min_chars = 36
END WITH

DIM box_preview as string = ""

setkeys YES
DO
 setwait 55
 setkeys YES
 
 IF state.active = NO THEN EXIT DO
 IF mstate.active = YES THEN
  menu_editor_menu_keys mstate, dstate, menudata, record
 ELSEIF dstate.active = YES THEN
  menu_editor_detail_keys dstate, mstate, detail, *menudata.items[mstate.pt]
 ELSE
  menu_editor_keys state, mstate, menudata, record, menu_set
 END IF
 
 IF state.need_update THEN
  state.need_update = NO
  update_menu_editor_menu record, edmenu, menudata
  init_menu_state state, edmenu
  init_menu_state mstate, menudata
 END IF
 IF mstate.need_update THEN
  mstate.need_update = NO
  init_menu_state mstate, menudata
 END IF
 IF dstate.need_update THEN
  dstate.need_update = NO
  update_detail_menu detail, *menudata.items[mstate.pt]
  init_menu_state dstate, detail
  WITH *menudata.items[mstate.pt]
   IF .t = mtypeTextBox THEN
    box_preview = textbox_preview_line(.sub_t)
   END IF
  END WITH
 END IF
 
 clearpage dpage
 IF NOT mstate.active THEN draw_menu menudata, mstate, dpage
 IF NOT mstate.active AND NOT dstate.active THEN draw_menu edmenu, state, dpage
 IF mstate.active THEN
  draw_menu menudata, mstate, dpage
  edgeprint "ENTER to edit, Shift+Arrows to re-order", 0, pBottom, uilook(uiDisabledItem), dpage
  IF record = 0 THEN
   edgeprint "CTRL+R to reload default", 0, pBottom - 10, uilook(uiDisabledItem), dpage
  END IF
 END IF
 IF dstate.active THEN
  draw_menu detail, dstate, dpage
  IF menudata.items[mstate.pt]->t = 3 THEN '--textbox
   edgeprint box_preview, 0, pBottom, uilook(uiText), dpage
  END IF
 END IF
 
 SWAP vpage, dpage
 setvispage vpage
 dowait
LOOP
SaveMenuData menu_set, menudata, record
ClearMenuData edmenu
ClearMenuData menudata
ClearMenuData detail

END SUB

SUB menu_editor_keys (state as MenuState, mstate as MenuState, menudata as MenuDef, byref record as integer, menu_set as MenuSet)
 IF keyval(scESC) > 1 THEN state.active = NO
 IF keyval(scF1) > 1 THEN show_help "menu_editor_main"
 
 usemenu state
 
 SELECT CASE state.pt
  CASE 0
   IF enter_space_click(state) THEN
    state.active = NO
   END IF
  CASE 1
   DIM saverecord as integer = record
   IF intgrabber_with_addset(record, 0, gen(genMaxMenu), 32767, "menu") THEN
    IF record > gen(genMaxMenu) THEN gen(genMaxMenu) = record
    SaveMenuData menu_set, menudata, saverecord
    LoadMenuData menu_set, menudata, record
    state.need_update = YES
    mstate.need_update = YES
   END IF
  CASE 2
   IF strgrabber(menudata.name, 20) THEN state.need_update = YES
  CASE 3
   IF enter_space_click(state) THEN
    mstate.active = YES
    mstate.need_update = YES
    menudata.edit_mode = YES
    append_menu_item menudata, "[NEW MENU ITEM]"
   END IF
  CASE 4
   IF intgrabber(menudata.boxstyle, 0, 14) THEN state.need_update = YES
  CASE 5
   IF intgrabber(menudata.textcolor, 0, 255) THEN state.need_update = YES
   IF enter_space_click(state) THEN
    menudata.textcolor = color_browser_256(menudata.textcolor)
    state.need_update = YES
   END IF
  CASE 6
   IF intgrabber(menudata.maxrows, 0, 20) THEN state.need_update = YES
  CASE 7
   IF enter_space_click(state) THEN
    edit_menu_bits menudata
    state.need_update = YES
   END IF
  CASE 8
   IF enter_space_click(state) THEN
    reposition_menu menudata, mstate
   END IF
  CASE 9
   IF enter_space_click(state) THEN
    reposition_anchor menudata, mstate
   END IF
  CASE 10 ' text align
   IF intgrabber(menudata.textalign, alignLeft, alignRight) THEN state.need_update = YES
  CASE 11 ' Minimum width in chars
   IF intgrabber(menudata.min_chars, 0, 38) THEN state.need_update = YES
  CASE 12 ' Maximum width in chars
   IF intgrabber(menudata.max_chars, 0, 38) THEN state.need_update = YES
  CASE 13 ' border size
   IF intgrabber(menudata.bordersize, -100, 100) THEN state.need_update = YES
  CASE 14 ' item spacing
   IF intgrabber(menudata.itemspacing, -10, 100) THEN state.need_update = YES
  CASE 15: ' on-close script
   IF enter_space_click(state) THEN
    scriptbrowse menudata.on_close, plottrigger, "menu on-close plotscript"
    state.need_update = YES
   END IF
   IF scrintgrabber(menudata.on_close, 0, 0, scLeft, scRight, 1, plottrigger) THEN state.need_update = YES
  CASE 16: ' esc menu
   IF zintgrabber(menudata.esc_menu, -1, gen(genMaxMenu)) THEN state.need_update = YES
 END SELECT
END SUB

SUB menu_editor_menu_keys (mstate as MenuState, dstate as MenuState, menudata as MenuDef, byval record as integer)
 DIM i as integer
 DIM elem as integer

 IF keyval(scESC) > 1 THEN
  mstate.active = NO
  menudata.edit_mode = NO
  mstate.need_update = YES
  'remove [NEW MENU ITEM]
  remove_menu_item menudata, menudata.last
  EXIT SUB
 END IF
 IF keyval(scF1) > 1 THEN show_help "menu_editor_items"

 usemenu mstate
 IF mstate.pt >= 0 AND mstate.pt < menudata.numitems THEN
 WITH *menudata.items[mstate.pt]
  IF NOT (menudata.edit_mode = YES AND .trueorder.next = NULL) THEN  'not the last item, "NEW MENU ITEM"
   strgrabber .caption, 38
   IF keyval(scEnter) > 1 THEN '--Enter
    mstate.active = NO
    dstate.active = YES
    dstate.need_update = YES
   END IF
   IF keyval(scDelete) > 1 THEN '-- Delete
    IF yesno("Delete this menu item?", NO) THEN
     remove_menu_item menudata, mstate.pt
     mstate.need_update = YES
    END IF
   END IF
   IF keyval(scLeftShift) > 0 OR keyval(scRightShift) > 0 THEN '--holding Shift
    IF keyval(scUp) > 1 AND mstate.pt < mstate.last - 1 THEN ' just went up
     'NOTE: Cursor will have already moved because of usemenu call above
     swap_menu_items menudata, mstate.pt, menudata, mstate.pt + 1
     mstate.need_update = YES
    END IF
    IF keyval(scDown) > 1 AND mstate.pt > mstate.first THEN ' just went down
     'NOTE: Cursor will have already moved because of usemenu call above
     swap_menu_items menudata, mstate.pt, menudata, mstate.pt - 1
     mstate.need_update = YES
    END IF
   END IF
  ELSE
   IF menudata.edit_mode = YES THEN
    'Selecting the item that appends new items
    IF enter_space_click(mstate) THEN
     menudata.last->caption = ""
     append_menu_item menudata, "[NEW MENU ITEM]"
     mstate.active = NO
     mstate.need_update = YES
     dstate.active = YES
     dstate.need_update = YES
    END IF
   END IF
  END IF
 END WITH
 END IF' above block only runs with a valid mstate.pt

 IF record = 0 THEN
  IF keyval(scCtrl) > 0 AND keyval(scR) > 1 THEN
   IF yesno("Reload the default main menu?") THEN
    ClearMenuData menudata
    create_default_menu menudata
    append_menu_item menudata, "[NEW MENU ITEM]"
    mstate.need_update = YES
   END IF
  END IF
 END IF
 
END SUB

SUB menu_editor_detail_keys(dstate as MenuState, mstate as MenuState, detail as MenuDef, mi as MenuDefItem)
 DIM max as integer

 IF keyval(scESC) > 1 THEN
  dstate.active = NO
  mstate.active = YES
  EXIT SUB
 END IF
 IF keyval(scF1) > 1 THEN show_help "menu_editor_item_details"

 usemenu dstate

 SELECT CASE dstate.pt
  CASE 0
   IF enter_space_click(dstate) THEN
    dstate.active = NO
    mstate.active = YES
    EXIT SUB
   END IF
  CASE 1: 'caption
   IF strgrabber(mi.caption, 38) THEN
    dstate.need_update = YES
   END IF
  CASE 2: 'type
   IF intgrabber(mi.t, 0, mtypeLAST) THEN
    mi.sub_t = 0
    dstate.need_update = YES
   END IF
  CASE 3:
   SELECT CASE mi.t
    CASE mtypeCaption:
     max = 1
    CASE mtypeSpecial
     max = spLAST
    CASE mtypeMenu
     max = gen(genMaxMenu)
    CASE mtypeTextBox
     max = gen(genMaxTextBox)
   END SELECT
   IF mi.t = mtypeScript THEN
    IF scrintgrabber(mi.sub_t, 0, 0, scLeft, scRight, 1, plottrigger) THEN dstate.need_update = YES
    IF enter_space_click(dstate) THEN
     scriptbrowse mi.sub_t, plottrigger, "Menu Item Script"
     dstate.need_update = YES
    END IF
   ELSE
    IF intgrabber(mi.sub_t, 0, max) THEN dstate.need_update = YES
   END IF
  CASE 4: 'conditional tag1
   IF tag_grabber(mi.tag1) THEN dstate.need_update = YES
  CASE 5: 'conditional tag2
   IF tag_grabber(mi.tag2) THEN dstate.need_update = YES
  CASE 6: 'set tag
   IF tag_grabber(mi.settag, , , NO) THEN dstate.need_update = YES
  CASE 7: 'toggle tag
   IF tag_grabber(mi.togtag, 0, , NO) THEN dstate.need_update = YES
  CASE 8: ' bitsets
   IF enter_space_click(dstate) THEN
    edit_menu_item_bits mi
   END IF
  CASE 9 TO 11:
   IF intgrabber(mi.extra(dstate.pt - 9), -32767, 32767) THEN dstate.need_update = YES
 END SELECT

END SUB

SUB update_menu_editor_menu(byval record as integer, edmenu as MenuDef, menu as MenuDef)
 DIM cap as string
 DeleteMenuItems edmenu
 
 append_menu_item edmenu, "Previous Menu"
 
 cap = "Menu " & record
 IF record = 0 THEN cap = cap & " (MAIN MENU)"
 append_menu_item edmenu, cap
 
 append_menu_item edmenu, "Name: " & menu.name
 append_menu_item edmenu, "Edit Items..."
 append_menu_item edmenu, "Box Style: " & menu.boxstyle
 append_menu_item edmenu, "Text color: " & zero_default(menu.textcolor)
 append_menu_item edmenu, "Max rows to display: " & zero_default(menu.maxrows)
 append_menu_item edmenu, "Edit Bitsets..."
 append_menu_item edmenu, "Reposition menu..."
 append_menu_item edmenu, "Change Anchor Point..."
 append_menu_item edmenu, "Text Align: " & HorizCaptions(menu.textalign)
 append_menu_item edmenu, "Minimum width: " & zero_default(menu.min_chars, "Automatic")
 append_menu_item edmenu, "Maximum width: " & zero_default(menu.max_chars, "None")
 append_menu_item edmenu, "Border size: " & zero_default(menu.bordersize)
 append_menu_item edmenu, "Item spacing: " & zero_default(menu.itemspacing)
 append_menu_item edmenu, "On-close script: " & scriptname(menu.on_close)
 IF menu.esc_menu = 0 THEN
  cap = "just closes this menu"
 ELSE
  cap = "switch to menu " & menu.esc_menu - 1 & " " & getmenuname(menu.esc_menu - 1)
 END IF
 IF menu.no_close THEN cap = "disabled by bitset"
 append_menu_item edmenu, "Cancel button: " & cap
END SUB

SUB update_detail_menu(detail as MenuDef, mi as MenuDefItem)
 DIM i as integer
 DIM cap as string
 DIM index as integer
 DeleteMenuItems detail
 
 append_menu_item detail, "Go Back"
 
 cap = mi.caption
 IF LEN(cap) = 0 THEN cap = "[DEFAULT]"
 append_menu_item detail, "Caption: " & cap
 
 append_menu_item(detail, "Type")
 WITH *detail.last
  SELECT CASE mi.t
   CASE mtypeCaption
    .caption = "Type: " & mi.t & " Caption"
   CASE mtypeSpecial
    .caption = "Type: " & mi.t & " Special screen"
   CASE mtypeMenu
    .caption = "Type: " & mi.t & " Go to Menu"
   CASE mtypeTextBox
    .caption = "Type: " & mi.t & " Show text box"
   CASE mtypeScript
    .caption = "Type: " & mi.t & " Run script"
  END SELECT
 END WITH
 
 append_menu_item(detail, "Subtype: " & mi.sub_t)
 WITH *detail.last
  SELECT CASE mi.t
   CASE mtypeCaption
    SELECT CASE mi.sub_t
     CASE 0: .caption = .caption & " Selectable"
     CASE 1: .caption = .caption & " Not Selectable"
    END SELECT
   CASE mtypeSpecial
    .caption = .caption & " " & get_special_menu_caption(mi.sub_t)
   CASE mtypeMenu
    .caption = .caption & " " & getmenuname(mi.sub_t)
   CASE mtypeScript
    .caption = "Subtype: " & scriptname(mi.sub_t)
   CASE ELSE
    .caption = "Subtype: " & mi.sub_t
  END SELECT
  .caption &= get_menu_item_editing_annotation(mi)
 END WITH
 
 append_menu_item detail, tag_condition_caption(mi.tag1, "Enable if tag", "Always")
 append_menu_item detail, tag_condition_caption(mi.tag2, " and also tag", "Always")
 append_menu_item detail, tag_set_caption(mi.settag, "Set tag")
 append_menu_item detail, tag_toggle_caption(mi.togtag)
 append_menu_item detail, "Edit Bitsets..."
 FOR i = 0 TO 2
  append_menu_item detail, "Extra data " & i & ": " & mi.extra(i)
 NEXT i
END SUB