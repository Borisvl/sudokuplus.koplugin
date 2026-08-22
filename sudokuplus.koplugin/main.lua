local DataStorage = require("datastorage")
local InfoMessage = require("ui/widget/infomessage")
local Notification = require("ui/widget/notification")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local T = require("ffi/util").template
local _ = require("gettext")
local time = require("ui/time")

local difficulties = require("sudokuplus.ui.difficulties")
local dialogs = require("sudokuplus.ui.dialogs")
local board = require("sudokuplus.core.board")
local generator = require("sudokuplus.core.generator")
local game = require("sudokuplus.game")
local prng = require("sudokuplus.core.prng")
local stats = require("sudokuplus.stats")
local storage = require("sudokuplus.storage")
local util = require("sudokuplus.core.util")
local help = require("sudokuplus.ui.help")
local statsview = require("sudokuplus.ui.statsview")
local SudokuView = require("sudokuplus.ui.sudokuview")

local Sudoku = WidgetContainer:extend {
    name = "sudokuplus",
    is_doc_only = false,
}

local SAVE_PATH = DataStorage:getDataDir() .. "/sudokuplus_save"
local STATS_PATH = DataStorage:getDataDir() .. "/sudokuplus_stats"
local AUTOFILL_SETTING = "sudokuplus_autofill_notes"

Sudoku.storage_adapter = storage
Sudoku.save_path = SAVE_PATH
Sudoku.stats_path = STATS_PATH
Sudoku.now = os.time

-- Puzzle-generation seed from the wall clock at millisecond resolution.
-- os.time() alone has one-second granularity, so back-to-back games would
-- share a puzzle; UIManager:getTime() is an fts-encoded MONOTONIC value, so
-- mixing it into the seed conflates two clocks. time.realtime() is wall-clock
-- fts; its epoch-millisecond value is masked to the PRNG's 32-bit state by
-- prng.new.
local function seed_from_wall_clock()
    return math.floor(time.to_ms(time.realtime()))
end

Sudoku.seed_source = seed_from_wall_clock

local function copy_generation_options(options)
    local copied = {}
    for key, value in pairs(options or {}) do
        copied[key] = value
    end
    return copied
end

local function load_plugin_translations(base_path)
    if not _.loadMO then
        return
    end
    local lang = _.current_lang
    if not lang or lang == "" or lang == "C" then
        lang = G_reader_settings and G_reader_settings:readSetting("language") or "C"
    end
    if not lang or lang == "" or lang == "C" then
        return
    end
    local candidates = {
        lang,
        lang:gsub("[-_].*", ""),
    }
    for idx = 1, #candidates do
        local l = candidates[idx]
        if l and l ~= "" and l ~= "C" then
            local mo = base_path .. "/l10n/" .. l .. "/sudokuplus.mo"
            if _.loadMO(mo) then
                break
            end
        end
    end
end

function Sudoku:init()
    load_plugin_translations(self.path)
    self.ui.menu:registerToMainMenu(self)
end

function Sudoku:_resetStats(on_loaded)
    if type(on_loaded) ~= "function" then
        return nil, "on_loaded must be a function"
    end
    local fresh = stats.new()
    local saved, save_err = self.storage_adapter.save(self.stats_path, stats.to_table(fresh))
    if saved then
        on_loaded(fresh)
        return
    end
    dialogs.confirm_persistence_failure(_("reset the statistics"), save_err, function()
        self:_resetStats(on_loaded)
    end, function()
        on_loaded(fresh)
    end)
end

function Sudoku:_withStats(on_loaded)
    if type(on_loaded) ~= "function" then
        return nil, "on_loaded must be a function"
    end
    local s, err, backed_up, _, is_missing = self.storage_adapter.load_or_backup(self.stats_path, stats.from_table)
    if s then
        on_loaded(s)
        return true
    end
    if is_missing then
        s = stats.new()
        on_loaded(s)
        return true
    end
    if backed_up then
        logger.warn("sudoku: backed up corrupted stats file: " .. tostring(err))
    else
        logger.warn("sudoku: failed to load stats: " .. tostring(err))
    end
    dialogs.confirm_stats_recovery(err, function()
        self:_withStats(on_loaded)
    end, function()
        self:_resetStats(on_loaded)
    end)
    return nil, err
end

-- Shows the game view for `g` (used by every entry point so the view wiring
-- never drifts).
function Sudoku:_viewForGame(g, stats_data)
    local view
    view = SudokuView:new {
        game = g,
        stats = stats_data,
        save_path = self.save_path,
        stats_path = self.stats_path,
        storage_adapter = self.storage_adapter,
        new_game_cb = function(new_difficulty, custom_options)
            self:startGame(new_difficulty, custom_options, view)
        end,
        replay_cb = function(descriptor)
            self:replayGame(descriptor, view)
        end,
    }
    UIManager:show(view, "full")
    return view
end

function Sudoku:_resumeSourceView(source_view)
    if not source_view then
        return
    end
    source_view.menu_open = false
    if source_view.game:is_finished() then
        source_view:_showWinDialog()
        return
    end
    source_view.game:resume()
    source_view:refreshCoarse()
end

function Sudoku:_activateReplacement(g, stats_data, source_view)
    g:resume()
    if source_view then
        source_view.menu_open = false
        source_view:_closeWithoutCheckpoint()
    end
    self:_viewForGame(g, stats_data)
end

function Sudoku:_persistReplacement(g, stats_data, source_view)
    local persist
    local function activate()
        self:_activateReplacement(g, stats_data, source_view)
    end
    persist = function()
        local stats_saved, stats_err = self.storage_adapter.save(self.stats_path, stats.to_table(stats_data))
        if not stats_saved then
            dialogs.confirm_persistence_failure(_("save the new game statistics"), stats_err, persist, activate)
            return
        end
        local game_saved, game_err = self.storage_adapter.save(self.save_path, g:serialize())
        if not game_saved then
            dialogs.confirm_persistence_failure(_("save the new game"), game_err, persist, activate)
            return
        end
        activate()
    end
    persist()
end

-- Routes generation cancellation back to the initiating context.
function Sudoku:_cancelGeneration(generation_options, source_view)
    if generation_options and generation_options.on_cancel then
        generation_options.on_cancel()
    elseif source_view then
        self:_resumeSourceView(source_view)
    end
end

-- Carries the full generation context into the next bounded search. Replays
-- continue from the exhausted PRNG state and run only the newly added budget;
-- fresh games keep the established new-seed/full-budget behavior.
function Sudoku:_retryGeneration(
    difficulty,
    seed,
    generation_options,
    source_view,
    current_attempts,
    next_attempts,
    rng_state
)
    local next_options = copy_generation_options(generation_options)
    local next_seed
    if next_options.is_replay then
        next_options.attempts = next_attempts - current_attempts
        next_options.total_attempts = next_attempts
        next_options.rng_state = rng_state
        next_seed = seed
    else
        next_options.attempts = next_attempts
        next_options.total_attempts = next_attempts
        next_options.rng_state = nil
        next_seed = self.seed_source()
    end
    self:_startWithSeed(difficulty, next_seed, next_options, source_view)
end

-- Abandons the currently saved game only after a valid replacement payload
-- exists, then constructs and durably persists the fresh game. Generation and
-- exact replay share this transition so replay receives the same ID and
-- persistence guarantees without invoking the generator.
function Sudoku:_replaceWithPayload(payload, stats_data, source_view)
    -- A new puzzle replaces the active save: if the replaced game had been
    -- started (at least one move), close its log entry as abandoned. This
    -- happens only after a puzzle exists, so a failed generation keeps the
    -- old game tracked as in progress.
    local stats_source = source_view and source_view.stats or stats_data
    local candidate_stats, clone_err = stats.from_table(stats.to_table(stats_source))
    if not candidate_stats then
        self:_resumeSourceView(source_view)
        UIManager:show(InfoMessage:new {
            text = _("Failed to prepare the game statistics.") .. "\n" .. tostring(clone_err),
        })
        return
    end
    local old_save = self.storage_adapter.load(self.save_path)
    local old_record
    if source_view and source_view.game:is_started() then
        old_record = source_view.game:started_record()
    elseif old_save and type(old_save.id) == "number" and type(old_save.started_at) == "number" then
        local old_game = game.restore(old_save, { now = self.now })
        if old_game and old_game:is_started() then
            old_record = old_game:started_record()
        end
    end
    if old_record then
        local ok, abandon_err = stats.abandon(candidate_stats, old_record.id, self.now(), old_record)
        if not ok and abandon_err ~= "no tracked game with that id" then
            logger.warn("sudoku: failed to abandon the previous game: " .. tostring(abandon_err))
        end
    elseif old_save and type(old_save.started_at) == "number" then
        logger.warn("sudoku: could not verify the previous game identity; leaving its statistics unchanged")
    end
    local game_id = stats.reserve_id(candidate_stats)
    local g, game_err = game.new {
        puzzle = payload.board,
        solution = payload.solution,
        difficulty = payload.difficulty,
        custom_tier = payload.custom_tier,
        custom_techniques = payload.custom_techniques,
        allowed_techniques = payload.allowed_techniques,
        techniques = payload.techniques,
        seed = payload.seed,
        id = game_id,
        now = self.now,
        autofill_notes = G_reader_settings:isTrue(AUTOFILL_SETTING),
    }
    if not g then
        self:_resumeSourceView(source_view)
        UIManager:show(InfoMessage:new {
            text = _("Failed to start a game.") .. "\n" .. tostring(game_err),
        })
        return
    end
    g:pause()
    self:_persistReplacement(g, candidate_stats, source_view)
end

-- Generates a puzzle (wall-clock or legacy reproduction seed), then routes the
-- valid payload through the shared replacement transition.
function Sudoku:_startWithStats(difficulty, seed, generation_options, stats_data, source_view)
    -- Generation (expert especially) can take a few seconds; the emulator
    -- and the device are single-threaded, so explain the wait up front.
    -- forceRePaint() drains the paint/refresh queues immediately: without it
    -- the notification would only be drawn on the next UI tick, which never
    -- comes before the synchronous generation finishes.
    local generating = Notification:new { text = _("Generating…") }
    UIManager:show(generating)
    UIManager:forceRePaint()
    local attempts = generation_options and generation_options.attempts or 100
    local total_attempts = generation_options and generation_options.total_attempts or attempts
    local gen_opts = {
        difficulty = difficulty,
        seed = seed,
        rng = prng.new(generation_options and generation_options.rng_state or seed),
        max_attempts = attempts,
    }
    if difficulty == "custom" and generation_options then
        gen_opts.target_tier = generation_options.target_tier
        gen_opts.required_techniques = generation_options.required_techniques
    end
    local payload, gen_err = generator.generate_game(gen_opts)
    UIManager:close(generating)
    if not payload then
        logger.warn("sudoku: generation failed: " .. tostring(gen_err))
        local next_attempts = math.floor(total_attempts * 1.5)
        local retry_callback = function()
            self:_retryGeneration(
                difficulty,
                seed,
                generation_options,
                source_view,
                total_attempts,
                next_attempts,
                gen_opts.rng.state
            )
        end
        local cancel_callback = function()
            self:_cancelGeneration(generation_options, source_view)
        end
        if difficulty == "custom" and generation_options then
            dialogs.confirm_continue_custom_generation(
                generation_options,
                total_attempts,
                next_attempts,
                retry_callback,
                cancel_callback
            )
        else
            dialogs.confirm_retry_generation(difficulty, total_attempts, next_attempts, retry_callback, cancel_callback)
        end
        return
    end
    self:_replaceWithPayload(payload, stats_data, source_view)
end

function Sudoku:_withSourceCheckpoint(source_view, skip_source_checkpoint, callback)
    if source_view and not source_view.game:is_finished() and not skip_source_checkpoint then
        source_view.game:pause()
        local checkpointed, checkpoint_err = source_view:checkpoint("replacement")
        if not checkpointed then
            dialogs.confirm_persistence_failure(
                _("save the current game before replacing it"),
                checkpoint_err,
                function()
                    self:_withSourceCheckpoint(source_view, false, callback)
                end,
                function()
                    self:_withSourceCheckpoint(source_view, true, callback)
                end
            )
            return
        end
    end
    callback()
end

function Sudoku:_startWithSeed(difficulty, seed, generation_options, source_view, skip_source_checkpoint)
    self:_withSourceCheckpoint(source_view, skip_source_checkpoint, function()
        self:_withStats(function(stats_data)
            self:_startWithStats(difficulty, seed, generation_options, stats_data, source_view)
        end)
    end)
end

function Sudoku:_startExactReplay(payload, source_view, skip_source_checkpoint)
    self:_withSourceCheckpoint(source_view, skip_source_checkpoint, function()
        self:_withStats(function(stats_data)
            self:_replaceWithPayload(payload, stats_data, source_view)
        end)
    end)
end

function Sudoku:startGame(difficulty, generation_options, source_view)
    -- core/ is deterministic: seed the PRNG from the wall clock (ms) in the
    -- plugin layer. A fresh game abandons any previous save, but only once a
    -- new puzzle exists: a failed generation must not destroy the saved game.
    difficulty = util.is_difficulty(difficulty) and difficulty or "easy"
    self:_startWithSeed(difficulty, self.seed_source(), generation_options, source_view)
end

-- Restarts exact stored boards directly. Positional arguments remain accepted
-- for old callers and represent the legacy seed-generation fallback.
function Sudoku:replayGame(replay, difficulty_or_source, custom_tier, custom_techniques, positional_source_view)
    local descriptor
    local source_view
    if type(replay) == "table" then
        descriptor = {
            seed = replay.seed,
            difficulty = replay.difficulty,
            custom_tier = replay.custom_tier,
            custom_techniques = util.deep_copy(replay.custom_techniques),
            techniques = util.deep_copy(replay.techniques),
            puzzle = replay.puzzle,
            solution = replay.solution,
        }
        source_view = difficulty_or_source
    else
        descriptor = {
            seed = replay,
            difficulty = difficulty_or_source,
            custom_tier = custom_tier,
            custom_techniques = util.deep_copy(custom_techniques),
        }
        source_view = positional_source_view
    end

    local difficulty = util.is_difficulty(descriptor.difficulty) and descriptor.difficulty or "easy"
    local replay_custom_tier
    local replay_custom_techniques
    local allowed_techniques
    if difficulty == "custom" then
        local allowed, custom_or_err, validated_techniques =
            util.custom_allowed_techniques(descriptor.custom_tier, descriptor.custom_techniques)
        if not allowed then
            UIManager:show(InfoMessage:new {
                text = _("Failed to start a game.") .. "\n" .. tostring(custom_or_err),
            })
            return
        end
        allowed_techniques = allowed
        replay_custom_tier = custom_or_err
        replay_custom_techniques = validated_techniques
    end
    if type(descriptor.puzzle) == "string" and type(descriptor.solution) == "string" then
        local puzzle, puzzle_err = board.from_string(descriptor.puzzle)
        local solution, solution_err = board.from_string(descriptor.solution)
        if not puzzle or not solution then
            UIManager:show(InfoMessage:new {
                text = _("Failed to start a game.") .. "\n" .. tostring(puzzle_err or solution_err),
            })
            return
        end
        self:_startExactReplay({
            board = puzzle,
            solution = solution,
            difficulty = difficulty,
            custom_tier = replay_custom_tier,
            custom_techniques = util.deep_copy(replay_custom_techniques),
            allowed_techniques = allowed_techniques,
            techniques = util.deep_copy(descriptor.techniques),
            seed = descriptor.seed,
        }, source_view)
        return
    end

    local seed = descriptor.seed
    if type(seed) ~= "number" or seed % 1 ~= 0 then
        UIManager:show(InfoMessage:new {
            text = _("This game cannot be replayed (no reproduction seed)."),
        })
        return
    end
    local generation_options = {
        is_replay = true,
    }
    if difficulty == "custom" then
        generation_options = {
            target_tier = replay_custom_tier,
            required_techniques = replay_custom_techniques,
            is_replay = true,
        }
    end
    self:_startWithSeed(difficulty, seed, generation_options, source_view)
end

function Sudoku:continueGame()
    -- Any restore failure (JSON parse error, schema validation failure, unsupported
    -- future version, or 7-day timer-drift guard) backs up and removes the save to prevent
    -- a permanent dead end on "Continue", while preserving the data in <path>.<ts>.bak.
    local g, err, backed_up, bak_path = self.storage_adapter.load_or_backup(self.save_path, function(data)
        return game.restore(data, { now = self.now })
    end)
    if not g then
        if backed_up then
            local reason = err and ("\n" .. tostring(err)) or ""
            UIManager:show(InfoMessage:new {
                text = T(_("The save was corrupted; a backup was kept at %1"), tostring(bak_path)) .. reason,
            })
        elseif self.storage_adapter.exists(self.save_path) then
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
    self:_withStats(function(stats_data)
        local game_id, reconcile_err
        if g.id == nil then
            game_id, reconcile_err = stats.reserve_id(stats_data)
        else
            local identity = g:is_started() and g:started_record() or { id = g.id }
            game_id, reconcile_err = stats.reconcile_id(stats_data, identity)
        end
        if not game_id then
            UIManager:show(InfoMessage:new {
                text = _("Failed to reconcile the saved game statistics.") .. "\n" .. tostring(reconcile_err),
            })
            return
        end
        g.id = game_id

        local persist
        local function activate()
            -- The save was written while paused; a resumed game starts its timer.
            g:resume()
            self:_viewForGame(g, stats_data)
        end
        persist = function()
            local stats_saved, stats_err = self.storage_adapter.save(self.stats_path, stats.to_table(stats_data))
            if not stats_saved then
                dialogs.confirm_persistence_failure(
                    _("save the continued game statistics"),
                    stats_err,
                    persist,
                    activate
                )
                return
            end
            local game_saved, game_err = self.storage_adapter.save(self.save_path, g:serialize())
            if not game_saved then
                dialogs.confirm_persistence_failure(_("save the continued game"), game_err, persist, activate)
                return
            end
            activate()
        end
        persist()
    end)
end

function Sudoku:showStatistics()
    self:_withStats(function(s)
        -- "full": the Tools menu stays open underneath (keep_menu_open), so the
        -- new fullscreen page must refresh the whole screen itself.
        UIManager:show(
            statsview.dashboard(s, {
                replay_cb = function(descriptor)
                    self:replayGame(descriptor)
                end,
            }),
            "full"
        )
    end)
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
    new_game_items[#new_game_items + 1] = {
        text = _("Custom…"),
        callback = function()
            dialogs.open_custom_difficulty_dialog(self, function(difficulty, custom_opts)
                self:startGame(difficulty, custom_opts)
            end)
        end,
    }
    menu_items.sudokuplus = {
        text = _("Sudoku+"),
        sorting_hint = "more_tools",
        sub_item_table = {
            {
                text = _("Continue"),
                enabled_func = function()
                    return self.storage_adapter.exists(self.save_path)
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
                text = _("Help"),
                keep_menu_open = true,
                callback = function()
                    help.show_menu()
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
