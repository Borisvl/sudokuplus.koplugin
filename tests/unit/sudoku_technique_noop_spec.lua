package.path = "plugins/sudokuplus.koplugin/?.lua;" .. package.path

local board = require("core.board")
local candidates = require("core.candidates")
local solve_path = require("core.solve_path")
local solver = require("core.solver")
local propagator = require("core.techniques.propagator")

local SOLVED = "534678912672195348198342567859761423426853791713924856961537284287419635345286179"

describe("every technique is a no-op on a solved board", function()
    for _, name in ipairs(propagator.technique_names()) do
        it(name .. " changes nothing on a solved board", function()
            local mod = require("core.techniques." .. name)
            local s = solver.new(board.from_string(SOLVED))
            local p = propagator.new(s.board, s.masks, s.candidates, 0)
            local path = solve_path.new()
            local before = candidates.clone(s.candidates)

            local changed = mod.apply(p, path)

            assert.is_false(changed, name .. " must not report progress on a solved board")
            assert.are.same(before, p.candidates, name .. " must not alter candidates")
            assert.are.equal(0, #path.steps, name .. " must not record steps")
        end)
    end
end)
