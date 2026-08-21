local bit = require("bit")
local flags = require("sudokuplus.core.techniques.flags")
local units = require("sudokuplus.core.techniques.units")

-- XY-Wing: a bivalue pivot {X, Y} with two bivalue wings {X, Z} and {Y, Z}
-- that see the pivot. The pivot must be X or Y, forcing the corresponding
-- wing to be Z, so Z can be eliminated from any cell seeing both wings.
local xy_wing = {}

local function eliminate_z(prop, path, p1, p2, z_bit, pattern)
    local changed = false
    for _, cell in ipairs(units.peers_of(p1[1], p1[2])) do
        local r, c = cell[1], cell[2]
        if
            (r ~= p2[1] or c ~= p2[2])
            and units.sees(r, c, p2[1], p2[2])
            and prop:is_empty(r, c)
            and bit.band(prop:cand(r, c), z_bit) ~= 0
        then
            changed = prop:eliminate_candidate(r, c, z_bit, xy_wing.flags(), path, pattern) or changed
        end
    end
    return changed
end

function xy_wing.apply(prop, path)
    local changed = false
    local bivalue = units.bivalue_cells(prop.candidates, prop.board)
    for _, pivot in ipairs(bivalue) do
        local pr, pc, pmask = pivot[1], pivot[2], pivot[3]
        local lowest = pmask - bit.band(pmask, pmask - 1)
        local x_val = flags.lowest_bit(lowest) + 1
        local y_val = flags.lowest_bit(bit.bxor(pmask, lowest)) + 1

        local x_wings, y_wings = {}, {}
        for _, wing in ipairs(bivalue) do
            local wr, wc, wmask = wing[1], wing[2], wing[3]
            if (wr ~= pr or wc ~= pc) and units.sees(pr, pc, wr, wc) then
                local shared = bit.band(wmask, pmask)
                if flags.count(shared) == 1 then
                    local shared_val = flags.lowest_bit(shared) + 1
                    local z_val = flags.lowest_bit(bit.bxor(wmask, shared)) + 1
                    if shared_val == x_val then
                        x_wings[#x_wings + 1] = { cell = { wr, wc }, z = z_val }
                    elseif shared_val == y_val then
                        y_wings[#y_wings + 1] = { cell = { wr, wc }, z = z_val }
                    end
                end
            end
        end
        for _, xw in ipairs(x_wings) do
            for _, yw in ipairs(y_wings) do
                if xw.z == yw.z then
                    local pattern = {
                        kind = "xy_wing",
                        cells = { { pr, pc }, xw.cell, yw.cell },
                        values = { xw.z },
                        pivot = { pr, pc },
                        pincers = { xw.cell, yw.cell },
                    }
                    if eliminate_z(prop, path, xw.cell, yw.cell, bit.lshift(1, xw.z - 1), pattern) then
                        changed = true
                    end
                end
            end
        end
    end
    return changed
end

function xy_wing.flags()
    return flags.XY_WING
end

return xy_wing
