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
    end)

    it("uses high-contrast foreground and background", function()
        assert.are_not.equal(theme.background, theme.digit)
        assert.are_not.equal(theme.background, theme.grid_thick)
        assert.are_not.equal(theme.grid_thick, theme.grid_thin)
        assert.are_not.equal(theme.digit, theme.note)
    end)

    it("keeps grid ink darker than the wrong-cell fill so digits stay readable", function()
        local function luminance(color)
            return tonumber(color.a)
        end
        assert.is_true(luminance(theme.wrong_fill) > luminance(theme.grid_thick))
        assert.is_true(luminance(theme.disabled) > luminance(theme.digit))
    end)
end)
