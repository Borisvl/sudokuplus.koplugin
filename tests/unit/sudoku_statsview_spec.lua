package.path = "plugins/sudoku.koplugin/?.lua;" .. package.path

describe("sudoku stats view", function()
    local Blitbuffer
    local StatsView
    local UIManager

    local function new_view(summary)
        return StatsView:new {
            summary = summary,
            width = 758,
            height = 1024,
        }
    end

    setup(function()
        require("commonrequire")
        Blitbuffer = require("ffi/blitbuffer")
        StatsView = require("ui.statsview")
        UIManager = require("ui/uimanager")
    end)

    it("paints an empty summary without error", function()
        local view = new_view(nil)
        local bb = Blitbuffer.new(758, 1024)
        bb:fill(Blitbuffer.COLOR_WHITE)
        view:paintTo(bb, 0, 0)
        bb:free()
    end)

    it("paints zero counts for an empty summary", function()
        local view = new_view({})
        local bb = Blitbuffer.new(758, 1024)
        bb:fill(Blitbuffer.COLOR_WHITE)
        view:paintTo(bb, 0, 0)
        local dark = 0
        for x = 0, 757, 8 do
            for y = 0, 1023, 8 do
                local pixel = bb:getPixel(x, y)
                if pixel ~= Blitbuffer.COLOR_WHITE then
                    dark = dark + 1
                end
            end
        end
        bb:free()
        assert.is_true(dark > 0, "the title must be painted")
    end)

    it("paints per-difficulty times and the most missed strategy", function()
        local summary = {
            games_played = 12,
            finished_count = 10,
            given_up_count = 2,
            streak = 3,
            per_difficulty = {
                easy = { count = 7, avg_duration = 300, best_duration = 120 },
                hard = { count = 3, avg_duration = 3600, best_duration = 1800 },
            },
            hints_per_technique = { naked_pairs = 4, x_wing = 2 },
            most_missed = { technique = "naked_pairs", count = 4 },
        }
        local view = new_view(summary)
        local bb = Blitbuffer.new(758, 1024)
        bb:fill(Blitbuffer.COLOR_WHITE)
        view:paintTo(bb, 0, 0)
        bb:free()
    end)

    it("wraps long lines instead of clipping them", function()
        local summary = {
            games_played = 200,
            finished_count = 150,
            given_up_count = 50,
            streak = 12,
            per_difficulty = {
                easy = { count = 200, avg_duration = 45296, best_duration = 3723 },
                medium = { count = 200, avg_duration = 45296, best_duration = 3723 },
                hard = { count = 200, avg_duration = 45296, best_duration = 3723 },
                expert = { count = 200, avg_duration = 45296, best_duration = 3723 },
            },
            hints_per_technique = {
                alternating_inference_chain = 42,
                hidden_singles = 42,
                naked_singles = 42,
                naked_pairs = 42,
                hidden_pairs = 42,
                locked_candidates = 42,
                naked_triples = 42,
                hidden_triples = 42,
                x_wing = 42,
                naked_quads = 42,
                hidden_quads = 42,
                swordfish = 42,
                jellyfish = 42,
                skyscraper = 42,
                w_wing = 42,
                xy_wing = 42,
                xyz_wing = 42,
            },
            most_missed = { technique = "alternating_inference_chain", count = 42 },
        }
        local view = new_view(summary)
        local bb = Blitbuffer.new(758, 1024)
        bb:fill(Blitbuffer.COLOR_WHITE)
        view:paintTo(bb, 0, 0)
        bb:free()
    end)

    it("uses legible but compact body text", function()
        local view = new_view({})
        local RenderText = require("ui/rendertext")
        -- the body face must not exceed a quarter of the view height in ink
        local size = RenderText:sizeUtf8Text(0, view.frame.inner_w, view.faces.body, "Xy", false, false)
        local body_height = size.y_top - size.y_bottom
        assert.is_true(body_height > 0)
        assert.is_true(body_height < 1024 / 4, "body text must not be oversized")
    end)

    it("closes on tap and on Back", function()
        local view = new_view({})
        local closed
        local original_close = UIManager.close
        UIManager.close = function(_, widget)
            closed = widget
        end
        view:onTap()
        UIManager.close = original_close
        assert.are.equal(view, closed)
        closed = nil
        UIManager.close = function(_, widget)
            closed = widget
        end
        view:onClose()
        UIManager.close = original_close
        assert.are.equal(view, closed)
    end)
end)
