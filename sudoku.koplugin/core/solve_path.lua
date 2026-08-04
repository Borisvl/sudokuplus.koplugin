local solve_path = {}

function solve_path.new()
    return { steps = {} }
end

function solve_path.push(path, step)
    step.step_number = #path.steps
    path.steps[#path.steps + 1] = step
end

function solve_path.placement_step(row, col, value, flags)
    return {
        type = "place",
        row = row,
        col = col,
        value = value,
        flags = flags or 0,
        candidates_eliminated = 0,
        related_cell_count = 0,
        difficulty_point = 0,
    }
end

function solve_path.elimination_step(row, col, value, flags)
    return {
        type = "elim",
        row = row,
        col = col,
        value = value,
        flags = flags or 0,
        candidates_eliminated = 0,
        related_cell_count = 0,
        difficulty_point = 0,
    }
end

function solve_path.snapshot(path)
    local steps = {}
    for i = 1, #path.steps do
        steps[i] = path.steps[i]
    end
    return { steps = steps }
end

return solve_path
