package.path = "plugins/sudokuplus.koplugin/?.lua;" .. package.path

local bit = require("bit")
local board = require("sudokuplus.core.board")
local propagator = require("sudokuplus.core.techniques.propagator")
local solve_path = require("sudokuplus.core.solve_path")
local solver = require("sudokuplus.core.solver")
local flags = require("sudokuplus.core.techniques.flags")

local FULL_MASK = 0x1FF

-- X-Wing and naked-pair expectations follow HoDoKu bf201 and n201. The AIC
-- expectations use the pinned rustoku X-Chain, XY-Chain, and DNL fixtures.
local CASES = {
    {
        name = "x_wing",
        puzzle = "000000000760003002002640009403900070000004903005000020010560000370090041000000060",
        techniques = bit.bor(flags.EASY, bit.bor(flags.MEDIUM, flags.X_WING)),
        lower_techniques = bit.bor(flags.EASY, flags.MEDIUM),
        module = "x_wing",
        flag = flags.X_WING,
        expected = {
            {
                type = "elim",
                row = 3,
                col = 4,
                value = 5,
                pattern = {
                    kind = "x_wing",
                    cells = { { 1, 4 }, { 1, 7 }, { 4, 4 }, { 4, 7 } },
                    values = { 5 },
                    base = { { type = "row", index = 1 }, { type = "row", index = 4 } },
                    cover = { { type = "col", index = 4 }, { type = "col", index = 7 } },
                },
            },
        },
    },
    {
        name = "naked_pair",
        puzzle = "700009030000105006400260009002083951007000000005600000000000003100000060000004010",
        techniques = bit.bor(flags.EASY, flags.NAKED_PAIRS),
        lower_techniques = flags.EASY,
        module = "naked_pairs",
        flag = flags.NAKED_PAIRS,
        expected = {
            {
                type = "elim",
                row = 7,
                col = 1,
                value = 3,
                pattern = {
                    kind = "naked_pair",
                    cells = { { 7, 2 }, { 7, 3 } },
                    values = { 3, 9 },
                    unit = { type = "row", index = 7 },
                },
            },
            {
                type = "elim",
                row = 8,
                col = 1,
                value = 7,
                pattern = {
                    kind = "naked_pair",
                    cells = { { 8, 4 }, { 8, 8 } },
                    values = { 2, 7 },
                    unit = { type = "row", index = 8 },
                },
            },
            {
                type = "elim",
                row = 8,
                col = 6,
                value = 2,
                pattern = {
                    kind = "naked_pair",
                    cells = { { 8, 4 }, { 8, 8 } },
                    values = { 2, 7 },
                    unit = { type = "row", index = 8 },
                },
            },
            {
                type = "elim",
                row = 8,
                col = 6,
                value = 7,
                pattern = {
                    kind = "naked_pair",
                    cells = { { 8, 4 }, { 8, 8 } },
                    values = { 2, 7 },
                    unit = { type = "row", index = 8 },
                },
            },
        },
    },
    {
        name = "aic_x_chain",
        puzzle = "3.4.2..8...6.......5..7.3.....68..2.....34....6.15.7...1.........9....6...8217..5",
        techniques = flags.ALTERNATING_INFERENCE_CHAIN,
        lower_techniques = 0,
        module = "aic",
        flag = flags.ALTERNATING_INFERENCE_CHAIN,
        expected = {
            {
                type = "elim",
                row = 6,
                col = 5,
                value = 6,
                pattern = {
                    kind = "x_chain",
                    values = { 6 },
                    nodes = {
                        { r = 0, c = 5, val = 6 },
                        { r = 2, c = 5, val = 6 },
                        { r = 6, c = 5, val = 6 },
                        { r = 6, c = 4, val = 6 },
                    },
                },
            },
        },
    },
    {
        name = "aic_xy_chain",
        puzzle = "3...4.52858.........2..........74....1....35..5.6...4..78.....21..2......39..68..",
        techniques = flags.ALTERNATING_INFERENCE_CHAIN,
        lower_techniques = 0,
        module = "aic",
        flag = flags.ALTERNATING_INFERENCE_CHAIN,
        expected = {
            {
                type = "elim",
                row = 2,
                col = 0,
                value = 6,
                pattern = {
                    kind = "aic",
                    values = { 6 },
                    nodes = {
                        { r = 0, c = 2, val = 6 },
                        { r = 0, c = 1, val = 6 },
                        { r = 7, c = 1, val = 6 },
                        { r = 7, c = 1, val = 4 },
                        { r = 6, c = 0, val = 4 },
                        { r = 6, c = 0, val = 6 },
                    },
                },
            },
            {
                type = "elim",
                row = 7,
                col = 2,
                value = 6,
                pattern = {
                    kind = "aic",
                    values = { 6 },
                    nodes = {
                        { r = 0, c = 2, val = 6 },
                        { r = 0, c = 1, val = 6 },
                        { r = 7, c = 1, val = 6 },
                        { r = 7, c = 1, val = 4 },
                        { r = 6, c = 0, val = 4 },
                        { r = 6, c = 0, val = 6 },
                    },
                },
            },
        },
    },
    {
        name = "aic_discontinuous_nice_loop",
        puzzle = "....8.2....5....4..2...5........7......21..971.4....3...........973..52...8.5136.",
        techniques = flags.ALTERNATING_INFERENCE_CHAIN,
        lower_techniques = 0,
        module = "aic",
        flag = flags.ALTERNATING_INFERENCE_CHAIN,
        expected = {
            {
                type = "elim",
                row = 3,
                col = 0,
                value = 3,
                pattern = {
                    kind = "aic",
                    values = { 3, 5, 6, 8 },
                    nodes = {
                        { r = 3, c = 0, val = 2 },
                        { r = 3, c = 2, val = 2 },
                        { r = 3, c = 2, val = 9 },
                        { r = 3, c = 0, val = 9 },
                    },
                },
            },
            {
                type = "elim",
                row = 3,
                col = 0,
                value = 5,
                pattern = {
                    kind = "aic",
                    values = { 3, 5, 6, 8 },
                    nodes = {
                        { r = 3, c = 0, val = 2 },
                        { r = 3, c = 2, val = 2 },
                        { r = 3, c = 2, val = 9 },
                        { r = 3, c = 0, val = 9 },
                    },
                },
            },
            {
                type = "elim",
                row = 3,
                col = 0,
                value = 6,
                pattern = {
                    kind = "aic",
                    values = { 3, 5, 6, 8 },
                    nodes = {
                        { r = 3, c = 0, val = 2 },
                        { r = 3, c = 2, val = 2 },
                        { r = 3, c = 2, val = 9 },
                        { r = 3, c = 0, val = 9 },
                    },
                },
            },
            {
                type = "elim",
                row = 3,
                col = 0,
                value = 8,
                pattern = {
                    kind = "aic",
                    values = { 3, 5, 6, 8 },
                    nodes = {
                        { r = 3, c = 0, val = 2 },
                        { r = 3, c = 2, val = 2 },
                        { r = 3, c = 2, val = 9 },
                        { r = 3, c = 0, val = 9 },
                    },
                },
            },
        },
    },
}

local function copy_cells(cells)
    local result = {}
    for i, cell in ipairs(cells or {}) do
        result[i] = { cell[1], cell[2] }
    end
    return result
end

local function copy_values(values)
    local result = {}
    for i, value in ipairs(values or {}) do
        result[i] = value
    end
    return result
end

local function copy_units(units)
    local result = {}
    for i, unit in ipairs(units or {}) do
        result[i] = { type = unit.type, index = unit.index }
    end
    return result
end

local function copy_nodes(nodes)
    local result = {}
    for i, node in ipairs(nodes or {}) do
        result[i] = { r = node.r, c = node.c, val = node.val }
    end
    return result
end

local function normalize_step(step)
    local pattern = step.pattern or {}
    local normalized_pattern = { kind = pattern.kind }
    if pattern.cells then
        normalized_pattern.cells = copy_cells(pattern.cells)
    end
    if pattern.values then
        normalized_pattern.values = copy_values(pattern.values)
    end
    if pattern.unit then
        normalized_pattern.unit = { type = pattern.unit.type, index = pattern.unit.index }
    end
    if pattern.base then
        normalized_pattern.base = copy_units(pattern.base)
    end
    if pattern.cover then
        normalized_pattern.cover = copy_units(pattern.cover)
    end
    if pattern.nodes then
        normalized_pattern.nodes = copy_nodes(pattern.nodes)
    end
    return {
        type = step.type,
        row = step.row,
        col = step.col,
        value = step.value,
        pattern = normalized_pattern,
    }
end

local function normalized_trace(path)
    local result = {}
    for _, step in ipairs(path.steps) do
        result[#result + 1] = normalize_step(step)
    end
    return result
end

local function apply_first_pass(case)
    local s = assert(solver.new(board.from_string(case.puzzle), { techniques = case.lower_techniques }))
    local lower_path = solve_path.new()
    if case.lower_techniques ~= 0 then
        assert.is_true(s:propagate(lower_path))
    end

    local prop = propagator.new(s.board, s.masks, s.candidates, 0)
    local path = solve_path.new()
    local technique = require("sudokuplus.core.techniques." .. case.module)
    assert.is_true(technique.apply(prop, path), case.name .. " should make a deduction")
    return path
end

local function legal_mask(b, r, c)
    local used = 0
    for i = 0, 8 do
        local row_value = board.get(b, r, i)
        local col_value = board.get(b, i, c)
        if row_value ~= 0 then
            used = bit.bor(used, bit.lshift(1, row_value - 1))
        end
        if col_value ~= 0 then
            used = bit.bor(used, bit.lshift(1, col_value - 1))
        end
    end

    local start_row = math.floor(r / 3) * 3
    local start_col = math.floor(c / 3) * 3
    for row = start_row, start_row + 2 do
        for col = start_col, start_col + 2 do
            local value = board.get(b, row, col)
            if value ~= 0 then
                used = bit.bor(used, bit.lshift(1, value - 1))
            end
        end
    end
    return bit.band(bit.bnot(used), FULL_MASK)
end

local function replay_state(puzzle)
    local initial = board.from_string(puzzle)
    local state = { board = board.clone(initial), candidates = {} }
    for r = 0, 8 do
        state.candidates[r + 1] = {}
        for c = 0, 8 do
            state.candidates[r + 1][c + 1] = board.is_empty(state.board, r, c) and legal_mask(state.board, r, c) or 0
        end
    end
    return state
end

local function replay_candidate(state, r, c)
    return state.candidates[r + 1][c + 1]
end

local function set_replay_candidate(state, r, c, mask)
    state.candidates[r + 1][c + 1] = mask
end

local function sees(r1, c1, r2, c2)
    return r1 == r2
        or c1 == c2
        or (math.floor(r1 / 3) == math.floor(r2 / 3) and math.floor(c1 / 3) == math.floor(c2 / 3))
end

local function replay_placement(state, step, step_number)
    local value_bit = bit.lshift(1, step.value - 1)
    assert.is_true(board.is_empty(state.board, step.row, step.col), "placement " .. step_number .. " overwrites a cell")
    assert.is_true(
        bit.band(replay_candidate(state, step.row, step.col), value_bit) ~= 0,
        "placement " .. step_number .. " uses an unavailable candidate"
    )

    board.set(state.board, step.row, step.col, step.value)
    set_replay_candidate(state, step.row, step.col, 0)
    for r = 0, 8 do
        for c = 0, 8 do
            if board.is_empty(state.board, r, c) and sees(step.row, step.col, r, c) then
                set_replay_candidate(state, r, c, bit.band(replay_candidate(state, r, c), bit.bnot(value_bit)))
            end
        end
    end
end

local function replay_elimination(state, step, step_number)
    local value_bit = bit.lshift(1, step.value - 1)
    assert.is_true(board.is_empty(state.board, step.row, step.col), "elimination " .. step_number .. " targets a clue")
    assert.is_true(
        bit.band(replay_candidate(state, step.row, step.col), value_bit) ~= 0,
        "elimination " .. step_number .. " was already absent"
    )
    set_replay_candidate(
        state,
        step.row,
        step.col,
        bit.band(replay_candidate(state, step.row, step.col), bit.bnot(value_bit))
    )
end

local function replay_steps(state, steps)
    for i, step in ipairs(steps) do
        if step.type == "place" then
            replay_placement(state, step, i)
        else
            assert.are.equal("elim", step.type)
            replay_elimination(state, step, i)
        end
    end
end

local function assert_replayed_state(case)
    local s = assert(solver.new(board.from_string(case.puzzle), { techniques = case.techniques }))
    local path = solve_path.new()
    assert.is_true(s:propagate(path), case.name .. " propagation should succeed")

    local replay = replay_state(case.puzzle)
    replay_steps(replay, path.steps)
    assert.are.equal(board.to_string(s.board), board.to_string(replay.board), case.name .. " board replay")
    for r = 0, 8 do
        for c = 0, 8 do
            assert.are.equal(
                s.candidates[r + 1][c + 1],
                replay.candidates[r + 1][c + 1],
                case.name .. " candidate replay at " .. r .. "," .. c
            )
        end
    end
end

describe("core.technique traces", function()
    it("matches exact normalized first-pass traces", function()
        for _, case in ipairs(CASES) do
            assert.are.same(case.expected, normalized_trace(apply_first_pass(case)), case.name)
        end
    end)

    it("replays every recorded step against an independent candidate model", function()
        for _, case in ipairs(CASES) do
            assert_replayed_state(case)
        end
    end)
end)
