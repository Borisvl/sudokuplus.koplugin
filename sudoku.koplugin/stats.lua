local board = require("core.board")
local hints = require("core.hints")
local util = require("core.util")

local stats = {}

local VERSION = 2
local MAX_GAMES = 200

local STATUSES = {
    in_progress = true,
    finished = true,
    give_up = true,
    abandoned = true,
}

local TECHNIQUES = {}
for _, technique in ipairs(hints.techniques() or {}) do
    TECHNIQUES[technique.id] = true
end

local function is_optional_integer(value)
    return value == nil or (type(value) == "number" and value % 1 == 0 and value >= 0)
end

local function is_optional_finite(value)
    return value == nil or (type(value) == "number" and util.is_finite(value))
end

local function validate_board_string(value, name)
    if value == nil then
        return nil, nil
    end
    if type(value) ~= "string" or #value ~= 81 then
        return nil, name .. " must be an 81-character board string"
    end
    if not board.from_string(value) then
        return nil, name .. " must be a valid board string"
    end
    return value
end

local function validate_record(record)
    if type(record) ~= "table" then
        return nil, "record must be a table"
    end
    if not STATUSES[record.status] then
        return nil, "record status must be one of in_progress, finished, give_up, abandoned"
    end
    if not is_optional_integer(record.id) then
        return nil, "record id must be a non-negative integer"
    end
    if not is_optional_integer(record.seed) then
        return nil, "record seed must be a non-negative integer"
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
    if not is_optional_integer(record.mistakes) then
        return nil, "record mistakes must be a non-negative integer"
    end
    if not is_optional_integer(record.check_errors) then
        return nil, "record check_errors must be a non-negative integer"
    end
    if not is_optional_finite(record.started_at) then
        return nil, "record started_at must be a number"
    end
    if not is_optional_finite(record.ended_at) then
        return nil, "record ended_at must be a number"
    end
    if not is_optional_integer(record.moves) then
        return nil, "record moves must be a non-negative integer"
    end
    if not is_optional_integer(record.filled) then
        return nil, "record filled must be a non-negative integer"
    end
    if not is_optional_integer(record.correct) then
        return nil, "record correct must be a non-negative integer"
    end
    local puzzle, puzzle_err = validate_board_string(record.puzzle, "record puzzle")
    if puzzle_err then
        return nil, puzzle_err
    end
    local solution, solution_err = validate_board_string(record.solution, "record solution")
    if solution_err then
        return nil, solution_err
    end
    local board_string, board_err = validate_board_string(record.board, "record board")
    if board_err then
        return nil, board_err
    end
    return {
        status = record.status,
        id = record.id,
        seed = record.seed,
        difficulty = record.difficulty,
        duration = record.duration,
        hints = technique_list,
        mistakes = record.mistakes,
        check_errors = record.check_errors,
        started_at = record.started_at,
        ended_at = record.ended_at,
        moves = record.moves,
        filled = record.filled,
        correct = record.correct,
        puzzle = puzzle,
        solution = solution,
        board = board_string,
    }
end

function stats.new()
    return {
        version = VERSION,
        streak = 0,
        best_streak = 0,
        next_id = 1,
        games = {},
    }
end

-- Hands out the next unique game-log id (the seed cannot be the identity:
-- a replay reuses the seed, so two logged games could share it).
function stats.reserve_id(s)
    if type(s) ~= "table" or s.version ~= VERSION then
        return nil, "stats must be a stats table"
    end
    local id = s.next_id
    s.next_id = id + 1
    return id
end

local function find_entry(s, id)
    for _, entry in ipairs(s.games) do
        if entry.id == id then
            return entry
        end
    end
    return nil
end

-- Appends an entry, dropping the oldest non-live entry once the cap is
-- exceeded. In-progress (live) entries are never evicted.
local function append_capped(s, entry)
    s.games[#s.games + 1] = entry
    if #s.games <= MAX_GAMES then
        return
    end
    for i, existing in ipairs(s.games) do
        if existing.status ~= "in_progress" then
            table.remove(s.games, i)
            return
        end
    end
    table.remove(s.games, 1)
end

-- Refreshes the volatile fields of an existing log entry from a record.
local function merge_entry(entry, record)
    entry.difficulty = record.difficulty
    entry.duration = record.duration
    entry.hints = record.hints
    entry.mistakes = record.mistakes
    entry.check_errors = record.check_errors
    entry.moves = record.moves
    entry.filled = record.filled
    entry.correct = record.correct
    entry.board = record.board
    entry.seed = record.seed
    entry.started_at = entry.started_at or record.started_at
end

-- Creates or updates the live in-progress entry for a game (called when the
-- first move is made and at every save point).
function stats.track(s, record)
    if type(s) ~= "table" or s.version ~= VERSION then
        return nil, "stats must be a stats table"
    end
    local normalized, err = validate_record(record)
    if not normalized then
        return nil, err
    end
    if not normalized.id then
        return nil, "tracked game needs an id"
    end
    if normalized.status ~= "in_progress" then
        return nil, "track requires an in_progress record"
    end
    local entry = find_entry(s, normalized.id)
    if entry then
        if entry.status ~= "in_progress" then
            return nil, "game is already finished"
        end
        merge_entry(entry, normalized)
    else
        normalized.status = "in_progress"
        append_capped(s, normalized)
    end
    return s
end

local function finalize(s, normalized)
    local entry = normalized.id and find_entry(s, normalized.id)
    if entry then
        merge_entry(entry, normalized)
        entry.status = normalized.status
        entry.ended_at = normalized.ended_at
        entry.started_at = entry.started_at or normalized.started_at
    elseif normalized.started_at then
        append_capped(s, normalized)
    else
        return false
    end
    -- Streak: a hint-free win extends it; hint-used wins, give-ups and
    -- abandons reset it.
    if normalized.status == "finished" and #normalized.hints == 0 then
        s.streak = s.streak + 1
        if s.streak > s.best_streak then
            s.best_streak = s.streak
        end
    else
        s.streak = 0
    end
    return true
end

-- Finalizes a game as finished or given-up (matches the live entry by id, or
-- appends a terminal entry when the game was never tracked — e.g. data
-- migrated from v1).
function stats.add(s, record)
    if type(s) ~= "table" or s.version ~= VERSION then
        return nil, "stats must be a stats table"
    end
    local normalized, err = validate_record(record)
    if not normalized then
        return nil, err
    end
    if normalized.status ~= "finished" and normalized.status ~= "give_up" then
        return nil, "add requires a finished or give_up record"
    end
    finalize(s, normalized)
    return s
end

-- Marks a started game abandoned (replaced by a new game without finishing).
-- The live entry's status flips to abandoned with `ended_at`; the final
-- snapshot was already captured by the last track at the previous save point.
function stats.abandon(s, id, ended_at)
    if type(s) ~= "table" or s.version ~= VERSION then
        return nil, "stats must be a stats table"
    end
    local entry = id and find_entry(s, id)
    if not entry then
        return nil, "no tracked game with that id"
    end
    if entry.status ~= "in_progress" then
        return nil, "game is already finished"
    end
    entry.status = "abandoned"
    entry.ended_at = ended_at
    s.streak = 0
    return s
end

function stats.list(s)
    if type(s) ~= "table" or s.version ~= VERSION then
        return nil, "stats must be a stats table"
    end
    -- Newest first: entries are appended oldest first, so a reverse copy
    -- preserves the recorded order while presenting the newest game on top.
    local result = {}
    for i = 1, #s.games do
        result[i] = s.games[#s.games - i + 1]
    end
    return result
end

function stats.summary(s)
    if type(s) ~= "table" or s.version ~= VERSION then
        return nil, "stats must be a stats table"
    end

    local games_started = #s.games
    local finished_count = 0
    local given_up_count = 0
    local abandoned_count = 0
    local in_progress_count = 0
    local total_playtime = 0
    local moves_sum = 0
    local finished_sum = 0
    local finished_best = math.huge
    local finished_with_time = 0
    local mistakes_sum = 0
    local check_errors_sum = 0
    local per_difficulty = {}
    local hints_per_technique = {}

    for _, entry in ipairs(s.games) do
        total_playtime = total_playtime + (entry.duration or 0)
        moves_sum = moves_sum + (entry.moves or 0)
        for _, technique in ipairs(entry.hints) do
            hints_per_technique[technique] = (hints_per_technique[technique] or 0) + 1
        end

        if entry.status == "finished" then
            finished_count = finished_count + 1
            finished_sum = finished_sum + entry.duration
            if entry.duration < finished_best then
                finished_best = entry.duration
            end
            finished_with_time = finished_with_time + 1
            mistakes_sum = mistakes_sum + (entry.mistakes or 0)
            check_errors_sum = check_errors_sum + (entry.check_errors or 0)
        elseif entry.status == "give_up" then
            given_up_count = given_up_count + 1
            mistakes_sum = mistakes_sum + (entry.mistakes or 0)
            check_errors_sum = check_errors_sum + (entry.check_errors or 0)
        elseif entry.status == "abandoned" then
            abandoned_count = abandoned_count + 1
        else
            in_progress_count = in_progress_count + 1
        end

        local bucket = per_difficulty[entry.difficulty]
        if not bucket then
            bucket = { finished = 0, given_up = 0, sum = 0, best = math.huge, mistakes_sum = 0 }
            per_difficulty[entry.difficulty] = bucket
        end
        if entry.status == "finished" then
            bucket.finished = bucket.finished + 1
            bucket.sum = bucket.sum + entry.duration
            if entry.duration < bucket.best then
                bucket.best = entry.duration
            end
            bucket.mistakes_sum = bucket.mistakes_sum + (entry.mistakes or 0)
        elseif entry.status == "give_up" then
            bucket.given_up = bucket.given_up + 1
        end
    end

    local normalized_per_difficulty = {}
    for difficulty, bucket in pairs(per_difficulty) do
        normalized_per_difficulty[difficulty] = {
            count = bucket.finished,
            given_up_count = bucket.given_up,
            avg_duration = bucket.finished > 0 and bucket.sum / bucket.finished or nil,
            best_duration = bucket.finished > 0 and bucket.best or nil,
            avg_mistakes = bucket.finished > 0 and bucket.mistakes_sum / bucket.finished or nil,
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

    local completed = finished_count + given_up_count

    return {
        games_started = games_started,
        games_played = games_started,
        finished_count = finished_count,
        given_up_count = given_up_count,
        abandoned_count = abandoned_count,
        in_progress_count = in_progress_count,
        completion_rate = games_started > 0 and finished_count / games_started or 0,
        win_rate = (finished_count + given_up_count) > 0 and finished_count / (finished_count + given_up_count) or 0,
        total_playtime = total_playtime,
        completed = completed,
        avg_duration = finished_with_time > 0 and finished_sum / finished_with_time or nil,
        best_duration = finished_with_time > 0 and finished_best or nil,
        avg_mistakes = completed > 0 and mistakes_sum / completed or nil,
        total_mistakes = mistakes_sum,
        total_check_errors = check_errors_sum,
        avg_moves = games_started > 0 and moves_sum / games_started or nil,
        streak = s.streak,
        best_streak = s.best_streak,
        per_difficulty = normalized_per_difficulty,
        hints_per_technique = hints_per_technique,
        most_missed = most_missed,
    }
end

function stats.to_table(s)
    return s
end

-- Recomputes streak and best_streak from the log order (oldest first): the
-- data may have been trimmed or hand-edited, and v1 stored only the streak.
local function recompute_streaks(result)
    local streak = 0
    for _, entry in ipairs(result.games) do
        if entry.status == "finished" then
            if #entry.hints == 0 then
                streak = streak + 1
                if streak > result.best_streak then
                    result.best_streak = streak
                end
            else
                streak = 0
            end
        else
            streak = 0
        end
    end
    result.streak = streak
    return result
end

local function migrate_from_v1(t)
    local result = {
        version = VERSION,
        streak = 0,
        best_streak = 0,
        next_id = 1,
        games = {},
    }
    for _, mapping in ipairs({ { "finished", "finished" }, { "given_up", "give_up" } }) do
        local list = t[mapping[1]]
        if type(list) ~= "table" then
            return nil, "record lists must be tables"
        end
        for _, rec in ipairs(list) do
            local normalized, err = validate_record({
                status = mapping[2],
                difficulty = rec.difficulty,
                duration = rec.duration,
                hints = rec.hints,
                mistakes = rec.mistakes,
                check_errors = rec.check_errors,
                -- v1 recorded only the end timestamp; reuse it for both.
                started_at = rec.timestamp,
                ended_at = rec.timestamp,
            })
            if not normalized then
                return nil, err
            end
            result.games[#result.games + 1] = normalized
        end
    end
    if #result.games > MAX_GAMES then
        local trimmed = {}
        for i = #result.games - MAX_GAMES + 1, #result.games do
            trimmed[#trimmed + 1] = result.games[i]
        end
        result.games = trimmed
    end
    return recompute_streaks(result)
end

function stats.from_table(t)
    if type(t) ~= "table" then
        return nil, "stats data must be a table"
    end
    if t.version == 1 then
        return migrate_from_v1(t)
    end
    if t.version ~= VERSION then
        return nil, "unsupported stats version: " .. tostring(t.version)
    end
    if type(t.streak) ~= "number" or not util.is_finite(t.streak) or t.streak % 1 ~= 0 or t.streak < 0 then
        return nil, "invalid streak"
    end
    if
        type(t.best_streak) ~= "number"
        or not util.is_finite(t.best_streak)
        or t.best_streak % 1 ~= 0
        or t.best_streak < t.streak
    then
        return nil, "invalid best_streak"
    end
    if type(t.next_id) ~= "number" or not util.is_finite(t.next_id) or t.next_id % 1 ~= 0 or t.next_id < 1 then
        return nil, "invalid next_id"
    end
    if type(t.games) ~= "table" then
        return nil, "games must be a table"
    end
    local result = {
        version = VERSION,
        streak = t.streak,
        best_streak = t.best_streak,
        next_id = t.next_id,
        games = {},
    }
    for _, entry in ipairs(t.games) do
        local normalized, err = validate_record(entry)
        if not normalized then
            return nil, err
        end
        append_capped(result, normalized)
    end
    return result
end

return stats
