package.path = "plugins/sudokuplus.koplugin/?.lua;" .. package.path

local bit = require("bit")
local flags = require("sudokuplus.core.techniques.flags")

describe("core.techniques.flags", function()
    it("assigns bit positions per difficulty tier", function()
        assert.are.equal(1, flags.NAKED_SINGLES)
        assert.are.equal(2, flags.HIDDEN_SINGLES)
        assert.are.equal(bit.lshift(1, 8), flags.NAKED_PAIRS)
        assert.are.equal(bit.lshift(1, 9), flags.HIDDEN_PAIRS)
        assert.are.equal(bit.lshift(1, 10), flags.LOCKED_CANDIDATES)
        assert.are.equal(bit.lshift(1, 11), flags.NAKED_TRIPLES)
        assert.are.equal(bit.lshift(1, 12), flags.HIDDEN_TRIPLES)
        assert.are.equal(bit.lshift(1, 16), flags.X_WING)
        assert.are.equal(bit.lshift(1, 17), flags.NAKED_QUADS)
        assert.are.equal(bit.lshift(1, 18), flags.HIDDEN_QUADS)
        assert.are.equal(bit.lshift(1, 19), flags.SWORDFISH)
        assert.are.equal(bit.lshift(1, 20), flags.JELLYFISH)
        assert.are.equal(bit.lshift(1, 21), flags.SKYSCRAPER)
        assert.are.equal(bit.lshift(1, 24), flags.W_WING)
        assert.are.equal(bit.lshift(1, 25), flags.XY_WING)
        assert.are.equal(bit.lshift(1, 26), flags.XYZ_WING)
        assert.are.equal(bit.lshift(1, 27), flags.ALTERNATING_INFERENCE_CHAIN)
        assert.are.equal(bit.lshift(1, 28), flags.X_CHAIN)
        assert.are.equal(bit.lshift(1, 29), flags.XY_CHAIN)
    end)

    it("provides composite tier masks", function()
        assert.are.equal(0xFF, flags.BEGINNER)
        assert.are.equal(0xFF, flags.EASY)
        assert.are.equal(bit.bor(flags.NAKED_PAIRS, flags.LOCKED_CANDIDATES), flags.MEDIUM)
        assert.are.equal(bit.bor(flags.HIDDEN_PAIRS, bit.bor(flags.NAKED_TRIPLES, flags.HIDDEN_TRIPLES)), flags.HARD)
        assert.are.equal(
            bit.bor(
                flags.X_WING,
                bit.bor(
                    flags.NAKED_QUADS,
                    bit.bor(
                        flags.SKYSCRAPER,
                        bit.bor(flags.SWORDFISH, bit.bor(flags.W_WING, bit.bor(flags.XY_WING, flags.XYZ_WING)))
                    )
                )
            ),
            flags.MASTER
        )
        assert.are.equal(
            bit.bor(
                flags.HIDDEN_QUADS,
                bit.bor(
                    flags.JELLYFISH,
                    bit.bor(flags.ALTERNATING_INFERENCE_CHAIN, bit.bor(flags.X_CHAIN, flags.XY_CHAIN))
                )
            ),
            flags.EXPERT
        )
        assert.are.equal(
            bit.bor(flags.EASY, bit.bor(flags.MEDIUM, bit.bor(flags.HARD, bit.bor(flags.MASTER, flags.EXPERT)))),
            flags.ALL
        )
    end)

    it("provides cumulative tier masks", function()
        assert.are.equal(flags.EASY, flags.CUMULATIVE_TIER_FLAGS.easy)
        assert.are.equal(bit.bor(flags.EASY, flags.MEDIUM), flags.CUMULATIVE_TIER_FLAGS.medium)
        assert.are.equal(bit.bor(flags.EASY, bit.bor(flags.MEDIUM, flags.HARD)), flags.CUMULATIVE_TIER_FLAGS.hard)
        assert.are.equal(
            bit.bor(flags.EASY, bit.bor(flags.MEDIUM, bit.bor(flags.HARD, flags.MASTER))),
            flags.CUMULATIVE_TIER_FLAGS.master
        )
        assert.are.equal(flags.ALL, flags.CUMULATIVE_TIER_FLAGS.expert)
    end)

    it("ensures non-overlapping disjoint partition of difficulty tiers across ALL", function()
        local non_overlapping_tiers = {
            flags.EASY,
            flags.MEDIUM,
            flags.HARD,
            flags.MASTER,
            flags.EXPERT,
        }
        for i = 1, #non_overlapping_tiers do
            for j = i + 1, #non_overlapping_tiers do
                assert.are.equal(
                    0,
                    bit.band(non_overlapping_tiers[i], non_overlapping_tiers[j]),
                    string.format("tiers %d and %d must be strictly disjoint", i, j)
                )
            end
        end
        local combined = 0
        for _, mask in ipairs(non_overlapping_tiers) do
            combined = bit.bor(combined, mask)
        end
        assert.are.equal(flags.ALL, combined)
    end)

    it("counts set bits", function()
        assert.are.equal(0, flags.count(0))
        assert.are.equal(1, flags.count(flags.NAKED_SINGLES))
        assert.are.equal(3, flags.count(bit.bor(flags.NAKED_SINGLES, flags.HIDDEN_SINGLES, flags.NAKED_PAIRS)))
    end)

    it("finds the lowest set bit index", function()
        assert.is_nil(flags.lowest_bit(0))
        assert.are.equal(0, flags.lowest_bit(flags.NAKED_SINGLES))
        assert.are.equal(1, flags.lowest_bit(flags.HIDDEN_SINGLES))
        assert.are.equal(8, flags.lowest_bit(flags.NAKED_PAIRS))
        assert.are.equal(27, flags.lowest_bit(flags.ALTERNATING_INFERENCE_CHAIN))
        assert.are.equal(28, flags.lowest_bit(flags.X_CHAIN))
        assert.are.equal(29, flags.lowest_bit(flags.XY_CHAIN))
    end)

    it("maps flags to difficulty tiers", function()
        assert.are.equal("easy", flags.difficulty(flags.NAKED_SINGLES))
        assert.are.equal("easy", flags.difficulty(flags.HIDDEN_SINGLES))
        assert.are.equal("medium", flags.difficulty(flags.NAKED_PAIRS))
        assert.are.equal("medium", flags.difficulty(flags.LOCKED_CANDIDATES))
        assert.are.equal("hard", flags.difficulty(flags.HIDDEN_PAIRS))
        assert.are.equal("hard", flags.difficulty(flags.NAKED_TRIPLES))
        assert.are.equal("hard", flags.difficulty(flags.HIDDEN_TRIPLES))
        assert.are.equal("master", flags.difficulty(flags.X_WING))
        assert.are.equal("master", flags.difficulty(flags.SKYSCRAPER))
        assert.are.equal("master", flags.difficulty(flags.W_WING))
        assert.are.equal("master", flags.difficulty(flags.XY_WING))
        assert.are.equal("master", flags.difficulty(flags.XYZ_WING))
        assert.are.equal("master", flags.difficulty(flags.NAKED_QUADS))
        assert.are.equal("master", flags.difficulty(flags.SWORDFISH))
        assert.are.equal("expert", flags.difficulty(flags.HIDDEN_QUADS))
        assert.are.equal("expert", flags.difficulty(flags.JELLYFISH))
        assert.are.equal("expert", flags.difficulty(flags.ALTERNATING_INFERENCE_CHAIN))
        assert.are.equal("expert", flags.difficulty(flags.X_CHAIN))
        assert.are.equal("expert", flags.difficulty(flags.XY_CHAIN))
        assert.are.equal("easy", flags.difficulty(0))
    end)

    it("computes technique scores", function()
        assert.are.equal(0, flags.score(0))
        assert.are.equal(10, flags.score(flags.NAKED_SINGLES))
        assert.are.equal(12, flags.score(flags.HIDDEN_SINGLES))
        assert.are.equal(40, flags.score(flags.LOCKED_CANDIDATES))
        assert.are.equal(50, flags.score(flags.NAKED_PAIRS))
        assert.are.equal(120, flags.score(flags.X_WING))
        assert.are.equal(190, flags.score(flags.SWORDFISH))
        assert.are.equal(220, flags.score(flags.X_CHAIN))
        assert.are.equal(260, flags.score(flags.XY_CHAIN))
        assert.are.equal(300, flags.score(flags.ALTERNATING_INFERENCE_CHAIN))
    end)

    it("computes difficulty points (lowest bit + 1)", function()
        assert.are.equal(0, flags.difficulty_point(0))
        assert.are.equal(1, flags.difficulty_point(flags.NAKED_SINGLES))
        assert.are.equal(2, flags.difficulty_point(flags.HIDDEN_SINGLES))
        assert.are.equal(9, flags.difficulty_point(flags.NAKED_PAIRS))
        assert.are.equal(17, flags.difficulty_point(flags.X_WING))
        assert.are.equal(28, flags.difficulty_point(flags.ALTERNATING_INFERENCE_CHAIN))
        assert.are.equal(29, flags.difficulty_point(flags.X_CHAIN))
        assert.are.equal(30, flags.difficulty_point(flags.XY_CHAIN))
    end)

    it("preserves catalog integrity between flags, scores, and lookup tables (drift protection)", function()
        assert.are.equal(19, #flags.TECHNIQUES)
        for _, t in ipairs(flags.TECHNIQUES) do
            assert.is_table(flags.TECHNIQUE_BY_ID[t.id])
            assert.are.equal(t.id, flags.TECHNIQUE_BY_ID[t.id].id)
            assert.is_table(flags.TECHNIQUE_BY_FLAG[t.flag])
            assert.are.equal(t.flag, flags.TECHNIQUE_BY_FLAG[t.flag].flag)

            local sc = flags.TECHNIQUE_SCORES[t.flag]
            assert.is_number(sc)
            assert.is_true(sc > 0, "technique " .. t.id .. " must have a positive score")
        end

        for flag, _ in pairs(flags.TECHNIQUE_SCORES) do
            assert.is_table(flags.TECHNIQUE_BY_FLAG[flag], "TECHNIQUE_SCORES contains unknown flag: " .. tostring(flag))
        end

        assert.is_table(flags.TECHNIQUES_BY_TIER.medium)
        assert.is_table(flags.TECHNIQUES_BY_TIER.hard)
        assert.is_table(flags.TECHNIQUES_BY_TIER.master)
        assert.is_table(flags.TECHNIQUES_BY_TIER.expert)
    end)
end)
