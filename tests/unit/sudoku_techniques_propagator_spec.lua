package.path = "plugins/sudoku.koplugin/?.lua;" .. package.path

local bit = require("bit")
local board = require("core.board")
local candidates = require("core.candidates")
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

-- All techniques implemented so far (easy + medium tiers).
local all_implemented = bit.bor(flags.EASY, flags.MEDIUM)

describe("core.techniques.propagator", function()
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
        assert.are.equal(81, board.count_clues(s.board))
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

    it("solve_until runs propagation before backtracking", function()
        local s = solver.new(board.from_string(NAKED_SINGLE_PUZZLE), { techniques = flags.NAKED_SINGLES })
        local sol = s:solve_any()
        assert.is_not_nil(sol)
        assert.are.equal(1, #sol.solve_path.steps)
        assert.are.equal(flags.NAKED_SINGLES, sol.solve_path.steps[1].flags)
        assert.are.equal(NAKED_SINGLE_PUZZLE:sub(1, 80) .. "6", board.to_string(sol.board))
    end)

    it("solve_until returns no solutions when propagation dead-ends", function()
        local s = solver.new(board.from_string(INCONSISTENT), { techniques = flags.NAKED_SINGLES })
        assert.is_nil(s:solve_any())
        assert.are.equal(0, #s:solve_all())
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
        for _, puzzle in ipairs({ ONE_PUZZLE, TWO_PUZZLE, SIX_PUZZLE }) do
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
            assert.are.equal(2, step.candidates_eliminated)
        end
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
end)
