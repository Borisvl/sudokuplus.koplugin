unused_args = false
-- ignore implicit self
self = false
std = "luajit"

-- KOReader runtime globals (mirrors KOReader's own .luacheckrc)
globals = {
    "G_reader_settings",
    "G_defaults",
}

-- don't balk on busted stuff in specs
files["tests/unit/*"] = {
    std = "+busted",
}
