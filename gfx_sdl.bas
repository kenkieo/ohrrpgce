''
'' gfx_sdl.bas - External graphics functions implemented in SDL
''
'' part of OHRRPGCE - see LICENCE.txt for GPL
''

option explicit

#include "crt.bi"
#include "gfx.bi"
#include "common.bi"
'#define NEED_SDL_GETENV
#include "SDL\SDL.bi"
/'
#ifdef __FB_WIN32__
'to load the window from resource file
include_windows_bi()
#endif
'/

EXTERN "C"

'why is this missing from crt.bi?
DECLARE FUNCTION putenv (byval as zstring ptr) as integer

'DECLARE FUNCTION SDL_putenv cdecl alias "SDL_putenv" (byval variable as zstring ptr) as integer
'DECLARE FUNCTION SDL_getenv cdecl alias "SDL_getenv" (byval name as zstring ptr) as zstring ptr

DECLARE FUNCTION gfx_sdl_set_screen_mode() as integer
DECLARE SUB gfx_sdl_update_screen()
DECLARE SUB update_state()
DECLARE FUNCTION update_mouse() as integer

DIM SHARED zoom AS INTEGER = 2
DIM SHARED smooth AS INTEGER = 0
DIM SHARED screensurface AS SDL_Surface PTR = NULL
DIM SHARED screenbuffer AS SDL_Surface PTR = NULL
DIM SHARED windowedmode AS INTEGER = -1
DIM SHARED rememmvis AS INTEGER = 1
DIM SHARED keystate AS Uint8 PTR = NULL
DIM SHARED sdljoystick AS SDL_Joystick PTR = NULL
DIM SHARED sdlpalette(0 TO 255) AS SDL_Color
DIM SHARED dest_rect AS SDL_Rect
DIM SHARED mouseclipped AS INTEGER = 0
DIM SHARED AS INTEGER mxmin = -1, mxmax = -1, mymin = -1, mymax = -1
DIM SHARED AS INTEGER privatemx, privatemy, lastmx, lastmy
DIM SHARED keybdstate(127) AS INTEGER  '"real"time keyboard array
DIM SHARED mouseclicks AS INTEGER

END EXTERN 'weirdness
'Translate SDL scancodes into a OHR scancodes
DIM SHARED scantrans(0 to 322) AS INTEGER
scantrans(SDLK_UNKNOWN) = 0
scantrans(SDLK_BACKSPACE) = 14
scantrans(SDLK_TAB) = 15
scantrans(SDLK_CLEAR) = 0
scantrans(SDLK_RETURN) = 28
scantrans(SDLK_PAUSE) = 0
scantrans(SDLK_ESCAPE) = 1
scantrans(SDLK_SPACE) = 57
scantrans(SDLK_EXCLAIM) = 2
scantrans(SDLK_QUOTEDBL) = 40
scantrans(SDLK_HASH) = 4
scantrans(SDLK_DOLLAR) = 5
scantrans(SDLK_AMPERSAND) = 8
scantrans(SDLK_QUOTE) = 40
scantrans(SDLK_LEFTPAREN) = 10
scantrans(SDLK_RIGHTPAREN) = 11
scantrans(SDLK_ASTERISK) = 9
scantrans(SDLK_PLUS) = 13
scantrans(SDLK_COMMA) = 51
scantrans(SDLK_MINUS) = 12
scantrans(SDLK_PERIOD) = 52
scantrans(SDLK_SLASH) = 53
scantrans(SDLK_0) = 11
scantrans(SDLK_1) = 2
scantrans(SDLK_2) = 3
scantrans(SDLK_3) = 4
scantrans(SDLK_4) = 5
scantrans(SDLK_5) = 6
scantrans(SDLK_6) = 7
scantrans(SDLK_7) = 8
scantrans(SDLK_8) = 9
scantrans(SDLK_9) = 10
scantrans(SDLK_COLON) = 39
scantrans(SDLK_SEMICOLON) = 39
scantrans(SDLK_LESS) = 51
scantrans(SDLK_EQUALS) = 13
scantrans(SDLK_GREATER) = 52
scantrans(SDLK_QUESTION) = 53
scantrans(SDLK_AT) = 3
scantrans(SDLK_LEFTBRACKET) = 26
scantrans(SDLK_BACKSLASH) = 43
scantrans(SDLK_RIGHTBRACKET) = 27
scantrans(SDLK_CARET) = 7
scantrans(SDLK_UNDERSCORE) = 12
scantrans(SDLK_BACKQUOTE) = 41
scantrans(SDLK_a) = 30
scantrans(SDLK_b) = 48
scantrans(SDLK_c) = 46
scantrans(SDLK_d) = 32
scantrans(SDLK_e) = 18
scantrans(SDLK_f) = 33
scantrans(SDLK_g) = 34
scantrans(SDLK_h) = 35
scantrans(SDLK_i) = 23
scantrans(SDLK_j) = 36
scantrans(SDLK_k) = 37
scantrans(SDLK_l) = 38
scantrans(SDLK_m) = 50
scantrans(SDLK_n) = 49
scantrans(SDLK_o) = 24
scantrans(SDLK_p) = 25
scantrans(SDLK_q) = 16
scantrans(SDLK_r) = 19
scantrans(SDLK_s) = 31
scantrans(SDLK_t) = 20
scantrans(SDLK_u) = 22
scantrans(SDLK_v) = 47
scantrans(SDLK_w) = 17
scantrans(SDLK_x) = 45
scantrans(SDLK_y) = 21
scantrans(SDLK_z) = 44
scantrans(SDLK_DELETE) = 83
scantrans(SDLK_KP0) = 82
scantrans(SDLK_KP1) = 79
scantrans(SDLK_KP2) = 80
scantrans(SDLK_KP3) = 81
scantrans(SDLK_KP4) = 75
scantrans(SDLK_KP5) = 76
scantrans(SDLK_KP6) = 77
scantrans(SDLK_KP7) = 71
scantrans(SDLK_KP8) = 72
scantrans(SDLK_KP9) = 73
scantrans(SDLK_KP_PERIOD) = 83
scantrans(SDLK_KP_DIVIDE) = 83
scantrans(SDLK_KP_MULTIPLY) = 55
scantrans(SDLK_KP_MINUS) = 74
scantrans(SDLK_KP_PLUS) = 78
scantrans(SDLK_KP_ENTER) = 28
scantrans(SDLK_KP_EQUALS) = 13
scantrans(SDLK_UP) = 72
scantrans(SDLK_DOWN) = 80
scantrans(SDLK_RIGHT) = 77
scantrans(SDLK_LEFT) = 75
scantrans(SDLK_INSERT) = 82
scantrans(SDLK_HOME) = 71
scantrans(SDLK_END) = 79
scantrans(SDLK_PAGEUP) = 73
scantrans(SDLK_PAGEDOWN) = 81
scantrans(SDLK_F1) = 59
scantrans(SDLK_F2) = 60
scantrans(SDLK_F3) = 61
scantrans(SDLK_F4) = 62
scantrans(SDLK_F5) = 63
scantrans(SDLK_F6) = 64
scantrans(SDLK_F7) = 65
scantrans(SDLK_F8) = 66
scantrans(SDLK_F9) = 67
scantrans(SDLK_F10) = 68
scantrans(SDLK_F11) = 87
scantrans(SDLK_F12) = 89
scantrans(SDLK_F13) = 0
scantrans(SDLK_F14) = 0
scantrans(SDLK_F15) = 0
scantrans(SDLK_NUMLOCK) = 69
scantrans(SDLK_CAPSLOCK) = 58
scantrans(SDLK_SCROLLOCK) = 70
scantrans(SDLK_RSHIFT) = 54
scantrans(SDLK_LSHIFT) = 42
scantrans(SDLK_RCTRL) = 29
scantrans(SDLK_LCTRL) = 29
scantrans(SDLK_RALT) = 56
scantrans(SDLK_LALT) = 56
scantrans(SDLK_RMETA) = 0
scantrans(SDLK_LMETA) = 0
scantrans(SDLK_LSUPER) = 0
scantrans(SDLK_RSUPER) = 0
scantrans(SDLK_MODE) = 0
scantrans(SDLK_COMPOSE) = 0
scantrans(SDLK_HELP) = 0
scantrans(SDLK_PRINT) = 0
scantrans(SDLK_SYSREQ) = 0
scantrans(SDLK_BREAK) = 0
scantrans(SDLK_MENU) = 0
scantrans(SDLK_POWER) = 0
scantrans(SDLK_EURO) = 0
scantrans(SDLK_UNDO) = 0
EXTERN "C"


FUNCTION gfx_sdl_init(byval terminate_signal_handler as sub cdecl (), byval windowicon as zstring ptr, byval info_buffer as zstring ptr, byval info_buffer_size as integer) as integer
/' Trying to load the resource as a SDL_Surface, Unfinished - the winapi has lost me
#ifdef __FB_WIN32__
  DIM as HBITMAP iconh
  DIM as BITMAP iconbmp
  iconh = cast(HBITMAP, LoadImage(NULL, windowicon, IMAGE_BITMAP, 0, 0, LR_CREATEDIBSECTION))
  GetObject(iconh, sizeof(iconbmp), @iconbmp);
#endif
'/
  'disable capslock/numlock/pause special keypress behaviour
  putenv("SDL_DISABLE_LOCK_KEYS=1") 'SDL 1.2.14
  putenv("SDL_NO_LOCK_KEYS=1")      'SDL SVN between 1.2.13 and 1.2.14

  IF SDL_WasInit(0) = 0 THEN
    DIM ver as SDL_version ptr = SDL_Linked_Version()
    *info_buffer = MID(", SDL " & ver->major & "." & ver->minor & "." & ver->patch, 1, info_buffer_size)
    IF SDL_Init(SDL_INIT_VIDEO) THEN
      *info_buffer = MID("Can't start SDL (video): " & *SDL_GetError & LINE_END & *info_buffer, 1, info_buffer_size)
      RETURN 0
    END IF
  ELSEIF SDL_WasInit(SDL_INIT_VIDEO) = 0 THEN
    IF SDL_InitSubSystem(SDL_INIT_VIDEO) THEN
      *info_buffer = MID("Can't start SDL video subsys: " & *SDL_GetError & LINE_END & *info_buffer, 1, info_buffer_size)
      RETURN 0
    END IF
  END IF
  RETURN gfx_sdl_set_screen_mode()
END FUNCTION

FUNCTION gfx_sdl_set_screen_mode() as integer
  DIM flags AS Uint32 = 0
  IF windowedmode = 0 THEN
    flags = flags OR SDL_FULLSCREEN
    SDL_ShowCursor(0)
  ELSE
    SDL_ShowCursor(rememmvis)
  END IF
  screensurface = SDL_SetVideoMode(320 * zoom, 200 * zoom, 0, flags)
  IF screensurface = NULL THEN
    debug "Failed to allocate display"
    RETURN 0
  END IF
  WITH dest_rect
    .x = 0
    .y = 0
    .w = 320 * zoom
    .h = 200 * zoom
  END WITH
  RETURN 1
END FUNCTION

SUB gfx_sdl_close()
  IF SDL_WasInit(SDL_INIT_VIDEO) THEN
    IF screenbuffer <> NULL THEN SDL_FreeSurface(screenbuffer)
    IF sdljoystick <> NULL THEN SDL_JoystickClose(sdljoystick)
    SDL_QuitSubSystem(SDL_INIT_VIDEO)
    IF SDL_WasInit(0) = 0 THEN
      SDL_Quit()
    END IF
  END IF
END SUB

FUNCTION gfx_sdl_getversion() as integer
  RETURN 1
END FUNCTION

SUB gfx_sdl_showpage(byval raw as ubyte ptr, byval w as integer, byval h as integer)
  'takes a pointer to raw 8-bit data at 320x200 (changing screen dimensions not supported yet)

  'We may either blit to screensurface (doing 8 bit -> display pixel format conversion) first
  'and then smoothzoom, with smoothzoomblit_anybit
  'Or smoothzoom first, with smoothzoomblit_8_to_8bit, and then blit to screensurface

  'unfinished variable resolution handling
  IF screenbuffer THEN
    IF screenbuffer->w <> w * zoom OR screenbuffer->h <> h * zoom THEN
      SDL_FreeSurface(screenbuffer)
      screenbuffer = NULL
    END IF
  END IF

  IF screenbuffer = NULL THEN
    screenbuffer = SDL_CreateRGBSurface(SDL_SWSURFACE, w * zoom, h * zoom, 8, 0,0,0,0)
  END IF
  'screenbuffer = SDL_CreateRGBSurfaceFrom(raw, w, h, 8, w, 0,0,0,0)
  IF screenbuffer = NULL THEN
    print "Failed to allocate page wrapping surface"
    SYSTEM
  END IF

  smoothzoomblit_8_to_8bit(raw, screenbuffer->pixels, w, h, screenbuffer->pitch, zoom, smooth)

  gfx_sdl_update_screen()
END SUB

SUB gfx_sdl_update_screen()
  IF screenbuffer <> NULL and screensurface <> NULL THEN
    SDL_SetColors(screenbuffer, @sdlpalette(0), 0, 256)
    SDL_BlitSurface(screenbuffer, NULL, screensurface, @dest_rect)
/'
    IF zoom > 1 THEN
      SDL_LockSurface(screensurface)

      DIM bpp AS INTEGER = screensurface->format->BytesPerPixel
      DIM destptr AS ANY PTR = screensurface->pixels + dest_rect.x + dest_rect.y * screensurface->pitch
      smoothzoomblit_anybit(destptr, destptr, dest_rect.w, dest_rect.h, zoom, 0, bpp, screensurface->pitch)

      SDL_UnlockSurface(screensurface)
    END IF
'/
    SDL_Flip(screensurface)
    update_state()
  END IF
END SUB

SUB gfx_sdl_setpal(byval pal as RGBcolor ptr)
  DIM i AS INTEGER
  FOR i = 0 TO 255
    sdlpalette(i).r = pal[i].r
    sdlpalette(i).g = pal[i].g
    sdlpalette(i).b = pal[i].b
  NEXT
  gfx_sdl_update_screen()
END SUB

FUNCTION gfx_sdl_screenshot(byval fname as zstring ptr) as integer
  gfx_sdl_screenshot = 0
END FUNCTION

SUB gfx_sdl_setwindowed(byval iswindow as integer)
  IF iswindow = 0 THEN
    windowedmode = 0
  ELSE
    windowedmode = -1
  END IF
  gfx_sdl_set_screen_mode()
END SUB

SUB gfx_sdl_windowtitle(byval title as zstring ptr)
  IF SDL_WasInit(SDL_INIT_VIDEO) then
    SDL_WM_SetCaption(title, title)
  END IF
END SUB

FUNCTION gfx_sdl_getwindowstate() as WindowState ptr
  STATIC state as WindowState
  DIM temp as integer = SDL_GetAppState()
  state.focused = (temp AND SDL_APPINPUTFOCUS) <> 0
  state.minimised = (temp AND SDL_APPACTIVE) = 0
  RETURN @state
END FUNCTION

FUNCTION gfx_sdl_setoption(byval opt as zstring ptr, byval arg as zstring ptr) as integer
  DIM ret as integer = 0
  DIM value as integer = str2int(*arg, -1)
  IF *opt = "zoom" or *opt = "z" THEN
    IF value >= 1 AND value <= 4 THEN
      zoom = value
      IF SDL_WasInit(SDL_INIT_VIDEO) THEN
        gfx_sdl_set_screen_mode()
      END IF
    END IF
    ret = 1
  ELSEIF *opt = "smooth" OR *opt = "s" THEN
    IF value = 1 OR value = -1 THEN  'arg optional (-1)
      smooth = 1
    ELSE
      smooth = 0
    END IF
    ret = 1
  END IF
  'globble numerical args even if invalid
  IF ret = 1 AND is_int(*arg) THEN ret = 2
  RETURN ret
END FUNCTION

FUNCTION gfx_sdl_describe_options() as zstring ptr
  return @"-z -zoom [1|2|3|4]  Scale screen to 1,2,3 or 4x normal size (2x default)" LINE_END _
          "-s -smooth          Enable smoothing filter for zoom modes (default off)"
END FUNCTION

SUB io_sdl_init
  'nothing needed at the moment...
END SUB

SUB gfx_sdl_process_events()
'The SDL event queue only holds 128 events, after which SDL_QuitEvents will be lost
'Of course, we might actually like to do something with some of the other events
  DIM evnt as SDL_Event

  WHILE SDL_PeepEvents(@evnt, 1, SDL_GETEVENT, SDL_ALLEVENTS)
    SELECT CASE evnt.type
      CASE SDL_EXIT
        post_terminate_signal
      CASE SDL_KEYDOWN
        IF evnt.key.keysym.mod_ AND KMOD_ALT THEN
          IF evnt.key.keysym.sym = SDLK_RETURN THEN  'alt-enter (not processed normally when using SDL)
            gfx_sdl_setwindowed(windowedmode XOR -1)
          END IF
          IF evnt.key.keysym.sym = SDLK_F4 THEN  'alt-F4
            post_terminate_signal
          END IF
        END IF
        DIM AS INTEGER key = scantrans(evnt.key.keysym.sym)
        IF key THEN keybdstate(key) = 7
      CASE SDL_KEYUP
        DIM AS INTEGER key = scantrans(evnt.key.keysym.sym)
        IF key THEN keybdstate(key) AND= NOT 1
      CASE SDL_MOUSEBUTTONDOWN
        'note SDL_GetMouseState is still used, while SDL_GetKeyState isn't
        mouseclicks OR= 1 SHL evnt.button.button
      CASE SDL_ACTIVEEVENT
        'debug "SDL_ACTIVEEVENT " & evnt.active.state
        IF evnt.active.state AND SDL_APPINPUTFOCUS THEN 
          IF evnt.active.gain = 0 THEN
            SDL_ShowCursor(1)
            IF mouseclipped = 1 THEN
              SDL_WarpMouse privatemx, privatemy
              SDL_PumpEvents
            END IF
          ELSE
            IF windowedmode THEN
              SDL_ShowCursor(rememmvis)
            ELSE
              SDL_ShowCursor(0)
            END IF
            IF mouseclipped = 1 THEN
              SDL_GetMouseState(@privatemx, @privatemy)
              lastmx = privatemx
              lastmy = privatemy
              'SDL_WarpMouse screensurface->w \ 2, screensurface->h \ 2
              'SDL_PumpEvents
              'lastmx = screensurface->w \ 2
              'lastmy = screensurface->h \ 2
            END IF
          END IF
        END IF
      'CASE SDL_VIDEORESIZE
        'debug "SDL_VIDEORESIZE: w=" & evnt.resize.w & " h=" & evnt.resize.h
    END SELECT
  WEND
END SUB

'may only be called from the main thread
SUB update_state()
  SDL_PumpEvents()
  update_mouse()
  gfx_sdl_process_events()
END SUB

SUB io_sdl_pollkeyevents()
  'might need to redraw the screen if exposed
  SDL_Flip(screensurface)
  update_state()
END SUB

SUB io_sdl_waitprocessing()
  update_state()
END SUB

SUB io_sdl_keybits (keybdarray as integer ptr)
  FOR a AS INTEGER = 0 TO &h7f
    keybdarray[a] = keybdstate(a)
    keybdstate(a) = keybdstate(a) and 1
  NEXT
END SUB

SUB io_sdl_updatekeys(byval keybd as integer ptr)
  'supports io_keybits instead
END SUB

SUB io_sdl_setmousevisibility(byval visible as integer)
  rememmvis = iif(visible, 1, 0)
  SDL_ShowCursor(iif(windowedmode, rememmvis, 0))
END SUB

'Change from SDL to OHR mouse button numbering (swap middle and right)
FUNCTION fix_buttons(byval buttons as integer)
  DIM mbuttons as integer = 0
  IF SDL_BUTTON(SDL_BUTTON_LEFT) AND buttons THEN mbuttons = mbuttons OR 1
  IF SDL_BUTTON(SDL_BUTTON_RIGHT) AND buttons THEN mbuttons = mbuttons OR 2
  IF SDL_BUTTON(SDL_BUTTON_MIDDLE) AND buttons THEN mbuttons = mbuttons OR 4
  RETURN mbuttons
END FUNCTION

FUNCTION update_mouse() as integer
  DIM x AS INTEGER
  DIM y AS INTEGER
  DIM buttons AS Uint8

  buttons = SDL_GetMouseState(@x, @y)
  IF SDL_GetAppState() AND SDL_APPINPUTFOCUS THEN
    IF mouseclipped THEN
      'Not moving the mouse back to the centre of the window rapidly is widely recommended, but I haven't seen (nor looked for) evidence that it's bad.
      'Implemented only due to attempting to fix eventually unrelated problem. Possibly beneficial to keep
      'debug "mousestate " & x & " " & y & " (" & lastmx & " " & lastmy & ")"
      privatemx += x - lastmx
      privatemy += y - lastmy
      IF x < 3 * screensurface->w \ 8 OR x > 5 * screensurface->w \ 8 OR _
         y < 3 * screensurface->h \ 8 OR y > 5 * screensurface->h \ 8 THEN
        SDL_WarpMouse screensurface->w \ 2, screensurface->h \ 2
        'Required after warping the mouse for it to take effect. Discovered with much blood, sweat, and murderous rage
        SDL_PumpEvents
        lastmx = screensurface->w \ 2
        lastmy = screensurface->h \ 2
        'debug "warped"
      ELSE
        lastmx = x
        lastmy = y
      END IF
      privatemx = bound(privatemx, mxmin, mxmax)
      privatemy = bound(privatemy, mymin, mymax)
    ELSE
      privatemx = x
      privatemy = y
    END IF
  END IF
  RETURN buttons
END FUNCTION

SUB io_sdl_mousebits (byref mx as integer, byref my as integer, byref mwheel as integer, byref mbuttons as integer, byref mclicks as integer)
  DIM buttons as integer
  buttons = update_mouse()
  mx = privatemx \ zoom
  my = privatemy \ zoom

  mclicks = fix_buttons(mouseclicks)
  mbuttons = fix_buttons(buttons or mouseclicks)
  mouseclicks = 0
END SUB

SUB io_sdl_getmouse(mx as integer, my as integer, mwheel as integer, mbuttons as integer)
  'supports io_mousebits instead
END SUB

SUB io_sdl_setmouse(byval x as integer, byval y as integer)
  IF mouseclipped THEN
    privatemx = x * zoom
    privatemy = y * zoom
    'IF SDL_GetAppState() AND SDL_APPINPUTFOCUS THEN
    '  SDL_WarpMouse screensurface->w \ 2, screensurface->h \ 2
    'END IF
  ELSE
    IF SDL_GetAppState() AND SDL_APPINPUTFOCUS THEN
      SDL_WarpMouse x * zoom, y * zoom
      SDL_PumpEvents
    END IF
  END IF
END SUB

SUB io_sdl_mouserect(byval xmin as integer, byval xmax as integer, byval ymin as integer, byval ymax as integer)
  IF mouseclipped = 0 AND (xmin >= 0) THEN
    'enter clipping mode
    'SDL_WM_GrabInput causes most WM key combinations to be blocked, which I find unacceptable, so instead
    'we stick the mouse at the centre of the window. It's a very common hack.
    mouseclipped = 1
    SDL_GetMouseState(@privatemx, @privatemy)
    IF SDL_GetAppState() AND SDL_APPINPUTFOCUS THEN
      SDL_WarpMouse screensurface->w \ 2, screensurface->h \ 2
      SDL_PumpEvents
    END IF
    lastmx = screensurface->w \ 2
    lastmy = screensurface->h \ 2
  ELSEIF mouseclipped = 1 AND (xmin = -1) THEN
    'exit clipping mode
    mouseclipped = 0
    SDL_WarpMouse privatemx, privatemy
  END IF
  mxmin = xmin * zoom
  mxmax = xmax * zoom + zoom - 1
  mymin = ymin * zoom
  mymax = ymax * zoom + zoom - 1
END SUB

FUNCTION io_sdl_readjoysane(byval joynum as integer, byref button as integer, byref x as integer, byref y as integer) as integer
  'FIXME: only bothers to support the first joystick
  IF SDL_NumJoysticks() = 0 THEN RETURN 0
  IF sdljoystick = NULL THEN
    sdljoystick = SDL_JoystickOpen(0)
  END IF
  SDL_JoystickUpdate() 'should this be here? moved from io_sdl_readjoy
  button = 0
  IF SDL_JoystickGetButton(sdljoystick, 0) THEN button = button AND 1
  IF SDL_JoystickGetButton(sdljoystick, 1) THEN button = button AND 2
  x = SDL_JoystickGetAxis(sdljoystick, 0)
  y = SDL_JoystickGetAxis(sdljoystick, 1)
END FUNCTION

FUNCTION gfx_sdl_setprocptrs() as integer
  gfx_close = @gfx_sdl_close
  gfx_getversion = @gfx_sdl_getversion
  gfx_showpage = @gfx_sdl_showpage
  gfx_setpal = @gfx_sdl_setpal
  gfx_screenshot = @gfx_sdl_screenshot
  gfx_setwindowed = @gfx_sdl_setwindowed
  gfx_windowtitle = @gfx_sdl_windowtitle
  gfx_getwindowstate = @gfx_sdl_getwindowstate
  gfx_setoption = @gfx_sdl_setoption
  gfx_describe_options = @gfx_sdl_describe_options
  io_init = @io_sdl_init
  io_pollkeyevents = @io_sdl_pollkeyevents
  io_waitprocessing = @io_sdl_waitprocessing
  io_keybits = @io_sdl_keybits
  io_updatekeys = @io_sdl_updatekeys
  io_mousebits = @io_sdl_mousebits
  io_setmousevisibility = @io_sdl_setmousevisibility
  io_getmouse = @io_sdl_getmouse
  io_setmouse = @io_sdl_setmouse
  io_mouserect = @io_sdl_mouserect
  io_readjoysane = @io_sdl_readjoysane

  RETURN 1
END FUNCTION

END EXTERN
