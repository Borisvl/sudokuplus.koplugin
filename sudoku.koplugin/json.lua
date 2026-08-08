-- Minimal strict JSON encoder/decoder for plain data (strings, numbers,
-- booleans, arrays, objects). Deterministic key order; rejects cycles,
-- non-finite numbers, and malformed input.

local json = {}

local function escape_char(char)
    local byte = char:byte()
    if byte == 34 then
        return '\\"'
    elseif byte == 92 then
        return "\\\\"
    elseif byte == 8 then
        return "\\b"
    elseif byte == 9 then
        return "\\t"
    elseif byte == 10 then
        return "\\n"
    elseif byte == 12 then
        return "\\f"
    elseif byte == 13 then
        return "\\r"
    elseif byte < 32 then
        return string.format("\\u%04x", byte)
    end
    return char
end

local function escape_string(value)
    local escaped = value:gsub(".", escape_char)
    return '"' .. escaped .. '"'
end

local function encode_number(value)
    if value ~= value or value == math.huge or value == -math.huge then
        return nil, "cannot encode non-finite numbers"
    end
    return tostring(value)
end

local function is_array(value)
    local index = 0
    for key in pairs(value) do
        if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > #value then
            return false
        end
        if key > index then
            index = key
        end
    end
    return index == #value
end

local function encode_value(value, seen)
    local value_type = type(value)
    if value_type == "string" then
        return escape_string(value)
    elseif value_type == "number" then
        local encoded, err = encode_number(value)
        if not encoded then
            return nil, err
        end
        return encoded
    elseif value_type == "boolean" then
        return value and "true" or "false"
    elseif value_type ~= "table" then
        return nil, "cannot encode " .. value_type
    end

    if seen[value] then
        return nil, "cannot encode cyclic tables"
    end
    seen[value] = true

    local result
    if is_array(value) then
        local parts = {}
        for i = 1, #value do
            local encoded, err = encode_value(value[i], seen)
            if not encoded then
                seen[value] = nil
                return nil, err
            end
            parts[i] = encoded
        end
        result = "[" .. table.concat(parts, ",") .. "]"
    else
        local keys = {}
        for key in pairs(value) do
            if type(key) ~= "string" then
                seen[value] = nil
                return nil, "object keys must be strings"
            end
            keys[#keys + 1] = key
        end
        table.sort(keys)
        local parts = {}
        for i, key in ipairs(keys) do
            local encoded, err = encode_value(value[key], seen)
            if not encoded then
                seen[value] = nil
                return nil, err
            end
            parts[i] = escape_string(key) .. ":" .. encoded
        end
        result = "{" .. table.concat(parts, ",") .. "}"
    end

    seen[value] = nil
    return result
end

function json.encode(value)
    return encode_value(value, {})
end

local function decode_error(position, message)
    return nil, "invalid JSON at position " .. position .. ": " .. message
end

local function skip_whitespace(d)
    local text = d.text
    while d.position <= d.length do
        local char = text:sub(d.position, d.position)
        if char ~= " " and char ~= "\t" and char ~= "\n" and char ~= "\r" then
            break
        end
        d.position = d.position + 1
    end
end

local function decode_string(d)
    -- d.position is at the opening quote.
    local text = d.text
    local position = d.position + 1
    local out = {}
    while position <= d.length do
        local char = text:sub(position, position)
        if char == '"' then
            d.position = position + 1
            return table.concat(out)
        elseif char == "\\" then
            local next_char = text:sub(position + 1, position + 1)
            if next_char == '"' then
                out[#out + 1] = '"'
            elseif next_char == "\\" then
                out[#out + 1] = "\\"
            elseif next_char == "/" then
                out[#out + 1] = "/"
            elseif next_char == "b" then
                out[#out + 1] = "\b"
            elseif next_char == "f" then
                out[#out + 1] = "\f"
            elseif next_char == "n" then
                out[#out + 1] = "\n"
            elseif next_char == "r" then
                out[#out + 1] = "\r"
            elseif next_char == "t" then
                out[#out + 1] = "\t"
            elseif next_char == "u" then
                local hex = text:sub(position + 2, position + 5)
                if not hex:match("^%x%x%x%x$") then
                    return decode_error(position, "invalid unicode escape")
                end
                out[#out + 1] = string.char(tonumber(hex, 16))
                position = position + 4
            else
                return decode_error(position, "invalid escape sequence")
            end
            position = position + 2
        elseif char == "\0" then
            return decode_error(position, "unterminated string")
        else
            out[#out + 1] = char
            position = position + 1
        end
    end
    return decode_error(position, "unterminated string")
end

local function decode_number(d)
    local text = d.text
    local position = d.position
    local rest = text:sub(position)

    local sign = ""
    if rest:sub(1, 1) == "-" then
        sign = "-"
        rest = rest:sub(2)
    end

    local mantissa = rest:match("^(%d+%.?%d*)")
    if not mantissa then
        return decode_error(position, "invalid number")
    end
    local digits = mantissa:match("^(%d+)")
    if #digits > 1 and digits:sub(1, 1) == "0" then
        return decode_error(position, "invalid number")
    end
    if mantissa:match("%.$") then
        return decode_error(position, "invalid number")
    end

    local remainder = rest:sub(#mantissa + 1)
    local exponent = ""
    if remainder:sub(1, 1) == "e" or remainder:sub(1, 1) == "E" then
        local exp_match = remainder:match("^[eE][+-]?%d+")
        if not exp_match then
            return decode_error(position, "invalid number")
        end
        exponent = exp_match
        remainder = remainder:sub(#exp_match + 1)
    end
    if remainder:match("^[%d%.eE]") then
        return decode_error(position, "invalid number")
    end

    d.position = position + #sign + #mantissa + #exponent
    return tonumber(sign .. mantissa .. exponent)
end

local function decode_value(d, depth)
    if depth > 256 then
        return decode_error(d.position, "nesting too deep")
    end
    skip_whitespace(d)
    local char = d.text:sub(d.position, d.position)
    if char == '"' then
        return decode_string(d)
    elseif char == "[" then
        d.position = d.position + 1
        local result = {}
        skip_whitespace(d)
        if d.text:sub(d.position, d.position) == "]" then
            d.position = d.position + 1
            return result
        end
        while true do
            local value, err = decode_value(d, depth + 1)
            if not value then
                return nil, err
            end
            result[#result + 1] = value
            skip_whitespace(d)
            local separator = d.text:sub(d.position, d.position)
            if separator == "]" then
                d.position = d.position + 1
                return result
            elseif separator ~= "," then
                return decode_error(d.position, "expected ',' or ']'")
            end
            d.position = d.position + 1
        end
    elseif char == "{" then
        d.position = d.position + 1
        local result = {}
        skip_whitespace(d)
        if d.text:sub(d.position, d.position) == "}" then
            d.position = d.position + 1
            return result
        end
        while true do
            skip_whitespace(d)
            if d.text:sub(d.position, d.position) ~= '"' then
                return decode_error(d.position, "expected string key")
            end
            local key, key_err = decode_string(d)
            if not key then
                return nil, key_err
            end
            skip_whitespace(d)
            if d.text:sub(d.position, d.position) ~= ":" then
                return decode_error(d.position, "expected ':'")
            end
            d.position = d.position + 1
            local value, value_err = decode_value(d, depth + 1)
            if not value then
                return nil, value_err
            end
            result[key] = value
            skip_whitespace(d)
            local separator = d.text:sub(d.position, d.position)
            if separator == "}" then
                d.position = d.position + 1
                return result
            elseif separator ~= "," then
                return decode_error(d.position, "expected ',' or '}'")
            end
            d.position = d.position + 1
        end
    elseif char == "t" and d.text:sub(d.position, d.position + 3) == "true" then
        d.position = d.position + 4
        return true
    elseif char == "f" and d.text:sub(d.position, d.position + 4) == "false" then
        d.position = d.position + 5
        return false
    elseif char == "-" or (char >= "0" and char <= "9") then
        return decode_number(d)
    end
    return decode_error(d.position, "unexpected token")
end

function json.decode(text)
    if type(text) ~= "string" then
        return nil, "input must be a string"
    end
    local d = { text = text, position = 1, length = #text }
    local value, err = decode_value(d, 0)
    if not value then
        return nil, err
    end
    skip_whitespace(d)
    if d.position <= d.length then
        return decode_error(d.position, "trailing content")
    end
    return value
end

return json
