local bit = require("bit")
local flags = require("core.techniques.flags")
local units = require("core.techniques.units")

local hidden_quads = {}

local function process_unit(prop, path, unit_cells, unit)
    local changed = false
    local pos_mask = units.build_pos_mask(prop, unit_cells)

    for n1 = 1, 6 do
        local m1 = pos_mask[n1]
        if m1 ~= 0 and flags.count(m1) <= 4 then
            for n2 = n1 + 1, 7 do
                local m2 = pos_mask[n2]
                if m2 ~= 0 and flags.count(m2) <= 4 then
                    for n3 = n2 + 1, 8 do
                        local m3 = pos_mask[n3]
                        if m3 ~= 0 and flags.count(m3) <= 4 then
                            for n4 = n3 + 1, 9 do
                                local m4 = pos_mask[n4]
                                if m4 ~= 0 and flags.count(m4) <= 4 then
                                    local union_mask = bit.bor(bit.bor(m1, m2), bit.bor(m3, m4))
                                    if flags.count(union_mask) == 4 then
                                        local all = {}
                                        local indices = {}
                                        for idx, cell in ipairs(unit_cells) do
                                            if bit.band(union_mask, bit.lshift(1, idx - 1)) ~= 0 then
                                                all[#all + 1] = cell
                                                indices[#indices + 1] = idx
                                            end
                                        end
                                        local keep_mask = bit.bor(
                                            bit.bor(bit.lshift(1, n1 - 1), bit.lshift(1, n2 - 1)),
                                            bit.bor(bit.lshift(1, n3 - 1), bit.lshift(1, n4 - 1))
                                        )
                                        local pattern = {
                                            kind = "hidden_quad",
                                            cells = all,
                                            values = { n1, n2, n3, n4 },
                                            unit = unit,
                                        }
                                        for i = 1, #all do
                                            local cell = all[i]
                                            local idx = indices[i]
                                            local r, col = cell[1], cell[2]
                                            local elim_mask = bit.band(prop:cand(r, col), bit.bnot(keep_mask))
                                            if elim_mask ~= 0 then
                                                prop:eliminate_multiple_candidates(
                                                    r,
                                                    col,
                                                    elim_mask,
                                                    hidden_quads.flags(),
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
                end
            end
        end
    end
    return changed
end

function hidden_quads.apply(prop, path)
    local changed = false
    units.for_each_unit(function(unit, cells)
        if process_unit(prop, path, cells, unit) then
            changed = true
        end
    end)
    return changed
end

function hidden_quads.flags()
    return flags.HIDDEN_QUADS
end

return hidden_quads
