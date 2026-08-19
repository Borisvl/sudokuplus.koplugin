package.path = "plugins/sudokuplus.koplugin/?.lua;" .. package.path

local board = require("core.board")
local generator = require("core.generator")
local prng = require("core.prng")
local solve_path = require("core.solve_path")
local solver = require("core.solver")
local sudoku = require("core.sudoku")
local flags = require("core.techniques.flags")

local ALL_TECHNIQUES = flags.ALL

describe("core.generator game payload", function()
    it("returns puzzle, solution, difficulty and clue count", function()
        local payload, err = generator.generate_game({
            difficulty = "medium",
            max_attempts = 50,
            rng = prng.new(4242),
        })

        assert.is_nil(err)
        assert.is_not_nil(payload)
        assert.is_not_nil(payload.board)
        assert.is_not_nil(payload.solution)
        assert.are.equal("medium", payload.difficulty)
        assert.are.equal(board.count_clues(payload.board), payload.clues)
        assert.is_table(payload.techniques)

        assert.are.equal(81, board.count_clues(payload.solution))
        assert.is_not_nil(solver.validate(payload.solution))
        for i = 1, 81 do
            if payload.board[i] ~= 0 then
                assert.are.equal(payload.board[i], payload.solution[i])
            end
        end

        local solutions = solver.new(payload.board):solve_until(2)
        assert.are.equal(1, #solutions)
        assert.are.equal(board.to_string(payload.solution), board.to_string(solutions[1].board))
    end)

    it("returns techniques list matching classification for generated puzzles", function()
        local payload, err = generator.generate_game({
            difficulty = "medium",
            seed = 3,
            rng = prng.new(3),
        })

        assert.is_nil(err)
        assert.is_not_nil(payload)
        assert.is_table(payload.techniques)
        assert.is_true(#payload.techniques > 0)
    end)

    it("keeps difficulty-targeted clue counts above the documented range floors", function()
        -- P3: the weighted clue-target picker (medium/hard) must never dig
        -- below the difficulty range floor, and must be deterministic per
        -- seed. The upper bound is NOT asserted: the greedy dig can stall
        -- above the target (expert targets 17..22 routinely land at 23..28).
        local ranges = {
            beginner = 38,
            easy = 30,
            medium = 26,
            hard = 24,
            master = 22,
            expert = 17,
        }
        for _, entry in ipairs({
            { "beginner", 1 },
            { "easy", 2 },
            { "medium", 3 },
            { "hard", 4 },
            { "master", 5 },
            { "expert", 6 },
        }) do
            local diff, seed = entry[1], entry[2]
            local payload, err = generator.generate_game {
                difficulty = diff,
                seed = seed,
                rng = prng.new(seed),
            }
            assert.is_nil(err)
            assert.is_not_nil(payload)
            assert.is_true(
                payload.clues >= ranges[diff],
                diff .. " clues " .. payload.clues .. " below range floor " .. ranges[diff]
            )
        end

        local a = assert(generator.generate_game({ difficulty = "medium", seed = 9, rng = prng.new(9) }))
        local b = assert(generator.generate_game({ difficulty = "medium", seed = 9, rng = prng.new(9) }))
        assert.are.equal(board.to_string(a.board), board.to_string(b.board))
        assert.are.equal(a.clues, b.clues)
    end)

    it("classifies difficulty when none is requested", function()
        local payload, err = generator.generate_game({ rng = prng.new(77) })

        assert.is_nil(err)
        assert.is_not_nil(payload)
        assert.is_not_nil(payload.difficulty)
        assert.is_not_nil(payload.solution)
        assert.are.equal(board.count_clues(payload.board), payload.clues)
    end)

    it("does not label a guessing puzzle as a technique-only game", function()
        local payload, err = generator.generate_game({ rng = prng.new(85) })
        assert.is_nil(err)
        assert.is_not_nil(payload)

        local solutions = solver
            .new(payload.board, {
                techniques = ALL_TECHNIQUES,
                rng = prng.new(85),
            })
            :solve_until(2)
        assert.are.equal(1, #solutions)
        local classification = solve_path.classify(solutions[1].solve_path)

        assert.is_false(classification.requires_guessing)
    end)

    it("rejects invalid options like generate", function()
        local payload, err = generator.generate_game({ difficulty = "impossible", rng = prng.new(1) })

        assert.is_nil(payload)
        assert.is_string(err)
    end)

    it("is deterministic for a fixed seed", function()
        local a, a_err = generator.generate_game({ difficulty = "easy", rng = prng.new(123) })
        local b, b_err = generator.generate_game({ difficulty = "easy", rng = prng.new(123) })

        assert.is_nil(a_err)
        assert.is_nil(b_err)
        assert.are.equal(board.to_string(a.board), board.to_string(b.board))
        assert.are.equal(board.to_string(a.solution), board.to_string(b.solution))
        assert.are.equal(a.difficulty, b.difficulty)
    end)

    it("is exposed through the sudoku facade", function()
        local payload, err = sudoku.generate_game({ difficulty = "hard", rng = prng.new(5) })

        assert.is_nil(err)
        assert.is_not_nil(payload)
        assert.is_not_nil(payload.solution)
        assert.are.equal("hard", payload.difficulty)
    end)

    it("records the generation seed when one is provided", function()
        local payload, err = generator.generate_game({
            difficulty = "easy",
            seed = 1234567,
            rng = prng.new(1234567),
        })

        assert.is_nil(err)
        assert.is_not_nil(payload)
        assert.are.equal(1234567, payload.seed, "the payload must expose the seed for reproduction")
    end)

    it("snapshots the rng state as the seed when none is provided", function()
        -- A fresh prng.new(seed) stores the normalized seed in state; recording
        -- it lets the puzzle be reproduced with prng.new(payload.seed).
        local payload, err = generator.generate_game({ difficulty = "easy", rng = prng.new(4242) })

        assert.is_nil(err)
        assert.is_not_nil(payload)
        assert.are.equal(prng.new(4242).state, payload.seed, "seed must be the rng's initial state")

        local replay, replay_err = generator.generate_game({
            difficulty = "easy",
            rng = prng.new(payload.seed),
        })
        assert.is_nil(replay_err)
        assert.is_not_nil(replay)
        assert.are.equal(
            board.to_string(payload.board),
            board.to_string(replay.board),
            "the recorded seed must reproduce the exact puzzle"
        )
    end)

    it("rejects a non-integer seed", function()
        local payload, err = generator.generate_game({
            difficulty = "easy",
            seed = 1.5,
            rng = prng.new(4242),
        })

        assert.is_nil(payload)
        assert.is_string(err)
    end)

    it("never hard-fails on an exact difficulty match: returns the closest valid puzzle", function()
        -- Force every attempt to classify as "hard" so "medium" can never
        -- match exactly; the generator must fall back to the closest usable
        -- puzzle (labeled with its actual difficulty) instead of failing.
        local solve_path_mod = require("core.solve_path")
        local original_classify = solve_path_mod.classify
        solve_path_mod.classify = function()
            return {
                difficulty = "hard",
                requires_guessing = false,
                hardest_flags = flags.X_WING,
                hardest_step_number = 1,
                non_single_count = 2,
            }
        end
        finally(function()
            solve_path_mod.classify = original_classify
        end)

        local payload, err = generator.generate_game({
            difficulty = "medium",
            max_attempts = 20,
            rng = prng.new(9999),
        })

        assert.is_nil(err)
        assert.is_not_nil(payload, "a best-effort puzzle must be returned instead of failing")
        assert.are.equal("hard", payload.difficulty, "the payload reports the actual classification")
        assert.are.equal(board.count_clues(payload.board), payload.clues)
        assert.is_not_nil(payload.solution)
    end)

    it("fallback prefers density-passing adjacent tier over non-dense exact match", function()
        local solve_path_mod = require("core.solve_path")
        local original_classify = solve_path_mod.classify
        local attempt = 0
        solve_path_mod.classify = function()
            attempt = attempt + 1
            if attempt == 1 then
                -- Attempt 1: exact difficulty match ("medium") but fails density (1 non-single)
                return {
                    difficulty = "medium",
                    requires_guessing = false,
                    hardest_flags = flags.NAKED_PAIRS,
                    hardest_step_number = 1,
                    non_single_count = 1,
                }
            else
                -- Subsequent attempts: adjacent tier ("hard") passing density (2 non-singles)
                return {
                    difficulty = "hard",
                    requires_guessing = false,
                    hardest_flags = flags.HIDDEN_PAIRS,
                    hardest_step_number = 1,
                    non_single_count = 2,
                }
            end
        end
        finally(function()
            solve_path_mod.classify = original_classify
        end)

        local payload, err = generator.generate_game({
            difficulty = "medium",
            max_attempts = 3,
            rng = prng.new(1234),
        })

        assert.is_nil(err)
        assert.is_not_nil(payload)
        -- Dense "hard" neighbor (score 1) must beat non-dense "medium" exact match (score 10)
        assert.are.equal("hard", payload.difficulty)
    end)

    it("generates within the search node budget on fixed seeds", function()
        -- P4 guard: the generator passes a search_budget to every solver it
        -- creates. With the fixed seeds below the cap must never fire — if a
        -- future change lowers the budget, difficulty targeting would degrade
        -- silently (digs would restore clues, classifications would reject).
        local mt = getmetatable(solver.new(board.new(), {}))
        local orig_su = mt.solve_until
        local orig_cs = mt.count_solutions
        local caps = 0
        local max_nodes = 0
        function mt:solve_until(bound)
            local result = orig_su(self, bound)
            max_nodes = math.max(max_nodes, self.search_nodes or 0)
            if self.search_capped then
                caps = caps + 1
            end
            return result
        end
        function mt:count_solutions(limit)
            local result = orig_cs(self, limit)
            max_nodes = math.max(max_nodes, self.search_nodes or 0)
            if self.search_capped then
                caps = caps + 1
            end
            return result
        end

        for _, entry in ipairs({
            { "beginner", 101 },
            { "easy", 102 },
            { "medium", 103 },
            { "hard", 104 },
            { "master", 105 },
            { "expert", 106 },
        }) do
            local payload, err = generator.generate_game {
                difficulty = entry[1],
                seed = entry[2],
                rng = prng.new(entry[2]),
            }
            assert.is_nil(err)
            assert.is_not_nil(payload)
        end

        assert.are.equal(0, caps, "no search call may hit the budget on these fixed seeds")
        assert.is_not_nil(max_nodes)
        assert.is_true(max_nodes > 0, "the instrumented solvers must actually run")
    end)

    it("digs safely and never hard-fails when uniqueness checks hit the budget (P4)", function()
        -- Force every dig uniqueness check (techniques == 0, non-empty board)
        -- to a tiny node budget so most checks cap. Capped removals must be
        -- restored, the final confirmation must accept (the dig invariant
        -- guarantees uniqueness), and generation must not hard-fail.
        local board_mod = require("core.board")
        local solver_mod = require("core.solver")
        local original_new = solver_mod.new
        solver_mod.new = function(b, opts)
            opts = opts or {}
            if opts.techniques == 0 and board_mod.count_clues(b) > 0 then
                opts = { rng = opts.rng, techniques = 0, search_budget = 100 }
            end
            return original_new(b, opts)
        end
        finally(function()
            solver_mod.new = original_new
        end)

        local payload, err = generator.generate_game { difficulty = "easy", seed = 123, rng = prng.new(123) }
        assert.is_nil(err)
        assert.is_not_nil(payload)
        assert.are.equal("easy", payload.difficulty)
        local solutions = solver.new(payload.board):solve_until(2)
        assert.are.equal(1, #solutions, "the dig invariant must hold even with capped checks")
    end)

    it("ensures medium, hard, and master games have at least 2 non-single steps", function()
        for _, diff in ipairs({ "medium", "hard", "master" }) do
            local payload, err = generator.generate_game {
                difficulty = diff,
                seed = 777,
                rng = prng.new(777),
            }
            assert.is_nil(err)
            assert.is_not_nil(payload)
            assert.are.equal(diff, payload.difficulty, diff .. " generation should hit the target tier on seed 777")
            local solutions = solver
                .new(payload.board, {
                    techniques = ALL_TECHNIQUES,
                    rng = prng.new(777),
                })
                :solve_until(2)
            assert.are.equal(1, #solutions)
            local clues = board.count_clues(payload.board)
            local classification = solve_path.classify(solutions[1].solve_path, { clues = clues })
            assert.is_true(
                classification.non_single_count >= 2,
                diff .. " must have >= 2 non-single steps to avoid single-step bottlenecks"
            )
        end
    end)

    it("property: every generated game is unique and matches its solution under an independent plain solve", function()
        for _, entry in ipairs({
            { "beginner", 101 },
            { "easy", 102 },
            { "medium", 103 },
            { "hard", 104 },
            { "master", 105 },
            { "expert", 106 },
        }) do
            local payload, err = generator.generate_game {
                difficulty = entry[1],
                seed = entry[2],
                rng = prng.new(entry[2]),
            }

            assert.is_nil(err)
            assert.is_not_nil(payload)

            -- The plain (technique-less) solver is independent of the
            -- generator's techniques-based classification.
            local solutions = solver.new(payload.board):solve_all()
            assert.are.equal(1, #solutions, entry[1] .. " must be uniquely solvable by the plain solver")
            assert.are.equal(
                board.to_string(payload.solution),
                board.to_string(solutions[1].board),
                entry[1] .. " payload solution must match the plain solve"
            )
            assert.are.equal(entry[1], payload.difficulty, entry[1] .. " difficulty claim")
            assert.is_not_nil(payload.seed, entry[1] .. " must record a reproduction seed")
        end
    end)

    describe("custom difficulty generation", function()
        it("generates a custom puzzle requiring selected techniques", function()
            local payload, err = generator.generate_game({
                difficulty = "custom",
                target_tier = "medium",
                required_techniques = { "naked_pairs" },
                seed = 1,
                rng = prng.new(1),
            })

            assert.is_nil(err)
            assert.is_not_nil(payload)
            assert.are.equal("custom", payload.difficulty)
            assert.are.equal("medium", payload.custom_tier)
            assert.are.same({ "naked_pairs" }, payload.custom_techniques)
            assert.is_number(payload.allowed_techniques)
            assert.are.equal(bit.bor(flags.EASY, flags.NAKED_PAIRS), payload.allowed_techniques)

            -- Verify that the puzzle contains naked_pairs
            local has_naked_pair = false
            for _, id in ipairs(payload.techniques) do
                if id == "naked_pairs" then
                    has_naked_pair = true
                    break
                end
            end
            assert.is_true(has_naked_pair)

            -- Verify it solves completely via pure propagation (no guessing) under allowed_techniques
            local s = solver.new(payload.board, { techniques = payload.allowed_techniques })
            local path = solve_path.new()
            assert.is_true(s:propagate(path))
            assert.is_true(s:is_solved(), "must solve to completion under allowed_techniques without guessing")
        end)

        it("generates custom puzzles across all strategy tiers", function()
            local test_tiers = {
                { tier = "hard", techs = { "hidden_pairs", "naked_triples" }, seed = 456 },
                { tier = "master", techs = { "swordfish", "x_wing" }, seed = 789 },
                { tier = "expert", techs = { "x_chain", "aic" }, seed = 1011 },
            }
            for _, cfg in ipairs(test_tiers) do
                local payload, err = generator.generate_game({
                    difficulty = "custom",
                    target_tier = cfg.tier,
                    required_techniques = cfg.techs,
                    seed = cfg.seed,
                    rng = prng.new(cfg.seed),
                })
                assert.is_nil(err, "generation error for " .. cfg.tier)
                assert.is_not_nil(payload, "payload for " .. cfg.tier)
                assert.are.equal("custom", payload.difficulty)
                assert.are.equal(cfg.tier, payload.custom_tier)
                assert.are.same(cfg.techs, payload.custom_techniques)

                -- Verify at least one of the required techniques is present
                local has_required = false
                local req_set = {}
                for _, id in ipairs(cfg.techs) do
                    req_set[id] = true
                end
                for _, id in ipairs(payload.techniques) do
                    if req_set[id] then
                        has_required = true
                        break
                    end
                end
                assert.is_true(has_required, cfg.tier .. " puzzle must contain at least one required technique")

                -- Verify it solves completely via pure propagation under payload.allowed_techniques
                local s = solver.new(payload.board, { techniques = payload.allowed_techniques })
                local path = solve_path.new()
                assert.is_true(s:propagate(path))
                assert.is_true(s:is_solved(), cfg.tier .. " must solve completely under allowed techniques")
            end
        end)

        it("accepts a puzzle containing any one of the selected techniques (any-of contract)", function()
            -- Player selects both x_wing and swordfish
            local payload, err = generator.generate_game({
                difficulty = "custom",
                target_tier = "master",
                required_techniques = { "x_wing", "swordfish" },
                seed = 789,
                rng = prng.new(789),
            })
            assert.is_nil(err)
            assert.is_not_nil(payload)
            local tech_set = {}
            for _, t in ipairs(payload.techniques) do
                tech_set[t] = true
            end
            -- It has at least one of them, without necessarily requiring both
            assert.is_true(tech_set["x_wing"] or tech_set["swordfish"])
        end)

        it("validates custom options strictly", function()
            local bad_tier, err1 = generator.generate_game({
                difficulty = "custom",
                target_tier = "invalid",
                required_techniques = { "naked_pairs" },
            })
            assert.is_nil(bad_tier)
            assert.is_string(err1)

            local empty_req, err2 = generator.generate_game({
                difficulty = "custom",
                target_tier = "medium",
                required_techniques = {},
            })
            assert.is_nil(empty_req)
            assert.is_string(err2)

            local wrong_tier_tech, err3 = generator.generate_game({
                difficulty = "custom",
                target_tier = "medium",
                required_techniques = { "x_wing" },
            })
            assert.is_nil(wrong_tier_tech)
            assert.is_string(err3)

            local non_custom_allowed, err4 = generator.generate_game({
                difficulty = "easy",
                allowed_techniques = flags.ALL,
            })
            assert.is_nil(non_custom_allowed)
            assert.is_string(err4)
        end)
    end)
end)
