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
local techniques = require("ui.techniques")
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
            seed = view.game.seed,
            techniques = view.game:techniques(),
        }
    end
    local dialog
    local function close_all()
        view._win_dialog = nil
        UIManager:close(dialog)
        UIManager:close(view, "flashui")
    end
    local title_lines = {
        _("Puzzle solved!"),
        "",
        T(_("Time: %1"), format_time(record.duration or 0))
            .. "   "
            .. T(_("Mistakes: %1"), tostring(record.mistakes or 0)),
    }
    local hints_text = T(_("Hints: %1"), tostring(#(record.hints or {})))
    if record.seed ~= nil then
        hints_text = hints_text .. "   " .. T(_("Seed: %1"), util.format_seed(record.seed))
    end
    title_lines[#title_lines + 1] = hints_text
    local req_tech = record.techniques
    if not req_tech and view.game and view.game.puzzle then
        req_tech = techniques.derive(view.game.puzzle)
    end
    if req_tech then
        local formatted = techniques.format_required(req_tech, 4)
        if formatted then
            title_lines[#title_lines + 1] = T(_("Techniques: %1"), formatted)
        end
    end

    dialog = ButtonDialog:new {
        title = table.concat(title_lines, "\n"),
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
                UIManager:close(diff_dialog)
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
            text = _("Custom…"),
            callback = function()
                UIManager:close(diff_dialog)
                dialogs.open_custom_difficulty_dialog(view, nil, function()
                    dialogs.open_difficulty_picker(view, cancel_cb)
                end)
            end,
        },
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

function dialogs.open_custom_difficulty_dialog(view, on_start, cancel_cb)
    local start_cb = on_start
        or function(difficulty, custom_opts)
            if view.new_game_cb then
                view.new_game_cb(difficulty, custom_opts)
            end
        end

    local function open_tier_picker()
        local tier_dialog
        local tiers = { "medium", "hard", "master", "expert" }
        local buttons = {}
        local current_row = {}
        for _, tier_id in ipairs(tiers) do
            current_row[#current_row + 1] = {
                text = difficulties.label(tier_id) or tier_id,
                callback = function()
                    UIManager:close(tier_dialog)
                    dialogs.open_custom_strategy_picker(view, tier_id, start_cb, function()
                        open_tier_picker()
                    end, cancel_cb)
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
                text = _("Back"),
                callback = function()
                    UIManager:close(tier_dialog)
                    if cancel_cb then
                        cancel_cb()
                    end
                end,
            },
        }
        tier_dialog = ButtonDialog:new {
            title = _("Custom difficulty — Strategy tier"),
            buttons = buttons,
            tap_close_callback = function()
                if cancel_cb then
                    cancel_cb()
                end
            end,
        }
        UIManager:show(tier_dialog)
    end

    open_tier_picker()
end

function dialogs.open_custom_strategy_picker(view, tier_id, on_start, back_cb, cancel_cb, selected_state)
    local tier_techs = techniques.by_tier(tier_id)
    local selected = selected_state
    if not selected then
        selected = {}
        for _, t in ipairs(tier_techs) do
            selected[t.id] = true
        end
    end

    local strat_dialog
    local function reopen(new_selected)
        if strat_dialog then
            UIManager:close(strat_dialog)
        end
        dialogs.open_custom_strategy_picker(view, tier_id, on_start, back_cb, cancel_cb, new_selected)
    end

    local buttons = {}
    for _, t in ipairs(tier_techs) do
        local check = selected[t.id] and "[✓] " or "[   ] "
        buttons[#buttons + 1] = {
            {
                text = check .. t.label,
                callback = function()
                    selected[t.id] = not selected[t.id]
                    reopen(selected)
                end,
            },
        }
    end

    buttons[#buttons + 1] = {
        {
            text = _("Select all"),
            callback = function()
                for _, t in ipairs(tier_techs) do
                    selected[t.id] = true
                end
                reopen(selected)
            end,
        },
        {
            text = _("Clear all"),
            callback = function()
                for _, t in ipairs(tier_techs) do
                    selected[t.id] = false
                end
                reopen(selected)
            end,
        },
    }

    buttons[#buttons + 1] = {
        {
            text = _("Generate"),
            callback = function()
                local chosen = {}
                for _, t in ipairs(tier_techs) do
                    if selected[t.id] then
                        chosen[#chosen + 1] = t.id
                    end
                end
                if #chosen == 0 then
                    UIManager:show(Notification:new { text = _("Please select at least one strategy.") })
                    return
                end
                UIManager:close(strat_dialog)
                on_start("custom", {
                    target_tier = tier_id,
                    required_techniques = chosen,
                })
            end,
        },
        {
            text = _("Back"),
            callback = function()
                UIManager:close(strat_dialog)
                if back_cb then
                    back_cb()
                end
            end,
        },
    }

    local tier_label = difficulties.label(tier_id) or tier_id
    strat_dialog = ButtonDialog:new {
        title = T(_("Custom %1 — Strategies"), tier_label),
        buttons = buttons,
        tap_close_callback = function()
            if cancel_cb then
                cancel_cb()
            end
        end,
    }
    UIManager:show(strat_dialog)
end

function dialogs.confirm_reset(view, cancel_cb)
    local confirm_dialog
    confirm_dialog = ConfirmBox:new {
        text = _("Reset this puzzle from the beginning? All progress will be lost."),
        ok_text = _("Reset"),
        ok_callback = function()
            local ok, err = view:resetGame(cancel_cb)
            if not ok then
                logger.warn("sudoku: reset failed: " .. tostring(err))
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

function dialogs.confirm_continue_custom_generation(
    parent,
    custom_options,
    current_attempts,
    next_attempts,
    continue_cb,
    cancel_cb
)
    local tier_label = difficulties.label(custom_options.target_tier) or custom_options.target_tier
    local tech_names = {}
    for _, id in ipairs(custom_options.required_techniques or {}) do
        tech_names[#tech_names + 1] = techniques.label(id) or id
    end
    local strategy_str = table.concat(tech_names, ", ")
    local text = T(
        _(
            "Could not generate a %1 puzzle requiring %2 in %3 attempts.\n\n"
                .. "Continue searching with +50% budget (%4 attempts)?"
        ),
        tier_label,
        strategy_str,
        tostring(current_attempts),
        tostring(next_attempts)
    )
    local confirm_dialog
    confirm_dialog = ConfirmBox:new {
        text = text,
        ok_text = T(_("Continue (%1)"), tostring(next_attempts)),
        ok_callback = function()
            if continue_cb then
                continue_cb()
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

function dialogs.confirm_persistence_failure(action, err, retry_cb, discard_cb)
    local confirm_dialog
    confirm_dialog = ConfirmBox:new {
        text = T(_("Could not %1.\n\n%2"), action, tostring(err)),
        ok_text = _("Retry"),
        ok_callback = retry_cb,
        cancel_text = _("Discard"),
        cancel_callback = discard_cb,
    }
    UIManager:show(confirm_dialog)
    return confirm_dialog
end

function dialogs.confirm_stats_recovery(err, retry_cb, reset_cb)
    local confirm_dialog = ConfirmBox:new {
        text = T(
            _("Could not load Sudoku statistics.\n\n%1\n\nReset permanently discards the existing statistics file."),
            tostring(err)
        ),
        ok_text = _("Retry"),
        ok_callback = retry_cb,
        cancel_text = _("Reset"),
        cancel_callback = reset_cb,
    }
    UIManager:show(confirm_dialog)
    return confirm_dialog
end

function dialogs.open_menu(view, skip_checkpoint)
    if view.game:is_finished() then
        dialogs.show_win_dialog(view)
        return
    end
    view.game:pause()
    view.menu_open = true
    -- A key press right before the menu opened may have armed the notes
    -- hold; invalidate it so the toggle cannot fire behind the dialog.
    view:_invalidateNotesHold()
    local checkpointed, checkpoint_err = true
    if not skip_checkpoint then
        checkpointed, checkpoint_err = view:checkpoint("pause")
    end
    if not checkpointed then
        view:showPersistenceFailure(_("save the paused game"), checkpoint_err, function()
            dialogs.open_menu(view)
        end, function()
            dialogs.open_menu(view, true)
        end)
        return
    end
    local dialog
    dialog = ButtonDialog:new {
        title = T(
            _("%1 — Time: %2    Mistakes: %3    Hints: %4"),
            difficulties.format_display(view.game:difficulty(), view.game.custom_tier) or view.game:difficulty(),
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
