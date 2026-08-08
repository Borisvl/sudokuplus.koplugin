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

return util
