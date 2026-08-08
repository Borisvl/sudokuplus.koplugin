package.path = "plugins/sudoku.koplugin/?.lua;" .. package.path

local bit = require("bit")
local board = require("core.board")
local candidates = require("core.candidates")
local flags = require("core.techniques.flags")
local hints = require("core.hints")
local solve_path = require("core.solve_path")
local solver = require("core.solver")
local sudoku = require("core.sudoku")

local NAKED_SINGLE_PUZZLE = "385421967194756328627983145571892634839645271246137589462579813918364752753218490"
local HIDDEN_SINGLE_PUZZLE = "008007000016083000000000051107290000000000000000046307290000000000860140000300700"
local NAKED_PAIR_PUZZLE = "700009030000105006400260009002083951007000000005600000000000003100000060000004010"
local HIDDEN_PAIR_PUZZLE = "000032000000000000007600914096000800005008000030040005050200000700000560904010000"
local LOCKED_CANDIDATES_PUZZLE = "984000000000500040000000002006097200003002000000000010005060003407051890030009700"
local NAKED_TRIPLE_PUZZLE = "400500370320000004060000000800002030210840000000000090070090100040651000000070000"
local HIDDEN_TRIPLE_PUZZLE = "200000400500000006001034080000500040000000000060790000090200600003009001000080037"
local X_WING_PUZZLE = "000000000760003002002640009403900070000004903005000020010560000370090041000000060"
local NAKED_QUAD_PUZZLE = "000000060000030047032500000600007005207010908081004000000002000000000001005870000"
local HIDDEN_QUAD_PUZZLE = "800570290390000000000200000001000508000496000000800000209000001008000070560000082"
local SWORDFISH_PUZZLE = "160540070008001030030800000700050069600902057000000000000030040000000016000164500"
local JELLYFISH_PUZZLE = "200000003080030050003402100001205400000090000009308600002506900090020070400000001"
local SKYSCRAPER_PUZZLE = "000000000001902060000006790902000600370000950005000004140003005709024000000800000"
local W_WING_PUZZLE = "025100000000009030400708900040000800150400000000060004000000008263040000080390106"
local XY_WING_PUZZLE = "000060000000010863003009000904000000300000704570820000000006580690007000000040030"
local XYZ_WING_PUZZLE = "069000000000021000000800400001530080007600050000000100000000003902080010000340205"
local AIC_PUZZLE = "3.4.2..8...6.......5..7.3.....68..2.....34....6.15.7...1.........9....6...8217..5"
local SOLVED_BOARD = "534678912672195348198342567859761423426853791713924856961537284287419635345286179"
local UNIQUE_PUZZLE = "530070000600195000098000060800060003400803001700020006060000280000419005000080079"
local DUPLICATES = "530070000600195000098000060800060003400803001700020006060000280000419005500080079"
local UNSOLVABLE = "078002609030008020002000083000000040043090000007300090200001036001840902050003007"

local ALL_TECHNIQUES = bit.bor(flags.EASY, bit.bor(flags.MEDIUM, bit.bor(flags.HARD, flags.EXPERT)))

local HODOKU_CASES = {
    { id = "naked_single", puzzle = NAKED_SINGLE_PUZZLE },
    { id = "hidden_single", puzzle = HIDDEN_SINGLE_PUZZLE },
    { id = "naked_pair", puzzle = NAKED_PAIR_PUZZLE },
    { id = "hidden_pair", puzzle = HIDDEN_PAIR_PUZZLE },
    { id = "locked_candidates", puzzle = LOCKED_CANDIDATES_PUZZLE },
    { id = "naked_triple", puzzle = NAKED_TRIPLE_PUZZLE },
    { id = "hidden_triple", puzzle = HIDDEN_TRIPLE_PUZZLE },
    { id = "x_wing", puzzle = X_WING_PUZZLE },
    { id = "naked_quad", puzzle = NAKED_QUAD_PUZZLE },
    { id = "hidden_quad", puzzle = HIDDEN_QUAD_PUZZLE },
    { id = "swordfish", puzzle = SWORDFISH_PUZZLE },
    { id = "jellyfish", puzzle = JELLYFISH_PUZZLE },
    { id = "skyscraper", puzzle = SKYSCRAPER_PUZZLE },
    { id = "w_wing", puzzle = W_WING_PUZZLE },
    { id = "xy_wing", puzzle = XY_WING_PUZZLE },
    { id = "xyz_wing", puzzle = XYZ_WING_PUZZLE },
    { id = "aic", puzzle = AIC_PUZZLE },
}

local function state_for(puzzle, include_solution)
    local b = assert(board.from_string(puzzle))
    local initial = assert(solver.new(b))
    local solution
    if include_solution ~= false then
        local solved = initial:solve_any()
        solution = solved and solved.board
    end
    return {
        board = b,
        notes = candidates.clone(initial.candidates),
        solution = solution,
        revision = 0,
    }
end

local function copy_state(state)
    return {
        board = board.clone(state.board),
        notes = candidates.clone(state.notes),
        solution = state.solution and board.clone(state.solution),
        revision = state.revision,
    }
end

local function assert_valid_cells(cells)
    assert.is_true(type(cells) == "table")
    assert.is_true(#cells > 0)
    for _, cell in ipairs(cells) do
        assert.is_true(cell[1] >= 0 and cell[1] <= 8)
        assert.is_true(cell[2] >= 0 and cell[2] <= 8)
    end
end

describe("core.hints", function()
    it("returns a complete hint without a reveal-level argument", function()
        local state = state_for(NAKED_SINGLE_PUZZLE)
        local result, err = hints.next(state)

        assert.is_nil(err)
        assert.are.equal("available", result.status)
        assert.is_nil(result.level)
        assert.are.equal("naked_singles", result.technique.id)
        assert.are.equal(flags.NAKED_SINGLES, result.technique.flag)
        assert.are.equal("easy", result.technique.difficulty)
        assert.are.equal("Naked Singles", result.technique.name)
        assert.are.same({ id = "naked_singles", flag = flags.NAKED_SINGLES }, result.missed_strategy)
        assert.are.equal(0, result.revision)
        assert.is_not_nil(result.pattern)
        assert.is_not_nil(result.action)
        assert.are.same({ type = "place", row = 8, col = 8, value = 6, revision = 0 }, result.action)
    end)

    it("rejects a reveal level because reveal state belongs to the UI", function()
        local result, err = hints.next(state_for(NAKED_SINGLE_PUZZLE), { level = 1 })

        assert.is_nil(result)
        assert.is_string(err)
    end)

    it("uses the supplied revision in returned actions", function()
        local state = state_for(NAKED_SINGLE_PUZZLE)
        state.revision = 17
        local result, err = hints.next(state)

        assert.is_nil(err)
        assert.are.equal(17, result.revision)
        assert.are.equal(17, result.action.revision)
    end)

    it("skips an elimination already removed from the supplied notes", function()
        local state = state_for(NAKED_PAIR_PUZZLE)
        local first = assert(hints.next(state, { techniques = flags.NAKED_PAIRS }))
        local first_bit = bit.lshift(1, first.action.value - 1)
        local current = candidates.get(state.notes, first.action.row, first.action.col)
        candidates.set(state.notes, first.action.row, first.action.col, bit.band(current, bit.bnot(first_bit)))

        local second, err = hints.next(state, { techniques = flags.NAKED_PAIRS })

        assert.is_nil(err)
        assert.are.equal("available", second.status)
        assert.is_false(
            second.action.row == first.action.row
                and second.action.col == first.action.col
                and second.action.value == first.action.value
        )
    end)

    it("reports no applicable technique when all of its eliminations are already removed", function()
        local state = state_for(NAKED_PAIR_PUZZLE)
        local reference = assert(solver.new(state.board, {
            candidates = state.notes,
            techniques = flags.NAKED_PAIRS,
        }))
        local path = solve_path.new()
        assert.is_true(reference:propagate(path))
        assert.is_true(#path.steps > 0)
        for _, step in ipairs(path.steps) do
            if step.type == "elim" then
                local value_bit = bit.lshift(1, step.value - 1)
                local mask = candidates.get(state.notes, step.row, step.col)
                candidates.set(state.notes, step.row, step.col, bit.band(mask, bit.bnot(value_bit)))
            end
        end

        local result, err = hints.next(state, { techniques = flags.NAKED_PAIRS })

        assert.is_nil(err)
        assert.are.equal("none", result.status)
        assert.are.equal("no_applicable_technique", result.reason)
    end)

    it("reports removal of the solution candidate as a note error", function()
        local state = state_for(UNIQUE_PUZZLE)
        local solution_value = board.get(state.solution, 0, 2)
        local value_bit = bit.lshift(1, solution_value - 1)
        local current = candidates.get(state.notes, 0, 2)
        candidates.set(state.notes, 0, 2, bit.band(current, bit.bnot(value_bit)))

        local result, err = hints.next(state)

        assert.is_nil(err)
        assert.are.equal("note_error", result.status)
        assert.are.equal("solution_candidate_removed", result.errors[1].reason)
        assert.are.equal(0, result.errors[1].row)
        assert.are.equal(2, result.errors[1].col)
        assert.are.equal(solution_value, result.errors[1].value)
    end)

    it("reports illegal note masks as note errors", function()
        local illegal = state_for(NAKED_SINGLE_PUZZLE)
        candidates.set(illegal.notes, 8, 8, bit.lshift(1, 0))
        local illegal_result = assert(hints.next(illegal))
        assert.are.equal("note_error", illegal_result.status)
        assert.are.equal("illegal_candidate", illegal_result.errors[1].reason)
    end)

    it("does not treat an empty note mask as an error", function()
        local state = state_for(NAKED_SINGLE_PUZZLE, false)
        candidates.set(state.notes, 8, 8, 0)

        local result, err = hints.next(state)
        assert.is_nil(err)
        assert.are.not_equal("note_error", result.status)
        assert.are.equal("none", result.status)
        assert.are.equal("contradiction", result.reason)
    end)

    it("reports notes on given cells as note errors", function()
        local state = state_for(NAKED_SINGLE_PUZZLE)
        candidates.set(state.notes, 0, 0, bit.lshift(1, 0))

        local result, err = hints.next(state)

        assert.is_nil(err)
        assert.are.equal("note_error", result.status)
        assert.are.equal("given_cell_has_notes", result.errors[1].reason)
        assert.are.equal(0, result.errors[1].row)
        assert.are.equal(0, result.errors[1].col)
    end)

    it("reports all independent note errors in one result", function()
        local state = state_for(NAKED_SINGLE_PUZZLE)
        candidates.set(state.notes, 0, 0, bit.lshift(1, 0))
        candidates.set(state.notes, 8, 8, bit.lshift(1, 0))

        local result, err = hints.next(state)

        assert.is_nil(err)
        assert.are.equal("note_error", result.status)
        assert.is_true(#result.errors >= 3)
    end)

    it("reports solved, contradictory, and no-technique states separately", function()
        local solved = assert(hints.next(state_for(SOLVED_BOARD)))
        assert.are.equal("none", solved.status)
        assert.are.equal("solved", solved.reason)

        local empty = state_for(UNIQUE_PUZZLE)
        local no_technique = assert(hints.next(empty, { techniques = 0 }))
        assert.are.equal("none", no_technique.status)
        assert.are.equal("no_applicable_technique", no_technique.reason)

        local contradictory = assert(hints.next(state_for(UNSOLVABLE, false)))
        assert.are.equal("none", contradictory.status)
        assert.are.equal("contradiction", contradictory.reason)
    end)

    it("reports capped AIC searches", function()
        local result, err = hints.next(state_for(AIC_PUZZLE), {
            techniques = flags.ALTERNATING_INFERENCE_CHAIN,
            aic_max_expansions = 0,
        })

        assert.is_nil(err)
        assert.are.equal("none", result.status)
        assert.are.equal("search_capped", result.reason)
    end)

    it("allows deduction-only callers to omit the solution", function()
        local result, err = hints.next(state_for(NAKED_SINGLE_PUZZLE, false))

        assert.is_nil(err)
        assert.are.equal("available", result.status)
    end)

    it("matches the first human deduction on representative HoDoKu fixtures", function()
        for _, test_case in ipairs(HODOKU_CASES) do
            local state = state_for(test_case.puzzle)
            local reference_solver = assert(solver.new(state.board, { techniques = ALL_TECHNIQUES }))
            local reference_path = solve_path.new()
            assert.is_true(reference_solver:propagate(reference_path), test_case.id .. " should propagate")
            assert.is_true(#reference_path.steps > 0, test_case.id .. " should have a deduction")
            local expected = reference_path.steps[1]

            local result, err = hints.next(state, { techniques = ALL_TECHNIQUES })

            assert.is_nil(err, test_case.id .. " should not return an error")
            assert.are.equal("available", result.status, test_case.id .. " should have a hint")
            assert.are.equal(expected.flags, result.technique.flag)
            assert.are.equal(expected.pattern.kind, result.pattern.kind)
            assert_valid_cells(result.pattern.cells)
            assert.are.same({
                type = expected.type,
                row = expected.row,
                col = expected.col,
                value = expected.value,
                revision = 0,
            }, result.action)
        end
    end)

    it("does not mutate the supplied stateless state", function()
        local state = state_for(X_WING_PUZZLE)
        local before = copy_state(state)
        local result, err = hints.next(state, { techniques = flags.X_WING })

        assert.is_nil(err)
        assert.is_not_nil(result)
        assert.are.same(before.board, state.board)
        assert.are.same(before.notes, state.notes)
    end)

    it("rejects malformed state and options", function()
        local invalid_state, state_err = hints.next(nil)
        assert.is_nil(invalid_state)
        assert.is_string(state_err)

        local duplicate = {
            board = assert(board.from_string(DUPLICATES)),
            notes = candidates.new(),
        }
        local duplicate_result, duplicate_err = hints.next(duplicate)
        assert.is_nil(duplicate_result)
        assert.is_string(duplicate_err)

        local oversized, mask_err = hints.next(state_for(NAKED_SINGLE_PUZZLE), { techniques = 0x100000000 })
        assert.is_nil(oversized)
        assert.is_string(mask_err)

        local invalid_level, level_err = hints.next(state_for(NAKED_SINGLE_PUZZLE), { level = 1 })
        assert.is_nil(invalid_level)
        assert.is_string(level_err)

        local missing_notes = state_for(NAKED_SINGLE_PUZZLE)
        missing_notes.notes = nil
        local missing_result, missing_err = hints.next(missing_notes)
        assert.is_nil(missing_result)
        assert.is_string(missing_err)

        local malformed_notes = state_for(NAKED_SINGLE_PUZZLE)
        malformed_notes.notes[10] = {}
        local malformed_result, malformed_err = hints.next(malformed_notes)
        assert.is_nil(malformed_result)
        assert.is_string(malformed_err)

        local invalid_mask = state_for(NAKED_SINGLE_PUZZLE)
        invalid_mask.notes[9][9] = 0x400
        local invalid_mask_result, invalid_mask_err = hints.next(invalid_mask)
        assert.is_nil(invalid_mask_result)
        assert.is_string(invalid_mask_err)

        for _, revision in ipairs({ -1, 1.5, "1" }) do
            local invalid_revision = state_for(NAKED_SINGLE_PUZZLE)
            invalid_revision.revision = revision
            local invalid_revision_result, invalid_revision_err = hints.next(invalid_revision)
            assert.is_nil(invalid_revision_result)
            assert.is_string(invalid_revision_err)
        end

        local invalid_solution = state_for(NAKED_SINGLE_PUZZLE)
        invalid_solution.solution = board.new()
        local invalid_solution_result, invalid_solution_err = hints.next(invalid_solution)
        assert.is_nil(invalid_solution_result)
        assert.is_string(invalid_solution_err)

        local mismatched_solution = state_for(NAKED_SINGLE_PUZZLE)
        mismatched_solution.solution = assert(board.from_string(SOLVED_BOARD))
        local mismatched_result, mismatched_err = hints.next(mismatched_solution)
        assert.is_nil(mismatched_result)
        assert.is_string(mismatched_err)
    end)

    it("is deterministic for repeated stateless probes", function()
        local first = hints.next(state_for(AIC_PUZZLE), { techniques = ALL_TECHNIQUES })
        local second = hints.next(state_for(AIC_PUZZLE), { techniques = ALL_TECHNIQUES })

        assert.are.same(first, second)
    end)

    it("is available through the sudoku facade", function()
        local state = state_for(NAKED_SINGLE_PUZZLE)
        local result, err = sudoku.next_hint(state)

        assert.is_nil(err)
        assert.are.equal("available", result.status)
        assert.are.same({ type = "place", row = 8, col = 8, value = 6, revision = 0 }, result.action)
    end)
end)
