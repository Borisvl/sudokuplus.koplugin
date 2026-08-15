local board = {}

local SIZE = 81

local function index(r, c)
    if type(r) ~= "number" or r % 1 ~= 0 or r < 0 or r > 8 then
        return nil, "row must be an integer in the range 0..8"
    end
    if type(c) ~= "number" or c % 1 ~= 0 or c < 0 or c > 8 then
        return nil, "column must be an integer in the range 0..8"
    end
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
    if type(s) ~= "string" then
        return nil, "input must be a string"
    end
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
    if type(b) ~= "table" then
        return nil, "board must be a table"
    end
    local i, err = index(r, c)
    if not i then
        return nil, err
    end
    return b[i]
end

-- Stores `value` in cell (r, c). Preconditions (validated by solver.validate
-- at the public boundary, not here — this is a hot path): `value` must be an
-- integer in 0..9 (0 = empty), or the board invariants silently break.
function board.set(b, r, c, value)
    if type(b) ~= "table" then
        return nil, "board must be a table"
    end
    local i, err = index(r, c)
    if not i then
        return nil, err
    end
    b[i] = value
    return true
end

-- Unchecked accessors for internal hot paths (solver recursion, technique
-- scans, candidate propagation). They skip the type/range validation of
-- get/set/is_empty; callers must pass a flat 81-cell board and in-range
-- 0..8 coordinates. Mirror the validated API for in-range inputs.
function board.raw_get(b, r, c)
    return b[r * 9 + c + 1]
end

function board.raw_is_empty(b, r, c)
    return b[r * 9 + c + 1] == 0
end

function board.raw_set(b, r, c, value)
    b[r * 9 + c + 1] = value
    return true
end

function board.is_empty(b, r, c)
    local value, err = board.get(b, r, c)
    if err then
        return nil, err
    end
    return value == 0
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

function board.solution_preserves_givens(puzzle, solution)
    if type(puzzle) ~= "table" or type(solution) ~= "table" then
        return false
    end
    for i = 1, 81 do
        local given = puzzle[i]
        if given ~= 0 and solution[i] ~= given then
            return false
        end
    end
    return true
end

return board
