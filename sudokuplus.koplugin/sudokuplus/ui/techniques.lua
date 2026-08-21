local _ = require("gettext")
local board = require("sudokuplus.core.board")
local flags = require("sudokuplus.core.techniques.flags")
local solve_path = require("sudokuplus.core.solve_path")
local solver = require("sudokuplus.core.solver")

local techniques = {}

local DERIVE_CACHE = {}

-- Derives the required solving techniques for an 81-char board string or board table.
-- Memoized by puzzle board string with capped solver budget to avoid UI freezes.
function techniques.derive(puzzle_input)
    local puzzle_str
    local b
    if type(puzzle_input) == "string" then
        if #puzzle_input ~= 81 then
            return nil
        end
        puzzle_str = puzzle_input
    elseif type(puzzle_input) == "table" then
        puzzle_str = board.to_string(puzzle_input)
        b = puzzle_input
    else
        return nil
    end

    if DERIVE_CACHE[puzzle_str] ~= nil then
        return DERIVE_CACHE[puzzle_str] or nil
    end

    b = b or board.from_string(puzzle_str)
    if not b then
        DERIVE_CACHE[puzzle_str] = false
        return nil
    end

    -- Capped search_budget avoids UI thread freezes on non-logical or malformed boards.
    local s = solver.new(b, { techniques = flags.ALL, search_budget = 200 })
    if not s then
        DERIVE_CACHE[puzzle_str] = false
        return nil
    end
    local solutions = s:solve_until(1)
    if #solutions == 0 then
        DERIVE_CACHE[puzzle_str] = false
        return nil
    end
    local classification = solve_path.classify(solutions[1].solve_path, { clues = board.count_clues(b) })
    local result = classification.techniques
    DERIVE_CACHE[puzzle_str] = result or false
    return result
end

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
    x_chain = function()
        return _("X-Chain")
    end,
    xy_chain = function()
        return _("XY-Chain")
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

function techniques.by_tier(tier_id)
    local tier_techs = flags.TECHNIQUES_BY_TIER[tier_id]
    if not tier_techs then
        return {}
    end
    local result = {}
    for i, t in ipairs(tier_techs) do
        result[i] = {
            id = t.id,
            label = techniques.label(t.id),
        }
    end
    return result
end

local T = require("ffi/util").template

function techniques.format_required(list, max_items)
    if not list or #list == 0 then
        return nil
    end
    local non_basics = {}
    for _, id in ipairs(list) do
        if id ~= "naked_singles" and id ~= "hidden_singles" then
            local label = techniques.label(id)
            if label then
                non_basics[#non_basics + 1] = label
            end
        end
    end
    if #non_basics == 0 then
        return _("Singles only")
    end
    if max_items and #non_basics > max_items then
        local shown = {}
        for i = 1, max_items do
            shown[i] = non_basics[i]
        end
        local remaining = #non_basics - max_items
        return table.concat(shown, ", ") .. " " .. T(_("+%1 more"), tostring(remaining))
    end
    return table.concat(non_basics, ", ")
end

return techniques
