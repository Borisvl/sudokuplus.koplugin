local Device = require("device")
local ButtonDialog = require("ui/widget/buttondialog")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
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
local util = require("core.util")

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
    new_game_cb = nil,
    show_stats_cb = nil,
}

local function format_time(seconds)
    return util.format_time(seconds)
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
        label = Font:getFace("cfont", self.layout.fonts.label),
    }

    self.selected = nil
    self.armed = nil
    self.notes_mode = false
    self.menu_open = false
    self._dirty_cells = {}
    self._dirty_tool_row = false
    self._dirty_number_row = false
    self._dirty_banner = false
    self._painted = false
    self._undo_state = { can_undo = false, can_redo = false }
    self._hint_result = nil
    self._hint_stage = 0
    self._hint_cells = {}
    self._match_value = nil
    self._match_cells = {}

    self.ges_events.Tap = {
        GestureRange:new {
            ges = "tap",
            range = Geom:new { x = 0, y = 0, w = self.width, h = self.height },
        },
    }
    self.ges_events.Hold = {
        GestureRange:new {
            ges = "hold",
            range = Geom:new { x = 0, y = 0, w = self.width, h = self.height },
        },
    }
    self.key_events.Close = { { Device.input.group.Back } }
end

-- E-ink refresh strategy: in-game updates use "ui" refreshes limited to the
-- cells that actually changed. "ui" is flash-free AND, unlike "partial",
-- never promoted by UIManager to a flashing refresh (which would block the
-- UI thread while the waveform runs, and flash the region); ghosting stays
-- bounded because every changed cell is repainted fresh. Nearby cells merge
-- into one update (clusters stay within a 2x2 cell block) so a tap costs a
-- single EPD update whenever possible — on mxcfb, consecutive updates are
-- serialized, each waiting for the previous one. "full" is reserved for the
-- first paint and wake/resize; leaving the game stays a "flashui" close.
local MAX_REGIONS = 8

function SudokuView:refresh()
    if not self._painted then
        UIManager:setDirty(self, "full")
        return
    end
    local regions = layout.cells_regions(self.layout, self._dirty_cells)
    if #regions > MAX_REGIONS then
        local bbox = layout.cells_region(self.layout, self._dirty_cells)
        if bbox then
            regions = { bbox }
        end
    end
    self._dirty_cells = {}
    if self._dirty_tool_row then
        local row = self.layout.tool_row
        regions[#regions + 1] = { x = row.x, y = row.y, w = row.w, h = row.h }
        self._dirty_tool_row = false
    end
    if self._dirty_number_row then
        local row = self.layout.number_row
        regions[#regions + 1] = { x = row.x, y = row.y, w = row.w, h = row.h }
        self._dirty_number_row = false
    end
    if self._dirty_banner then
        local banner = self.layout.banner
        regions[#regions + 1] = { x = banner.x, y = banner.y, w = banner.w, h = banner.h }
        self._dirty_banner = false
    end
    for _, rect in ipairs(regions) do
        UIManager:setDirty(self, "ui", Geom:new(rect))
    end
end

-- Full-screen flash-free refresh for state changes that move too much to
-- track precisely (closing the pause menu).
function SudokuView:refreshCoarse()
    if not self._painted then
        UIManager:setDirty(self, "full")
        return
    end
    UIManager:setDirty(self, "ui")
end

function SudokuView:refreshFull()
    UIManager:setDirty(self, "full")
end

function SudokuView:markCell(row, col)
    self._dirty_cells[row * 9 + col] = true
end

function SudokuView:markCells(cells)
    for key in pairs(cells) do
        self._dirty_cells[key] = true
    end
end

function SudokuView:markToolRow()
    self._dirty_tool_row = true
end

-- Marks the tool row only when the undo/redo button state actually changed,
-- so moves that leave it untouched do not pay for an extra EPD update.
function SudokuView:markToolRowIfChanged()
    local can_undo = self.game:can_undo()
    local can_redo = self.game:can_redo()
    if can_undo ~= self._undo_state.can_undo or can_redo ~= self._undo_state.can_redo then
        self._undo_state = { can_undo = can_undo, can_redo = can_redo }
        self:markToolRow()
    end
end

function SudokuView:markNumberRow()
    self._dirty_number_row = true
end

function SudokuView:markBanner()
    self._dirty_banner = true
end

local function hint_cell_key(row, col)
    return row * 9 + col
end

-- Marks the currently highlighted hint cells as dirty (they must be
-- repainted when the highlight appears or disappears).
function SudokuView:_markHintCells()
    for key in pairs(self._hint_cells) do
        self._dirty_cells[key] = true
    end
end

function SudokuView:_setHintCells(cells)
    self:_markHintCells()
    self._hint_cells = {}
    for _, cell in ipairs(cells or {}) do
        self._hint_cells[hint_cell_key(cell[1], cell[2])] = true
    end
    self:_markHintCells()
end

-- Drops any in-progress hint reveal and marks the painted regions dirty.
function SudokuView:_clearHintState()
    if self._hint_stage == 0 then
        return
    end
    self:_markHintCells()
    self._hint_cells = {}
    self._hint_result = nil
    self._hint_stage = 0
    self:markBanner()
end

-- Digit-match highlight: selecting a cell that holds a digit highlights every
-- cell showing that digit (as a value or in its notes), making naked-single
-- style patterns easy to spot. Tapping the same digit cell again (or any
-- empty cell) clears it; moves keep the highlight in sync.

function SudokuView:_markMatchCells()
    for key in pairs(self._match_cells) do
        self._dirty_cells[key] = true
    end
end

-- Replaces the highlighted set with `cells` (a set keyed row * 9 + col),
-- marking the cells whose paint state changed.
function SudokuView:_applyMatchCells(cells)
    for key in pairs(cells) do
        if not self._match_cells[key] then
            self._dirty_cells[key] = true
        end
    end
    for key in pairs(self._match_cells) do
        if not cells[key] then
            self._dirty_cells[key] = true
        end
    end
    self._match_cells = cells
end

function SudokuView:_clearMatch()
    if not self._match_value then
        return
    end
    self:_markMatchCells()
    self._match_value = nil
    self._match_cells = {}
end

-- Recomputed after any board/notes change so the highlight follows the moves.
function SudokuView:_refreshMatchAfterMove()
    if self._match_value then
        local cells = self.game:digit_cells(self._match_value)
        if cells then
            self:_applyMatchCells(cells)
        end
    end
end

-- Called after the selection changes: a digit cell selects that digit (or, if
-- the same cell is tapped again, toggles the highlight off); an empty cell
-- clears it.
function SudokuView:_onSelectionChanged(previous)
    local value = self.game:get(self.selected.row, self.selected.col)
    if value == 0 then
        self:_clearMatch()
        return
    end
    if
        previous
        and previous.row == self.selected.row
        and previous.col == self.selected.col
        and value == self._match_value
    then
        self:_clearMatch()
        return
    end
    if value ~= self._match_value then
        self._match_value = value
    end
    self:_applyMatchCells(self.game:digit_cells(value))
end

-- Moves the cursor to (row, col), marking the old and new cell for repaint.
function SudokuView:_moveSelection(row, col)
    local previous = self.selected
    if previous then
        self:markCell(previous.row, previous.col)
    end
    self.selected = { row = row, col = col }
    self:markCell(row, col)
end

-- Arms `value` as the active number-bar digit: the button inverts, the board
-- selection clears, and every cell showing the digit (as a value or in its
-- notes) is highlighted, so the player sees where the digit can go.
function SudokuView:_arm(value)
    self.armed = value
    self._match_value = value
    if self.selected then
        self:markCell(self.selected.row, self.selected.col)
        self.selected = nil
    end
    self:_applyMatchCells(self.game:digit_cells(value))
    self:markNumberRow()
end

-- Disarms the number bar; the highlight falls back to the cursor-derived
-- digit match (the pre-armed behavior).
function SudokuView:_disarm()
    self.armed = nil
    if self.selected then
        self:_onSelectionChanged(nil)
    else
        self:_clearMatch()
    end
    self:markNumberRow()
end

-- Applies the armed digit to (row, col). With `as_note` the digit is toggled
-- as a note; otherwise it is written (placed, or erased when the cell already
-- holds it). Shared by tap (notes mode decides) and hold (the opposite mode),
-- so the two gesture paths cannot drift.
function SudokuView:_applyArmed(row, col, as_note)
    self:_moveSelection(row, col)
    local ok, err
    if as_note then
        self:markCell(row, col)
        ok, err = self.game:toggle_note(row, col, self.armed)
    else
        self:markCells(self.game:affected_cells(row, col, self.armed))
        if self.game:get(row, col) == self.armed then
            ok, err = self.game:erase(row, col)
        else
            ok, err = self.game:place(row, col, self.armed)
        end
    end
    self:markToolRowIfChanged()
    self:afterMove()
    if not ok and err ~= nil then
        UIManager:show(Notification:new { text = err })
    end
end

-- Cursor-only tap: moves the selection and drives the digit-match highlight
-- (a digit cell highlights every cell sharing its digit).
function SudokuView:_selectCell(hit)
    self:_clearHintState()
    local previous = self.selected
    self:_moveSelection(hit.row, hit.col)
    self:_onSelectionChanged(previous)
    self:refresh()
end

function SudokuView:paintGrid(bb)
    local l = self.layout
    local grid = l.grid
    for _, line in ipairs(layout.grid_lines(l).horizontal) do
        local color = line.thickness == l.thick and theme.grid_thick or theme.grid_thin
        bb:paintRect(grid.x, line.y, line.w, line.thickness, color)
    end
    for _, line in ipairs(layout.grid_lines(l).vertical) do
        local color = line.thickness == l.thick and theme.grid_thick or theme.grid_thin
        bb:paintRect(line.x, grid.y, line.thickness, line.h, color)
    end
    bb:paintRect(grid.x, grid.y, grid.w, l.thick, theme.grid_thick)
    bb:paintRect(grid.x, grid.y + grid.h - l.thick, grid.w, l.thick, theme.grid_thick)
    bb:paintRect(grid.x, grid.y, l.thick, grid.h, theme.grid_thick)
    bb:paintRect(grid.x + grid.w - l.thick, grid.y, l.thick, grid.h, theme.grid_thick)
end

function SudokuView:paintNotes(bb, rect, mask, inverted)
    local third = math.floor(rect.w / 3)
    for value = 1, 9 do
        if bit.band(mask, bit.lshift(1, value - 1)) ~= 0 then
            local sub = {
                x = rect.x + ((value - 1) % 3) * third,
                y = rect.y + math.floor((value - 1) / 3) * third,
                w = third,
                h = third,
            }
            numberbar.render_centered(
                bb,
                self.faces.notes,
                tostring(value),
                false,
                sub,
                inverted and theme.invert_fg or theme.note
            )
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
            if is_selected then
                bb:invertRect(rect.x, rect.y, rect.w, rect.h)
            elseif conflict_set[key] or revealed_set[key] then
                bb:paintRect(rect.x, rect.y, rect.w, rect.h, theme.wrong_fill)
            elseif self._hint_stage == 2 and self._hint_cells[key] then
                bb:paintRect(rect.x, rect.y, rect.w, rect.h, theme.hint_fill)
            elseif self._match_cells[key] then
                bb:paintRect(rect.x, rect.y, rect.w, rect.h, theme.match_fill)
            end

            local value = self.game:get(row, col)
            if value ~= 0 then
                local face = self.game:is_given(row, col) and self.faces.given or self.faces.user
                local ink = is_selected and theme.invert_fg or theme.digit
                numberbar.render_centered(bb, face, tostring(value), false, rect, ink)
            elseif self.game:get_notes(row, col) ~= 0 then
                self:paintNotes(bb, rect, self.game:get_notes(row, col), is_selected)
            end
        end
    end
end

function SudokuView:paintTo(bb, x, y)
    bb:paintRect(0, 0, self.width, self.height, theme.background)
    self:paintGrid(bb)
    self:paintCells(bb)
    numberbar.paint(bb, self.layout, {
        notes_mode = self.notes_mode,
        armed = self.armed,
        can_undo = self.game:can_undo(),
        can_redo = self.game:can_redo(),
    })
    if self._hint_stage >= 1 and self._hint_result then
        local banner = self.layout.banner
        bb:paintRect(banner.x, banner.y, banner.w, banner.h, theme.background)
        local text
        if self._hint_stage == 1 then
            text = T(_("%1 — tap Hint for the pattern"), self._hint_result.technique.name)
        else
            text = T(_("%1 — tap Hint to apply"), self._hint_result.technique.name)
        end
        numberbar.render_centered(bb, self.faces.label, text, false, banner, theme.digit)
    end
    self._painted = true
end

function SudokuView:onTap(ev_args, ges)
    local hit = layout.hit(self.layout, ges.pos.x, ges.pos.y)
    if not hit then
        return true
    end
    if hit.kind == "cell" then
        if self.armed then
            self:_clearHintState()
            self:_applyArmed(hit.row, hit.col, self.notes_mode)
        else
            self:_selectCell(hit)
        end
        return true
    end

    local ok, err
    if type(hit.id) == "number" then
        -- The number bar is the "pen": arming never mutates the board. Tapping
        -- the armed digit again disarms it, any other digit switches to it.
        self:_clearHintState()
        if self.armed == hit.id then
            self:_disarm()
        else
            self:_arm(hit.id)
        end
    elseif hit.id == "undo" then
        self:_clearHintState()
        ok, err = self.game:undo()
        if ok then
            self:markCells(self.game:undo_affected_cells())
            self:markToolRowIfChanged()
        end
    elseif hit.id == "redo" then
        self:_clearHintState()
        ok, err = self.game:redo()
        if ok then
            self:markCells(self.game:redo_affected_cells())
            self:markToolRowIfChanged()
        end
    elseif hit.id == "notes" then
        self:_clearHintState()
        self.notes_mode = not self.notes_mode
        self:markToolRow()
    elseif hit.id == "check" then
        self:_clearHintState()
        self:onCheck()
    elseif hit.id == "menu" then
        self:_clearHintState()
        self:openMenu()
    elseif hit.id == "hint" then
        self:onHint()
    end
    if not ok and err ~= nil then
        UIManager:show(Notification:new { text = err })
    end
    self:afterMove()
    return true
end

-- A long press in a cell while a digit is armed flips the entry mode for that
-- cell: with notes off it writes a note, with notes on it writes a value.
function SudokuView:onHold(ev_args, ges)
    local hit = layout.hit(self.layout, ges.pos.x, ges.pos.y)
    if not hit or hit.kind ~= "cell" or not self.armed then
        return true
    end
    self:_clearHintState()
    self:_applyArmed(hit.row, hit.col, not self.notes_mode)
    return true
end

function SudokuView:afterMove()
    self:_refreshMatchAfterMove()
    self:refresh()
    if self.game:is_won() then
        self:onWin()
    end
end

function SudokuView:onCheck()
    local before = self.game:revealed()
    local wrong = self.game:check_for_errors()
    local text = #wrong == 0 and _("No mistakes found.") or T(_("%1 wrong cell(s) found."), #wrong)
    UIManager:show(Notification:new { text = text })
    self:markRevealedDiff(before)
end

-- Marks the cells whose check-reveal state changed since `before` (a list
-- of {row, col} from `game:revealed()`).
function SudokuView:markRevealedDiff(before)
    local before_set = {}
    for _, cell in ipairs(before) do
        before_set[cell[1] * 9 + cell[2]] = true
    end
    for _, cell in ipairs(self.game:revealed()) do
        local key = cell[1] * 9 + cell[2]
        if not before_set[key] then
            self:markCell(cell[1], cell[2])
        end
        before_set[key] = nil
    end
    for key in pairs(before_set) do
        self:markCell(math.floor(key / 9), key % 9)
    end
end

-- Progressive hint reveal: ① technique name in the banner, ② pattern cells
-- highlighted, ③ the action applied (undoable, recorded by game:hint as the
-- missed strategy). Any other interaction cancels the reveal.
function SudokuView:onHint()
    if self._hint_stage == 1 then
        self._hint_stage = 2
        self:_setHintCells(self._hint_result.pattern.cells)
        self:markBanner()
        self:refresh()
        return true
    end
    if self._hint_stage == 2 then
        local action = self._hint_result.action
        local affected = self.game:affected_cells(action.row, action.col, action.value)
        self:_clearHintState()
        local ok, err = self.game:apply_action(action)
        if ok then
            if affected then
                self:markCells(affected)
            else
                self:markCell(action.row, action.col)
            end
            self:markToolRowIfChanged()
            self:_refreshMatchAfterMove()
        elseif err then
            UIManager:show(Notification:new { text = err })
        end
        self:refresh()
        return true
    end

    local result, err = self.game:hint()
    if not result then
        UIManager:show(Notification:new { text = err })
        return true
    end
    if result.status == "available" then
        self._hint_result = result
        self._hint_stage = 1
        self:_clearMatch()
        self:markBanner()
    elseif result.status == "note_error" then
        UIManager:show(Notification:new {
            text = _("Some notes are inconsistent with the board. Fix them first."),
        })
    else
        -- status == "none": the engine could not deduce anything. Cells the
        -- user cleared of all candidates are ground truth the engine cannot
        -- use; name them so the player can re-add their notes.
        local needed = self.game:notes_needed()
        if #needed > 0 then
            local cells = {}
            for i, cell in ipairs(needed) do
                cells[i] = "(" .. (cell[1] + 1) .. ", " .. (cell[2] + 1) .. ")"
            end
            UIManager:show(Notification:new {
                text = T(_("No hint available. Re-add notes to: %1"), table.concat(cells, ", ")),
            })
        elseif result.reason == "solved" then
            UIManager:show(Notification:new { text = _("The puzzle is solved.") })
        else
            UIManager:show(Notification:new { text = _("No hint available.") })
        end
    end
    self:refresh()
    return true
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
    local dialog
    dialog = MultiConfirmBox:new {
        text = T(
            _("Puzzle solved!\n\nTime: %1\nMistakes: %2\nHints: %3"),
            format_time(record.duration),
            tostring(record.mistakes),
            tostring(#record.hints)
        ),
        cancel_text = _("Close"),
        cancel_callback = function()
            UIManager:close(dialog)
            UIManager:close(self, "flashui")
        end,
        choice1_text = _("New game"),
        choice1_callback = function()
            local difficulty = self.game:difficulty()
            UIManager:close(dialog)
            UIManager:close(self, "flashui")
            if self.new_game_cb then
                self.new_game_cb(difficulty)
            end
        end,
        choice2_text = _("Statistics"),
        choice2_callback = function()
            UIManager:close(dialog)
            UIManager:close(self, "flashui")
            if self.show_stats_cb then
                self.show_stats_cb()
            end
        end,
    }
    UIManager:show(dialog)
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

-- Pauses the game and shows the in-game menu. Every dismissal path resumes
-- the timer: the Resume button, the Back key and tapping outside the dialog
-- all end in resumeFromPause() (ButtonDialog runs its tap_close_callback on
-- outside taps / Back, which MultiConfirmBox did not — the old pause menu
-- stayed paused when dismissed by tapping outside).
function SudokuView:openMenu()
    self.game:pause()
    self.menu_open = true
    local function resumeFromPause()
        if self.menu_open then
            self.menu_open = false
            if not self.game:is_finished() then
                self.game:resume()
            end
            self:refreshCoarse()
        end
    end
    local dialog
    dialog = ButtonDialog:new {
        title = T(
            _("Time: %1    Mistakes: %2    Hints: %3"),
            format_time(self.game:elapsed()),
            tostring(self.game:mistakes()),
            tostring(#self.game:hints())
        ),
        buttons = {
            {
                {
                    text = _("Resume"),
                    callback = function()
                        UIManager:close(dialog)
                        resumeFromPause()
                    end,
                },
                {
                    text = _("Statistics"),
                    callback = function()
                        self:showStats()
                    end,
                },
            },
            {
                {
                    text = _("Give up"),
                    callback = function()
                        self.menu_open = false
                        UIManager:close(dialog)
                        self:onGiveUp()
                    end,
                },
                {
                    text = _("Quit"),
                    callback = function()
                        self.menu_open = false
                        UIManager:close(dialog)
                        self:onQuit()
                    end,
                },
            },
        },
        tap_close_callback = function()
            resumeFromPause()
        end,
    }
    UIManager:show(dialog)
end

-- Opens the statistics screen on top of the open pause menu (the game stays
-- paused; closing the stats view reveals the pause menu again). "full":
-- like the Tools-menu path, the pause dialog stays open underneath, so the
-- new fullscreen page must refresh the whole screen itself.
function SudokuView:showStats()
    local StatsView = require("ui.statsview")
    UIManager:show(
        StatsView:new {
            summary = stats.summary(self.stats or stats.new()),
        },
        "full"
    )
end

function SudokuView:onSuspend()
    self.game:pause()
    return true
end

function SudokuView:onResume()
    if not self.menu_open and not self.game:is_finished() then
        self.game:resume()
    end
    self:refreshFull()
    return true
end

function SudokuView:onSetDimensions(dimen)
    if dimen then
        self.width = dimen.w
        self.height = dimen.h
    end
    self.layout = layout.compute(self.width, self.height, function(dp)
        return Screen:scaleBySize(dp)
    end)
    self.dimen = Geom:new { x = 0, y = 0, w = self.width, h = self.height }
    self.ges_events.Tap = {
        GestureRange:new {
            ges = "tap",
            range = Geom:new { x = 0, y = 0, w = self.width, h = self.height },
        },
    }
    self.ges_events.Hold = {
        GestureRange:new {
            ges = "hold",
            range = Geom:new { x = 0, y = 0, w = self.width, h = self.height },
        },
    }
    self:refreshFull()
    return true
end

return SudokuView
