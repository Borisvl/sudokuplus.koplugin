local DataStorage = require("datastorage")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local _ = require("gettext")

local generator = require("core.generator")
local game = require("game")
local prng = require("core.prng")
local stats = require("stats")
local storage = require("storage")
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

function Sudoku:startGame()
    -- core/ is deterministic; seed the PRNG from the wall clock and the
    -- UI timer in the plugin layer. A fresh game abandons any previous save.
    storage.delete(SAVE_PATH)
    local rng = prng.new(os.time() + UIManager:getTime())
    local payload, gen_err = generator.generate_game { difficulty = "easy", rng = rng }
    if not payload then
        UIManager:show(InfoMessage:new {
            text = _("Failed to generate a Sudoku puzzle.") .. "\n" .. tostring(gen_err),
        })
        return
    end
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
    UIManager:show(SudokuView:new {
        game = g,
        stats = self:loadStats(),
        save_path = SAVE_PATH,
        stats_path = STATS_PATH,
    })
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
    UIManager:show(SudokuView:new {
        game = g,
        stats = self:loadStats(),
        save_path = SAVE_PATH,
        stats_path = STATS_PATH,
    })
end

function Sudoku:addToMainMenu(menu_items)
    menu_items.sudoku = {
        text = _("Sudoku"),
        sorting_hint = "more_tools",
        sub_item_table = {
            {
                text = _("Resume game"),
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
                callback = function()
                    self:startGame()
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
