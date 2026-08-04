local bit = require("bit")

local masks = {}

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
    return math.floor(r / 3) * 3 + math.floor(c / 3)
end

function masks.add_number(m, r, c, num)
    local bitmask = mask_for(num)
    m.row[r + 1] = bit.bor(m.row[r + 1], bitmask)
    m.col[c + 1] = bit.bor(m.col[c + 1], bitmask)
    m.box[masks.get_box_idx(r, c) + 1] = bit.bor(m.box[masks.get_box_idx(r, c) + 1], bitmask)
end

function masks.remove_number(m, r, c, num)
    local bitmask = mask_for(num)
    m.row[r + 1] = bit.band(m.row[r + 1], bit.bnot(bitmask))
    m.col[c + 1] = bit.band(m.col[c + 1], bit.bnot(bitmask))
    m.box[masks.get_box_idx(r, c) + 1] = bit.band(m.box[masks.get_box_idx(r, c) + 1], bit.bnot(bitmask))
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
    return bit.band(bit.bnot(used), 0x1FF)
end

return masks
