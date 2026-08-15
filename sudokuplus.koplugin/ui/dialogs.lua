local ButtonDialog = require("ui/widget/buttondialog")
local ConfirmBox = require("ui/widget/confirmbox")
local Notification = require("ui/widget/notification")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local T = require("ffi/util").template
local _ = require("gettext")

local difficulties = require("ui.difficulties")
local help = require("ui.help")
local messages = require("ui.messages")
local stats = require("stats")
local util = require("core.util")

local format_time = util.format_time

local dialogs = {}

function dialogs.close_menu_and_resume(view, dialog, fn)
    if dialog then
        UIManager:close(dialog)
    end
    if fn then
        local ok, err = pcall(fn)
        if not ok then
            logger.warn("sudoku: menu action failed: " .. tostring(err))
        end
    end
    if view.menu_open then
        view.menu_open = false
        if not view.game:is_finished() then
            view.game:resume()
        end
        view:refreshCoarse()
    end
end

function dialogs.show_win_dialog(view)
    if view._win_dialog then
        UIManager:close(view._win_dialog)
        view._win_dialog = nil
    end
    local record = view.game:final_record()
    if not record then
        logger.warn("sudoku: attempted to show win dialog without a finished record")
        record = {
            duration = view.game:elapsed(),
            mistakes = view.game:mistakes(),
            hints = view.game:hints(),
        }
    end
    local dialog
    local function close_all()
        view._win_dialog = nil
        UIManager:close(dialog)
        UIManager:close(view, "flashui")
    end
    dialog = ButtonDialog:new {
        title = T(
            _("Puzzle solved!\n\nTime: %1\nMistakes: %2\nHints: %3"),
            format_time(record.duration or 0),
            tostring(record.mistakes or 0),
            tostring(#(record.hints or {}))
        ),
        buttons = {
            {
                {
                    text = _("New game"),
                    callback = function()
                        view._win_dialog = nil
                        UIManager:close(dialog)
                        dialogs.open_difficulty_picker(view, function()
                            dialogs.show_win_dialog(view)
                        end)
                    end,
                },
                {
                    text = _("Statistics"),
                    callback = function()
                        view:showStats(function()
                            if view._win_dialog == dialog then
                                view._win_dialog = nil
                                UIManager:close(dialog)
                            end
                        end)
                    end,
                },
            },
            {
                {
                    text = _("Close"),
                    callback = close_all,
                },
            },
        },
        tap_close_callback = close_all,
    }
    view._win_dialog = dialog
    UIManager:show(dialog)
end

function dialogs.open_difficulty_picker(view, cancel_cb)
    local diff_dialog
    local buttons = {}
    local current_row = {}
    for _, entry in ipairs(difficulties.list()) do
        current_row[#current_row + 1] = {
            text = entry.label,
            callback = function()
                view.menu_open = false
                UIManager:close(diff_dialog)
                UIManager:close(view, "flashui")
                if view.new_game_cb then
                    view.new_game_cb(entry.id)
                end
            end,
        }
        if #current_row == 2 then
            buttons[#buttons + 1] = current_row
            current_row = {}
        end
    end
    if #current_row > 0 then
        buttons[#buttons + 1] = current_row
    end
    buttons[#buttons + 1] = {
        {
            text = _("Cancel"),
            callback = function()
                UIManager:close(diff_dialog)
                if cancel_cb then
                    cancel_cb()
                end
            end,
        },
    }
    diff_dialog = ButtonDialog:new {
        title = _("New game — Choose difficulty"),
        buttons = buttons,
        tap_close_callback = function()
            if cancel_cb then
                cancel_cb()
            end
        end,
    }
    UIManager:show(diff_dialog)
end

function dialogs.confirm_reset(view, cancel_cb)
    local confirm_dialog
    confirm_dialog = ConfirmBox:new {
        text = _("Reset this puzzle from the beginning? All progress will be lost."),
        ok_text = _("Reset"),
        ok_callback = function()
            if view.stats and view.game.id then
                stats.drop_in_progress(view.stats, view.game.id)
                view:persistStats()
            end
            local ok, err = view.game:reset()
            if not ok then
                logger.warn("sudoku: reset failed: " .. tostring(err))
            end
            if view.stats then
                view.game.id = stats.reserve_id(view.stats)
            end
            view.selected = nil
            view.armed = nil
            view.notes_mode = false
            view._log_started = false
            view._hint_result = nil
            view._hint_stage = 0
            view._hint_cells = {}
            view._match_value = nil
            view._match_cells = {}
            view._completed_digits = view.game:completed_digits()
            view:deleteSave()
            view:markToolRowIfChanged()
            view:markNumberRow()
            if cancel_cb then
                cancel_cb()
            end
        end,
        cancel_text = _("Cancel"),
        cancel_callback = function()
            if cancel_cb then
                cancel_cb()
            end
        end,
    }
    UIManager:show(confirm_dialog)
end

function dialogs.confirm_give_up(view, cancel_cb)
    local confirm_dialog
    confirm_dialog = ConfirmBox:new {
        text = _("Are you sure you want to give up?"),
        ok_text = _("Give up"),
        ok_callback = function()
            view.menu_open = false
            view:onGiveUp()
        end,
        cancel_text = _("Cancel"),
        cancel_callback = function()
            if cancel_cb then
                cancel_cb()
            end
        end,
    }
    UIManager:show(confirm_dialog)
end

function dialogs.open_menu(view)
    if view.game:is_finished() then
        dialogs.show_win_dialog(view)
        return
    end
    view.game:pause()
    view.menu_open = true
    -- A key press right before the menu opened may have armed the notes
    -- hold; invalidate it so the toggle cannot fire behind the dialog.
    view:_invalidateNotesHold()
    local dialog
    dialog = ButtonDialog:new {
        title = T(
            _("%1 — Time: %2    Mistakes: %3    Hints: %4"),
            difficulties.label(view.game:difficulty()) or view.game:difficulty(),
            format_time(view.game:elapsed()),
            tostring(view.game:mistakes()),
            tostring(#view.game:hints())
        ),
        buttons = {
            {
                {
                    text = _("Resume"),
                    callback = function()
                        dialogs.close_menu_and_resume(view, dialog)
                    end,
                },
                {
                    text = _("Statistics"),
                    callback = function()
                        view:showStats(function()
                            UIManager:close(dialog)
                        end)
                    end,
                },
            },
            {
                {
                    text = _("New game"),
                    callback = function()
                        UIManager:close(dialog)
                        dialogs.open_difficulty_picker(view, function()
                            dialogs.close_menu_and_resume(view)
                        end)
                    end,
                },
                {
                    text = _("Reset puzzle"),
                    callback = function()
                        UIManager:close(dialog)
                        dialogs.confirm_reset(view, function()
                            dialogs.close_menu_and_resume(view)
                        end)
                    end,
                },
            },
            {
                {
                    text = _("Fill all notes"),
                    callback = function()
                        dialogs.close_menu_and_resume(view, dialog, function()
                            local ok, err = view.game:fill_all_notes()
                            if not ok then
                                UIManager:show(Notification:new { text = messages.translate(err) })
                            else
                                view:_refreshMatchAfterMove()
                                view:markToolRowIfChanged()
                            end
                        end)
                    end,
                },
                {
                    text = _("Help"),
                    callback = function()
                        help.show_menu()
                    end,
                },
            },
            {
                {
                    text = _("Give up"),
                    callback = function()
                        UIManager:close(dialog)
                        dialogs.confirm_give_up(view, function()
                            dialogs.close_menu_and_resume(view)
                        end)
                    end,
                },
                {
                    text = _("Quit"),
                    callback = function()
                        view.menu_open = false
                        UIManager:close(dialog)
                        view:onQuit()
                    end,
                },
            },
        },
        tap_close_callback = function()
            dialogs.close_menu_and_resume(view)
        end,
    }
    UIManager:show(dialog)
end

return dialogs
