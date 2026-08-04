unused_args = false
-- ignore implicit self
self = false
std = "luajit"

-- don't balk on busted stuff in specs
files["tests/unit/*"] = {
    std = "+busted",
}
