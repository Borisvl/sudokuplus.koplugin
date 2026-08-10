local bit = require("bit")
local board = require("core.board")
local candidates = require("core.candidates")
local flags = require("core.techniques.flags")
local masks = require("core.masks")

local units = {}

local ROW_CELLS = {}
local COL_CELLS = {}
local BOX_CELLS = {}
local ROW_UNITS = {}
local COL_UNITS = {}
local BOX_UNITS = {}

for i = 0, 8 do
    local row = {}
    local col = {}
    for j = 0, 8 do
        row[j + 1] = { i, j }
        col[j + 1] = { j, i }
    end
    ROW_CELLS[i + 1] = row
    COL_CELLS[i + 1] = col
    ROW_UNITS[i + 1] = { type = "row", index = i }
    COL_UNITS[i + 1] = { type = "col", index = i }

    local start_row = math.floor(i / 3) * 3
    local start_col = (i % 3) * 3
    local box = {}
    for k = 0, 8 do
        box[k + 1] = { start_row + math.floor(k / 3), start_col + k % 3 }
    end
    BOX_CELLS[i + 1] = box
    BOX_UNITS[i + 1] = { type = "box", index = i }
end

function units.row_cells(r)
    return ROW_CELLS[r + 1]
end

function units.col_cells(c)
    return COL_CELLS[c + 1]
end

function units.box_cells(box_idx)
    return BOX_CELLS[box_idx + 1]
end

-- Shared unit descriptors; treat as immutable. They are referenced from
-- pattern metadata on solve steps.
function units.row_unit(r)
    return ROW_UNITS[r + 1]
end

function units.col_unit(c)
    return COL_UNITS[c + 1]
end

function units.box_unit(box_idx)
    return BOX_UNITS[box_idx + 1]
end

-- Iterates every unit in rustoku's fixed order (rows, then columns, then boxes).
function units.for_each_unit(fn)
    for i = 1, 9 do
        fn(ROW_UNITS[i], ROW_CELLS[i])
    end
    for i = 1, 9 do
        fn(COL_UNITS[i], COL_CELLS[i])
    end
    for i = 1, 9 do
        fn(BOX_UNITS[i], BOX_CELLS[i])
    end
end

function units.find_units_with_n_candidates(candidate_bit, n, c, b, unit_type)
    return units.find_units_with_candidate_count_range(candidate_bit, n, n, c, b, unit_type)
end

function units.find_units_with_candidate_count_range(candidate_bit, min_n, max_n, c, b, unit_type)
    local result = {}
    for i = 0, 8 do
        local cells
        if unit_type == "row" then
            cells = ROW_CELLS[i + 1]
        else
            cells = COL_CELLS[i + 1]
        end
        local positions = {}
        for _, cell in ipairs(cells) do
            local r, col = cell[1], cell[2]
            if board.raw_is_empty(b, r, col) and bit.band(candidates.get(c, r, col), candidate_bit) ~= 0 then
                if unit_type == "row" then
                    positions[#positions + 1] = col
                else
                    positions[#positions + 1] = r
                end
            end
        end
        if #positions >= min_n and #positions <= max_n then
            result[#result + 1] = { i, positions }
        end
    end
    return result
end

function units.sees(r1, c1, r2, c2)
    return r1 == r2 or c1 == c2 or masks.get_box_idx(r1, c1) == masks.get_box_idx(r2, c2)
end

-- Invokes fn(combo) for every combination of `size` indices from 1..count, in
-- lexicographic order. fn receives a fresh table it may retain; no calls are
-- made when count < size or size <= 0.
function units.for_each_combination(count, size, fn)
    if size <= 0 or count < size then
        return
    end
    local combo = {}
    local function rec(start)
        if #combo == size then
            local copy = {}
            for i = 1, size do
                copy[i] = combo[i]
            end
            fn(copy)
            return
        end
        for i = start, count do
            combo[#combo + 1] = i
            rec(i + 1)
            combo[#combo] = nil
        end
    end
    rec(1)
end

-- Lists { r, c, mask } for every empty cell holding exactly two candidates.
function units.bivalue_cells(c, b)
    local result = {}
    for r = 0, 8 do
        for col = 0, 8 do
            if board.raw_is_empty(b, r, col) then
                local mask = candidates.get(c, r, col)
                if flags.count(mask) == 2 then
                    result[#result + 1] = { r, col, mask }
                end
            end
        end
    end
    return result
end

-- Calls visitor(r, c) for every peer of (r, c) — row, column and box peers,
-- excluding the cell itself — each exactly once, without allocating. This is
-- the canonical peer iteration; peers_of() builds a list from it.
function units.each_peer(r, c, visitor)
    for col = 0, 8 do
        if col ~= c then
            visitor(r, col)
        end
    end
    for row = 0, 8 do
        if row ~= r then
            visitor(row, c)
        end
    end
    local box_r = math.floor(r / 3) * 3
    local box_c = math.floor(c / 3) * 3
    for br = box_r, box_r + 2 do
        for bc = box_c, box_c + 2 do
            if br ~= r and bc ~= c then
                visitor(br, bc)
            end
        end
    end
end

-- Lists every cell sharing a row, column, or box with (r, c), excluding
-- itself, each cell exactly once.
function units.peers_of(r, c)
    local result = {}
    units.each_peer(r, c, function(cell_r, cell_c)
        result[#result + 1] = { cell_r, cell_c }
    end)
    return result
end

return units
