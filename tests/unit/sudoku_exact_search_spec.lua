package.path = "plugins/sudokuplus.koplugin/?.lua;" .. package.path

local board = require("sudokuplus.core.board")
local exact_search = require("sudokuplus.core.exact_search")
local prng = require("sudokuplus.core.prng")
local solver = require("sudokuplus.core.solver")
local util = require("sudokuplus.core.util")

local SOLUTION = "534678912672195348198342567859761423426853791713924856961537284287419635345286179"
local TWO_PUZZLE = "295743861431865900876192543387459216612387495549216738763504189928671354154938600"

local function snapshot(workspace)
    return {
        board = board.to_string(workspace.board),
        masks = util.deep_copy(workspace.masks),
    }
end

describe("core.exact_search", function()
    it("uses the forced-mask shortcut for a singleton removal", function()
        local solution = assert(board.from_string(SOLUTION))
        local workspace = assert(exact_search.new(solution, solution, { search_budget = 50000 }))

        assert.are.equal(5, workspace:remove(0, 0))
        local alternative, err, forced = workspace:has_alternative(0, 0)

        assert.is_nil(err)
        assert.is_false(alternative)
        assert.is_true(forced)
        assert.are.equal(0, workspace.search_nodes)
        assert.is_nil(workspace.search_capped)
    end)

    it("matches a fresh two-solution count over deterministic unique-parent transitions", function()
        local solution = assert(board.from_string(SOLUTION))
        local workspace = assert(exact_search.new(solution, solution, { search_budget = 50000 }))
        local fresh = board.clone(solution)
        local order = {}
        for index = 1, 81 do
            order[index] = index
        end
        prng.new(20260822):shuffle(order)

        local saw_forced = false
        local saw_searched_unique = false
        local saw_alternative = false
        for _, index in ipairs(order) do
            local row = math.floor((index - 1) / 9)
            local col = (index - 1) % 9
            local value = assert(workspace:remove(row, col))
            fresh[index] = 0

            local before_search = snapshot(workspace)
            local alternative, err, forced = workspace:has_alternative(row, col)
            assert.is_nil(err)
            assert.is_nil(workspace.search_capped)
            assert.are.same(before_search, snapshot(workspace), "search mutated exact state at cell " .. index)
            local reference = assert(solver.new(fresh)):count_solutions(2)
            assert.are.equal(reference > 1, alternative, "oracle mismatch at cell " .. index)
            assert.are.same(assert(solver.validate(fresh)), workspace.masks)

            saw_forced = saw_forced or forced
            saw_searched_unique = saw_searched_unique or (not alternative and not forced)
            saw_alternative = saw_alternative or alternative
            if alternative then
                assert.is_true(workspace:restore(row, col))
                fresh[index] = value
            end
        end

        assert.is_true(saw_forced)
        assert.is_true(saw_searched_unique)
        assert.is_true(saw_alternative)
        assert.are.equal(board.to_string(fresh), board.to_string(workspace.board))
    end)

    it("leaves a capped alternative search inconclusive and restores exact state", function()
        local solution = assert(board.from_string(SOLUTION))
        local workspace = assert(exact_search.new(board.new(), solution, { search_budget = 0 }))
        local before = snapshot(workspace)

        local alternative, err, forced = workspace:has_alternative(0, 0)

        assert.is_nil(alternative)
        assert.is_nil(err)
        assert.is_false(forced)
        assert.is_true(workspace.search_capped)
        assert.are.same(before, snapshot(workspace))
    end)

    it("counts multi-cell removals when an alternative differs in only one removed cell", function()
        local puzzle = assert(board.from_string(TWO_PUZZLE))
        local solutions = assert(solver.new(puzzle)):solve_until(2)
        assert.are.equal(2, #solutions)
        local first = solutions[1].board
        local second = solutions[2].board
        local differing_index
        local agreeing_index
        for index = 1, 81 do
            if puzzle[index] == 0 then
                if first[index] ~= second[index] then
                    differing_index = differing_index or index
                else
                    agreeing_index = agreeing_index or index
                end
            end
        end
        assert.is_not_nil(differing_index)
        assert.is_not_nil(agreeing_index)

        local parent = board.clone(puzzle)
        parent[differing_index] = first[differing_index]
        parent[agreeing_index] = first[agreeing_index]
        assert.are.equal(1, assert(solver.new(parent)):count_solutions(2))

        local workspace = assert(exact_search.new(parent, first, { search_budget = 50000 }))
        for _, index in ipairs({ differing_index, agreeing_index }) do
            assert(workspace:remove(math.floor((index - 1) / 9), (index - 1) % 9))
        end
        assert.are.equal(2, workspace:count_solutions(2))
        assert.is_nil(workspace.search_capped)
    end)

    it("restores exact state after completed, repeated, and capped searches", function()
        local solution = assert(board.from_string(SOLUTION))
        local puzzle = board.new()
        local workspace = assert(exact_search.new(puzzle, solution, { search_budget = 25 }))
        local before = snapshot(workspace)

        workspace:count_solutions(2)
        assert.is_true(workspace.search_capped)
        assert.are.same(before, snapshot(workspace))
        local first_nodes = workspace.search_nodes

        workspace:count_solutions(2)
        assert.is_true(workspace.search_capped)
        assert.are.equal(first_nodes, workspace.search_nodes)
        assert.are.same(before, snapshot(workspace))
    end)

    it("rejects malformed or mismatched known solutions and invalid transitions", function()
        local solution = assert(board.from_string(SOLUTION))
        local incomplete = board.clone(solution)
        incomplete[1] = 0
        local missing, missing_err = exact_search.new(incomplete, incomplete)
        assert.is_nil(missing)
        assert.is_string(missing_err)

        local mismatched = board.new()
        mismatched[1] = 1
        local invalid, invalid_err = exact_search.new(mismatched, solution)
        assert.is_nil(invalid)
        assert.is_string(invalid_err)

        local workspace = assert(exact_search.new(solution, solution))
        local alternative, alternative_err = workspace:has_alternative(0, 0)
        assert.is_nil(alternative)
        assert.is_string(alternative_err)
        local removed, remove_err = workspace:remove(-1, 0)
        assert.is_nil(removed)
        assert.is_string(remove_err)
    end)
end)
