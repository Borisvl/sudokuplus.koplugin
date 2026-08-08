local bit = require("bit")
local board = require("core.board")
local hints = require("core.hints")
local masks = require("core.masks")
local solver = require("core.solver")

local game = {}
local mt = {}
mt.__index = mt

local VERSION = 1
local FULL_CANDIDATE_MASK = 0x1FF

local DIFFICULTIES = {
    easy = true,
    medium = true,
    hard = true,
    expert = true,
}

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

local function is_safe_board(b, r, c, value)
    for i = 0, 8 do
        if i ~= c and b[r * 9 + i + 1] == value then
            return false
        end
        if i ~= r and b[i * 9 + c + 1] == value then
            return false
        end
    end
    local br = math.floor(r / 3) * 3
    local bc = math.floor(c / 3) * 3
    for dr = 0, 2 do
        for dc = 0, 2 do
            local cr, cc = br + dr, bc + dc
            if cr ~= r and cc ~= c and b[cr * 9 + cc + 1] == value then
                return false
            end
        end
    end
    return true
end

local function legal_mask_for(b, r, c)
    local mask = 0
    for value = 1, 9 do
        if is_safe_board(b, r, c, value) then
            mask = bit.bor(mask, digit_bit(value))
        end
    end
    return mask
end

local function conflicts_board(b, r, c)
    local value = b[cell_index(r, c)]
    if value == 0 then
        return false
    end
    for i = 0, 8 do
        if i ~= c and b[r * 9 + i + 1] == value then
            return true
        end
        if i ~= r and b[i * 9 + c + 1] == value then
            return true
        end
    end
    local br = math.floor(r / 3) * 3
    local bc = math.floor(c / 3) * 3
    for dr = 0, 2 do
        for dc = 0, 2 do
            local cr, cc = br + dr, bc + dc
            if cr ~= r and cc ~= c and b[cr * 9 + cc + 1] == value then
                return true
            end
        end
    end
    return false
end

local function each_peer(r, c, visitor)
    for i = 0, 8 do
        if i ~= c then
            visitor(r, i)
        end
        if i ~= r then
            visitor(i, c)
        end
    end
    local br = math.floor(r / 3) * 3
    local bc = math.floor(c / 3) * 3
    for dr = 0, 2 do
        for dc = 0, 2 do
            local cr, cc = br + dr, bc + dc
            if cr ~= r and cc ~= c then
                visitor(cr, cc)
            end
        end
    end
end

-- Removes `value` from the notes of empty peer cells and returns the list of
-- cleaned {row, col, value} entries for undo.
local function auto_clean(self, r, c, value)
    local cleaned = {}
    local v_bit = digit_bit(value)
    each_peer(r, c, function(cr, cc)
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
    if self.board[index] == 0 then
        self.notes[cr + 1][cc + 1] = bit.bor(self.notes[cr + 1][cc + 1], digit_bit(value))
    end
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

local function commit(self, entry)
    self.undo_ptr = self.undo_ptr + 1
    self.history[self.undo_ptr] = entry
    for i = self.undo_ptr + 1, #self.history do
        self.history[i] = nil
    end
    self._revision = self._revision + 1
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
    if self.timer.running then
        self.timer.elapsed = self.timer.elapsed + math.max(0, self.now() - self.timer.started)
        self.timer.running = false
    end
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

    if type(difficulty) ~= "string" or not DIFFICULTIES[difficulty] then
        return nil, "difficulty must be one of easy, medium, hard, expert"
    end
    if type(now) ~= "function" then
        return nil, "now must be a function returning the current time in seconds"
    end

    local notes = {}
    for r = 0, 8 do
        local row = {}
        for c = 0, 8 do
            local mask = 0
            if board.is_empty(puzzle, r, c) then
                mask = masks.compute_candidates_mask_for_cell(constraint_masks, r, c)
            end
            row[c + 1] = mask
        end
        notes[r + 1] = row
    end

    local instance = {
        puzzle = board.clone(puzzle),
        solution = board.clone(solution),
        board = board.clone(puzzle),
        notes = notes,
        _difficulty = difficulty,
        now = now,
        timer = { running = true, started = now(), elapsed = 0 },
        _revision = 0,
        history = {},
        undo_ptr = 0,
        _mistakes = 0,
        _check_errors = 0,
        _revealed = {},
        _hints = {},
        finished = false,
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
    local cleaned = auto_clean(self, r, c, value)
    self.board[index] = value
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
        cleaned = cleaned,
    })
    return true
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
    self.notes[r + 1][c + 1] = legal_mask_for(self.board, r, c)

    commit(self, { kind = "erase", r = r, c = c, old = old })
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
    commit(self, { kind = "note", r = r, c = c, value = value, added = not has })
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

    commit(self, { kind = "notes_clear", r = r, c = c, old_mask = old })
    return true
end

local function undo_entry(self, entry)
    if entry.kind == "place" then
        self.board[cell_index(entry.r, entry.c)] = entry.old
        self.notes[entry.r + 1][entry.c + 1] = entry.old_notes
        for _, cleaned in ipairs(entry.cleaned or {}) do
            add_note_digit(self, cleaned[1], cleaned[2], cleaned[3])
        end
    elseif entry.kind == "erase" then
        self.board[cell_index(entry.r, entry.c)] = entry.old
        self.notes[entry.r + 1][entry.c + 1] = 0
    elseif entry.kind == "note" then
        toggle_note_digit(self, entry.r, entry.c, entry.value, not entry.added)
    elseif entry.kind == "notes_clear" then
        self.notes[entry.r + 1][entry.c + 1] = entry.old_mask
    end
end

local function redo_entry(self, entry)
    if entry.kind == "place" then
        self.board[cell_index(entry.r, entry.c)] = entry.value
        self.notes[entry.r + 1][entry.c + 1] = 0
        auto_clean(self, entry.r, entry.c, entry.value)
    elseif entry.kind == "erase" then
        self.board[cell_index(entry.r, entry.c)] = 0
        self.notes[entry.r + 1][entry.c + 1] = legal_mask_for(self.board, entry.r, entry.c)
    elseif entry.kind == "note" then
        toggle_note_digit(self, entry.r, entry.c, entry.value, entry.added)
    elseif entry.kind == "notes_clear" then
        self.notes[entry.r + 1][entry.c + 1] = 0
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

local function make_record(self, kind)
    return {
        kind = kind,
        difficulty = self._difficulty,
        duration = self:elapsed(),
        hints = self:hints(),
        mistakes = self._mistakes,
        check_errors = self._check_errors,
        timestamp = self.now(),
    }
end

function mt:finish()
    if self.finished then
        return nil, "game is already finished"
    end
    if not self:is_won() then
        return nil, "board is not solved"
    end
    local record = make_record(self, "finished")
    finish_timer(self)
    self.finished = true
    return record
end

function mt:give_up()
    if self.finished then
        return nil, "game is already finished"
    end
    local record = make_record(self, "give_up")
    finish_timer(self)
    self.finished = true
    return record
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
    local result, err = hints.next({
        board = self.board,
        notes = self.notes,
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
    toggle_note_digit(self, action.row, action.col, action.value, false)
    commit(self, {
        kind = "note",
        r = action.row,
        c = action.col,
        value = action.value,
        added = false,
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
        history = self.history,
        undo_ptr = self.undo_ptr,
        revision = self._revision,
        mistakes = self._mistakes,
        check_errors = self._check_errors,
        revealed = revealed,
        timer = { running = self.timer.running, elapsed = self:elapsed() },
        hints = hints_copy,
        finished = self.finished,
    }
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
        local cell_ok, cell_err = validate_cell(entry.r, entry.c)
        if not cell_ok then
            return nil, "invalid history entry: " .. cell_err
        end
        local kind = entry.kind
        if kind == "place" or kind == "erase" then
            if not validate_value(entry.value or entry.old) then
                return nil, "invalid history entry value"
            end
            if entry.old ~= nil and (entry.old < 0 or entry.old > 9 or entry.old % 1 ~= 0) then
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
            if
                type(entry.old_mask) ~= "number"
                or entry.old_mask % 1 ~= 0
                or entry.old_mask < 0
                or entry.old_mask > FULL_CANDIDATE_MASK
            then
                return nil, "invalid history entry note mask"
            end
        else
            return nil, "unknown history entry kind"
        end
        if entry.old_notes ~= nil then
            if
                type(entry.old_notes) ~= "number"
                or entry.old_notes % 1 ~= 0
                or entry.old_notes < 0
                or entry.old_notes > FULL_CANDIDATE_MASK
            then
                return nil, "invalid history entry note mask"
            end
        end
        if entry.cleaned ~= nil then
            if type(entry.cleaned) ~= "table" then
                return nil, "invalid history entry cleaned list"
            end
            for _, cleaned in ipairs(entry.cleaned) do
                if not validate_cell(cleaned[1], cleaned[2]) then
                    return nil, "invalid history entry cleaned cell"
                end
                if not validate_value(cleaned[3]) then
                    return nil, "invalid history entry cleaned value"
                end
            end
        end
        history[i] = entry
    end
    return history
end

function game.restore(data, opts)
    if type(data) ~= "table" then
        return nil, "save data must be a table"
    end
    if data.version ~= VERSION then
        return nil, "unsupported save version: " .. tostring(data.version)
    end
    if type(opts) ~= "table" or type(opts.now) ~= "function" then
        return nil, "opts.now must be a function returning the current time in seconds"
    end
    if type(data.difficulty) ~= "string" or not DIFFICULTIES[data.difficulty] then
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
    for r = 0, 8 do
        for c = 0, 8 do
            local mask = notes[r + 1][c + 1]
            if current[cell_index(r, c)] == 0 then
                local legal = legal_mask_for(current, r, c)
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
    if type(data.timer.elapsed) ~= "number" or data.timer.elapsed < 0 then
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

    local now = opts.now
    local instance = {
        puzzle = puzzle,
        solution = solution,
        board = current,
        notes = notes,
        difficulty = data.difficulty,
        now = now,
        timer = { running = false, started = now(), elapsed = 0 },
        _revision = data.revision,
        history = history,
        undo_ptr = data.undo_ptr,
        _mistakes = data.mistakes,
        _check_errors = data.check_errors,
        _revealed = revealed,
        _hints = hints_copy,
        finished = data.finished,
    }
    if data.timer.running then
        instance.timer.running = true
        instance.timer.started = now() - data.timer.elapsed
    else
        instance.timer.elapsed = data.timer.elapsed
    end
    return setmetatable(instance, mt)
end

return game
