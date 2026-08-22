local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local Notification = require("ui/widget/notification")
local UIManager = require("ui/uimanager")
local bit = require("bit")
local logger = require("logger")
local T = require("ffi/util").template
local _ = require("gettext")
local N_ = _.ngettext

local dialogs = require("sudokuplus.ui.dialogs")
local layout = require("sudokuplus.ui.layout")
local messages = require("sudokuplus.ui.messages")
local numberbar = require("sudokuplus.ui.numberbar")
local game_model = require("sudokuplus.game")
local stats = require("sudokuplus.stats")
local storage = require("sudokuplus.storage")
local techniques = require("sudokuplus.ui.techniques")
local theme = require("sudokuplus.ui.theme")

local Screen = Device.screen

-- How long a cycling hardware key must be held (without release) before the
-- notes mode toggles. Kobo hardware has no long-press event (only KeyPress /
-- KeyRelease / auto-repeat), so the hold is detected with this timer.
local HOLD_TOGGLE_NOTES_DELAY = 0.5

-- Hardware keys that cycle the armed digit: the page-turn keys (the physical
-- keys on most Kobo devices) are directional — PgFwd advances, PgBack backs
-- up — and the directional pad mirrors them (Down/Right advance, Up/Left back
-- up). Each group becomes one key sequence ("any of its keys"); the union
-- names cycling keys for the KeyRepeat consumer.
local DIGIT_FWD_SEQUENCES = {}
local DIGIT_BACK_SEQUENCES = {}
local DIGIT_KEYS = {}
for _, group in ipairs({ Device.input.group.PgFwd, { "Down", "Right" } }) do
    table.insert(DIGIT_FWD_SEQUENCES, { group })
    for _, name in ipairs(group) do
        DIGIT_KEYS[name] = true
    end
end
for _, group in ipairs({ Device.input.group.PgBack, { "Up", "Left" } }) do
    table.insert(DIGIT_BACK_SEQUENCES, { group })
    for _, name in ipairs(group) do
        DIGIT_KEYS[name] = true
    end
end

local SudokuView = InputContainer:extend {
    name = "sudokuview",
    covers_fullscreen = true,
    width = nil,
    height = nil,
    game = nil,
    stats = nil,
    save_path = nil,
    stats_path = nil,
    storage_adapter = nil,
    new_game_cb = nil,
    replay_cb = nil,
}

-- Strikes through the digit of a check-revealed (wrong-vs-solution) cell: a
-- bar across the cell width at vertical center, drawn in the same ink as the
-- digit (inverted ink on the cursor cell) so it reads as a deliberate pen
-- stroke crossing the number. Narrow margins let the bar poke out of even the
-- widest glyphs; the thickness scales with the cell height, the same way the
-- grid border scales with the screen DPI.
local function paint_strike(bb, rect, ink)
    local margin = math.floor(rect.w * 0.08)
    local thickness = math.max(1, math.floor(rect.h * 0.03))
    bb:paintRect(rect.x + margin, rect.y + math.floor((rect.h - thickness) / 2), rect.w - 2 * margin, thickness, ink)
end

-- 1-bit stand-in for the gray highlight fills: a fine black/white dot grid
-- (one dot every 2 pixels, every other row — ~25% black, inset 1px from the
-- cell edges) so updated regions contain no gray pixels. On the Aura One the
-- EPDC upgrades AUTO partial updates that touch gray content to a flashing
-- waveform; a pure black/white region avoids that path (verified on-device:
-- no more dark flashes). Match and hint share the look (they never coexist);
-- wrong cells keep a solid gray fill, since error cells are rare enough that
-- their flash is acceptable.
local DITHER_HIGHLIGHT = { period = 2, inset = 1 }

local function paint_dither(bb, rect, ink)
    for y = rect.y + DITHER_HIGHLIGHT.inset, rect.y + rect.h - 1, DITHER_HIGHLIGHT.period do
        for x = rect.x + DITHER_HIGHLIGHT.inset, rect.x + rect.w - 1, DITHER_HIGHLIGHT.period do
            bb:paintRect(x, y, 1, 1, ink)
        end
    end
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
    self._completed_digits = self.game:completed_digits()
    self._terminal_stats_applied = false
    self._finalization_complete = false
    self._log_started = false
    self._win_dialog = nil
    self._hold_token = 0
    self._holding_key = nil
    self._pending_persistence = nil
    self._skip_checkpoint = false

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
    self.key_events.DigitNext = DIGIT_FWD_SEQUENCES
    self.key_events.DigitPrev = DIGIT_BACK_SEQUENCES
end

-- E-ink refresh strategy: in-game updates use "ui" refreshes limited to the
-- cells that actually changed. "ui" is flash-free AND, unlike "partial",
-- never promoted by UIManager to a flashing refresh (which would block the
-- UI thread while the waveform runs, and flash the region); ghosting stays
-- bounded because every changed cell is repainted fresh. All dirty cells are
-- merged into ONE bounding-box region per interaction: on mxcfb, consecutive
-- updates are serialized, each waiting for the previous one and each running
-- a waveform with a visible dark phase — per-cluster regions made a digit
-- match highlight flash region by region (old cells dark, then white, then
-- the new cells settling gray). "full" is reserved for the first paint and
-- wake/resize; leaving the game stays a "flashui" close.

function SudokuView:refresh()
    if not self._painted then
        UIManager:setDirty(self, "full")
        return
    end
    local regions = {}
    local bbox = layout.cells_region(self.layout, self._dirty_cells)
    if bbox then
        regions[#regions + 1] = bbox
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
    self:_clearHintState()
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
        UIManager:show(Notification:new { text = messages.translate(err) })
    end
end

-- Cursor-only tap: moves the selection and drives the digit-match highlight
-- (a digit cell highlights every cell sharing its digit).
function SudokuView:_selectCell(hit)
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

-- Caches conflict and revealed cell sets indexed by cell key (row * 9 + col).
-- Invariant: Board edits bump game:revision(); error check reveals bump
-- game:check_errors(); revealed cell removals always follow a board fix that
-- bumps revision. Checking the vector (revision, check_errors) guarantees zero
-- redundant scans during non-mutating UI repaints (cell selection, arming digits,
-- menu navigation).
function SudokuView:_updateCachedSets()
    local conflict_set = {}
    for _, cell in ipairs(self.game:conflicts()) do
        conflict_set[cell[1] * 9 + cell[2]] = true
    end
    local revealed_set = {}
    for _, cell in ipairs(self.game:revealed()) do
        revealed_set[cell[1] * 9 + cell[2]] = true
    end
    self._conflict_set = conflict_set
    self._revealed_set = revealed_set
    self._cached_revision = self.game:revision()
    self._cached_check_errors = self.game:check_errors()
end

function SudokuView:paintCells(bb)
    local cur_rev = self.game:revision()
    local cur_errs = self.game:check_errors()
    if not self._conflict_set or self._cached_revision ~= cur_rev or self._cached_check_errors ~= cur_errs then
        self:_updateCachedSets()
    end
    local conflict_set = self._conflict_set
    local revealed_set = self._revealed_set

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
                paint_dither(bb, rect, theme.digit)
            elseif self._match_cells[key] then
                paint_dither(bb, rect, theme.digit)
            end

            local value = self.game:get(row, col)
            if value ~= 0 then
                local face = self.game:is_given(row, col) and self.faces.given or self.faces.user
                local ink = is_selected and theme.invert_fg or theme.digit
                numberbar.render_centered(bb, face, tostring(value), false, rect, ink)
                if revealed_set[key] then
                    paint_strike(bb, rect, ink)
                end
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
        completed = self._completed_digits,
    })
    if self._hint_stage >= 1 and self._hint_result then
        local banner = self.layout.banner
        bb:paintRect(banner.x, banner.y, banner.w, banner.h, theme.background)
        local tech_name = techniques.label(self._hint_result.technique.id)
        local text
        if self._hint_stage == 1 then
            text = T(_("%1 — tap Hint for the pattern"), tech_name)
        else
            text = T(_("%1 — tap Hint to apply"), tech_name)
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
        self:_toggleNotes()
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
        UIManager:show(Notification:new { text = messages.translate(err) })
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
    self:_applyArmed(hit.row, hit.col, not self.notes_mode)
    return true
end

-- Next digit to arm when cycling, skipping digits already placed nine times
-- (the greyed-out number-bar buttons, `_completed_digits`). Returns nil when
-- every digit is complete (a full-but-wrong board): there is nothing to arm.
local function next_cycle_digit(completed, forward, from)
    local digit = from
    for _ = 1, 9 do
        if not completed[digit] then
            return digit
        end
        digit = forward and (digit % 9 + 1) or (digit == 1 and 9 or digit - 1)
    end
    return nil
end

-- Toggles notes mode; shared by the Notes button and the hardware-key hold so
-- the two paths cannot drift. The caller runs afterMove() to repaint.
function SudokuView:_toggleNotes()
    self.notes_mode = not self.notes_mode
    self:markToolRow()
end

-- Hardware-key digit cycling: page-turn and directional keys move the armed
-- digit in their direction (forward = 1 -> 9, backward = 9 -> 1), arming 1
-- or 9 respectively when nothing is armed and wrapping at the ends. Digits
-- already placed nine times (the greyed-out bar buttons) are skipped. Every
-- press also (re)arms the hold timer: holding any cycling key for
-- HOLD_TOGGLE_NOTES_DELAY toggles notes mode, while a release or another
-- press invalidates it. Modal dialogs (pause menu, win dialog, stats page)
-- only bind Back, so an unhandled key press falls through the widget stack
-- into this view; the guard keeps cycling inert while a dialog is on top.
function SudokuView:onDigitNext(ev_args, key)
    return self:_cycleDigit(true, key)
end

function SudokuView:onDigitPrev(ev_args, key)
    return self:_cycleDigit(false, key)
end

function SudokuView:_cycleDigit(forward, key)
    if self.menu_open or self.game:is_finished() then
        return true
    end
    if self.armed then
        local from = forward and (self.armed % 9 + 1) or (self.armed == 1 and 9 or self.armed - 1)
        local digit = next_cycle_digit(self._completed_digits, forward, from)
        if digit then
            self:_arm(digit)
        end
    else
        local digit = next_cycle_digit(self._completed_digits, forward, forward and 1 or 9)
        if digit then
            self:_arm(digit)
        end
    end
    if key then
        self._holding_key = key.key
        self._hold_token = self._hold_token + 1
        local token = self._hold_token
        UIManager:scheduleIn(HOLD_TOGGLE_NOTES_DELAY, function()
            if self._hold_token ~= token or self.menu_open or self.game:is_finished() then
                return
            end
            self:_invalidateNotesHold()
            self:_toggleNotes()
            self:afterMove()
        end)
    end
    self:afterMove()
    return true
end

-- Drops a pending notes hold: called on the release of the held key and on
-- any state transition that ends a press cycle (pause menu, suspend, quit,
-- win, give-up), so the scheduled callback can never fire afterwards. A
-- release of a key that is not currently held is a no-op, so pressing and
-- releasing one cycling key cannot cancel the hold of another.
function SudokuView:_invalidateNotesHold()
    self._holding_key = nil
    self._hold_token = self._hold_token + 1
end

function SudokuView:onKeyRelease(key)
    if key and self._holding_key and self._holding_key == key.key then
        self:_invalidateNotesHold()
        return true
    end
end

-- Consumed so auto-repeat never cascades: InputContainer's default onKeyRepeat
-- is a verbatim copy of onKeyPress, which would cycle the digit repeatedly
-- while the key is held.
function SudokuView:onKeyRepeat(key)
    if key and DIGIT_KEYS[key.key] then
        return true
    end
end

-- Marks the number row only when the set of fully placed digits changes, so a
-- digit completing (or an undo/erase breaking it) repaints the row but
-- ordinary moves pay no extra EPD update.
function SudokuView:_syncCompletedDigits()
    local completed = self.game:completed_digits()
    local changed = false
    for v = 1, 9 do
        if (completed[v] ~= nil) ~= (self._completed_digits[v] ~= nil) then
            changed = true
            break
        end
    end
    if changed then
        self._completed_digits = completed
        self:markNumberRow()
    end
end

function SudokuView:afterMove()
    self:_refreshMatchAfterMove()
    self:_syncCompletedDigits()
    -- The first move that adds a number or note starts the game-log entry.
    if self.game:is_started() and not self._log_started then
        self._log_started = true
        self:updateStats(false)
    end
    self:refresh()
    if self.game:is_won() then
        self:onWin()
    end
end

function SudokuView:onCheck()
    local before = self.game:revealed()
    local wrong = self.game:check_for_errors()
    local text = #wrong == 0 and _("No mistakes found.")
        or T(N_("1 wrong cell found.", "%1 wrong cells found.", #wrong), #wrong)
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
        local actions = self._hint_result.actions or { self._hint_result.action }
        local affected = {}
        for _, act in ipairs(actions) do
            if act.type == "place" then
                local aff = self.game:affected_cells(act.row, act.col, act.value)
                if aff then
                    for key in pairs(aff) do
                        affected[key] = true
                    end
                end
            else
                affected[act.row * 9 + act.col] = true
            end
        end
        self:_clearHintState()
        local ok, err = self.game:apply_action(actions)
        if ok then
            self:markCells(affected)
            self:markToolRowIfChanged()
            self:_refreshMatchAfterMove()
        elseif err then
            UIManager:show(Notification:new { text = messages.translate(err) })
        end
        self:refresh()
        return true
    end

    local result, err = self.game:hint()
    if not result then
        UIManager:show(Notification:new { text = messages.translate(err) })
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
    if not self.stats or not self.stats_path then
        return true
    end
    local ok, err = (self.storage_adapter or storage).save(self.stats_path, stats.to_table(self.stats))
    if not ok then
        logger.warn("sudoku: failed to save stats: " .. tostring(err))
        return nil, err
    end
    return true
end

-- Creates or refreshes the game-log entry for the live game (matched by the
-- game id). Called when the first move is made and at save points; only the
-- save points persist, so per-move activity never touches the disk.
function SudokuView:updateStats(persist)
    if not self.stats or self.game.id == nil or not self.game:is_started() or self.game:is_finished() then
        return true
    end
    local ok, err = stats.track(self.stats, self.game:started_record())
    if not ok then
        logger.warn("sudoku: failed to track game: " .. tostring(err))
        return nil, err
    end
    if persist then
        return self:persistStats()
    end
    return true
end

function SudokuView:deleteSave()
    if not self.save_path then
        return true
    end
    local adapter = self.storage_adapter or storage
    if adapter.exists and not adapter.exists(self.save_path) then
        return true
    end
    local ok, err = adapter.delete(self.save_path)
    if not ok then
        logger.dbg("sudoku: failed to delete save: " .. tostring(err))
        return nil, err
    end
    return true
end

function SudokuView:checkpoint(_reason)
    if self.game:is_finished() then
        return true
    end
    local adapter = self.storage_adapter or storage
    if self.save_path then
        local saved, save_err = adapter.save(self.save_path, self.game:serialize())
        if not saved then
            logger.warn("sudoku: failed to save game: " .. tostring(save_err))
            return nil, save_err
        end
    end
    local tracked, track_err = self:updateStats(false)
    if not tracked then
        return nil, track_err
    end
    return self:persistStats()
end

function SudokuView:showPersistenceFailure(action, err, retry_cb, discard_cb)
    return dialogs.confirm_persistence_failure(action, err, retry_cb or function() end, discard_cb or function() end)
end

function SudokuView:_closeWithoutCheckpoint()
    self._skip_checkpoint = true
    UIManager:close(self, "flashui")
end

function SudokuView:_persistTerminal(action, on_success)
    local record = self.game:final_record()
    local persist_terminal
    local delete_active_save

    local function complete()
        self._finalization_complete = true
        on_success()
    end

    delete_active_save = function()
        local deleted, delete_err = self:deleteSave()
        if deleted then
            complete()
            return
        end
        self:showPersistenceFailure(_("remove the active game save"), delete_err, delete_active_save, complete)
    end

    persist_terminal = function()
        if self.stats then
            if not self._terminal_stats_applied then
                local added, add_err = stats.add(self.stats, record)
                if not added then
                    self:showPersistenceFailure(action, add_err, persist_terminal, delete_active_save)
                    return
                end
                self._terminal_stats_applied = true
            end
            local saved, save_err = self:persistStats()
            if not saved then
                self:showPersistenceFailure(action, save_err, persist_terminal, delete_active_save)
                return
            end
        end
        delete_active_save()
    end

    persist_terminal()
end

function SudokuView:onWin()
    -- A hold armed by a key press just before the winning move must not
    -- fire behind the win dialog (the callback guard also catches this,
    -- since the game is finished by then; invalidating here keeps the
    -- state self-consistent).
    self:_invalidateNotesHold()
    if self._finalization_complete then
        self:_showWinDialog()
        return
    end
    if not self.game:is_finished() then
        local record, err = self.game:finish()
        if not record then
            logger.warn("sudoku: failed to finish game: " .. tostring(err))
            return
        end
    end
    self:_persistTerminal(_("save the completed game statistics"), function()
        self:_showWinDialog()
    end)
end

function SudokuView:_showWinDialog()
    return dialogs.show_win_dialog(self)
end

function SudokuView:onGiveUp()
    self:_invalidateNotesHold()
    if not self.game:is_finished() then
        local record, err = self.game:give_up()
        if not record then
            logger.warn("sudoku: failed to give up: " .. tostring(err))
            return
        end
    end
    self:_persistTerminal(_("save the give-up statistics"), function()
        self:_closeWithoutCheckpoint()
    end)
end

function SudokuView:onQuit()
    -- The win dialog also closes the view; a finished game must not be
    -- re-saved (the save was already cleared) or re-tracked in the log.
    if self.game:is_finished() then
        self:_closeWithoutCheckpoint()
        return
    end
    self:_invalidateNotesHold()
    self.game:pause()
    local ok, err = self:checkpoint("quit")
    if ok then
        self:_closeWithoutCheckpoint()
        return true
    end
    self:showPersistenceFailure(_("save the game before quitting"), err, function()
        self:onQuit()
    end, function()
        self:_closeWithoutCheckpoint()
    end)
    return nil, err
end

function SudokuView:onClose()
    self:onQuit()
end

function SudokuView:onFlushSettings()
    if self._skip_checkpoint or self.game:is_finished() then
        return true
    end
    local should_resume = self.game.timer.running and not self.menu_open
    self.game:pause()
    local persist
    local function finish()
        self._pending_persistence = nil
        if should_resume then
            self.game:resume()
        end
    end
    persist = function()
        local ok, err = self:checkpoint("flush")
        if ok then
            finish()
            return
        end
        self._pending_persistence = { action = _("save the game"), err = err }
        self:showPersistenceFailure(_("save the game"), err, persist, finish)
    end
    persist()
    return true
end

function SudokuView:_closeMenuAndResume(dialog, fn)
    return dialogs.close_menu_and_resume(self, dialog, fn)
end

function SudokuView:_openDifficultyPicker(cancel_cb)
    return dialogs.open_difficulty_picker(self, cancel_cb)
end

function SudokuView:_confirmReset(cancel_cb)
    return dialogs.confirm_reset(self, cancel_cb)
end

function SudokuView:_applyReset(new_stats, new_id, on_success)
    if new_stats then
        if self.stats then
            for key in pairs(self.stats) do
                self.stats[key] = nil
            end
            for key, value in pairs(new_stats) do
                self.stats[key] = value
            end
        else
            self.stats = new_stats
        end
    end
    local ok, err = self.game:reset()
    if not ok then
        return nil, err
    end
    self.game.id = new_id
    self.selected = nil
    self.armed = nil
    self.notes_mode = false
    self._log_started = false
    self._hint_result = nil
    self._hint_stage = 0
    self._hint_cells = {}
    self._match_value = nil
    self._match_cells = {}
    self._completed_digits = self.game:completed_digits()
    self._terminal_stats_applied = false
    self._finalization_complete = false
    self:markToolRowIfChanged()
    self:markNumberRow()
    if on_success then
        on_success()
    end
    return true
end

function SudokuView:resetGame(on_success)
    local candidate, clone_err = game_model.restore(self.game:serialize(), { now = self.game.now })
    if not candidate then
        return nil, clone_err
    end
    local reset, reset_err = candidate:reset()
    if not reset then
        return nil, reset_err
    end

    local new_stats = self.stats
    local new_id = self.game.id
    if self.stats then
        new_stats, clone_err = stats.from_table(stats.to_table(self.stats))
        if not new_stats then
            return nil, clone_err
        end
        local identity = self.game:is_started() and self.game:started_record() or nil
        local dropped, drop_err = stats.drop_in_progress(new_stats, self.game.id, identity)
        if not dropped then
            return nil, drop_err
        end
        new_id = stats.reserve_id(new_stats)
        candidate.id = new_id
    end

    local adapter = self.storage_adapter or storage
    local persist_reset
    local function apply_reset()
        local applied, apply_err = self:_applyReset(new_stats, new_id, on_success)
        if not applied then
            logger.warn("sudoku: reset failed: " .. tostring(apply_err))
        end
    end
    persist_reset = function()
        if new_stats and self.stats_path then
            local stats_saved, stats_err = adapter.save(self.stats_path, stats.to_table(new_stats))
            if not stats_saved then
                self:showPersistenceFailure(
                    _("save statistics before resetting"),
                    stats_err,
                    persist_reset,
                    apply_reset
                )
                return
            end
        end
        if self.save_path then
            local game_saved, game_err = adapter.save(self.save_path, candidate:serialize())
            if not game_saved then
                self:showPersistenceFailure(_("save the reset game"), game_err, persist_reset, apply_reset)
                return
            end
        end
        apply_reset()
    end
    persist_reset()
    return true
end

function SudokuView:_confirmGiveUp(cancel_cb)
    return dialogs.confirm_give_up(self, cancel_cb)
end

function SudokuView:openMenu()
    return dialogs.open_menu(self)
end

-- Opens the statistics screen on top of the open pause menu or win dialog
-- (closing the stats view reveals the previous screen again). "full":
-- the previous view stays open underneath, so the new fullscreen page must
-- refresh the whole screen itself.
function SudokuView:showStats(parent_close_cb)
    self:updateStats(false)
    local statsview = require("sudokuplus.ui.statsview")
    UIManager:show(
        statsview.dashboard(self.stats or stats.new(), {
            replay_cb = function(descriptor)
                if parent_close_cb then
                    parent_close_cb()
                end
                if self.replay_cb then
                    self.replay_cb(descriptor)
                end
            end,
        }),
        "full"
    )
end

function SudokuView:onSuspend()
    self.game:pause()
    -- Key releases are dropped while the device sleeps, so a pending notes
    -- hold could never be invalidated by its release; drop it here instead.
    self:_invalidateNotesHold()
    if not self.game:is_finished() then
        local ok, err = self:checkpoint("suspend")
        if not ok then
            self._pending_persistence = { action = _("save the suspended game"), err = err }
        end
    end
    return true
end

function SudokuView:onResume()
    if self._pending_persistence then
        local pending = self._pending_persistence
        self:showPersistenceFailure(pending.action, pending.err, function()
            local ok, err = self:checkpoint("resume-retry")
            if ok then
                self._pending_persistence = nil
                if not self.menu_open and not self.game:is_finished() then
                    self.game:resume()
                end
                self:refreshFull()
            else
                pending.err = err
                self:onResume()
            end
        end, function()
            self._pending_persistence = nil
            if not self.menu_open and not self.game:is_finished() then
                self.game:resume()
            end
            self:refreshFull()
        end)
        return true
    end
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
