describe("sudoku numberbar", function()
    local Blitbuffer
    local layout
    local numberbar
    local theme

    local WIDTH = 758
    local HEIGHT = 1024
    local bb
    local l

    local function scaler(dp)
        return math.ceil(dp * 1.26)
    end

    local function pixel(buffer, x, y)
        return tonumber(buffer:getPixel(x, y).a)
    end

    local function scan_rect(buffer, rect, color)
        for y = rect.y + 1, rect.y + rect.h - 2 do
            for x = rect.x + 1, rect.x + rect.w - 2 do
                if pixel(buffer, x, y) == color then
                    return true
                end
            end
        end
        return false
    end

    setup(function()
        require("commonrequire")
        Blitbuffer = require("ffi/blitbuffer")
        package.path = "plugins/sudoku.koplugin/?.lua;" .. package.path
        layout = require("ui.layout")
        numberbar = require("ui.numberbar")
        theme = require("ui.theme")
    end)

    before_each(function()
        l = layout.compute(WIDTH, HEIGHT, scaler)
        bb = Blitbuffer.new(WIDTH, HEIGHT)
        bb:fill(Blitbuffer.COLOR_WHITE)
    end)

    after_each(function()
        bb:free()
    end)

    it("paints both bar rows without error", function()
        assert.is_true(numberbar.paint(bb, l, {}))
    end)

    it("draws a digit inside every number button", function()
        numberbar.paint(bb, l, {})
        for _, button in ipairs(l.number_row.buttons) do
            if type(button.id) == "number" then
                assert.is_true(
                    scan_rect(bb, button, tonumber(theme.digit.a)),
                    "no ink in button " .. tostring(button.id)
                )
            end
        end
    end)

    it("draws a label inside every tool button", function()
        numberbar.paint(bb, l, { can_undo = true, can_redo = true })
        for _, button in ipairs(l.tool_row.buttons) do
            assert.is_true(scan_rect(bb, button, tonumber(theme.digit.a)), "no ink in button " .. tostring(button.id))
        end
    end)

    it("separates buttons with a line", function()
        numberbar.paint(bb, l, {})
        local button_width = l.number_row.buttons[1].w
        local separator_x = l.number_row.x + button_width
        local gray = tonumber(theme.grid_thin.a)
        local found = false
        for y = l.number_row.y + 1, l.number_row.y + l.number_row.h - 2 do
            if pixel(bb, separator_x, y) == gray then
                found = true
                break
            end
        end
        assert.is_true(found, "no separator line between buttons")
    end)

    it("inverts the notes button when notes mode is active", function()
        local notes_button
        for _, button in ipairs(l.tool_row.buttons) do
            if button.id == "notes" then
                notes_button = button
            end
        end
        numberbar.paint(bb, l, { notes_mode = false })
        assert.are.equal(pixel(bb, notes_button.x + 2, notes_button.y + 2), 0xFF)
        numberbar.paint(bb, l, { notes_mode = true })
        assert.are.equal(pixel(bb, notes_button.x + 2, notes_button.y + 2), 0x00)
    end)

    it("dims undo/redo labels when there is nothing to undo or redo", function()
        numberbar.paint(bb, l, { can_undo = false, can_redo = false })
        for _, button in ipairs(l.tool_row.buttons) do
            if button.id == "undo" or button.id == "redo" then
                assert.is_false(
                    scan_rect(bb, button, tonumber(theme.digit.a)),
                    "button " .. tostring(button.id) .. " must be dimmed"
                )
                assert.is_true(scan_rect(bb, button, tonumber(theme.disabled.a)))
            end
        end
        numberbar.paint(bb, l, { can_undo = true, can_redo = true })
        for _, button in ipairs(l.tool_row.buttons) do
            if button.id == "undo" or button.id == "redo" then
                assert.is_true(scan_rect(bb, button, tonumber(theme.digit.a)))
            end
        end
    end)

    it("centers text and reports its width", function()
        local face = require("ui/font"):getFace("cfont", l.fonts.label)
        local rect = l.tool_row.buttons[1]
        local width = numberbar.render_centered(bb, face, "Menu", false, rect, theme.digit)
        assert.is_true(width > 0)
    end)

    it("centers rendered text vertically inside its rect", function()
        local face = require("ui/font"):getFace("cfont", l.fonts.label)
        local rect = l.tool_row.buttons[1]
        numberbar.render_centered(bb, face, "5", false, rect, theme.digit)
        local min_y, max_y
        for y = rect.y, rect.y + rect.h - 1 do
            for x = rect.x, rect.x + rect.w - 1 do
                if pixel(bb, x, y) == tonumber(theme.digit.a) then
                    min_y = math.min(min_y or y, y)
                    max_y = math.max(max_y or y, y)
                end
            end
        end
        assert.is_not_nil(min_y, "no ink rendered")
        local ink_center = (min_y + max_y) / 2
        local rect_center = rect.y + rect.h / 2
        assert.is_true(math.abs(ink_center - rect_center) <= 2, "ink is not vertically centered")
    end)
end)
