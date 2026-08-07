local bit = require("bit")
local board = require("core.board")
local candidates = require("core.candidates")
local masks = require("core.masks")
local solve_path = require("core.solve_path")
local flags = require("core.techniques.flags")
local units = require("core.techniques.units")

local propagator = {}
local mt = {}
mt.__index = mt

local board_set = board.set
local board_is_empty = board.is_empty
local masks_add = masks.add_number
local masks_remove = masks.remove_number
local cand_clone = candidates.clone
local cand_get = candidates.get
local cand_restore = candidates.restore
local cand_set = candidates.set
local cand_update_for = candidates.update_affected_cells_for
local cand_update = candidates.update_affected_cells
local path_push = solve_path.push
local path_placement = solve_path.placement_step
local path_elimination = solve_path.elimination_step

-- Fixed technique order (rustoku parity). All modules are loaded eagerly so a
-- deployment or porting error cannot silently change the enabled technique set.
local TECHNIQUE_NAMES = {
    "naked_singles",
    "hidden_singles",
    "naked_pairs",
    "hidden_pairs",
    "locked_candidates",
    "naked_triples",
    "hidden_triples",
    "x_wing",
    "naked_quads",
    "hidden_quads",
    "swordfish",
    "jellyfish",
    "skyscraper",
    "w_wing",
    "xy_wing",
    "xyz_wing",
    "aic",
}

local function load_techniques()
    local order = {}
    local names = {}

    for _, name in ipairs(TECHNIQUE_NAMES) do
        local ok, mod_or_error = pcall(require, "core.techniques." .. name)
        if not ok then
            error("failed to load Sudoku technique '" .. name .. "': " .. tostring(mod_or_error))
        end
        if
            type(mod_or_error) ~= "table"
            or type(mod_or_error.apply) ~= "function"
            or type(mod_or_error.flags) ~= "function"
        then
            error("Sudoku technique '" .. name .. "' did not return a valid technique module")
        end
        order[#order + 1] = mod_or_error
        names[#names + 1] = name
    end

    return order, names
end

local technique_order, loaded_technique_names = load_techniques()

function propagator.new(b, m, c, techniques)
    return setmetatable({
        board = b,
        masks = m,
        candidates = c,
        techniques = techniques or 0,
        candidate_snapshots = {},
        search_status = nil,
    }, mt)
end

function propagator.technique_names()
    local names = {}
    for i, name in ipairs(loaded_technique_names) do
        names[i] = name
    end
    return names
end

function mt:is_empty(r, c)
    return board_is_empty(self.board, r, c)
end

function mt:cand(r, c)
    return cand_get(self.candidates, r, c)
end

function mt:count_affected_cells(r, c)
    local count = 0
    local box_r = math.floor(r / 3) * 3
    local box_c = math.floor(c / 3) * 3
    for col = 0, 8 do
        if col ~= c and board_is_empty(self.board, r, col) then
            count = count + 1
        end
    end
    for row = 0, 8 do
        if row ~= r and board_is_empty(self.board, row, c) then
            count = count + 1
        end
    end
    for br = box_r, box_r + 2 do
        for bc = box_c, box_c + 2 do
            if br ~= r and bc ~= c and board_is_empty(self.board, br, bc) then
                count = count + 1
            end
        end
    end
    return count
end

function mt:count_candidates_eliminated(r, c, num)
    local count = 0
    local num_bit = bit.lshift(1, num - 1)
    local box_r = math.floor(r / 3) * 3
    local box_c = math.floor(c / 3) * 3
    for col = 0, 8 do
        if col ~= c and bit.band(cand_get(self.candidates, r, col), num_bit) ~= 0 then
            count = count + 1
        end
    end
    for row = 0, 8 do
        if row ~= r and bit.band(cand_get(self.candidates, row, c), num_bit) ~= 0 then
            count = count + 1
        end
    end
    for br = box_r, box_r + 2 do
        for bc = box_c, box_c + 2 do
            if br ~= r and bc ~= c and bit.band(cand_get(self.candidates, br, bc), num_bit) ~= 0 then
                count = count + 1
            end
        end
    end
    return count
end

function mt:place_and_update(r, c, num, technique_flags, path, pattern)
    local candidates_before = cand_clone(self.candidates)
    board_set(self.board, r, c, num)
    masks_add(self.masks, r, c, num)

    local affected = self:count_affected_cells(r, c)
    local eliminated = self:count_candidates_eliminated(r, c, num)

    cand_update_for(self.candidates, r, c, self.masks, self.board, num)

    local step = path_placement(r, c, num, technique_flags, pattern)
    step.candidates_eliminated = eliminated
    step.related_cell_count = affected
    step.difficulty_point = flags.difficulty_point(technique_flags)
    path_push(path, step)
    self.candidate_snapshots[step] = candidates_before
end

function mt:eliminate_candidate(r, c, candidate_bit, technique_flags, path, pattern)
    local initial = cand_get(self.candidates, r, c)
    local refined = bit.band(initial, bit.bnot(candidate_bit))
    cand_set(self.candidates, r, c, refined)

    if initial ~= refined then
        local num = flags.lowest_bit(candidate_bit) + 1
        local step = path_elimination(r, c, num, technique_flags, pattern)
        step.candidates_eliminated = 1
        step.related_cell_count = 1
        step.difficulty_point = flags.difficulty_point(technique_flags)
        path_push(path, step)
    end

    return initial ~= refined
end

function mt:eliminate_multiple_candidates(r, c, elimination_mask, technique_flags, path, pattern)
    local initial = cand_get(self.candidates, r, c)
    local refined = bit.band(initial, bit.bnot(elimination_mask))
    cand_set(self.candidates, r, c, refined)

    local eliminated_mask = bit.band(initial, elimination_mask)

    for num = 1, 9 do
        local num_bit = bit.lshift(1, num - 1)
        if bit.band(eliminated_mask, num_bit) ~= 0 then
            local step = path_elimination(r, c, num, technique_flags, pattern)
            step.candidates_eliminated = 1
            step.related_cell_count = 1
            step.difficulty_point = flags.difficulty_point(technique_flags)
            path_push(path, step)
        end
    end

    return initial ~= refined
end

local function unit_has_dead_end(self, cells, used)
    for num = 1, 9 do
        local num_bit = bit.lshift(1, num - 1)
        if bit.band(used, num_bit) == 0 then
            local has_position = false
            for _, cell in ipairs(cells) do
                if
                    board_is_empty(self.board, cell[1], cell[2])
                    and bit.band(cand_get(self.candidates, cell[1], cell[2]), num_bit) ~= 0
                then
                    has_position = true
                    break
                end
            end
            if not has_position then
                return true
            end
        end
    end
    return false
end

local function has_dead_end(self)
    for r = 0, 8 do
        for col = 0, 8 do
            if board_is_empty(self.board, r, col) and cand_get(self.candidates, r, col) == 0 then
                return true
            end
        end
    end

    for i = 0, 8 do
        if
            unit_has_dead_end(self, units.row_cells(i), self.masks.row[i + 1])
            or unit_has_dead_end(self, units.col_cells(i), self.masks.col[i + 1])
            or unit_has_dead_end(self, units.box_cells(i), self.masks.box[i + 1])
        then
            return true
        end
    end

    return false
end

function mt:rollback(path, initial_path_len)
    while #path.steps > initial_path_len do
        local step = path.steps[#path.steps]
        path.steps[#path.steps] = nil
        if step.type == "place" then
            board_set(self.board, step.row, step.col, 0)
            masks_remove(self.masks, step.row, step.col, step.value)
            local snapshot = self.candidate_snapshots[step]
            if snapshot then
                cand_restore(self.candidates, snapshot)
                self.candidate_snapshots[step] = nil
            else
                cand_update(self.candidates, step.row, step.col, self.masks, self.board)
            end
        else
            local m = cand_get(self.candidates, step.row, step.col)
            cand_set(self.candidates, step.row, step.col, bit.bor(m, bit.lshift(1, step.value - 1)))
        end
    end
end

function mt:propagate_constraints(path, initial_path_len)
    while true do
        local changed = false
        for _, tech in ipairs(technique_order) do
            if bit.band(self.techniques, tech.flags()) ~= 0 then
                local status
                changed, status = tech.apply(self, path)
                if status then
                    self.search_status = status
                end
                if changed then
                    break
                end
            end
        end

        if has_dead_end(self) then
            self:rollback(path, initial_path_len)
            return false, self.search_status
        end

        if not changed then
            break
        end
    end
    return true, self.search_status
end

return propagator
