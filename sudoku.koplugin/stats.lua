local hints = require("core.hints")
local util = require("core.util")

local stats = {}

local VERSION = 1
local MAX_FINISHED = 200
local MAX_GIVEN_UP = 200

local TECHNIQUES = {}
for _, technique in ipairs(hints.techniques() or {}) do
    TECHNIQUES[technique.id] = true
end

local function validate_record(record)
    if type(record) ~= "table" then
        return nil, "record must be a table"
    end
    if record.kind ~= "finished" and record.kind ~= "give_up" then
        return nil, "record kind must be 'finished' or 'give_up'"
    end
    if type(record.difficulty) ~= "string" or not util.is_difficulty(record.difficulty) then
        return nil, "record difficulty must be one of easy, medium, hard, expert"
    end
    if type(record.duration) ~= "number" or not util.is_finite(record.duration) or record.duration < 0 then
        return nil, "record duration must be a non-negative number"
    end
    if type(record.hints) ~= "table" then
        return nil, "record hints must be a list of technique ids"
    end
    local technique_list = {}
    for i, technique in ipairs(record.hints) do
        if type(technique) ~= "string" or not TECHNIQUES[technique] then
            return nil, "record hints must list known technique ids"
        end
        technique_list[i] = technique
    end
    if type(record.mistakes) ~= "number" or record.mistakes % 1 ~= 0 or record.mistakes < 0 then
        return nil, "record mistakes must be a non-negative integer"
    end
    if type(record.check_errors) ~= "number" or record.check_errors % 1 ~= 0 or record.check_errors < 0 then
        return nil, "record check_errors must be a non-negative integer"
    end
    if type(record.timestamp) ~= "number" or not util.is_finite(record.timestamp) then
        return nil, "record timestamp must be a number"
    end
    return {
        kind = record.kind,
        difficulty = record.difficulty,
        duration = record.duration,
        hints = technique_list,
        mistakes = record.mistakes,
        check_errors = record.check_errors,
        timestamp = record.timestamp,
    }
end

function stats.new()
    return {
        version = VERSION,
        streak = 0,
        finished = {},
        given_up = {},
    }
end

local function append_capped(list, record, cap)
    list[#list + 1] = record
    if #list > cap then
        table.remove(list, 1)
    end
end

function stats.add(s, record)
    if type(s) ~= "table" or s.version ~= VERSION then
        return nil, "stats must be a stats table"
    end
    local normalized, err = validate_record(record)
    if not normalized then
        return nil, err
    end

    if normalized.kind == "finished" then
        append_capped(s.finished, normalized, MAX_FINISHED)
        if #normalized.hints == 0 then
            s.streak = s.streak + 1
        else
            s.streak = 0
        end
    else
        append_capped(s.given_up, normalized, MAX_GIVEN_UP)
        s.streak = 0
    end
    return s
end

function stats.summary(s)
    local per_difficulty = {}
    local hints_per_technique = {}
    for _, record in ipairs(s.finished) do
        local bucket = per_difficulty[record.difficulty]
        if not bucket then
            bucket = { count = 0, sum = 0, best_duration = math.huge }
            per_difficulty[record.difficulty] = bucket
        end
        bucket.count = bucket.count + 1
        bucket.sum = bucket.sum + record.duration
        if record.duration < bucket.best_duration then
            bucket.best_duration = record.duration
        end
        for _, technique in ipairs(record.hints) do
            hints_per_technique[technique] = (hints_per_technique[technique] or 0) + 1
        end
    end
    for _, record in ipairs(s.given_up) do
        for _, technique in ipairs(record.hints) do
            hints_per_technique[technique] = (hints_per_technique[technique] or 0) + 1
        end
    end

    local normalized_per_difficulty = {}
    for difficulty, bucket in pairs(per_difficulty) do
        normalized_per_difficulty[difficulty] = {
            count = bucket.count,
            avg_duration = bucket.sum / bucket.count,
            best_duration = bucket.best_duration,
        }
    end

    local most_missed
    local sorted_techniques = {}
    for technique in pairs(hints_per_technique) do
        sorted_techniques[#sorted_techniques + 1] = technique
    end
    table.sort(sorted_techniques)
    for _, technique in ipairs(sorted_techniques) do
        local count = hints_per_technique[technique]
        if not most_missed or count > most_missed.count then
            most_missed = { technique = technique, count = count }
        end
    end

    return {
        games_played = #s.finished + #s.given_up,
        finished_count = #s.finished,
        given_up_count = #s.given_up,
        streak = s.streak,
        per_difficulty = normalized_per_difficulty,
        hints_per_technique = hints_per_technique,
        most_missed = most_missed,
    }
end

function stats.to_table(s)
    return s
end

function stats.from_table(t)
    if type(t) ~= "table" then
        return nil, "stats data must be a table"
    end
    if t.version ~= VERSION then
        return nil, "unsupported stats version: " .. tostring(t.version)
    end
    if type(t.streak) ~= "number" or not util.is_finite(t.streak) or t.streak % 1 ~= 0 or t.streak < 0 then
        return nil, "invalid streak"
    end
    if type(t.finished) ~= "table" or type(t.given_up) ~= "table" then
        return nil, "record lists must be tables"
    end

    local result = {
        version = VERSION,
        streak = t.streak,
        finished = {},
        given_up = {},
    }
    for _, list in ipairs({
        { t.finished, result.finished, MAX_FINISHED },
        { t.given_up, result.given_up, MAX_GIVEN_UP },
    }) do
        for _, record in ipairs(list[1]) do
            local normalized, err = validate_record(record)
            if not normalized then
                return nil, err
            end
            append_capped(list[2], normalized, list[3])
        end
    end
    return result
end

return stats
