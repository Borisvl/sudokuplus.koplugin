local bit = require("bit")
local solve_path = {}
local technique_flags = require("sudokuplus.core.techniques.flags")

local DIFFICULTY_RANK = {
    beginner = 0,
    easy = 1,
    medium = 2,
    hard = 3,
    master = 4,
    expert = 5,
}

local ORDERED_TECHNIQUES = technique_flags.TECHNIQUES

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

function solve_path.classify(path, options)
    local clue_count = nil
    if type(options) == "number" then
        clue_count = options
    elseif type(options) == "table" and type(options.clues) == "number" then
        clue_count = options.clues
    end

    local result = {
        difficulty = "easy",
        requires_guessing = false,
        hardest_flags = 0,
        hardest_step_number = nil,
        non_single_count = 0,
        score = 0,
    }
    local hardest_rank = -1
    local has_hardest_step = false
    local peak_difficulty = nil
    local used_flags = 0

    for index, step in ipairs((path or {}).steps or {}) do
        local step_flags = step.flags or 0
        if step.type == "place" and step_flags == 0 then
            result.requires_guessing = true
        end

        if step_flags ~= 0 then
            used_flags = bit.bor(used_flags, step_flags)
            local step_score = technique_flags.score(step_flags)
            result.score = result.score + step_score

            if step_flags ~= technique_flags.NAKED_SINGLES and step_flags ~= technique_flags.HIDDEN_SINGLES then
                result.non_single_count = result.non_single_count + 1
            end

            local difficulty = technique_flags.difficulty(step_flags)
            local rank = DIFFICULTY_RANK[difficulty] or 0
            if rank > hardest_rank or (rank == hardest_rank and not has_hardest_step) then
                hardest_rank = rank
                peak_difficulty = difficulty
                result.hardest_flags = step_flags
                result.hardest_step_number = step.step_number or index - 1
                has_hardest_step = true
            end
        end
    end

    local techniques = {}
    for _, entry in ipairs(ORDERED_TECHNIQUES) do
        if bit.band(used_flags, entry.flag) ~= 0 then
            techniques[#techniques + 1] = entry.id
        end
    end
    result.techniques = techniques

    if peak_difficulty == nil or peak_difficulty == "easy" then
        if clue_count and clue_count >= 38 then
            result.difficulty = "beginner"
        else
            result.difficulty = "easy"
        end
    else
        result.difficulty = peak_difficulty
    end

    return result
end

return solve_path
