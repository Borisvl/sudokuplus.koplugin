local _ = require("gettext")

local difficulties = {}

local ORDERED_IDS = { "beginner", "easy", "medium", "hard", "master", "expert" }

-- Ordered difficulty definitions for the picker and the stats screen.
-- Evaluated dynamically through static getters so language changes immediately update all labels
-- without transient per-lookup table allocations.
local GETTERS = {
    beginner = function()
        return _("Beginner")
    end,
    easy = function()
        return _("Easy")
    end,
    medium = function()
        return _("Medium")
    end,
    hard = function()
        return _("Hard")
    end,
    master = function()
        return _("Master")
    end,
    expert = function()
        return _("Expert")
    end,
}

function difficulties.list()
    local list = {}
    for i, id in ipairs(ORDERED_IDS) do
        local getter = GETTERS[id]
        list[i] = { id = id, label = getter and getter() or id }
    end
    return list
end

function difficulties.label(id)
    if not id then
        return nil
    end
    local getter = GETTERS[id]
    return getter and getter() or nil
end

return difficulties
