local bit = require("bit")
local board = require("sudokuplus.core.board")
local prng = require("sudokuplus.core.prng")
local solve_path = require("sudokuplus.core.solve_path")
local solver = require("sudokuplus.core.solver")
local util = require("sudokuplus.core.util")
local flags = require("sudokuplus.core.techniques.flags")

local generator = {}

local BOARD_SIZE = 9
local CELL_COUNT = BOARD_SIZE * BOARD_SIZE
local DEFAULT_CLUES = 30
local DEFAULT_SYMMETRY = "none"
local DEFAULT_MAX_ATTEMPTS = 100
local ALL_TECHNIQUES = flags.ALL

-- P4: per-solve node budget. Uniqueness checks and difficulty classification
-- can hit pathological search trees (a hard puzzle classified with only
-- easy+medium techniques must exhaust the tree to prove uniqueness). Normal
-- generation tops out around ~13k nodes per call; the budget caps the rare
-- pathological boards at a fixed cost instead of stalling the UI for seconds.
-- A capped check is treated as non-unique (dig restores the clue) and a
-- capped classification as a failed attempt, so generation never fails hard
-- because of one unlucky board.
local SEARCH_BUDGET = 50000

-- P2: a difficulty-targeted generation classifies with only the techniques up
-- to the requested tier. A medium request never runs AIC or the fish/wing
-- detectors: puzzles that need them classify as "requires guessing" and are
-- rejected just the same, but far more cheaply. Easy/medium/hard verdicts
-- are identical to an all-techniques solve (the propagator runs the tiers in
-- fixed order, so a puzzle that solves within the tier follows the same path).
local TIER_TECHNIQUES = flags.CUMULATIVE_TIER_FLAGS

local DIFFICULTY_RANGES = {
    beginner = { min = 38, max = 44 },
    easy = { min = 30, max = 36 },
    medium = { min = 26, max = 31 },
    hard = { min = 24, max = 28 },
    master = { min = 22, max = 26 },
    expert = { min = 17, max = 22 },
    custom_master = { min = 22, max = 26 },
    custom_expert = { min = 21, max = 26 },
}

-- Rank used to pick the closest usable fallback when an exact difficulty
-- match cannot be found within max_attempts.
local DIFFICULTY_ORDER = {
    beginner = 1,
    easy = 2,
    medium = 3,
    hard = 4,
    master = 5,
    expert = 6,
}

-- P3: clue-target sampling weights, aligned with DIFFICULTY_RANGES (weights[1]
-- is the low end of the range). Empirical calibration balances generation speed
-- with hitting the target technique tier.
local DIFFICULTY_WEIGHTS = {
    medium = { 100, 80, 60, 50, 40, 30 },
    hard = { 100, 80, 60, 50, 30 },
    master = { 100, 80, 60, 40, 30 },
    custom_master = { 100, 80, 60, 40, 30 },
    custom_expert = { 100, 80, 60, 40, 30, 20 },
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

    local target_tier = options.target_tier
    local required_techniques = options.required_techniques
    local allowed_techniques = options.allowed_techniques

    if difficulty == "custom" then
        local valid_tier, valid_techs =
            util.validate_custom_tier_and_techniques(target_tier, required_techniques, "custom difficulty requires ")
        if not valid_tier then
            return nil, valid_techs
        end
        target_tier = valid_tier
        required_techniques = valid_techs

        local required_flags = 0
        for _, id in ipairs(required_techniques) do
            local t = flags.TECHNIQUE_BY_ID[id]
            required_flags = bit.bor(required_flags, t.flag)
        end

        local floor_mask = 0
        if target_tier == "medium" then
            floor_mask = flags.CUMULATIVE_TIER_FLAGS.easy
        elseif target_tier == "hard" then
            floor_mask = flags.CUMULATIVE_TIER_FLAGS.medium
        elseif target_tier == "master" then
            floor_mask = flags.CUMULATIVE_TIER_FLAGS.hard
        elseif target_tier == "expert" then
            floor_mask = flags.CUMULATIVE_TIER_FLAGS.master
        end
        allowed_techniques = bit.bor(floor_mask, required_flags)
    else
        if target_tier ~= nil or required_techniques ~= nil or allowed_techniques ~= nil then
            return nil, "non-custom difficulty must not specify target_tier, required_techniques, or allowed_techniques"
        end
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
        target_tier = target_tier,
        required_techniques = required_techniques,
        allowed_techniques = allowed_techniques,
        max_attempts = max_attempts,
        rng = rng,
        seed = seed,
    }
end

local function new_solver(puzzle, rng, techniques)
    -- solver instances clone their RNG, so derive each search seed from the generator RNG.
    return solver.new(puzzle, {
        rng = prng.new(rng:next()),
        techniques = techniques,
        search_budget = SEARCH_BUDGET,
    })
end

local function sample_solution(rng)
    local search_solver, err = new_solver(board.new(), rng, 0)
    if not search_solver then
        return nil, err
    end

    local solution = search_solver:solve_any()
    if not solution then
        -- An empty board is always solvable, so a missing first solution can
        -- only mean the search hit the node budget. Treat it as a retryable
        -- failed attempt instead of a hard error (P4).
        return nil
    end
    return solution.board
end

-- Returns true when the puzzle is proven uniquely solvable, false when it is
-- proven non-unique, or nil when the search hit the node budget and the
-- verdict is inconclusive. `err` is only set for a hard solver failure.
local function is_unique(puzzle, rng)
    local uniqueness_solver, err = new_solver(puzzle, rng, 0)
    if not uniqueness_solver then
        return nil, err
    end
    -- P1: count_solutions(2) only counts, it never materializes solution
    -- boards or solve paths (solve_until(2) does both). The dig runs this
    -- oracle after every clue removal, so the savings are direct.
    local count = uniqueness_solver:count_solutions(2)
    if uniqueness_solver.search_capped then
        -- P4: inconclusive within budget. The dig restores the removed clue
        -- (the safe side of a rejected removal); the final confirmation below
        -- accepts (the dig invariant already guarantees uniqueness).
        return nil
    end
    return count == 1
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
                local unique, unique_err = is_unique(puzzle, options.rng)
                if unique_err then
                    return nil, unique_err
                elseif unique then
                    clues = clues - #removed
                else
                    -- Not unique, or inconclusive under the budget: both are
                    -- "do not accept this removal"; restore the group.
                    for _, cell in ipairs(removed) do
                        puzzle[cell.index] = cell.value
                    end
                end
            end
        end
    end

    -- Final confirmation. unique == nil means the check capped, which is
    -- accepted: every accepted removal above preserved uniqueness, so the
    -- board is unique by construction and the proof is just belt-and-braces.
    local unique, unique_err = is_unique(puzzle, options.rng)
    if unique_err then
        return nil, unique_err
    end
    if unique == false then
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
-- `difficulty` selects the classification technique tier (P2); nil means
-- the full technique set (used when the actual difficulty is unknown).
-- Note: Because the propagator runs techniques in strict difficulty order
-- (singles -> medium -> hard -> master -> expert), an ALL-techniques solve
-- of a tier-solvable puzzle produces the exact same deduction path and technique
-- set as a tier-restricted solve.
local function classify_puzzle(puzzle, options, difficulty, custom_techniques_mask)
    local techniques = ALL_TECHNIQUES
    if custom_techniques_mask ~= nil then
        techniques = custom_techniques_mask
    elseif difficulty ~= nil then
        techniques = TIER_TECHNIQUES[difficulty]
    end

    local human_solver, err = new_solver(puzzle, options.rng, techniques)
    if not human_solver then
        return nil, err
    end

    local solutions = human_solver:solve_until(2)
    if human_solver.search_capped then
        -- P4: the search hit the node budget. Treat as a failed attempt (the
        -- retry loop skips it), never as a difficulty verdict.
        return nil
    end
    if #solutions ~= 1 then
        return nil
    end

    local clues = board.count_clues(puzzle)
    return solve_path.classify(solutions[1].solve_path, { clues = clues })
end

local function meets_density_criteria(classification, target_difficulty)
    if target_difficulty == "medium" or target_difficulty == "hard" or target_difficulty == "master" then
        return (classification.non_single_count or 0) >= 2
    end
    return true
end

local function contains_any_required(classification_techniques, required_techniques)
    local req_set = {}
    for _, id in ipairs(required_techniques or {}) do
        req_set[id] = true
    end
    for _, id in ipairs(classification_techniques or {}) do
        if req_set[id] then
            return true
        end
    end
    return false
end

local function game_payload(payload, classification, options)
    return {
        board = payload.board,
        solution = payload.solution,
        difficulty = options.difficulty == "custom" and "custom" or classification.difficulty,
        custom_tier = options.target_tier,
        custom_techniques = options.required_techniques,
        allowed_techniques = options.allowed_techniques,
        clues = board.count_clues(payload.board),
        seed = options.seed,
        techniques = classification.techniques,
    }
end

-- Picks the clue-count target for one attempt: weighted for difficulties with
-- a measured yield curve (P3), uniform otherwise.
local function pick_target_clues(options, range, weights_key)
    local key = weights_key or options.difficulty
    local weights = DIFFICULTY_WEIGHTS[key]
    if not weights then
        return range.min + options.rng:int(range.max - range.min + 1) - 1
    end

    local total = 0
    for _, weight in ipairs(weights) do
        total = total + weight
    end
    local roll = options.rng:int(total)
    for index, weight in ipairs(weights) do
        roll = roll - weight
        if roll <= 0 then
            return range.min + index - 1
        end
    end
    return range.max
end

-- Runs one difficulty-targeted attempt: generates to a random clue count in
-- `range`, then classifies. Returns (payload, nil, classification) for a
-- usable (uniquely solvable) puzzle, nil for a failed attempt, or
-- (nil, err) for a hard generation error.
local function attempt_puzzle(options, range)
    local target = pick_target_clues(options, range)
    local payload, generate_err = generate_single(options, target)
    if not payload then
        return nil, generate_err
    end

    local classification, classify_err = classify_puzzle(payload.board, options, options.difficulty)
    if classify_err then
        return nil, classify_err
    end
    if not classification then
        return nil
    end

    return payload, nil, classification
end

local function attempt_custom_puzzle(options, range, weights_key)
    local target = pick_target_clues(options, range, weights_key)
    local payload, generate_err = generate_single(options, target)
    if not payload then
        return nil, generate_err
    end

    -- Classify strictly using the allowed techniques mask (lower tiers | selected techniques).
    -- This guarantees the puzzle is 100% solvable without guessing using only the allowed
    -- techniques and prevents play-time hints from dead-ending on unselected strategies.
    local classification, classify_err = classify_puzzle(payload.board, options, nil, options.allowed_techniques)
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

    if normalized.difficulty == "custom" then
        local range_key = "custom_" .. normalized.target_tier
        local range = DIFFICULTY_RANGES[range_key] or DIFFICULTY_RANGES[normalized.target_tier]
        local weights_key = DIFFICULTY_WEIGHTS[range_key] and range_key or normalized.target_tier
        for _ = 1, normalized.max_attempts do
            local payload, attempt_err, classification = attempt_custom_puzzle(normalized, range, weights_key)
            if attempt_err then
                return nil, attempt_err
            end
            if
                payload
                and not classification.requires_guessing
                and contains_any_required(classification.techniques, normalized.required_techniques)
            then
                return payload.board
            end
        end
        return nil, "failed to generate a custom " .. normalized.target_tier .. " puzzle"
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
        if
            payload
            and not classification.requires_guessing
            and classification.difficulty == normalized.difficulty
            and meets_density_criteria(classification, normalized.difficulty)
        then
            return payload.board
        end
    end

    return nil, "failed to generate a " .. normalized.difficulty .. " puzzle"
end

function generator.generate_game(options)
    local normalized, err = validate_options(options)
    if not normalized then
        return nil, err
    end

    if normalized.difficulty == "custom" then
        local range_key = "custom_" .. normalized.target_tier
        local range = DIFFICULTY_RANGES[range_key] or DIFFICULTY_RANGES[normalized.target_tier]
        local weights_key = DIFFICULTY_WEIGHTS[range_key] and range_key or normalized.target_tier
        for _ = 1, normalized.max_attempts do
            local payload, attempt_err, classification = attempt_custom_puzzle(normalized, range, weights_key)
            if attempt_err then
                return nil, attempt_err
            end
            if
                payload
                and not classification.requires_guessing
                and contains_any_required(classification.techniques, normalized.required_techniques)
            then
                return game_payload(payload, classification, normalized)
            end
        end
        return nil, "failed to generate a custom " .. normalized.target_tier .. " game with the requested techniques"
    end

    if not normalized.difficulty then
        local last_err
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
                last_err = generate_err
            end
        end
        return nil, last_err or "failed to generate a non-guessing game"
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
            if
                classification.difficulty == normalized.difficulty
                and meets_density_criteria(classification, normalized.difficulty)
            then
                return game_payload(payload, classification, normalized)
            end
            local rank_diff = math.abs(requested_rank - DIFFICULTY_ORDER[classification.difficulty])
            local is_dense = meets_density_criteria(classification, classification.difficulty)
            -- Prioritize density-passing candidates over non-dense candidates:
            -- A density-passing adjacent tier candidate (score 1) beats an exact-tier candidate
            -- that failed density (score 10). If all attempts fail density, the exact match wins (10 vs 11).
            local penalty = is_dense and 0 or 10
            local distance = rank_diff + penalty
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
    return nil, "failed to generate a " .. normalized.difficulty .. " game"
end

return generator
