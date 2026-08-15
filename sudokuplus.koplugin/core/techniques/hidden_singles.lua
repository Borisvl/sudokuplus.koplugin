local bit = require("bit")
local flags = require("core.techniques.flags")
local units = require("core.techniques.units")

local hidden_singles = {}

local function check_unit(prop, path, unit_cells, unit)
    local placed = false
    for v = 1, 9 do
        local v_bit = bit.lshift(1, v - 1)
        local occurrences = 0
        local cell
        for _, unit_cell in ipairs(unit_cells) do
            local r, col = unit_cell[1], unit_cell[2]
            if prop:is_empty(r, col) and bit.band(prop:cand(r, col), v_bit) ~= 0 then
                occurrences = occurrences + 1
                cell = unit_cell
            end
        end
        if occurrences == 1 and cell and prop:is_empty(cell[1], cell[2]) then
            prop:place_and_update(cell[1], cell[2], v, hidden_singles.flags(), path, {
                kind = "hidden_single",
                cells = { { cell[1], cell[2] } },
                values = { v },
                unit = unit,
            })
            placed = true
        end
    end
    return placed
end

function hidden_singles.apply(prop, path)
    local changed = false
    units.for_each_unit(function(unit, cells)
        if check_unit(prop, path, cells, unit) then
            changed = true
        end
    end)
    return changed
end

function hidden_singles.flags()
    return flags.HIDDEN_SINGLES
end

return hidden_singles
