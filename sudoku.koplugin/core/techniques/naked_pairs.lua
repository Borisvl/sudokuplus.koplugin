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
                local pattern = {
                    kind = "naked_pair",
                    cells = { a.cell, b.cell },
                    values = candidates.from_mask(a.mask),
                    unit = unit,
                }
                for _, cell in ipairs(unit_cells) do
                    if cell ~= a.cell and cell ~= b.cell then
                        local r, col = cell[1], cell[2]
                        if prop:is_empty(r, col) and bit.band(prop:cand(r, col), a.mask) ~= 0 then
                            changed = prop:eliminate_multiple_candidates(
                                r,
                                col,
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
    end
    return changed
end

function naked_pairs.apply(prop, path)
    local changed = false
    for r = 0, 8 do
        if process_unit(prop, path, units.row_cells(r), { type = "row", index = r }) then
            changed = true
        end
    end
    for col = 0, 8 do
        if process_unit(prop, path, units.col_cells(col), { type = "col", index = col }) then
            changed = true
        end
    end
    for box_idx = 0, 8 do
        if process_unit(prop, path, units.box_cells(box_idx), { type = "box", index = box_idx }) then
            changed = true
        end
    end
    return changed
end

function naked_pairs.flags()
    return flags.NAKED_PAIRS
end

return naked_pairs
