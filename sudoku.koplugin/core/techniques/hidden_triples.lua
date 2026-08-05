local bit = require("bit")
local flags = require("core.techniques.flags")
local units = require("core.techniques.units")

local hidden_triples = {}

local function process_unit(prop, path, unit_cells, unit)
    local changed = false
    for n1 = 1, 7 do
        for n2 = n1 + 1, 8 do
            for n3 = n2 + 1, 9 do
                local bits = {
                    bit.lshift(1, n1 - 1),
                    bit.lshift(1, n2 - 1),
                    bit.lshift(1, n3 - 1),
                }
                local cell_lists = { {}, {}, {} }
                for _, cell in ipairs(unit_cells) do
                    local r, col = cell[1], cell[2]
                    if prop:is_empty(r, col) then
                        local mask = prop:cand(r, col)
                        for i = 1, 3 do
                            if bit.band(mask, bits[i]) ~= 0 then
                                cell_lists[i][#cell_lists[i] + 1] = cell
                            end
                        end
                    end
                end
                if
                    #cell_lists[1] > 0
                    and #cell_lists[1] <= 3
                    and #cell_lists[2] > 0
                    and #cell_lists[2] <= 3
                    and #cell_lists[3] > 0
                    and #cell_lists[3] <= 3
                then
                    local all = {}
                    for i = 1, 3 do
                        for _, cell in ipairs(cell_lists[i]) do
                            local dup = false
                            for _, existing in ipairs(all) do
                                if existing[1] == cell[1] and existing[2] == cell[2] then
                                    dup = true
                                    break
                                end
                            end
                            if not dup then
                                all[#all + 1] = cell
                            end
                        end
                    end
                    if #all == 3 then
                        local keep_mask = bit.bor(bits[1], bit.bor(bits[2], bits[3]))
                        local pattern = {
                            kind = "hidden_triple",
                            cells = all,
                            values = { n1, n2, n3 },
                            unit = unit,
                        }
                        for _, cell in ipairs(all) do
                            local r, col = cell[1], cell[2]
                            local elim_mask = bit.band(prop:cand(r, col), bit.bnot(keep_mask))
                            if elim_mask ~= 0 then
                                changed = prop:eliminate_multiple_candidates(
                                    r,
                                    col,
                                    elim_mask,
                                    hidden_triples.flags(),
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

function hidden_triples.apply(prop, path)
    local changed = false
    units.for_each_unit(function(unit, cells)
        if process_unit(prop, path, cells, unit) then
            changed = true
        end
    end)
    return changed
end

function hidden_triples.flags()
    return flags.HIDDEN_TRIPLES
end

return hidden_triples
