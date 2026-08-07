local solve_path = {}
local technique_flags = require("core.techniques.flags")

local DIFFICULTY_RANK = {
    easy = 0,
    medium = 1,
    hard = 2,
    expert = 3,
}

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

function solve_path.classify(path)
    local result = {
        difficulty = "easy",
        requires_guessing = false,
        hardest_flags = 0,
        hardest_step_number = nil,
    }
    local hardest_rank = DIFFICULTY_RANK.easy

    local has_hardest_step = false
    for index, step in ipairs((path or {}).steps or {}) do
        local step_flags = step.flags or 0
        if step.type == "place" and step_flags == 0 then
            result.requires_guessing = true
        end

        if step_flags ~= 0 then
            local difficulty = technique_flags.difficulty(step_flags)
            local rank = DIFFICULTY_RANK[difficulty]
            if rank > hardest_rank or (rank == hardest_rank and not has_hardest_step) then
                hardest_rank = rank
                result.difficulty = difficulty
                result.hardest_flags = step_flags
                result.hardest_step_number = step.step_number or index - 1
                has_hardest_step = true
            end
        end
    end

    return result
end

return solve_path
