package.path = "plugins/sudoku.koplugin/?.lua;" .. package.path

local flags = require("core.techniques.flags")
local solve_path = require("core.solve_path")

describe("core.solve_path", function()
    it("creates placement steps with defaults", function()
        local step = solve_path.placement_step(3, 4, 7)
        assert.are.equal("place", step.type)
        assert.are.equal(3, step.row)
        assert.are.equal(4, step.col)
        assert.are.equal(7, step.value)
        assert.are.equal(0, step.flags)
        assert.are.equal(0, step.candidates_eliminated)
        assert.are.equal(0, step.related_cell_count)
        assert.are.equal(0, step.difficulty_point)
        assert.is_nil(step.pattern)
        assert.is_nil(step.step_number)
    end)

    it("creates elimination steps with defaults", function()
        local step = solve_path.elimination_step(1, 2, 5)
        assert.are.equal("elim", step.type)
        assert.are.equal(1, step.row)
        assert.are.equal(2, step.col)
        assert.are.equal(5, step.value)
        assert.are.equal(0, step.flags)
        assert.is_nil(step.pattern)
    end)

    it("carries flags and pattern metadata", function()
        local pattern = { kind = "naked_pair", cells = { { 0, 1 }, { 0, 2 } }, values = { 5, 7 } }
        local step = solve_path.placement_step(0, 0, 5, 1, pattern)
        assert.are.equal(1, step.flags)
        assert.are.same(pattern, step.pattern)

        local elim = solve_path.elimination_step(0, 3, 5, 1, pattern)
        assert.are.equal("elim", elim.type)
        assert.are.same(pattern, elim.pattern)
    end)

    it("assigns sequential step numbers on push", function()
        local path = solve_path.new()
        solve_path.push(path, solve_path.placement_step(0, 0, 1))
        solve_path.push(path, solve_path.elimination_step(0, 1, 2))
        solve_path.push(path, solve_path.placement_step(1, 1, 3))
        assert.are.equal(0, path.steps[1].step_number)
        assert.are.equal(1, path.steps[2].step_number)
        assert.are.equal(2, path.steps[3].step_number)
    end)

    it("snapshots copy the steps", function()
        local path = solve_path.new()
        solve_path.push(path, solve_path.placement_step(0, 0, 1))
        local snap = solve_path.snapshot(path)
        assert.are.equal(1, #snap.steps)
        assert.are.same(path.steps[1], snap.steps[1])
        path.steps[1] = nil
        assert.are.equal(1, #snap.steps)
    end)

    it("snapshots deep-copy nested pattern metadata", function()
        local pattern = {
            kind = "fish",
            cells = { { 0, 1 } },
            values = { 5 },
            unit = { type = "row", index = 0 },
            base = { { type = "row", index = 0 } },
        }
        local path = solve_path.new()
        solve_path.push(path, solve_path.elimination_step(0, 2, 5, 1, pattern))
        local snap = solve_path.snapshot(path)

        snap.steps[1].pattern.cells[1][1] = 8
        snap.steps[1].pattern.values[1] = 9
        snap.steps[1].pattern.unit.index = 8
        snap.steps[1].pattern.base[1].type = "col"

        assert.are.equal(0, path.steps[1].pattern.cells[1][1])
        assert.are.equal(5, path.steps[1].pattern.values[1])
        assert.are.equal(0, path.steps[1].pattern.unit.index)
        assert.are.equal("row", path.steps[1].pattern.base[1].type)

        path.steps[1].pattern.cells[1][2] = 7
        assert.are.equal(1, snap.steps[1].pattern.cells[1][2])
    end)

    it("classifies an empty path as an easy path", function()
        local result = solve_path.classify(solve_path.new())

        assert.are.equal("easy", result.difficulty)
        assert.is_false(result.requires_guessing)
        assert.are.equal(0, result.hardest_flags)
        assert.is_nil(result.hardest_step_number)
    end)

    it("classifies the hardest flagged technique in a path", function()
        local path = solve_path.new()
        solve_path.push(path, solve_path.placement_step(0, 0, 1, flags.NAKED_SINGLES))
        solve_path.push(path, solve_path.elimination_step(0, 1, 2, flags.NAKED_PAIRS))
        solve_path.push(path, solve_path.elimination_step(0, 2, 3, flags.SKYSCRAPER))
        solve_path.push(path, solve_path.elimination_step(0, 3, 4, flags.W_WING))

        local result = solve_path.classify(path)

        assert.are.equal("expert", result.difficulty)
        assert.is_false(result.requires_guessing)
        assert.are.equal(flags.W_WING, result.hardest_flags)
        assert.are.equal(3, result.hardest_step_number)
    end)

    it("marks flagless placements as requiring guessing", function()
        local path = solve_path.new()
        solve_path.push(path, solve_path.placement_step(0, 0, 1, flags.NAKED_SINGLES))
        solve_path.push(path, solve_path.placement_step(0, 1, 2))

        local result = solve_path.classify(path)

        assert.are.equal("easy", result.difficulty)
        assert.is_true(result.requires_guessing)
        assert.are.equal(flags.NAKED_SINGLES, result.hardest_flags)
        assert.are.equal(0, result.hardest_step_number)
    end)
end)
