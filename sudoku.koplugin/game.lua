local bit = require("bit")
local board = require("core.board")
local hints = require("core.hints")
local masks = require("core.masks")
local solver = require("core.solver")
local util = require("core.util")
local units = require("core.techniques.units")

local game = {}
local mt = {}
mt.__index = mt

local VERSION = 2
local FULL_CANDIDATE_MASK = 0x1FF
-- Saves are only ever written while paused, so a save claiming a *running*
-- timer must have a wall-clock start timestamp close to now; anything further
-- out is a corrupted/edited save whose started value would inflate elapsed().
local MAX_TIMER_STARTED_DRIFT = 7 * 24 * 3600

local function new_mask_grid(value)
    local grid = {}
    for row = 1, 9 do
        grid[row] = {}
        for col = 1, 9 do
            grid[row][col] = value or 0
        end
    end
    return grid
end

local function build_notes_grid(b, constraint_masks, autofill)
    local notes = {}
    for r = 0, 8 do
        local row = {}
        for c = 0, 8 do
            local mask = 0
            if autofill and board.is_empty(b, r, c) then
                mask = masks.compute_candidates_mask_for_cell(constraint_masks, r, c)
            end
            row[c + 1] = mask
        end
        notes[r + 1] = row
    end
    return notes
end

local function deep_copy(value)
    if type(value) ~= "table" then
        return value
    end
    local copy = {}
    for key, nested in pairs(value) do
        copy[key] = deep_copy(nested)
    end
    return copy
end

local function digit_bit(value)
    return bit.lshift(1, value - 1)
end

local function validate_cell(r, c)
    if type(r) ~= "number" or r % 1 ~= 0 or r < 0 or r > 8 then
        return nil, "row must be an integer in the range 0..8"
    end
    if type(c) ~= "number" or c % 1 ~= 0 or c < 0 or c > 8 then
        return nil, "column must be an integer in the range 0..8"
    end
    return true
end

local function validate_value(value)
    if type(value) ~= "number" or value % 1 ~= 0 or value < 1 or value > 9 then
        return nil, "value must be an integer in the range 1..9"
    end
    return true
end

local function validate_non_negative(value, name)
    if type(value) ~= "number" or value % 1 ~= 0 or value < 0 then
        return nil, name .. " must be a non-negative integer"
    end
    return true
end

local function cell_index(r, c)
    return r * 9 + c + 1
end

-- Builds the constraint-mask structure (core.masks) that reflects `b`, so the
-- game layer reuses core's "which digits are legal in a cell" implementation
-- instead of re-deriving it. Built on demand (the game state keeps the board
-- as its source of truth; no parallel mask cache to drift).
local function constraint_masks_for(b)
    local m = masks.new()
    for i = 1, 81 do
        local value = b[i]
        if value ~= 0 then
            masks.add_number(m, math.floor((i - 1) / 9), (i - 1) % 9, value)
        end
    end
    return m
end

local function legal_mask_for(b, r, c)
    return masks.compute_candidates_mask_for_cell(constraint_masks_for(b), r, c)
end

-- Peer enumeration is shared with the core techniques via units.each_peer, so
-- the game layer and the solver can never disagree on what a peer is.
local function is_safe_board(b, r, c, value)
    local safe = true
    units.each_peer(r, c, function(cr, cc)
        if b[cell_index(cr, cc)] == value then
            safe = false
        end
    end)
    return safe
end

local function conflicts_board(b, r, c)
    local value = b[cell_index(r, c)]
    if value == 0 then
        return false
    end
    local conflict = false
    units.each_peer(r, c, function(cr, cc)
        if b[cell_index(cr, cc)] == value then
            conflict = true
        end
    end)
    return conflict
end

-- Removes `value` from the notes of empty peer cells and returns the list of
-- cleaned {row, col, value} entries for undo.
local function auto_clean(self, r, c, value)
    local cleaned = {}
    local v_bit = digit_bit(value)
    units.each_peer(r, c, function(cr, cc)
        local index = cell_index(cr, cc)
        if self.board[index] == 0 then
            local cell_notes = self.notes[cr + 1][cc + 1]
            if bit.band(cell_notes, v_bit) ~= 0 then
                self.notes[cr + 1][cc + 1] = bit.band(cell_notes, bit.bnot(v_bit))
                cleaned[#cleaned + 1] = { cr, cc, value }
            end
        end
    end)
    return cleaned
end

local function add_note_digit(self, cr, cc, value)
    local index = cell_index(cr, cc)
    local value_bit = digit_bit(value)
    if self.board[index] == 0 and bit.band(self.manual_removed[cr + 1][cc + 1], value_bit) == 0 then
        self.notes[cr + 1][cc + 1] = bit.bor(self.notes[cr + 1][cc + 1], digit_bit(value))
    end
end

local function remove_note_digit(self, cr, cc, value)
    local index = cell_index(cr, cc)
    if self.board[index] == 0 then
        self.notes[cr + 1][cc + 1] = bit.band(self.notes[cr + 1][cc + 1], bit.bnot(digit_bit(value)))
    end
end

-- The most recent placement in (r, c): the entry that set the value
-- currently occupying the cell (or the one whose undo an erase mirrors).
local function last_place_entry(self, r, c)
    for i = self.undo_ptr, 1, -1 do
        local entry = self.history[i]
        if entry.kind == "place" and entry.r == r and entry.c == c then
            return entry
        end
    end
    return nil
end

-- Re-adds exactly the notes the last placement in (r, c) auto-cleaned (what
-- an undo of that placement would restore). Peers the user never noted are
-- left untouched.
local function restored_cleaned(self, r, c)
    local entry = last_place_entry(self, r, c)
    local restored = {}
    if entry then
        for _, cell in ipairs(entry.cleaned or {}) do
            local cr, cc, value = cell[1], cell[2], cell[3]
            if
                self.board[cell_index(cr, cc)] == 0
                and bit.band(self.manual_removed[cr + 1][cc + 1], digit_bit(value)) == 0
                and is_safe_board(self.board, cr, cc, value)
                and bit.band(self.notes[cr + 1][cc + 1], digit_bit(value)) == 0
            then
                self.notes[cr + 1][cc + 1] = bit.bor(self.notes[cr + 1][cc + 1], digit_bit(value))
                restored[#restored + 1] = { cr, cc, value }
            end
        end
    end
    return restored
end

local function toggle_note_digit(self, r, c, value, add)
    local v_bit = digit_bit(value)
    local mask = self.notes[r + 1][c + 1]
    if add then
        self.notes[r + 1][c + 1] = bit.bor(mask, v_bit)
    else
        self.notes[r + 1][c + 1] = bit.band(mask, bit.bnot(v_bit))
    end
end

local function clear_fixed_revealed(self)
    for key in pairs(self._revealed) do
        local index = key + 1
        if self.board[index] == 0 or self.board[index] == self.solution[index] then
            self._revealed[key] = nil
        end
    end
end

local function commit(self, entry)
    self.undo_ptr = self.undo_ptr + 1
    self.history[self.undo_ptr] = entry
    for i = self.undo_ptr + 1, #self.history do
        self.history[i] = nil
    end
    self._revision = self._revision + 1
    -- A game is "started" once the user adds at least one number or note
    -- (the game-log definition); the timestamp feeds per-game stats.
    if
        not self._started
        and (entry.kind == "place" or (entry.kind == "note" and entry.added) or entry.kind == "fill_all_notes")
    then
        self._started = true
        self._started_at = self.now()
    end
    clear_fixed_revealed(self)
end

local function wrong_cells(self)
    local wrong = {}
    for i = 1, 81 do
        if self.board[i] ~= 0 and self.board[i] ~= self.solution[i] then
            wrong[#wrong + 1] = i - 1
        end
    end
    return wrong
end

local function finish_timer(self)
    local timestamp = self.now()
    if self.timer.running then
        self.timer.elapsed = self.timer.elapsed + math.max(0, timestamp - self.timer.started)
        self.timer.running = false
    end
    return timestamp
end

function game.new(options)
    if type(options) ~= "table" then
        return nil, "options must be a table"
    end

    local puzzle = options.puzzle
    local solution = options.solution
    local difficulty = options.difficulty
    local now = options.now

    if type(puzzle) ~= "table" then
        return nil, "puzzle must be a board table"
    end
    local constraint_masks, puzzle_err = solver.validate(puzzle)
    if not constraint_masks then
        return nil, "invalid puzzle: " .. puzzle_err
    end
    if board.count_clues(puzzle) == 0 then
        return nil, "puzzle must contain at least one given"
    end

    if type(solution) ~= "table" then
        return nil, "solution must be a board table"
    end
    local solution_masks, solution_err = solver.validate(solution)
    if not solution_masks then
        return nil, "invalid solution: " .. solution_err
    end
    if board.count_clues(solution) ~= 81 then
        return nil, "solution must contain 81 values"
    end
    for r = 0, 8 do
        for c = 0, 8 do
            local given = board.get(puzzle, r, c)
            if given ~= 0 and board.get(solution, r, c) ~= given then
                return nil, "solution does not preserve the puzzle givens"
            end
        end
    end

    if type(difficulty) ~= "string" or not util.is_difficulty(difficulty) then
        return nil, "difficulty must be one of beginner, easy, medium, hard, master, expert"
    end
    if type(now) ~= "function" then
        return nil, "now must be a function returning the current time in seconds"
    end
    local autofill_notes = options.autofill_notes
    if autofill_notes ~= nil and type(autofill_notes) ~= "boolean" then
        return nil, "autofill_notes must be a boolean"
    end
    -- Optional reproduction seed (from generator.generate_game); lets a saved
    -- game be recreated exactly.
    local seed = options.seed
    if seed ~= nil and (type(seed) ~= "number" or seed % 1 ~= 0) then
        return nil, "seed must be an integer"
    end
    -- Optional stable identity for the game log (assigned by the plugin
    -- layer); threaded through serialize/restore like seed.
    local id = options.id
    if id ~= nil and (type(id) ~= "number" or id % 1 ~= 0 or id < 0) then
        return nil, "id must be a non-negative integer"
    end

    local notes = build_notes_grid(puzzle, constraint_masks, autofill_notes)

    local instance = {
        puzzle = board.clone(puzzle),
        solution = board.clone(solution),
        board = board.clone(puzzle),
        notes = notes,
        manual_removed = new_mask_grid(),
        _difficulty = difficulty,
        now = now,
        autofill_notes = not not autofill_notes,
        timer = { running = true, started = now(), elapsed = 0 },
        _revision = 0,
        history = {},
        undo_ptr = 0,
        _mistakes = 0,
        _check_errors = 0,
        _revealed = {},
        _hints = {},
        _started = false,
        _started_at = nil,
        finished = false,
        seed = seed,
        id = id,
    }
    return setmetatable(instance, mt)
end

function mt:get(r, c)
    return board.get(self.board, r, c)
end

function mt:is_given(r, c)
    local ok, err = validate_cell(r, c)
    if not ok then
        return nil, err
    end
    return self.puzzle[cell_index(r, c)] ~= 0
end

function mt:get_notes(r, c)
    local ok, err = validate_cell(r, c)
    if not ok then
        return nil, err
    end
    return self.notes[r + 1][c + 1]
end

-- Cells that show `value` anywhere: as a placed digit (given or entry) or as
-- a candidate in the notes. Returned as a set keyed row * 9 + col. Drives the
-- digit-match highlight when a digit cell is selected.
function mt:digit_cells(value)
    local value_ok, value_err = validate_value(value)
    if not value_ok then
        return nil, value_err
    end
    local set = {}
    local v_bit = digit_bit(value)
    for r = 0, 8 do
        for c = 0, 8 do
            if self.board[cell_index(r, c)] == value or bit.band(self.notes[r + 1][c + 1], v_bit) ~= 0 then
                set[r * 9 + c] = true
            end
        end
    end
    return set
end

-- The set of digits placed exactly nine times (fully solved). Used to grey out
-- the number selector; the digit stays selectable, this is purely visual.
function mt:completed_digits()
    local counts = {}
    for i = 1, 81 do
        local value = self.board[i]
        if value ~= 0 then
            counts[value] = (counts[value] or 0) + 1
        end
    end
    local result = {}
    for value = 1, 9 do
        if counts[value] == 9 then
            result[value] = true
        end
    end
    return result
end

-- Empty cells whose notes the user cleared (ground truth): the hint engine
-- cannot use them, so deduction may be blocked until notes are re-added.
function mt:notes_needed()
    local result = {}
    for r = 0, 8 do
        for c = 0, 8 do
            if
                self.board[cell_index(r, c)] == 0
                and self.notes[r + 1][c + 1] == 0
                and self.manual_removed[r + 1][c + 1] ~= 0
            then
                result[#result + 1] = { r, c }
            end
        end
    end
    return result
end

function mt:conflicts()
    local result = {}
    for r = 0, 8 do
        for c = 0, 8 do
            if conflicts_board(self.board, r, c) then
                result[#result + 1] = { r, c }
            end
        end
    end
    return result
end

-- The set of cells whose paint can change when the history entry is undone
-- or redone: its cell, the peers whose conflict state the entry's value
-- changes can affect, and the peers whose notes the entry cleaned/restored.
local function entry_affected(self, entry)
    if entry.kind == "fill_all_notes" then
        local affected = {}
        for r = 0, 8 do
            for c = 0, 8 do
                if self.board[cell_index(r, c)] == 0 then
                    affected[r * 9 + c] = true
                end
            end
        end
        return affected
    end
    local affected = { [entry.r * 9 + entry.c] = true }
    local function peers_with(value)
        if value ~= 0 then
            units.each_peer(entry.r, entry.c, function(cr, cc)
                if self.board[cell_index(cr, cc)] == value then
                    affected[cr * 9 + cc] = true
                end
            end)
        end
    end
    if entry.kind == "place" then
        peers_with(entry.value)
        peers_with(entry.old)
    elseif entry.kind == "erase" then
        peers_with(entry.old)
    end
    for _, cell in ipairs(entry.cleaned or {}) do
        affected[cell[1] * 9 + cell[2]] = true
    end
    for _, cell in ipairs(entry.restored or {}) do
        affected[cell[1] * 9 + cell[2]] = true
    end
    return affected
end

-- The set (keyed r * 9 + c) of cells whose painted appearance can change
-- when `value` is placed in or erased from (r, c): the cell itself, peers
-- holding `value` or the value being replaced (conflict highlights), peers
-- with `value` in their notes (auto-clean), and the peers the last
-- placement in (r, c) auto-cleaned (notes an erase or replace may restore).
-- Computed as the repaint set of the place entry that move would commit,
-- so this path can never drift from what an undo or redo of it repaints.
function mt:affected_cells(r, c, value)
    local ok, err = validate_cell(r, c)
    if not ok then
        return nil, err
    end
    local value_ok, value_err = validate_value(value)
    if not value_ok then
        return nil, value_err
    end
    local cleaned = {}
    local v_bit = digit_bit(value)
    units.each_peer(r, c, function(cr, cc)
        if bit.band(self.notes[cr + 1][cc + 1], v_bit) ~= 0 then
            cleaned[#cleaned + 1] = { cr, cc, value }
        end
    end)
    local restored = {}
    local entry = last_place_entry(self, r, c)
    if entry then
        for _, cell in ipairs(entry.cleaned or {}) do
            restored[#restored + 1] = cell
        end
    end
    return entry_affected(self, {
        kind = "place",
        r = r,
        c = c,
        value = value,
        old = self.board[cell_index(r, c)],
        cleaned = cleaned,
        restored = restored,
    })
end

-- Cells whose paint can change when the most recent move was undone (the
-- entry at undo_ptr + 1); {} when nothing was undone. Valid after `undo()`.
function mt:undo_affected_cells()
    local entry = self.history[self.undo_ptr + 1]
    if not entry then
        return {}
    end
    return entry_affected(self, entry)
end

-- Cells whose paint can change when the most recent undo was redone (the
-- entry at undo_ptr); {} when nothing can be redone. Valid after `redo()`.
function mt:redo_affected_cells()
    local entry = self.history[self.undo_ptr]
    if not entry then
        return {}
    end
    return entry_affected(self, entry)
end

function mt:difficulty()
    return self._difficulty
end

function mt:revision()
    return self._revision
end

function mt:mistakes()
    return self._mistakes
end

function mt:check_errors()
    return self._check_errors
end

function mt:is_finished()
    return self.finished
end

-- True once the player has added at least one number or note (the game-log
-- definition of "started"); it never reverts, even if every move is undone.
function mt:is_started()
    return self._started
end

-- Wall-clock timestamp of the first started move (nil before any).
function mt:started_at()
    return self._started_at
end

-- Total user moves committed (place/erase/note/notes_clear); undo/redo do
-- not count.
function mt:move_count()
    return #self.history
end

-- Per-game progress: `filled` user-placed digits (beyond the givens),
-- `correct` among them matching the solution, `clues` givens and `total`.
function mt:progress()
    local clues = 0
    local filled = 0
    local correct = 0
    for i = 1, 81 do
        if self.puzzle[i] ~= 0 then
            clues = clues + 1
        elseif self.board[i] ~= 0 then
            filled = filled + 1
            if self.board[i] == self.solution[i] then
                correct = correct + 1
            end
        end
    end
    return { filled = filled, correct = correct, clues = clues, total = 81 }
end

function mt:hints()
    local copy = {}
    for i, entry in ipairs(self._hints) do
        copy[i] = { id = entry.id, technique = entry.technique, flag = entry.flag }
    end
    return copy
end

function mt:place(r, c, value)
    local ok, err = validate_cell(r, c)
    if not ok then
        return nil, err
    end
    local value_ok, value_err = validate_value(value)
    if not value_ok then
        return nil, value_err
    end
    if self.finished then
        return nil, "game is finished"
    end
    local index = cell_index(r, c)
    if self.puzzle[index] ~= 0 then
        return nil, "cannot modify a given cell"
    end
    if self.board[index] == value then
        return true
    end

    local old = self.board[index]
    local old_notes = self.notes[r + 1][c + 1]
    self.board[index] = 0
    local restored = {}
    if old ~= 0 then
        restored = restored_cleaned(self, r, c)
    end
    self.board[index] = value
    local cleaned = auto_clean(self, r, c, value)
    self.notes[r + 1][c + 1] = 0
    if conflicts_board(self.board, r, c) then
        self._mistakes = self._mistakes + 1
    end

    commit(self, {
        kind = "place",
        r = r,
        c = c,
        value = value,
        old = old,
        old_notes = old_notes,
        restored = restored,
        cleaned = cleaned,
    })
    return true
end

-- The note mask the cell had before its current value was placed (what an
-- undo of that placement would restore), or 0 when it was untouched.
local function restored_cell_notes(self, r, c)
    local entry = last_place_entry(self, r, c)
    local previous = entry and entry.old_notes or 0
    return bit.band(previous, legal_mask_for(self.board, r, c))
end

function mt:erase(r, c)
    local ok, err = validate_cell(r, c)
    if not ok then
        return nil, err
    end
    if self.finished then
        return nil, "game is finished"
    end
    local index = cell_index(r, c)
    if self.puzzle[index] ~= 0 then
        return nil, "cannot modify a given cell"
    end
    if self.board[index] == 0 then
        return true
    end

    local old = self.board[index]
    self.board[index] = 0
    local restored = restored_cleaned(self, r, c)
    self.notes[r + 1][c + 1] = restored_cell_notes(self, r, c)

    commit(self, { kind = "erase", r = r, c = c, old = old, restored = restored })
    return true
end

function mt:toggle_note(r, c, value)
    local ok, err = validate_cell(r, c)
    if not ok then
        return nil, err
    end
    local value_ok, value_err = validate_value(value)
    if not value_ok then
        return nil, value_err
    end
    if self.finished then
        return nil, "game is finished"
    end
    if self.board[cell_index(r, c)] ~= 0 then
        return nil, "cannot edit notes on a filled cell"
    end

    local v_bit = digit_bit(value)
    local has = bit.band(self.notes[r + 1][c + 1], v_bit) ~= 0
    if not has and not is_safe_board(self.board, r, c, value) then
        return nil, "digit already present in the same row, column or box"
    end

    toggle_note_digit(self, r, c, value, not has)
    local value_bit = digit_bit(value)
    local old_manual_removed = self.manual_removed[r + 1][c + 1]
    if has then
        self.manual_removed[r + 1][c + 1] = bit.bor(old_manual_removed, value_bit)
    else
        self.manual_removed[r + 1][c + 1] = bit.band(old_manual_removed, bit.bnot(value_bit))
    end
    commit(self, {
        kind = "note",
        r = r,
        c = c,
        value = value,
        added = not has,
        old_manual_removed = old_manual_removed,
    })
    return true
end

function mt:clear_notes(r, c)
    local ok, err = validate_cell(r, c)
    if not ok then
        return nil, err
    end
    if self.finished then
        return nil, "game is finished"
    end
    if self.board[cell_index(r, c)] ~= 0 then
        return nil, "cannot edit notes on a filled cell"
    end

    local old = self.notes[r + 1][c + 1]
    if old == 0 then
        return true
    end
    self.notes[r + 1][c + 1] = 0
    local old_manual_removed = self.manual_removed[r + 1][c + 1]
    self.manual_removed[r + 1][c + 1] = FULL_CANDIDATE_MASK

    commit(self, {
        kind = "notes_clear",
        r = r,
        c = c,
        old_mask = old,
        old_manual_removed = old_manual_removed,
    })
    return true
end

local function undo_entry(self, entry)
    if entry.kind == "place" then
        self.board[cell_index(entry.r, entry.c)] = entry.old
        self.notes[entry.r + 1][entry.c + 1] = entry.old_notes
        for _, restored in ipairs(entry.restored or {}) do
            remove_note_digit(self, restored[1], restored[2], restored[3])
        end
        for _, cleaned in ipairs(entry.cleaned or {}) do
            add_note_digit(self, cleaned[1], cleaned[2], cleaned[3])
        end
    elseif entry.kind == "erase" then
        self.board[cell_index(entry.r, entry.c)] = entry.old
        self.notes[entry.r + 1][entry.c + 1] = 0
        for _, restored in ipairs(entry.restored or {}) do
            remove_note_digit(self, restored[1], restored[2], restored[3])
        end
    elseif entry.kind == "note" then
        if entry.old_manual_removed ~= nil then
            self.manual_removed[entry.r + 1][entry.c + 1] = entry.old_manual_removed
        end
        toggle_note_digit(self, entry.r, entry.c, entry.value, not entry.added)
    elseif entry.kind == "notes_clear" then
        self.notes[entry.r + 1][entry.c + 1] = entry.old_mask
        if entry.old_manual_removed ~= nil then
            self.manual_removed[entry.r + 1][entry.c + 1] = entry.old_manual_removed
        end
    elseif entry.kind == "fill_all_notes" then
        self.notes = deep_copy(entry.old_notes)
        self.manual_removed = deep_copy(entry.old_manual_removed)
    end
end

local function redo_entry(self, entry)
    if entry.kind == "place" then
        self.board[cell_index(entry.r, entry.c)] = entry.value
        self.notes[entry.r + 1][entry.c + 1] = 0
        auto_clean(self, entry.r, entry.c, entry.value)
    elseif entry.kind == "erase" then
        self.board[cell_index(entry.r, entry.c)] = 0
        restored_cleaned(self, entry.r, entry.c)
        self.notes[entry.r + 1][entry.c + 1] = restored_cell_notes(self, entry.r, entry.c)
    elseif entry.kind == "note" then
        local value_bit = digit_bit(entry.value)
        local old_manual_removed = entry.old_manual_removed or self.manual_removed[entry.r + 1][entry.c + 1]
        if entry.added then
            self.manual_removed[entry.r + 1][entry.c + 1] = bit.band(old_manual_removed, bit.bnot(value_bit))
        else
            self.manual_removed[entry.r + 1][entry.c + 1] = bit.bor(old_manual_removed, value_bit)
        end
        toggle_note_digit(self, entry.r, entry.c, entry.value, entry.added)
    elseif entry.kind == "notes_clear" then
        self.notes[entry.r + 1][entry.c + 1] = 0
        self.manual_removed[entry.r + 1][entry.c + 1] = FULL_CANDIDATE_MASK
    elseif entry.kind == "fill_all_notes" then
        self.notes = deep_copy(entry.new_notes)
        self.manual_removed = new_mask_grid()
    end
end

function mt:undo()
    if self.finished then
        return nil, "game is finished"
    end
    if self.undo_ptr == 0 then
        return nil, "nothing to undo"
    end
    undo_entry(self, self.history[self.undo_ptr])
    self.undo_ptr = self.undo_ptr - 1
    self._revision = self._revision + 1
    clear_fixed_revealed(self)
    return true
end

function mt:redo()
    if self.finished then
        return nil, "game is finished"
    end
    if self.undo_ptr >= #self.history then
        return nil, "nothing to redo"
    end
    redo_entry(self, self.history[self.undo_ptr + 1])
    self.undo_ptr = self.undo_ptr + 1
    self._revision = self._revision + 1
    clear_fixed_revealed(self)
    return true
end

function mt:can_undo()
    return self.undo_ptr > 0
end

function mt:can_redo()
    return self.undo_ptr < #self.history
end

function mt:elapsed()
    local elapsed = self.timer.elapsed
    if self.timer.running then
        elapsed = elapsed + math.max(0, self.now() - self.timer.started)
    end
    return elapsed
end

function mt:pause()
    if self.finished then
        return nil, "game is finished"
    end
    if not self.timer.running then
        return true
    end
    self.timer.elapsed = self.timer.elapsed + math.max(0, self.now() - self.timer.started)
    self.timer.running = false
    return true
end

function mt:resume()
    if self.finished then
        return nil, "game is finished"
    end
    if self.timer.running then
        return true
    end
    self.timer.started = self.now()
    self.timer.running = true
    return true
end

function mt:check_for_errors()
    if self.finished then
        return nil, "game is finished"
    end
    local wrong = wrong_cells(self)
    local wrong_set = {}
    for _, key in ipairs(wrong) do
        wrong_set[key] = true
    end
    for key in pairs(self._revealed) do
        if not wrong_set[key] then
            self._revealed[key] = nil
        end
    end
    for _, key in ipairs(wrong) do
        if not self._revealed[key] then
            self._revealed[key] = true
            self._check_errors = self._check_errors + 1
        end
    end
    local result = {}
    for _, key in ipairs(wrong) do
        result[#result + 1] = { math.floor(key / 9), key % 9 }
    end
    return result
end

function mt:revealed()
    local result = {}
    for key in pairs(self._revealed) do
        result[#result + 1] = { math.floor(key / 9), key % 9 }
    end
    return result
end

function mt:is_won()
    for i = 1, 81 do
        if self.board[i] ~= self.solution[i] then
            return false
        end
    end
    return true
end

local function make_record(self, status, ended_at)
    local hint_ids = {}
    for i, entry in ipairs(self._hints) do
        hint_ids[i] = entry.technique
    end
    local progress = self:progress()
    return {
        status = status,
        id = self.id,
        seed = self.seed,
        difficulty = self._difficulty,
        duration = self:elapsed(),
        hints = hint_ids,
        mistakes = self._mistakes,
        check_errors = self._check_errors,
        started_at = self._started_at,
        ended_at = ended_at,
        moves = self:move_count(),
        filled = progress.filled,
        correct = progress.correct,
        puzzle = board.to_string(self.puzzle),
        solution = board.to_string(self.solution),
        board = board.to_string(self.board),
    }
end

-- A snapshot of the live game for the game log: same shape as a final
-- record, but marked in_progress (upserted by stats.track at save points).
function mt:started_record()
    return make_record(self, "in_progress", nil)
end

function mt:final_record()
    return self._record
end

local function finalize_game(self, status)
    if self.finished then
        return nil, "game is already finished"
    end
    local timestamp = finish_timer(self)
    local record = make_record(self, status, timestamp)
    self.finished = true
    self._record = record
    return record
end

function mt:finish()
    if self.finished then
        return nil, "game is already finished"
    end
    if not self:is_won() then
        return nil, "board is not solved"
    end
    return finalize_game(self, "finished")
end

function mt:give_up()
    return finalize_game(self, "give_up")
end

function mt:hint()
    if self.finished then
        return nil, "game is finished"
    end
    if #self:conflicts() > 0 then
        return nil, "board has conflicts"
    end
    for i = 1, 81 do
        if self.board[i] ~= 0 and self.board[i] ~= self.solution[i] then
            return nil, "board does not match the solution"
        end
    end
    -- Notes are ground truth once the user has started them; untouched
    -- empty cells are substituted with their board-legal candidates so the
    -- hint engine can assume fully filled notes.
    local constraint_masks = constraint_masks_for(self.board)
    local derived = {}
    for r = 0, 8 do
        derived[r + 1] = {}
        for c = 0, 8 do
            local mask = self.notes[r + 1][c + 1]
            if self.board[cell_index(r, c)] == 0 and mask == 0 and self.manual_removed[r + 1][c + 1] == 0 then
                mask = masks.compute_candidates_mask_for_cell(constraint_masks, r, c)
            end
            derived[r + 1][c + 1] = mask
        end
    end
    local result, err = hints.next({
        board = self.board,
        notes = derived,
        solution = self.solution,
        revision = self._revision,
    })
    if not result then
        return nil, err
    end
    if result.status == "available" then
        self._hints[#self._hints + 1] = {
            id = result.hint_id,
            technique = result.technique.id,
            flag = result.technique.flag,
        }
    end
    return result
end

function mt:apply_action(action)
    if type(action) ~= "table" then
        return nil, "action must be a table"
    end
    if action.type ~= "place" and action.type ~= "elim" then
        return nil, "action type must be 'place' or 'elim'"
    end
    local cell_ok, cell_err = validate_cell(action.row, action.col)
    if not cell_ok then
        return nil, cell_err
    end
    local value_ok, value_err = validate_value(action.value)
    if not value_ok then
        return nil, value_err
    end
    if self.finished then
        return nil, "game is finished"
    end
    if action.revision ~= nil and action.revision ~= self._revision then
        return nil, "action is stale"
    end

    if action.type == "place" then
        return self:place(action.row, action.col, action.value)
    end

    local index = cell_index(action.row, action.col)
    if self.board[index] ~= 0 then
        return nil, "cannot edit notes on a filled cell"
    end
    local v_bit = digit_bit(action.value)
    if bit.band(self.notes[action.row + 1][action.col + 1], v_bit) == 0 then
        return nil, "candidate is already absent"
    end
    local old_manual_removed = self.manual_removed[action.row + 1][action.col + 1]
    toggle_note_digit(self, action.row, action.col, action.value, false)
    self.manual_removed[action.row + 1][action.col + 1] = bit.bor(old_manual_removed, v_bit)
    commit(self, {
        kind = "note",
        r = action.row,
        c = action.col,
        value = action.value,
        added = false,
        old_manual_removed = old_manual_removed,
    })
    return true
end

function mt:reset()
    self.board = board.clone(self.puzzle)
    local constraint_masks = constraint_masks_for(self.puzzle)
    self.notes = build_notes_grid(self.puzzle, constraint_masks, self.autofill_notes)
    self.manual_removed = new_mask_grid()
    self.history = {}
    self.undo_ptr = 0
    self._revision = self._revision + 1
    self._mistakes = 0
    self._check_errors = 0
    self._revealed = {}
    self._hints = {}
    self._started = false
    self._started_at = nil
    self.timer = { running = self.timer.running, started = self.now(), elapsed = 0 }
    self.finished = false
    self._record = nil
    return true
end

function mt:fill_all_notes()
    if self.finished then
        return nil, "game is finished"
    end
    if #self:conflicts() > 0 then
        return nil, "board has conflicts"
    end
    for i = 1, 81 do
        if self.board[i] ~= 0 and self.board[i] ~= self.solution[i] then
            return nil, "board does not match the solution"
        end
    end
    local constraint_masks = constraint_masks_for(self.board)
    local new_notes = build_notes_grid(self.board, constraint_masks, true)
    local changed = false
    for r = 1, 9 do
        for c = 1, 9 do
            if self.notes[r][c] ~= new_notes[r][c] or self.manual_removed[r][c] ~= 0 then
                changed = true
                break
            end
        end
        if changed then
            break
        end
    end
    if not changed then
        return true
    end
    local old_notes = deep_copy(self.notes)
    local old_manual_removed = deep_copy(self.manual_removed)
    self.notes = new_notes
    self.manual_removed = new_mask_grid()
    commit(self, {
        kind = "fill_all_notes",
        old_notes = old_notes,
        old_manual_removed = old_manual_removed,
        new_notes = deep_copy(new_notes),
    })
    return true
end

function mt:serialize()
    local notes = {}
    for r = 1, 9 do
        local row = {}
        for c = 1, 9 do
            row[c] = self.notes[r][c]
        end
        notes[r] = row
    end
    local revealed = {}
    for key in pairs(self._revealed) do
        revealed[#revealed + 1] = key
    end
    table.sort(revealed)
    local hints_copy = {}
    for i, entry in ipairs(self._hints) do
        hints_copy[i] = { id = entry.id, technique = entry.technique, flag = entry.flag }
    end
    return {
        version = VERSION,
        difficulty = self._difficulty,
        puzzle = board.to_string(self.puzzle),
        solution = board.to_string(self.solution),
        board = board.to_string(self.board),
        notes = notes,
        manual_removed = deep_copy(self.manual_removed),
        history = deep_copy(self.history),
        undo_ptr = self.undo_ptr,
        revision = self._revision,
        mistakes = self._mistakes,
        check_errors = self._check_errors,
        revealed = revealed,
        timer = { running = self.timer.running, elapsed = self.timer.elapsed, started = self.timer.started },
        hints = hints_copy,
        finished = self.finished,
        seed = self.seed,
        id = self.id,
        started_at = self._started_at,
        autofill_notes = self.autofill_notes,
    }
end

local function validate_history_mask(mask)
    return type(mask) == "number"
        and util.is_finite(mask)
        and mask % 1 == 0
        and mask >= 0
        and mask <= FULL_CANDIDATE_MASK
end

local function validate_mask_grid(grid, name)
    if type(grid) ~= "table" then
        return nil, name .. " must be a 9x9 table"
    end
    local result = {}
    for r = 1, 9 do
        if type(grid[r]) ~= "table" then
            return nil, name .. " must be a 9x9 table"
        end
        result[r] = {}
        for c = 1, 9 do
            local mask = grid[r][c]
            if type(mask) ~= "number" or mask % 1 ~= 0 or mask < 0 or mask > FULL_CANDIDATE_MASK then
                return nil, name .. " masks must be integers in the range 0..511"
            end
            result[r][c] = mask
        end
    end
    return result
end

local function validate_history_cells(cells, name)
    if cells == nil then
        return {}
    end
    if type(cells) ~= "table" then
        return nil, "invalid history entry " .. name .. " list"
    end
    for _, cell in ipairs(cells) do
        if type(cell) ~= "table" or not validate_cell(cell[1], cell[2]) then
            return nil, "invalid history entry " .. name .. " cell"
        end
        if not validate_value(cell[3]) then
            return nil, "invalid history entry " .. name .. " value"
        end
    end
    return cells
end

local function validate_history(data)
    if type(data) ~= "table" then
        return nil, "history must be a table"
    end
    local history = {}
    for i, entry in ipairs(data) do
        if type(entry) ~= "table" then
            return nil, "history entries must be tables"
        end
        local kind = entry.kind
        if kind == "fill_all_notes" then
            local old_notes, old_err = validate_mask_grid(entry.old_notes, "history old_notes")
            if not old_notes then
                return nil, old_err
            end
            local old_manual_removed, mr_err =
                validate_mask_grid(entry.old_manual_removed, "history old_manual_removed")
            if not old_manual_removed then
                return nil, mr_err
            end
            local new_notes, new_err = validate_mask_grid(entry.new_notes, "history new_notes")
            if not new_notes then
                return nil, new_err
            end
            history[i] = {
                kind = "fill_all_notes",
                old_notes = old_notes,
                old_manual_removed = old_manual_removed,
                new_notes = new_notes,
            }
        else
            local cell_ok, cell_err = validate_cell(entry.r, entry.c)
            if not cell_ok then
                return nil, "invalid history entry: " .. cell_err
            end
            if kind == "place" then
                if not validate_value(entry.value) then
                    return nil, "invalid history entry value"
                end
                if
                    type(entry.old) ~= "number"
                    or not util.is_finite(entry.old)
                    or entry.old % 1 ~= 0
                    or entry.old < 0
                    or entry.old > 9
                then
                    return nil, "invalid history entry old value"
                end
                if not validate_history_mask(entry.old_notes) then
                    return nil, "invalid history entry note mask"
                end
            elseif kind == "erase" then
                if not validate_value(entry.old) then
                    return nil, "invalid history entry old value"
                end
            elseif kind == "note" then
                if not validate_value(entry.value) then
                    return nil, "invalid history entry value"
                end
                if type(entry.added) ~= "boolean" then
                    return nil, "invalid history entry flag"
                end
            elseif kind == "notes_clear" then
                if not validate_history_mask(entry.old_mask) then
                    return nil, "invalid history entry note mask"
                end
            else
                return nil, "unknown history entry kind"
            end
            if entry.old_manual_removed ~= nil and not validate_history_mask(entry.old_manual_removed) then
                return nil, "invalid history entry manual note mask"
            end
            local cleaned, cleaned_err = validate_history_cells(entry.cleaned, "cleaned")
            if not cleaned then
                return nil, cleaned_err
            end
            local restored, restored_err = validate_history_cells(entry.restored, "restored")
            if not restored then
                return nil, restored_err
            end
            local copy = deep_copy(entry)
            copy.cleaned = deep_copy(cleaned)
            copy.restored = deep_copy(restored)
            history[i] = copy
        end
    end
    return history
end

function game.restore(data, opts)
    if type(data) ~= "table" then
        return nil, "save data must be a table"
    end
    if data.version ~= 1 and data.version ~= VERSION then
        return nil, "unsupported save version: " .. tostring(data.version)
    end
    if type(opts) ~= "table" or type(opts.now) ~= "function" then
        return nil, "opts.now must be a function returning the current time in seconds"
    end
    if type(data.difficulty) ~= "string" or not util.is_difficulty(data.difficulty) then
        return nil, "invalid difficulty"
    end

    local puzzle, puzzle_err = board.from_string(data.puzzle)
    if not puzzle then
        return nil, "invalid puzzle: " .. puzzle_err
    end
    local solution, solution_err = board.from_string(data.solution)
    if not solution then
        return nil, "invalid solution: " .. solution_err
    end
    local current, current_err = board.from_string(data.board)
    if not current then
        return nil, "invalid board: " .. current_err
    end

    local constraint_masks, validate_err = solver.validate(puzzle)
    if not constraint_masks then
        return nil, "invalid puzzle: " .. validate_err
    end
    local solution_masks, solution_validate_err = solver.validate(solution)
    if not solution_masks then
        return nil, "invalid solution: " .. solution_validate_err
    end
    if board.count_clues(solution) ~= 81 then
        return nil, "solution must contain 81 values"
    end
    for i = 1, 81 do
        if puzzle[i] ~= 0 then
            if solution[i] ~= puzzle[i] then
                return nil, "solution does not preserve the puzzle givens"
            end
            if current[i] ~= puzzle[i] then
                return nil, "board does not preserve the puzzle givens"
            end
        end
    end

    local notes = {}
    if type(data.notes) ~= "table" then
        return nil, "notes must be a 9x9 table"
    end
    for r = 1, 9 do
        if type(data.notes[r]) ~= "table" then
            return nil, "notes must be a 9x9 table"
        end
        notes[r] = {}
        for c = 1, 9 do
            local mask = data.notes[r][c]
            if type(mask) ~= "number" or mask % 1 ~= 0 or mask < 0 or mask > FULL_CANDIDATE_MASK then
                return nil, "note masks must be integers in the range 0..511"
            end
            notes[r][c] = mask
        end
    end
    local manual_removed = new_mask_grid()
    if data.manual_removed ~= nil then
        if type(data.manual_removed) ~= "table" then
            return nil, "manual_removed must be a 9x9 table"
        end
        for r = 1, 9 do
            if type(data.manual_removed[r]) ~= "table" then
                return nil, "manual_removed must be a 9x9 table"
            end
            for c = 1, 9 do
                local mask = data.manual_removed[r][c]
                if type(mask) ~= "number" or mask % 1 ~= 0 or mask < 0 or mask > FULL_CANDIDATE_MASK then
                    return nil, "manual_removed masks must be integers in the range 0..511"
                end
                manual_removed[r][c] = mask
            end
        end
    end
    local restore_masks = constraint_masks_for(current)
    for r = 0, 8 do
        for c = 0, 8 do
            local mask = notes[r + 1][c + 1]
            if current[cell_index(r, c)] == 0 then
                local legal = masks.compute_candidates_mask_for_cell(restore_masks, r, c)
                if bit.band(mask, bit.bnot(legal)) ~= 0 then
                    return nil, "notes contain an illegal candidate"
                end
            elseif mask ~= 0 then
                return nil, "filled cells must not have notes"
            end
        end
    end

    local history, history_err = validate_history(data.history)
    if not history then
        return nil, history_err
    end
    if type(data.undo_ptr) ~= "number" or data.undo_ptr % 1 ~= 0 or data.undo_ptr < 0 or data.undo_ptr > #history then
        return nil, "invalid undo position"
    end

    local revision_ok, revision_err = validate_non_negative(data.revision, "revision")
    if not revision_ok then
        return nil, revision_err
    end
    local mistakes_ok, mistakes_err = validate_non_negative(data.mistakes, "mistakes")
    if not mistakes_ok then
        return nil, mistakes_err
    end
    local errors_ok, errors_err = validate_non_negative(data.check_errors, "check_errors")
    if not errors_ok then
        return nil, errors_err
    end

    if type(data.revealed) ~= "table" then
        return nil, "revealed must be a table"
    end
    local revealed = {}
    for _, key in ipairs(data.revealed) do
        if type(key) ~= "number" or key % 1 ~= 0 or key < 0 or key > 80 then
            return nil, "revealed entries must be cell indices in the range 0..80"
        end
        revealed[key] = true
    end

    if type(data.timer) ~= "table" or type(data.timer.running) ~= "boolean" then
        return nil, "invalid timer state"
    end
    if type(data.timer.elapsed) ~= "number" or not util.is_finite(data.timer.elapsed) or data.timer.elapsed < 0 then
        return nil, "invalid timer state"
    end
    if
        data.timer.started ~= nil and (type(data.timer.started) ~= "number" or not util.is_finite(data.timer.started))
    then
        return nil, "invalid timer state"
    end
    if type(data.hints) ~= "table" then
        return nil, "hints must be a table"
    end
    local hints_copy = {}
    for i, entry in ipairs(data.hints) do
        if
            type(entry) ~= "table"
            or type(entry.id) ~= "string"
            or type(entry.technique) ~= "string"
            or type(entry.flag) ~= "number"
        then
            return nil, "invalid hint record"
        end
        hints_copy[i] = { id = entry.id, technique = entry.technique, flag = entry.flag }
    end
    if type(data.finished) ~= "boolean" then
        return nil, "invalid finished flag"
    end
    -- Optional reproduction seed; older saves predate the field and stay nil.
    local seed = data.seed
    if seed ~= nil and (type(seed) ~= "number" or seed % 1 ~= 0) then
        return nil, "invalid seed"
    end
    -- Optional game-log identity; older saves predate the field and stay nil.
    local id = data.id
    if id ~= nil and (type(id) ~= "number" or id % 1 ~= 0 or id < 0) then
        return nil, "invalid id"
    end
    -- Optional started timestamp; nil until the player makes the first move.
    local started_at = data.started_at
    if started_at ~= nil and (type(started_at) ~= "number" or not util.is_finite(started_at)) then
        return nil, "invalid started_at"
    end

    local now = opts.now
    local instance = {
        puzzle = puzzle,
        solution = solution,
        board = current,
        notes = notes,
        manual_removed = manual_removed,
        _difficulty = data.difficulty,
        now = now,
        timer = { running = false, started = now(), elapsed = data.timer.elapsed },
        _revision = data.revision,
        history = history,
        undo_ptr = data.undo_ptr,
        _mistakes = data.mistakes,
        _check_errors = data.check_errors,
        _revealed = revealed,
        _hints = hints_copy,
        _started = started_at ~= nil,
        _started_at = started_at,
        finished = data.finished,
        seed = seed,
        id = id,
        autofill_notes = not not data.autofill_notes,
    }
    if data.timer.running then
        if data.timer.started == nil then
            return nil, "invalid timer state"
        end
        if math.abs(data.timer.started - now()) > MAX_TIMER_STARTED_DRIFT then
            return nil, "invalid timer state"
        end
        instance.timer.running = true
        instance.timer.started = data.timer.started
    end
    return setmetatable(instance, mt)
end

return game
