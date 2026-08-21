local guard = {}

local installed = false

local function normalized(path, cwd)
    if type(path) ~= "string" or path == "" then
        return nil
    end
    if path:sub(1, 1) ~= "/" then
        path = cwd .. "/" .. path
    end
    local parts = {}
    for part in path:gmatch("[^/]+") do
        if part == ".." then
            parts[#parts] = nil
        elseif part ~= "." and part ~= "" then
            parts[#parts + 1] = part
        end
    end
    return "/" .. table.concat(parts, "/")
end

local function split_roots(text, cwd)
    local roots = {}
    for root in (text or ""):gmatch("[^:]+") do
        roots[#roots + 1] = normalized(root, cwd)
    end
    return roots
end

local function is_production_name(path, root)
    local prefix = root .. "/"
    if path:sub(1, #prefix) ~= prefix then
        return false
    end
    local relative = path:sub(#prefix + 1)
    local basenames = {
        "settings.reader.lua",
        "sudokuplus_save",
        "sudokuplus_stats",
        "sudoku_save",
        "sudoku_stats",
    }
    for _, basename in ipairs(basenames) do
        if relative == basename or relative:sub(1, #basename + 1) == basename .. "." then
            return true
        end
    end
    return false
end

function guard.install()
    if installed then
        return
    end

    local lfs = require("lfs")
    local cwd = lfs.currentdir()
    local home = normalized(os.getenv("KO_HOME"), cwd)
    local run_root = normalized(os.getenv("SUDOKU_TEST_RUN_ROOT"), cwd)
    local sentinel_root = normalized(os.getenv("SUDOKU_TEST_SENTINEL_ROOT"), cwd)
    assert(home and run_root and sentinel_root, "frontend tests require the isolated KO_HOME harness")
    assert(home:sub(1, #run_root + 1) == run_root .. "/", "KO_HOME must be inside SUDOKU_TEST_RUN_ROOT")
    assert(home ~= sentinel_root, "KO_HOME must not use the protected sentinel root")

    local original_open = io.open
    local marker = original_open(home .. "/.sudoku-test-home", "rb")
    assert(marker, "isolated KO_HOME marker is missing")
    marker:close()

    local protected_roots = split_roots(os.getenv("SUDOKU_PROTECTED_DATA_ROOTS"), cwd)
    protected_roots[#protected_roots + 1] = sentinel_root
    for _, root in ipairs(protected_roots) do
        assert(home ~= root, "KO_HOME must not equal a protected data root")
    end

    local function assert_allowed(path)
        local absolute = normalized(path, cwd)
        if not absolute then
            return
        end
        for _, root in ipairs(protected_roots) do
            if is_production_name(absolute, root) then
                error("frontend test blocked production data access: " .. absolute, 3)
            end
        end
    end

    local function assert_command_allowed(command)
        if type(command) ~= "string" then
            return
        end
        command = command:gsub("/+", "/")
        for _, root in ipairs(protected_roots) do
            if command:find(root .. "/", 1, true) then
                error("frontend test blocked command accessing protected data: " .. command, 3)
            end
        end
    end

    local original_remove = os.remove
    local original_rename = os.rename
    local original_input = io.input
    local original_output = io.output
    local original_lines = io.lines
    local original_popen = io.popen
    local original_execute = os.execute
    local original_loadfile = loadfile
    local original_dofile = dofile
    -- luacheck: push ignore 121 122
    io.open = function(path, mode)
        assert_allowed(path)
        return original_open(path, mode)
    end
    io.input = function(file)
        if type(file) == "string" then
            assert_allowed(file)
        end
        return original_input(file)
    end
    io.output = function(file)
        if type(file) == "string" then
            assert_allowed(file)
        end
        return original_output(file)
    end
    io.lines = function(path, ...)
        assert_allowed(path)
        return original_lines(path, ...)
    end
    io.popen = function(command, mode)
        assert_command_allowed(command)
        return original_popen(command, mode)
    end
    os.execute = function(command)
        if type(command) == "string" then
            assert_command_allowed(command)
        end
        return original_execute(command)
    end
    os.remove = function(path)
        assert_allowed(path)
        return original_remove(path)
    end
    os.rename = function(old_path, new_path)
        assert_allowed(old_path)
        assert_allowed(new_path)
        return original_rename(old_path, new_path)
    end
    loadfile = function(path, ...)
        assert_allowed(path)
        return original_loadfile(path, ...)
    end
    dofile = function(path)
        assert_allowed(path)
        return original_dofile(path)
    end
    -- luacheck: pop

    local DataStorage = require("datastorage")
    assert(
        normalized(DataStorage:getDataDir(), cwd) == home,
        "DataStorage must resolve to the isolated per-spec KO_HOME"
    )
    installed = true
end

function guard.is_installed()
    return installed
end

return guard
