local bit = require("bit")
local board = require("core.board")
local prng = require("core.prng")
local solve_path = require("core.solve_path")
local solver = require("core.solver")
local util = require("core.util")
local flags = require("core.techniques.flags")

local generator = {}

local BOARD_SIZE = 9
local CELL_COUNT = BOARD_SIZE * BOARD_SIZE
local DEFAULT_CLUES = 30
local DEFAULT_SYMMETRY = "none"
local DEFAULT_MAX_ATTEMPTS = 100
local ALL_TECHNIQUES = bit.bor(flags.EASY, bit.bor(flags.MEDIUM, bit.bor(flags.HARD, flags.EXPERT)))

local DIFFICULTY_RANGES = {
    easy = { min = 34, max = 42 },
    -- 25..31 is where medium classifications actually concentrate: measured
    -- 2026-08-09, 28..34 (the old rustoku range) classified ~90% "easy" and
    -- only ~2-6% "medium", forcing dozens of retries (and occasional
    -- exhaustion); 25..31 yields roughly 3-13% medium per attempt.
    medium = { min = 25, max = 31 },
    hard = { min = 22, max = 28 },
    expert = { min = 17, max = 22 },
}

-- Rank used to pick the closest usable fallback when an exact difficulty
-- match cannot be found within max_attempts.
local DIFFICULTY_ORDER = {
    easy = 1,
    medium = 2,
    hard = 3,
    expert = 4,
}

local SYMMETRIES = {
    none = true,
    rotational180 = true,
    rotational90 = true,
    mirrorvertical = true,
    mirrorhorizontal = true,
    mirrordiagonal = true,
}

local function cell_index(row, col)
    return row * BOARD_SIZE + col + 1
end

local function symmetry_partners(symmetry, row, col)
    local cells = {}
    local seen = {}

    local function add(partner_row, partner_col)
        local index = cell_index(partner_row, partner_col)
        if not seen[index] then
            seen[index] = true
            cells[#cells + 1] = { partner_row, partner_col }
        end
    end

    add(row, col)
    if symmetry == "rotational180" then
        add(8 - row, 8 - col)
    elseif symmetry == "rotational90" then
        add(col, 8 - row)
        add(8 - row, 8 - col)
        add(8 - col, row)
    elseif symmetry == "mirrorvertical" then
        add(row, 8 - col)
    elseif symmetry == "mirrorhorizontal" then
        add(8 - row, col)
    elseif symmetry == "mirrordiagonal" then
        add(col, row)
    end

    return cells
end

local function symmetry_groups(symmetry)
    local visited = {}
    local groups = {}

    for row = 0, 8 do
        for col = 0, 8 do
            local index = cell_index(row, col)
            if not visited[index] then
                local group = symmetry_partners(symmetry, row, col)
                for _, cell in ipairs(group) do
                    visited[cell_index(cell[1], cell[2])] = true
                end
                groups[#groups + 1] = group
            end
        end
    end

    return groups
end

local function validate_integer(value, name, minimum, maximum)
    if type(value) ~= "number" or value % 1 ~= 0 or value < minimum or value > maximum then
        return nil, name .. " must be an integer in the range " .. minimum .. ".." .. maximum
    end
    return value
end

local function validate_options(options)
    if options ~= nil and type(options) ~= "table" then
        return nil, "options must be a table"
    end
    options = options or {}

    local clues_value = options.clues
    if clues_value == nil then
        clues_value = DEFAULT_CLUES
    end
    local clues, clues_err = validate_integer(clues_value, "clues", 17, CELL_COUNT)
    if not clues then
        return nil, clues_err
    end

    local symmetry = options.symmetry
    if symmetry == nil then
        symmetry = DEFAULT_SYMMETRY
    end
    if not SYMMETRIES[symmetry] then
        return nil, "unknown symmetry: " .. tostring(symmetry)
    end

    local difficulty = options.difficulty
    if difficulty ~= nil and not util.is_difficulty(difficulty) then
        return nil, "unknown difficulty: " .. tostring(difficulty)
    end

    local max_attempts_value = options.max_attempts
    if max_attempts_value == nil then
        max_attempts_value = DEFAULT_MAX_ATTEMPTS
    end
    local max_attempts, attempts_err = validate_integer(max_attempts_value, "max_attempts", 1, math.huge)
    if not max_attempts then
        return nil, attempts_err
    end

    local rng = options.rng
    if rng == nil then
        rng = prng.new()
    end
    if
        type(rng) ~= "table"
        or type(rng.next) ~= "function"
        or type(rng.int) ~= "function"
        or type(rng.shuffle) ~= "function"
    then
        return nil, "rng must provide next, int, and shuffle methods"
    end

    -- The generation seed: recorded so the exact puzzle can be reproduced.
    -- Prefer the explicit option; otherwise snapshot the rng's initial state
    -- (a fresh prng.new(seed) stores the normalized seed in state, so
    -- prng.new(seed) with the snapshot reproduces the puzzle).
    local seed = options.seed
    if seed == nil and type(rng.state) == "number" then
        seed = rng.state
    end
    if seed ~= nil and (type(seed) ~= "number" or seed % 1 ~= 0) then
        return nil, "seed must be an integer"
    end

    return {
        clues = clues,
        symmetry = symmetry,
        difficulty = difficulty,
        max_attempts = max_attempts,
        rng = rng,
        seed = seed,
    }
end

local function new_solver(puzzle, rng, techniques)
    -- solver instances clone their RNG, so derive each search seed from the generator RNG.
    return solver.new(puzzle, { rng = prng.new(rng:next()), techniques = techniques })
end

local function sample_solution(rng)
    local search_solver, err = new_solver(board.new(), rng, 0)
    if not search_solver then
        return nil, err
    end

    local solution = search_solver:solve_any()
    if not solution then
        return nil, "failed to sample a solved board"
    end
    return solution.board
end

local function is_unique(puzzle, rng)
    local uniqueness_solver, err = new_solver(puzzle, rng, 0)
    if not uniqueness_solver then
        return nil, err
    end
    return #uniqueness_solver:solve_until(2) == 1
end

local function remove_clues(solution, options, target_clues)
    local puzzle = board.clone(solution)
    local groups = symmetry_groups(options.symmetry)
    options.rng:shuffle(groups)

    local clues = CELL_COUNT
    for _, group in ipairs(groups) do
        if clues <= target_clues then
            break
        end

        if #group <= clues - target_clues then
            local removed = {}
            for _, cell in ipairs(group) do
                local index = cell_index(cell[1], cell[2])
                if puzzle[index] ~= 0 then
                    removed[#removed + 1] = { index = index, value = puzzle[index] }
                    puzzle[index] = 0
                end
            end

            if #removed > 0 then
                local unique, err = is_unique(puzzle, options.rng)
                if unique == nil then
                    return nil, err
                elseif unique then
                    clues = clues - #removed
                else
                    for _, cell in ipairs(removed) do
                        puzzle[cell.index] = cell.value
                    end
                end
            end
        end
    end

    local unique, err = is_unique(puzzle, options.rng)
    if unique == nil then
        return nil, err
    end
    if not unique then
        return nil, "generated puzzle is not uniquely solvable"
    end

    return puzzle
end

local function generate_single(options, target_clues)
    local solution, err = sample_solution(options.rng)
    if not solution then
        return nil, err
    end
    local puzzle, remove_err = remove_clues(solution, options, target_clues)
    if not puzzle then
        return nil, remove_err
    end
    return { board = puzzle, solution = solution }
end

-- Returns the classification when the puzzle is uniquely solvable, nil
-- without an error when it is not (a failed attempt, not a failure).
local function classify_puzzle(puzzle, options)
    local human_solver, err = new_solver(puzzle, options.rng, ALL_TECHNIQUES)
    if not human_solver then
        return nil, err
    end

    local solutions = human_solver:solve_until(2)
    if #solutions ~= 1 then
        return nil
    end

    return solve_path.classify(solutions[1].solve_path)
end

local function game_payload(payload, classification, options)
    return {
        board = payload.board,
        solution = payload.solution,
        difficulty = classification.difficulty,
        clues = board.count_clues(payload.board),
        seed = options.seed,
    }
end

-- Runs one difficulty-targeted attempt: generates to a random clue count in
-- `range`, then classifies. Returns (payload, nil, classification) for a
-- usable (uniquely solvable) puzzle, nil for a failed attempt, or
-- (nil, err) for a hard generation error.
local function attempt_puzzle(options, range)
    local target = range.min + options.rng:int(range.max - range.min + 1) - 1
    local payload, generate_err = generate_single(options, target)
    if not payload then
        return nil, generate_err
    end

    local classification, classify_err = classify_puzzle(payload.board, options)
    if classify_err then
        return nil, classify_err
    end
    if not classification then
        return nil
    end

    return payload, nil, classification
end

function generator.generate(options)
    local normalized, err = validate_options(options)
    if not normalized then
        return nil, err
    end

    if not normalized.difficulty then
        local payload, generate_err = generate_single(normalized, normalized.clues)
        if not payload then
            return nil, generate_err
        end
        return payload.board
    end

    -- Strict API: a requested difficulty is an exact-match contract. The
    -- game-facing generate_game adds the best-effort fallback below; here
    -- exhaustion is still an error (the caller asked for a specific board).
    local range = DIFFICULTY_RANGES[normalized.difficulty]
    for _ = 1, normalized.max_attempts do
        local payload, attempt_err, classification = attempt_puzzle(normalized, range)
        if attempt_err then
            return nil, attempt_err
        end
        if payload and not classification.requires_guessing and classification.difficulty == normalized.difficulty then
            return payload.board
        end
    end

    return nil, err or ("failed to generate a " .. normalized.difficulty .. " puzzle")
end

function generator.generate_game(options)
    local normalized, err = validate_options(options)
    if not normalized then
        return nil, err
    end

    if not normalized.difficulty then
        for _ = 1, normalized.max_attempts do
            local payload, generate_err = generate_single(normalized, normalized.clues)
            if payload then
                local classification, classify_err = classify_puzzle(payload.board, normalized)
                if classify_err then
                    return nil, classify_err
                elseif classification and not classification.requires_guessing then
                    return game_payload(payload, classification, normalized)
                end
            elseif generate_err then
                err = generate_err
            end
        end
        return nil, err or "failed to generate a non-guessing game"
    end

    -- Best-effort difficulty targeting: prefer an exact match, but never
    -- hard-fail — if max_attempts is exhausted, return the closest usable
    -- (unique, no-guessing) puzzle with its ACTUAL difficulty so the game
    -- labels it correctly.
    local range = DIFFICULTY_RANGES[normalized.difficulty]
    local requested_rank = DIFFICULTY_ORDER[normalized.difficulty]
    local best
    for _ = 1, normalized.max_attempts do
        local payload, attempt_err, classification = attempt_puzzle(normalized, range)
        if attempt_err then
            return nil, attempt_err
        end
        if payload and not classification.requires_guessing then
            if classification.difficulty == normalized.difficulty then
                return game_payload(payload, classification, normalized)
            end
            local distance = math.abs(requested_rank - DIFFICULTY_ORDER[classification.difficulty])
            if not best or distance < best.distance then
                best = {
                    payload = payload,
                    classification = classification,
                    distance = distance,
                }
            end
        end
    end

    if best then
        return game_payload(best.payload, best.classification, normalized)
    end
    return nil, err or ("failed to generate a " .. normalized.difficulty .. " game")
end

return generator
