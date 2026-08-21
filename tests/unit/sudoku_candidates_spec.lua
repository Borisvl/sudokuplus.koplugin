package.path = "plugins/sudokuplus.koplugin/?.lua;" .. package.path

local bit = require("bit")
local board = require("sudokuplus.core.board")
local candidates = require("sudokuplus.core.candidates")
local masks = require("sudokuplus.core.masks")

local function bit_of(n)
    return bit.lshift(1, n - 1)
end

describe("core.candidates", function()
    it("returns no candidates for an empty mask", function()
        local c = candidates.new()
        assert.are.same({}, candidates.get_candidates(c, 0, 0))
    end)

    it("returns all candidates for a full mask", function()
        local c = candidates.new()
        candidates.set(c, 0, 0, 0x1FF)
        assert.are.same({ 1, 2, 3, 4, 5, 6, 7, 8, 9 }, candidates.get_candidates(c, 0, 0))
    end)

    it("returns single candidates", function()
        local c = candidates.new()
        candidates.set(c, 1, 2, bit_of(1))
        assert.are.same({ 1 }, candidates.get_candidates(c, 1, 2))
        candidates.set(c, 1, 2, bit_of(5))
        assert.are.same({ 5 }, candidates.get_candidates(c, 1, 2))
        candidates.set(c, 1, 2, bit_of(9))
        assert.are.same({ 9 }, candidates.get_candidates(c, 1, 2))
    end)

    it("returns multiple candidates", function()
        local c = candidates.new()
        local mask = bit.bor(bit_of(2), bit.bor(bit_of(4), bit_of(7)))
        candidates.set(c, 3, 4, mask)
        assert.are.same({ 2, 4, 7 }, candidates.get_candidates(c, 3, 4))
        local mask_1_9 = bit.bor(bit_of(1), bit_of(9))
        candidates.set(c, 3, 4, mask_1_9)
        assert.are.same({ 1, 9 }, candidates.get_candidates(c, 3, 4))
    end)

    it("keeps candidates per cell", function()
        local c = candidates.new()
        candidates.set(c, 0, 0, bit.bor(bit_of(1), bit_of(3)))
        candidates.set(c, 8, 8, bit.bor(bit_of(6), bit_of(8)))
        assert.are.same({ 1, 3 }, candidates.get_candidates(c, 0, 0))
        assert.are.same({ 6, 8 }, candidates.get_candidates(c, 8, 8))
        assert.are.same({}, candidates.get_candidates(c, 0, 1))
    end)

    it("counts candidates in a mask", function()
        assert.are.equal(0, candidates.count(0))
        assert.are.equal(9, candidates.count(0x1FF))
        assert.are.equal(3, candidates.count(bit.bor(bit_of(2), bit.bor(bit_of(4), bit_of(7)))))
    end)

    it("restores changed cells with a reversible trail", function()
        local c = candidates.new()
        candidates.set(c, 0, 0, bit_of(1))
        candidates.set(c, 0, 1, bit_of(2))
        local trail = candidates.new_trail()
        local marker = candidates.mark(trail)

        candidates.set(c, 0, 0, bit_of(3), trail)
        candidates.set(c, 0, 1, bit_of(4), trail)
        candidates.set(c, 0, 2, bit_of(5), trail)
        candidates.rollback(c, trail, marker)

        assert.are.equal(bit_of(1), candidates.get(c, 0, 0))
        assert.are.equal(bit_of(2), candidates.get(c, 0, 1))
        assert.are.equal(0, candidates.get(c, 0, 2))
        assert.are.equal(marker, candidates.mark(trail))
    end)

    it("expands a mask to numbers", function()
        assert.are.same({}, candidates.from_mask(0))
        assert.are.same({ 1, 2, 3, 4, 5, 6, 7, 8, 9 }, candidates.from_mask(0x1FF))
        assert.are.same({ 2, 4, 7 }, candidates.from_mask(bit.bor(bit_of(2), bit.bor(bit_of(4), bit_of(7)))))
    end)

    it("updates affected cells on placement", function()
        local b = board.new()
        local m = masks.new()
        masks.add_number(m, 0, 0, 1)
        board.set(b, 0, 0, 1)
        local c = candidates.new()
        for r = 0, 8 do
            for col = 0, 8 do
                if board.is_empty(b, r, col) then
                    candidates.set(c, r, col, masks.compute_candidates_mask_for_cell(m, r, col))
                end
            end
        end
        candidates.update_affected_cells_for(c, 0, 0, m, b, 1)
        assert.are.equal(0, candidates.get(c, 0, 0))
        local remaining = { 2, 3, 4, 5, 6, 7, 8, 9 }
        assert.are.same(remaining, candidates.get_candidates(c, 0, 1), "1 removed from row cells")
        assert.are.same(remaining, candidates.get_candidates(c, 1, 0), "1 removed from col cells")
        assert.are.same(remaining, candidates.get_candidates(c, 1, 1), "1 removed from box cells")
        assert.are.same(
            { 1, 2, 3, 4, 5, 6, 7, 8, 9 },
            candidates.get_candidates(c, 8, 8),
            "unaffected cells keep their candidates"
        )
    end)

    it("preserves logical eliminations when updating after a placement", function()
        local b = board.new()
        local m = masks.new()
        local c = candidates.new()
        candidates.set(c, 0, 1, 0x1FF)

        candidates.set(c, 0, 1, bit.band(candidates.get(c, 0, 1), bit.bnot(bit_of(1))))
        board.set(b, 0, 0, 2)
        masks.add_number(m, 0, 0, 2)
        candidates.update_affected_cells_for(c, 0, 0, m, b, 2)

        assert.are.equal(0, bit.band(candidates.get(c, 0, 1), bit_of(1)))
        assert.are.equal(0, bit.band(candidates.get(c, 0, 1), bit_of(2)))
    end)

    it("restores all affected cells after a trailed placement update", function()
        local b = board.new()
        local m = masks.new()
        local c = candidates.new()
        local trail = candidates.new_trail()
        for r = 0, 8 do
            for col = 0, 8 do
                candidates.set(c, r, col, 0x1FF)
            end
        end
        local before = candidates.clone(c)

        board.set(b, 0, 0, 1)
        masks.add_number(m, 0, 0, 1)
        candidates.update_affected_cells_for(c, 0, 0, m, b, 1, trail)
        candidates.rollback(c, trail, 0)

        assert.are.same(before, c)
    end)

    it("updates affected cells on removal", function()
        local b = board.new()
        local m = masks.new()
        local c = candidates.new()
        masks.add_number(m, 0, 0, 1)
        board.set(b, 0, 0, 1)
        for r = 0, 8 do
            for col = 0, 8 do
                if board.is_empty(b, r, col) then
                    candidates.set(c, r, col, masks.compute_candidates_mask_for_cell(m, r, col))
                end
            end
        end
        masks.remove_number(m, 0, 0, 1)
        board.set(b, 0, 0, 0)
        candidates.update_affected_cells_for(c, 0, 0, m, b, nil)
        assert.are.same(
            { 1, 2, 3, 4, 5, 6, 7, 8, 9 },
            candidates.get_candidates(c, 0, 0),
            "removed cell regains all candidates"
        )
    end)
end)
