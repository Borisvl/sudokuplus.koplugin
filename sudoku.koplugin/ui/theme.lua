-- Ink table for the game view. Only luminance grays: KOReader inverts
-- the whole framebuffer in night mode, so these colors stay consistent
-- on both white-on-black and black-on-white screens.

local Blitbuffer = require("ffi/blitbuffer")

local theme = {
    background = Blitbuffer.COLOR_WHITE,
    grid_thin = Blitbuffer.COLOR_GRAY,
    grid_thick = Blitbuffer.COLOR_BLACK,
    digit = Blitbuffer.COLOR_BLACK,
    note = Blitbuffer.COLOR_GRAY_3,
    wrong_fill = Blitbuffer.COLOR_GRAY,
    disabled = Blitbuffer.COLOR_GRAY_7,
    -- Ink for digits/notes drawn on the inverted (black) selection cell
    invert_fg = Blitbuffer.COLOR_WHITE,
}

return theme
