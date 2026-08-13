local bit = require("bit")
local board = require("core.board")
local candidates = require("core.candidates")
local masks = require("core.masks")
local solver = require("core.solver")
local solve_path = require("core.solve_path")
local flags = require("core.techniques.flags")

local hints = {}

local ALL_TECHNIQUES = flags.ALL
local MIN_INT32 = -2147483648
local UINT32_LIMIT = 4294967296
local FULL_CANDIDATE_MASK = 0x1FF

local TECHNIQUES = {
    { id = "naked_singles", name = "Naked Singles", flag = flags.NAKED_SINGLES },
    { id = "hidden_singles", name = "Hidden Singles", flag = flags.HIDDEN_SINGLES },
    { id = "naked_pairs", name = "Naked Pairs", flag = flags.NAKED_PAIRS },
    { id = "hidden_pairs", name = "Hidden Pairs", flag = flags.HIDDEN_PAIRS },
    { id = "locked_candidates", name = "Locked Candidates", flag = flags.LOCKED_CANDIDATES },
    { id = "naked_triples", name = "Naked Triples", flag = flags.NAKED_TRIPLES },
    { id = "hidden_triples", name = "Hidden Triples", flag = flags.HIDDEN_TRIPLES },
    { id = "x_wing", name = "X-Wing", flag = flags.X_WING },
    { id = "naked_quads", name = "Naked Quads", flag = flags.NAKED_QUADS },
    { id = "hidden_quads", name = "Hidden Quads", flag = flags.HIDDEN_QUADS },
    { id = "swordfish", name = "Swordfish", flag = flags.SWORDFISH },
    { id = "jellyfish", name = "Jellyfish", flag = flags.JELLYFISH },
    { id = "skyscraper", name = "Skyscraper", flag = flags.SKYSCRAPER },
    { id = "w_wing", name = "W-Wing", flag = flags.W_WING },
    { id = "xy_wing", name = "XY-Wing", flag = flags.XY_WING },
    { id = "xyz_wing", name = "XYZ-Wing", flag = flags.XYZ_WING },
    { id = "aic", name = "Alternating Inference Chain", flag = flags.ALTERNATING_INFERENCE_CHAIN },
}

local TECHNIQUE_BY_FLAG = {}
for _, technique in ipairs(TECHNIQUES) do
    TECHNIQUE_BY_FLAG[technique.flag] = technique
end

-- Public read-only access to the supported technique list (id, name, flag).
function hints.techniques()
    local copy = {}
    for i, technique in ipairs(TECHNIQUES) do
        copy[i] = {
            id = technique.id,
            name = technique.name,
            flag = technique.flag,
        }
    end
    return copy
end

local function validate_optional_limit(value, name)
    if value == nil then
        return nil
    end
    if type(value) ~= "number" or value % 1 ~= 0 or value < 0 then
        return nil, name .. " must be a non-negative integer"
    end
    return value
end

local function validate_options(options)
    if options ~= nil and type(options) ~= "table" then
        return nil, "options must be a table"
    end
    options = options or {}

    if options.level ~= nil then
        return nil, "hint reveal level belongs to the UI"
    end

    local techniques = options.techniques
    if techniques == nil then
        techniques = ALL_TECHNIQUES
    elseif
        type(techniques) ~= "number"
        or techniques % 1 ~= 0
        or techniques < MIN_INT32
        or techniques >= UINT32_LIMIT
    then
        return nil, "techniques must be a signed 32-bit integer bitmask"
    end

    local max_depth, depth_err = validate_optional_limit(options.aic_max_depth, "aic_max_depth")
    if depth_err then
        return nil, depth_err
    end
    local max_expansions, expansions_err = validate_optional_limit(options.aic_max_expansions, "aic_max_expansions")
    if expansions_err then
        return nil, expansions_err
    end

    return {
        techniques = techniques,
        aic_max_depth = max_depth,
        aic_max_expansions = max_expansions,
    }
end

local function validate_revision(revision)
    if revision == nil then
        return 0
    end
    if type(revision) ~= "number" or revision % 1 ~= 0 or revision < 0 then
        return nil, "revision must be a non-negative integer"
    end
    return revision
end

local function copy_cells(cells)
    local result = {}
    local seen = {}
    for _, cell in ipairs(cells or {}) do
        local row, col = cell[1], cell[2]
        local key = row * 9 + col
        if not seen[key] then
            seen[key] = true
            result[#result + 1] = { row, col }
        end
    end
    return result
end

local function project_pattern(step, technique)
    local source = step.pattern or {}
    local cells = source.cells
    if not cells then
        cells = {}
        for _, node in ipairs(source.nodes or {}) do
            cells[#cells + 1] = { node.r, node.c }
        end
    end
    return {
        kind = source.kind or technique.id,
        cells = copy_cells(cells),
    }
end

local function hint_id(step, technique)
    local parts = {
        technique.id,
        step.type,
        tostring(step.row),
        tostring(step.col),
        tostring(step.value),
        step.pattern and step.pattern.kind or technique.id,
    }
    return table.concat(parts, ":")
end

local function validate_solution(solution, b)
    if solution == nil then
        return true
    end
    local solution_masks, solution_err = solver.validate(solution)
    if not solution_masks then
        return nil, "invalid solution: " .. solution_err
    end
    if board.count_clues(solution) ~= 81 then
        return nil, "solution must contain 81 values"
    end
    for r = 0, 8 do
        for c = 0, 8 do
            local given = board.get(b, r, c)
            if given ~= 0 and board.get(solution, r, c) ~= given then
                return nil, "solution does not preserve the puzzle givens"
            end
        end
    end
    return true
end

local function validate_notes(state, constraint_masks)
    local notes = state.notes
    if type(notes) ~= "table" then
        return nil, "state.notes must be a 9x9 candidate mask table"
    end
    local errors = {}
    for row = 1, 9 do
        if type(notes[row]) ~= "table" then
            return nil, "state.notes must be a 9x9 candidate mask table"
        end
        for col = 1, 9 do
            local mask = notes[row][col]
            if type(mask) ~= "number" or mask % 1 ~= 0 or mask < 0 or mask > FULL_CANDIDATE_MASK then
                return nil, "note masks must be integers in the range 0..511"
            end
        end
    end
    for key in pairs(notes) do
        if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > 9 then
            return nil, "state.notes must be a 9x9 candidate mask table"
        end
    end

    local solution = state.solution
    for r = 0, 8 do
        for c = 0, 8 do
            local mask = notes[r + 1][c + 1]
            if not board.is_empty(state.board, r, c) then
                if mask ~= 0 then
                    errors[#errors + 1] = {
                        reason = "given_cell_has_notes",
                        row = r,
                        col = c,
                    }
                end
            else
                local legal = masks.compute_candidates_mask_for_cell(constraint_masks, r, c)
                local illegal = bit.band(mask, bit.bnot(legal))
                if illegal ~= 0 then
                    errors[#errors + 1] = {
                        reason = "illegal_candidate",
                        row = r,
                        col = c,
                        values = candidates.from_mask(illegal),
                    }
                end
                -- An empty mask is legitimate state, not an error: the game
                -- layer substitutes board-legal candidates for untouched
                -- cells, and a user-cleared cell is ground truth. Deduction
                -- simply cannot use the cell.
                if solution then
                    local value = board.get(solution, r, c)
                    if bit.band(mask, bit.lshift(1, value - 1)) == 0 then
                        errors[#errors + 1] = {
                            reason = "solution_candidate_removed",
                            row = r,
                            col = c,
                            value = value,
                        }
                    end
                end
            end
        end
    end
    return errors
end

local function validate_state(state)
    if type(state) ~= "table" then
        return nil, "state must be a table"
    end
    if type(state.board) ~= "table" then
        return nil, "state.board must be a board table"
    end
    local constraint_masks, board_err = solver.validate(state.board)
    if not constraint_masks then
        return nil, board_err
    end
    local solution_ok, solution_err = validate_solution(state.solution, state.board)
    if not solution_ok then
        return nil, solution_err
    end
    local revision, revision_err = validate_revision(state.revision)
    if not revision then
        return nil, revision_err
    end
    local note_errors, notes_err = validate_notes(state, constraint_masks)
    if not note_errors then
        return nil, notes_err
    end
    return {
        board = state.board,
        notes = state.notes,
        solution = state.solution,
        revision = revision,
        masks = constraint_masks,
    },
        note_errors
end

local function normalize_step(step)
    local technique = TECHNIQUE_BY_FLAG[step.flags]
    if not technique then
        return nil, "unknown technique flag: " .. tostring(step.flags)
    end
    return {
        type = step.type,
        row = step.row,
        col = step.col,
        value = step.value,
        flags = step.flags,
        pattern = project_pattern(step, technique),
        id = hint_id(step, technique),
    }
end

local function note_error_result(state, errors)
    return {
        status = "note_error",
        revision = state.revision,
        errors = errors,
    }
end

local function no_hint_result(state, reason)
    return {
        status = "none",
        reason = reason,
        revision = state.revision,
    }
end

local function no_hint_reason(instance, propagated, search_status)
    if instance:is_solved() then
        return "solved"
    elseif search_status == "search_capped" then
        return "search_capped"
    elseif not propagated then
        return "contradiction"
    end
    return "no_applicable_technique"
end

function hints.next(state, options)
    local normalized_options, options_err = validate_options(options)
    if not normalized_options then
        return nil, options_err
    end

    local normalized_state, note_errors_or_err = validate_state(state)
    if not normalized_state then
        return nil, note_errors_or_err
    end
    if #note_errors_or_err > 0 then
        return note_error_result(normalized_state, note_errors_or_err)
    end

    local instance, solver_err = solver.new(normalized_state.board, {
        candidates = normalized_state.notes,
        techniques = normalized_options.techniques,
        aic_max_depth = normalized_options.aic_max_depth,
        aic_max_expansions = normalized_options.aic_max_expansions,
    })
    if not instance then
        return nil, solver_err
    end

    local path = solve_path.new()
    local propagated, search_status = instance:propagate_next(path)
    if not propagated or #path.steps == 0 then
        return no_hint_result(normalized_state, no_hint_reason(instance, propagated, search_status))
    end

    local step, step_err = normalize_step(path.steps[1])
    if not step then
        return nil, step_err
    end
    local technique = TECHNIQUE_BY_FLAG[step.flags]
    return {
        status = "available",
        revision = normalized_state.revision,
        hint_id = step.id,
        technique = {
            id = technique.id,
            name = technique.name,
            flag = technique.flag,
            difficulty = flags.difficulty(technique.flag),
        },
        missed_strategy = {
            id = technique.id,
            flag = technique.flag,
        },
        pattern = {
            kind = step.pattern.kind,
            cells = copy_cells(step.pattern.cells),
        },
        action = {
            type = step.type,
            row = step.row,
            col = step.col,
            value = step.value,
            revision = normalized_state.revision,
        },
    }
end

return hints
