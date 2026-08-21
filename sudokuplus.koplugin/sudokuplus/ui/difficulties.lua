local _ = require("gettext")

local difficulties = {}

local ORDERED_IDS = { "beginner", "easy", "medium", "hard", "master", "expert" }
local ALL_DIFFICULTIES = { "beginner", "easy", "medium", "hard", "master", "expert", "custom" }

difficulties.ORDERED_IDS = ORDERED_IDS
difficulties.ALL_DIFFICULTIES = ALL_DIFFICULTIES

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
    custom = function()
        return _("Custom")
    end,
}

local T = require("ffi/util").template

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

function difficulties.format_display(difficulty, custom_tier)
    if not difficulty then
        return nil
    end
    if difficulty == "custom" then
        if custom_tier then
            local tier_label = difficulties.label(custom_tier) or custom_tier
            return T(_("Custom (%1)"), tier_label)
        end
        return difficulties.label("custom")
    end
    return difficulties.label(difficulty) or difficulty
end

return difficulties
