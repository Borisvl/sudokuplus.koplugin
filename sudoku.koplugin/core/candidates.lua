local bit = require("bit")
local board = require("core.board")
local masks = require("core.masks")
local flags = require("core.techniques.flags")

local candidates = {}

function candidates.new()
    local cache = {}
    for i = 1, 9 do
        cache[i] = { 0, 0, 0, 0, 0, 0, 0, 0, 0 }
    end
    return cache
end

function candidates.clone(c)
    local copy = {}
    for r = 1, 9 do
        copy[r] = {}
        for col = 1, 9 do
            copy[r][col] = c[r][col]
        end
    end
    return copy
end

function candidates.new_trail()
    return { size = 0, rows = {}, cols = {}, values = {} }
end

function candidates.mark(trail)
    return trail.size
end

function candidates.rollback(c, trail, marker)
    for index = trail.size, marker + 1, -1 do
        c[trail.rows[index] + 1][trail.cols[index] + 1] = trail.values[index]
    end
    trail.size = marker
end

function candidates.restore(c, snapshot)
    for r = 1, 9 do
        for col = 1, 9 do
            c[r][col] = snapshot[r][col]
        end
    end
end

function candidates.get(c, r, col)
    return c[r + 1][col + 1]
end

-- Stores `mask` in cell (r, col), recording the previous value on the trail
-- when one is given. Precondition: `mask` must be a 0..511 candidate bitmask
-- consistent with the board constraints (solver.validate is the gate; this is
-- a hot path and does not re-check).
function candidates.set(c, r, col, mask, trail)
    local row = c[r + 1]
    local column = col + 1
    local previous = row[column]
    if previous == mask then
        return false
    end

    if trail then
        local index = trail.size + 1
        trail.size = index
        trail.rows[index] = r
        trail.cols[index] = col
        trail.values[index] = previous
    end

    row[column] = mask
    return true
end

function candidates.from_mask(mask)
    local result = {}
    for i = 0, 8 do
        if bit.band(mask, bit.lshift(1, i)) ~= 0 then
            result[#result + 1] = i + 1
        end
    end
    return result
end

function candidates.get_candidates(c, r, col)
    return candidates.from_mask(candidates.get(c, r, col))
end

function candidates.count(mask)
    return flags.count(mask)
end

function candidates.update_affected_cells(c, r, col, m, b, trail)
    candidates.update_affected_cells_for(c, r, col, m, b, nil, trail)
end

function candidates.update_affected_cells_for(c, r, col, m, b, placed_num, trail)
    local preserve_eliminations = placed_num ~= nil

    if board.raw_is_empty(b, r, col) then
        candidates.set(c, r, col, masks.compute_candidates_mask_for_cell(m, r, col), trail)
    else
        candidates.set(c, r, col, 0, trail)
    end

    local function update_cell(cell_r, cell_col)
        local legal = masks.compute_candidates_mask_for_cell(m, cell_r, cell_col)
        if preserve_eliminations then
            legal = bit.band(candidates.get(c, cell_r, cell_col), legal)
        end
        candidates.set(c, cell_r, cell_col, legal, trail)
    end

    for i = 0, 8 do
        if i ~= col and board.raw_is_empty(b, r, i) then
            update_cell(r, i)
        end
        if i ~= r and board.raw_is_empty(b, i, col) then
            update_cell(i, col)
        end
    end

    local box_idx = masks.get_box_idx(r, col)
    local start_row = masks.box_start_row(box_idx)
    local start_col = masks.box_start_col(box_idx)
    for r_offset = 0, 2 do
        for c_offset = 0, 2 do
            local cur_r = start_row + r_offset
            local cur_c = start_col + c_offset
            if cur_r ~= r and cur_c ~= col then
                if board.raw_is_empty(b, cur_r, cur_c) then
                    update_cell(cur_r, cur_c)
                end
            end
        end
    end
end

return candidates
