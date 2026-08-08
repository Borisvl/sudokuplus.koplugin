local json = require("json")

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
    file:close()
    if not ok then
        os.remove(tmp_path)
        return nil, write_err or "failed to write file"
    end
    local renamed, rename_err = os.rename(tmp_path, path)
    if not renamed then
        os.remove(tmp_path)
        return nil, rename_err or "failed to write file"
    end
    return true
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

return storage
