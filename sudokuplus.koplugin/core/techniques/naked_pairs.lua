local bit = require("bit")
local candidates = require("core.candidates")
local flags = require("core.techniques.flags")
local units = require("core.techniques.units")

local naked_pairs = {}

local function process_unit(prop, path, unit_cells, unit)
    local changed = false
    local two_cells = {}
    for _, cell in ipairs(unit_cells) do
        local r, col = cell[1], cell[2]
        if prop:is_empty(r, col) then
            local mask = prop:cand(r, col)
            if flags.count(mask) == 2 then
                two_cells[#two_cells + 1] = { cell = cell, mask = mask }
            end
        end
    end
    for i = 1, #two_cells do
        for j = i + 1, #two_cells do
            local a, b = two_cells[i], two_cells[j]
            if a.mask == b.mask then
                local targets = {}
                for _, cell in ipairs(unit_cells) do
                    local r, col = cell[1], cell[2]
                    if (r ~= a.cell[1] or col ~= a.cell[2]) and (r ~= b.cell[1] or col ~= b.cell[2]) then
                        if prop:is_empty(r, col) and bit.band(prop:cand(r, col), a.mask) ~= 0 then
                            targets[#targets + 1] = { r, col }
                        end
                    end
                end
                if #targets > 0 then
                    local pattern = {
                        kind = "naked_pair",
                        cells = { a.cell, b.cell },
                        values = candidates.from_mask(a.mask),
                        unit = unit,
                    }
                    for _, target in ipairs(targets) do
                        changed = prop:eliminate_multiple_candidates(
                            target[1],
                            target[2],
                            a.mask,
                            naked_pairs.flags(),
                            path,
                            pattern
                        ) or changed
                    end
                end
            end
        end
    end
    return changed
end

function naked_pairs.apply(prop, path)
    local changed = false
    units.for_each_unit(function(unit, cells)
        if process_unit(prop, path, cells, unit) then
            changed = true
        end
    end)
    return changed
end

function naked_pairs.flags()
    return flags.NAKED_PAIRS
end

return naked_pairs
