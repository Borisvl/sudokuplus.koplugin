local _ = require("gettext")

local techniques = {}

-- Canonical localized display names for all 17 solving techniques.
-- Evaluated dynamically through static getter closures to avoid per-call table allocations.
local GETTERS = {
    naked_singles = function()
        return _("Naked Singles")
    end,
    hidden_singles = function()
        return _("Hidden Singles")
    end,
    naked_pairs = function()
        return _("Naked Pairs")
    end,
    hidden_pairs = function()
        return _("Hidden Pairs")
    end,
    locked_candidates = function()
        return _("Locked Candidates")
    end,
    naked_triples = function()
        return _("Naked Triples")
    end,
    hidden_triples = function()
        return _("Hidden Triples")
    end,
    x_wing = function()
        return _("X-Wing")
    end,
    naked_quads = function()
        return _("Naked Quads")
    end,
    hidden_quads = function()
        return _("Hidden Quads")
    end,
    swordfish = function()
        return _("Swordfish")
    end,
    jellyfish = function()
        return _("Jellyfish")
    end,
    skyscraper = function()
        return _("Skyscraper")
    end,
    w_wing = function()
        return _("W-Wing")
    end,
    xy_wing = function()
        return _("XY-Wing")
    end,
    xyz_wing = function()
        return _("XYZ-Wing")
    end,
    aic = function()
        return _("Alternating Inference Chain")
    end,
}

function techniques.label(id)
    if not id then
        return nil
    end
    local getter = GETTERS[id]
    return getter and getter() or id
end

return techniques
