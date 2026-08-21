local bit = require("bit")
local flags = require("sudokuplus.core.techniques.flags")
local units = require("sudokuplus.core.techniques.units")

-- XYZ-Wing: a trivalue pivot {X, Y, Z} with two bivalue pincers that see the
-- pivot, whose candidate sets are subsets of the pivot's and together cover
-- it ({X, Z} and {Y, Z}). One of pivot or the pincers must be Z, so Z can be
-- eliminated from any cell seeing all three.
local xyz_wing = {}

local function eliminate_z(prop, path, pivot, p1, p2, z_bit, pattern)
    local changed = false
    for _, cell in ipairs(units.peers_of(pivot[1], pivot[2])) do
        local r, c = cell[1], cell[2]
        if
            (r ~= p1[1] or c ~= p1[2])
            and (r ~= p2[1] or c ~= p2[2])
            and units.sees(r, c, p1[1], p1[2])
            and units.sees(r, c, p2[1], p2[2])
            and prop:is_empty(r, c)
            and bit.band(prop:cand(r, c), z_bit) ~= 0
        then
            changed = prop:eliminate_candidate(r, c, z_bit, xyz_wing.flags(), path, pattern) or changed
        end
    end
    return changed
end

function xyz_wing.apply(prop, path)
    local changed = false
    local bivalue, trivalue = {}, {}
    for r = 0, 8 do
        for c = 0, 8 do
            if prop:is_empty(r, c) then
                local mask = prop:cand(r, c)
                local count = flags.count(mask)
                if count == 3 then
                    trivalue[#trivalue + 1] = { r, c, mask }
                elseif count == 2 then
                    bivalue[#bivalue + 1] = { r, c, mask }
                end
            end
        end
    end
    for _, pivot in ipairs(trivalue) do
        local pr, pc, pmask = pivot[1], pivot[2], pivot[3]
        local pincers = {}
        for _, b in ipairs(bivalue) do
            if units.sees(pr, pc, b[1], b[2]) and bit.band(b[3], bit.bnot(pmask)) == 0 then
                pincers[#pincers + 1] = b
            end
        end
        for i = 1, #pincers do
            for j = i + 1, #pincers do
                local p1, p2 = pincers[i], pincers[j]
                if bit.bor(p1[3], p2[3]) == pmask then
                    local shared = bit.band(p1[3], p2[3])
                    if flags.count(shared) == 1 then
                        local z_val = flags.lowest_bit(shared) + 1
                        local pattern = {
                            kind = "xyz_wing",
                            cells = { { pr, pc }, { p1[1], p1[2] }, { p2[1], p2[2] } },
                            values = { z_val },
                            pivot = { pr, pc },
                            pincers = { { p1[1], p1[2] }, { p2[1], p2[2] } },
                        }
                        if
                            eliminate_z(
                                prop,
                                path,
                                { pr, pc },
                                { p1[1], p1[2] },
                                { p2[1], p2[2] },
                                bit.lshift(1, z_val - 1),
                                pattern
                            )
                        then
                            changed = true
                        end
                    end
                end
            end
        end
    end
    return changed
end

function xyz_wing.flags()
    return flags.XYZ_WING
end

return xyz_wing
