local flags = require("core.techniques.flags")
local fish = require("core.techniques.fish")

local x_wing = {}

function x_wing.apply(prop, path)
    return fish.apply(prop, path, 2, x_wing.flags(), "x_wing")
end

function x_wing.flags()
    return flags.X_WING
end

return x_wing
