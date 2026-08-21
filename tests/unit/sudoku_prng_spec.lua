package.path = "plugins/sudokuplus.koplugin/?.lua;" .. package.path

local prng = require("sudokuplus.core.prng")

local function sequence(seed, n)
    local rng = prng.new(seed)
    local out = {}
    for _ = 1, n do
        out[#out + 1] = rng:next()
    end
    return out
end

local function sorted(list)
    local out = {}
    for i = 1, #list do
        out[i] = list[i]
    end
    table.sort(out)
    return out
end

describe("core.prng", function()
    it("is deterministic for a given seed", function()
        assert.are.same(sequence(42, 20), sequence(42, 20))
        assert.are.same(sequence(0xDEADBEEF, 20), sequence(0xDEADBEEF, 20))
    end)

    it("produces different sequences for different seeds", function()
        local a = sequence(1, 20)
        local b = sequence(2, 20)
        local equal = true
        for i = 1, #a do
            if a[i] ~= b[i] then
                equal = false
                break
            end
        end
        assert.is_false(equal)
    end)

    it("defaults to a fixed seed (deterministic, no os.time)", function()
        assert.are.same(sequence(nil, 10), sequence(nil, 10))
    end)

    it("normalizes the seed before replacing a zero state", function()
        assert.are.same(sequence(nil, 10), sequence(0x100000000, 10))
    end)

    it("rejects non-integer seeds", function()
        for _, seed in ipairs({ 1.5, "42" }) do
            local ok = pcall(function()
                prng.new(seed)
            end)
            assert.is_false(ok, "new() should reject " .. tostring(seed))
        end
    end)

    it("next() returns values in the u32 range", function()
        local rng = prng.new(7)
        for _ = 1, 1000 do
            local v = rng:next()
            assert.is_true(v >= 0 and v <= 0xFFFFFFFF)
        end
    end)

    it("int(n) returns values in 1..n", function()
        local rng = prng.new(7)
        for _ = 1, 1000 do
            local v = rng:int(9)
            assert.is_true(v >= 1 and v <= 9)
        end
        for _ = 1, 1000 do
            local v = rng:int(81)
            assert.is_true(v >= 1 and v <= 81)
        end
    end)

    it("rejects non-positive and fractional int bounds", function()
        for _, n in ipairs({ 0, -1, 1.5 }) do
            local ok = pcall(function()
                prng.new(7):int(n)
            end)
            assert.is_false(ok, "int() should reject " .. tostring(n))
        end
    end)

    it("shuffle preserves elements and is deterministic", function()
        local base = { 1, 2, 3, 4, 5, 6, 7, 8, 9 }
        local a = prng.new(5):shuffle({ 1, 2, 3, 4, 5, 6, 7, 8, 9 })
        local b = prng.new(5):shuffle({ 1, 2, 3, 4, 5, 6, 7, 8, 9 })
        assert.are.same(a, b)
        assert.are.same(sorted(base), sorted(a))
        assert.are.same(base, sorted(a))
    end)

    it("shuffles in place and returns the list", function()
        local list = { 1, 2, 3, 4, 5 }
        local ret = prng.new(3):shuffle(list)
        assert.is_true(ret == list)
    end)
end)
