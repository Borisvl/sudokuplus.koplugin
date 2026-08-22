local bit = require("bit")

local flags = {}

flags.NAKED_SINGLES = bit.lshift(1, 0)
flags.HIDDEN_SINGLES = bit.lshift(1, 1)

flags.NAKED_PAIRS = bit.lshift(1, 8)
flags.HIDDEN_PAIRS = bit.lshift(1, 9)
flags.LOCKED_CANDIDATES = bit.lshift(1, 10)
flags.NAKED_TRIPLES = bit.lshift(1, 11)
flags.HIDDEN_TRIPLES = bit.lshift(1, 12)

flags.X_WING = bit.lshift(1, 16)
flags.NAKED_QUADS = bit.lshift(1, 17)
flags.HIDDEN_QUADS = bit.lshift(1, 18)
flags.SWORDFISH = bit.lshift(1, 19)
flags.JELLYFISH = bit.lshift(1, 20)
flags.SKYSCRAPER = bit.lshift(1, 21)

flags.W_WING = bit.lshift(1, 24)
flags.XY_WING = bit.lshift(1, 25)
flags.XYZ_WING = bit.lshift(1, 26)
flags.ALTERNATING_INFERENCE_CHAIN = bit.lshift(1, 27)
flags.X_CHAIN = bit.lshift(1, 28)
flags.XY_CHAIN = bit.lshift(1, 29)

-- Beginner and Easy share the same technique mask (naked & hidden singles);
-- the difficulty split is determined by clue count (>= 38 for beginner) in
-- solve_path.classify.
flags.BEGINNER = 0xFF
flags.EASY = 0xFF
flags.MEDIUM = bit.bor(flags.NAKED_PAIRS, flags.LOCKED_CANDIDATES)
flags.HARD = bit.bor(flags.HIDDEN_PAIRS, bit.bor(flags.NAKED_TRIPLES, flags.HIDDEN_TRIPLES))
flags.MASTER = bit.bor(
    flags.X_WING,
    bit.bor(
        flags.NAKED_QUADS,
        bit.bor(
            flags.SKYSCRAPER,
            bit.bor(flags.SWORDFISH, bit.bor(flags.W_WING, bit.bor(flags.XY_WING, flags.XYZ_WING)))
        )
    )
)
flags.EXPERT = bit.bor(
    flags.HIDDEN_QUADS,
    bit.bor(flags.JELLYFISH, bit.bor(flags.ALTERNATING_INFERENCE_CHAIN, bit.bor(flags.X_CHAIN, flags.XY_CHAIN)))
)

flags.ALL = bit.bor(flags.EASY, bit.bor(flags.MEDIUM, bit.bor(flags.HARD, bit.bor(flags.MASTER, flags.EXPERT))))

flags.CUMULATIVE_TIER_FLAGS = {
    beginner = flags.BEGINNER,
    easy = flags.EASY,
    medium = bit.bor(flags.EASY, flags.MEDIUM),
    hard = bit.bor(flags.EASY, bit.bor(flags.MEDIUM, flags.HARD)),
    master = bit.bor(flags.EASY, bit.bor(flags.MEDIUM, bit.bor(flags.HARD, flags.MASTER))),
    expert = flags.ALL,
}

flags.TECHNIQUE_SCORES = {
    [flags.NAKED_SINGLES] = 10,
    [flags.HIDDEN_SINGLES] = 12,
    [flags.LOCKED_CANDIDATES] = 40,
    [flags.NAKED_PAIRS] = 50,
    [flags.HIDDEN_PAIRS] = 60,
    [flags.NAKED_TRIPLES] = 80,
    [flags.HIDDEN_TRIPLES] = 100,
    [flags.X_WING] = 120,
    [flags.SKYSCRAPER] = 130,
    [flags.NAKED_QUADS] = 140,
    [flags.W_WING] = 150,
    [flags.XY_WING] = 160,
    [flags.XYZ_WING] = 180,
    [flags.SWORDFISH] = 190,
    [flags.HIDDEN_QUADS] = 200,
    [flags.X_CHAIN] = 220,
    [flags.XY_CHAIN] = 260,
    [flags.JELLYFISH] = 280,
    [flags.ALTERNATING_INFERENCE_CHAIN] = 300,
}

flags.TECHNIQUES = {
    { id = "naked_singles", name = "Naked Singles", flag = flags.NAKED_SINGLES, tier = "easy" },
    { id = "hidden_singles", name = "Hidden Singles", flag = flags.HIDDEN_SINGLES, tier = "easy" },
    { id = "locked_candidates", name = "Locked Candidates", flag = flags.LOCKED_CANDIDATES, tier = "medium" },
    { id = "naked_pairs", name = "Naked Pairs", flag = flags.NAKED_PAIRS, tier = "medium" },
    { id = "hidden_pairs", name = "Hidden Pairs", flag = flags.HIDDEN_PAIRS, tier = "hard" },
    { id = "naked_triples", name = "Naked Triples", flag = flags.NAKED_TRIPLES, tier = "hard" },
    { id = "hidden_triples", name = "Hidden Triples", flag = flags.HIDDEN_TRIPLES, tier = "hard" },
    { id = "x_wing", name = "X-Wing", flag = flags.X_WING, tier = "master" },
    { id = "swordfish", name = "Swordfish", flag = flags.SWORDFISH, tier = "master" },
    { id = "skyscraper", name = "Skyscraper", flag = flags.SKYSCRAPER, tier = "master" },
    { id = "xy_wing", name = "XY-Wing", flag = flags.XY_WING, tier = "master" },
    { id = "xyz_wing", name = "XYZ-Wing", flag = flags.XYZ_WING, tier = "master" },
    { id = "w_wing", name = "W-Wing", flag = flags.W_WING, tier = "master" },
    { id = "naked_quads", name = "Naked Quads", flag = flags.NAKED_QUADS, tier = "master" },
    { id = "x_chain", name = "X-Chain", flag = flags.X_CHAIN, tier = "expert" },
    { id = "xy_chain", name = "XY-Chain", flag = flags.XY_CHAIN, tier = "expert" },
    { id = "hidden_quads", name = "Hidden Quads", flag = flags.HIDDEN_QUADS, tier = "expert" },
    { id = "jellyfish", name = "Jellyfish", flag = flags.JELLYFISH, tier = "expert" },
    { id = "aic", name = "Alternating Inference Chain", flag = flags.ALTERNATING_INFERENCE_CHAIN, tier = "expert" },
}

flags.TECHNIQUE_BY_ID = {}
flags.TECHNIQUE_BY_FLAG = {}
for _, technique in ipairs(flags.TECHNIQUES) do
    flags.TECHNIQUE_BY_ID[technique.id] = technique
    flags.TECHNIQUE_BY_FLAG[technique.flag] = technique
end

flags.TECHNIQUES_BY_TIER = {
    medium = {
        flags.TECHNIQUE_BY_ID["locked_candidates"],
        flags.TECHNIQUE_BY_ID["naked_pairs"],
    },
    hard = {
        flags.TECHNIQUE_BY_ID["hidden_pairs"],
        flags.TECHNIQUE_BY_ID["naked_triples"],
        flags.TECHNIQUE_BY_ID["hidden_triples"],
    },
    master = {
        flags.TECHNIQUE_BY_ID["x_wing"],
        flags.TECHNIQUE_BY_ID["swordfish"],
        flags.TECHNIQUE_BY_ID["skyscraper"],
        flags.TECHNIQUE_BY_ID["xy_wing"],
        flags.TECHNIQUE_BY_ID["xyz_wing"],
        flags.TECHNIQUE_BY_ID["w_wing"],
        flags.TECHNIQUE_BY_ID["naked_quads"],
    },
    expert = {
        flags.TECHNIQUE_BY_ID["x_chain"],
        flags.TECHNIQUE_BY_ID["xy_chain"],
        flags.TECHNIQUE_BY_ID["aic"],
        flags.TECHNIQUE_BY_ID["jellyfish"],
        flags.TECHNIQUE_BY_ID["hidden_quads"],
    },
}

-- Candidate masks are always nine bits. Keep the general fallback because
-- this helper also counts the wider technique-flag masks above.
local CANDIDATE_BIT_COUNTS = { [0] = 0 }
for mask = 1, 0x1FF do
    CANDIDATE_BIT_COUNTS[mask] = CANDIDATE_BIT_COUNTS[math.floor(mask / 2)] + (mask % 2)
end

function flags.count(mask)
    local candidate_count = CANDIDATE_BIT_COUNTS[mask]
    if candidate_count ~= nil then
        return candidate_count
    end
    local count = 0
    while mask ~= 0 do
        mask = bit.band(mask, mask - 1)
        count = count + 1
    end
    return count
end

function flags.lowest_bit(mask)
    local index = 0
    while mask ~= 0 do
        if bit.band(mask, 1) ~= 0 then
            return index
        end
        mask = bit.rshift(mask, 1)
        index = index + 1
    end
    return nil
end

function flags.difficulty(f)
    if bit.band(f, flags.EXPERT) ~= 0 then
        return "expert"
    elseif bit.band(f, flags.MASTER) ~= 0 then
        return "master"
    elseif bit.band(f, flags.HARD) ~= 0 then
        return "hard"
    elseif bit.band(f, flags.MEDIUM) ~= 0 then
        return "medium"
    end
    return "easy"
end

function flags.score(f)
    if not f or f == 0 then
        return 0
    end
    local total = 0
    for flag, sc in pairs(flags.TECHNIQUE_SCORES) do
        if bit.band(f, flag) ~= 0 then
            total = total + sc
        end
    end
    return total > 0 and total or 10
end

function flags.difficulty_point(f)
    if f == 0 then
        return 0
    end
    return flags.lowest_bit(f) + 1
end

return flags
