local bit = require("bit")
local flags = require("core.techniques.flags")
local units = require("core.techniques.units")

local hidden_pairs = {}

local function process_unit(prop, path, unit_cells, unit)
    local changed = false
    for n1 = 1, 8 do
        for n2 = n1 + 1, 9 do
            local n1_bit = bit.lshift(1, n1 - 1)
            local n2_bit = bit.lshift(1, n2 - 1)
            local cells1 = {}
            local cells2 = {}
            for _, cell in ipairs(unit_cells) do
                local r, col = cell[1], cell[2]
                if prop:is_empty(r, col) then
                    local mask = prop:cand(r, col)
                    if bit.band(mask, n1_bit) ~= 0 then
                        cells1[#cells1 + 1] = cell
                    end
                    if bit.band(mask, n2_bit) ~= 0 then
                        cells2[#cells2 + 1] = cell
                    end
                end
            end
            if #cells1 == 2 and #cells2 == 2 and cells1[1] == cells2[1] and cells1[2] == cells2[2] then
                local keep_mask = bit.bor(n1_bit, n2_bit)
                local pattern = {
                    kind = "hidden_pair",
                    cells = { cells1[1], cells1[2] },
                    values = { n1, n2 },
                    unit = unit,
                }
                for _, cell in ipairs(cells1) do
                    local r, col = cell[1], cell[2]
                    local elim_mask = bit.band(prop:cand(r, col), bit.bnot(keep_mask))
                    if elim_mask ~= 0 then
                        changed = prop:eliminate_multiple_candidates(
                            r,
                            col,
                            elim_mask,
                            hidden_pairs.flags(),
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

function hidden_pairs.apply(prop, path)
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

function hidden_pairs.flags()
    return flags.HIDDEN_PAIRS
end

return hidden_pairs
