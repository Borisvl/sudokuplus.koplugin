local flags = require("sudokuplus.core.techniques.flags")
local masks = require("sudokuplus.core.masks")

local util = {}

local DIFFICULTIES = {
    beginner = true,
    easy = true,
    medium = true,
    hard = true,
    master = true,
    expert = true,
    custom = true,
}

local CUSTOM_TIERS = {
    medium = true,
    hard = true,
    master = true,
    expert = true,
}

function util.validate_custom_tier_and_techniques(tier, techniques, prefix)
    prefix = prefix or ""
    if type(tier) ~= "string" or not CUSTOM_TIERS[tier] then
        return nil, prefix .. "custom_tier must be one of medium, hard, master, expert"
    end
    if type(techniques) ~= "table" or #techniques == 0 then
        return nil, prefix .. "custom_techniques must be a non-empty list of technique ids"
    end
    local count = 0
    for k, _ in pairs(techniques) do
        if type(k) ~= "number" or k % 1 ~= 0 or k < 1 then
            return nil, prefix .. "custom_techniques must be a non-empty list of technique ids"
        end
        count = count + 1
    end
    if count ~= #techniques then
        return nil, prefix .. "custom_techniques must be a non-empty list of technique ids"
    end
    local valid_techs = flags.TECHNIQUES_BY_TIER[tier] or {}
    local valid_map = {}
    for _, t in ipairs(valid_techs) do
        valid_map[t.id] = true
    end
    local validated_techs = {}
    for i, t in ipairs(techniques) do
        if type(t) ~= "string" or not valid_map[t] then
            return nil, prefix .. "custom_techniques contains invalid technique id for tier"
        end
        validated_techs[i] = t
    end
    return tier, validated_techs
end

util.FULL_CANDIDATE_MASK = 0x1FF

function util.is_difficulty(value)
    if type(value) ~= "string" then
        return false
    end
    return DIFFICULTIES[value] or false
end

function util.is_finite(value)
    return value == value and value ~= math.huge and value ~= -math.huge
end

-- Rounds to whole seconds and formats as HH:MM:SS (the UI timer display).
function util.format_time(seconds)
    seconds = math.max(0, math.floor(seconds + 0.5))
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    return string.format("%02d:%02d:%02d", hours, minutes, seconds % 60)
end

-- Formats a seed into space-separated 4-digit groups (e.g. 4354 5433 6455 32).
function util.format_seed(seed)
    if seed == nil then
        return nil
    end
    local s = tostring(seed)
    local chunks = {}
    for i = 1, #s, 4 do
        chunks[#chunks + 1] = s:sub(i, i + 3)
    end
    return table.concat(chunks, " ")
end

function util.cell_index(r, c)
    return r * 9 + c + 1
end

function util.validate_cell(r, c)
    if type(r) ~= "number" or r % 1 ~= 0 or r < 0 or r > 8 then
        return nil, "row must be an integer in the range 0..8"
    end
    if type(c) ~= "number" or c % 1 ~= 0 or c < 0 or c > 8 then
        return nil, "column must be an integer in the range 0..8"
    end
    return true
end

function util.validate_value(value)
    if type(value) ~= "number" or value % 1 ~= 0 or value < 1 or value > 9 then
        return nil, "value must be an integer in the range 1..9"
    end
    return true
end

function util.validate_non_negative(value, name)
    if type(value) ~= "number" or value % 1 ~= 0 or value < 0 then
        return nil, name .. " must be a non-negative integer"
    end
    return true
end

function util.new_mask_grid(value)
    local grid = {}
    for row = 1, 9 do
        grid[row] = {}
        for col = 1, 9 do
            grid[row][col] = value or 0
        end
    end
    return grid
end

function util.deep_copy(value)
    if type(value) ~= "table" then
        return value
    end
    local copy = {}
    for key, nested in pairs(value) do
        copy[key] = util.deep_copy(nested)
    end
    return copy
end

-- Builds the constraint-mask structure (core.masks) that reflects `b`.
function util.constraint_masks_for(b)
    local m = masks.new()
    for i = 1, 81 do
        local value = b[i]
        if value ~= 0 then
            masks.add_number(m, math.floor((i - 1) / 9), (i - 1) % 9, value)
        end
    end
    return m
end

return util
