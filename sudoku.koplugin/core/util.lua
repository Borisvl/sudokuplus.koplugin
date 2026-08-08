local util = {}

local DIFFICULTIES = {
    easy = true,
    medium = true,
    hard = true,
    expert = true,
}

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

return util
