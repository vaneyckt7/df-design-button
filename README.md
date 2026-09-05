# Design Button

A DFHack mod for Dwarf Fortress. It adds a button to the vanilla dig toolbar
that opens `gui/design`, DFHack's shape-based digging tool. Meant for
playing without a keyboard, e.g. on the Steam Deck.

Requires [DFHack](https://store.steampowered.com/app/2346660/). The mod does
nothing without it.

## Layout

    info.txt                                  mod metadata (ID + NUMERIC_VERSION are mandatory for DFHack)
    preview.png                               Steam Workshop thumbnail
    scripts_modinstalled/gui/design-button.lua    the overlay widget; active whenever the mod is installed
    graphics/images/design_button.png         8x3 tiles of 8x12: resting icon left, hover icon right

The overlay is registered as `gui/design-button.button`; toggle it in
`gui/control-panel` → Overlays, or `overlay disable gui/design-button.button`.

## Publishing

Copy the folder into `<DF>/mods/mod_upload/`, then title screen → Mods →
Publish. DF appends `[STEAM_FILE_ID:...]` to `info.txt` afterwards; keep it so
later uploads update the same Workshop item.

## License

MIT. See [LICENSE](LICENSE).
