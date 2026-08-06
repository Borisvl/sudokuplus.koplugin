local bit = require("bit")
local candidates = require("core.candidates")
local flags = require("core.techniques.flags")
local units = require("core.techniques.units")

local naked_quads = {}

local function is_pattern_cell(pattern, r, c)
    for _, cell in ipairs(pattern.cells) do
        if cell[1] == r and cell[2] == c then
            return true
        end
    end
    return false
end

local function process_unit(prop, path, unit_cells, unit)
    local changed = false
    local eligible = {}
    for _, cell in ipairs(unit_cells) do
        local r, col = cell[1], cell[2]
        if prop:is_empty(r, col) then
            local mask = prop:cand(r, col)
            local count = flags.count(mask)
            if count >= 2 and count <= 4 then
                eligible[#eligible + 1] = { cell = cell, mask = mask }
            end
        end
    end
    local combo = {}
    local function rec(start)
        if #combo == 4 then
            local union = 0
            local pattern = {
                kind = "naked_quad",
                cells = {},
                values = {},
                unit = unit,
            }
            for _, i in ipairs(combo) do
                union = bit.bor(union, eligible[i].mask)
                pattern.cells[#pattern.cells + 1] = eligible[i].cell
            end
            if flags.count(union) == 4 then
                pattern.values = candidates.from_mask(union)
                for _, cell in ipairs(unit_cells) do
                    local r, col = cell[1], cell[2]
                    if prop:is_empty(r, col) and not is_pattern_cell(pattern, r, col) then
                        if bit.band(prop:cand(r, col), union) ~= 0 then
                            changed = prop:eliminate_multiple_candidates(
                                r,
                                col,
                                union,
                                naked_quads.flags(),
                                path,
                                pattern
                            ) or changed
                        end
                    end
                end
            end
            return
        end
        for i = start, #eligible do
            combo[#combo + 1] = i
            rec(i + 1)
            combo[#combo] = nil
        end
    end
    rec(1)
    return changed
end

function naked_quads.apply(prop, path)
    local changed = false
    units.for_each_unit(function(unit, cells)
        if process_unit(prop, path, cells, unit) then
            changed = true
        end
    end)
    return changed
end

function naked_quads.flags()
    return flags.NAKED_QUADS
end

return naked_quads
