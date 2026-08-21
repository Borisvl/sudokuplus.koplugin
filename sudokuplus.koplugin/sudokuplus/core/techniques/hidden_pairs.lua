local bit = require("bit")
local flags = require("sudokuplus.core.techniques.flags")
local units = require("sudokuplus.core.techniques.units")

local hidden_pairs = {}

local function process_unit(prop, path, unit_cells, unit)
    local changed = false
    local pos_mask = units.build_pos_mask(prop, unit_cells)

    for n1 = 1, 8 do
        local m1 = pos_mask[n1]
        if m1 ~= 0 and flags.count(m1) <= 2 then
            local n1_bit = bit.lshift(1, n1 - 1)
            for n2 = n1 + 1, 9 do
                local m2 = pos_mask[n2]
                if m2 ~= 0 and flags.count(m2) <= 2 then
                    local union_mask = bit.bor(m1, m2)
                    if flags.count(union_mask) == 2 then
                        local n2_bit = bit.lshift(1, n2 - 1)
                        local pair_cells = {}
                        local pair_indices = {}
                        for idx, cell in ipairs(unit_cells) do
                            if bit.band(union_mask, bit.lshift(1, idx - 1)) ~= 0 then
                                pair_cells[#pair_cells + 1] = cell
                                pair_indices[#pair_indices + 1] = idx
                            end
                        end
                        local keep_mask = bit.bor(n1_bit, n2_bit)
                        local pattern = {
                            kind = "hidden_pair",
                            cells = pair_cells,
                            values = { n1, n2 },
                            unit = unit,
                        }
                        for i = 1, #pair_cells do
                            local cell = pair_cells[i]
                            local idx = pair_indices[i]
                            local r, col = cell[1], cell[2]
                            local elim_mask = bit.band(prop:cand(r, col), bit.bnot(keep_mask))
                            if elim_mask ~= 0 then
                                prop:eliminate_multiple_candidates(
                                    r,
                                    col,
                                    elim_mask,
                                    hidden_pairs.flags(),
                                    path,
                                    pattern
                                )
                                changed = true
                                units.update_pos_mask(pos_mask, idx, elim_mask)
                            end
                        end
                    end
                end
            end
        end
    end
    return changed
end

function hidden_pairs.apply(prop, path)
    local changed = false
    units.for_each_unit(function(unit, cells)
        if process_unit(prop, path, cells, unit) then
            changed = true
        end
    end)
    return changed
end

function hidden_pairs.flags()
    return flags.HIDDEN_PAIRS
end

return hidden_pairs
