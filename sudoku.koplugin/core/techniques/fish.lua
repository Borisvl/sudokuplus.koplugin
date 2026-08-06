local bit = require("bit")
local flags = require("core.techniques.flags")
local units = require("core.techniques.units")

-- Shared engine for the "fish" family: X-Wing (size 2), Swordfish (size 3),
-- Jellyfish (size 4). For a candidate digit, if it appears in 2..size
-- positions across exactly `size` lines (all rows or all columns), and those
-- positions collectively span exactly `size` crossing lines, the digit can be
-- eliminated from those crossing lines in every other line. Thin technique
-- modules parametrize this engine; the pattern metadata carries the defining
-- lines as `base` and the crossing lines as `cover`.
local fish = {}

local function line_cells(unit_type, index)
    if unit_type == "row" then
        return units.row_cells(index)
    end
    return units.col_cells(index)
end

local function line_unit(unit_type, index)
    if unit_type == "row" then
        return units.row_unit(index)
    end
    return units.col_unit(index)
end

local function crossing_type(unit_type)
    if unit_type == "row" then
        return "col"
    end
    return "row"
end

-- All combinations of `size` indices from 1..count.
local function combinations(count, size)
    local result = {}
    local combo = {}
    local function rec(start)
        if #combo == size then
            local copy = {}
            for i = 1, size do
                copy[i] = combo[i]
            end
            result[#result + 1] = copy
            return
        end
        for i = start, count do
            combo[#combo + 1] = i
            rec(i + 1)
            combo[#combo] = nil
        end
    end
    rec(1)
    return result
end

local function process_orientation(prop, path, candidate_bit, unit_type, size, technique_flags, kind)
    local changed = false
    local eligible =
        units.find_units_with_candidate_count_range(candidate_bit, 2, size, prop.candidates, prop.board, unit_type)
    for _, combo in ipairs(combinations(#eligible, size)) do
        local base_lines, cover_mask = {}, 0
        for _, i in ipairs(combo) do
            local entry = eligible[i]
            base_lines[#base_lines + 1] = entry[1]
            for _, position in ipairs(entry[2]) do
                cover_mask = bit.bor(cover_mask, bit.lshift(1, position))
            end
        end
        if flags.count(cover_mask) == size then
            local base_units = {}
            local cover_units = {}
            for _, index in ipairs(base_lines) do
                base_units[#base_units + 1] = line_unit(unit_type, index)
            end
            for position = 0, 8 do
                if bit.band(cover_mask, bit.lshift(1, position)) ~= 0 then
                    cover_units[#cover_units + 1] = line_unit(crossing_type(unit_type), position)
                end
            end
            local pattern = {
                kind = kind,
                cells = {},
                values = { flags.lowest_bit(candidate_bit) + 1 },
                base = base_units,
                cover = cover_units,
            }
            for _, index in ipairs(base_lines) do
                for _, cell in ipairs(line_cells(unit_type, index)) do
                    local r, c = cell[1], cell[2]
                    if prop:is_empty(r, c) and bit.band(prop:cand(r, c), candidate_bit) ~= 0 then
                        pattern.cells[#pattern.cells + 1] = { r, c }
                    end
                end
            end
            for position = 0, 8 do
                if bit.band(cover_mask, bit.lshift(1, position)) ~= 0 then
                    for i = 0, 8 do
                        local r, c
                        if unit_type == "row" then
                            r, c = i, position
                        else
                            r, c = position, i
                        end
                        local in_base = false
                        for _, index in ipairs(base_lines) do
                            if (unit_type == "row" and r == index) or (unit_type == "col" and c == index) then
                                in_base = true
                                break
                            end
                        end
                        if not in_base and prop:is_empty(r, c) and bit.band(prop:cand(r, c), candidate_bit) ~= 0 then
                            changed = prop:eliminate_candidate(r, c, candidate_bit, technique_flags, path, pattern)
                                or changed
                        end
                    end
                end
            end
        end
    end
    return changed
end

-- size: number of defining lines (2 = X-Wing, 3 = Swordfish, 4 = Jellyfish).
-- kind: pattern kind recorded on solve steps (e.g. "x_wing").
function fish.apply(prop, path, size, technique_flags, kind)
    local changed = false
    for candidate = 1, 9 do
        local candidate_bit = bit.lshift(1, candidate - 1)
        if process_orientation(prop, path, candidate_bit, "row", size, technique_flags, kind) then
            changed = true
        end
        if process_orientation(prop, path, candidate_bit, "col", size, technique_flags, kind) then
            changed = true
        end
    end
    return changed
end

return fish
