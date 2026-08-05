local bit = require("bit")
local candidates = require("core.candidates")
local flags = require("core.techniques.flags")
local units = require("core.techniques.units")

local naked_triples = {}

local function process_unit(prop, path, unit_cells, unit)
    local changed = false
    local eligible = {}
    for _, cell in ipairs(unit_cells) do
        local r, col = cell[1], cell[2]
        if prop:is_empty(r, col) then
            local mask = prop:cand(r, col)
            local count = flags.count(mask)
            if count == 2 or count == 3 then
                eligible[#eligible + 1] = { cell = cell, mask = mask }
            end
        end
    end
    for i = 1, #eligible do
        for j = i + 1, #eligible do
            for k = j + 1, #eligible do
                local a, b, c = eligible[i], eligible[j], eligible[k]
                local union = bit.bor(a.mask, bit.bor(b.mask, c.mask))
                if flags.count(union) == 3 then
                    local pattern = {
                        kind = "naked_triple",
                        cells = { a.cell, b.cell, c.cell },
                        values = candidates.from_mask(union),
                        unit = unit,
                    }
                    for _, cell in ipairs(unit_cells) do
                        if cell ~= a.cell and cell ~= b.cell and cell ~= c.cell then
                            local r, col = cell[1], cell[2]
                            if prop:is_empty(r, col) and bit.band(prop:cand(r, col), union) ~= 0 then
                                changed = prop:eliminate_multiple_candidates(
                                    r,
                                    col,
                                    union,
                                    naked_triples.flags(),
                                    path,
                                    pattern
                                ) or changed
                            end
                        end
                    end
                end
            end
        end
    end
    return changed
end

function naked_triples.apply(prop, path)
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

function naked_triples.flags()
    return flags.NAKED_TRIPLES
end

return naked_triples
