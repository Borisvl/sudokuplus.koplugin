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

-- dp sizes are passed to Font:getFace raw: it applies Screen:scaleBySize
-- itself (KOReader convention, see ui/layout.lua). The geometry values below
-- are scaled explicitly.
local TITLE_DP = 24
local HEADER_DP = 18
local BODY_DP = 16
local MARGIN_DP = 14
local SPACING_DP = 8
local SECTION_GAP_DP = 12

function StatsView:init()
    self.width = self.width or Screen:getWidth()
    self.height = self.height or Screen:getHeight()
    self.dimen = Geom:new { x = 0, y = 0, w = self.width, h = self.height }
    local function scale(dp)
        return Screen:scaleBySize(dp)
    end
    self.faces = {
        title = Font:getFace("cfont", TITLE_DP),
        header = Font:getFace("cfont", HEADER_DP),
        body = Font:getFace("cfont", BODY_DP),
    }
    self.margin = scale(MARGIN_DP)
    self.spacing = scale(SPACING_DP)
    self.section_gap = scale(SECTION_GAP_DP)
    local function line_height(face)
        local size = RenderText:sizeUtf8Text(0, self.width, face, "Xy", false, false)
        return size.y_top - size.y_bottom + self.spacing
    end
    self.line_heights = {
        title = line_height(self.faces.title),
        header = line_height(self.faces.header),
        body = line_height(self.faces.body),
    }
    local border = math.max(2, scale(2))
    local inner_pad = border + self.spacing
    self.frame = {
        x = self.margin,
        y = self.margin,
        w = self.width - 2 * self.margin,
        h = self.height - 2 * self.margin,
        border = border,
        inner_x = self.margin + inner_pad,
        inner_y = self.margin + inner_pad,
        inner_w = self.width - 2 * (self.margin + inner_pad),
    }
    self.ges_events.Tap = {
        GestureRange:new {
            ges = "tap",
            range = Geom:new { x = 0, y = 0, w = self.width, h = self.height },
        },
    }
    self.key_events.Close = { { Device.input.group.Back } }
end

-- Splits `text` into lines that fit the frame's inner width, breaking on
-- spaces (RenderText does not wrap for us).
local function wrap_text(view, face, text)
    local lines = {}
    local current = ""
    local current_width = 0
    for word in text:gmatch("%S+") do
        local word_width = RenderText:sizeUtf8Text(0, view.frame.inner_w, face, word, false, false).x
        local space_width = current == "" and 0
            or RenderText:sizeUtf8Text(0, view.frame.inner_w, face, " ", false, false).x
        if current ~= "" and current_width + space_width + word_width > view.frame.inner_w then
            lines[#lines + 1] = current
            current = word
            current_width = word_width
        else
            current = current ~= "" and current .. " " .. word or word
            current_width = current_width + space_width + word_width
        end
    end
    if current ~= "" then
        lines[#lines + 1] = current
    end
    if #lines == 0 then
        lines[1] = ""
    end
    return lines
end

-- Paints `text` (wrapped to the frame width) starting at line_top and
-- returns the next line top. Lines that would spill past the frame bottom
-- are skipped (no scrolling in v1).
local function paint_line(bb, view, text, line_top, face, line_h, bold)
    for _, line in ipairs(wrap_text(view, face, text)) do
        if line_top + line_h <= view._bottom then
            local size = RenderText:sizeUtf8Text(0, view.frame.inner_w, face, line, false, bold)
            local baseline = line_top + math.floor((line_h + size.y_top - size.y_bottom) / 2)
            RenderText:renderUtf8Text(
                bb,
                view.frame.inner_x,
                baseline,
                face,
                line,
                false,
                bold,
                theme.digit,
                view.frame.inner_w
            )
        end
        line_top = line_top + line_h
    end
    return line_top
end

-- Centered page title.
local function paint_title(bb, view, text, line_top)
    local face = view.faces.title
    local line_h = view.line_heights.title
    if line_top + line_h > view._bottom then
        return line_top + line_h
    end
    local size = RenderText:sizeUtf8Text(0, view.frame.inner_w, face, text, false, true)
    local baseline = line_top + math.floor((line_h + size.y_top - size.y_bottom) / 2)
    local x = view.frame.inner_x + math.floor((view.frame.inner_w - size.x) / 2)
    RenderText:renderUtf8Text(bb, x, baseline, face, text, false, true, theme.digit, view.frame.inner_w)
    return line_top + line_h
end

-- Section header: bold text with a separator rule underneath.
local function paint_header(bb, view, text, line_top)
    line_top = paint_line(bb, view, text, line_top, view.faces.header, view.line_heights.header, true)
    local rule_y = line_top - view.spacing - 1
    if rule_y >= view.frame.inner_y then
        bb:paintRect(view.frame.inner_x, rule_y, view.frame.inner_w, 2, theme.grid_thin)
    end
    return line_top + view.spacing
end

function StatsView:paintTo(bb, x, y)
    local summary = self.summary or {}
    bb:paintRect(0, 0, self.width, self.height, theme.background)

    local f = self.frame
    bb:paintRect(f.x, f.y, f.w, f.border, theme.grid_thick)
    bb:paintRect(f.x, f.y + f.h - f.border, f.w, f.border, theme.grid_thick)
    bb:paintRect(f.x, f.y, f.border, f.h, theme.grid_thick)
    bb:paintRect(f.x + f.w - f.border, f.y, f.border, f.h, theme.grid_thick)

    self._bottom = f.y + f.h - f.border - self.spacing
    local top = f.y + f.border + self.spacing

    top = paint_title(bb, self, gettext("Sudoku statistics"), top)
    top = top + self.section_gap
    top = paint_line(
        bb,
        self,
        T(gettext("Streak: %1"), tostring(summary.streak or 0)),
        top,
        self.faces.body,
        self.line_heights.body,
        false
    )
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
        self.faces.body,
        self.line_heights.body,
        false
    )
    top = top + self.section_gap

    local per_difficulty = summary.per_difficulty or {}
    local has_difficulty = false
    for _, entry in ipairs(difficulties.list()) do
        local bucket = per_difficulty[entry.id]
        if bucket and bucket.count > 0 then
            has_difficulty = true
        end
    end
    if has_difficulty then
        top = paint_header(bb, self, gettext("By difficulty"), top)
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
                    self.faces.body,
                    self.line_heights.body,
                    false
                )
            end
        end
        top = top + self.section_gap
    end

    local hints_per_technique = summary.hints_per_technique or {}
    local techniques = {}
    for id, count in pairs(hints_per_technique) do
        techniques[#techniques + 1] = { id = id, count = count }
    end
    table.sort(techniques, function(a, b)
        return a.count > b.count or (a.count == b.count and a.id < b.id)
    end)
    if #techniques > 0 then
        top = paint_header(bb, self, gettext("Hints used"), top)
        for _, technique in ipairs(techniques) do
            top = paint_line(
                bb,
                self,
                T(gettext("%1: %2"), technique_name(technique.id), tostring(technique.count)),
                top,
                self.faces.body,
                self.line_heights.body,
                false
            )
        end
        top = top + self.section_gap
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
        self.faces.body,
        self.line_heights.body,
        false
    )

    paint_line(
        bb,
        self,
        gettext("Tap anywhere or press Back to close."),
        top,
        self.faces.body,
        self.line_heights.body,
        false
    )
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
