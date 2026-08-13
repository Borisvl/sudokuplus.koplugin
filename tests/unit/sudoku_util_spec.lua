package.path = "plugins/sudoku.koplugin/?.lua;" .. package.path

local util = require("core.util")

describe("core.util", function()
    it("accepts the six supported difficulties", function()
        for _, name in ipairs({ "beginner", "easy", "medium", "hard", "master", "expert" }) do
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

    it("formats durations as HH:MM:SS with rounding", function()
        assert.are.equal("00:00:00", util.format_time(0))
        assert.are.equal("00:00:01", util.format_time(0.6))
        assert.are.equal("00:01:00", util.format_time(60))
        assert.are.equal("01:02:03", util.format_time(3723))
        assert.are.equal("12:34:56", util.format_time(45296.4))
        assert.are.equal("00:00:00", util.format_time(-5), "negative durations clamp to zero")
    end)
end)
