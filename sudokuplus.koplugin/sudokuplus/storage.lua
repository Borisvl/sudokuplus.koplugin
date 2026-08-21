local json = require("sudokuplus.json")

local storage = {}

function storage.save(path, data)
    if type(path) ~= "string" then
        return nil, "path must be a string"
    end
    local text, encode_err = json.encode(data)
    if not text then
        return nil, encode_err
    end
    -- Write to a temp file and rename over the target so a crash or power
    -- cut never leaves a truncated save behind (rename is atomic on POSIX).
    local tmp_path = path .. ".tmp"
    local file, open_err = io.open(tmp_path, "wb")
    if not file then
        return nil, open_err
    end
    local ok, write_err = file:write(text)
    local close_ok, close_err = file:close()
    if not ok then
        os.remove(tmp_path)
        return nil, write_err or "failed to write file"
    end
    if not close_ok then
        os.remove(tmp_path)
        return nil, close_err or "failed to close file"
    end
    local renamed, rename_err = os.rename(tmp_path, path)
    if not renamed then
        os.remove(tmp_path)
        return nil, rename_err or "failed to write file"
    end
    return true
end

function storage.exists(path)
    if type(path) ~= "string" then
        return false
    end
    local file = io.open(path, "rb")
    if file then
        file:close()
        return true
    end
    return false
end

function storage.load(path)
    if type(path) ~= "string" then
        return nil, "path must be a string"
    end
    local file, open_err = io.open(path, "rb")
    if not file then
        return nil, open_err
    end
    local text = file:read("*a")
    file:close()
    if not text then
        return nil, "failed to read file"
    end
    return json.decode(text)
end

function storage.delete(path)
    if type(path) ~= "string" then
        return nil, "path must be a string"
    end
    local ok, err = os.remove(path)
    if not ok then
        return nil, err
    end
    return true
end

-- Attempts to load and deserialize a JSON data file from `path`.
-- Returns (obj, nil, false, nil, false) on success.
-- Returns (nil, err, false, nil, is_missing) on I/O read failure (is_missing is true ONLY for ENOENT/missing file).
-- Returns (nil, err, true, bak_path, false) if data corruption occurred (JSON error or deserialization exception)
-- and the corrupted file was safely backed up to `bak_path`.
-- If the corruption backup rename fails, returns (nil, err, false, nil, false).
function storage.load_or_backup(path, deserialize_fn)
    if type(path) ~= "string" then
        return nil, "path must be a string", false, nil, false
    end
    local file, open_err = io.open(path, "rb")
    if not file then
        local err_str = tostring(open_err)
        local is_missing = string.find(err_str, "No such file") ~= nil or string.find(err_str, "not found") ~= nil
        return nil, open_err, false, nil, is_missing
    end
    local text = file:read("*a")
    file:close()
    if not text then
        return nil, "failed to read file", false, nil, false
    end

    local decode_ok, data, decode_err = pcall(json.decode, text)
    if not decode_ok then
        decode_err = data
        data = nil
    end

    local obj, deser_err
    if data ~= nil then
        if deserialize_fn then
            local ok, res_or_err, err_detail = pcall(deserialize_fn, data)
            if ok then
                obj = res_or_err
                deser_err = err_detail
            else
                deser_err = res_or_err
            end
        else
            obj = data
        end
    end

    if obj ~= nil then
        return obj, nil, false, nil, false
    end

    local err_msg = tostring(deser_err or decode_err or "corrupt data")
    local timestamp = os.time()
    local bak_path = string.format("%s.%d.bak", path, timestamp)
    local counter = 1
    while storage.exists(bak_path) do
        counter = counter + 1
        bak_path = string.format("%s.%d_%d.bak", path, timestamp, counter)
    end

    local renamed, rename_err = os.rename(path, bak_path)
    if not renamed then
        return nil, "corrupt file backup failed (" .. tostring(rename_err) .. "): " .. err_msg, false, nil, false
    end

    return nil, err_msg, true, bak_path, false
end

return storage
