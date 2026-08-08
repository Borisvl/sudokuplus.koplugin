local DataStorage = require("datastorage")
local InfoMessage = require("ui/widget/infomessage")
local Notification = require("ui/widget/notification")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local _ = require("gettext")

local difficulties = require("ui.difficulties")
local generator = require("core.generator")
local game = require("game")
local prng = require("core.prng")
local stats = require("stats")
local storage = require("storage")
local util = require("core.util")
local StatsView = require("ui.statsview")
local SudokuView = require("ui.sudokuview")

local Sudoku = WidgetContainer:extend {
    name = "sudoku",
    is_doc_only = false,
}

local SAVE_PATH = DataStorage:getDataDir() .. "/sudoku_save"
local STATS_PATH = DataStorage:getDataDir() .. "/sudoku_stats"
local AUTOFILL_SETTING = "sudoku_autofill_notes"

function Sudoku:init()
    self.ui.menu:registerToMainMenu(self)
end

function Sudoku:loadStats()
    local data, load_err = storage.load(STATS_PATH)
    if not data then
        return stats.new()
    end
    local s, err = stats.from_table(data)
    if not s then
        logger.warn("sudoku: ignoring invalid stats: " .. tostring(err) .. " (" .. tostring(load_err) .. ")")
        return stats.new()
    end
    return s
end

function Sudoku:startGame(difficulty)
    -- core/ is deterministic; seed the PRNG from the wall clock and the
    -- UI timer in the plugin layer. A fresh game abandons any previous
    -- save, but only once a new puzzle exists: a failed generation must
    -- not destroy the saved game.
    difficulty = util.is_difficulty(difficulty) and difficulty or "easy"
    -- Generation (expert especially) can take a few seconds; the emulator
    -- and the device are single-threaded, so explain the wait up front.
    local generating = Notification:new { text = _("Generating…") }
    UIManager:show(generating)
    local rng = prng.new(os.time() + UIManager:getTime())
    local payload, gen_err = generator.generate_game { difficulty = difficulty, rng = rng }
    UIManager:close(generating)
    if not payload then
        UIManager:show(InfoMessage:new {
            text = _("Failed to generate a Sudoku puzzle.") .. "\n" .. tostring(gen_err),
        })
        return
    end
    storage.delete(SAVE_PATH)
    local g, game_err = game.new {
        puzzle = payload.board,
        solution = payload.solution,
        difficulty = payload.difficulty,
        now = os.time,
        autofill_notes = G_reader_settings:isTrue(AUTOFILL_SETTING),
    }
    if not g then
        UIManager:show(InfoMessage:new {
            text = _("Failed to start a game.") .. "\n" .. tostring(game_err),
        })
        return
    end
    UIManager:show(
        SudokuView:new {
            game = g,
            stats = self:loadStats(),
            save_path = SAVE_PATH,
            stats_path = STATS_PATH,
            new_game_cb = function(new_difficulty)
                self:startGame(new_difficulty)
            end,
            show_stats_cb = function()
                self:showStatistics()
            end,
        },
        "full"
    )
end

function Sudoku:continueGame()
    local data, load_err = storage.load(SAVE_PATH)
    if not data then
        UIManager:show(InfoMessage:new {
            text = _("No saved game found.") .. "\n" .. tostring(load_err),
        })
        return
    end
    local g, err = game.restore(data, { now = os.time })
    if not g then
        UIManager:show(InfoMessage:new {
            text = _("Failed to restore the saved game.") .. "\n" .. tostring(err),
        })
        return
    end
    -- The save was written while paused; a resumed game starts its timer.
    g:resume()
    UIManager:show(
        SudokuView:new {
            game = g,
            stats = self:loadStats(),
            save_path = SAVE_PATH,
            stats_path = STATS_PATH,
        },
        "full"
    )
end

function Sudoku:showStatistics()
    local summary = stats.summary(self:loadStats())
    -- "full": the Tools menu stays open underneath (keep_menu_open), so the
    -- new fullscreen page must refresh the whole screen itself.
    UIManager:show(
        StatsView:new {
            summary = summary,
        },
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
    menu_items.sudoku = {
        text = _("Sudoku"),
        sorting_hint = "more_tools",
        sub_item_table = {
            {
                text = _("Continue"),
                enabled_func = function()
                    local file = io.open(SAVE_PATH, "rb")
                    if file then
                        file:close()
                        return true
                    end
                    return false
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
