local bit = require("bit")

local prng = {}
local mt = {}

local DEFAULT_SEED = 0x9E3779B9
local UINT32_MASK = 0xFFFFFFFF

local function normalize_seed(seed)
    if seed == nil then
        seed = DEFAULT_SEED
    end
    if type(seed) ~= "number" or seed % 1 ~= 0 then
        error("seed must be an integer")
    end

    local state = bit.band(seed, UINT32_MASK)
    if state == 0 then
        state = bit.band(DEFAULT_SEED, UINT32_MASK)
    end
    return state
end

function prng.new(seed)
    return setmetatable({ state = normalize_seed(seed) }, { __index = mt })
end

function mt:next()
    local x = self.state
    x = bit.bxor(x, bit.lshift(x, 13))
    x = bit.bxor(x, bit.rshift(x, 17))
    x = bit.bxor(x, bit.lshift(x, 5))
    self.state = bit.band(x, 0xFFFFFFFF)
    if self.state < 0 then
        return self.state + 0x100000000
    end
    return self.state
end

function mt:int(n)
    if type(n) ~= "number" or n % 1 ~= 0 or n <= 0 then
        error("n must be a positive integer")
    end
    return 1 + (self:next() % n)
end

function mt:shuffle(list)
    for i = #list, 2, -1 do
        local j = self:int(i)
        list[i], list[j] = list[j], list[i]
    end
    return list
end

return prng
