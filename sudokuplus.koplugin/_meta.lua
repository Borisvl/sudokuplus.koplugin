local ok, _ = pcall(require, "gettext")
if not ok then
    _ = function(s)
        return s
    end
end

return {
    name = "sudokuplus",
    fullname = _("Sudoku+"),
    description = _([[A logical Sudoku puzzle game and tutor for e-ink readers.]]),
    version = "1.1.0",
}
