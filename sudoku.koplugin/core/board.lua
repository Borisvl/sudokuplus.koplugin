local board = {}

local SIZE = 81

local function index(r, c)
    return r * 9 + c + 1
end

function board.new()
    local cells = {}
    for i = 1, SIZE do
        cells[i] = 0
    end
    return cells
end

function board.from_string(s)
    if #s ~= SIZE then
        return nil, "input string must be exactly 81 characters long"
    end
    local cells = board.new()
    for i = 1, SIZE do
        local ch = s:sub(i, i)
        if ch == "." or ch == "_" then
            cells[i] = 0
        elseif ch >= "0" and ch <= "9" then
            cells[i] = tonumber(ch)
        else
            return nil, "input string must contain only digits '0'-'9'"
        end
    end
    return cells
end

function board.to_string(b)
    local out = {}
    for i = 1, SIZE do
        out[i] = tostring(b[i])
    end
    return table.concat(out)
end

function board.get(b, r, c)
    return b[index(r, c)]
end

function board.set(b, r, c, value)
    b[index(r, c)] = value
end

function board.is_empty(b, r, c)
    return b[index(r, c)] == 0
end

function board.clone(b)
    local copy = {}
    for i = 1, SIZE do
        copy[i] = b[i]
    end
    return copy
end

function board.count_clues(b)
    local count = 0
    for i = 1, SIZE do
        if b[i] ~= 0 then
            count = count + 1
        end
    end
    return count
end

function board.iter_empty_cells(b)
    local cells = {}
    for r = 0, 8 do
        for c = 0, 8 do
            if board.is_empty(b, r, c) then
                cells[#cells + 1] = { r, c }
            end
        end
    end
    return cells
end

return board
