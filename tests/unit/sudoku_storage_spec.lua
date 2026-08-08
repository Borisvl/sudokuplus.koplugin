package.path = "plugins/sudoku.koplugin/?.lua;" .. package.path

local storage = require("storage")

local function temp_path()
    local name = os.tmpname()
    os.remove(name)
    return name
end

describe("storage", function()
    it("saves and loads a table round-trip", function()
        local path = temp_path()
        local payload = {
            version = 1,
            streak = 2,
            finished = {
                {
                    kind = "finished",
                    difficulty = "easy",
                    duration = 90.5,
                    hints = { "naked_pairs" },
                    mistakes = 0,
                    check_errors = 0,
                    timestamp = 1000,
                },
            },
            given_up = {},
        }

        assert.is_true(storage.save(path, payload))
        local loaded, err = storage.load(path)
        assert.is_nil(err)
        assert.are.same(payload, loaded)
        os.remove(path)
    end)

    it("round-trips boolean values in persisted data", function()
        local path = temp_path()
        local payload = { finished = false, timer = { running = true } }

        assert.is_true(storage.save(path, payload))
        local loaded, err = storage.load(path)
        os.remove(path)

        assert.is_nil(err)
        assert.are.same(payload, loaded)
    end)

    it("writes valid JSON text", function()
        local path = temp_path()
        assert.is_true(storage.save(path, { b = 1, a = { 1, 2 } }))

        local file = io.open(path, "rb")
        assert.is_not_nil(file)
        local text = file:read("*a")
        file:close()
        assert.are.equal('{"a":[1,2],"b":1}', text)
        os.remove(path)
    end)

    it("reports a missing file on load", function()
        local path = temp_path()
        os.remove(path)
        local loaded, err = storage.load(path)
        assert.is_nil(loaded)
        assert.is_string(err)
    end)

    it("reports corrupt files instead of crashing", function()
        local path = temp_path()
        local file = io.open(path, "wb")
        file:write('{"a": broken')
        file:close()

        local loaded, err = storage.load(path)
        assert.is_nil(loaded)
        assert.is_string(err)
        os.remove(path)
    end)

    it("overwrites an existing file and leaves no temp file behind", function()
        local path = temp_path()
        assert.is_true(storage.save(path, { first = true }))
        assert.is_true(storage.save(path, { second = true }))

        local loaded, err = storage.load(path)
        assert.is_nil(err)
        assert.are.same({ second = true }, loaded)
        assert.is_nil(io.open(path .. ".tmp", "rb"), "no temp file may remain after a save")
        os.remove(path)
    end)

    it("deletes files", function()
        local path = temp_path()
        assert.is_true(storage.save(path, { ok = true }))
        assert.is_true(storage.delete(path))
        local loaded, err = storage.load(path)
        assert.is_nil(loaded)
        assert.is_string(err)
    end)

    it("refuses to save unencodable data", function()
        local path = temp_path()
        local cyclic = {}
        cyclic.self = cyclic
        local ok, err = storage.save(path, cyclic)
        assert.is_nil(ok)
        assert.is_string(err)
        os.remove(path)
    end)
end)
