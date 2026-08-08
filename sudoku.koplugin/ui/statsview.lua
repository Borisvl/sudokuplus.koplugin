local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local RenderText = require("ui/rendertext")
local UIManager = require("ui/uimanager")
local T = require("ffi/util").template
local gettext = require("gettext")

local difficulties = require("ui.difficulties")
local hints = require("core.hints")
local theme = require("ui.theme")
local util = require("core.util")

local TECHNIQUE_NAMES = {}
for _, technique in ipairs(hints.techniques() or {}) do
    TECHNIQUE_NAMES[technique.id] = technique.name
end

local function technique_name(id)
    return TECHNIQUE_NAMES[id] or id
end

local Screen = Device.screen

-- Fullscreen statistics report: streak, played/given-up counts, per-difficulty
-- times, hints per technique and the most missed strategy.
local StatsView = InputContainer:extend {
    name = "statsview",
    covers_fullscreen = true,
    width = nil,
    height = nil,
    summary = nil,
}

local TITLE_DP = 28
local BODY_DP = 20
local MARGIN_DP = 16
local SPACING_DP = 8

function StatsView:init()
    self.width = self.width or Screen:getWidth()
    self.height = self.height or Screen:getHeight()
    self.dimen = Geom:new { x = 0, y = 0, w = self.width, h = self.height }
    self.scale = function(dp)
        return Screen:scaleBySize(dp)
    end
    self.faces = {
        title = Font:getFace("cfont", self.scale(TITLE_DP)),
        body = Font:getFace("cfont", self.scale(BODY_DP)),
    }
    self.ges_events.Tap = {
        GestureRange:new {
            ges = "tap",
            range = Geom:new { x = 0, y = 0, w = self.width, h = self.height },
        },
    }
    self.key_events.Close = { { Device.input.group.Back } }
end

-- Paints one text line at y and returns the y of the next line.
local function paint_line(bb, view, text, y, bold)
    local face = bold and view.faces.title or view.faces.body
    local size = RenderText:sizeUtf8Text(0, view.width - 2 * view.margin, face, text, false, bold)
    local baseline = y + math.floor((view.line_height + size.y_top - size.y_bottom) / 2)
    RenderText:renderUtf8Text(
        bb,
        view.margin,
        baseline,
        face,
        text,
        false,
        bold,
        theme.digit,
        view.width - 2 * view.margin
    )
    return y + view.line_height
end

function StatsView:paintTo(bb, x, y)
    local summary = self.summary or {}
    bb:paintRect(0, 0, self.width, self.height, theme.background)

    self.margin = self.scale(MARGIN_DP)
    local spacing = self.scale(SPACING_DP)
    local title_size = RenderText:sizeUtf8Text(0, self.width, self.faces.title, "Xy", false, true)
    local body_size = RenderText:sizeUtf8Text(0, self.width, self.faces.body, "Xy", false, false)
    self.line_height =
        math.max(title_size.y_top - title_size.y_bottom + spacing, body_size.y_top - body_size.y_bottom + spacing)
    local top = self.margin

    top = paint_line(bb, self, gettext("Sudoku statistics"), top, true)
    top = top + spacing
    top = paint_line(bb, self, T(gettext("Streak: %1"), tostring(summary.streak or 0)), top, false)
    top = paint_line(
        bb,
        self,
        T(
            gettext("Games played: %1 (finished %2, given up %3)"),
            tostring(summary.games_played or 0),
            tostring(summary.finished_count or 0),
            tostring(summary.given_up_count or 0)
        ),
        top,
        false
    )
    top = top + spacing

    local per_difficulty = summary.per_difficulty or {}
    for _, entry in ipairs(difficulties.list()) do
        local bucket = per_difficulty[entry.id]
        if bucket and bucket.count > 0 then
            top = paint_line(
                bb,
                self,
                T(
                    gettext("%1: %2 games, avg %3, best %4"),
                    entry.label,
                    tostring(bucket.count),
                    util.format_time(bucket.avg_duration),
                    util.format_time(bucket.best_duration)
                ),
                top,
                false
            )
        end
    end
    top = top + spacing

    local hints_per_technique = summary.hints_per_technique or {}
    local techniques = {}
    for id, count in pairs(hints_per_technique) do
        techniques[#techniques + 1] = { id = id, count = count }
    end
    table.sort(techniques, function(a, b)
        return a.count > b.count or (a.count == b.count and a.id < b.id)
    end)
    if #techniques > 0 then
        top = paint_line(bb, self, gettext("Hints used"), top, false)
        for _, technique in ipairs(techniques) do
            top = paint_line(
                bb,
                self,
                T(gettext("%1: %2"), technique_name(technique.id), tostring(technique.count)),
                top,
                false
            )
        end
        top = top + spacing
    end

    local most_missed = summary.most_missed
    top = paint_line(
        bb,
        self,
        most_missed
                and T(
                    gettext("Most missed strategy: %1 (%2)"),
                    technique_name(most_missed.technique),
                    tostring(most_missed.count)
                )
            or gettext("Most missed strategy: none yet"),
        top,
        false
    )
    top = top + spacing

    paint_line(bb, self, gettext("Tap anywhere or press Back to close."), top, false)
end

function StatsView:onTap()
    UIManager:close(self, "flashui")
    return true
end

function StatsView:onClose()
    UIManager:close(self, "flashui")
    return true
end

return StatsView
