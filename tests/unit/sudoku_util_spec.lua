package.path = "plugins/sudokuplus.koplugin/?.lua;" .. package.path

local util = require("core.util")

describe("core.util", function()
    it("accepts the seven supported difficulties", function()
        for _, name in ipairs({ "beginner", "easy", "medium", "hard", "master", "expert", "custom" }) do
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

    it("formats seed into 4-digit space-separated chunks", function()
        assert.is_nil(util.format_seed(nil))
        assert.are.equal("42", util.format_seed(42))
        assert.are.equal("4242", util.format_seed(4242))
        assert.are.equal("4242 42", util.format_seed(424242))
        assert.are.equal("1234 5678", util.format_seed(12345678))
        assert.are.equal("4354 5433 6455 32", util.format_seed(43545433645532))
        assert.are.equal("4354 5433 6455 32", util.format_seed("43545433645532"))
    end)

    it("computes 1-based 81-element cell index", function()
        assert.are.equal(1, util.cell_index(0, 0))
        assert.are.equal(9, util.cell_index(0, 8))
        assert.are.equal(10, util.cell_index(1, 0))
        assert.are.equal(81, util.cell_index(8, 8))
    end)

    it("validates cell coordinates", function()
        assert.is_true(util.validate_cell(0, 0))
        assert.is_true(util.validate_cell(8, 8))

        local ok, err = util.validate_cell(-1, 0)
        assert.is_nil(ok)
        assert.is_string(err)

        ok, err = util.validate_cell(0, 9)
        assert.is_nil(ok)
        assert.is_string(err)

        ok, err = util.validate_cell(1.5, 0)
        assert.is_nil(ok)
        assert.is_string(err)
    end)

    it("validates cell values", function()
        assert.is_true(util.validate_value(1))
        assert.is_true(util.validate_value(9))

        local ok, err = util.validate_value(0)
        assert.is_nil(ok)
        assert.is_string(err)

        ok, err = util.validate_value(10)
        assert.is_nil(ok)
        assert.is_string(err)
    end)

    it("validates non-negative integers", function()
        assert.is_true(util.validate_non_negative(0, "test"))
        assert.is_true(util.validate_non_negative(5, "test"))

        local ok, err = util.validate_non_negative(-1, "test")
        assert.is_nil(ok)
        assert.is_string(err)

        ok, err = util.validate_non_negative(1.2, "test")
        assert.is_nil(ok)
        assert.is_string(err)
    end)

    it("creates 9x9 mask grids", function()
        local grid = util.new_mask_grid()
        assert.are.equal(9, #grid)
        assert.are.equal(9, #grid[1])
        assert.are.equal(0, grid[1][1])

        local custom = util.new_mask_grid(util.FULL_CANDIDATE_MASK)
        assert.are.equal(511, custom[9][9])
    end)

    it("deep-copies nested tables and primitives", function()
        assert.are.equal(42, util.deep_copy(42))
        assert.are.equal("hello", util.deep_copy("hello"))

        local original = { a = { b = 1 } }
        local copy = util.deep_copy(original)
        assert.are.equal(1, copy.a.b)
        copy.a.b = 2
        assert.are.equal(1, original.a.b, "nested table must be independent")
    end)

    it("builds constraint masks from a board", function()
        local b = {}
        for i = 1, 81 do
            b[i] = 0
        end
        b[1] = 5 -- (0,0) = 5
        local m = util.constraint_masks_for(b)
        assert.is_not_nil(m)
        assert.are.equal(16, m.row[1]) -- 1 << (5 - 1) == 16
        assert.are.equal(16, m.col[1])
        assert.are.equal(16, m.box[1])
    end)

    it("validates custom tier and techniques lists correctly", function()
        local tier, techs = util.validate_custom_tier_and_techniques("master", { "swordfish", "x_wing" })
        assert.are.equal("master", tier)
        assert.are.same({ "swordfish", "x_wing" }, techs)

        -- Invalid tier
        local bad_tier, err1 = util.validate_custom_tier_and_techniques("easy", { "naked_pairs" })
        assert.is_nil(bad_tier)
        assert.is_true(err1:find("custom_tier must be one of", 1, true) ~= nil)

        -- Empty techniques
        local bad_empty, err2 = util.validate_custom_tier_and_techniques("master", {})
        assert.is_nil(bad_empty)
        assert.is_true(err2:find("custom_techniques must be a non-empty list", 1, true) ~= nil)

        -- Invalid technique for tier
        local bad_tech, err3 = util.validate_custom_tier_and_techniques("hard", { "swordfish" })
        assert.is_nil(bad_tech)
        assert.is_true(err3:find("invalid technique id for tier", 1, true) ~= nil)

        -- Prefix support
        local _, err_prefixed = util.validate_custom_tier_and_techniques("invalid", {}, "record ")
        assert.is_true(err_prefixed:find("record custom_tier", 1, true) ~= nil)
    end)
end)
