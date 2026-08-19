local bit = require("bit")
local board = require("core.board")
local masks = require("core.masks")
local solver = require("core.solver")
local util = require("core.util")

local game_serialize = {}

local VERSION = 2
local FULL_CANDIDATE_MASK = util.FULL_CANDIDATE_MASK
local new_mask_grid = util.new_mask_grid
local deep_copy = util.deep_copy
local validate_cell = util.validate_cell
local validate_value = util.validate_value
local validate_non_negative = util.validate_non_negative
local cell_index = util.cell_index
local constraint_masks_for = util.constraint_masks_for

-- Saves are only ever written while paused, so a save claiming a *running*
-- timer must have a wall-clock start timestamp close to now; anything further
-- out is a corrupted/edited save whose started value would inflate elapsed().
local MAX_TIMER_STARTED_DRIFT = 7 * 24 * 3600

game_serialize.VERSION = VERSION

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

function game_serialize.serialize(self)
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
    local techniques_copy = nil
    if self._techniques ~= nil then
        techniques_copy = {}
        for i, t in ipairs(self._techniques) do
            techniques_copy[i] = t
        end
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
        techniques = techniques_copy,
        custom_tier = self.custom_tier,
        custom_techniques = self.custom_techniques and deep_copy(self.custom_techniques) or nil,
        allowed_techniques = self._allowed_techniques,
    }
end

function game_serialize.restore(data, opts, mt)
    if type(data) ~= "table" then
        return nil, "save data must be a table"
    end
    if data.version ~= VERSION then
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
    if not board.solution_preserves_givens(puzzle, solution) then
        return nil, "solution does not preserve the puzzle givens"
    end
    if not board.solution_preserves_givens(puzzle, current) then
        return nil, "board does not preserve the puzzle givens"
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
    -- Optional required techniques list (accepts any non-empty string id for forward compatibility).
    local techniques_copy = nil
    if data.techniques ~= nil then
        if type(data.techniques) ~= "table" then
            return nil, "invalid techniques"
        end
        techniques_copy = {}
        for i, t in ipairs(data.techniques) do
            if type(t) ~= "string" or #t == 0 then
                return nil, "invalid techniques"
            end
            techniques_copy[i] = t
        end
    end

    local custom_tier = nil
    local custom_techniques = nil
    local allowed_techniques = data.allowed_techniques
    if data.difficulty == "custom" then
        local valid_tier, valid_techs =
            util.validate_custom_tier_and_techniques(data.custom_tier, data.custom_techniques)
        if not valid_tier then
            return nil, "invalid custom fields"
        end
        custom_tier = valid_tier
        custom_techniques = valid_techs
        if allowed_techniques == nil or type(allowed_techniques) ~= "number" or allowed_techniques % 1 ~= 0 then
            return nil, "invalid allowed_techniques"
        end
    else
        if data.custom_tier ~= nil or data.custom_techniques ~= nil or data.allowed_techniques ~= nil then
            return nil, "invalid custom fields on non-custom save"
        end
    end

    local now = opts.now
    local instance = {
        puzzle = puzzle,
        solution = solution,
        board = current,
        notes = notes,
        manual_removed = manual_removed,
        _difficulty = data.difficulty,
        custom_tier = custom_tier,
        custom_techniques = custom_techniques,
        _allowed_techniques = allowed_techniques,
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
        _techniques = techniques_copy,
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
    if mt then
        return setmetatable(instance, mt)
    end
    return instance
end

return game_serialize
