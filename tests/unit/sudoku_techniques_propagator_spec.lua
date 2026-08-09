package.path = "plugins/sudoku.koplugin/?.lua;" .. package.path

local bit = require("bit")
local board = require("core.board")
local candidates = require("core.candidates")
local prng = require("core.prng")
local solve_path = require("core.solve_path")
local solver = require("core.solver")
local flags = require("core.techniques.flags")
local propagator = require("core.techniques.propagator")

-- HoDoKu naked single example (single empty cell at (8,8), only candidate 6).
local NAKED_SINGLE_PUZZLE = "385421967194756328627983145571892634839645271246137589462579813918364752753218490"
-- HoDoKu hidden single example.
local HIDDEN_SINGLE_PUZZLE = "008007000016083000000000051107290000000000000000046307290000000000860140000300700"
-- Rule-legal board that is logically inconsistent: cells (0,0) and (1,1) are both
-- forced to 1 (naked singles) inside box 0, which can only hold one 1. Placing
-- 1 at (0,0) empties the candidates of (1,1), so propagation dead-ends and must
-- roll back.
local INCONSISTENT = "023456789405789236678000000250000000380000000790000000530000000840000000960000000"
local ONE_PUZZLE = "530070000600195000098000060800060003400803001700020006060000280000419005000080079"
local TWO_PUZZLE = "295743861431865900876192543387459216612387495549216738763504189928671354154938600"
local SIX_PUZZLE = "295743001431865900876192543387459216612387495549216738763500000000000000000000000"

-- All techniques implemented so far (easy through expert tiers).
local all_implemented = bit.bor(flags.EASY, bit.bor(flags.MEDIUM, bit.bor(flags.HARD, flags.EXPERT)))

-- HoDoKu hard-tier examples: x-wing (bf201), swordfish (bf301), jellyfish
-- (bf401), skyscraper (sk01), naked quads (n401), hidden quads (h401).
local HARD_PUZZLES = {
    { "x_wing", "000000000760003002002640009403900070000004903005000020010560000370090041000000060" },
    { "swordfish", "160540070008001030030800000700050069600902057000000000000030040000000016000164500" },
    { "jellyfish", "200000003080030050003402100001205400000090000009308600002506900090020070400000001" },
    { "skyscraper", "000000000001902060000006790902000600370000950005000004140003005709024000000800000" },
    { "naked_quad", "000000060000030047032500000600007005207010908081004000000002000000000001005870000" },
    { "hidden_quad", "800570290390000000000200000001000508000496000000800000209000001008000070560000082" },
}

-- Expert-tier examples: w-wing (w101), xy-wing (y101), xyz-wing (z101), and
-- rustoku's chain puzzles (x-chain, xy-chain, discontinuous nice loop).
local EXPERT_PUZZLES = {
    { "w_wing", "025100000000009030400708900040000800150400000000060004000000008263040000080390106" },
    { "xy_wing", "000060000000010863003009000904000000300000704570820000000006580690007000000040030" },
    { "xyz_wing", "069000000000021000000800400001530080007600050000000100000000003902080010000340205" },
    { "aic", "3.4.2..8...6.......5..7.3.....68..2.....34....6.15.7...1.........9....6...8217..5" },
    { "aic", "3...4.52858.........2..........74....1....35..5.6...4..78.....21..2......39..68.." },
    { "aic", "....8.2....5....4..2...5........7......21..971.4....3...........973..52...8.5136." },
}

local function assert_valid_completion(puzzle, completed, label)
    assert.are.equal(81, board.count_clues(completed), label .. " should be complete")
    assert.is_not_nil(solver.validate(completed), label .. " should be a valid Sudoku")

    local givens = board.from_string(puzzle)
    for i = 1, 81 do
        if givens[i] ~= 0 then
            assert.are.equal(givens[i], completed[i], label .. " should preserve givens")
        end
    end
end

local function copy_list(list)
    local copy = {}
    for i, value in ipairs(list) do
        copy[i] = value
    end
    return copy
end

describe("core.techniques.propagator", function()
    it("loads every configured technique", function()
        assert.are.same({
            "naked_singles",
            "hidden_singles",
            "naked_pairs",
            "hidden_pairs",
            "locked_candidates",
            "naked_triples",
            "hidden_triples",
            "x_wing",
            "naked_quads",
            "hidden_quads",
            "swordfish",
            "jellyfish",
            "skyscraper",
            "w_wing",
            "xy_wing",
            "xyz_wing",
            "aic",
        }, propagator.technique_names())
    end)

    it("does nothing when no techniques are enabled", function()
        local s = solver.new(board.from_string(NAKED_SINGLE_PUZZLE))
        local path = solve_path.new()
        assert.is_true(s:propagate(path))
        assert.are.equal(0, #path.steps)
    end)

    it("propagates to completion on a single-candidate board", function()
        local s = solver.new(board.from_string(NAKED_SINGLE_PUZZLE), { techniques = flags.NAKED_SINGLES })
        local path = solve_path.new()
        assert.is_true(s:propagate(path))
        assert_valid_completion(NAKED_SINGLE_PUZZLE, s.board, "naked single")
        assert.are.equal(1, #path.steps)
        assert.are.equal(flags.NAKED_SINGLES, path.steps[1].flags)
        assert.is_not_nil(path.steps[1].pattern)
    end)

    it("runs naked singles before hidden singles in the fixed order", function()
        local s = solver.new(board.from_string(NAKED_SINGLE_PUZZLE), {
            techniques = bit.bor(flags.NAKED_SINGLES, flags.HIDDEN_SINGLES),
        })
        local path = solve_path.new()
        assert.is_true(s:propagate(path))
        assert.are.equal(1, #path.steps)
        assert.are.equal(flags.NAKED_SINGLES, path.steps[1].flags)
    end)

    it("combines techniques with sequential step numbers and valid flags", function()
        local s = solver.new(board.from_string(HIDDEN_SINGLE_PUZZLE), {
            techniques = bit.bor(flags.NAKED_SINGLES, flags.HIDDEN_SINGLES),
        })
        local path = solve_path.new()
        assert.is_true(s:propagate(path))
        assert.is_true(#path.steps > 0)
        local hidden = false
        for i, step in ipairs(path.steps) do
            assert.are.equal(i - 1, step.step_number)
            assert.is_true(step.flags == flags.NAKED_SINGLES or step.flags == flags.HIDDEN_SINGLES)
            if step.flags == flags.HIDDEN_SINGLES then
                hidden = true
            end
        end
        assert.is_true(hidden)
    end)

    it("records difficulty points on technique steps", function()
        local s = solver.new(board.from_string(NAKED_SINGLE_PUZZLE), { techniques = flags.NAKED_SINGLES })
        local path = solve_path.new()
        s:propagate(path)
        assert.are.equal(1, path.steps[1].difficulty_point)
    end)

    it("rolls back all steps and restores state on a dead end", function()
        local initial = board.from_string(INCONSISTENT)
        local s = solver.new(board.from_string(INCONSISTENT), { techniques = flags.NAKED_SINGLES })
        local path = solve_path.new()
        assert.is_false(s:propagate(path))
        assert.are.equal(0, #path.steps)
        assert.are.equal(board.to_string(initial), board.to_string(s.board))
        assert.are.equal(bit.lshift(1, 0), candidates.get(s.candidates, 0, 0))
        assert.are.equal(bit.lshift(1, 0), candidates.get(s.candidates, 1, 1))
    end)

    it("detects missing candidate positions in rows, columns, and boxes", function()
        local bit1 = bit.lshift(1, 0)
        local unit_cells = {
            {
                { 0, 0 },
                { 0, 1 },
                { 0, 2 },
                { 0, 3 },
                { 0, 4 },
                { 0, 5 },
                { 0, 6 },
                { 0, 7 },
                { 0, 8 },
            },
            {
                { 0, 0 },
                { 1, 0 },
                { 2, 0 },
                { 3, 0 },
                { 4, 0 },
                { 5, 0 },
                { 6, 0 },
                { 7, 0 },
                { 8, 0 },
            },
            {
                { 0, 0 },
                { 0, 1 },
                { 0, 2 },
                { 1, 0 },
                { 1, 1 },
                { 1, 2 },
                { 2, 0 },
                { 2, 1 },
                { 2, 2 },
            },
        }

        for _, cells in ipairs(unit_cells) do
            local s = solver.new(board.new(), { techniques = 0 })
            local p = propagator.new(s.board, s.masks, s.candidates, 0)
            local path = solve_path.new()
            for _, cell in ipairs(cells) do
                assert.is_true(p:eliminate_candidate(cell[1], cell[2], bit1, flags.NAKED_SINGLES, path))
            end

            assert.is_false(p:propagate_constraints(path, 0))
            assert.are.equal(0, #path.steps)
            for _, cell in ipairs(cells) do
                assert.are_not.equal(0, bit.band(p:cand(cell[1], cell[2]), bit1))
            end
        end
    end)

    it("is deterministic for a seeded solver", function()
        local function propagate()
            local s = solver.new(board.from_string(HIDDEN_SINGLE_PUZZLE), {
                techniques = bit.bor(flags.NAKED_SINGLES, flags.HIDDEN_SINGLES),
                rng = require("core.prng").new(42),
            })
            local path = solve_path.new()
            s:propagate(path)
            local out = {}
            for i, step in ipairs(path.steps) do
                out[i] = { step.type, step.row, step.col, step.value, step.flags }
            end
            return out
        end
        assert.are.same(propagate(), propagate())
    end)

    it("is deterministic across the full technique tier", function()
        -- Hard (jellyfish) and expert (AIC nice loop) examples: two runs of the
        -- same propagation must produce identical step traces, including the
        -- pattern metadata that feeds the hint system.
        for _, puzzle in ipairs({
            "200000003080030050003402100001205400000090000009308600002506900090020070400000001",
            "....8.2....5....4..2...5........7......21..971.4....3...........973..52...8.5136.",
        }) do
            local function propagate()
                local s = solver.new(board.from_string(puzzle), { techniques = all_implemented })
                local path = solve_path.new()
                s:propagate(path)
                local out = {}
                for i, step in ipairs(path.steps) do
                    out[i] = {
                        step.type,
                        step.row,
                        step.col,
                        step.value,
                        step.flags,
                        step.pattern and step.pattern.kind,
                        step.pattern and step.pattern.values,
                    }
                end
                return out
            end
            assert.are.same(propagate(), propagate(), "full-tier propagation should be deterministic")
        end
    end)

    it("solve_until runs propagation before backtracking", function()
        local s = solver.new(board.from_string(NAKED_SINGLE_PUZZLE), { techniques = flags.NAKED_SINGLES })
        local sol = s:solve_any()
        assert.is_not_nil(sol)
        assert.are.equal(1, #sol.solve_path.steps)
        assert.are.equal(flags.NAKED_SINGLES, sol.solve_path.steps[1].flags)
        assert.are.equal(NAKED_SINGLE_PUZZLE:sub(1, 80) .. "6", board.to_string(sol.board))
    end)

    it("can stop after the first technique makes progress", function()
        local techniques = bit.bor(flags.NAKED_SINGLES, flags.HIDDEN_SINGLES)
        local next_solver = solver.new(board.from_string(HIDDEN_SINGLE_PUZZLE), { techniques = techniques })
        local next_path = solve_path.new()
        local before_board = board.clone(next_solver.board)
        local before_candidates = candidates.clone(next_solver.candidates)
        local ok = next_solver:propagate_next(next_path)

        assert.is_true(ok)
        assert.is_true(#next_path.steps > 0)
        assert.are.same(before_board, next_solver.board)
        assert.are.same(before_candidates, next_solver.candidates)
        local first_flags = next_path.steps[1].flags
        for _, step in ipairs(next_path.steps) do
            assert.are.equal(first_flags, step.flags)
        end

        local full_solver = solver.new(board.from_string(HIDDEN_SINGLE_PUZZLE), { techniques = techniques })
        local full_path = solve_path.new()
        assert.is_true(full_solver:propagate(full_path))
        local used_later_technique = false
        for _, step in ipairs(full_path.steps) do
            if step.flags ~= first_flags then
                used_later_technique = true
                break
            end
        end
        assert.is_true(used_later_technique)
    end)

    it("rejects unsafe placements and multi-bit single eliminations", function()
        local occupied = solver.new(board.from_string(NAKED_SINGLE_PUZZLE), { techniques = 0 })
        local occupied_prop = propagator.new(occupied.board, occupied.masks, occupied.candidates, 0)
        local occupied_path = solve_path.new()
        local occupied_ok, occupied_err = occupied_prop:place_and_update(0, 0, 1, 0, occupied_path)

        assert.is_nil(occupied_ok)
        assert.is_string(occupied_err)
        assert.are.equal(0, #occupied_path.steps)

        local empty = solver.new(board.new(), { techniques = 0 })
        local empty_prop = propagator.new(empty.board, empty.masks, empty.candidates, 0)
        local empty_path = solve_path.new()
        local multi_bit = bit.bor(bit.lshift(1, 0), bit.lshift(1, 1))
        local eliminated, elimination_err = empty_prop:eliminate_candidate(0, 0, multi_bit, 0, empty_path)

        assert.is_nil(eliminated)
        assert.is_string(elimination_err)
        assert.are.equal(0, #empty_path.steps)
        assert.are.equal(0x1FF, empty_prop:cand(0, 0))
    end)

    it("solve_until reports no solutions for a logically inconsistent board", function()
        -- The propagation dead-end is rolled back and falls through to plain
        -- backtracking; the board is genuinely unsolvable, so the result is
        -- still empty (never a wrong non-zero count).
        local s = solver.new(board.from_string(INCONSISTENT), { techniques = flags.NAKED_SINGLES })
        assert.is_nil(s:solve_any())
        assert.are.equal(0, #s:solve_all())
    end)

    it("falls back to backtracking when the technique pass dead-ends on a solvable board", function()
        -- Simulate an unsound technique: strip candidates from cell (0, 2)
        -- until it is empty, forcing a propagation dead-end on a board that is
        -- still solvable. The dead-end must not hide the real solution: the
        -- rolled-back state is handed to plain backtracking.
        local naked_singles_mod = require("core.techniques.naked_singles")
        local original_apply = naked_singles_mod.apply
        naked_singles_mod.apply = function(prop, path)
            local mask = prop:cand(0, 2)
            if mask ~= 0 then
                local lowest = bit.band(mask, bit.bnot(bit.band(mask, mask - 1)))
                prop:eliminate_candidate(0, 2, lowest, flags.NAKED_SINGLES, path)
                return true
            end
            return false
        end
        finally(function()
            naked_singles_mod.apply = original_apply
        end)

        local s = solver.new(board.from_string(ONE_PUZZLE), {
            techniques = flags.NAKED_SINGLES,
            rng = prng.new(7),
        })
        local solutions = s:solve_all()
        assert.are.equal(1, #solutions, "a technique dead-end must not hide the real solution")

        local plain = solver.new(board.from_string(ONE_PUZZLE), { rng = prng.new(7) })
        assert.are.equal(
            board.to_string(plain:solve_any().board),
            board.to_string(solutions[1].board),
            "the fallback result must match the plain solver"
        )
    end)

    it("without techniques the backtracking path keeps empty flags", function()
        local s = solver.new(board.from_string(NAKED_SINGLE_PUZZLE))
        local sol = s:solve_any()
        assert.is_not_nil(sol)
        for _, step in ipairs(sol.solve_path.steps) do
            assert.are.equal(0, step.flags)
            assert.is_nil(step.pattern)
        end
    end)

    it("techniques-enabled solving matches the plain solver (solution parity)", function()
        -- Easy multi-solution puzzles plus every hard- and expert-tier example:
        -- the advanced techniques only fire on the latter, so this actually
        -- exercises the EASY|MEDIUM|HARD|EXPERT tier.
        local puzzles = {
            ONE_PUZZLE,
            TWO_PUZZLE,
            SIX_PUZZLE,
        }
        for _, entry in ipairs(HARD_PUZZLES) do
            puzzles[#puzzles + 1] = entry[2]
        end
        for _, entry in ipairs(EXPERT_PUZZLES) do
            puzzles[#puzzles + 1] = entry[2]
        end
        for _, puzzle in ipairs(puzzles) do
            local plain = solver.new(board.from_string(puzzle), { rng = require("core.prng").new(7) })
            local tech = solver.new(board.from_string(puzzle), {
                rng = require("core.prng").new(7),
                techniques = all_implemented,
            })
            local a = plain:solve_all()
            local b = tech:solve_all()
            assert.are.equal(#a, #b, "solution count parity for " .. puzzle:sub(1, 8))
            for i = 1, #a do
                assert.are.equal(
                    board.to_string(a[i].board),
                    board.to_string(b[i].board),
                    "solution board parity for " .. puzzle:sub(1, 8)
                )
            end
        end
    end)

    it("solves every hard- and expert-tier example guess-free with all techniques", function()
        local all_puzzles = {}
        for _, entry in ipairs(HARD_PUZZLES) do
            all_puzzles[#all_puzzles + 1] = entry
        end
        for _, entry in ipairs(EXPERT_PUZZLES) do
            all_puzzles[#all_puzzles + 1] = entry
        end
        for _, entry in ipairs(all_puzzles) do
            local name, puzzle = entry[1], entry[2]
            local s = solver.new(board.from_string(puzzle), { techniques = all_implemented })
            local path = solve_path.new()
            assert.is_true(s:propagate(path), name .. " propagation should not dead-end")
            assert_valid_completion(puzzle, s.board, name)
            local used_target = false
            for _, step in ipairs(path.steps) do
                if step.pattern and step.pattern.kind == name then
                    used_target = true
                end
            end
            assert.is_true(used_target, name .. " technique should appear in the solve path")
        end
    end)

    it("eliminate_candidate removes the candidate, records a step, and reports no-op", function()
        local s = solver.new(board.from_string(INCONSISTENT), { techniques = 0 })
        local p = propagator.new(s.board, s.masks, s.candidates, 0)
        local path = solve_path.new()
        local mask = p:cand(0, 0)
        assert.are.equal(1, mask)
        local bit1 = bit.lshift(1, 0)

        assert.is_true(p:eliminate_candidate(0, 0, bit1, flags.NAKED_SINGLES, path, { kind = "test" }))
        assert.are.equal(0, p:cand(0, 0))
        assert.are.equal(1, #path.steps)
        assert.are.equal("elim", path.steps[1].type)
        assert.are.equal(flags.NAKED_SINGLES, path.steps[1].flags)
        assert.are.equal(1, path.steps[1].candidates_eliminated)
        assert.are.same({ kind = "test" }, path.steps[1].pattern)

        -- Re-eliminating an absent candidate is a no-op: no step is recorded.
        assert.is_false(p:eliminate_candidate(0, 0, bit1, flags.NAKED_SINGLES, path, { kind = "test" }))
        assert.are.equal(1, #path.steps)
    end)

    it("eliminate_multiple_candidates records one step per eliminated candidate", function()
        local s = solver.new(board.from_string(INCONSISTENT), { techniques = 0 })
        local p = propagator.new(s.board, s.masks, s.candidates, 0)
        local path = solve_path.new()
        local mask = p:cand(3, 2)
        local rest = bit.band(mask, mask - 1)
        local b1 = mask - rest
        local b2 = rest - bit.band(rest, rest - 1)
        local two = bit.bor(b1, b2)

        assert.is_true(p:eliminate_multiple_candidates(3, 2, two, flags.NAKED_SINGLES, path, { kind = "test" }))
        assert.are.equal(2, #path.steps)
        assert.are.equal(0, bit.band(p:cand(3, 2), two))
        for _, step in ipairs(path.steps) do
            assert.are.equal("elim", step.type)
            assert.are.equal(1, step.candidates_eliminated)
            assert.are.equal(1, step.related_cell_count)
        end
        assert.are.equal(2, path.steps[1].candidates_eliminated + path.steps[2].candidates_eliminated)
    end)

    it("records placement metrics for direct peer effects", function()
        local s = solver.new(board.new(), { techniques = 0 })
        local p = propagator.new(s.board, s.masks, s.candidates, 0)
        local path = solve_path.new()

        p:place_and_update(0, 0, 1, 0, path)

        assert.are.equal(20, path.steps[1].candidates_eliminated)
        assert.are.equal(20, path.steps[1].related_cell_count)
    end)

    it("rollback restores eliminated candidates", function()
        local s = solver.new(board.from_string(INCONSISTENT), { techniques = 0 })
        local p = propagator.new(s.board, s.masks, s.candidates, 0)
        local path = solve_path.new()
        local before0 = p:cand(0, 0)
        local before32 = p:cand(3, 2)

        p:eliminate_candidate(0, 0, 1, flags.NAKED_SINGLES, path, { kind = "test" })
        local rest = bit.band(p:cand(3, 2), p:cand(3, 2) - 1)
        local two = bit.bor(p:cand(3, 2) - rest, rest - bit.band(rest, rest - 1))
        p:eliminate_multiple_candidates(3, 2, two, flags.NAKED_SINGLES, path, { kind = "test" })

        p:rollback(path, 0)
        assert.are.equal(0, #path.steps)
        assert.are.equal(before0, p:cand(0, 0))
        assert.are.equal(before32, p:cand(3, 2))
    end)

    it("refuses to roll back a step with no candidate marker", function()
        local s = solver.new(board.from_string(INCONSISTENT), { techniques = 0 })
        local p = propagator.new(s.board, s.masks, s.candidates, 0)
        local path = solve_path.new()
        -- A foreign step pushed directly into the path never went through
        -- place_and_update/eliminate_candidate, so no trail marker exists; a
        -- silent full recompute could corrupt earlier eliminations.
        solve_path.push(path, solve_path.placement_step(0, 0, 1, flags.NAKED_SINGLES))
        assert.has_error(function()
            p:rollback(path, 0)
        end)
    end)

    it("rollback is a no-op at a checkpoint past the pushed steps", function()
        local s = solver.new(board.from_string(INCONSISTENT), { techniques = 0 })
        local p = propagator.new(s.board, s.masks, s.candidates, 0)
        local path = solve_path.new()
        solve_path.push(path, solve_path.placement_step(0, 0, 1, flags.NAKED_SINGLES))
        p:rollback(path, 1)
        assert.are.equal(1, #path.steps, "steps at or before the checkpoint must be preserved")
    end)

    it("keeps earlier eliminations when rolling back a later placement", function()
        local s = solver.new(board.new(), { techniques = 0 })
        local p = propagator.new(s.board, s.masks, s.candidates, 0)
        local path = solve_path.new()
        local bit1 = bit.lshift(1, 0)

        p:eliminate_candidate(0, 1, bit1, flags.NAKED_SINGLES, path, { kind = "test" })
        local checkpoint = #path.steps
        p:place_and_update(0, 0, 2, flags.NAKED_SINGLES, path, { kind = "test" })

        assert.are.equal(0, bit.band(p:cand(0, 1), bit1))
        p:rollback(path, checkpoint)

        assert.are.equal(checkpoint, #path.steps)
        assert.are.equal(0, s.board[1])
        assert.are.equal(0, bit.band(p:cand(0, 1), bit1))
        assert.are.equal(bit.lshift(1, 1), bit.band(p:cand(0, 1), bit.lshift(1, 1)))
    end)

    it("preserves caller-owned steps at a nonzero propagation checkpoint", function()
        local s = solver.new(board.from_string(INCONSISTENT), { techniques = flags.NAKED_SINGLES })
        local p = propagator.new(s.board, s.masks, s.candidates, flags.NAKED_SINGLES)
        local path = solve_path.new()
        local prior_mask = p:cand(3, 2)
        local prior_num = flags.lowest_bit(prior_mask) + 1

        p:place_and_update(3, 2, prior_num, flags.NAKED_SINGLES, path, { kind = "prior" })
        local checkpoint = #path.steps
        local before_board = board.to_string(s.board)

        assert.is_false(s:propagate(path))
        assert.are.equal(checkpoint, #path.steps)
        assert.are.equal("place", path.steps[1].type)
        assert.are.equal(3, path.steps[1].row)
        assert.are.equal(2, path.steps[1].col)
        assert.are.equal(prior_num, path.steps[1].value)
        assert.are.equal(prior_num, board.get(s.board, 3, 2))
        assert.are.equal(before_board, board.to_string(s.board))
        assert.are.equal(bit.lshift(1, 0), p:cand(0, 0))
        assert.are.equal(bit.lshift(1, 0), p:cand(1, 1))
    end)

    it("preserves randomized candidate state across branch rollback", function()
        local solution =
            board.from_string("534678912672195348198342567859761423426853791713924856961537284287419635345286179")
        local rng = prng.new(91)

        for _ = 1, 12 do
            local puzzle = board.clone(solution)
            for _ = 1, 35 do
                local index = rng:int(81)
                puzzle[index] = 0
            end

            local s = assert(solver.new(puzzle, { techniques = 0 }))
            local before_board = board.clone(s.board)
            local before_masks = {
                row = copy_list(s.masks.row),
                col = copy_list(s.masks.col),
                box = copy_list(s.masks.box),
            }
            local before_candidates = candidates.clone(s.candidates)
            local p = propagator.new(s.board, s.masks, s.candidates, 0)
            local path = solve_path.new()

            for _ = 1, 8 do
                local empty = board.iter_empty_cells(s.board)
                if #empty == 0 then
                    break
                end
                local cell = empty[rng:int(#empty)]
                local mask = p:cand(cell[1], cell[2])
                local values = candidates.from_mask(mask)
                if #values == 0 then
                    break
                end

                if rng:int(2) == 1 then
                    p:eliminate_candidate(cell[1], cell[2], bit.lshift(1, values[rng:int(#values)] - 1), 0, path)
                else
                    p:place_and_update(cell[1], cell[2], values[rng:int(#values)], 0, path)
                end
            end

            p:rollback(path, 0)
            assert.are.same(before_board, s.board)
            assert.are.same(before_masks, s.masks)
            assert.are.same(before_candidates, s.candidates)
        end
    end)
end)
