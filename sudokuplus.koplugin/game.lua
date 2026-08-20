local bit = require("bit")
local board = require("core.board")
local hints = require("core.hints")
local masks = require("core.masks")
local solver = require("core.solver")
local util = require("core.util")
local units = require("core.techniques.units")
local game_serialize = require("game_serialize")

local game = {}
local mt = {}
mt.__index = mt

local FULL_CANDIDATE_MASK = util.FULL_CANDIDATE_MASK
local new_mask_grid = util.new_mask_grid
local deep_copy = util.deep_copy
local validate_cell = util.validate_cell
local validate_value = util.validate_value
local cell_index = util.cell_index
local constraint_masks_for = util.constraint_masks_for

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

local function digit_bit(value)
    return bit.lshift(1, value - 1)
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
    -- A game is "started" once the user places a digit, adds a note, fills all notes,
    -- or applies a hint elimination (the game-log definition); the timestamp feeds per-game stats.
    if
        not self._started
        and (
            entry.kind == "place"
            or (entry.kind == "note" and entry.added)
            or entry.kind == "fill_all_notes"
            or entry.kind == "notes_elim"
        )
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
    if not board.solution_preserves_givens(puzzle, solution) then
        return nil, "solution does not preserve the puzzle givens"
    end

    if type(difficulty) ~= "string" or not util.is_difficulty(difficulty) then
        return nil, "difficulty must be one of beginner, easy, medium, hard, master, expert, custom"
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

    local custom_tier = nil
    local custom_techniques = nil
    local allowed_techniques = options.allowed_techniques
    if difficulty == "custom" then
        local valid_tier, valid_techs =
            util.validate_custom_tier_and_techniques(options.custom_tier, options.custom_techniques)
        if not valid_tier then
            return nil, valid_techs
        end
        custom_tier = valid_tier
        custom_techniques = valid_techs
        if allowed_techniques == nil or type(allowed_techniques) ~= "number" or allowed_techniques % 1 ~= 0 then
            return nil, "allowed_techniques must be an integer bitmask"
        end
    else
        if options.custom_tier ~= nil or options.custom_techniques ~= nil or options.allowed_techniques ~= nil then
            return nil, "non-custom difficulty must not specify custom_tier, custom_techniques, or allowed_techniques"
        end
    end

    local techniques_list = nil
    if options.techniques ~= nil then
        if type(options.techniques) ~= "table" then
            return nil, "techniques must be a list of technique ids"
        end
        techniques_list = {}
        for i, t in ipairs(options.techniques) do
            if type(t) ~= "string" or #t == 0 then
                return nil, "techniques must be a list of technique ids"
            end
            techniques_list[i] = t
        end
    end

    local notes = build_notes_grid(puzzle, constraint_masks, autofill_notes)

    local instance = {
        puzzle = board.clone(puzzle),
        solution = board.clone(solution),
        board = board.clone(puzzle),
        notes = notes,
        manual_removed = new_mask_grid(),
        _difficulty = difficulty,
        custom_tier = custom_tier,
        custom_techniques = custom_techniques,
        _allowed_techniques = allowed_techniques,
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
        _hint_ids = {},
        _started = false,
        _started_at = nil,
        finished = false,
        seed = seed,
        id = id,
        _techniques = techniques_list,
    }
    return setmetatable(instance, mt)
end

function mt:techniques()
    if self._techniques == nil then
        return nil
    end
    local copy = {}
    for i, t in ipairs(self._techniques) do
        copy[i] = t
    end
    return copy
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

-- Set (keyed by 1..9) of digits whose 9 placements are already on the board.
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
    if entry.kind == "notes_elim" then
        local affected = {}
        for _, elim in ipairs(entry.eliminations) do
            affected[elim.r * 9 + elim.c] = true
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
    elseif entry.kind == "notes_elim" then
        for i = #entry.eliminations, 1, -1 do
            local elim = entry.eliminations[i]
            if elim.old_manual_removed ~= nil then
                self.manual_removed[elim.r + 1][elim.c + 1] = elim.old_manual_removed
            end
            if elim.old_notes ~= nil then
                self.notes[elim.r + 1][elim.c + 1] = elim.old_notes
            else
                toggle_note_digit(self, elim.r, elim.c, elim.value, true)
            end
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
        for _, cell in ipairs(entry.restored or {}) do
            local cr, cc, val = cell[1], cell[2], cell[3]
            if is_safe_board(self.board, cr, cc, val) then
                add_note_digit(self, cr, cc, val)
            end
        end
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
    elseif entry.kind == "notes_elim" then
        for _, elim in ipairs(entry.eliminations) do
            local value_bit = digit_bit(elim.value)
            local old_manual_removed = elim.old_manual_removed or self.manual_removed[elim.r + 1][elim.c + 1]
            self.manual_removed[elim.r + 1][elim.c + 1] = bit.bor(old_manual_removed, value_bit)
            if elim.new_notes ~= nil then
                self.notes[elim.r + 1][elim.c + 1] = elim.new_notes
            else
                toggle_note_digit(self, elim.r, elim.c, elim.value, false)
            end
        end
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
    for _, entry in ipairs(self._hints) do
        hint_ids[#hint_ids + 1] = entry.technique
    end
    local techniques_copy = nil
    if self._techniques ~= nil then
        techniques_copy = {}
        for i, t in ipairs(self._techniques) do
            techniques_copy[i] = t
        end
    end
    local custom_techniques_copy = nil
    if self.custom_techniques ~= nil then
        custom_techniques_copy = {}
        for i, t in ipairs(self.custom_techniques) do
            custom_techniques_copy[i] = t
        end
    end
    local progress = self:progress()
    return {
        status = status,
        id = self.id,
        seed = self.seed,
        difficulty = self._difficulty,
        custom_tier = self.custom_tier,
        custom_techniques = custom_techniques_copy,
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
        techniques = techniques_copy,
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
    -- The game layer permits sparse/lazy candidate notes: completely unannotated
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
    }, {
        techniques = self._allowed_techniques,
    })
    if not result then
        return nil, err
    end
    if result.status == "available" then
        -- Deduplicate hints across the session using core.hints' deterministic hint_id
        -- (technique:type:row:col:value:pattern). This ensures repeated hint requests
        -- on the same puzzle state, or re-requesting a previously revealed deduction
        -- after undo/redo, only count as a single missed strategy in game statistics.
        if not self._hint_ids[result.hint_id] then
            self._hint_ids[result.hint_id] = true
            self._hints[#self._hints + 1] = {
                id = result.hint_id,
                technique = result.technique.id,
                flag = result.technique.flag,
            }
        end
    end
    return result
end

function mt:apply_action(action)
    if type(action) ~= "table" then
        return nil, "action must be a table"
    end
    if self.finished then
        return nil, "game is finished"
    end
    if action.revision ~= nil and action.revision ~= self._revision then
        return nil, "action is stale"
    end

    if action.type == "place" then
        local cell_ok, cell_err = validate_cell(action.row, action.col)
        if not cell_ok then
            return nil, cell_err
        end
        local value_ok, value_err = validate_value(action.value)
        if not value_ok then
            return nil, value_err
        end
        return self:place(action.row, action.col, action.value)
    end

    local list
    if
        action[1] ~= nil
        or action.type == "batch"
        or (action.type == nil and action.actions ~= nil)
        or (action.type == nil and action.row == nil and action.col == nil)
    then
        list = action.actions or action
        if #list == 1 and type(list[1]) == "table" and list[1].type == "place" then
            return self:apply_action(list[1])
        end
    elseif action.type == "elim" then
        list = { action }
    else
        return nil, "action type must be 'place' or 'elim'"
    end

    if #list == 0 then
        return nil, "action list must not be empty"
    end
    if action.revision ~= nil and action.revision ~= self._revision then
        return nil, "action is stale"
    end

    for _, act in ipairs(list) do
        if type(act) ~= "table" then
            return nil, "action list item must be a table"
        end
        if act.type ~= "elim" then
            return nil, "batch actions only support elimination type"
        end
        if act.revision ~= nil and act.revision ~= self._revision then
            return nil, "action is stale"
        end
        local cell_ok, cell_err = validate_cell(act.row, act.col)
        if not cell_ok then
            return nil, cell_err
        end
        local value_ok, value_err = validate_value(act.value)
        if not value_ok then
            return nil, value_err
        end
        local index = cell_index(act.row, act.col)
        if self.board[index] ~= 0 then
            return nil, "cannot edit notes on a filled cell"
        end
    end

    local constraint_masks
    local applied_elims = {}
    for _, act in ipairs(list) do
        local v_bit = digit_bit(act.value)
        local old_mr = self.manual_removed[act.row + 1][act.col + 1]
        local cur_notes = self.notes[act.row + 1][act.col + 1]

        if cur_notes == 0 then
            if not constraint_masks then
                constraint_masks = constraint_masks_for(self.board)
            end
            local legal = masks.compute_candidates_mask_for_cell(constraint_masks, act.row, act.col)
            local already_absent = bit.band(legal, v_bit) == 0 or bit.band(old_mr, v_bit) ~= 0
            if not already_absent then
                local new_notes = bit.band(legal, bit.bnot(bit.bor(v_bit, old_mr)))
                applied_elims[#applied_elims + 1] = {
                    r = act.row,
                    c = act.col,
                    value = act.value,
                    old_manual_removed = old_mr,
                    old_notes = 0,
                    new_notes = new_notes,
                }
                self.notes[act.row + 1][act.col + 1] = new_notes
                self.manual_removed[act.row + 1][act.col + 1] = bit.bor(old_mr, v_bit)
            end
        else
            local already_absent = bit.band(cur_notes, v_bit) == 0
            if not already_absent then
                local new_notes = bit.band(cur_notes, bit.bnot(v_bit))
                applied_elims[#applied_elims + 1] = {
                    r = act.row,
                    c = act.col,
                    value = act.value,
                    old_manual_removed = old_mr,
                    old_notes = cur_notes,
                    new_notes = new_notes,
                }
                self.notes[act.row + 1][act.col + 1] = new_notes
                self.manual_removed[act.row + 1][act.col + 1] = bit.bor(old_mr, v_bit)
            end
        end
    end

    if #applied_elims == 0 then
        return nil, "candidate is already absent"
    end

    commit(self, {
        kind = "notes_elim",
        eliminations = applied_elims,
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
    self._hint_ids = {}
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
    return game_serialize.serialize(self)
end

function game.restore(data, opts)
    return game_serialize.restore(data, opts, mt)
end

return game
