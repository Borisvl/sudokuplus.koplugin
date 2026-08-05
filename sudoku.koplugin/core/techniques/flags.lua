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

flags.EASY = 0xFF
flags.MEDIUM = 0xFF00
flags.HARD = 0xFF0000
flags.EXPERT = bit.tobit(0xFF000000)

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
    elseif bit.band(f, flags.HARD) ~= 0 then
        return "hard"
    elseif bit.band(f, flags.MEDIUM) ~= 0 then
        return "medium"
    end
    return "easy"
end

function flags.difficulty_point(f)
    if f == 0 then
        return 0
    end
    return flags.lowest_bit(f) + 1
end

return flags
