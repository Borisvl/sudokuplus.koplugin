package.path = "plugins/sudoku.koplugin/?.lua;" .. package.path

local bit = require("bit")
local masks = require("core.masks")

local function bit_of(n)
    return bit.lshift(1, n - 1)
end

local function bits(nums)
    local result = 0
    for _, n in ipairs(nums) do
        result = bit.bor(result, bit_of(n))
    end
    return result
end

describe("core.masks", function()
    it("initializes all masks to zero", function()
        local m = masks.new()
        for i = 1, 9 do
            assert.are.equal(0, m.row[i])
            assert.are.equal(0, m.col[i])
            assert.are.equal(0, m.box[i])
        end
    end)

    it("computes box indices", function()
        assert.are.equal(0, masks.get_box_idx(0, 0))
        assert.are.equal(0, masks.get_box_idx(1, 1))
        assert.are.equal(0, masks.get_box_idx(2, 2))
        assert.are.equal(4, masks.get_box_idx(3, 3))
        assert.are.equal(4, masks.get_box_idx(4, 4))
        assert.are.equal(4, masks.get_box_idx(5, 5))
        assert.are.equal(8, masks.get_box_idx(6, 6))
        assert.are.equal(8, masks.get_box_idx(7, 7))
        assert.are.equal(8, masks.get_box_idx(8, 8))
        assert.are.equal(1, masks.get_box_idx(0, 3))
        assert.are.equal(3, masks.get_box_idx(3, 0))
        assert.are.equal(2, masks.get_box_idx(0, 8))
        assert.are.equal(6, masks.get_box_idx(8, 0))
    end)

    it("matches the floor-division formula for every cell", function()
        -- L2: get_box_idx is a table lookup; it must stay identical to
        -- (r // 3) * 3 + (c // 3) for every valid coordinate.
        for r = 0, 8 do
            for c = 0, 8 do
                assert.are.equal(
                    math.floor(r / 3) * 3 + math.floor(c / 3),
                    masks.get_box_idx(r, c),
                    string.format("box index mismatch at (%d, %d)", r, c)
                )
            end
        end
    end)

    it("derives box start coordinates from a box index", function()
        for box_idx = 0, 8 do
            assert.are.equal(
                math.floor(box_idx / 3) * 3,
                masks.box_start_row(box_idx),
                string.format("box start row mismatch at box %d", box_idx)
            )
            assert.are.equal(
                (box_idx % 3) * 3,
                masks.box_start_col(box_idx),
                string.format("box start col mismatch at box %d", box_idx)
            )
        end
    end)

    it("adds a number to one cell", function()
        local m = masks.new()
        masks.add_number(m, 0, 0, 1)
        assert.are.equal(bit_of(1), m.row[1])
        assert.are.equal(bit_of(1), m.col[1])
        assert.are.equal(bit_of(1), m.box[1])
    end)

    it("adds multiple numbers in the same row", function()
        local m = masks.new()
        masks.add_number(m, 0, 0, 1)
        masks.add_number(m, 0, 1, 5)
        assert.are.equal(bits({ 1, 5 }), m.row[1])
        assert.are.equal(bit_of(1), m.col[1])
        assert.are.equal(bit_of(5), m.col[2])
        assert.are.equal(bits({ 1, 5 }), m.box[1])
    end)

    it("adds a number to a different box", function()
        local m = masks.new()
        masks.add_number(m, 8, 8, 9)
        assert.are.equal(bit_of(9), m.row[9])
        assert.are.equal(bit_of(9), m.col[9])
        assert.are.equal(bit_of(9), m.box[9])
    end)

    it("adding an already present number does not change masks", function()
        local m = masks.new()
        masks.add_number(m, 0, 0, 1)
        local before = m.row[1]
        masks.add_number(m, 0, 0, 1)
        assert.are.equal(before, m.row[1])
    end)

    it("removes a single number from a cell", function()
        local m = masks.new()
        masks.add_number(m, 0, 0, 1)
        masks.remove_number(m, 0, 0, 1)
        assert.are.equal(0, m.row[1])
        assert.are.equal(0, m.col[1])
        assert.are.equal(0, m.box[1])
    end)

    it("removes a number from a shared row", function()
        local m = masks.new()
        masks.add_number(m, 0, 0, 1)
        masks.add_number(m, 0, 1, 5)
        masks.remove_number(m, 0, 0, 1)
        assert.are.equal(bit_of(5), m.row[1])
        assert.are.equal(0, m.col[1])
        assert.are.equal(bit_of(5), m.col[2])
        assert.are.equal(bit_of(5), m.box[1])
    end)

    it("removing a number not present does not change masks", function()
        local m = masks.new()
        masks.add_number(m, 0, 0, 1)
        local before = m.row[1]
        masks.remove_number(m, 0, 0, 3)
        assert.are.equal(before, m.row[1])
    end)

    it("is_safe on an empty board is always true", function()
        local m = masks.new()
        assert.is_true(masks.is_safe(m, 0, 0, 1))
        assert.is_true(masks.is_safe(m, 8, 8, 9))
    end)

    it("detects conflicts in a row", function()
        local m = masks.new()
        masks.add_number(m, 0, 0, 1)
        assert.is_false(masks.is_safe(m, 0, 1, 1))
        assert.is_true(masks.is_safe(m, 0, 1, 2))
    end)

    it("detects conflicts in a column", function()
        local m = masks.new()
        masks.add_number(m, 0, 0, 1)
        assert.is_false(masks.is_safe(m, 1, 0, 1))
        assert.is_true(masks.is_safe(m, 1, 0, 2))
    end)

    it("detects conflicts in a box", function()
        local m = masks.new()
        masks.add_number(m, 1, 1, 1)
        assert.is_false(masks.is_safe(m, 0, 0, 1))
        assert.is_true(masks.is_safe(m, 0, 0, 2))
    end)

    it("is_safe conflicts with the current cell value", function()
        local m = masks.new()
        masks.add_number(m, 0, 0, 1)
        assert.is_false(masks.is_safe(m, 0, 0, 1))
        assert.is_true(masks.is_safe(m, 0, 0, 2))
    end)

    it("computes candidates for an empty cell as all available", function()
        local m = masks.new()
        assert.are.equal(0x1FF, masks.compute_candidates_mask_for_cell(m, 0, 0))
    end)

    it("computes candidates with a full row mask", function()
        local m = masks.new()
        m.row[1] = bits({ 1, 2, 3, 4, 5, 6, 7, 8 })
        assert.are.equal(bit_of(9), masks.compute_candidates_mask_for_cell(m, 0, 0))
    end)

    it("computes candidates with a full col mask", function()
        local m = masks.new()
        m.col[1] = bits({ 1, 2, 3, 4, 5, 6, 7, 8 })
        assert.are.equal(bit_of(9), masks.compute_candidates_mask_for_cell(m, 0, 0))
    end)

    it("computes candidates with a full box mask", function()
        local m = masks.new()
        m.box[masks.get_box_idx(1, 1) + 1] = bits({ 1, 2, 3, 4, 5, 6, 7, 8 })
        assert.are.equal(bit_of(9), masks.compute_candidates_mask_for_cell(m, 1, 1))
    end)

    it("computes candidates with mixed restrictions", function()
        local m = masks.new()
        m.row[1] = bits({ 1, 2 })
        m.col[1] = bits({ 3, 4 })
        m.box[1] = bits({ 5, 6 })
        assert.are.equal(bits({ 7, 8, 9 }), masks.compute_candidates_mask_for_cell(m, 0, 0))
    end)

    it("computes candidates when none are left", function()
        local m = masks.new()
        m.row[1] = 0x1FF
        assert.are.equal(0, masks.compute_candidates_mask_for_cell(m, 0, 0))
    end)
end)
