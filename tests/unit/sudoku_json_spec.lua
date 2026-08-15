package.path = "plugins/sudokuplus.koplugin/?.lua;" .. package.path

local json = require("json")

local function round_trip(value)
    local encoded, encode_err = json.encode(value)
    assert.is_nil(encode_err)
    local decoded, decode_err = json.decode(encoded)
    assert.is_nil(decode_err)
    return decoded
end

describe("json", function()
    it("encodes scalars", function()
        assert.are.equal("true", json.encode(true))
        assert.are.equal("false", json.encode(false))
        assert.are.equal("0", json.encode(0))
        assert.are.equal("-5", json.encode(-5))
        assert.are.equal("3.5", json.encode(3.5))
        assert.are.equal('"hello"', json.encode("hello"))
        assert.are.equal('""', json.encode(""))
    end)

    it("escapes strings", function()
        assert.are.equal('"a\\"b"', json.encode('a"b'))
        assert.are.equal('"a\\\\b"', json.encode("a\\b"))
        assert.are.equal('"a\\nb"', json.encode("a\nb"))
        assert.are.equal('"a\\tb"', json.encode("a\tb"))
        assert.are.equal('"a\\u0001b"', json.encode("a\1b"))
    end)

    it("encodes arrays and objects", function()
        assert.are.equal("[1,2,3]", json.encode({ 1, 2, 3 }))
        assert.are.equal("[]", json.encode({}))
        assert.are.equal('{"a":1,"b":2}', json.encode({ b = 2, a = 1 }))
        assert.are.equal('[{"a":1},2]', json.encode({ { a = 1 }, 2 }))
    end)

    it("orders object keys deterministically", function()
        local encoded = json.encode({ z = 1, m = 2, a = 3 })
        assert.are.equal('{"a":3,"m":2,"z":1}', encoded)
    end)

    it("decodes JSON text", function()
        assert.are.equal(true, json.decode(" true "))
        assert.are.equal(-7, json.decode("-7"))
        assert.are.equal(2.5, json.decode("2.5"))
        assert.are.equal(1e30, json.decode("1e30"))
        assert.are.equal(1.5e-3, json.decode("1.5e-3"))
        assert.are.same({ 1, 2, 3 }, json.decode("[1,2,3]"))
        assert.are.same({ a = 1 }, json.decode('{"a":1}'))
        assert.are.same({ a = { b = { 1, 2 } } }, json.decode('{"a":{"b":[1,2]}}'))
    end)

    it("decodes false values", function()
        local value, err = json.decode("false")
        assert.is_nil(err)
        assert.is_false(value)

        local nested, nested_err = json.decode('{"finished":false,"values":[true,false]}')
        assert.is_nil(nested_err)
        assert.is_false(nested.finished)
        assert.are.same({ true, false }, nested.values)
    end)

    it("rejects malformed JSON", function()
        local cases = {
            "",
            "{",
            "[1,",
            "{a:1}",
            "{'a':1}",
            "01",
            "1 2",
            "null",
            '"unterminated',
            '{"a":}',
            '{"a" 1}',
        }
        for _, text in ipairs(cases) do
            local decoded, err = json.decode(text)
            assert.is_nil(decoded, "must reject: " .. text)
            assert.is_string(err, "must report an error for: " .. text)
        end
    end)

    it("rejects unescaped control characters", function()
        local decoded, err = json.decode('"line\nbreak"')

        assert.is_nil(decoded)
        assert.is_string(err)
    end)

    it("decodes unicode escapes without throwing", function()
        local ok, decoded, err = pcall(json.decode, '"\\u20ac"')

        assert.is_true(ok)
        assert.is_nil(err)
        assert.are.equal("\226\130\172", decoded)
    end)

    it("rejects numbers that overflow to infinity", function()
        local decoded, err = json.decode("1e9999")

        assert.is_nil(decoded)
        assert.is_string(err)
    end)

    it("round-trips nested plain data", function()
        local value = {
            version = 1,
            streak = 3,
            finished = {
                {
                    kind = "finished",
                    difficulty = "hard",
                    duration = 120.5,
                    hints = { "x_wing" },
                    mistakes = 0,
                    check_errors = 1,
                    timestamp = 1234567,
                },
            },
            given_up = {},
            notes = { { 511, 0, 1 }, { 2, 3, 4 } },
        }
        assert.are.same(value, round_trip(value))
    end)

    it("round-trips floats and exponents", function()
        local value = { 0.1, 1e30, 1.5e-3, 1000000, -0.25 }
        assert.are.same(value, round_trip(value))
    end)

    it("rejects values that cannot be represented", function()
        local cyclic = {}
        cyclic.self = cyclic
        local encoded, err = json.encode(cyclic)
        assert.is_nil(encoded)
        assert.is_string(err)

        local bad_number, number_err = json.encode(0 / 0)
        assert.is_nil(bad_number)
        assert.is_string(number_err)

        local infinite, inf_err = json.encode(1 / 0)
        assert.is_nil(infinite)
        assert.is_string(inf_err)
    end)
end)
