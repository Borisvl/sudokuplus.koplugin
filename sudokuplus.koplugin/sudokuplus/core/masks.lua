local bit = require("bit")

local masks = {}

local FULL_MASK = 0x1FF

-- L2: box computations are table lookups instead of math.floor divisions.
-- get_box_idx(r, c) == (r // 3) * 3 + (c // 3); the start tables hold the
-- box's top-left cell for box index 0..8. Indexed by (coordinate + 1).
local BOX_START_ROW = { 0, 0, 0, 3, 3, 3, 6, 6, 6 }
local BOX_OFFSET_COL = { 0, 0, 0, 1, 1, 1, 2, 2, 2 }
local BOX_START_COL = { 0, 3, 6, 0, 3, 6, 0, 3, 6 }

local function mask_for(num)
    return bit.lshift(1, num - 1)
end

function masks.new()
    return {
        row = { 0, 0, 0, 0, 0, 0, 0, 0, 0 },
        col = { 0, 0, 0, 0, 0, 0, 0, 0, 0 },
        box = { 0, 0, 0, 0, 0, 0, 0, 0, 0 },
    }
end

function masks.get_box_idx(r, c)
    return BOX_START_ROW[r + 1] + BOX_OFFSET_COL[c + 1]
end

function masks.box_start_row(box_idx)
    return BOX_START_ROW[box_idx + 1]
end

function masks.box_start_col(box_idx)
    return BOX_START_COL[box_idx + 1]
end

function masks.add_number(m, r, c, num)
    local bitmask = mask_for(num)
    local box_idx = masks.get_box_idx(r, c)
    m.row[r + 1] = bit.bor(m.row[r + 1], bitmask)
    m.col[c + 1] = bit.bor(m.col[c + 1], bitmask)
    m.box[box_idx + 1] = bit.bor(m.box[box_idx + 1], bitmask)
end

-- Removes `num` from the row/column/box presence masks for cell (r, c).
-- Precondition: `num` was previously added (or is otherwise absent) — the
-- masks are presence sets, not occurrence counts, so removing a digit that is
-- still present in another cell of the same unit would wrongly clear the bit.
-- Callers must uphold the no-duplicate-in-unit invariant (validated by
-- solver.validate at the public boundary).
function masks.remove_number(m, r, c, num)
    local bitmask = mask_for(num)
    local box_idx = masks.get_box_idx(r, c)
    m.row[r + 1] = bit.band(m.row[r + 1], bit.bnot(bitmask))
    m.col[c + 1] = bit.band(m.col[c + 1], bit.bnot(bitmask))
    m.box[box_idx + 1] = bit.band(m.box[box_idx + 1], bit.bnot(bitmask))
end

function masks.is_safe(m, r, c, num)
    local bitmask = mask_for(num)
    local box_idx = masks.get_box_idx(r, c)
    return bit.band(m.row[r + 1], bitmask) == 0
        and bit.band(m.col[c + 1], bitmask) == 0
        and bit.band(m.box[box_idx + 1], bitmask) == 0
end

function masks.compute_candidates_mask_for_cell(m, r, c)
    local used = bit.bor(m.row[r + 1], bit.bor(m.col[c + 1], m.box[masks.get_box_idx(r, c) + 1]))
    return bit.band(bit.bnot(used), FULL_MASK)
end

return masks
