local solve_path = {}

-- Step metrics describe direct effects of a step, not all cells in its pattern.
-- Elimination steps remove one candidate value; placement steps count all peer
-- candidates removed and peer cells directly affected by that placement.

local function deep_copy(value, seen)
    if type(value) ~= "table" then
        return value
    end
    seen = seen or {}
    if seen[value] then
        return seen[value]
    end

    local copy = {}
    seen[value] = copy
    for key, nested in pairs(value) do
        copy[deep_copy(key, seen)] = deep_copy(nested, seen)
    end
    return copy
end

function solve_path.new()
    return { steps = {} }
end

function solve_path.push(path, step)
    step.step_number = #path.steps
    path.steps[#path.steps + 1] = step
end

function solve_path.placement_step(row, col, value, flags, pattern)
    return {
        type = "place",
        row = row,
        col = col,
        value = value,
        flags = flags or 0,
        pattern = pattern,
        candidates_eliminated = 0,
        related_cell_count = 0,
        difficulty_point = 0,
    }
end

function solve_path.elimination_step(row, col, value, flags, pattern)
    return {
        type = "elim",
        row = row,
        col = col,
        value = value,
        flags = flags or 0,
        pattern = pattern,
        candidates_eliminated = 0,
        related_cell_count = 0,
        difficulty_point = 0,
    }
end

function solve_path.snapshot(path)
    local steps = {}
    local seen = {}
    for i = 1, #path.steps do
        steps[i] = deep_copy(path.steps[i], seen)
    end
    return { steps = steps }
end

return solve_path
