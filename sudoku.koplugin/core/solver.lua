local bit = require("bit")
local board = require("core.board")
local candidates = require("core.candidates")
local masks = require("core.masks")
local prng = require("core.prng")
local solve_path = require("core.solve_path")

local solver = {}
local mt = {}
mt.__index = mt

function solver.new(b, opts)
    local m = masks.new()
    for r = 0, 8 do
        for col = 0, 8 do
            local num = board.get(b, r, col)
            if num ~= 0 then
                if not masks.is_safe(m, r, col, num) then
                    return nil, "initial board contains duplicates"
                end
                masks.add_number(m, r, col, num)
            end
        end
    end
    local c = candidates.new()
    for r = 0, 8 do
        for col = 0, 8 do
            if board.is_empty(b, r, col) then
                candidates.set(c, r, col, masks.compute_candidates_mask_for_cell(m, r, col))
            end
        end
    end
    local state = {
        board = board.clone(b),
        masks = m,
        candidates = c,
        rng = (opts or {}).rng or prng.new(),
    }
    return setmetatable(state, mt)
end

local function place_number(state, r, col, num)
    board.set(state.board, r, col, num)
    masks.add_number(state.masks, r, col, num)
    candidates.update_affected_cells_for(state.candidates, r, col, state.masks, state.board, num)
end

local function remove_number(state, r, col, num)
    board.set(state.board, r, col, 0)
    masks.remove_number(state.masks, r, col, num)
    candidates.update_affected_cells(state.candidates, r, col, state.masks, state.board)
end

local function find_next_empty_cell(state)
    local min_count = 10
    local best = nil
    for _, cell in ipairs(board.iter_empty_cells(state.board)) do
        local count = candidates.count(candidates.get(state.candidates, cell[1], cell[2]))
        if count < min_count then
            min_count = count
            best = cell
            if count == 1 then
                return best
            end
        end
    end
    return best
end

local function candidates_from_mask(mask)
    local nums = {}
    for v = 1, 9 do
        if bit.band(mask, bit.lshift(1, v - 1)) ~= 0 then
            nums[#nums + 1] = v
        end
    end
    return nums
end

local function solve_until_recursive(state, solutions, path, bound)
    local cell = find_next_empty_cell(state)
    if not cell then
        solutions[#solutions + 1] = {
            board = board.clone(state.board),
            solve_path = solve_path.snapshot(path),
        }
        return
    end
    local r, col = cell[1], cell[2]
    local nums = candidates_from_mask(candidates.get(state.candidates, r, col))
    state.rng:shuffle(nums)
    for _, num in ipairs(nums) do
        if masks.is_safe(state.masks, r, col, num) then
            place_number(state, r, col, num)
            solve_path.push(path, solve_path.placement_step(r, col, num))
            solve_until_recursive(state, solutions, path, bound)
            path.steps[#path.steps] = nil
            remove_number(state, r, col, num)
            if bound > 0 and #solutions >= bound then
                return
            end
        end
    end
end

function mt:solve_until(bound)
    local solutions = {}
    local path = solve_path.new()
    solve_until_recursive(self, solutions, path, bound)
    return solutions
end

function mt:solve_any()
    return self:solve_until(1)[1]
end

function mt:solve_all()
    return self:solve_until(0)
end

function mt:is_solved()
    for r = 0, 8 do
        for col = 0, 8 do
            if board.is_empty(self.board, r, col) then
                return false
            end
        end
    end
    return solver.new(self.board) ~= nil
end

return solver
