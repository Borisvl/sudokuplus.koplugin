local bit = require("bit")
local board = require("core.board")
local candidates = require("core.candidates")
local masks = require("core.masks")
local prng = require("core.prng")
local solve_path = require("core.solve_path")
local propagator = require("core.techniques.propagator")

local solver = {}
local mt = {}
mt.__index = mt

local board_get = board.raw_get
local board_set = board.raw_set
local board_is_empty = board.raw_is_empty
local board_clone = board.clone
local masks_add = masks.add_number
local masks_remove = masks.remove_number
local masks_is_safe = masks.is_safe
local masks_compute = masks.compute_candidates_mask_for_cell
local cand_clone = candidates.clone
local cand_new_trail = candidates.new_trail
local cand_mark = candidates.mark
local cand_get = candidates.get
local cand_set = candidates.set
local cand_count = candidates.count
local cand_from_mask = candidates.from_mask
local cand_rollback = candidates.rollback
local cand_update_for = candidates.update_affected_cells_for
local path_push = solve_path.push
local path_placement = solve_path.placement_step
local path_snapshot = solve_path.snapshot

local FULL_CANDIDATE_MASK = 0x1FF

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
        candidate_trail = cand_new_trail(),
        rng = prng.new(state.rng.state),
        techniques = state.techniques,
        aic_max_depth = state.aic_max_depth,
        aic_max_expansions = state.aic_max_expansions,
        -- search_budget persists across calls on an instance, but the node
        -- counter and cap flag are run-scoped: a clone must not inherit a
        -- stale pre-charged count or a stale cap from a previous run.
        search_budget = state.search_budget,
        search_nodes = 0,
        search_capped = false,
    }
end

local function new_propagator(state)
    return propagator.new(state.board, state.masks, state.candidates, state.techniques, {
        aic_max_depth = state.aic_max_depth,
        aic_max_expansions = state.aic_max_expansions,
    })
end

local function validate_candidate_cache(c, b, m)
    if type(c) ~= "table" then
        return nil, "candidates must be a 9x9 table"
    end
    for row = 1, 9 do
        if type(c[row]) ~= "table" then
            return nil, "candidates must be a 9x9 table"
        end
        for col = 1, 9 do
            local mask = c[row][col]
            if type(mask) ~= "number" or mask % 1 ~= 0 or mask < 0 or mask > FULL_CANDIDATE_MASK then
                return nil, "candidate masks must be integers in the range 0..511"
            end
        end
    end

    for key in pairs(c) do
        if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > 9 then
            return nil, "candidates must be a 9x9 table"
        end
    end

    for r = 0, 8 do
        for col = 0, 8 do
            local mask = c[r + 1][col + 1]
            if board_is_empty(b, r, col) then
                local legal = masks_compute(m, r, col)
                if bit.band(mask, bit.bnot(legal)) ~= 0 then
                    return nil, "candidate cache contains an illegal candidate"
                end
            elseif mask ~= 0 then
                return nil, "given cells must not have candidates"
            end
        end
    end
    return true
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
    local options = opts or {}
    local c
    if options.candidates ~= nil then
        local valid_candidates, candidates_err = validate_candidate_cache(options.candidates, b, m)
        if not valid_candidates then
            return nil, candidates_err
        end
        c = cand_clone(options.candidates)
    else
        c = candidates.new()
        for r = 0, 8 do
            for col = 0, 8 do
                if board_is_empty(b, r, col) then
                    cand_set(c, r, col, masks_compute(m, r, col))
                end
            end
        end
    end
    local state = {
        board = board_clone(b),
        masks = m,
        candidates = c,
        candidate_trail = cand_new_trail(),
        rng = options.rng or prng.new(),
        techniques = options.techniques or 0,
        aic_max_depth = options.aic_max_depth,
        aic_max_expansions = options.aic_max_expansions,
        search_budget = options.search_budget,
        search_nodes = 0,
        search_capped = false,
    }
    return setmetatable(state, mt)
end

local CELL_R = {}
local CELL_C = {}
for r = 0, 8 do
    for c = 0, 8 do
        local idx = r * 9 + c
        CELL_R[idx] = r
        CELL_C[idx] = c
    end
end

local function place_number(state, r, col, num)
    board_set(state.board, r, col, num)
    masks_add(state.masks, r, col, num)
    cand_update_for(state.candidates, r, col, state.masks, state.board, num, state.candidate_trail)
end

local function remove_number(state, r, col, num)
    board_set(state.board, r, col, 0)
    masks_remove(state.masks, r, col, num)
end

local function init_empty_cells(state)
    local empty_cells = {}
    for r = 0, 8 do
        for c = 0, 8 do
            if board_is_empty(state.board, r, c) then
                empty_cells[#empty_cells + 1] = r * 9 + c
            end
        end
    end
    state.empty_cells = empty_cells
end

local function find_next_empty_cell(state)
    local min_count = 10
    local best_r, best_c
    local empty_cells = state.empty_cells
    for i = 1, #empty_cells do
        local cell = empty_cells[i]
        local r, col = CELL_R[cell], CELL_C[cell]
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
    return best_r, best_c
end

local function search_node_entered(state)
    if state.search_budget then
        state.search_nodes = state.search_nodes + 1
        if state.search_nodes > state.search_budget then
            state.search_capped = true
            return true
        end
    end
    return false
end

local function solve_until_recursive(state, solutions, path, bound)
    if search_node_entered(state) then
        return
    end
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
            local candidate_marker = cand_mark(state.candidate_trail)
            place_number(state, r, col, num)
            path_push(path, path_placement(r, col, num))
            solve_until_recursive(state, solutions, path, bound)
            path.steps[#path.steps] = nil
            remove_number(state, r, col, num)
            cand_rollback(state.candidates, state.candidate_trail, candidate_marker)
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
    if search_node_entered(state) then
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
            local candidate_marker = cand_mark(state.candidate_trail)
            place_number(state, r, col, num)
            count = count_solutions_recursive(state, count, limit)
            remove_number(state, r, col, num)
            cand_rollback(state.candidates, state.candidate_trail, candidate_marker)
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
        local prop = new_propagator(state)
        -- A propagation dead-end is rolled back to the pre-propagation state;
        -- falling through to plain backtracking means a technique dead-end can
        -- never hide real solutions (parity with the technique-less solver).
        -- Genuinely unsolvable boards still report zero solutions.
        prop:propagate_constraints(path, 0)
    end
    init_empty_cells(state)
    solve_until_recursive(state, solutions, path, bound)
    self.search_nodes = state.search_nodes
    self.search_capped = state.search_capped or nil
    return solutions
end

function mt:propagate(path)
    local initial_path_len = #path.steps
    local prop = new_propagator(self)
    return prop:propagate_constraints(path, initial_path_len)
end

function mt:propagate_next(path)
    local initial_path_len = #path.steps
    local state = clone_state(self)
    local prop = new_propagator(state)
    return prop:propagate_constraints(path, initial_path_len, true)
end

function mt:apply_action(action)
    if type(action) ~= "table" then
        return nil, "action must be a table"
    end
    if action.type ~= "place" and action.type ~= "elim" then
        return nil, "action type must be 'place' or 'elim'"
    end
    if
        type(action.row) ~= "number"
        or action.row % 1 ~= 0
        or action.row < 0
        or action.row > 8
        or type(action.col) ~= "number"
        or action.col % 1 ~= 0
        or action.col < 0
        or action.col > 8
        or type(action.value) ~= "number"
        or action.value % 1 ~= 0
        or action.value < 1
        or action.value > 9
    then
        return nil, "action coordinates and value are out of range"
    end
    if not board_is_empty(self.board, action.row, action.col) then
        return nil, "action target must be empty"
    end

    local value_bit = bit.lshift(1, action.value - 1)
    if bit.band(cand_get(self.candidates, action.row, action.col), value_bit) == 0 then
        return nil, "action value is not a candidate"
    end
    if action.type == "place" and not masks_is_safe(self.masks, action.row, action.col, action.value) then
        return nil, "action value violates Sudoku constraints"
    end

    local path = solve_path.new()
    local prop = propagator.new(self.board, self.masks, self.candidates, 0)
    if action.type == "place" then
        local placed, place_err = prop:place_and_update(action.row, action.col, action.value, 0, path)
        if not placed then
            return nil, place_err
        end
    else
        local eliminated, eliminate_err = prop:eliminate_candidate(action.row, action.col, value_bit, 0, path)
        if not eliminated then
            return nil, eliminate_err or "action candidate is already absent"
        end
    end
    return true
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
    if state.techniques ~= 0 then
        local path = solve_path.new()
        local prop = new_propagator(state)
        prop:propagate_constraints(path, 0)
    end
    init_empty_cells(state)
    local count = count_solutions_recursive(state, 0, normalized_limit)
    self.search_nodes = state.search_nodes
    self.search_capped = state.search_capped or nil
    return count
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
