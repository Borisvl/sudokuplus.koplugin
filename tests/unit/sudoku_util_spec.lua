package.path = "plugins/sudoku.koplugin/?.lua;" .. package.path

local util = require("core.util")

describe("core.util", function()
    it("accepts the four supported difficulties", function()
        for _, name in ipairs({ "easy", "medium", "hard", "expert" }) do
            assert.is_true(util.is_difficulty(name), name .. " must be a difficulty")
        end
    end)

    it("rejects unknown difficulties and non-string values", function()
        assert.is_false(util.is_difficulty("impossible"))
        assert.is_false(util.is_difficulty(1))
        assert.is_false(util.is_difficulty(nil))
    end)

    it("detects non-finite numbers", function()
        assert.is_true(util.is_finite(0))
        assert.is_true(util.is_finite(-1.5))
        assert.is_false(util.is_finite(0 / 0))
        assert.is_false(util.is_finite(math.huge))
        assert.is_false(util.is_finite(-math.huge))
    end)
end)
