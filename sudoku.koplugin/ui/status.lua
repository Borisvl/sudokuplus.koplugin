local _ = require("gettext")

local status = {}

-- Localized status labels for game history entries and stats view.
-- Evaluated dynamically through static getter closures.
local STATUS_GETTERS = {
    in_progress = function()
        return _("In progress")
    end,
    finished = function()
        return _("Finished")
    end,
    give_up = function()
        return _("Given up")
    end,
    abandoned = function()
        return _("Abandoned")
    end,
}

function status.label(s)
    if not s then
        return nil
    end
    local getter = STATUS_GETTERS[s]
    return getter and getter() or s
end

return status
