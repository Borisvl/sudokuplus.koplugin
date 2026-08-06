local flags = require("core.techniques.flags")
local fish = require("core.techniques.fish")

local swordfish = {}

function swordfish.apply(prop, path)
    return fish.apply(prop, path, 3, swordfish.flags(), "swordfish")
end

function swordfish.flags()
    return flags.SWORDFISH
end

return swordfish
