local bit = require("bit")
local flags = require("sudokuplus.core.techniques.flags")
local units = require("sudokuplus.core.techniques.units")

-- Skyscraper: two lines (rows or columns) each hold a candidate in exactly two
-- positions and share exactly one of them (the "base"). The two non-shared
-- positions (the "roof") cannot both be false, so any cell seeing both roof
-- cells cannot contain the candidate.
local skyscraper = {}

local function line_cells(unit_type, index)
    if unit_type == "row" then
        return units.row_cells(index)
    end
    return units.col_cells(index)
end

local function line_position(unit_type, cell)
    if unit_type == "row" then
        return cell[2]
    end
    return cell[1]
end

local function process_orientation(prop, path, candidate_bit, unit_type)
    local changed = false
    local eligible = {}
    for i = 0, 8 do
        local positions = {}
        for _, cell in ipairs(line_cells(unit_type, i)) do
            local r, c = cell[1], cell[2]
            if prop:is_empty(r, c) and bit.band(prop:cand(r, c), candidate_bit) ~= 0 then
                positions[#positions + 1] = cell
            end
        end
        if #positions == 2 then
            eligible[#eligible + 1] = { index = i, cells = positions }
        end
    end
    for i = 1, #eligible do
        for j = i + 1, #eligible do
            local a, b = eligible[i], eligible[j]
            local shared, shared_count
            for _, cell_a in ipairs(a.cells) do
                for _, cell_b in ipairs(b.cells) do
                    if line_position(unit_type, cell_a) == line_position(unit_type, cell_b) then
                        shared = line_position(unit_type, cell_a)
                        shared_count = (shared_count or 0) + 1
                    end
                end
            end
            if shared_count == 1 then
                local roof_a, roof_b
                for _, cell in ipairs(a.cells) do
                    if line_position(unit_type, cell) ~= shared then
                        roof_a = cell
                    end
                end
                for _, cell in ipairs(b.cells) do
                    if line_position(unit_type, cell) ~= shared then
                        roof_b = cell
                    end
                end
                local elim_cells = {}
                units.each_peer(roof_a[1], roof_a[2], function(r, c)
                    if
                        (r ~= roof_b[1] or c ~= roof_b[2])
                        and units.sees(r, c, roof_b[1], roof_b[2])
                        and prop:is_empty(r, c)
                        and bit.band(prop:cand(r, c), candidate_bit) ~= 0
                    then
                        elim_cells[#elim_cells + 1] = { r, c }
                    end
                end)

                if #elim_cells > 0 then
                    local base_a, base_b
                    if unit_type == "row" then
                        base_a = { a.index, shared }
                        base_b = { b.index, shared }
                    else
                        base_a = { shared, a.index }
                        base_b = { shared, b.index }
                    end
                    local pattern = {
                        kind = "skyscraper",
                        cells = { base_a, base_b, roof_a, roof_b },
                        values = { flags.lowest_bit(candidate_bit) + 1 },
                        base = { base_a, base_b },
                        roof = { roof_a, roof_b },
                    }
                    for _, target in ipairs(elim_cells) do
                        changed = prop:eliminate_candidate(
                            target[1],
                            target[2],
                            candidate_bit,
                            skyscraper.flags(),
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

function skyscraper.apply(prop, path)
    local changed = false
    for candidate = 1, 9 do
        local candidate_bit = bit.lshift(1, candidate - 1)
        if process_orientation(prop, path, candidate_bit, "row") then
            changed = true
        end
        if process_orientation(prop, path, candidate_bit, "col") then
            changed = true
        end
    end
    return changed
end

function skyscraper.flags()
    return flags.SKYSCRAPER
end

return skyscraper
