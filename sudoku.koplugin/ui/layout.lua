-- Pure geometry for the Sudoku game view. Screen size and a density
-- scaler are injected so the module stays headless-testable.

local layout = {}

local MARGIN_DP = 4
local BAR_HEIGHT_DP = 50
local BAR_GAP_DP = 4
local THICK_BORDER_DP = 3
local THIN_BORDER_DP = 1
local FONT_GIVEN_DP = 32
local FONT_USER_DP = 28
local FONT_NOTES_DP = 15
local FONT_DIGIT_DP = 24
local FONT_LABEL_DP = 16

local NUMBER_ROW = { 1, 2, 3, 4, 5, 6, 7, 8, 9, "erase" }
local TOOL_ROW = { "undo", "redo", "notes", "check", "menu" }

local function default_scale(dp)
    return math.max(1, math.ceil(dp))
end

local function bar_row(x, y, width, height, buttons)
    local count = #buttons
    local button_width = math.floor(width / count)
    local leftover = width - button_width * count
    local row = {
        x = x + math.floor(leftover / 2),
        y = y,
        w = button_width * count,
        h = height,
        buttons = {},
    }
    for i, id in ipairs(buttons) do
        row.buttons[i] = {
            id = id,
            x = row.x + (i - 1) * button_width,
            y = y,
            w = button_width,
            h = height,
        }
    end
    return row
end

function layout.compute(width, height, scale)
    if type(width) ~= "number" or type(height) ~= "number" or width <= 0 or height <= 0 then
        return nil, "width and height must be positive numbers"
    end
    if scale ~= nil and type(scale) ~= "function" then
        return nil, "scale must be a function"
    end
    scale = scale or default_scale

    local margin = scale(MARGIN_DP)
    local bar_height = scale(BAR_HEIGHT_DP)
    local gap = scale(BAR_GAP_DP)
    local thin = math.max(1, scale(THIN_BORDER_DP))
    local thick = math.max(1, scale(THICK_BORDER_DP))

    local grid_max_w = width - 2 * margin
    local grid_max_h = height - 2 * margin - 2 * bar_height - 2 * gap
    local side = math.max(0, math.min(grid_max_w, grid_max_h))
    local cell = math.max(0, math.floor((side - 6 * thin - 4 * thick) / 9))
    local grid_w = 9 * cell + 6 * thin + 4 * thick

    local number_y = height - margin - bar_height
    local tool_y = number_y - gap - bar_height

    return {
        width = width,
        height = height,
        margin = margin,
        bar_height = bar_height,
        gap = gap,
        thin = thin,
        thick = thick,
        grid = {
            x = margin + math.floor((width - 2 * margin - grid_w) / 2),
            y = margin,
            w = grid_w,
            h = grid_w,
            cell = cell,
        },
        fonts = {
            given = FONT_GIVEN_DP,
            user = FONT_USER_DP,
            notes = FONT_NOTES_DP,
            digit = FONT_DIGIT_DP,
            label = FONT_LABEL_DP,
        },
        number_row = bar_row(margin, number_y, width - 2 * margin, bar_height, NUMBER_ROW),
        tool_row = bar_row(margin, tool_y, width - 2 * margin, bar_height, TOOL_ROW),
    }
end

-- Pixel offset of the left (or top) edge of column (or row) `index`,
-- measured from the grid origin. Borders sit between cells.
function layout.cell_offset(index, cell, thin, thick)
    local box = math.floor(index / 3)
    return (box + 1) * thick + (index - box) * thin + index * cell
end

function layout.cell_rect(l, row, col)
    local offset = layout.cell_offset
    return {
        x = l.grid.x + offset(col, l.grid.cell, l.thin, l.thick),
        y = l.grid.y + offset(row, l.grid.cell, l.thin, l.thick),
        w = l.grid.cell,
        h = l.grid.cell,
    }
end

-- Bounding box ({x, y, w, h}) over the rects of the given cells (a set
-- keyed row * 9 + col), or nil when the set holds no valid cells.
function layout.cells_region(l, cell_keys)
    local min_x, min_y, max_x, max_y
    for key in pairs(cell_keys) do
        local row = math.floor(key / 9)
        local col = key % 9
        if row >= 0 and row <= 8 and col >= 0 and col <= 8 then
            local rect = layout.cell_rect(l, row, col)
            if min_x == nil then
                min_x, min_y = rect.x, rect.y
                max_x, max_y = rect.x + rect.w, rect.y + rect.h
            else
                min_x = math.min(min_x, rect.x)
                min_y = math.min(min_y, rect.y)
                max_x = math.max(max_x, rect.x + rect.w)
                max_y = math.max(max_y, rect.y + rect.h)
            end
        end
    end
    if min_x == nil then
        return nil
    end
    return { x = min_x, y = min_y, w = max_x - min_x, h = max_y - min_y }
end

-- One rect per cell (a set keyed row * 9 + col), merging only cells that are
-- horizontally adjacent in the same row into strips (borders included), so a
-- scattered selection never turns into one large rectangle; ordered by row,
-- then by column. Returns {} when the set holds no valid cells.
function layout.cells_regions(l, cell_keys)
    local rows = {}
    for key in pairs(cell_keys) do
        local row = math.floor(key / 9)
        local col = key % 9
        if row >= 0 and row <= 8 and col >= 0 and col <= 8 then
            local cols = rows[row]
            if not cols then
                cols = {}
                rows[row] = cols
            end
            cols[#cols + 1] = col
        end
    end
    local regions = {}
    for row = 0, 8 do
        local cols = rows[row]
        if cols then
            table.sort(cols)
            local start = cols[1]
            local prev = cols[1]
            for i = 2, #cols do
                local col = cols[i]
                if col ~= prev + 1 then
                    local first = layout.cell_rect(l, row, start)
                    local last = layout.cell_rect(l, row, prev)
                    regions[#regions + 1] = { x = first.x, y = first.y, w = last.x + last.w - first.x, h = first.h }
                    start = col
                end
                prev = col
            end
            local first = layout.cell_rect(l, row, start)
            local last = layout.cell_rect(l, row, prev)
            regions[#regions + 1] = { x = first.x, y = first.y, w = last.x + last.w - first.x, h = first.h }
        end
    end
    return regions
end

-- Line positions for grid painting: one separator between each pair of
-- consecutive cells, thin inside a box and thick between boxes.
function layout.grid_lines(l)
    local lines = { horizontal = {}, vertical = {} }
    for i = 0, 7 do
        local thickness = (i % 3 == 2) and l.thick or l.thin
        local pos = layout.cell_offset(i, l.grid.cell, l.thin, l.thick) + l.grid.cell
        lines.horizontal[#lines.horizontal + 1] = {
            y = l.grid.y + pos,
            w = l.grid.w,
            thickness = thickness,
        }
        lines.vertical[#lines.vertical + 1] = {
            x = l.grid.x + pos,
            h = l.grid.h,
            thickness = thickness,
        }
    end
    return lines
end

local function cell_index_at(l, x, y)
    if x < l.grid.x or y < l.grid.y or x >= l.grid.x + l.grid.w or y >= l.grid.y + l.grid.h then
        return nil
    end
    local inner_x = x - l.grid.x
    local inner_y = y - l.grid.y
    local function index_at(offset, cell, thin, thick)
        for i = 0, 8 do
            local start = layout.cell_offset(i, cell, thin, thick)
            if offset >= start and offset < start + cell then
                return i
            end
        end
        return nil
    end
    local row = index_at(inner_y, l.grid.cell, l.thin, l.thick)
    local col = index_at(inner_x, l.grid.cell, l.thin, l.thick)
    if row == nil or col == nil then
        return nil
    end
    return row, col
end

local function button_at(row, x, y)
    if y < row.y or y >= row.y + row.h then
        return nil
    end
    for _, button in ipairs(row.buttons) do
        if x >= button.x and x < button.x + button.w then
            return button.id
        end
    end
    return nil
end

function layout.hit(l, x, y)
    local row, col = cell_index_at(l, x, y)
    if row ~= nil then
        return { kind = "cell", row = row, col = col }
    end
    local number_id = button_at(l.number_row, x, y)
    if number_id ~= nil then
        return { kind = "button", id = number_id }
    end
    local tool_id = button_at(l.tool_row, x, y)
    if tool_id ~= nil then
        return { kind = "button", id = tool_id }
    end
    return nil
end

return layout
