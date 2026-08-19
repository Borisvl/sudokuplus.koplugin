package.path = "plugins/sudokuplus.koplugin/?.lua;" .. package.path

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

local function chain_steps(path)
    local steps = {}
    for _, step in ipairs(path.steps) do
        if
            step.type == "elim"
            and (
                step.flags == flags.ALTERNATING_INFERENCE_CHAIN
                or step.flags == flags.X_CHAIN
                or step.flags == flags.XY_CHAIN
            )
        then
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

local FIRST_PASS_TRACES = {
    x_chain = {
        { 6, 5, 6 },
    },
    xy_chain = {
        { 2, 0, 6 },
        { 7, 2, 6 },
    },
    dnl = {
        { 3, 0, 3 },
        { 3, 0, 5 },
        { 3, 0, 6 },
        { 3, 0, 8 },
    },
}

local function first_pass_trace(puzzle, technique_mask)
    local s = solver.new(board.from_string(puzzle), { techniques = 0 })
    local p = propagator.new(s.board, s.masks, s.candidates, technique_mask or aic.flags())
    local path = solve_path.new()
    assert.is_true(aic.apply(p, path))

    local trace = {}
    for _, step in ipairs(path.steps) do
        trace[#trace + 1] = { step.row, step.col, step.value }
    end
    return trace
end

local function capped_propagator()
    local c = candidates.new()
    for r = 0, 8 do
        for col = 0, 8 do
            candidates.set(c, r, col, 0x1FF)
        end
    end
    candidates.set(c, 0, 0, bit.bor(bit.lshift(1, 0), bit.lshift(1, 1)))
    local p = propagator.new(board.new(), masks.new(), c, aic.flags())
    return p
end

describe("core.techniques.aic", function()
    for _, entry in ipairs({ { "x_chain", X_CHAIN }, { "xy_chain", XY_CHAIN }, { "dnl", DNL } }) do
        local name, puzzle = entry[1], entry[2]

        it("produces valid chain eliminations on the " .. name .. " puzzle", function()
            local s = solver.new(board.from_string(puzzle), { techniques = aic.flags() })
            local path = solve_path.new()
            assert.is_true(s:propagate(path))
            local steps = chain_steps(path)
            assert.is_true(#steps > 0)
            for _, step in ipairs(steps) do
                assert.is_true(
                    step.flags == flags.ALTERNATING_INFERENCE_CHAIN
                        or step.flags == flags.X_CHAIN
                        or step.flags == flags.XY_CHAIN
                )
                local v_bit = bit.lshift(1, step.value - 1)
                assert.are.equal(0, bit.band(candidates.get(s.candidates, step.row, step.col), v_bit))
            end
        end)

        it("records chain pattern metadata on the " .. name .. " puzzle", function()
            local s = solver.new(board.from_string(puzzle), { techniques = aic.flags() })
            local path = solve_path.new()
            s:propagate(path)
            for _, step in ipairs(chain_steps(path)) do
                local pattern = step.pattern
                assert.is_true(pattern.kind == "aic" or pattern.kind == "x_chain" or pattern.kind == "xy_chain")
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

        it("reconstructs each chain without duplicate candidate nodes on the " .. name .. " puzzle", function()
            local s = solver.new(board.from_string(puzzle), { techniques = aic.flags() })
            local path = solve_path.new()
            s:propagate(path)
            for _, step in ipairs(chain_steps(path)) do
                local seen = {}
                for _, node in ipairs(step.pattern.nodes) do
                    local key = node.r .. ":" .. node.c .. ":" .. node.val
                    assert.is_nil(seen[key])
                    seen[key] = true
                end
            end
        end)

        it("does not alter the givens on the " .. name .. " puzzle", function()
            local original = board.from_string(puzzle)
            local s = solver.new(board.from_string(puzzle), { techniques = aic.flags() })
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

    local PURE_XY_CHAIN = "..3.......1...8627....64.3......246.58..3.1.......78...26.............8689...1..."

    it("correctly sub-classifies X-Chain, XY-Chain, and General AIC", function()
        -- First pass of X_CHAIN puzzle produces a 4-node single-digit X-Chain on value 6
        local s = solver.new(board.from_string(X_CHAIN), { techniques = flags.X_CHAIN })
        local p = propagator.new(s.board, s.masks, s.candidates, flags.X_CHAIN)
        local path = solve_path.new()
        assert.is_true(aic.apply(p, path))
        assert.are.equal(1, #path.steps)
        assert.are.equal(flags.X_CHAIN, path.steps[1].flags)
        assert.are.equal("x_chain", path.steps[1].pattern.kind)

        -- Pure XY_CHAIN puzzle produces an 8-node XY-Chain through bivalue cells
        local s_xy = solver.new(board.from_string(PURE_XY_CHAIN), {
            techniques = bit.bor(flags.EASY, bit.bor(flags.MEDIUM, flags.HARD)),
        })
        local path_prep = solve_path.new()
        s_xy:propagate(path_prep)
        local p_xy = propagator.new(s_xy.board, s_xy.masks, s_xy.candidates, flags.XY_CHAIN)
        local path_xy = solve_path.new()
        assert.is_true(aic.apply(p_xy, path_xy))
        assert.are.equal(1, #path_xy.steps)
        assert.are.equal(flags.XY_CHAIN, path_xy.steps[1].flags)
        assert.are.equal("xy_chain", path_xy.steps[1].pattern.kind)
        assert.are.equal(1, path_xy.steps[1].row)
        assert.are.equal(4, path_xy.steps[1].col)
        assert.are.equal(9, path_xy.steps[1].value)

        -- First pass of XY_CHAIN puzzle produces a 6-node General AIC with mixed digits & inter-cell link
        local s2 = solver.new(board.from_string(XY_CHAIN), { techniques = flags.ALTERNATING_INFERENCE_CHAIN })
        local p2 = propagator.new(s2.board, s2.masks, s2.candidates, flags.ALTERNATING_INFERENCE_CHAIN)
        local path2 = solve_path.new()
        assert.is_true(aic.apply(p2, path2))
        assert.are.equal(2, #path2.steps)
        assert.are.equal(flags.ALTERNATING_INFERENCE_CHAIN, path2.steps[1].flags)
        assert.are.equal("aic", path2.steps[1].pattern.kind)
    end)

    it("respects sub-type gating when specific chain flags are disabled", function()
        -- X-Chain elimination requires X_CHAIN flag
        local s_x = solver.new(board.from_string(X_CHAIN), { techniques = flags.X_CHAIN })
        local p_x = propagator.new(s_x.board, s_x.masks, s_x.candidates, flags.X_CHAIN)
        local path_x = solve_path.new()
        assert.is_true(aic.apply(p_x, path_x))
        assert.are.equal(flags.X_CHAIN, path_x.steps[1].flags)

        -- If only XY_CHAIN is allowed on X_CHAIN first-pass, the X-Chain is gated out
        local s_no_x = solver.new(board.from_string(X_CHAIN), { techniques = flags.XY_CHAIN })
        local p_no_x = propagator.new(s_no_x.board, s_no_x.masks, s_no_x.candidates, flags.XY_CHAIN)
        local path_no_x = solve_path.new()
        assert.is_false(aic.apply(p_no_x, path_no_x))

        -- If only X_CHAIN is allowed on pure XY-Chain, the XY-Chain is gated out
        local s_prep = solver.new(board.from_string(PURE_XY_CHAIN), {
            techniques = bit.bor(flags.EASY, bit.bor(flags.MEDIUM, flags.HARD)),
        })
        s_prep:propagate(solve_path.new())
        local p_no_xy = propagator.new(s_prep.board, s_prep.masks, s_prep.candidates, flags.X_CHAIN)
        local path_no_xy = solve_path.new()
        assert.is_false(aic.apply(p_no_xy, path_no_xy))

        -- If only X_CHAIN is allowed on General AIC puzzle first-pass, the AIC is gated out
        local s_no_aic = solver.new(board.from_string(XY_CHAIN), { techniques = flags.X_CHAIN })
        local p_no_aic = propagator.new(s_no_aic.board, s_no_aic.masks, s_no_aic.candidates, flags.X_CHAIN)
        local path_no_aic = solve_path.new()
        assert.is_false(aic.apply(p_no_aic, path_no_aic))
    end)

    it("preserves the exact first-pass elimination trace", function()
        for _, entry in ipairs({ { "x_chain", X_CHAIN }, { "xy_chain", XY_CHAIN }, { "dnl", DNL } }) do
            assert.are.same(FIRST_PASS_TRACES[entry[1]], first_pass_trace(entry[2]), entry[1])
        end
    end)

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
