local board = require("core.board")
local candidates = require("core.candidates")
local masks = require("core.masks")
local prng = require("core.prng")
local solve_path = require("core.solve_path")
local propagator = require("core.techniques.propagator")

local solver = {}
local mt = {}
mt.__index = mt

local board_get = board.get
local board_set = board.set
local board_is_empty = board.is_empty
local board_clone = board.clone
local masks_add = masks.add_number
local masks_remove = masks.remove_number
local masks_is_safe = masks.is_safe
local masks_compute = masks.compute_candidates_mask_for_cell
local cand_clone = candidates.clone
local cand_get = candidates.get
local cand_set = candidates.set
local cand_count = candidates.count
local cand_from_mask = candidates.from_mask
local cand_restore = candidates.restore
local cand_update_for = candidates.update_affected_cells_for
local path_push = solve_path.push
local path_placement = solve_path.placement_step
local path_snapshot = solve_path.snapshot

local function validate_board_shape(b)
    if type(b) ~= "table" then
        return nil, "board must be a table"
    end
    for i = 1, 81 do
        if rawget(b, i) == nil then
            return nil, "board must contain exactly 81 cells"
        end
    end
    for key in pairs(b) do
        if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > 81 then
            return nil, "board must contain exactly 81 cells"
        end
    end
    return true
end

local function clone_masks(m)
    local copy = { row = {}, col = {}, box = {} }
    for i = 1, 9 do
        copy.row[i] = m.row[i]
        copy.col[i] = m.col[i]
        copy.box[i] = m.box[i]
    end
    return copy
end

local function clone_state(state)
    return {
        board = board_clone(state.board),
        masks = clone_masks(state.masks),
        candidates = cand_clone(state.candidates),
        rng = prng.new(state.rng.state),
        techniques = state.techniques,
    }
end

function solver.validate(b)
    local valid, shape_err = validate_board_shape(b)
    if not valid then
        return nil, shape_err
    end

    local m = masks.new()
    for r = 0, 8 do
        for col = 0, 8 do
            local num = board_get(b, r, col)
            if type(num) ~= "number" or num % 1 ~= 0 then
                return nil, "cell value must be an integer"
            end
            if num ~= 0 then
                if num < 1 or num > 9 then
                    return nil, "cell value out of range"
                end
                if not masks_is_safe(m, r, col, num) then
                    return nil, "initial board contains duplicates"
                end
                masks_add(m, r, col, num)
            end
        end
    end
    return m
end

function solver.new(b, opts)
    local m, err = solver.validate(b)
    if not m then
        return nil, err
    end
    local c = candidates.new()
    for r = 0, 8 do
        for col = 0, 8 do
            if board_is_empty(b, r, col) then
                cand_set(c, r, col, masks_compute(m, r, col))
            end
        end
    end
    local state = {
        board = board_clone(b),
        masks = m,
        candidates = c,
        rng = (opts or {}).rng or prng.new(),
        techniques = (opts or {}).techniques or 0,
    }
    return setmetatable(state, mt)
end

local function place_number(state, r, col, num)
    board_set(state.board, r, col, num)
    masks_add(state.masks, r, col, num)
    cand_update_for(state.candidates, r, col, state.masks, state.board, num)
end

local function remove_number(state, r, col, num)
    board_set(state.board, r, col, 0)
    masks_remove(state.masks, r, col, num)
end

local function find_next_empty_cell(state)
    local min_count = 10
    local best_r, best_c
    for r = 0, 8 do
        for col = 0, 8 do
            if board_is_empty(state.board, r, col) then
                local count = cand_count(cand_get(state.candidates, r, col))
                if count < min_count then
                    min_count = count
                    best_r, best_c = r, col
                    if count == 1 then
                        return best_r, best_c
                    end
                end
            end
        end
    end
    return best_r, best_c
end

local function solve_until_recursive(state, solutions, path, bound)
    local r, col = find_next_empty_cell(state)
    if not r then
        solutions[#solutions + 1] = {
            board = board_clone(state.board),
            solve_path = path_snapshot(path),
        }
        return
    end
    local nums = cand_from_mask(cand_get(state.candidates, r, col))
    state.rng:shuffle(nums)
    for _, num in ipairs(nums) do
        if masks_is_safe(state.masks, r, col, num) then
            local candidates_before = cand_clone(state.candidates)
            place_number(state, r, col, num)
            path_push(path, path_placement(r, col, num))
            solve_until_recursive(state, solutions, path, bound)
            path.steps[#path.steps] = nil
            remove_number(state, r, col, num)
            cand_restore(state.candidates, candidates_before)
            if bound > 0 and #solutions >= bound then
                return
            end
        end
    end
end

local function count_solutions_recursive(state, count, limit)
    if limit > 0 and count >= limit then
        return count
    end

    local r, col = find_next_empty_cell(state)
    if not r then
        return count + 1
    end

    local nums = cand_from_mask(cand_get(state.candidates, r, col))
    state.rng:shuffle(nums)
    for _, num in ipairs(nums) do
        if masks_is_safe(state.masks, r, col, num) then
            local candidates_before = cand_clone(state.candidates)
            place_number(state, r, col, num)
            count = count_solutions_recursive(state, count, limit)
            remove_number(state, r, col, num)
            cand_restore(state.candidates, candidates_before)
            if limit > 0 and count >= limit then
                return count
            end
        end
    end
    return count
end

local function validate_solution_limit(limit)
    if limit == nil then
        return 0
    end
    if type(limit) ~= "number" or limit % 1 ~= 0 or limit < 0 then
        return nil, "solution limit must be a non-negative integer"
    end
    return limit
end

function mt:solve_until(bound)
    local solutions = {}
    local path = solve_path.new()
    local state = clone_state(self)
    if state.techniques ~= 0 then
        local prop = propagator.new(state.board, state.masks, state.candidates, state.techniques)
        if not prop:propagate_constraints(path, 0) then
            return solutions
        end
    end
    solve_until_recursive(state, solutions, path, bound)
    return solutions
end

function mt:propagate(path)
    local initial_path_len = #path.steps
    local prop = propagator.new(self.board, self.masks, self.candidates, self.techniques)
    return prop:propagate_constraints(path, initial_path_len)
end

function mt:solve_any()
    return self:solve_until(1)[1]
end

function mt:solve_all(limit)
    local normalized_limit, err = validate_solution_limit(limit)
    if not normalized_limit then
        return nil, err
    end
    return self:solve_until(normalized_limit)
end

function mt:count_solutions(limit)
    local normalized_limit, err = validate_solution_limit(limit)
    if not normalized_limit then
        return nil, err
    end

    local state = clone_state(self)
    local path = solve_path.new()
    if state.techniques ~= 0 then
        local prop = propagator.new(state.board, state.masks, state.candidates, state.techniques)
        if not prop:propagate_constraints(path, 0) then
            return 0
        end
    end
    return count_solutions_recursive(state, 0, normalized_limit)
end

function mt:is_solved()
    for r = 0, 8 do
        for col = 0, 8 do
            if board_is_empty(self.board, r, col) then
                return false
            end
        end
    end
    return solver.validate(self.board) ~= nil
end

return solver
