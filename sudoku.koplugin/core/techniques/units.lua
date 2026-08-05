local bit = require("bit")
local board = require("core.board")
local candidates = require("core.candidates")

local units = {}

local ROW_CELLS = {}
local COL_CELLS = {}
local BOX_CELLS = {}

for i = 0, 8 do
    local row = {}
    local col = {}
    for j = 0, 8 do
        row[j + 1] = { i, j }
        col[j + 1] = { j, i }
    end
    ROW_CELLS[i + 1] = row
    COL_CELLS[i + 1] = col

    local start_row = math.floor(i / 3) * 3
    local start_col = (i % 3) * 3
    local box = {}
    for k = 0, 8 do
        box[k + 1] = { start_row + math.floor(k / 3), start_col + k % 3 }
    end
    BOX_CELLS[i + 1] = box
end

function units.row_cells(r)
    return ROW_CELLS[r + 1]
end

function units.col_cells(c)
    return COL_CELLS[c + 1]
end

function units.box_cells(box_idx)
    return BOX_CELLS[box_idx + 1]
end

function units.sees(r1, c1, r2, c2)
    return r1 == r2
        or c1 == c2
        or (math.floor(r1 / 3) == math.floor(r2 / 3) and math.floor(c1 / 3) == math.floor(c2 / 3))
end

function units.peers_of(r, c)
    local peers = {}
    for i = 0, 8 do
        if i ~= c then
            peers[#peers + 1] = { r, i }
        end
        if i ~= r then
            peers[#peers + 1] = { i, c }
        end
    end
    local start_row = math.floor(r / 3) * 3
    local start_col = math.floor(c / 3) * 3
    for br = start_row, start_row + 2 do
        for bc = start_col, start_col + 2 do
            if br ~= r and bc ~= c then
                peers[#peers + 1] = { br, bc }
            end
        end
    end
    return peers
end

function units.bivalue_cells(c, b)
    local cells = {}
    for r = 0, 8 do
        for col = 0, 8 do
            if board.is_empty(b, r, col) then
                local mask = candidates.get(c, r, col)
                local rest = bit.band(mask, mask - 1)
                if rest ~= 0 and bit.band(rest, rest - 1) == 0 then
                    cells[#cells + 1] = { r, col, mask }
                end
            end
        end
    end
    return cells
end

function units.find_units_with_n_candidates(candidate_bit, n, c, b, unit_type)
    local result = {}
    for i = 0, 8 do
        local cells
        if unit_type == "row" then
            cells = ROW_CELLS[i + 1]
        else
            cells = COL_CELLS[i + 1]
        end
        local positions = {}
        for _, cell in ipairs(cells) do
            local r, col = cell[1], cell[2]
            if board.is_empty(b, r, col) and bit.band(candidates.get(c, r, col), candidate_bit) ~= 0 then
                if unit_type == "row" then
                    positions[#positions + 1] = col
                else
                    positions[#positions + 1] = r
                end
            end
        end
        if #positions == n then
            result[#result + 1] = { i, positions }
        end
    end
    return result
end

return units
