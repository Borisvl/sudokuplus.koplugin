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

            -- Standard hidden-pair semantics: both digits occur at least once
            -- (each may occur once or twice) and their positions' union is
            -- exactly two cells. Requiring both present is what keeps the
            -- elimination sound: otherwise a digit with zero positions could
            -- still "confine" the other digit to two cells and the removal
            -- would strip legitimate candidates.
            local union = {}
            local pair_cells = {}
            local n1_found, n2_found = false, false
            local function add(cell)
                local key = cell[1] * 9 + cell[2]
                if not union[key] then
                    union[key] = true
                    pair_cells[#pair_cells + 1] = cell
                end
            end
            for _, cell in ipairs(unit_cells) do
                local r, col = cell[1], cell[2]
                if prop:is_empty(r, col) then
                    local mask = prop:cand(r, col)
                    if bit.band(mask, n1_bit) ~= 0 then
                        n1_found = true
                        add(cell)
                    end
                    if bit.band(mask, n2_bit) ~= 0 then
                        n2_found = true
                        add(cell)
                    end
                end
            end

            if n1_found and n2_found and #pair_cells == 2 then
                table.sort(pair_cells, function(a, b)
                    return a[1] * 9 + a[2] < b[1] * 9 + b[2]
                end)
                local keep_mask = bit.bor(n1_bit, n2_bit)
                local pattern = {
                    kind = "hidden_pair",
                    cells = pair_cells,
                    values = { n1, n2 },
                    unit = unit,
                }
                for _, cell in ipairs(pair_cells) do
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
