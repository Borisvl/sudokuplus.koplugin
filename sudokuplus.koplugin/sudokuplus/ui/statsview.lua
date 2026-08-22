local Device = require("device")
local Menu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")
local T = require("ffi/util").template
local _ = require("gettext")

local difficulties = require("sudokuplus.ui.difficulties")
local stats = require("sudokuplus.stats")
local techniques = require("sudokuplus.ui.techniques")
local util = require("sudokuplus.core.util")
local GameDetail = require("sudokuplus.ui.gamedetail")

local Screen = Device.screen

local statsview = {}

local format_time = util.format_time

local function percent(fraction)
    return string.format("%d%%", math.floor((fraction or 0) * 100 + 0.5))
end

local status_helper = require("sudokuplus.ui.status")

local function game_row_text(entry)
    local difficulty = difficulties.format_display(entry.difficulty, entry.custom_tier) or entry.difficulty
    return T(
        _("#%1 · %2 · %3 · %4"),
        tostring(entry.id or "?"),
        difficulty,
        status_helper.label(entry.status),
        format_time(entry.duration or 0)
    )
end

-- Ranked technique rows for the "Most missed strategies" section.
local function technique_rows(summary)
    local rows = {}
    local techniques_list = {}
    for id, count in pairs(summary.hints_per_technique or {}) do
        techniques_list[#techniques_list + 1] = { id = id, count = count }
    end
    table.sort(techniques_list, function(a, b)
        return a.count > b.count or (a.count == b.count and a.id < b.id)
    end)
    for i, item in ipairs(techniques_list) do
        rows[#rows + 1] = { text = T(_("%1: %2"), techniques.label(item.id), tostring(item.count)) }
    end
    return rows
end

-- Per-difficulty rows for the "By difficulty" section.
local function difficulty_rows(summary)
    local rows = {}
    for diff_idx, id in ipairs(difficulties.ALL_DIFFICULTIES) do
        local bucket = summary.per_difficulty[id]
        if bucket and bucket.count > 0 then
            rows[#rows + 1] = {
                text = T(
                    _("%1 — %2 finished, avg %3, best %4, given up %5"),
                    difficulties.label(id) or id,
                    tostring(bucket.count),
                    format_time(bucket.avg_duration),
                    format_time(bucket.best_duration),
                    tostring(bucket.given_up_count)
                ),
            }
        end
    end
    return rows
end

-- Closes every stats widget stacked on top of the dashboard (detail, games
-- list, dashboard) before a replay starts, so the new game view opens on a
-- clean stack instead of leaving stale stats underneath.
local function close_session(widgets)
    for i = #widgets, 1, -1 do
        UIManager:close(widgets[i], "flashui")
    end
end

-- The fullscreen games list: one row per logged game, newest first, tapping
-- a row opens its detail page. `opts.widgets` (when present) collects every
-- widget opened on top of the dashboard so a replay can close them all.
function statsview.games_list(s, opts)
    opts = opts or {}
    opts.widgets = opts.widgets or {}
    local games = stats.list(s)
    local items = {}
    for i, entry in ipairs(games) do
        items[#items + 1] = {
            text = game_row_text(entry),
            callback = function()
                local detail = GameDetail:new {
                    entries = games,
                    index = i,
                    entry = entry,
                    replay_cb = function(descriptor)
                        close_session(opts.widgets)
                        if opts.replay_cb then
                            opts.replay_cb(descriptor)
                        end
                    end,
                }
                opts.widgets[#opts.widgets + 1] = detail
                UIManager:show(detail, "full")
            end,
        }
    end
    local menu = Menu:new {
        title = _("Game history"),
        item_table = items,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        items_per_page = 12,
    }
    opts.widgets[#opts.widgets + 1] = menu
    return menu
end

-- The fullscreen insight dashboard: totals, completion/win rates, playtime,
-- streak, mistakes, expandable per-difficulty and technique sections, and the
-- entry point to the game history.
function statsview.dashboard(s, opts)
    opts = opts or {}
    local summary = stats.summary(s)
    local items = {}

    local function add(text)
        items[#items + 1] = { text = text }
    end

    add(
        T(
            _("Started: %1   Finished: %2   Given up: %3"),
            tostring(summary.games_started),
            tostring(summary.finished_count),
            tostring(summary.given_up_count)
        )
    )
    add(T(_("Abandoned: %1   In progress: %2"), tostring(summary.abandoned_count), tostring(summary.in_progress_count)))
    add(T(_("Completion rate: %1   Win rate: %2"), percent(summary.completion_rate), percent(summary.win_rate)))
    add(T(_("Total playtime: %1"), format_time(summary.total_playtime)))
    if summary.best_duration then
        add(T(_("Best time: %1   Average: %2"), format_time(summary.best_duration), format_time(summary.avg_duration)))
    end
    add(T(_("Current streak: %1   Best streak: %2"), tostring(summary.streak), tostring(summary.best_streak)))
    add(
        T(
            _("Total mistakes: %1 (avg %2 per game)   Check errors: %3"),
            tostring(summary.total_mistakes),
            summary.avg_mistakes and string.format("%.1f", summary.avg_mistakes) or "0",
            tostring(summary.total_check_errors)
        )
    )
    add(T(_("Average moves per game: %1"), summary.avg_moves and string.format("%.1f", summary.avg_moves) or "0"))

    items[#items + 1] = {
        text = _("By difficulty"),
        sub_item_table = difficulty_rows(summary),
    }
    items[#items + 1] = {
        text = _("Most missed strategies"),
        sub_item_table = technique_rows(summary),
    }
    items[#items + 1] = {
        text = T(_("Game history (%1)"), tostring(summary.games_started)),
        callback = function()
            UIManager:show(statsview.games_list(s, opts))
        end,
    }

    local menu = Menu:new {
        title = _("Sudoku statistics"),
        item_table = items,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
    }
    -- The dashboard is the root of the stats session: collect it with the
    -- widgets opened on top of it so a replay can close the whole stack.
    opts.widgets = opts.widgets or {}
    opts.widgets[#opts.widgets + 1] = menu
    return menu
end

return statsview
