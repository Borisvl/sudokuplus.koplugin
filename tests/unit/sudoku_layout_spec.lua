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

    it("keeps the number and tool bars and hint banner on screen with gaps", function()
        local l = layout.compute(1072, 1448, scaler(CLARA))
        assert.is_true(l.number_row.y + l.number_row.h <= 1448)
        assert.is_true(l.tool_row.y + l.tool_row.h <= l.number_row.y)
        assert.is_true(l.banner.y + l.banner.h <= l.tool_row.y)
        assert.is_true(l.banner.y >= l.grid.y + l.grid.h)
        assert.is_true(l.banner.y - (l.grid.y + l.grid.h) >= l.gap)
        assert.is_true(l.tool_row.y - (l.banner.y + l.banner.h) >= l.gap)
        assert.are.equal(#l.number_row.buttons, 10)
        assert.are.equal(#l.tool_row.buttons, 6)
    end)

    it("keeps the portrait grid width-constrained with the banner reserved", function()
        for _, spec in ipairs({
            { 758, 1024, GLO },
            { 1072, 1448, CLARA },
            { 1404, 1872, AURA },
        }) do
            local l = layout.compute(spec[1], spec[2], scaler(spec[3]))
            assert.is_true(l.banner.h > 0)
            assert.is_true(l.grid.w <= spec[1] - 2 * l.margin)
            assert.is_true(l.grid.y + l.grid.h + l.gap < l.banner.y, "the banner must not shrink the portrait grid")
        end
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
        local expected_tools = { "undo", "redo", "notes", "check", "hint", "menu" }
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
        assert.is_true(l.fonts.given >= 36, "board digits must be large")
        assert.is_true(l.fonts.user >= 32, "entered digits must be large")
        assert.is_true(l.fonts.label >= 18, "button labels must be legible")
        assert.is_true(l.fonts.notes >= 16, "notes must be legible")
    end)

    it("returns nil for an empty cell set", function()
        local l = layout.compute(758, 1024, scaler(GLO))
        assert.is_nil(layout.cells_region(l, {}))
        assert.is_nil(layout.cells_region(l, { [99999] = true }), "invalid keys are ignored")
    end)

    it("returns the exact rect for a single cell", function()
        local l = layout.compute(758, 1024, scaler(GLO))
        local rect = layout.cell_rect(l, 3, 4)
        local region = layout.cells_region(l, { [3 * 9 + 4] = true })
        assert.is_not_nil(region)
        assert.are.equal(rect.x, region.x)
        assert.are.equal(rect.y, region.y)
        assert.are.equal(rect.w, region.w)
        assert.are.equal(rect.h, region.h)
    end)

    it("returns the bounding box of distant cells", function()
        local l = layout.compute(758, 1024, scaler(GLO))
        local a = layout.cell_rect(l, 0, 0)
        local b = layout.cell_rect(l, 8, 8)
        local region = layout.cells_region(l, { [0] = true, [8 * 9 + 8] = true })
        assert.is_not_nil(region)
        assert.are.equal(a.x, region.x)
        assert.are.equal(a.y, region.y)
        assert.are.equal(b.x + b.w - a.x, region.w)
        assert.are.equal(b.y + b.h - a.y, region.h)
    end)

    it("squares off the box when cells span rows and columns", function()
        local l = layout.compute(1072, 1448, scaler(CLARA))
        local a = layout.cell_rect(l, 0, 5)
        local b = layout.cell_rect(l, 4, 0)
        local region = layout.cells_region(l, { [0 * 9 + 5] = true, [4 * 9 + 0] = true })
        assert.is_not_nil(region)
        assert.are.equal(b.x, region.x)
        assert.are.equal(a.y, region.y)
        assert.are.equal(a.x + a.w - b.x, region.w)
        assert.are.equal(b.y + b.h - a.y, region.h)
    end)

    it("returns no regions for an empty cell set", function()
        local l = layout.compute(758, 1024, scaler(GLO))
        assert.are.equal(0, #layout.cells_regions(l, {}))
        assert.are.equal(0, #layout.cells_regions(l, { [99999] = true }), "invalid keys are ignored")
    end)

    it("returns the exact rect for a single cell", function()
        local l = layout.compute(758, 1024, scaler(GLO))
        local rect = layout.cell_rect(l, 3, 4)
        local regions = layout.cells_regions(l, { [3 * 9 + 4] = true })
        assert.are.equal(1, #regions)
        assert.are.equal(rect.x, regions[1].x)
        assert.are.equal(rect.y, regions[1].y)
        assert.are.equal(rect.w, regions[1].w)
        assert.are.equal(rect.h, regions[1].h)
    end)

    it("keeps distant cells as separate regions", function()
        local l = layout.compute(758, 1024, scaler(GLO))
        local a = layout.cell_rect(l, 0, 0)
        local b = layout.cell_rect(l, 8, 8)
        local regions = layout.cells_regions(l, { [0] = true, [8 * 9 + 8] = true })
        assert.are.equal(2, #regions)
        assert.are.equal(a.x, regions[1].x)
        assert.are.equal(a.y, regions[1].y)
        assert.are.equal(b.x, regions[2].x)
        assert.are.equal(b.y, regions[2].y)
    end)

    it("clusters cells that fit within a 2x2 cell block", function()
        local l = layout.compute(758, 1024, scaler(GLO))
        local a = layout.cell_rect(l, 3, 4)
        local b = layout.cell_rect(l, 3, 5)
        local horizontal = layout.cells_regions(l, { [3 * 9 + 4] = true, [3 * 9 + 5] = true })
        assert.are.equal(1, #horizontal)
        assert.are.equal(a.x, horizontal[1].x)
        assert.are.equal(a.y, horizontal[1].y)
        assert.are.equal(b.x + b.w - a.x, horizontal[1].w, "strip spans the border between the cells")
        assert.are.equal(a.h, horizontal[1].h)
        local c = layout.cell_rect(l, 4, 4)
        local vertical = layout.cells_regions(l, { [3 * 9 + 4] = true, [4 * 9 + 4] = true })
        assert.are.equal(1, #vertical, "cells stacked in a column cluster too")
        assert.are.equal(c.y + c.h - a.y, vertical[1].h)
        local d = layout.cell_rect(l, 4, 5)
        local diagonal = layout.cells_regions(l, { [3 * 9 + 4] = true, [4 * 9 + 5] = true })
        assert.are.equal(1, #diagonal, "a 2x2 corner fits the cluster bound")
        assert.are.equal(d.x + d.w - a.x, diagonal[1].w)
        assert.are.equal(d.y + d.h - a.y, diagonal[1].h)
    end)

    it("keeps cells separated by more than one row or column in separate regions", function()
        local l = layout.compute(1072, 1448, scaler(CLARA))
        local regions = layout.cells_regions(l, { [0 * 9 + 5] = true, [0 * 9 + 1] = true, [4 * 9 + 5] = true })
        assert.are.equal(3, #regions)
        assert.are.equal(layout.cell_rect(l, 0, 1).x, regions[1].x)
        assert.are.equal(layout.cell_rect(l, 0, 5).x, regions[2].x)
        assert.are.equal(layout.cell_rect(l, 4, 5).x, regions[3].x)
        local wide_gap = layout.cells_regions(l, { [3 * 9 + 3] = true, [3 * 9 + 6] = true })
        assert.are.equal(2, #wide_gap, "three columns of gap do not merge")
    end)
end)
