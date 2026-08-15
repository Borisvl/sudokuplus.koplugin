local flags = require("core.techniques.flags")
local fish = require("core.techniques.fish")

local jellyfish = {}

function jellyfish.apply(prop, path)
    return fish.apply(prop, path, 4, jellyfish.flags(), "jellyfish")
end

function jellyfish.flags()
    return flags.JELLYFISH
end

return jellyfish
