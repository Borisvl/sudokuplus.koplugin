package.path = "plugins/sudokuplus.koplugin/?.lua;" .. package.path

local bit = require("bit")
local board = require("core.board")
local game = require("game")

local PUZZLE = "530070000600195000098000060800060003400803001700020006060000280000419005000080079"
local SOLUTION = "534678912672195348198342567859761423426853791713924856961537284287419635345286179"

local function blank_cells(solution, cells)
    local chars = {}
    for i = 1, 81 do
        chars[i] = solution:sub(i, i)
    end
    for _, cell in ipairs(cells) do
        chars[cell[1] * 9 + cell[2] + 1] = "0"
    end
    return table.concat(chars)
end

-- SOLUTION with the two cells (0,6) and (0,7) blanked: winnable in two moves.
local PUZZLE_WIN = blank_cells(SOLUTION, { { 0, 6 }, { 0, 7 } })

local NAKED_SINGLE_PUZZLE = "385421967194756328627983145571892634839645271246137589462579813918364752753218490"
local NAKED_SINGLE_SOLUTION = "385421967194756328627983145571892634839645271246137589462579813918364752753218496"

local function new_game(puzzle, solution)
    local clock = { t = 1000 }
    local instance = assert(game.new({
        puzzle = board.from_string(puzzle or PUZZLE),
        solution = board.from_string(solution or SOLUTION),
        difficulty = "medium",
        now = function()
            return clock.t
        end,
    }))
    return instance, clock
end

local function digit_bit(v)
    return bit.lshift(1, v - 1)
end

local function cell_key(r, c)
    return r * 9 + c
end

local function has_note(instance, r, c, v)
    return bit.band(instance:get_notes(r, c), digit_bit(v)) ~= 0
end

local function count(set)
    local n = 0
    for _ in pairs(set or {}) do
        n = n + 1
    end
    return n
end

local function count_set(set)
    return count(set)
end

describe("game", function()
    it("rejects invalid construction arguments", function()
        local now = function()
            return 0
        end
        local puzzle = board.from_string(PUZZLE)
        local solution = board.from_string(SOLUTION)

        local no_puzzle, no_puzzle_err = game.new({ solution = solution, difficulty = "easy", now = now })
        assert.is_nil(no_puzzle)
        assert.is_string(no_puzzle_err)

        local no_solution, no_solution_err = game.new({ puzzle = puzzle, difficulty = "easy", now = now })
        assert.is_nil(no_solution)
        assert.is_string(no_solution_err)

        local inconsistent, inconsistent_err = game.new({
            puzzle = puzzle,
            solution = board.from_string(
                "999999999999999999999999999999999999999999999999999999999999999999999999999999999"
            ),
            difficulty = "easy",
            now = now,
        })
        assert.is_nil(inconsistent)
        assert.is_string(inconsistent_err)

        local duplicate, duplicate_err = game.new({
            puzzle = board.from_string(
                "530070000530070000098000060800060003400803001700020006060000280000419005000080079"
            ),
            solution = solution,
            difficulty = "easy",
            now = now,
        })
        assert.is_nil(duplicate)
        assert.is_string(duplicate_err)

        local bad_difficulty, bad_difficulty_err =
            game.new({ puzzle = puzzle, solution = solution, difficulty = "impossible", now = now })
        assert.is_nil(bad_difficulty)
        assert.is_string(bad_difficulty_err)

        local bad_clock, bad_clock_err = game.new({ puzzle = puzzle, solution = solution, difficulty = "easy" })
        assert.is_nil(bad_clock)
        assert.is_string(bad_clock_err)

        local bad_seed, bad_seed_err = game.new({
            puzzle = puzzle,
            solution = solution,
            difficulty = "easy",
            seed = 1.5,
            now = now,
        })
        assert.is_nil(bad_seed)
        assert.is_string(bad_seed_err)

        local bad_tech, bad_tech_err = game.new({
            puzzle = puzzle,
            solution = solution,
            difficulty = "easy",
            techniques = "naked_pairs",
            now = now,
        })
        assert.is_nil(bad_tech)
        assert.is_string(bad_tech_err)

        local bad_tech_item, bad_tech_item_err = game.new({
            puzzle = puzzle,
            solution = solution,
            difficulty = "easy",
            techniques = { 123 },
            now = now,
        })
        assert.is_nil(bad_tech_item)
        assert.is_string(bad_tech_item_err)
    end)

    it("stores an optional reproduction seed and techniques", function()
        local instance = new_game()
        assert.is_nil(instance.seed, "no seed by default")
        assert.is_nil(instance:techniques(), "nil techniques by default")

        local clock = { t = 1000 }
        local seeded = assert(game.new({
            puzzle = board.from_string(PUZZLE),
            solution = board.from_string(SOLUTION),
            difficulty = "easy",
            seed = 987654,
            techniques = { "locked_candidates", "naked_pairs" },
            now = function()
                return clock.t
            end,
        }))
        assert.are.equal(987654, seeded.seed, "the reproduction seed must be stored on the game")
        assert.are.same({ "locked_candidates", "naked_pairs" }, seeded:techniques())
    end)

    it("tracks which digits are fully placed on the board", function()
        -- Blank two of the 5s in the solution so digit 5 starts at 7 givens.
        local five_indices = {}
        for i = 1, 81 do
            if SOLUTION:sub(i, i) == "5" then
                five_indices[#five_indices + 1] = i
            end
        end
        local chars = {}
        for i = 1, 81 do
            chars[i] = SOLUTION:sub(i, i)
        end
        chars[five_indices[1]] = "0"
        chars[five_indices[2]] = "0"
        local clock = { t = 1000 }
        local instance = assert(game.new({
            puzzle = board.from_string(table.concat(chars)),
            solution = board.from_string(SOLUTION),
            difficulty = "medium",
            now = function()
                return clock.t
            end,
        }))

        assert.is_nil(instance:completed_digits()[5], "5 is not fully placed yet")
        assert.is_true(instance:completed_digits()[1], "1 is fully placed as givens")

        local r1, c1 = math.floor((five_indices[1] - 1) / 9), (five_indices[1] - 1) % 9
        local r2, c2 = math.floor((five_indices[2] - 1) / 9), (five_indices[2] - 1) % 9
        assert.is_true(instance:place(r1, c1, 5))
        assert.is_true(instance:place(r2, c2, 5))
        assert.is_true(instance:completed_digits()[5], "5 completes once placed nine times")

        assert.is_true(instance:erase(r1, c1))
        assert.is_nil(instance:completed_digits()[5], "erasing breaks the completion")
    end)

    it("starts with empty notes unless auto-fill is enabled", function()
        local instance = new_game()
        local puzzle = board.from_string(PUZZLE)

        for r = 0, 8 do
            for c = 0, 8 do
                assert.are.equal(0, instance:get_notes(r, c), "empty cell must start without notes")
            end
        end

        local clock = { t = 1000 }
        local filled = assert(game.new({
            puzzle = board.from_string(PUZZLE),
            solution = board.from_string(SOLUTION),
            difficulty = "medium",
            now = function()
                return clock.t
            end,
            autofill_notes = true,
        }))
        for r = 0, 8 do
            for c = 0, 8 do
                if board.is_empty(puzzle, r, c) then
                    assert.is_true(filled:get_notes(r, c) ~= 0, "auto-fill must seed candidate notes")
                else
                    assert.are.equal(0, filled:get_notes(r, c), "given cell must not have notes")
                end
            end
        end

        assert.are.equal(0, instance:revision())
        assert.are.equal(0, instance:mistakes())
        assert.are.equal(0, instance:check_errors())
        assert.are.equal("medium", instance:difficulty())
        assert.is_false(instance:is_finished())
    end)

    it("rejects a non-boolean autofill_notes option", function()
        local clock = { t = 1000 }
        local instance, err = game.new({
            puzzle = board.from_string(PUZZLE),
            solution = board.from_string(SOLUTION),
            difficulty = "medium",
            now = function()
                return clock.t
            end,
            autofill_notes = "yes",
        })
        assert.is_nil(instance)
        assert.is_string(err)
    end)

    it("locks given cells against every kind of mutation", function()
        local instance = new_game()

        local place_ok, place_err = instance:place(0, 0, 4)
        assert.is_nil(place_ok)
        assert.is_string(place_err)

        local erase_ok, erase_err = instance:erase(0, 0)
        assert.is_nil(erase_ok)
        assert.is_string(erase_err)

        local toggle_ok, toggle_err = instance:toggle_note(0, 0, 4)
        assert.is_nil(toggle_ok)
        assert.is_string(toggle_err)

        local clear_ok, clear_err = instance:clear_notes(0, 0)
        assert.is_nil(clear_ok)
        assert.is_string(clear_err)

        assert.are.equal(0, instance:revision())
    end)

    it("places values and reports rule-legal entries without conflicts", function()
        local instance = new_game()

        assert.is_true(instance:place(0, 2, 4))
        assert.are.equal(4, instance:get(0, 2))
        assert.are.equal(0, instance:get_notes(0, 2))
        assert.are.equal(0, #instance:conflicts())
        assert.are.equal(0, instance:mistakes())
        assert.are.equal(1, instance:revision())
    end)

    it("auto-cleans the placed digit from peer notes and prunes to legal candidates", function()
        local instance = new_game()

        assert.is_true(instance:toggle_note(0, 3, 2))
        assert.is_true(instance:toggle_note(1, 2, 2))
        assert.is_true(instance:toggle_note(1, 1, 2))
        assert.is_true(instance:toggle_note(1, 7, 2))
        assert.is_true(has_note(instance, 0, 3, 2))
        assert.is_true(instance:place(0, 2, 2))

        assert.is_false(has_note(instance, 0, 3, 2), "row peer note cleaned")
        assert.is_false(has_note(instance, 1, 2, 2), "column peer note cleaned")
        assert.is_false(has_note(instance, 1, 1, 2), "box peer note cleaned")
        assert.is_true(has_note(instance, 1, 7, 2), "non-peer notes are untouched")
    end)

    it("preserves manually removed candidates when a filled cell is erased", function()
        local instance = new_game()

        assert.is_true(instance:toggle_note(0, 2, 4))
        assert.is_true(has_note(instance, 0, 2, 4))
        assert.is_true(instance:toggle_note(0, 2, 4))
        assert.is_false(has_note(instance, 0, 2, 4))
        assert.is_true(instance:place(0, 2, 2))
        assert.is_true(instance:erase(0, 2))

        assert.is_false(has_note(instance, 0, 2, 4))
    end)

    it("restores auto-cleaned peer candidates when a filled cell is erased", function()
        local instance = new_game()

        assert.is_true(instance:toggle_note(0, 3, 2))
        assert.is_true(has_note(instance, 0, 3, 2))
        assert.is_true(instance:place(0, 2, 2))
        assert.is_false(has_note(instance, 0, 3, 2))
        assert.is_true(instance:erase(0, 2))

        assert.is_true(has_note(instance, 0, 3, 2))
    end)

    it("never re-adds notes to peers the user did not write", function()
        local instance = new_game()

        assert.is_true(instance:place(0, 2, 2))
        assert.is_true(instance:place(0, 2, 5))
        assert.are.equal(0, instance:get_notes(0, 3), "no phantom note when replacing a digit")
        assert.are.equal(0, instance:get_notes(1, 2))
        assert.are.equal(0, instance:get_notes(1, 1))
        assert.is_true(instance:undo())

        assert.is_true(instance:erase(0, 2))
        assert.are.equal(0, instance:get_notes(0, 3), "no phantom note when erasing a digit")
        assert.are.equal(0, instance:get_notes(1, 2))
        assert.are.equal(0, instance:get_notes(1, 1))
    end)

    it("erasing restores the cell's previous note state", function()
        local instance = new_game()

        assert.is_true(instance:toggle_note(0, 2, 4))
        assert.is_true(instance:toggle_note(0, 2, 1))
        assert.is_true(has_note(instance, 0, 2, 4))
        assert.is_true(instance:place(0, 2, 2))
        assert.are.equal(0, instance:get_notes(0, 2))
        assert.is_true(instance:erase(0, 2))

        assert.is_true(has_note(instance, 0, 2, 4), "previous notes restored")
        assert.is_true(has_note(instance, 0, 2, 1), "previous notes restored")
        assert.is_false(has_note(instance, 0, 2, 2), "the erased digit is not a note")
    end)

    it("erasing a digit placed in an untouched cell leaves its notes empty", function()
        local instance = new_game()

        assert.is_true(instance:place(0, 2, 2))
        assert.is_true(instance:erase(0, 2))

        assert.are.equal(0, instance:get_notes(0, 2))
    end)

    it("marks live conflicts only for rule violations and counts mistakes per entry", function()
        local instance = new_game()

        assert.is_true(instance:place(0, 7, 5))
        assert.are.equal(5, instance:get(0, 7))

        local conflicts = instance:conflicts()
        assert.are.equal(2, #conflicts)
        local found = {}
        for _, cell in ipairs(conflicts) do
            found[cell[1] * 9 + cell[2]] = true
        end
        assert.is_true(found[0 * 9 + 0], "given twin is part of the conflict")
        assert.is_true(found[0 * 9 + 7], "placed duplicate is part of the conflict")
        assert.are.equal(1, instance:mistakes(), "one violating entry created")

        assert.is_true(instance:erase(0, 7))
        assert.are.equal(0, #instance:conflicts())
        assert.are.equal(1, instance:mistakes(), "mistakes are cumulative")
    end)

    it("replaces an existing user entry without creating a new history depth", function()
        local instance = new_game()

        assert.is_true(instance:place(0, 2, 4))
        assert.is_true(instance:place(0, 2, 2))
        assert.are.equal(2, instance:get(0, 2))

        assert.is_true(instance:undo())
        assert.are.equal(4, instance:get(0, 2))
        assert.is_true(instance:undo())
        assert.are.equal(0, instance:get(0, 2))
    end)

    it("rejects out-of-range coordinates and values", function()
        local instance = new_game()

        assert.is_nil(instance:place(9, 0, 4))
        assert.is_nil(instance:place(0, -1, 4))
        assert.is_nil(instance:place(0, 2, 0))
        assert.is_nil(instance:place(0, 2, 10))
        assert.is_nil(instance:toggle_note(0, 2, 10))
        assert.is_nil(instance:get_notes(0, 12))
    end)

    it("rejects illegal note toggles and allows user removals of any candidate", function()
        local instance = new_game()

        assert.is_true(instance:place(0, 2, 2))
        local ok, err = instance:toggle_note(0, 3, 2)
        assert.is_nil(ok)
        assert.is_string(err)

        assert.is_true(instance:toggle_note(0, 3, 6))
        assert.is_true(has_note(instance, 0, 3, 6))
        assert.is_true(instance:toggle_note(0, 3, 6))
        assert.is_false(has_note(instance, 0, 3, 6))
    end)

    it("clears all notes of a cell", function()
        local instance = new_game()

        assert.is_true(instance:toggle_note(0, 3, 6))
        assert.is_true(has_note(instance, 0, 3, 6))
        assert.is_true(instance:clear_notes(0, 3))
        assert.are.equal(0, instance:get_notes(0, 3))

        assert.is_true(instance:undo())
        assert.is_true(has_note(instance, 0, 3, 6))
    end)

    it("reports cells that block deduction because the user cleared their notes", function()
        local instance = new_game()

        assert.are.same({}, instance:notes_needed(), "untouched cells never need notes")

        -- the user removed a candidate: ground truth, deduction cannot use the cell
        assert.is_true(instance:toggle_note(0, 3, 6))
        assert.is_true(instance:toggle_note(0, 3, 6))
        assert.are.same({ { 0, 3 } }, instance:notes_needed())

        -- clearing non-empty notes also marks the cell as ground truth
        assert.is_true(instance:toggle_note(8, 0, 1))
        assert.is_true(instance:clear_notes(8, 0))
        assert.are.same({ { 0, 3 }, { 8, 0 } }, instance:notes_needed())

        -- filling the cell removes it from the list
        assert.is_true(instance:place(0, 3, 6))
        assert.are.same({ { 8, 0 } }, instance:notes_needed())

        -- undoing the fill restores the cleared-notes state
        assert.is_true(instance:undo())
        assert.are.same({ { 0, 3 }, { 8, 0 } }, instance:notes_needed())
    end)

    it("does not treat an already-empty clear or a place/erase cycle as user-cleared", function()
        local instance = new_game()

        assert.is_true(instance:clear_notes(0, 3))
        assert.are.same({}, instance:notes_needed(), "clearing an untouched empty cell is a no-op")

        assert.is_true(instance:place(0, 2, 2))
        assert.is_true(instance:erase(0, 2))
        assert.are.same({}, instance:notes_needed(), "erase restores the previous (empty) note state")
    end)

    it("lists cells holding a digit as a value or in notes", function()
        local instance = new_game()

        -- givens: 6 at (1,0), (2,7), (3,4), (5,8), (6,1)
        local set = instance:digit_cells(6)
        assert.are.equal(5, count_set(set))
        assert.is_not_nil(set[1 * 9 + 0])
        assert.is_not_nil(set[2 * 9 + 7])
        assert.is_not_nil(set[3 * 9 + 4])
        assert.is_not_nil(set[5 * 9 + 8])
        assert.is_not_nil(set[6 * 9 + 1])
        assert.is_nil(set[0 * 9 + 3], "empty cells without the digit in notes are excluded")

        -- a note on an empty cell adds it to the set
        assert.is_true(instance:toggle_note(0, 3, 6))
        assert.is_not_nil(instance:digit_cells(6)[0 * 9 + 3])
        assert.are.equal(6, count_set(instance:digit_cells(6)))

        -- placing the digit keeps the cell in the set (as a value now)
        assert.is_true(instance:place(0, 3, 6))
        assert.is_not_nil(instance:digit_cells(6)[0 * 9 + 3])
        assert.are.equal(6, count_set(instance:digit_cells(6)))

        -- undoing the placement restores the note state
        assert.is_true(instance:undo())
        assert.is_not_nil(instance:digit_cells(6)[0 * 9 + 3])
        assert.are.equal(6, count_set(instance:digit_cells(6)))

        -- erasing a note removes the cell again
        assert.is_true(instance:toggle_note(0, 3, 6))
        assert.are.equal(5, count_set(instance:digit_cells(6)))
    end)

    it("validates the digit for digit_cells", function()
        local instance = new_game()
        assert.is_nil(instance:digit_cells(0))
        assert.is_nil(instance:digit_cells(10))
        assert.is_nil(instance:digit_cells("6"))
    end)

    it("undoes and redoes moves restoring notes exactly", function()
        local instance = new_game()

        assert.is_true(instance:toggle_note(0, 3, 2))
        assert.is_true(instance:place(0, 2, 2))
        assert.is_false(has_note(instance, 0, 3, 2), "placed digit auto-cleaned")
        assert.is_true(instance:toggle_note(0, 3, 6))

        assert.is_true(instance:undo())
        assert.is_false(has_note(instance, 0, 3, 6), "note toggle undone")
        assert.is_true(instance:undo())
        assert.are.equal(0, instance:get(0, 2))
        assert.is_true(has_note(instance, 0, 3, 2), "auto-cleaned note restored")
        assert.is_true(instance:undo())
        assert.is_false(has_note(instance, 0, 3, 2), "note toggle undone")

        local no_undo, undo_err = instance:undo()
        assert.is_nil(no_undo)
        assert.is_string(undo_err)

        assert.is_true(instance:redo())
        assert.is_true(has_note(instance, 0, 3, 2))
        assert.is_true(instance:redo())
        assert.are.equal(2, instance:get(0, 2))
        assert.is_false(has_note(instance, 0, 3, 2))
        assert.is_true(instance:redo())
        assert.is_true(has_note(instance, 0, 3, 6))
    end)

    it("restores notes on redo of a cell replacement (B1)", function()
        local instance = new_game()

        -- Cell (0, 3) gets note 2
        assert.is_true(instance:toggle_note(0, 3, 2))
        assert.is_true(has_note(instance, 0, 3, 2))

        -- Place 2 at (0, 2) -> auto-cleans note 2 from (0, 3)
        assert.is_true(instance:place(0, 2, 2))
        assert.is_false(has_note(instance, 0, 3, 2), "placing 2 auto-cleans note 2")

        -- Replace (0, 2) with 5 -> restores note 2 at (0, 3)
        assert.is_true(instance:place(0, 2, 5))
        assert.are.equal(5, instance:get(0, 2))
        assert.is_true(has_note(instance, 0, 3, 2), "replacing 2 with 5 restores note 2")

        -- Undo replacement -> reverts to 2 at (0, 2), removing note 2 from (0, 3)
        assert.is_true(instance:undo())
        assert.are.equal(2, instance:get(0, 2))
        assert.is_false(has_note(instance, 0, 3, 2), "undoing replace removes restored note")

        -- Redo replacement -> reverts to 5 at (0, 2), note 2 MUST be restored at (0, 3)
        assert.is_true(instance:redo())
        assert.are.equal(5, instance:get(0, 2))
        assert.is_true(has_note(instance, 0, 3, 2), "redoing replace re-restores note 2")
    end)

    it("clears the redo stack on a new move", function()
        local instance = new_game()

        assert.is_true(instance:place(0, 2, 2))
        assert.is_true(instance:undo())
        assert.is_true(instance:can_redo())
        assert.is_true(instance:toggle_note(0, 3, 6))
        assert.is_false(instance:can_redo())
        local no_redo, redo_err = instance:redo()
        assert.is_nil(no_redo)
        assert.is_string(redo_err)
    end)

    it("keeps the timer paused while suspended", function()
        local instance, clock = new_game()

        assert.are.equal(0, instance:elapsed())
        clock.t = 1010
        assert.are.equal(10, instance:elapsed())

        assert.is_true(instance:pause())
        clock.t = 1020
        assert.are.equal(10, instance:elapsed())

        assert.is_true(instance:resume())
        clock.t = 1030
        assert.are.equal(20, instance:elapsed())

        assert.is_true(instance:resume(), "resuming a running timer is a no-op")
        clock.t = 1035
        assert.are.equal(25, instance:elapsed())
    end)

    it("matches the completion record duration to the stopped timer", function()
        local times = { 1000, 1010, 1020, 1030 }
        local instance = assert(game.new({
            puzzle = board.from_string(PUZZLE_WIN),
            solution = board.from_string(SOLUTION),
            difficulty = "medium",
            now = function()
                local time = times[1]
                table.remove(times, 1)
                return time
            end,
        }))

        assert.is_true(instance:place(0, 6, 9))
        assert.is_true(instance:place(0, 7, 1))
        local record = assert(instance:finish())

        assert.are.equal(record.duration, instance:elapsed())
    end)

    it("reveals all wrong numbers and counts each cell once until fixed", function()
        local instance = new_game()

        local wrong = instance:check_for_errors()
        assert.are.equal(0, #wrong)
        assert.are.equal(0, instance:check_errors())

        assert.is_true(instance:place(0, 2, 2))

        local first_check = instance:check_for_errors()
        assert.are.equal(1, #first_check)
        assert.are.same({ 0, 2 }, first_check[1])
        assert.are.equal(1, instance:check_errors())

        local second_check = instance:check_for_errors()
        assert.are.equal(1, #second_check)
        assert.are.equal(1, instance:check_errors(), "repeated checks do not re-count")

        assert.is_true(instance:erase(0, 2))
        assert.are.equal(0, #instance:check_for_errors())
        assert.are.equal(0, #instance:revealed())

        assert.is_true(instance:place(0, 2, 2))
        instance:check_for_errors()
        assert.are.equal(2, instance:check_errors(), "re-break re-counts after a fix")
    end)

    it("clears a revealed error immediately when the cell is fixed", function()
        local instance = new_game()

        assert.is_true(instance:place(0, 2, 2))
        assert.are.equal(1, #instance:check_for_errors())
        assert.are.equal(1, #instance:revealed())

        assert.is_true(instance:place(0, 2, 4))
        assert.are.equal(0, #instance:revealed())

        assert.is_true(instance:place(0, 2, 2))
        assert.are.equal(1, #instance:check_for_errors())
        assert.are.equal(2, instance:check_errors())
    end)

    it("detects the win only when the board matches the solution", function()
        local instance = new_game(NAKED_SINGLE_PUZZLE, NAKED_SINGLE_SOLUTION)

        assert.is_false(instance:is_won())
        assert.is_true(instance:place(8, 8, 6))
        assert.is_true(instance:is_won())

        assert.is_not_nil(instance:finish())
        assert.is_true(instance:is_finished())
    end)

    it("finish() produces the game record and locks the board", function()
        local instance, clock = new_game(NAKED_SINGLE_PUZZLE, NAKED_SINGLE_SOLUTION)

        assert.is_true(instance:place(8, 8, 6))
        clock.t = 1337
        local record = instance:finish()

        assert.is_not_nil(record)
        assert.are.equal("finished", record.status)
        assert.are.equal("medium", record.difficulty)
        assert.are.equal(337, record.duration)
        assert.are.equal(1337, record.ended_at)
        assert.are.equal(0, record.mistakes)
        assert.are.equal(0, record.check_errors)
        assert.are.same({}, record.hints)

        local move_ok, move_err = instance:place(0, 2, 4)
        assert.is_nil(move_ok)
        assert.is_string(move_err)
        local undo_ok, undo_err = instance:undo()
        assert.is_nil(undo_ok)
        assert.is_string(undo_err)
        local second_finish, second_finish_err = instance:finish()
        assert.is_nil(second_finish)
        assert.is_string(second_finish_err)
    end)

    it("finish() rejects an unsolved board", function()
        local instance = new_game()
        local ok, err = instance:finish()
        assert.is_nil(ok)
        assert.is_string(err)
    end)

    it("give_up() records separately and locks the board", function()
        local instance, clock = new_game()

        assert.is_true(instance:place(0, 2, 2))
        instance:check_for_errors()
        assert.is_true(instance:place(0, 7, 5))
        clock.t = 2000
        local record = instance:give_up()

        assert.is_not_nil(record)
        assert.are.equal("give_up", record.status)
        assert.are.equal(1000, record.duration)
        assert.are.equal(1, record.mistakes)
        assert.are.equal(1, record.check_errors)
        assert.is_true(instance:is_finished())

        local again, again_err = instance:give_up()
        assert.is_nil(again)
        assert.is_string(again_err)
    end)

    it("returns a hint, records the missed strategy, and applies its action", function()
        local instance = new_game(NAKED_SINGLE_PUZZLE, NAKED_SINGLE_SOLUTION)

        local result, err = instance:hint()
        assert.is_nil(err)
        assert.is_not_nil(result)
        assert.are.equal("available", result.status)
        assert.are.equal("naked_singles", result.technique.id)
        assert.are.same({ 8, 8 }, { result.action.row, result.action.col })

        local hints = instance:hints()
        assert.are.equal(1, #hints)
        assert.are.equal("naked_singles", hints[1].technique)
        assert.is_string(hints[1].id)
        assert.is_true(hints[1].flag ~= 0)

        assert.is_true(instance:apply_action(result.action))
        assert.are.equal(6, instance:get(8, 8))
        assert.is_true(instance:is_won())

        local exhausted = instance:hint()
        assert.are.equal("none", exhausted.status)
        assert.are.equal(1, #instance:hints(), "no-hint results are not recorded")
    end)

    it("rejects a hint action after the game revision changes", function()
        local instance = new_game(NAKED_SINGLE_PUZZLE, NAKED_SINGLE_SOLUTION)
        local result = assert(instance:hint())

        assert.is_true(instance:place(8, 8, 5))
        local ok, err = instance:apply_action(result.action)

        assert.is_nil(ok)
        assert.is_string(err)
        assert.are.equal(5, instance:get(8, 8))
    end)

    it("blocks hints while the board has live conflicts", function()
        local instance = new_game()

        assert.is_true(instance:place(0, 3, 5))
        local result, err = instance:hint()
        assert.is_nil(result)
        assert.is_string(err)
        assert.are.equal(0, #instance:hints())
    end)

    it("substitutes board-legal candidates for untouched cells when hinting", function()
        local instance = new_game(NAKED_SINGLE_PUZZLE, NAKED_SINGLE_SOLUTION)

        -- no notes anywhere: the hint engine must assume fully filled
        -- candidates for untouched cells
        local result, err = instance:hint()
        assert.is_nil(err)
        assert.are.equal("available", result.status)
        assert.are.equal("naked_singles", result.technique.id)
        assert.are.same({ 8, 8 }, { result.action.row, result.action.col })
    end)

    it("treats started notes as ground truth for hinting", function()
        local instance = new_game(NAKED_SINGLE_PUZZLE, NAKED_SINGLE_SOLUTION)

        -- the user touched (8,8) and removed its only candidate
        assert.is_true(instance:toggle_note(8, 8, 6))
        assert.is_true(instance:toggle_note(8, 8, 6))
        assert.is_false(has_note(instance, 8, 8, 6))

        local result, err = instance:hint()
        assert.is_nil(err)
        assert.are.equal("note_error", result.status)
        assert.are.equal(0, #instance:hints())
    end)

    it("blocks hints when the board diverges from the solution", function()
        local instance = new_game()

        assert.is_true(instance:place(0, 2, 2))
        local result, err = instance:hint()
        assert.is_nil(result)
        assert.is_string(err)
        assert.are.equal(0, #instance:hints())
    end)

    it("surfaces note errors and does not record them as missed strategies", function()
        local instance = new_game()

        assert.is_true(instance:toggle_note(0, 2, 4))
        assert.is_true(instance:toggle_note(0, 2, 4))
        assert.is_false(has_note(instance, 0, 2, 4), "solution candidate removed by the user")
        local result, err = instance:hint()
        assert.is_nil(err)
        assert.is_not_nil(result)
        assert.are.equal("note_error", result.status)
        assert.is_true(#result.errors > 0)
        assert.are.equal(0, #instance:hints())
    end)

    it("applies elimination actions as undoable note changes", function()
        local instance = new_game()

        assert.is_true(instance:toggle_note(0, 2, 4))
        assert.is_true(has_note(instance, 0, 2, 4))

        assert.is_true(instance:apply_action({ type = "elim", row = 0, col = 2, value = 4 }))
        assert.is_false(has_note(instance, 0, 2, 4))
        assert.is_true(instance:undo())
        assert.is_true(has_note(instance, 0, 2, 4))
    end)

    it("counts mistakes into the finish record", function()
        local instance, clock = new_game(PUZZLE_WIN, SOLUTION)

        assert.is_true(instance:place(0, 6, 5))
        assert.are.equal(1, instance:mistakes(), "duplicate of a given is a mistake")

        assert.is_true(instance:erase(0, 6))
        assert.is_true(instance:place(0, 6, 9))
        assert.is_true(instance:place(0, 7, 1))
        assert.is_true(instance:is_won())

        clock.t = 5000
        local record = instance:finish()
        assert.are.equal("finished", record.status)
        assert.are.equal(1, record.mistakes)
        assert.are.equal(0, record.check_errors)
        assert.are.equal(4000, record.duration)
    end)

    describe("stats metadata", function()
        it("stores an optional game id and rejects a non-integer one", function()
            local instance = new_game()
            assert.is_nil(instance.id, "no id by default")

            local clock = { t = 1000 }
            local with_id = assert(game.new({
                puzzle = board.from_string(PUZZLE),
                solution = board.from_string(SOLUTION),
                difficulty = "easy",
                id = 42,
                now = function()
                    return clock.t
                end,
            }))
            assert.are.equal(42, with_id.id)

            local bad, err = game.new({
                puzzle = board.from_string(PUZZLE),
                solution = board.from_string(SOLUTION),
                difficulty = "easy",
                id = 1.5,
                now = function()
                    return clock.t
                end,
            })
            assert.is_nil(bad)
            assert.is_string(err)
        end)

        it("is not started until the first number or note is added", function()
            local instance = new_game()
            assert.is_false(instance:is_started())
            assert.is_nil(instance:started_at())

            assert.is_true(instance:toggle_note(0, 3, 6))
            assert.is_true(instance:is_started(), "a note starts the game")
            assert.is_not_nil(instance:started_at())

            local note_only = new_game()
            assert.is_true(note_only:clear_notes(0, 3))
            assert.is_false(note_only:is_started(), "clearing an untouched cell is not a start")

            local place_only = new_game()
            assert.is_true(place_only:place(0, 2, 2))
            assert.is_true(place_only:is_started(), "a placement starts the game")
        end)

        it("counts moves and reports progress", function()
            local instance = new_game()
            assert.are.equal(0, instance:move_count())

            assert.is_true(instance:place(0, 2, 2))
            assert.is_true(instance:toggle_note(0, 3, 6))
            assert.is_true(instance:erase(0, 2))
            assert.is_true(instance:undo())
            assert.are.equal(3, instance:move_count(), "undo and redo do not add to the move count")
        end)

        it("reports progress as filled, correct and clues", function()
            local instance = new_game(NAKED_SINGLE_PUZZLE, NAKED_SINGLE_SOLUTION)

            local p0 = instance:progress()
            assert.are.equal(0, p0.filled)
            assert.are.equal(80, p0.clues)
            assert.are.equal(81, p0.total)

            assert.is_true(instance:place(8, 8, 6))
            local p1 = instance:progress()
            assert.are.equal(1, p1.filled)
            assert.are.equal(1, p1.correct)

            assert.is_true(instance:erase(8, 8))
            assert.is_true(instance:place(8, 8, 5))
            local p2 = instance:progress()
            assert.are.equal(1, p2.filled)
            assert.are.equal(0, p2.correct, "a wrong entry counts as filled but not correct")
        end)

        it("builds an in-progress record for the game log", function()
            local clock = { t = 1000 }
            local instance = assert(game.new({
                puzzle = board.from_string(NAKED_SINGLE_PUZZLE),
                solution = board.from_string(NAKED_SINGLE_SOLUTION),
                difficulty = "expert",
                id = 7,
                seed = 123,
                now = function()
                    return clock.t
                end,
            }))
            assert.is_true(instance:place(8, 8, 6))
            clock.t = 1500

            local record = instance:started_record()
            assert.are.equal("in_progress", record.status)
            assert.are.equal(7, record.id)
            assert.are.equal(123, record.seed)
            assert.are.equal("expert", record.difficulty)
            assert.are.equal(500, record.duration)
            assert.are.equal(1, record.moves)
            assert.are.equal(1, record.filled)
            assert.are.equal(1, record.correct)
            assert.are.equal(1000, record.started_at)
            assert.is_nil(record.ended_at)
            assert.are.equal(NAKED_SINGLE_PUZZLE, record.puzzle)
            assert.are.equal(NAKED_SINGLE_SOLUTION, record.solution)
            assert.are.equal(board.to_string(instance.board), record.board)
            assert.are.same({}, record.hints)
        end)

        it("carries the id, seed and progress into the finish record", function()
            local clock = { t = 1000 }
            local instance = assert(game.new({
                puzzle = board.from_string(NAKED_SINGLE_PUZZLE),
                solution = board.from_string(NAKED_SINGLE_SOLUTION),
                difficulty = "easy",
                id = 11,
                seed = 4242,
                now = function()
                    return clock.t
                end,
            }))
            assert.is_true(instance:place(8, 8, 6))
            clock.t = 1337

            local record = instance:finish()
            assert.are.equal("finished", record.status)
            assert.are.equal(11, record.id)
            assert.are.equal(4242, record.seed)
            assert.are.equal(337, record.duration)
            assert.are.equal(1337, record.ended_at)
            assert.are.equal(1000, record.started_at)
            assert.are.equal(1, record.moves)
            assert.are.equal(1, record.filled)
            assert.are.equal(1, record.correct)
            assert.are.equal(NAKED_SINGLE_PUZZLE, record.puzzle)
            assert.are.equal(NAKED_SINGLE_SOLUTION, record.solution)
        end)

        it("keeps the started timestamp across restore", function()
            local clock = { t = 1000 }
            local instance = assert(game.new({
                puzzle = board.from_string(PUZZLE),
                solution = board.from_string(SOLUTION),
                difficulty = "easy",
                now = function()
                    return clock.t
                end,
            }))
            assert.is_true(instance:place(0, 2, 2))
            assert.are.equal(1000, instance:started_at())

            local restored, err = game.restore(instance:serialize(), {
                now = function()
                    return clock.t
                end,
            })
            assert.is_not_nil(restored, err)
            assert.are.equal(1000, restored:started_at(), "the started timestamp survives save/restore")
            assert.is_true(restored:is_started())
        end)
    end)

    describe("affected_cells", function()
        it("rejects invalid arguments", function()
            local instance = new_game()
            assert.is_nil(instance:affected_cells(-1, 0, 5))
            assert.is_nil(instance:affected_cells(0, 9, 5))
            assert.is_nil(instance:affected_cells(0, 0, 0))
            assert.is_nil(instance:affected_cells(0, 0, 10))
        end)

        it("includes the cell itself and every peer holding the value", function()
            local instance = new_game()
            -- (0,5) is empty; 3 sits at (0,1) in its row and (4,5) in its column
            local affected = instance:affected_cells(0, 5, 3)
            assert.is_not_nil(affected[cell_key(0, 5)])
            assert.is_not_nil(affected[cell_key(0, 1)], "row peer holding 3")
            assert.is_not_nil(affected[cell_key(4, 5)], "column peer holding 3")
            assert.are.equal(3, count(affected))
        end)

        it("includes peers whose notes hold the value", function()
            local instance = new_game()
            assert.is_true(instance:toggle_note(0, 3, 2))
            -- (0,4) is empty; (5,4) holds 2; (0,3) notes 2
            local affected = instance:affected_cells(0, 4, 2)
            assert.is_not_nil(affected[cell_key(0, 4)])
            assert.is_not_nil(affected[cell_key(5, 4)])
            assert.is_not_nil(affected[cell_key(0, 3)], "peer noting 2")
            assert.are.equal(3, count(affected))
        end)

        it("excludes cells outside the row, column and box of the target", function()
            local instance = new_game()
            assert.is_true(instance:toggle_note(8, 0, 2))
            local affected = instance:affected_cells(0, 4, 2)
            assert.is_nil(affected[cell_key(8, 0)], "(8,0) is not a peer of (0,4)")
            assert.is_nil(affected[cell_key(0, 0)], "no 2 in the unit and no note")
            assert.is_not_nil(affected[cell_key(5, 4)], "(5,4) holds 2 in the column")
            assert.are.equal(2, count(affected))
        end)

        it("includes the peers the last placement cleaned, even after the note is gone", function()
            local instance = new_game()
            assert.is_true(instance:toggle_note(0, 3, 2))
            assert.is_true(instance:place(0, 6, 2), "cleans note 2 from (0,3)")
            assert.is_false(has_note(instance, 0, 3, 2))
            -- erasing (0,6) may restore the cleaned note on (0,3)
            local affected = instance:affected_cells(0, 6, 2)
            assert.is_not_nil(affected[cell_key(0, 6)])
            assert.is_not_nil(affected[cell_key(6, 6)], "peer holding 2")
            assert.is_not_nil(affected[cell_key(0, 3)], "restored peer from the placement")
            assert.are.equal(3, count(affected))
        end)

        it("includes peers holding the value being replaced", function()
            local instance = new_game()
            assert.is_true(instance:place(0, 6, 2), "2 at (6,6) makes the placement a live conflict")
            -- replacing 2 with 4 at (0,6) clears (6,6)'s conflict highlight
            local affected = instance:affected_cells(0, 6, 4)
            assert.is_not_nil(affected[cell_key(0, 6)])
            assert.is_not_nil(affected[cell_key(6, 6)], "peer holding the replaced value 2")
            assert.are.equal(2, count(affected))
        end)
    end)

    describe("undo and redo affected cells", function()
        it("returns an empty set without history", function()
            local instance = new_game()
            assert.are.equal(0, count(instance:undo_affected_cells()))
            assert.are.equal(0, count(instance:redo_affected_cells()))
        end)

        it("undo of a place covers the cell, its value peers and cleaned notes", function()
            local instance = new_game()
            assert.is_true(instance:toggle_note(0, 3, 2))
            assert.is_true(instance:place(0, 6, 2))
            assert.is_true(instance:undo())
            local affected = instance:undo_affected_cells()
            assert.is_not_nil(affected[cell_key(0, 6)])
            assert.is_not_nil(affected[cell_key(6, 6)], "peer holding the placed value")
            assert.is_not_nil(affected[cell_key(0, 3)], "peer whose cleaned note is restored")
            assert.are.equal(3, count(affected))
        end)

        it("redo of the place covers the same cells", function()
            local instance = new_game()
            assert.is_true(instance:toggle_note(0, 3, 2))
            assert.is_true(instance:place(0, 6, 2))
            assert.is_true(instance:undo())
            assert.is_true(instance:redo())
            local affected = instance:redo_affected_cells()
            assert.is_not_nil(affected[cell_key(0, 6)])
            assert.is_not_nil(affected[cell_key(6, 6)])
            assert.is_not_nil(affected[cell_key(0, 3)], "peer whose note is cleaned again")
            assert.are.equal(3, count(affected))
        end)

        it("undo of an erase covers the cell, its old-value peers and restored notes", function()
            local instance = new_game()
            assert.is_true(instance:toggle_note(0, 3, 2))
            assert.is_true(instance:place(0, 6, 2))
            assert.is_true(instance:erase(0, 6))
            assert.is_true(instance:undo())
            local affected = instance:undo_affected_cells()
            assert.is_not_nil(affected[cell_key(0, 6)])
            assert.is_not_nil(affected[cell_key(6, 6)], "peer whose conflict returns")
            assert.is_not_nil(affected[cell_key(0, 3)], "peer whose restored note is removed")
            assert.are.equal(3, count(affected))
        end)

        it("undo of a replacing place covers peers of both values", function()
            local instance = new_game()
            assert.is_true(instance:place(0, 6, 2))
            assert.is_true(instance:place(0, 6, 3))
            assert.is_true(instance:undo())
            local affected = instance:undo_affected_cells()
            assert.is_not_nil(affected[cell_key(0, 6)])
            assert.is_not_nil(affected[cell_key(6, 6)], "peer holding the replaced value 2")
            assert.is_not_nil(affected[cell_key(0, 1)], "peer holding the restored value 3")
            assert.are.equal(3, count(affected))
        end)
    end)

    describe("reset", function()
        it("reverts the board, notes, timer, mistakes, and history to fresh state", function()
            local instance, clock = new_game()
            clock.t = 1010
            assert.is_true(instance:place(0, 2, 4))
            assert.is_true(instance:toggle_note(0, 3, 6))
            assert.is_true(instance:place(0, 6, 2)) -- mistake (peer with 6,6)
            assert.are.equal(1, instance:mistakes())
            assert.are.equal(10, instance:elapsed())
            assert.is_true(instance:is_started())
            assert.is_not_nil(instance:started_at())
            assert.is_true(instance:can_undo())

            clock.t = 1050
            assert.is_true(instance:reset())

            -- Board reverted
            assert.are.equal(0, instance:get(0, 2))
            assert.are.equal(0, instance:get(0, 6))
            assert.are.equal(5, instance:get(0, 0)) -- given intact
            -- Notes cleared
            assert.are.equal(0, instance:get_notes(0, 3))
            -- Timer reset
            assert.are.equal(0, instance:elapsed())
            clock.t = 1060
            assert.are.equal(10, instance:elapsed())
            -- Mistakes & history reset
            assert.are.equal(0, instance:mistakes())
            assert.are.equal(0, instance:check_errors())
            assert.are.equal(0, #instance:revealed())
            assert.are.equal(0, #instance:hints())
            assert.is_false(instance:can_undo())
            assert.is_false(instance:can_redo())
            assert.is_false(instance:is_started())
            assert.is_nil(instance:started_at())
            assert.is_false(instance:is_finished())
        end)

        it("reverts notes to legal candidates when autofill_notes was enabled", function()
            local clock = { t = 1000 }
            local instance = assert(game.new({
                puzzle = board.from_string(PUZZLE),
                solution = board.from_string(SOLUTION),
                difficulty = "medium",
                autofill_notes = true,
                now = function()
                    return clock.t
                end,
            }))
            local initial_notes = instance:get_notes(0, 2)
            assert.is_true(initial_notes > 0)

            assert.is_true(instance:place(0, 2, 4))
            assert.are.equal(0, instance:get_notes(0, 2))

            assert.is_true(instance:reset())
            assert.are.equal(0, instance:get(0, 2))
            assert.are.equal(initial_notes, instance:get_notes(0, 2))
        end)

        it("resets a finished game back to playable state", function()
            local instance = new_game(PUZZLE_WIN)
            assert.is_true(instance:place(0, 6, 9))
            assert.is_true(instance:place(0, 7, 1))
            assert.is_not_nil(instance:finish())
            assert.is_true(instance:is_finished())

            assert.is_true(instance:reset())
            assert.is_false(instance:is_finished())
            assert.are.equal(0, instance:get(0, 6))
            assert.are.equal(0, instance:get(0, 7))
            assert.are.equal(0, instance:elapsed())
        end)

        it("resets timer to 0 and keeps timer running when timer was running", function()
            local instance, clock = new_game()
            clock.t = 1030
            assert.are.equal(30, instance:elapsed())

            assert.is_true(instance:reset())
            assert.are.equal(0, instance:elapsed())
            assert.is_true(instance.timer.running)
            clock.t = 1035
            assert.are.equal(5, instance:elapsed())
        end)
    end)

    describe("fill_all_notes", function()
        it("populates legal candidates across all empty cells and is undoable", function()
            local instance = new_game()
            assert.are.equal(0, instance:get_notes(0, 2))
            assert.is_true(instance:place(0, 2, 4))
            assert.is_true(instance:toggle_note(0, 3, 2))

            assert.is_true(instance:fill_all_notes())

            -- Placed cell has 0 notes
            assert.are.equal(0, instance:get_notes(0, 2))
            -- Givens have 0 notes
            assert.are.equal(0, instance:get_notes(0, 0))
            -- Empty cell (0, 3) now has all board-legal candidates
            local filled_mask = instance:get_notes(0, 3)
            assert.is_true(filled_mask > 0)
            -- 4 is placed at (0,2), so 4 cannot be candidate in (0,3)
            assert.is_false(has_note(instance, 0, 3, 4))
            -- 5 is given at (0,0), so 5 cannot be candidate in (0,3)
            assert.is_false(has_note(instance, 0, 3, 5))

            -- Undo restores previous notes state
            assert.is_true(instance:can_undo())
            assert.is_true(instance:undo())
            local affected = instance:undo_affected_cells()
            assert.is_not_nil(affected[cell_key(0, 3)])
            assert.are.equal(digit_bit(2), instance:get_notes(0, 3))

            -- Redo re-applies full candidate fill
            assert.is_true(instance:can_redo())
            assert.is_true(instance:redo())
            assert.are.equal(filled_mask, instance:get_notes(0, 3))
        end)

        it("is a no-op when all empty cells already have full legal candidate masks", function()
            local instance = new_game()
            assert.is_true(instance:fill_all_notes())
            assert.is_true(instance:is_started())
            assert.is_true(instance:can_undo())
            local rev = instance:revision()

            -- Subsequent fill is a no-op: does not commit or increment revision
            assert.is_true(instance:fill_all_notes())
            assert.are.equal(rev, instance:revision())
        end)

        it("fails when the board has conflicts", function()
            local instance = new_game()
            -- 5 is given at (0, 0), placing 5 at (0, 2) creates a row conflict
            assert.is_true(instance:place(0, 2, 5))
            assert.is_true(#instance:conflicts() > 0)

            local ok, err = instance:fill_all_notes()
            assert.is_nil(ok)
            assert.are.equal("board has conflicts", err)
        end)

        it("fails when the board has wrong digits placed", function()
            local instance = new_game()
            -- (0, 2) solution is 4; placing 1 is not a conflict yet, but wrong
            assert.is_true(instance:place(0, 2, 1))
            assert.are.equal(0, #instance:conflicts())

            local ok, err = instance:fill_all_notes()
            assert.is_nil(ok)
            assert.are.equal("board does not match the solution", err)
        end)

        it("fails when game is already finished", function()
            local instance = new_game(PUZZLE_WIN)
            assert.is_true(instance:place(0, 6, 9))
            assert.is_true(instance:place(0, 7, 1))
            assert.is_not_nil(instance:finish())

            local ok, err = instance:fill_all_notes()
            assert.is_nil(ok)
            assert.are.equal("game is finished", err)
        end)
    end)

    describe("custom difficulty game properties", function()
        it("initializes custom difficulty games and passes allowed_techniques to hints.next", function()
            local clock = { t = 1000 }
            local instance = assert(game.new({
                puzzle = board.from_string(PUZZLE),
                solution = board.from_string(SOLUTION),
                difficulty = "custom",
                custom_tier = "master",
                custom_techniques = { "swordfish" },
                allowed_techniques = 0, -- no techniques allowed
                now = function()
                    return clock.t
                end,
            }))

            assert.are.equal("custom", instance:difficulty())
            assert.are.equal("master", instance.custom_tier)
            assert.are.same({ "swordfish" }, instance.custom_techniques)

            -- With allowed_techniques = 0, hint() should find none
            local hint_res = instance:hint()
            assert.is_not_nil(hint_res)
            assert.are.equal("none", hint_res.status)

            local rec = instance:started_record()
            assert.are.equal("custom", rec.difficulty)
            assert.are.equal("master", rec.custom_tier)
            assert.are.same({ "swordfish" }, rec.custom_techniques)
        end)

        it("strictly validates custom_tier and custom_techniques on game.new", function()
            local now = function()
                return 1000
            end
            -- Non-custom with custom fields
            local bad1, err1 = game.new({
                puzzle = board.from_string(PUZZLE),
                solution = board.from_string(SOLUTION),
                difficulty = "easy",
                custom_tier = "master",
                now = now,
            })
            assert.is_nil(bad1)
            assert.is_string(err1)

            -- Custom without custom_tier
            local bad2, err2 = game.new({
                puzzle = board.from_string(PUZZLE),
                solution = board.from_string(SOLUTION),
                difficulty = "custom",
                custom_techniques = { "swordfish" },
                now = now,
            })
            assert.is_nil(bad2)
            assert.is_string(err2)

            -- Custom without custom_techniques
            local bad3, err3 = game.new({
                puzzle = board.from_string(PUZZLE),
                solution = board.from_string(SOLUTION),
                difficulty = "custom",
                custom_tier = "master",
                now = now,
            })
            assert.is_nil(bad3)
            assert.is_string(err3)

            -- Custom with invalid technique for tier
            local bad4, err4 = game.new({
                puzzle = board.from_string(PUZZLE),
                solution = board.from_string(SOLUTION),
                difficulty = "custom",
                custom_tier = "hard",
                custom_techniques = { "swordfish" }, -- swordfish is master, not hard
                allowed_techniques = 0,
                now = now,
            })
            assert.is_nil(bad4)
            assert.is_string(err4)

            -- Custom without allowed_techniques
            local bad5, err5 = game.new({
                puzzle = board.from_string(PUZZLE),
                solution = board.from_string(SOLUTION),
                difficulty = "custom",
                custom_tier = "master",
                custom_techniques = { "swordfish" },
                now = now,
            })
            assert.is_nil(bad5)
            assert.is_string(err5)
        end)
    end)
end)
