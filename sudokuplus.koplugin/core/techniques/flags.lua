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

-- Beginner and Easy share the same technique mask (naked & hidden singles);
-- the difficulty split is determined by clue count (>= 38 for beginner) in
-- solve_path.classify.
flags.BEGINNER = 0xFF
flags.EASY = 0xFF
flags.MEDIUM = bit.bor(flags.NAKED_PAIRS, flags.LOCKED_CANDIDATES)
flags.HARD = bit.bor(flags.HIDDEN_PAIRS, bit.bor(flags.NAKED_TRIPLES, flags.HIDDEN_TRIPLES))
flags.MASTER = bit.bor(
    flags.X_WING,
    bit.bor(flags.NAKED_QUADS, bit.bor(flags.SKYSCRAPER, bit.bor(flags.W_WING, bit.bor(flags.XY_WING, flags.XYZ_WING))))
)
flags.EXPERT =
    bit.bor(flags.HIDDEN_QUADS, bit.bor(flags.SWORDFISH, bit.bor(flags.JELLYFISH, flags.ALTERNATING_INFERENCE_CHAIN)))

flags.ALL = bit.bor(flags.EASY, bit.bor(flags.MEDIUM, bit.bor(flags.HARD, bit.bor(flags.MASTER, flags.EXPERT))))

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
    [flags.HIDDEN_QUADS] = 200,
    [flags.SWORDFISH] = 220,
    [flags.JELLYFISH] = 260,
    [flags.ALTERNATING_INFERENCE_CHAIN] = 300,
}

flags.TECHNIQUES = {
    { id = "naked_singles", name = "Naked Singles", flag = flags.NAKED_SINGLES },
    { id = "hidden_singles", name = "Hidden Singles", flag = flags.HIDDEN_SINGLES },
    { id = "locked_candidates", name = "Locked Candidates", flag = flags.LOCKED_CANDIDATES },
    { id = "naked_pairs", name = "Naked Pairs", flag = flags.NAKED_PAIRS },
    { id = "hidden_pairs", name = "Hidden Pairs", flag = flags.HIDDEN_PAIRS },
    { id = "naked_triples", name = "Naked Triples", flag = flags.NAKED_TRIPLES },
    { id = "hidden_triples", name = "Hidden Triples", flag = flags.HIDDEN_TRIPLES },
    { id = "x_wing", name = "X-Wing", flag = flags.X_WING },
    { id = "skyscraper", name = "Skyscraper", flag = flags.SKYSCRAPER },
    { id = "xy_wing", name = "XY-Wing", flag = flags.XY_WING },
    { id = "xyz_wing", name = "XYZ-Wing", flag = flags.XYZ_WING },
    { id = "w_wing", name = "W-Wing", flag = flags.W_WING },
    { id = "naked_quads", name = "Naked Quads", flag = flags.NAKED_QUADS },
    { id = "swordfish", name = "Swordfish", flag = flags.SWORDFISH },
    { id = "hidden_quads", name = "Hidden Quads", flag = flags.HIDDEN_QUADS },
    { id = "jellyfish", name = "Jellyfish", flag = flags.JELLYFISH },
    { id = "aic", name = "Alternating Inference Chain", flag = flags.ALTERNATING_INFERENCE_CHAIN },
}

flags.TECHNIQUE_BY_ID = {}
flags.TECHNIQUE_BY_FLAG = {}
for _, technique in ipairs(flags.TECHNIQUES) do
    flags.TECHNIQUE_BY_ID[technique.id] = technique
    flags.TECHNIQUE_BY_FLAG[technique.flag] = technique
end

function flags.count(mask)
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
