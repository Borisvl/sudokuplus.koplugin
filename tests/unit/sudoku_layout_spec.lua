package.path = "plugins/sudoku.koplugin/?.lua;" .. package.path

local layout = require("ui.layout")

-- Scale functions mimic Screen:scaleBySize for a given factor.
local function scaler(factor)
    return function(dp)
        return math.ceil(dp * factor)
    end
end

-- Approximate scale factors: Glo 6" (758x1024@212) ~1.26, Clara HD 6"
-- (1072x1448@300) ~1.79, Aura One 7.8" (1404x1872@300) ~2.34.
local GLO = 1.26
local CLARA = 1.79
local AURA = 2.34

describe("sudoku layout", function()
    it("validates its inputs", function()
        assert.is_nil(layout.compute())
        assert.is_nil(layout.compute("758", 1024, scaler(GLO)))
        assert.is_nil(layout.compute(758, "1024", scaler(GLO)))
        assert.is_nil(layout.compute(758, 1024, "not a function"))
        assert.is_nil(layout.compute(-1, 1024, scaler(GLO)))
    end)

    it("produces a square grid that fits inside the screen", function()
        for _, spec in ipairs({
            { 758, 1024, GLO },
            { 1072, 1448, CLARA },
            { 1404, 1872, AURA },
            { 1872, 1404, AURA },
            { 1024, 758, GLO },
        }) do
            local l = layout.compute(spec[1], spec[2], scaler(spec[3]))
            assert.is_not_nil(l)
            assert.are.equal(l.grid.w, l.grid.h)
            assert.is_true(l.grid.w > 0)
            assert.is_true(l.grid.x >= 0)
            assert.is_true(l.grid.y >= 0)
            assert.is_true(l.grid.x + l.grid.w <= spec[1])
            assert.is_true(l.grid.y + l.grid.h <= spec[2])
            assert.is_true(l.grid.cell > 0)
            assert.are.equal(l.grid.w, 9 * l.grid.cell + 6 * l.thin + 4 * l.thick)
            assert.is_true(l.thin < l.thick)
        end
    end)

    it("keeps the number and tool bars on screen with a gap from the grid", function()
        local l = layout.compute(1072, 1448, scaler(CLARA))
        assert.is_true(l.number_row.y + l.number_row.h <= 1448)
        assert.is_true(l.tool_row.y + l.tool_row.h <= l.number_row.y)
        assert.is_true(l.tool_row.y >= l.grid.y + l.grid.h)
        assert.is_true(l.tool_row.y - (l.grid.y + l.grid.h) >= l.gap)
        assert.are.equal(#l.number_row.buttons, 10)
        assert.are.equal(#l.tool_row.buttons, 5)
    end)

    it("tiles bar buttons without overflow", function()
        local l = layout.compute(758, 1024, scaler(GLO))
        for _, row in ipairs({ l.number_row, l.tool_row }) do
            local bw = math.floor(row.w / #row.buttons)
            assert.is_true(row.x >= 0)
            assert.is_true(row.x + row.w <= 758)
            for _, button in ipairs(row.buttons) do
                assert.is_true(button.x >= row.x)
                assert.is_true(button.x + button.w <= row.x + row.w)
                assert.are.equal(button.h, row.h)
                assert.are.equal(button.w, bw)
            end
        end
    end)

    it("maps every cell center back to its own cell", function()
        local l = layout.compute(1072, 1448, scaler(CLARA))
        for row = 0, 8 do
            for col = 0, 8 do
                local rect = layout.cell_rect(l, row, col)
                local hit = layout.hit(l, rect.x + math.floor(rect.w / 2), rect.y + math.floor(rect.h / 2))
                assert.is_not_nil(hit, "cell " .. row .. "," .. col)
                assert.are.equal(hit.kind, "cell")
                assert.are.equal(hit.row, row)
                assert.are.equal(hit.col, col)
            end
        end
    end)

    it("maps bar button centers to their ids", function()
        local l = layout.compute(1072, 1448, scaler(CLARA))
        local expected_numbers = { 1, 2, 3, 4, 5, 6, 7, 8, 9, "erase" }
        local expected_tools = { "undo", "redo", "notes", "check", "menu" }
        for i, button in ipairs(l.number_row.buttons) do
            local hit = layout.hit(l, button.x + math.floor(button.w / 2), button.y + math.floor(button.h / 2))
            assert.are.equal(hit.kind, "button")
            assert.are.equal(hit.id, expected_numbers[i])
        end
        for i, button in ipairs(l.tool_row.buttons) do
            local hit = layout.hit(l, button.x + math.floor(button.w / 2), button.y + math.floor(button.h / 2))
            assert.are.equal(hit.kind, "button")
            assert.are.equal(hit.id, expected_tools[i])
        end
    end)

    it("returns nil for taps outside the widget", function()
        local l = layout.compute(1072, 1448, scaler(CLARA))
        assert.is_nil(layout.hit(l, -1, -1))
        assert.is_nil(layout.hit(l, 0, 5000))
        assert.is_nil(layout.hit(l, 5000, 0))
    end)

    it("reports grid line geometry for painting", function()
        local l = layout.compute(1072, 1448, scaler(CLARA))
        local lines = layout.grid_lines(l)
        assert.are.equal(#lines.horizontal, 8)
        assert.are.equal(#lines.vertical, 8)
        local previous_y = -1
        for i, line in ipairs(lines.horizontal) do
            assert.is_true(line.y > previous_y)
            previous_y = line.y
            assert.are.equal(line.w, l.grid.w)
            if (i - 1) % 3 == 2 then
                assert.are.equal(line.thickness, l.thick)
            else
                assert.are.equal(line.thickness, l.thin)
            end
        end
        local previous_x = -1
        for i, line in ipairs(lines.vertical) do
            assert.is_true(line.x > previous_x)
            previous_x = line.x
            assert.are.equal(line.h, l.grid.h)
            if (i - 1) % 3 == 2 then
                assert.are.equal(line.thickness, l.thick)
            else
                assert.are.equal(line.thickness, l.thin)
            end
        end
    end)

    it("degrades gracefully on tiny screens", function()
        local l = layout.compute(200, 200, scaler(1.0))
        assert.is_not_nil(l)
        assert.is_true(l.grid.cell >= 0)
        local l2 = layout.compute(300, 400, scaler(1.0))
        assert.is_true(l2.grid.cell >= 1)
        assert.is_true(l2.number_row.y + l2.number_row.h <= 400)
    end)

    it("offers positive font sizes for givens, entries, notes and bar", function()
        local l = layout.compute(758, 1024, scaler(GLO))
        assert.is_true(l.fonts.given > l.fonts.user)
        assert.is_true(l.fonts.user > l.fonts.notes)
        assert.is_true(l.fonts.digit > 0)
        assert.is_true(l.fonts.label > 0)
        assert.is_true(l.fonts.notes > 0)
    end)
end)
