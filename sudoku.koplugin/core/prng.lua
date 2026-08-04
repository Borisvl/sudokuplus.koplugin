local bit = require("bit")

local prng = {}
local mt = {}

local DEFAULT_SEED = 0x9E3779B9

function prng.new(seed)
    local state = seed or DEFAULT_SEED
    if state == 0 then
        state = DEFAULT_SEED
    end
    return setmetatable({ state = bit.band(state, 0xFFFFFFFF) }, { __index = mt })
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
