local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local MultiConfirmBox = require("ui/widget/multiconfirmbox")
local Notification = require("ui/widget/notification")
local UIManager = require("ui/uimanager")
local bit = require("bit")
local logger = require("logger")
local T = require("ffi/util").template
local _ = require("gettext")

local layout = require("ui.layout")
local numberbar = require("ui.numberbar")
local stats = require("stats")
local storage = require("storage")
local theme = require("ui.theme")

local Screen = Device.screen

local SudokuView = InputContainer:extend {
    name = "sudokuview",
    covers_fullscreen = true,
    width = nil,
    height = nil,
    game = nil,
    stats = nil,
    save_path = nil,
    stats_path = nil,
}

local function format_time(seconds)
    seconds = math.max(0, math.floor(seconds + 0.5))
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    return string.format("%02d:%02d:%02d", hours, minutes, seconds % 60)
end

function SudokuView:init()
    self.width = self.width or Screen:getWidth()
    self.height = self.height or Screen:getHeight()
    self.layout = layout.compute(self.width, self.height, function(dp)
        return Screen:scaleBySize(dp)
    end)
    self.dimen = Geom:new { x = 0, y = 0, w = self.width, h = self.height }

    local bold_name = Font.bold_font_variant[Font.fontmap.cfont] or Font.fontmap.cfont
    self.faces = {
        given = Font:getFace(bold_name, self.layout.fonts.given),
        user = Font:getFace("cfont", self.layout.fonts.user),
        notes = Font:getFace("cfont", self.layout.fonts.notes),
    }

    self.selected = nil
    self.notes_mode = false
    self.menu_open = false

    self.ges_events.Tap = {
        GestureRange:new {
            ges = "tap",
            range = Geom:new { x = 0, y = 0, w = self.width, h = self.height },
        },
    }
    self.key_events.Close = { { Device.input.group.Back } }
end

function SudokuView:refresh()
    UIManager:setDirty(self, "full")
end

function SudokuView:paintGrid(bb)
    local l = self.layout
    local grid = l.grid
    for i, line in ipairs(layout.grid_lines(l).horizontal) do
        local color = (i - 1) % 3 == 2 and theme.grid_thick or theme.grid_thin
        bb:paintRect(grid.x, line.y, line.w, line.thickness, color)
    end
    for i, line in ipairs(layout.grid_lines(l).vertical) do
        local color = (i - 1) % 3 == 2 and theme.grid_thick or theme.grid_thin
        bb:paintRect(line.x, grid.y, line.thickness, line.h, color)
    end
    bb:paintRect(grid.x, grid.y, grid.w, l.thick, theme.grid_thick)
    bb:paintRect(grid.x, grid.y + grid.h - l.thick, grid.w, l.thick, theme.grid_thick)
    bb:paintRect(grid.x, grid.y, l.thick, grid.h, theme.grid_thick)
    bb:paintRect(grid.x + grid.w - l.thick, grid.y, l.thick, grid.h, theme.grid_thick)
end

function SudokuView:paintNotes(bb, rect, mask)
    local third = math.floor(rect.w / 3)
    for value = 1, 9 do
        if bit.band(mask, bit.lshift(1, value - 1)) ~= 0 then
            local sub = {
                x = rect.x + ((value - 1) % 3) * third,
                y = rect.y + math.floor((value - 1) / 3) * third,
                w = third,
                h = third,
            }
            numberbar.render_centered(bb, self.faces.notes, tostring(value), false, sub, theme.note)
        end
    end
end

function SudokuView:paintCells(bb)
    local conflict_set = {}
    for _, cell in ipairs(self.game:conflicts()) do
        conflict_set[cell[1] * 9 + cell[2]] = true
    end
    local revealed_set = {}
    for _, cell in ipairs(self.game:revealed()) do
        revealed_set[cell[1] * 9 + cell[2]] = true
    end

    for row = 0, 8 do
        for col = 0, 8 do
            local rect = layout.cell_rect(self.layout, row, col)
            local key = row * 9 + col
            local is_selected = self.selected ~= nil and self.selected.row == row and self.selected.col == col
            if conflict_set[key] or revealed_set[key] then
                bb:paintRect(rect.x, rect.y, rect.w, rect.h, theme.wrong_fill)
            end

            local value = self.game:get(row, col)
            if value ~= 0 then
                local face = self.game:is_given(row, col) and self.faces.given or self.faces.user
                numberbar.render_centered(bb, face, tostring(value), false, rect, theme.digit)
            elseif self.game:get_notes(row, col) ~= 0 then
                self:paintNotes(bb, rect, self.game:get_notes(row, col))
            end

            if is_selected then
                self:paintSelection(bb, rect)
            end
        end
    end
end

function SudokuView:paintSelection(bb, rect)
    local t = self.layout.thick
    bb:paintRect(rect.x, rect.y, rect.w, t, theme.digit)
    bb:paintRect(rect.x, rect.y + rect.h - t, rect.w, t, theme.digit)
    bb:paintRect(rect.x, rect.y, t, rect.h, theme.digit)
    bb:paintRect(rect.x + rect.w - t, rect.y, t, rect.h, theme.digit)
end

function SudokuView:paintTo(bb, x, y)
    bb:paintRect(0, 0, self.width, self.height, theme.background)
    self:paintGrid(bb)
    self:paintCells(bb)
    numberbar.paint(bb, self.layout, {
        notes_mode = self.notes_mode,
        can_undo = self.game:can_undo(),
        can_redo = self.game:can_redo(),
    })
end

function SudokuView:onTap(ev_args, ges)
    local hit = layout.hit(self.layout, ges.pos.x, ges.pos.y)
    if not hit then
        return true
    end
    if hit.kind == "cell" then
        self.selected = { row = hit.row, col = hit.col }
        self:refresh()
        return true
    end

    if type(hit.id) == "number" or hit.id == "erase" then
        if not self.selected then
            UIManager:show(Notification:new { text = _("Select a cell first.") })
            return true
        end
    end

    local ok, err
    if type(hit.id) == "number" then
        if self.notes_mode then
            ok, err = self.game:toggle_note(self.selected.row, self.selected.col, hit.id)
        elseif self.game:get(self.selected.row, self.selected.col) == hit.id then
            ok, err = self.game:erase(self.selected.row, self.selected.col)
        else
            ok, err = self.game:place(self.selected.row, self.selected.col, hit.id)
        end
    elseif hit.id == "erase" then
        if self.game:get(self.selected.row, self.selected.col) ~= 0 then
            ok, err = self.game:erase(self.selected.row, self.selected.col)
        else
            ok, err = self.game:clear_notes(self.selected.row, self.selected.col)
        end
    elseif hit.id == "undo" then
        self.game:undo()
    elseif hit.id == "redo" then
        self.game:redo()
    elseif hit.id == "notes" then
        self.notes_mode = not self.notes_mode
    elseif hit.id == "check" then
        self:onCheck()
    elseif hit.id == "menu" then
        self:openMenu()
    end
    if ok == false or (ok == nil and err ~= nil) then
        UIManager:show(Notification:new { text = err })
    end
    self:afterMove()
    return true
end

function SudokuView:afterMove()
    self:refresh()
    if self.game:is_won() then
        self:onWin()
    end
end

function SudokuView:onCheck()
    local wrong = self.game:check_for_errors()
    local text = #wrong == 0 and _("No mistakes found.") or T(_("%1 wrong cell(s) found."), #wrong)
    UIManager:show(Notification:new { text = text })
end

function SudokuView:persistStats()
    local ok, err = storage.save(self.stats_path, stats.to_table(self.stats))
    if not ok then
        logger.warn("sudoku: failed to save stats: " .. tostring(err))
    end
end

function SudokuView:deleteSave()
    if not self.save_path then
        return
    end
    local ok, err = storage.delete(self.save_path)
    if not ok then
        logger.dbg("sudoku: failed to delete save: " .. tostring(err))
    end
end

function SudokuView:onWin()
    local record, err = self.game:finish()
    if not record then
        logger.warn("sudoku: failed to finish game: " .. tostring(err))
        return
    end
    if self.stats then
        stats.add(self.stats, record)
        self:persistStats()
    end
    self:deleteSave()
    UIManager:show(InfoMessage:new {
        text = T(
            _("Puzzle solved!\n\nTime: %1\nMistakes: %2"),
            format_time(record.duration),
            tostring(record.mistakes)
        ),
        dismiss_callback = function()
            UIManager:close(self, "flashui")
        end,
    })
end

function SudokuView:onGiveUp()
    local record, err = self.game:give_up()
    if not record then
        logger.warn("sudoku: failed to give up: " .. tostring(err))
        return
    end
    if self.stats then
        stats.add(self.stats, record)
        self:persistStats()
    end
    self:deleteSave()
    UIManager:close(self, "flashui")
end

function SudokuView:onQuit()
    self.game:pause()
    if self.save_path then
        local ok, err = storage.save(self.save_path, self.game:serialize())
        if not ok then
            logger.warn("sudoku: failed to save game: " .. tostring(err))
        end
    end
    UIManager:close(self, "flashui")
end

function SudokuView:onClose()
    self:onQuit()
end

function SudokuView:openMenu()
    self.game:pause()
    self.menu_open = true
    UIManager:show(MultiConfirmBox:new {
        text = T(_("Time: %1    Mistakes: %2"), format_time(self.game:elapsed()), tostring(self.game:mistakes())),
        cancel_text = _("Resume"),
        cancel_callback = function()
            self:closeMenu()
        end,
        choice1_text = _("Give up"),
        choice1_callback = function()
            self.menu_open = false
            self:onGiveUp()
        end,
        choice2_text = _("Quit"),
        choice2_callback = function()
            self.menu_open = false
            self:onQuit()
        end,
    })
end

function SudokuView:closeMenu()
    self.menu_open = false
    self.game:resume()
    self:refresh()
end

function SudokuView:onSuspend()
    self.game:pause()
    return true
end

function SudokuView:onResume()
    if not self.menu_open and not self.game:is_finished() then
        self.game:resume()
    end
    self:refresh()
    return true
end

function SudokuView:onSetDimensions(dimen)
    self.layout = layout.compute(self.width, self.height, function(dp)
        return Screen:scaleBySize(dp)
    end)
    self:refresh()
    return true
end

return SudokuView
