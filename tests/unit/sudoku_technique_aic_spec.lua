package.path = "plugins/sudoku.koplugin/?.lua;" .. package.path

local bit = require("bit")
local board = require("core.board")
local candidates = require("core.candidates")
local masks = require("core.masks")
local aic = require("core.techniques.aic")
local propagator = require("core.techniques.propagator")
local solve_path = require("core.solve_path")
local solver = require("core.solver")
local flags = require("core.techniques.flags")

-- rustoku AIC test puzzles: an X-Chain, an XY-Chain, and a Discontinuous Nice
-- Loop. Each has a candidate elimination reachable by AIC alone.
local X_CHAIN = "3.4.2..8...6.......5..7.3.....68..2.....34....6.15.7...1.........9....6...8217..5"
local XY_CHAIN = "3...4.52858.........2..........74....1....35..5.6...4..78.....21..2......39..68.."
local DNL = "....8.2....5....4..2...5........7......21..971.4....3...........973..52...8.5136."

local function aic_steps(path)
    local steps = {}
    for _, step in ipairs(path.steps) do
        if step.type == "elim" and step.flags == flags.ALTERNATING_INFERENCE_CHAIN then
            steps[#steps + 1] = step
        end
    end
    return steps
end

local function is_in_values(values, v)
    for _, value in ipairs(values) do
        if value == v then
            return true
        end
    end
    return false
end

local function capped_propagator()
    local c = candidates.new()
    for r = 0, 8 do
        for col = 0, 8 do
            candidates.set(c, r, col, 0x1FF)
        end
    end
    candidates.set(c, 0, 0, bit.bor(bit.lshift(1, 0), bit.lshift(1, 1)))
    local p = propagator.new(board.new(), masks.new(), c, flags.ALTERNATING_INFERENCE_CHAIN)
    return p
end

describe("core.techniques.aic", function()
    for _, entry in ipairs({ { "x_chain", X_CHAIN }, { "xy_chain", XY_CHAIN }, { "dnl", DNL } }) do
        local name, puzzle = entry[1], entry[2]

        it("produces aic eliminations on the " .. name .. " puzzle", function()
            local s = solver.new(board.from_string(puzzle), { techniques = flags.ALTERNATING_INFERENCE_CHAIN })
            local path = solve_path.new()
            assert.is_true(s:propagate(path))
            local steps = aic_steps(path)
            assert.is_true(#steps > 0)
            for _, step in ipairs(steps) do
                local v_bit = bit.lshift(1, step.value - 1)
                assert.are.equal(0, bit.band(candidates.get(s.candidates, step.row, step.col), v_bit))
            end
        end)

        it("records chain pattern metadata on the " .. name .. " puzzle", function()
            local s = solver.new(board.from_string(puzzle), { techniques = flags.ALTERNATING_INFERENCE_CHAIN })
            local path = solve_path.new()
            s:propagate(path)
            for _, step in ipairs(aic_steps(path)) do
                local pattern = step.pattern
                assert.are.equal("aic", pattern.kind)
                assert.is_true(#pattern.nodes >= 4)
                assert.are.equal(0, #pattern.nodes % 2)
                assert.is_true(#pattern.values >= 1)
                assert.is_true(is_in_values(pattern.values, step.value))
                local first, last = pattern.nodes[1], pattern.nodes[#pattern.nodes]
                for _, node in ipairs(pattern.nodes) do
                    assert.is_true(node.r >= 0 and node.r <= 8)
                    assert.is_true(node.c >= 0 and node.c <= 8)
                    assert.is_true(node.val >= 1 and node.val <= 9)
                end
                -- Chains start and end on the same value; nice loops close on the same cell.
                assert.is_true(first.val == last.val or (first.r == last.r and first.c == last.c))
            end
        end)

        it("does not alter the givens on the " .. name .. " puzzle", function()
            local original = board.from_string(puzzle)
            local s = solver.new(board.from_string(puzzle), { techniques = flags.ALTERNATING_INFERENCE_CHAIN })
            local path = solve_path.new()
            s:propagate(path)
            for r = 0, 8 do
                for c = 0, 8 do
                    local orig = board.get(original, r, c)
                    if orig ~= 0 then
                        assert.are.equal(orig, board.get(s.board, r, c))
                    end
                end
            end
        end)
    end

    it("reports expansion-cap status separately from no-chain", function()
        local no_chain_prop = propagator.new(board.new(), masks.new(), candidates.new(), 0)
        local no_chain_changed, no_chain_status = aic.apply(no_chain_prop, solve_path.new())
        assert.is_false(no_chain_changed)
        assert.is_nil(no_chain_status)

        local p = capped_propagator()
        p.aic_max_expansions = 0
        local path = solve_path.new()
        local changed, status = aic.apply(p, path)

        assert.is_false(changed)
        assert.are.equal("search_capped", status)
        assert.are.equal(14, aic.MAX_DEPTH)
        assert.are.equal(10000, aic.MAX_EXPANSIONS)
    end)

    it("reports depth-cap status", function()
        local p = capped_propagator()
        p.aic_max_depth = 1
        local path = solve_path.new()
        local changed, status = aic.apply(p, path)

        assert.is_false(changed)
        assert.are.equal("search_capped", status)
    end)

    it("exposes a capped AIC pass through the propagator", function()
        local p = capped_propagator()
        p.aic_max_expansions = 0
        local path = solve_path.new()
        local ok, status = p:propagate_constraints(path, 0)

        assert.is_true(ok)
        assert.are.equal("search_capped", status)
    end)
end)
