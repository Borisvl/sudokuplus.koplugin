local bit = require("bit")
local board = require("sudokuplus.core.board")
local masks = require("sudokuplus.core.masks")
local solver = require("sudokuplus.core.solver")
local flags = require("sudokuplus.core.techniques.flags")

local exact_search = {}
local mt = {}
mt.__index = mt

local DIGIT_BITS = { 1, 2, 4, 8, 16, 32, 64, 128, 256 }

local function valid_coordinate(value)
    return type(value) == "number" and value % 1 == 0 and value >= 0 and value <= 8
end

local function validate_cell(row, col)
    if not valid_coordinate(row) or not valid_coordinate(col) then
        return nil, "row and col must be integers in the range 0..8"
    end
    return row * 9 + col + 1
end

local function validate_limit(limit)
    if limit == nil then
        return 0
    end
    if type(limit) ~= "number" or limit % 1 ~= 0 or limit < 0 then
        return nil, "solution limit must be a non-negative integer"
    end
    return limit
end

function exact_search.new(puzzle, solution, options)
    local puzzle_masks, puzzle_err = solver.validate(puzzle)
    if not puzzle_masks then
        return nil, puzzle_err
    end
    local valid_solution, solution_err = solver.validate(solution)
    if not valid_solution then
        return nil, solution_err
    end
    if board.count_clues(solution) ~= 81 then
        return nil, "known solution must be complete"
    end
    for index = 1, 81 do
        if puzzle[index] ~= 0 and puzzle[index] ~= solution[index] then
            return nil, "known solution must agree with every puzzle clue"
        end
    end

    local opts = options or {}
    local search_budget = opts.search_budget
    if search_budget ~= nil and (type(search_budget) ~= "number" or search_budget % 1 ~= 0 or search_budget < 0) then
        return nil, "search_budget must be a non-negative integer"
    end
    return setmetatable({
        board = board.clone(puzzle),
        solution = board.clone(solution),
        masks = puzzle_masks,
        search_budget = search_budget,
        search_nodes = 0,
        search_capped = nil,
    }, mt)
end

function mt:remove(row, col)
    local index, coordinate_err = validate_cell(row, col)
    if not index then
        return nil, coordinate_err
    end
    local value = self.board[index]
    if value == 0 then
        return nil, "cannot remove an empty cell"
    end
    if value ~= self.solution[index] then
        return nil, "puzzle clue does not match the known solution"
    end
    self.board[index] = 0
    masks.remove_number(self.masks, row, col, value)
    return value
end

function mt:restore(row, col)
    local index, coordinate_err = validate_cell(row, col)
    if not index then
        return nil, coordinate_err
    end
    if self.board[index] ~= 0 then
        return nil, "cannot restore a non-empty cell"
    end
    local value = self.solution[index]
    if not masks.is_safe(self.masks, row, col, value) then
        return nil, "known solution cannot be restored into the current puzzle"
    end
    self.board[index] = value
    masks.add_number(self.masks, row, col, value)
    return true
end

local function find_next_empty(state, excluded_index, excluded_bit)
    local best_index
    local best_mask
    local min_count = 10
    for index = 1, 81 do
        if state.board[index] == 0 then
            local row = math.floor((index - 1) / 9)
            local col = (index - 1) % 9
            local mask = masks.compute_candidates_mask_for_cell(state.masks, row, col)
            if index == excluded_index then
                mask = bit.band(mask, bit.bnot(excluded_bit))
            end
            local count = flags.count(mask)
            if count < min_count then
                best_index = index
                best_mask = mask
                min_count = count
                if count <= 1 then
                    return best_index, best_mask
                end
            end
        end
    end
    return best_index, best_mask
end

local function search_node_entered(state)
    state.search_nodes = state.search_nodes + 1
    if state.search_budget and state.search_nodes > state.search_budget then
        state.search_capped = true
        return true
    end
    return false
end

local function count_recursive(state, count, limit, excluded_index, excluded_bit)
    if (limit > 0 and count >= limit) or state.search_capped or search_node_entered(state) then
        return count
    end
    local index, mask = find_next_empty(state, excluded_index, excluded_bit)
    if not index then
        return count + 1
    end
    if mask == 0 then
        return count
    end

    local row = math.floor((index - 1) / 9)
    local col = (index - 1) % 9
    for value = 1, 9 do
        local value_bit = DIGIT_BITS[value]
        if bit.band(mask, value_bit) ~= 0 then
            state.board[index] = value
            masks.add_number(state.masks, row, col, value)
            count = count_recursive(state, count, limit, excluded_index, excluded_bit)
            state.board[index] = 0
            masks.remove_number(state.masks, row, col, value)
            if state.search_capped or (limit > 0 and count >= limit) then
                return count
            end
        end
    end
    return count
end

local function run_count(state, limit, excluded_index, excluded_bit)
    state.search_nodes = 0
    state.search_capped = nil
    return count_recursive(state, 0, limit, excluded_index, excluded_bit)
end

function mt:count_solutions(limit)
    local normalized_limit, limit_err = validate_limit(limit)
    if not normalized_limit then
        return nil, limit_err
    end
    return run_count(self, normalized_limit)
end

function mt:has_alternative(row, col)
    local index, coordinate_err = validate_cell(row, col)
    if not index then
        return nil, coordinate_err
    end
    if self.board[index] ~= 0 then
        return nil, "alternative search requires the removed cell to be empty"
    end

    local known_bit = DIGIT_BITS[self.solution[index]]
    local legal = masks.compute_candidates_mask_for_cell(self.masks, row, col)
    if bit.band(legal, known_bit) == 0 then
        return nil, "known solution is incompatible with the current puzzle"
    end
    if bit.band(legal, bit.bnot(known_bit)) == 0 then
        self.search_nodes = 0
        self.search_capped = nil
        return false, nil, true
    end

    local count = run_count(self, 1, index, known_bit)
    if self.search_capped then
        return nil, nil, false
    end
    return count > 0, nil, false
end

return exact_search
