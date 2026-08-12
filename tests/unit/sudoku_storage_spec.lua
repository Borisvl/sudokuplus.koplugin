package.path = "plugins/sudoku.koplugin/?.lua;" .. package.path

local storage = require("storage")

local counter = 0
local function temp_path()
    counter = counter + 1
    local name = string.format("sudoku_test_tmp_%d_%d.json", os.time(), counter)
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
        assert.is_true(storage.exists(path), "pure storage.load must leave corrupt file untouched")
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

    it("checks file existence correctly", function()
        local path = temp_path()
        assert.is_false(storage.exists(path))
        assert.is_true(storage.save(path, { ok = true }))
        assert.is_true(storage.exists(path))
        storage.delete(path)
        assert.is_false(storage.exists(path))
    end)

    it("handles write errors during save without leaving temp files behind", function()
        local path = temp_path()

        -- luacheck: push ignore 122
        local real_io_open = io.open
        io.open = function(p, mode)
            if string.sub(p, -4) == ".tmp" then
                local real_file = real_io_open(p, mode)
                return {
                    write = function()
                        return nil, "write error"
                    end,
                    close = function(self)
                        return real_file:close()
                    end,
                }
            end
            return real_io_open(p, mode)
        end

        local status, ok, write_err = pcall(function()
            return storage.save(path, { test = true })
        end)
        io.open = real_io_open
        -- luacheck: pop

        assert.is_true(status)
        assert.is_nil(ok)
        assert.are.equal("write error", write_err)
        assert.is_false(storage.exists(path .. ".tmp"))
    end)

    it("handles close errors during save without replacing the original file (CE-2)", function()
        local path = temp_path()
        assert.is_true(storage.save(path, { original = true }))

        -- luacheck: push ignore 122
        local real_io_open = io.open
        io.open = function(p, mode)
            if string.sub(p, -4) == ".tmp" then
                local real_file = real_io_open(p, mode)
                return {
                    write = function(self, text)
                        return real_file:write(text)
                    end,
                    close = function(self)
                        real_file:close()
                        return nil, "No space left on device"
                    end,
                }
            end
            return real_io_open(p, mode)
        end

        local status, ok, save_err = pcall(function()
            return storage.save(path, { corrupted = true })
        end)
        io.open = real_io_open
        -- luacheck: pop

        assert.is_true(status)
        assert.is_nil(ok)
        assert.are.equal("No space left on device", save_err)
        assert.is_false(storage.exists(path .. ".tmp"), "tmp file must be removed on close failure")

        local loaded = storage.load(path)
        assert.are.same({ original = true }, loaded, "original save file must not be overwritten on close failure")
        os.remove(path)
    end)

    it("load_or_backup loads valid data without backing up", function()
        local path = temp_path()
        local payload = { version = 1, games = {} }
        assert.is_true(storage.save(path, payload))

        local loaded, err, backed_up = storage.load_or_backup(path)
        assert.is_nil(err)
        assert.is_false(backed_up)
        assert.are.same(payload, loaded)
        os.remove(path)
    end)

    it("load_or_backup distinguishes missing file read failures from corruption", function()
        local path = temp_path()
        os.remove(path)

        local obj, err, backed_up, bak_path, is_missing = storage.load_or_backup(path)
        assert.is_nil(obj)
        assert.is_string(err)
        assert.is_false(backed_up, "missing file read failure must not trigger backup")
        assert.is_nil(bak_path)
        assert.is_true(is_missing)
    end)

    it("load_or_backup returns is_missing=false for non-ENOENT open failures", function()
        local path = temp_path()

        -- luacheck: push ignore 122
        local real_io_open = io.open
        io.open = function(p, mode)
            if p == path then
                return nil, "Permission denied"
            end
            return real_io_open(p, mode)
        end

        local status, obj, err, backed_up, bak_path, is_missing = pcall(function()
            return storage.load_or_backup(path)
        end)
        io.open = real_io_open
        -- luacheck: pop

        assert.is_true(status)
        assert.is_nil(obj)
        assert.are.equal("Permission denied", err)
        assert.is_false(backed_up)
        assert.is_nil(bak_path)
        assert.is_false(is_missing, "Permission denied open failure must have is_missing=false")
    end)

    it("load_or_backup creates collision-free backup names when multiple corruptions occur", function()
        local path1 = temp_path()
        local file1 = io.open(path1, "wb")
        file1:write('{"version": corrupt1')
        file1:close()

        local _, _, backed_up1, bak_path1 = storage.load_or_backup(path1)
        assert.is_true(backed_up1)
        assert.is_string(bak_path1)

        local file2 = io.open(path1, "wb")
        file2:write('{"version": corrupt2')
        file2:close()

        local _, _, backed_up2, bak_path2 = storage.load_or_backup(path1)
        assert.is_true(backed_up2)
        assert.is_string(bak_path2)
        assert.are_not.equal(bak_path1, bak_path2, "backup paths must be distinct to prevent collision")

        os.remove(path1)
        if bak_path1 then
            os.remove(bak_path1)
        end
        if bak_path2 then
            os.remove(bak_path2)
        end
    end)

    it("load_or_backup backs up corrupted JSON syntax to timestamped .bak (CE-1)", function()
        local path = temp_path()
        local file = io.open(path, "wb")
        file:write('{"version": corrupted_json')
        file:close()

        local obj, err, backed_up, bak_path = storage.load_or_backup(path)
        assert.is_nil(obj)
        assert.is_string(err)
        assert.is_true(backed_up, "corrupted file must be backed up")
        assert.is_false(storage.exists(path), "original corrupted file must be moved")
        assert.is_string(bak_path)
        assert.is_true(storage.exists(bak_path), "backup file must exist")

        os.remove(path)
        if bak_path then
            os.remove(bak_path)
        end
    end)

    it("load_or_backup backs up schema deserialization failure to timestamped .bak (CE-1)", function()
        local path = temp_path()
        assert.is_true(storage.save(path, { invalid_schema = true }))

        local function fail_deserializer()
            return nil, "invalid schema format"
        end

        local obj, err, backed_up, bak_path = storage.load_or_backup(path, fail_deserializer)
        assert.is_nil(obj)
        assert.are.equal("invalid schema format", err)
        assert.is_true(backed_up, "schema failure must trigger backup")
        assert.is_false(storage.exists(path), "corrupted file must be moved")
        assert.is_string(bak_path)
        assert.is_true(storage.exists(bak_path), "backup file must exist")

        os.remove(path)
        if bak_path then
            os.remove(bak_path)
        end
    end)

    it("load_or_backup catches deserializer exceptions and triggers backup (CE-1)", function()
        local path = temp_path()
        assert.is_true(storage.save(path, { crash_schema = true }))

        local function throwing_deserializer()
            error("attempt to index nil in deserializer")
        end

        local obj, err, backed_up, bak_path = storage.load_or_backup(path, throwing_deserializer)
        assert.is_nil(obj)
        assert.is_string(err)
        assert.is_true(backed_up, "throwing deserializer must trigger backup")
        assert.is_false(storage.exists(path))
        assert.is_string(bak_path)
        assert.is_true(storage.exists(bak_path))

        os.remove(path)
        if bak_path then
            os.remove(bak_path)
        end
    end)

    it("load_or_backup handles os.rename failure gracefully", function()
        local path = temp_path()
        assert.is_true(storage.save(path, { invalid_schema = true }))

        -- luacheck: push ignore 122
        local real_rename = os.rename
        os.rename = function()
            return nil, "Permission denied"
        end

        local status, obj, err, backed_up = pcall(function()
            return storage.load_or_backup(path, function()
                return nil, "schema error"
            end)
        end)
        os.rename = real_rename
        -- luacheck: pop

        assert.is_true(status)
        assert.is_nil(obj)
        assert.is_string(err)
        assert.is_false(backed_up, "must return backed_up=false when os.rename fails")
        assert.is_true(storage.exists(path), "file remains when rename fails")
        os.remove(path)
    end)
end)
