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
