local _ = require("gettext")

-- Ordered difficulty list for the picker and the stats screen.
local difficulties = {
    { id = "easy", label = _("Easy") },
    { id = "medium", label = _("Medium") },
    { id = "hard", label = _("Hard") },
    { id = "expert", label = _("Expert") },
}

function difficulties.list()
    local copy = {}
    for i, entry in ipairs(difficulties) do
        copy[i] = { id = entry.id, label = entry.label }
    end
    return copy
end

function difficulties.label(id)
    for _, entry in ipairs(difficulties) do
        if entry.id == id then
            return entry.label
        end
    end
    return nil
end

return difficulties
