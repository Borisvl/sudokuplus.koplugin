local Blitbuffer = require("ffi/blitbuffer")
local ButtonTable = require("ui/widget/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local InputContainer = require("ui/widget/container/inputcontainer")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Widget = require("ui/widget/widget")
local T = require("ffi/util").template
local _ = require("gettext")

local difficulties = require("ui.difficulties")
local numberbar = require("ui.numberbar")
local status_helper = require("ui.status")
local techniques_helper = require("ui.techniques")
local theme = require("ui.theme")
local util = require("core.util")

local Screen = Device.screen

-- A miniature 9x9 sudoku grid painted from the stored puzzle/board strings.
-- Givens use the bold face, user entries the regular one.
local MiniGrid = Widget:extend {
    name = "minigrid",
    size = nil,
    puzzle = nil,
    board = nil,
}

function MiniGrid:init()
    self.dimen = Geom:new { w = self.size, h = self.size }
    self.thick = math.max(2, math.floor(self.size / 90))
    self.thin = math.max(1, math.floor(self.size / 180))
    self.cell = (self.size - 4 * self.thick - 6 * self.thin) / 9
    local digit_dp = math.max(10, math.floor(self.size / 26))
    local bold_name = Font.bold_font_variant[Font.fontmap.cfont] or Font.fontmap.cfont
    self.faces = {
        given = Font:getFace(bold_name, digit_dp),
        user = Font:getFace("cfont", digit_dp),
    }
end

function MiniGrid:paintTo(bb, x, y)
    bb:paintRect(x, y, self.size, self.size, theme.background)
    local pos = 0
    for i = 0, 9 do
        local thick = i % 3 == 0
        local width = thick and self.thick or self.thin
        bb:paintRect(x, y + pos, self.size, width, thick and theme.grid_thick or theme.grid_thin)
        bb:paintRect(x + pos, y, width, self.size, thick and theme.grid_thick or theme.grid_thin)
        pos = pos + width
        if i < 9 then
            pos = pos + self.cell
        end
    end
    -- v1-migrated games carry no board snapshot: render the empty frame.
    if not self.board then
        return
    end
    local puzzle = self.puzzle or ""
    for r = 0, 8 do
        for c = 0, 8 do
            local index = r * 9 + c + 1
            local ch = self.board:sub(index, index)
            if ch ~= "0" then
                local given = puzzle:sub(index, index) ~= "0"
                local cell_x = x
                    + self.thick * (math.floor(c / 3) + 1)
                    + self.thin * (c - math.floor(c / 3))
                    + c * self.cell
                local cell_y = y
                    + self.thick * (math.floor(r / 3) + 1)
                    + self.thin * (r - math.floor(r / 3))
                    + r * self.cell
                local rect = {
                    x = cell_x,
                    y = cell_y,
                    w = self.cell,
                    h = self.cell,
                }
                numberbar.render_centered(
                    bb,
                    given and self.faces.given or self.faces.user,
                    ch,
                    given,
                    rect,
                    theme.digit
                )
            end
        end
    end
end

local function count_clues(puzzle)
    local n = 0
    for i = 1, 81 do
        if puzzle:sub(i, i) ~= "0" then
            n = n + 1
        end
    end
    return n
end

-- Fullscreen page for one logged game: miniature board + per-game stats and
-- a "Play again" action that regenerates the exact puzzle from its seed.
local GameDetail = InputContainer:extend {
    name = "gamedetail",
    covers_fullscreen = true,
    width = nil,
    height = nil,
    entries = nil,
    index = nil,
    entry = nil,
    replay_cb = nil,
}

function GameDetail:init()
    self.width = self.width or Screen:getWidth()
    self.height = self.height or Screen:getHeight()
    self.dimen = Geom:new { x = 0, y = 0, w = self.width, h = self.height }

    if not self.entries then
        self.entries = self.entry and { self.entry } or {}
        self.index = 1
    elseif not self.index then
        self.index = 1
    end
    self.entry = self.entries[self.index] or self.entry

    self.key_events.Close = { { Device.input.group.Back } }
    self.key_events.PrevGame = { { Device.input.group.PgBack, Device.input.group.Left } }
    self.key_events.NextGame = { { Device.input.group.PgFwd, Device.input.group.Right } }

    local entry = self.entry
    local difficulty = difficulties.label(entry.difficulty) or entry.difficulty
    local grid_size = math.floor(math.min(self.width * 0.50, self.height * 0.36))
    local text_width = math.floor(math.min(self.width, self.height) * 0.8)
    local body_face = Font:getFace("cfont", 18)

    local lines = {}
    local function add(text)
        lines[#lines + 1] = TextBoxWidget:new { text = text, width = text_width, face = body_face }
    end
    add(T(_("#%1 · %2 · %3"), tostring(entry.id or "?"), difficulty, status_helper.label(entry.status)))
    local time_text = T(_("Time: %1"), util.format_time(entry.duration or 0))
    if entry.started_at then
        time_text = time_text .. "   " .. T(_("Started: %1"), os.date("%Y-%m-%d %H:%M", entry.started_at))
    end
    add(time_text)
    add(T(_("Mistakes: %1   Check errors: %2"), entry.mistakes or 0, entry.check_errors or 0))
    add(T(_("Hints: %1   Moves: %2"), #(entry.hints or {}), entry.moves or 0))

    local placement_text = nil
    if entry.status ~= "finished" and entry.puzzle then
        local empty = 81 - count_clues(entry.puzzle)
        placement_text = T(_("Correct placements: %1 of %2"), entry.correct or 0, empty)
    end
    local seed_text = entry.seed ~= nil and T(_("Seed: %1"), util.format_seed(entry.seed)) or nil
    if placement_text and seed_text then
        add(placement_text .. "   " .. seed_text)
    elseif placement_text then
        add(placement_text)
    elseif seed_text then
        add(seed_text)
    end

    -- Do not reveal required techniques for in-progress puzzles to avoid spoilers.
    if entry.status ~= "in_progress" then
        local req_tech = entry.techniques
        if not req_tech then
            req_tech = techniques_helper.derive(entry.puzzle)
            if req_tech then
                entry.techniques = req_tech
            end
        end
        if req_tech then
            local formatted = techniques_helper.format_required(req_tech)
            if formatted then
                add(T(_("Techniques: %1"), formatted))
            end
        end
    end

    local grid = MiniGrid:new {
        size = grid_size,
        puzzle = entry.puzzle,
        board = entry.board,
    }

    local button_row = {}
    if #self.entries > 1 then
        button_row[#button_row + 1] = {
            text = "◀",
            enabled = self.index > 1,
            callback = function()
                self:onPrevGame()
            end,
        }
    end
    button_row[#button_row + 1] = {
        text = _("Back"),
        callback = function()
            UIManager:close(self, "flashui")
        end,
    }
    if self.replay_cb and entry.seed ~= nil then
        button_row[#button_row + 1] = {
            text = _("Play again"),
            callback = function()
                UIManager:close(self, "flashui")
                self.replay_cb(entry.seed, entry.difficulty)
            end,
        }
    end
    if #self.entries > 1 then
        button_row[#button_row + 1] = {
            text = "▶",
            enabled = self.index < #self.entries,
            callback = function()
                self:onNextGame()
            end,
        }
    end

    local content = VerticalGroup:new {
        align = "center",
        grid,
        VerticalSpan:new { width = Size.padding.default },
        VerticalGroup:new {
            align = "left",
            unpack(lines),
        },
        VerticalSpan:new { width = Size.padding.default },
        ButtonTable:new {
            width = text_width,
            buttons = { button_row },
            show_parent = self,
        },
    }

    self[1] = CenterContainer:new {
        dimen = self.dimen,
        FrameContainer:new {
            background = Blitbuffer.COLOR_WHITE,
            radius = Size.radius.window,
            padding = Size.padding.large,
            content,
        },
    }
end

function GameDetail:setIndex(index)
    if not self.entries or not self.entries[index] then
        return
    end
    self.index = index
    self.entry = self.entries[index]
    self:init()
    UIManager:setDirty(self, "ui")
end

function GameDetail:onPrevGame()
    if self.entries and self.index and self.index > 1 then
        self:setIndex(self.index - 1)
        return true
    end
end

function GameDetail:onNextGame()
    if self.entries and self.index and self.index < #self.entries then
        self:setIndex(self.index + 1)
        return true
    end
end

function GameDetail:onSwipe(arg, ges)
    if not ges then
        return
    end
    if ges.direction == "east" or ges.direction == "right" then
        return self:onPrevGame()
    elseif ges.direction == "west" or ges.direction == "left" then
        return self:onNextGame()
    end
end

function GameDetail:onClose()
    UIManager:close(self, "flashui")
    return true
end

return GameDetail
