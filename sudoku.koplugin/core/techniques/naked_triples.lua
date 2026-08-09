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
            -- A valid naked subset can include a 1-candidate cell (e.g. a
            -- singleton inside the triple); the union check below still
            -- requires exactly three digits across the three cells.
            if count >= 1 and count <= 3 then
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
                        local r, col = cell[1], cell[2]
                        if
                            (r ~= a.cell[1] or col ~= a.cell[2])
                            and (r ~= b.cell[1] or col ~= b.cell[2])
                            and (r ~= c.cell[1] or col ~= c.cell[2])
                        then
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
    units.for_each_unit(function(unit, cells)
        if process_unit(prop, path, cells, unit) then
            changed = true
        end
    end)
    return changed
end

function naked_triples.flags()
    return flags.NAKED_TRIPLES
end

return naked_triples
