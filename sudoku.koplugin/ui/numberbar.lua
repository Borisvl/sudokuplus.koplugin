local Font = require("ui/font")
local RenderText = require("ui/rendertext")
local theme = require("ui.theme")
local _ = require("gettext")

local numberbar = {}

-- Renders `text` centered inside `rect` and returns the rendered width.
function numberbar.render_centered(bb, face, text, bold, rect, color)
    local size = RenderText:sizeUtf8Text(0, rect.w, face, text, false, bold)
    -- Glyphs are blitted from baseline - y_top down to baseline + y_bottom,
    -- so centering the ink vertically means:
    local baseline = rect.y + math.floor((rect.h + size.y_top - size.y_bottom) / 2)
    return RenderText:renderUtf8Text(
        bb,
        rect.x + math.floor((rect.w - size.x) / 2),
        baseline,
        face,
        text,
        false,
        bold,
        color,
        rect.w
    )
end

local TOOL_LABELS = {
    undo = function()
        return _("Undo")
    end,
    redo = function()
        return _("Redo")
    end,
    notes = function()
        return _("Notes")
    end,
    check = function()
        return _("Check")
    end,
    hint = function()
        return _("Hint")
    end,
    menu = function()
        return _("Menu")
    end,
}

local function label_for(id)
    local getter = TOOL_LABELS[id]
    if getter then
        return getter()
    end
    return tostring(id)
end

local function paint_row(bb, row)
    bb:paintRect(row.x, row.y, row.w, row.h, theme.background)
    local button_width = row.buttons[1].w
    for i = 1, #row.buttons - 1 do
        local x = row.x + i * button_width
        bb:paintRect(x, row.y, 1, row.h, theme.grid_thin)
    end
end

function numberbar.paint(bb, layout, state)
    state = state or {}
    local digit_face = Font:getFace("cfont", layout.fonts.digit)
    local label_face = Font:getFace("cfont", layout.fonts.label)

    paint_row(bb, layout.number_row)
    for _, button in ipairs(layout.number_row.buttons) do
        local face = type(button.id) == "number" and digit_face or label_face
        -- A digit fully placed (nine times) is greyed out but stays selectable:
        -- arming it still inverts below.
        local color = theme.digit
        if type(button.id) == "number" and state.completed and state.completed[button.id] then
            color = theme.disabled
        end
        numberbar.render_centered(bb, face, label_for(button.id), false, button, color)
        if state.armed and button.id == state.armed then
            bb:invertRect(button.x, button.y, button.w, button.h)
        end
    end

    paint_row(bb, layout.tool_row)
    for _, button in ipairs(layout.tool_row.buttons) do
        local enabled = true
        if button.id == "undo" then
            enabled = state.can_undo
        elseif button.id == "redo" then
            enabled = state.can_redo
        end
        local color = enabled and theme.digit or theme.disabled
        numberbar.render_centered(bb, label_face, label_for(button.id), false, button, color)
        if button.id == "notes" and state.notes_mode then
            bb:invertRect(button.x, button.y, button.w, button.h)
        end
    end
    return true
end

return numberbar
