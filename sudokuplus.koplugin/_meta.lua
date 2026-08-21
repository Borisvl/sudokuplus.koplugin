local ok, _ = pcall(require, "gettext")
if not ok then
    _ = function(s)
        return s
    end
end

local metadata = require("sudokuplus.metadata")

return {
    name = metadata.name,
    fullname = _("Sudoku+"),
    description = _([[A logical Sudoku puzzle game and tutor for e-ink readers.]]),
    version = metadata.version,
}
