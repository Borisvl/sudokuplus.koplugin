local bit = require("bit")
local flags = require("core.techniques.flags")
local units = require("core.techniques.units")

local hidden_quads = {}

local function is_pattern_cell(cells, r, c)
    for _, cell in ipairs(cells) do
        if cell[1] == r and cell[2] == c then
            return true
        end
    end
    return false
end

local function process_unit(prop, path, unit_cells, unit)
    local changed = false
    local combo = {}
    local function rec(start)
        if #combo == 4 then
            local keep_mask = 0
            local all = {}
            local valid = true
            for _, n in ipairs(combo) do
                local n_bit = bit.lshift(1, n - 1)
                local cell_list = {}
                for _, cell in ipairs(unit_cells) do
                    local r, col = cell[1], cell[2]
                    if prop:is_empty(r, col) and bit.band(prop:cand(r, col), n_bit) ~= 0 then
                        cell_list[#cell_list + 1] = cell
                    end
                end
                if #cell_list == 0 or #cell_list > 4 then
                    valid = false
                    break
                end
                keep_mask = bit.bor(keep_mask, n_bit)
                for _, cell in ipairs(cell_list) do
                    if not is_pattern_cell(all, cell[1], cell[2]) then
                        all[#all + 1] = cell
                    end
                end
            end
            if valid and #all == 4 then
                local pattern = {
                    kind = "hidden_quad",
                    cells = all,
                    values = { combo[1], combo[2], combo[3], combo[4] },
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
                            hidden_quads.flags(),
                            path,
                            pattern
                        ) or changed
                    end
                end
            end
            return
        end
        for n = start, 9 do
            combo[#combo + 1] = n
            rec(n + 1)
            combo[#combo] = nil
        end
    end
    rec(1)
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
