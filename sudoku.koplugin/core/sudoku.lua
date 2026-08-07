local board = require("core.board")
local generator = require("core.generator")
local solver = require("core.solver")

local sudoku = {}

function sudoku.from_string(s)
    return board.from_string(s)
end

function sudoku.solve_any(puzzle, opts)
    local b, err = sudoku.from_string(puzzle)
    if not b then
        return nil, err
    end
    local s, s_err = solver.new(b, opts)
    if not s then
        return nil, s_err
    end
    return s:solve_any()
end

function sudoku.solve_all(puzzle, opts, limit)
    local b, err = sudoku.from_string(puzzle)
    if not b then
        return nil, err
    end
    local s, s_err = solver.new(b, opts)
    if not s then
        return nil, s_err
    end
    return s:solve_all(limit)
end

function sudoku.solutions_count(puzzle, opts, limit)
    local b, err = sudoku.from_string(puzzle)
    if not b then
        return nil, err
    end
    local s, s_err = solver.new(b, opts)
    if not s then
        return nil, s_err
    end
    local count, count_err = s:count_solutions(limit)
    if count == nil then
        return nil, count_err
    end
    return count
end

function sudoku.is_solved(puzzle)
    local b, err = sudoku.from_string(puzzle)
    if not b then
        return false, err
    end
    local s, solver_err = solver.new(b)
    if not s then
        return false, solver_err
    end
    return s:is_solved()
end

function sudoku.generate(opts)
    return generator.generate(opts)
end

return sudoku
