local _ = require("gettext")

local messages = {}

-- User-facing translation mapper for game errors and notification strings
-- returned by the pure engine and state machine.
local GETTERS = {
    ["cannot modify a given cell"] = function()
        return _("Cannot modify a given cell.")
    end,
    ["cannot edit notes on a filled cell"] = function()
        return _("Cannot edit notes on a filled cell.")
    end,
    ["digit already present in the same row, column or box"] = function()
        return _("Digit already present in the same row, column, or box.")
    end,
    ["board has conflicts"] = function()
        return _("The board has conflicts. Fix them before asking for a hint.")
    end,
    ["board does not match the solution"] = function()
        return _("The board does not match the solution. Fix mistakes first.")
    end,
    ["action is stale"] = function()
        return _("The board has changed since this hint was generated.")
    end,
    ["candidate is already absent"] = function()
        return _("Candidate is already absent.")
    end,
    ["nothing to undo"] = function()
        return _("Nothing to undo.")
    end,
    ["nothing to redo"] = function()
        return _("Nothing to redo.")
    end,
    ["game is finished"] = function()
        return _("The game is finished.")
    end,
    ["game is already finished"] = function()
        return _("The game is already finished.")
    end,
    ["board is not solved"] = function()
        return _("The board is not solved.")
    end,
}

function messages.translate(msg)
    if not msg then
        return nil
    end
    local getter = GETTERS[msg]
    return getter and getter() or msg
end

function messages.keys()
    local keys = {}
    for k in pairs(GETTERS) do
        keys[#keys + 1] = k
    end
    table.sort(keys)
    return keys
end

return messages
