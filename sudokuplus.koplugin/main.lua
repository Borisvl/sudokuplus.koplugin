local DataStorage = require("datastorage")
local InfoMessage = require("ui/widget/infomessage")
local Notification = require("ui/widget/notification")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local T = require("ffi/util").template
local _ = require("gettext")
local time = require("ui/time")

local difficulties = require("ui.difficulties")
local generator = require("core.generator")
local game = require("game")
local prng = require("core.prng")
local stats = require("stats")
local storage = require("storage")
local util = require("core.util")
local statsview = require("ui.statsview")
local SudokuView = require("ui.sudokuview")

local Sudoku = WidgetContainer:extend {
    name = "sudokuplus",
    is_doc_only = false,
}

local SAVE_PATH = DataStorage:getDataDir() .. "/sudokuplus_save"
local STATS_PATH = DataStorage:getDataDir() .. "/sudokuplus_stats"
local AUTOFILL_SETTING = "sudokuplus_autofill_notes"

-- Puzzle-generation seed from the wall clock at millisecond resolution.
-- os.time() alone has one-second granularity, so back-to-back games would
-- share a puzzle; UIManager:getTime() is an fts-encoded MONOTONIC value, so
-- mixing it into the seed conflates two clocks. time.realtime() is wall-clock
-- fts; its epoch-millisecond value is masked to the PRNG's 32-bit state by
-- prng.new.
local function seed_from_wall_clock()
    return math.floor(time.to_ms(time.realtime()))
end

local function load_plugin_translations(plugin_path)
    local lang = _.current_lang
    if not lang or lang == "C" then
        lang = G_reader_settings and G_reader_settings:readSetting("language")
    end
    if lang and lang ~= "C" and not lang:match("^en") then
        local base_path = plugin_path or "plugins/sudokuplus.koplugin"
        local candidates = { lang, lang:match("^([a-z]+)") }
        for idx = 1, #candidates do
            local l = candidates[idx]
            if l then
                local mo = base_path .. "/l10n/" .. l .. "/sudokuplus.mo"
                if _.loadMO and _.loadMO(mo) then
                    break
                end
            end
        end
    end
end

function Sudoku:init()
    load_plugin_translations(self.path)
    self.ui.menu:registerToMainMenu(self)
end

function Sudoku:loadStats()
    local s, err, backed_up, _, is_missing = storage.load_or_backup(STATS_PATH, stats.from_table)
    if s then
        return s
    end
    if backed_up then
        logger.warn("sudoku: backed up corrupted stats file: " .. tostring(err))
    elseif err and not is_missing then
        logger.warn("sudoku: failed to load stats: " .. tostring(err))
    end
    return stats.new()
end

-- Shows the game view for `g` (used by every entry point so the view wiring
-- never drifts).
function Sudoku:_viewForGame(g, stats_data)
    UIManager:show(
        SudokuView:new {
            game = g,
            stats = stats_data,
            save_path = SAVE_PATH,
            stats_path = STATS_PATH,
            new_game_cb = function(new_difficulty)
                self:startGame(new_difficulty)
            end,
            replay_cb = function(replay_seed, replay_difficulty)
                self:replayGame(replay_seed, replay_difficulty)
            end,
        },
        "full"
    )
end

-- Generates a puzzle (wall-clock or reproduction seed), abandons the
-- currently saved game, and starts a fresh one. Shared by startGame and
-- replayGame so the replace/abandon/bookkeeping flow stays in one place.
function Sudoku:_startWithSeed(difficulty, seed)
    local stats_data = self:loadStats()
    -- Generation (expert especially) can take a few seconds; the emulator
    -- and the device are single-threaded, so explain the wait up front.
    -- forceRePaint() drains the paint/refresh queues immediately: without it
    -- the notification would only be drawn on the next UI tick, which never
    -- comes before the synchronous generation finishes.
    local generating = Notification:new { text = _("Generating…") }
    UIManager:show(generating)
    UIManager:forceRePaint()
    local payload, gen_err = generator.generate_game {
        difficulty = difficulty,
        seed = seed,
        rng = prng.new(seed),
    }
    UIManager:close(generating)
    if not payload then
        UIManager:show(InfoMessage:new {
            text = _("Failed to generate a Sudoku puzzle.") .. "\n" .. tostring(gen_err),
        })
        return
    end
    -- A new puzzle replaces the active save: if the replaced game had been
    -- started (at least one move), close its log entry as abandoned. This
    -- happens only after a puzzle exists, so a failed generation keeps the
    -- old game tracked as in progress.
    local old_save = storage.load(SAVE_PATH)
    if old_save and type(old_save.id) == "number" and type(old_save.started_at) == "number" then
        local ok, abandon_err = stats.abandon(stats_data, old_save.id, os.time())
        if not ok and abandon_err ~= "no tracked game with that id" then
            logger.warn("sudoku: failed to abandon the previous game: " .. tostring(abandon_err))
        end
        if ok then
            local saved, save_err = storage.save(STATS_PATH, stats.to_table(stats_data))
            if not saved then
                logger.warn("sudoku: failed to save stats: " .. tostring(save_err))
            end
        end
    end
    local game_id = stats.reserve_id(stats_data)
    storage.delete(SAVE_PATH)
    local g, game_err = game.new {
        puzzle = payload.board,
        solution = payload.solution,
        difficulty = payload.difficulty,
        seed = payload.seed,
        id = game_id,
        now = os.time,
        autofill_notes = G_reader_settings:isTrue(AUTOFILL_SETTING),
    }
    if not g then
        UIManager:show(InfoMessage:new {
            text = _("Failed to start a game.") .. "\n" .. tostring(game_err),
        })
        return
    end
    self:_viewForGame(g, stats_data)
end

function Sudoku:startGame(difficulty)
    -- core/ is deterministic: seed the PRNG from the wall clock (ms) in the
    -- plugin layer. A fresh game abandons any previous save, but only once a
    -- new puzzle exists: a failed generation must not destroy the saved game.
    difficulty = util.is_difficulty(difficulty) and difficulty or "easy"
    self:_startWithSeed(difficulty, seed_from_wall_clock())
end

-- Restarts an exact puzzle from the game log by its reproduction seed.
function Sudoku:replayGame(seed, difficulty)
    difficulty = util.is_difficulty(difficulty) and difficulty or "easy"
    if type(seed) ~= "number" or seed % 1 ~= 0 then
        UIManager:show(InfoMessage:new {
            text = _("This game cannot be replayed (no reproduction seed)."),
        })
        return
    end
    self:_startWithSeed(difficulty, seed)
end

function Sudoku:continueGame()
    -- Any restore failure (JSON parse error, schema validation failure, unsupported
    -- future version, or 7-day timer-drift guard) backs up and removes the save to prevent
    -- a permanent dead end on "Continue", while preserving the data in <path>.<ts>.bak.
    local g, err, backed_up, bak_path = storage.load_or_backup(SAVE_PATH, function(data)
        return game.restore(data, { now = os.time })
    end)
    if not g then
        if backed_up then
            local reason = err and ("\n" .. tostring(err)) or ""
            UIManager:show(InfoMessage:new {
                text = T(_("The save was corrupted; a backup was kept at %1"), tostring(bak_path)) .. reason,
            })
        elseif storage.exists(SAVE_PATH) then
            UIManager:show(InfoMessage:new {
                text = _("Failed to restore the saved game.") .. "\n" .. tostring(err),
            })
        else
            UIManager:show(InfoMessage:new {
                text = _("No saved game found.") .. "\n" .. tostring(err),
            })
        end
        return
    end
    -- A save written before the game-log identity existed gets a fresh id.
    local stats_data = self:loadStats()
    if g.id == nil then
        g.id = stats.reserve_id(stats_data)
    end
    -- The save was written while paused; a resumed game starts its timer.
    g:resume()
    self:_viewForGame(g, stats_data)
end

function Sudoku:showStatistics()
    local s = self:loadStats()
    -- "full": the Tools menu stays open underneath (keep_menu_open), so the
    -- new fullscreen page must refresh the whole screen itself.
    UIManager:show(
        statsview.dashboard(s, {
            replay_cb = function(seed, difficulty)
                self:replayGame(seed, difficulty)
            end,
        }),
        "full"
    )
end

function Sudoku:addToMainMenu(menu_items)
    local new_game_items = {}
    for _, entry in ipairs(difficulties.list()) do
        new_game_items[#new_game_items + 1] = {
            text = entry.label,
            callback = function()
                self:startGame(entry.id)
            end,
        }
    end
    menu_items.sudokuplus = {
        text = _("Sudoku+"),
        sorting_hint = "more_tools",
        sub_item_table = {
            {
                text = _("Continue"),
                enabled_func = function()
                    return storage.exists(SAVE_PATH)
                end,
                callback = function()
                    self:continueGame()
                end,
            },
            {
                text = _("New game"),
                sub_item_table = new_game_items,
            },
            {
                text = _("Statistics"),
                keep_menu_open = true,
                callback = function()
                    self:showStatistics()
                end,
            },
            {
                text = _("Auto-fill notes"),
                checked_func = function()
                    return G_reader_settings:isTrue(AUTOFILL_SETTING)
                end,
                callback = function()
                    G_reader_settings:flipNilOrFalse(AUTOFILL_SETTING)
                end,
            },
        },
    }
end

return Sudoku
