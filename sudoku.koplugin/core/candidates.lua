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

function candidates.set(c, r, col, mask)
    c[r + 1][col + 1] = mask
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

function candidates.update_affected_cells(c, r, col, m, b)
    candidates.update_affected_cells_for(c, r, col, m, b, nil)
end

function candidates.update_affected_cells_for(c, r, col, m, b, placed_num)
    local preserve_eliminations = placed_num ~= nil

    if board.is_empty(b, r, col) then
        candidates.set(c, r, col, masks.compute_candidates_mask_for_cell(m, r, col))
    else
        candidates.set(c, r, col, 0)
    end

    local function update_cell(cell_r, cell_col)
        local legal = masks.compute_candidates_mask_for_cell(m, cell_r, cell_col)
        if preserve_eliminations then
            legal = bit.band(candidates.get(c, cell_r, cell_col), legal)
        end
        candidates.set(c, cell_r, cell_col, legal)
    end

    for i = 0, 8 do
        if i ~= col and board.is_empty(b, r, i) then
            update_cell(r, i)
        end
        if i ~= r and board.is_empty(b, i, col) then
            update_cell(i, col)
        end
    end

    local box_idx = masks.get_box_idx(r, col)
    local start_row = math.floor(box_idx / 3) * 3
    local start_col = (box_idx % 3) * 3
    for r_offset = 0, 2 do
        for c_offset = 0, 2 do
            local cur_r = start_row + r_offset
            local cur_c = start_col + c_offset
            if cur_r ~= r and cur_c ~= col then
                if board.is_empty(b, cur_r, cur_c) then
                    update_cell(cur_r, cur_c)
                end
            end
        end
    end
end

return candidates
