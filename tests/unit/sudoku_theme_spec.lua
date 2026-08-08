describe("sudoku theme", function()
    local theme
    setup(function()
        require("commonrequire")
        package.path = "plugins/sudoku.koplugin/?.lua;" .. package.path
        theme = require("ui.theme")
    end)

    it("defines all inks used by the view", function()
        assert.is_not_nil(theme.background)
        assert.is_not_nil(theme.grid_thin)
        assert.is_not_nil(theme.grid_thick)
        assert.is_not_nil(theme.digit)
        assert.is_not_nil(theme.note)
        assert.is_not_nil(theme.wrong_fill)
        assert.is_not_nil(theme.disabled)
        assert.is_not_nil(theme.invert_fg)
    end)

    it("uses high-contrast foreground and background", function()
        assert.are_not.equal(theme.background, theme.digit)
        assert.are_not.equal(theme.background, theme.grid_thick)
        assert.are_not.equal(theme.grid_thick, theme.grid_thin)
        assert.are_not.equal(theme.digit, theme.note)
        assert.are_not.equal(theme.digit, theme.invert_fg, "inverted cells must use light ink")
    end)

    it("keeps grid ink darker than the wrong-cell fill so digits stay readable", function()
        local function luminance(color)
            return tonumber(color.a)
        end
        assert.is_true(luminance(theme.wrong_fill) > luminance(theme.grid_thick))
        assert.is_true(luminance(theme.disabled) > luminance(theme.digit))
    end)

    it("keeps the notes ink dark enough to read", function()
        local function luminance(color)
            return tonumber(color.a)
        end
        assert.is_true(luminance(theme.note) < 0x40, "notes must be at least ~75% black ink")
        assert.are_not.equal(theme.digit, theme.note, "notes stay distinct from digits")
    end)
end)
