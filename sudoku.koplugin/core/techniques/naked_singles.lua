local flags = require("core.techniques.flags")

local naked_singles = {}

function naked_singles.apply(prop, path)
    local placements_made = false
    for r = 0, 8 do
        for col = 0, 8 do
            if prop:is_empty(r, col) then
                local mask = prop:cand(r, col)
                if flags.count(mask) == 1 then
                    local num = flags.lowest_bit(mask) + 1
                    prop:place_and_update(r, col, num, naked_singles.flags(), path, {
                        kind = "naked_single",
                        cells = { { r, col } },
                        values = { num },
                    })
                    placements_made = true
                end
            end
        end
    end
    return placements_made
end

function naked_singles.flags()
    return flags.NAKED_SINGLES
end

return naked_singles
