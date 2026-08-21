package.path = "plugins/sudokuplus.koplugin/?.lua;" .. package.path

local flags = require("sudokuplus.core.techniques.flags")
local solve_path = require("sudokuplus.core.solve_path")

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
        assert.are.equal(0, result.non_single_count)
        assert.are.equal(0, result.score)
    end)

    it("differentiates beginner and easy for pure singles by clue count", function()
        local path = solve_path.new()
        solve_path.push(path, solve_path.placement_step(0, 0, 1, flags.NAKED_SINGLES))
        solve_path.push(path, solve_path.placement_step(0, 1, 2, flags.HIDDEN_SINGLES))

        local beginner_res = solve_path.classify(path, { clues = 38 })
        assert.are.equal("beginner", beginner_res.difficulty)
        assert.are.equal(0, beginner_res.non_single_count)
        assert.are.equal(22, beginner_res.score) -- 10 + 12

        local easy_res = solve_path.classify(path, { clues = 32 })
        assert.are.equal("easy", easy_res.difficulty)
        assert.are.equal(0, easy_res.non_single_count)
    end)

    it("classifies medium, hard, master, and expert paths", function()
        local medium_path = solve_path.new()
        solve_path.push(medium_path, solve_path.placement_step(0, 0, 1, flags.NAKED_SINGLES))
        solve_path.push(medium_path, solve_path.elimination_step(0, 1, 2, flags.LOCKED_CANDIDATES))
        solve_path.push(medium_path, solve_path.elimination_step(0, 2, 3, flags.NAKED_PAIRS))
        local medium_res = solve_path.classify(medium_path)
        assert.are.equal("medium", medium_res.difficulty)
        assert.are.equal(2, medium_res.non_single_count)

        local hard_path = solve_path.new()
        solve_path.push(hard_path, solve_path.elimination_step(0, 1, 2, flags.NAKED_TRIPLES))
        local hard_res = solve_path.classify(hard_path)
        assert.are.equal("hard", hard_res.difficulty)
        assert.are.equal(1, hard_res.non_single_count)

        local master_path = solve_path.new()
        solve_path.push(master_path, solve_path.elimination_step(0, 1, 2, flags.SKYSCRAPER))
        solve_path.push(master_path, solve_path.elimination_step(0, 2, 3, flags.XY_WING))
        local master_res = solve_path.classify(master_path)
        assert.are.equal("master", master_res.difficulty)
        assert.are.equal(2, master_res.non_single_count)

        local expert_path = solve_path.new()
        solve_path.push(expert_path, solve_path.elimination_step(0, 1, 2, flags.ALTERNATING_INFERENCE_CHAIN))
        local expert_res = solve_path.classify(expert_path)
        assert.are.equal("expert", expert_res.difficulty)
        assert.are.equal(1, expert_res.non_single_count)
    end)

    it("classifies the hardest flagged technique in a path", function()
        local path = solve_path.new()
        solve_path.push(path, solve_path.placement_step(0, 0, 1, flags.NAKED_SINGLES))
        solve_path.push(path, solve_path.elimination_step(0, 1, 2, flags.NAKED_PAIRS))
        solve_path.push(path, solve_path.elimination_step(0, 2, 3, flags.SKYSCRAPER))
        solve_path.push(path, solve_path.elimination_step(0, 3, 4, flags.ALTERNATING_INFERENCE_CHAIN))

        local result = solve_path.classify(path)

        assert.are.equal("expert", result.difficulty)
        assert.is_false(result.requires_guessing)
        assert.are.equal(flags.ALTERNATING_INFERENCE_CHAIN, result.hardest_flags)
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

    it("records hardest_flags and step number accurately for beginner paths", function()
        local path = solve_path.new()
        solve_path.push(path, solve_path.placement_step(0, 0, 1, flags.NAKED_SINGLES))
        solve_path.push(path, solve_path.placement_step(0, 1, 2, flags.HIDDEN_SINGLES))

        local result = solve_path.classify(path, { clues = 40 })

        assert.are.equal("beginner", result.difficulty)
        assert.is_false(result.requires_guessing)
        assert.are.equal(flags.NAKED_SINGLES, result.hardest_flags)
        assert.are.equal(0, result.hardest_step_number)
        assert.are.equal(0, result.non_single_count)
        assert.are.equal(22, result.score) -- 10 (naked) + 12 (hidden)
    end)

    it("accepts clue count as raw number in options and tests threshold boundaries", function()
        local path = solve_path.new()
        solve_path.push(path, solve_path.placement_step(0, 0, 1, flags.NAKED_SINGLES))

        assert.are.equal("easy", solve_path.classify(path, 36).difficulty)
        assert.are.equal("easy", solve_path.classify(path, 37).difficulty)
        assert.are.equal("beginner", solve_path.classify(path, 38).difficulty)
    end)

    it("extracts and orders unique technique IDs used in the solve path", function()
        local path = solve_path.new()
        solve_path.push(path, solve_path.placement_step(0, 0, 1, flags.NAKED_SINGLES))
        solve_path.push(path, solve_path.elimination_step(0, 1, 2, flags.NAKED_PAIRS))
        solve_path.push(path, solve_path.elimination_step(0, 2, 3, flags.LOCKED_CANDIDATES))
        solve_path.push(path, solve_path.elimination_step(0, 3, 4, flags.NAKED_PAIRS)) -- duplicate flag
        solve_path.push(path, solve_path.elimination_step(0, 4, 5, flags.ALTERNATING_INFERENCE_CHAIN))

        local result = solve_path.classify(path)
        assert.is_table(result.techniques)
        assert.are.same({
            "naked_singles",
            "locked_candidates",
            "naked_pairs",
            "aic",
        }, result.techniques)
    end)

    it("returns empty techniques list for empty solve path", function()
        local result = solve_path.classify(solve_path.new())
        assert.is_table(result.techniques)
        assert.are.same({}, result.techniques)
    end)

    it("orders all 19 techniques in canonical sequence regardless of push order", function()
        local path = solve_path.new()
        -- Push in reverse order
        for i = #flags.TECHNIQUES, 1, -1 do
            local tech = flags.TECHNIQUES[i]
            solve_path.push(path, solve_path.elimination_step(0, 0, 1, tech.flag))
        end

        local expected = {}
        for i, tech in ipairs(flags.TECHNIQUES) do
            expected[i] = tech.id
        end

        local result = solve_path.classify(path)
        assert.are.equal(19, #result.techniques)
        assert.are.same(expected, result.techniques)
    end)
end)
