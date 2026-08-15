local bit = require("bit")
local flags = require("core.techniques.flags")
local units = require("core.techniques.units")

local locked_candidates = {}

-- Pointing: a candidate is confined to a single box within a row/column, so it
-- can be eliminated from the rest of that box. unit = the row/column,
-- target = the box.
local function collect_line_confined(prop, is_row, index, v_bit)
    local confined = {}
    if is_row then
        for col = 0, 8 do
            if prop:is_empty(index, col) and bit.band(prop:cand(index, col), v_bit) ~= 0 then
                confined[#confined + 1] = { index, col }
            end
        end
    else
        for row = 0, 8 do
            if prop:is_empty(row, index) and bit.band(prop:cand(row, index), v_bit) ~= 0 then
                confined[#confined + 1] = { row, index }
            end
        end
    end
    return confined
end

local function collect_box_confined(prop, start_row, start_col, v_bit)
    local confined = {}
    for r = start_row, start_row + 2 do
        for col = start_col, start_col + 2 do
            if prop:is_empty(r, col) and bit.band(prop:cand(r, col), v_bit) ~= 0 then
                confined[#confined + 1] = { r, col }
            end
        end
    end
    return confined
end

-- Pointing: a candidate is confined to a single box within a row/column, so it
-- can be eliminated from the rest of that box. unit = the row/column,
-- target = the box.
local function pointing_from_line(prop, path, unit_desc, eliminate)
    local changed = false
    local index = unit_desc.index
    local is_row = unit_desc.type == "row"
    for v = 1, 9 do
        local v_bit = bit.lshift(1, v - 1)
        local box_mask = 0
        if is_row then
            for col = 0, 8 do
                if prop:is_empty(index, col) and bit.band(prop:cand(index, col), v_bit) ~= 0 then
                    box_mask = bit.bor(box_mask, bit.lshift(1, math.floor(index / 3) * 3 + math.floor(col / 3)))
                end
            end
        else
            for row = 0, 8 do
                if prop:is_empty(row, index) and bit.band(prop:cand(row, index), v_bit) ~= 0 then
                    box_mask = bit.bor(box_mask, bit.lshift(1, math.floor(row / 3) * 3 + math.floor(index / 3)))
                end
            end
        end
        if box_mask ~= 0 and flags.count(box_mask) == 1 then
            local confined = collect_line_confined(prop, is_row, index, v_bit)
            local box_idx = flags.lowest_bit(box_mask)
            local start_row = math.floor(box_idx / 3) * 3
            local start_col = (box_idx % 3) * 3
            local pattern = {
                kind = "pointing",
                cells = confined,
                values = { v },
                unit = unit_desc,
                target = units.box_unit(box_idx),
            }
            for r = start_row, start_row + 2 do
                for col = start_col, start_col + 2 do
                    if is_row then
                        if r ~= index then
                            changed = eliminate(r, col, v_bit, pattern) or changed
                        end
                    elseif col ~= index then
                        changed = eliminate(r, col, v_bit, pattern) or changed
                    end
                end
            end
        end
    end
    return changed
end

-- Claiming (box/line reduction): a candidate is confined to a single row/column
-- within a box, so it can be eliminated from the rest of that row/column.
-- unit = the box, target = the row/column.
local function claiming_from_box(prop, path, box_idx, eliminate)
    local changed = false
    local start_row = math.floor(box_idx / 3) * 3
    local start_col = (box_idx % 3) * 3
    for v = 1, 9 do
        local v_bit = bit.lshift(1, v - 1)
        local row_mask = 0
        local col_mask = 0
        for r = start_row, start_row + 2 do
            for col = start_col, start_col + 2 do
                if prop:is_empty(r, col) and bit.band(prop:cand(r, col), v_bit) ~= 0 then
                    row_mask = bit.bor(row_mask, bit.lshift(1, r))
                    col_mask = bit.bor(col_mask, bit.lshift(1, col))
                end
            end
        end
        local row_single = (row_mask ~= 0 and flags.count(row_mask) == 1)
        local col_single = (col_mask ~= 0 and flags.count(col_mask) == 1)
        if row_single or col_single then
            local confined = collect_box_confined(prop, start_row, start_col, v_bit)
            if row_single then
                local row = flags.lowest_bit(row_mask)
                local pattern = {
                    kind = "claiming",
                    cells = confined,
                    values = { v },
                    unit = units.box_unit(box_idx),
                    target = units.row_unit(row),
                }
                for col = 0, 8 do
                    if col < start_col or col >= start_col + 3 then
                        changed = eliminate(row, col, v_bit, pattern) or changed
                    end
                end
            end
            if col_single then
                local col = flags.lowest_bit(col_mask)
                local pattern = {
                    kind = "claiming",
                    cells = confined,
                    values = { v },
                    unit = units.box_unit(box_idx),
                    target = units.col_unit(col),
                }
                for row = 0, 8 do
                    if row < start_row or row >= start_row + 3 then
                        changed = eliminate(row, col, v_bit, pattern) or changed
                    end
                end
            end
        end
    end
    return changed
end

function locked_candidates.apply(prop, path)
    local changed = false
    local function eliminate(r, col, v_bit, pattern)
        if prop:is_empty(r, col) and bit.band(prop:cand(r, col), v_bit) ~= 0 then
            return prop:eliminate_candidate(r, col, v_bit, locked_candidates.flags(), path, pattern)
        end
        return false
    end
    for r = 0, 8 do
        if pointing_from_line(prop, path, units.row_unit(r), eliminate) then
            changed = true
        end
    end
    for col = 0, 8 do
        if pointing_from_line(prop, path, units.col_unit(col), eliminate) then
            changed = true
        end
    end
    for box_idx = 0, 8 do
        if claiming_from_box(prop, path, box_idx, eliminate) then
            changed = true
        end
    end
    return changed
end

function locked_candidates.flags()
    return flags.LOCKED_CANDIDATES
end

return locked_candidates
