local bit = require("bit")
local candidates = require("core.candidates")
local flags = require("core.techniques.flags")
local units = require("core.techniques.units")

-- W-Wing: two identical bivalue cells {X, Y} connected by a strong link on one
-- of the candidates (say X) — X appears exactly twice in a unit, one pincer
-- seeing each end. Then at least one pincer must be Y, so Y can be eliminated
-- from any cell seeing both pincers.
local w_wing = {}

local function check_pincer_pair(prop, path, p1, p2, bridge_val, other_val)
    local bridge_bit = bit.lshift(1, bridge_val - 1)
    local other_bit = bit.lshift(1, other_val - 1)
    local changed = false
    units.for_each_unit(function(unit, cells)
        if changed then
            return
        end
        local ends = {}
        for _, cell in ipairs(cells) do
            local r, c = cell[1], cell[2]
            if prop:is_empty(r, c) and bit.band(prop:cand(r, c), bridge_bit) ~= 0 then
                ends[#ends + 1] = cell
            end
        end
        if #ends == 2 then
            local s1, s2 = ends[1], ends[2]
            local linked = (units.sees(p1[1], p1[2], s1[1], s1[2]) and units.sees(p2[1], p2[2], s2[1], s2[2]))
                or (units.sees(p1[1], p1[2], s2[1], s2[2]) and units.sees(p2[1], p2[2], s1[1], s1[2]))
            if linked then
                local p1_is_end = (s1[1] == p1[1] and s1[2] == p1[2]) or (s2[1] == p1[1] and s2[2] == p1[2])
                local p2_is_end = (s1[1] == p2[1] and s1[2] == p2[2]) or (s2[1] == p2[1] and s2[2] == p2[2])
                if not p1_is_end and not p2_is_end then
                    local pattern = {
                        kind = "w_wing",
                        cells = { p1, p2, s1, s2 },
                        values = { other_val },
                        bridge_value = bridge_val,
                        pincers = { p1, p2 },
                        bridge = { s1, s2 },
                    }
                    for _, cell in ipairs(units.peers_of(p1[1], p1[2])) do
                        local r, c = cell[1], cell[2]
                        if
                            (r ~= p2[1] or c ~= p2[2])
                            and units.sees(r, c, p2[1], p2[2])
                            and prop:is_empty(r, c)
                            and bit.band(prop:cand(r, c), other_bit) ~= 0
                        then
                            changed = prop:eliminate_candidate(r, c, other_bit, w_wing.flags(), path, pattern)
                                or changed
                        end
                    end
                end
            end
        end
    end)
    return changed
end

function w_wing.apply(prop, path)
    local changed = false
    local bivalue = units.bivalue_cells(prop.candidates, prop.board)
    for i = 1, #bivalue do
        for j = i + 1, #bivalue do
            local p1 = { bivalue[i][1], bivalue[i][2] }
            local p2 = { bivalue[j][1], bivalue[j][2] }
            if bivalue[i][3] == bivalue[j][3] and not units.sees(p1[1], p1[2], p2[1], p2[2]) then
                local digits = candidates.from_mask(bivalue[i][3])
                if check_pincer_pair(prop, path, p1, p2, digits[1], digits[2]) then
                    changed = true
                end
                if check_pincer_pair(prop, path, p1, p2, digits[2], digits[1]) then
                    changed = true
                end
            end
        end
    end
    return changed
end

function w_wing.flags()
    return flags.W_WING
end

return w_wing
