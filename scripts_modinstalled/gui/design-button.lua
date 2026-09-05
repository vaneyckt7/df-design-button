-- Adds a clickable gui/design button to the vanilla dig toolbar.
--@ module = true
--[====[
gui/design-button
=================
Adds a button to the vanilla dig designation toolbar that opens `gui/design`,
so shape-based digging can be reached by pointing and clicking. This is aimed
at the Steam Deck, where there is no keyboard.

The button sits immediately to the left of the vanilla dig icons. Hovering over
it shows a popup describing what it does. Click it, or press
:kbd:`Ctrl`:kbd:`g`, to close the dig submenu and open `gui/design`. Close
that window with :kbd:`Esc`, or with a right click once nothing is in progress.
(The first right click is spent by `gui/design` closing its help window or
cancelling a drag.)

While `gui/design` is up, the word ``Design`` replaces the designation mode in
the top-left banner. That part needs graphics mode. The banner is replayed from
a snapshot of its sprites, and ASCII mode has no sprites to snapshot, so there
the banner area is simply left empty. The button itself works in either mode.

Enabling and disabling
----------------------
This tool is a single overlay widget, so it has no command of its own and
nothing needs to be added to an autostart list. Toggle it on the Overlays tab
of `gui/control-panel`, or from the console::

    overlay enable gui/design-button.button
    overlay disable gui/design-button.button

The setting is written to ``dfhack-config/overlay.json`` and is restored every
time DFHack starts. It defaults to enabled.

The widget is registered against the ``dwarfmode`` viewscreen, not the dig
toolbar's own focus strings. Opening `gui/design` clears the designation mode,
which takes those focus strings away. The button and its
popup are shown only while the dig toolbar is actually up.

]====]

local gui = require('gui')
local overlay = require('plugins.overlay')
local widgets = require('gui.widgets')

-- Our own art, not DFHack's shipped hack/data/art/design_toolbar.png, so a
-- DFHack update cannot clobber it. 64x36 = 8x3 tiles of 8x12; the left four
-- columns are the resting icon, the right four the hover state.
--
-- loadTileset caches by filename: editing the PNG in place and reloading the
-- script returns the already-uploaded texture and the game keeps showing the
-- OLD art (measured: the handles resolve to an unchanged texpos range), so
-- art changes need a DF restart.
--
-- The art lives next to this script in the mod folder; getModSourcePath finds
-- the installed copy (mods/, data/installed_mods/ or the Workshop dir).
local scriptmanager = require('script-manager')
local MOD_ID = 'design_button'
local mod_path = scriptmanager.getModSourcePath(MOD_ID)
    or qerror('gui/design-button: mod "'..MOD_ID..'" is not installed')
local toolbar_textures = dfhack.textures.loadTileset(
    mod_path..'graphics/images/design_button.png', 8, 12, true)

local main_if = df.global.game.main_interface
local selection_rect = df.global.selection_rect

-- The nine designation modes that put the vanilla dig toolbar on screen. The
-- focus string is derived from this field, so testing it directly gives the same
-- answer while gui/design is the top viewscreen, which matchFocusString does not.
local DIG_MODES = {}
for _, name in ipairs{'DIG_DIG', 'DIG_REMOVE_STAIRS_RAMPS', 'DIG_STAIR_UP',
                      'DIG_STAIR_UPDOWN', 'DIG_STAIR_DOWN', 'DIG_RAMP',
                      'DIG_CHANNEL', 'DIG_FROM_MARKER', 'DIG_TO_MARKER'} do
    DIG_MODES[df.main_designation_type[name]] = true
end

local function on_dig_toolbar()
    return not not DIG_MODES[main_if.main_designation_selected]
end

-- mirrors the layout math in hack/lua/plugins/dig.lua so this button stays
-- aligned with the warm/damp button as the window is resized
local BASELINE_OFFSET = 42

local function get_l_offset(parent_rect)
    local w = parent_rect.width
    if w <= 177 then
        return BASELINE_OFFSET + w - 114
    end
    return BASELINE_OFFSET + (w+1)//2 - 26
end

-- gui/design is loaded lazily and memoised: a failure to load it should cost the
-- mode label, not the toolbar button.
local design_mod

-- true only between our toolbar button opening gui/design and that window
-- closing again, so a gui/design opened by keybinding is left entirely alone
local our_session = false

-- Called from render, so once per frame on every dwarfmode viewscreen. reqscript
-- re-runs loadfile on any script it failed to load, because
-- hack/lua/dfhack.lua:1099-1109 only stamps mtime on success. So a broken
-- gui/design.lua would mean a silent full parse of ~1600 lines every frame. Remember the failure instead; the button
-- keeps working and only the label is lost, and a reload of this script retries.
local design_mod_broken = false

local function design_is_open()
    if not design_mod then
        if design_mod_broken then return false end
        local ok, mod = pcall(reqscript, 'gui/design')
        if not ok then
            design_mod_broken = true
            return false
        end
        design_mod = mod
    end
    return not not design_mod.view
end

-- DF prints the active designation mode on row 9 of a 3-row decorated banner
-- (measured: rows 8-10, columns 8-63, left-cap / fill / right-cap tiles per row).
-- The banner is drawn only while a designation mode is active, so clearing the
-- mode takes it away along with the label. The texpos ids are assigned at load,
-- so capture the strip off the live frame while the dig toolbar is still up and
-- replay it underneath our own label rather than hardcoding numbers.
local LABEL_ROW = 9

local banner

-- Recaptured on every launch rather than memoised. Anything else drawn across
-- rows 8-10 on the captured frame (gui/design.dimensions' tooltip follows the
-- pointer and is framed) would be baked into the strip and replayed under the
-- label for the rest of the DF run, with no way to heal short of a resize or a
-- script reload. 168 readTile calls per button press is not worth that risk.
local function capture_banner()
    local w = dfhack.screen.getWindowSize()
    banner = nil
    local function tile_at(x, y)
        local pen = dfhack.screen.readTile(x, y)
        return pen and pen.tile or 0
    end
    local x1
    for x = 0, w-1 do
        if tile_at(x, LABEL_ROW) ~= 0 then x1 = x break end
    end
    if not x1 then return end
    local x2 = x1
    for x = x1, w-1 do
        if tile_at(x, LABEL_ROW) == 0 then break end
        x2 = x
    end
    local tiles = {}
    for y = LABEL_ROW-1, LABEL_ROW+1 do
        local row = {}
        for x = x1, x2 do
            row[#row+1] = tile_at(x, y)
        end
        tiles[#tiles+1] = row
    end
    banner = {x1=x1, tiles=tiles}
end

local function paint_banner()
    if not banner then return end
    for dy, row in ipairs(banner.tiles) do
        local y = LABEL_ROW - 2 + dy
        for dx, tile in ipairs(row) do
            if tile ~= 0 then
                dfhack.screen.paintTile(
                    {ch=0, fg=COLOR_BLACK, bg=COLOR_BLACK, tile=tile,
                     write_to_lower=true},
                    banner.x1 + dx - 1, y)
            end
        end
    end
end

-- Only while gui/design is up and no vanilla designation is active, so we can
-- never half-overdraw vanilla's own label if gui/design is opened some other way.
local function show_mode_label()
    local open = design_is_open()
    if not open then our_session = false end
    return our_session and open
        and main_if.main_designation_selected == df.main_designation_type.NONE
end

-- DF prints the active designation mode in the top-left info area. Clicking the
-- toolbar button clears main_designation_selected, so vanilla stops drawing that
-- label; this puts "Design" there instead for as long as gui/design is up.
-- The label sits ~50 rows away from the widget frame, so it is painted directly
-- rather than as a subview. Column is banner.x1+2, so it tracks a moved banner
-- (measured: the banner starts at column 8 and vanilla's mode text at column 10).
--
-- These six cells lose the replayed banner fill: dfhack.screen has no way to
-- write a character and keep a sprite in the same cell (measured: vanilla gets
-- both only by writing DF's buffers direct). The banner's middle-row fill tile is
-- solid #1c1c1c, so they go to black and the gold frame above and below is
-- untouched.
local function paint_mode_label()
    if not banner then return end
    dfhack.screen.paintString({fg=COLOR_WHITE, bg=COLOR_BLACK},
                              banner.x1 + 2, LABEL_ROW, 'Design')
end

-- Clearing main_designation_selected closes the dig submenu, which is what we
-- want: gui/design takes over the map. Leaving vanilla's own designation mode
-- armed underneath would otherwise show two designation UIs at once. (This is the
-- field that does it; bottom_mode_selected is already -1 while the dig toolbar
-- is up, so setting it does nothing.) The submenu is back as soon as gui/design
-- is dismissed and the user picks a dig type again.
--
-- The start_x/y/z reset goes with it: gui/design reads selection_rect as its
-- anchor (hack/scripts/gui/design.lua:79-81), and a stale vanilla drag start
-- would be picked up as one.
local function launch_design()
    capture_banner()
    selection_rect.start_x = -30000
    selection_rect.start_y = -30000
    selection_rect.start_z = -30000
    main_if.main_designation_selected = df.main_designation_type.NONE
    dfhack.timeout(1, 'frames', function()
        dfhack.run_command('gui/design')
        if design_is_open() then
            -- not before now: the dwarfmode overlay renders at least once
            -- between the click and this callback, and show_mode_label clears
            -- the flag on any frame where the window is not up yet
            our_session = true
        end
    end)
end

DesignButtonOverlay = defclass(DesignButtonOverlay, overlay.OverlayWidget)
DesignButtonOverlay.ATTRS{
    desc='Adds a button to the dig toolbar that opens gui/design.',
    default_pos={x=1, y=-4},
    default_enabled=true,
    -- Deliberately not the nine DIG_* focus strings. Clicking the button
    -- clears main_designation_selected, which takes those focus strings away.
    -- A widget scoped to them would then be torn down the moment gui/design
    -- opens, and could never draw the mode label. Scoped to dwarfmode instead, it
    -- renders through ZScreen:renderParent while the
    -- design window has focus; on_dig_toolbar() gates the parts that are only
    -- meant to show on the dig toolbar itself.
    viewscreens={'dwarfmode'},
    -- tall enough to hold the hover popup as well as the button: 7 rows of
    -- popup + 1 blank + 3 of button. The overlay paints no background of its
    -- own, so the extra height is invisible whenever the popup is hidden.
    frame={w=26, h=11},
}

-- Ctrl+D is taken by dig.lua's warm/damp button, which is the only other
-- overlay on these viewscreens (checked: nothing else declares DIG_DIG).
local HOTKEY = 'CUSTOM_CTRL_G'

function DesignButtonOverlay:init()
    -- fallback for ASCII mode, where the tileset above is not used
    local button_chars = {
        {218, 196, 196, 191},
        {179, 'D', 254, 179},
        {192, 196, 196, 217},
    }

    self:addviews{
        -- DFHack has no tooltip widget; its own toolbar popups are just a Panel
        -- whose visibility is a hover test on the button (hack/lua/plugins/dig.lua:172).
        -- frame_background=CLEAR_PEN is what makes it opaque over the map.
        -- The popup hangs left off the button because nothing vanilla draws
        -- there. Below ~139 columns of window width the overlay frame is narrower
        -- than 26; compute_frame_rect clamps the panel to the space available, so
        -- the borders stay intact and the text truncates on the right.
        widgets.Panel{
            frame={t=0, r=0, w=26, h=7},
            frame_style=gui.FRAME_PANEL,
            frame_background=gui.CLEAR_PEN,
            frame_inset={l=1, r=1},
            -- a hidden view keeps its last frame_body, so getMousePos alone
            -- would still answer yes after the toolbar is gone
            visible=function()
                return on_dig_toolbar()
                    and not not self.subviews.button:getMousePos()
            end,
            subviews={
                widgets.Label{
                    text={
                        'Open gui/design for', NEWLINE,
                        'shape-based digging', NEWLINE,
                        'designations.', NEWLINE,
                        NEWLINE,
                        {text='Hotkey: ', pen=COLOR_GRAY}, {key=HOTKEY},
                    },
                },
            },
        },
        widgets.Label{
            view_id='button',
            frame={b=0, r=0, w=4, h=3},
            visible=on_dig_toolbar,
            text=widgets.makeButtonLabelText{
                chars=button_chars,
                pens={
                    {COLOR_GRAY,  COLOR_GRAY,      COLOR_GRAY,  COLOR_GRAY},
                    {COLOR_GRAY,  COLOR_LIGHTCYAN, COLOR_CYAN,  COLOR_GRAY},
                    {COLOR_GRAY,  COLOR_GRAY,      COLOR_GRAY,  COLOR_GRAY},
                },
                pens_hover={
                    {COLOR_WHITE, COLOR_WHITE,     COLOR_WHITE, COLOR_WHITE},
                    {COLOR_WHITE, COLOR_LIGHTCYAN, COLOR_CYAN,  COLOR_WHITE},
                    {COLOR_WHITE, COLOR_WHITE,     COLOR_WHITE, COLOR_WHITE},
                },
                tileset=toolbar_textures,
                tileset_offset=1,
                tileset_stride=8,
                tileset_hover=toolbar_textures,
                tileset_hover_offset=5,
                tileset_hover_stride=8,
            },
            on_click=launch_design,
        },
    }
end

-- Measured on the live toolbar (150x66, get_l_offset 78): the vanilla dig-type
-- buttons run from get_l_offset-41 in 4-wide slots, and everything on this row
-- is anchored a fixed 72 columns from the right edge, so it all tracks
-- get_l_offset. The widget is pinned at column 0 and stretched rightwards to
-- get_l_offset-42, which puts the r=0 button at get_l_offset-45 .. get_l_offset-42,
-- immediately left of the first vanilla button, the way warm/damp butts
-- against the last one on the other end. Nothing vanilla draws left of it.
local VANILLA_LEFT_OFFSET = 41

function DesignButtonOverlay:render(dc)
    if show_mode_label() then
        paint_banner()       -- under the label, not over it
        paint_mode_label()
    end
    DesignButtonOverlay.super.render(self, dc)
end

function DesignButtonOverlay:onInput(keys)
    if keys[HOTKEY] and on_dig_toolbar() then
        launch_design()
        return true
    end
    return DesignButtonOverlay.super.onInput(self, keys)
end

function DesignButtonOverlay:preUpdateLayout(parent_rect)
    self.frame.w = get_l_offset(parent_rect) - VANILLA_LEFT_OFFSET
end

OVERLAY_WIDGETS = {
    button=DesignButtonOverlay,
}
