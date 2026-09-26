local errno = require('errno')
local json = require('json')
local t = require('luatest')

local helper = dofile('test/helper.lua')

local g = helper.group('tnt.config.reader')

local config = helper.config

--- Отказ разбора целиком: род, путь и текст.
---@param path string
---@param reason string
---@return table
local function invalid(path, reason)
    return {
        kind = 'invalid',
        path = path,
        message = ('файл настроек %s не разобран: %s'):format(path, reason),
    }
end

--- Отказ как простая таблица: поля без метатаблицы.
---@param err table
---@return table
local function fields(err)
    return { kind = err.kind, path = err.path, message = err.message }
end

-- ── Форматы ──────────────────────────────────────────────────────────

g.test_yaml_json_and_lua_data_are_read_by_the_extension = function()
    local expected = { app = { name = 'demo', port = 8080, debug = false, hosts = { 'a', 'b' } } }

    t.assert_equals(
        config.read(helper.put('site.yaml', 'app:\n  name: demo\n  port: 8080\n  debug: false\n  hosts: [a, b]\n')),
        expected
    )
    t.assert_equals(
        config.read(helper.put('site.yml', 'app: { name: demo, port: 8080, debug: false, hosts: [a, b] }')),
        expected
    )
    t.assert_equals(
        config.read(helper.put('site.json', '{"app":{"name":"demo","port":8080,"debug":false,"hosts":["a","b"]}}')),
        expected
    )
    t.assert_equals(
        config.read(
            helper.put(
                'site.lua',
                "return { app = { name = 'demo', port = 8080, debug = false, hosts = { 'a', 'b' } } }"
            )
        ),
        expected
    )
end

g.test_nulls_and_big_integers_are_data = function()
    local read = config.read(helper.put('big.json', '{"limit": 18446744073709551615, "none": null, "empty": {}}'))

    t.assert_equals(read.limit, 18446744073709551615ULL)
    t.assert_equals(read.none, box.NULL)
    t.assert_equals(json.encode(read.empty), '{}', 'пометка словаря на месте')
    t.assert_equals(config.read(helper.put('big.lua', 'return { limit = 5ULL, low = -5LL, far = 1/0 }')), {
        limit = 5ULL,
        low = -5LL,
        far = math.huge,
    })
end

g.test_an_unknown_extension_is_a_mistake_in_the_code = function()
    t.assert_equals(
        helper.blamed(function()
            config.read('site.toml')
        end),
        'файл настроек site.toml: расширение — .yaml, .yml, .json либо .lua'
    )
    t.assert_equals(
        helper.blamed(function()
            config.read('config')
        end),
        'файл настроек config: расширение — .yaml, .yml, .json либо .lua'
    )
    t.assert_equals(
        helper.blamed(function()
            config.read('site.lua.bak')
        end),
        'файл настроек site.lua.bak: расширение — .yaml, .yml, .json либо .lua'
    )
    t.assert_equals(
        helper.blamed(function()
            config.read('site_lua')
        end),
        'файл настроек site_lua: расширение — .yaml, .yml, .json либо .lua'
    )
    t.assert_equals(
        helper.blamed(function()
            config.read(helper.wrong(nil))
        end),
        'путь к файлу настроек — непустая строка, а не nil'
    )
end

-- ── Отказы ───────────────────────────────────────────────────────────

g.test_a_missing_file_is_the_refusal_of_the_disk = function()
    local path = helper.file('none.yaml')
    local read, err = config.read(path)

    t.assert_equals(read, nil)
    t.assert_equals(err.kind, 'missing')
    t.assert_equals(err.errno, errno.ENOENT)
    t.assert_equals(tostring(err), ('файл %s не прочитан: %s'):format(path, errno.strerror(errno.ENOENT)))
end

g.test_a_file_that_does_not_parse_is_invalid = function()
    local yaml_path = helper.put('bad.yaml', 'app: [unclosed\n')
    local lua_path = helper.put('bad.lua', 'return { app = }')

    local read, err = config.read(yaml_path)

    t.assert_equals(read, nil)
    t.assert_equals(err.kind, config.INVALID)
    t.assert_equals(err.path, yaml_path)
    t.assert_str_contains(err.message, ('файл настроек %s не разобран: '):format(yaml_path))

    local _, lua_err = config.read(lua_path)

    t.assert_equals(fields(lua_err), invalid(lua_path, lua_path .. ":1: unexpected symbol near '}'"))
end

g.test_an_empty_file_is_invalid_and_not_empty_settings = function()
    -- Оборванный на записи файл, прочитанный как «настроек нет», поднял бы
    -- приложение без единой настройки.
    local cases = {
        { 'empty.yaml', '', 'в нём не словарь настроек, а nil' },
        { 'null.yaml', '~', 'в нём не словарь настроек, а box.NULL' },
        { 'empty.lua', '', 'в нём не словарь настроек, а nil' },
        { 'number.json', '7', 'в нём не словарь настроек, а число' },
        { 'list.json', '["a"]', 'в нём не словарь настроек, а список' },
        { 'empty-list.json', '[]', 'в нём не словарь настроек, а список' },
        { 'list.lua', "return { 'a' }", 'в нём не словарь настроек, а список' },
    }

    for _, case in ipairs(cases) do
        local path = helper.put(case[1], case[2])
        local read, err = config.read(path)

        t.assert_equals(read, nil, case[1])
        t.assert_equals(fields(err), invalid(path, case[3]), case[1])
    end
end

g.test_lua_is_data_and_not_code = function()
    local globals = helper.put('code.lua', "return { app = io.open('/etc/passwd'):read('*a') }")
    local _, err = config.read(globals)

    t.assert_equals(fields(err), invalid(globals, globals .. ":1: attempt to index global 'io' (a nil value)"))

    local bytecode = helper.put(
        'bytecode.lua',
        string.dump(function()
            return {}
        end)
    )
    local _, dumped = config.read(bytecode)

    t.assert_equals(fields(dumped), invalid(bytecode, 'attempt to load chunk with wrong mode'))
end

g.test_what_is_not_data_is_invalid_with_its_place = function()
    local cases = {
        {
            'function.lua',
            'return { app = { handler = function() end } }',
            'app.handler — функция, а в файле настроек только данные',
        },
        {
            'key.lua',
            'return { app = { [true] = 1 } }',
            'app: ключ — строка либо число, а не логическое значение',
        },
        {
            'root.lua',
            'return { [false] = 1 }',
            'корень: ключ — строка либо число, а не логическое значение',
        },
        {
            'list.lua',
            'return { hosts = { 1, function() end } }',
            'hosts.2 — функция, а в файле настроек только данные',
        },
    }

    for _, case in ipairs(cases) do
        local path = helper.put(case[1], case[2])
        local _, err = config.read(path)

        t.assert_equals(fields(err), invalid(path, case[3]), case[1])
    end
end

g.test_a_table_met_twice_is_walked_once = function()
    -- Одна и та же таблица в двух местах — не беда, а кольцо без памяти
    -- об обойдённом обходилось бы без конца.
    local shared = helper.put('shared.lua', 'local s = { a = 1 } return { x = s, y = s }')
    local ring = helper.put('ring.lua', 'local r = { a = 1 } r.self = r return { r = r }')

    t.assert_equals(config.read(shared), { x = { a = 1 }, y = { a = 1 } })

    local read = config.read(ring)

    t.assert_is(read.r.self, read.r)
end

g.test_the_refusal_reads_as_its_text = function()
    local path = helper.put('bad.json', '[')
    local _, err = config.read(path)

    t.assert_equals(tostring(err), err.message)
    t.assert_equals('причина: ' .. err, 'причина: ' .. err.message)
    t.assert_equals(err .. '!', err.message .. '!')
    t.assert_equals(json.encode({ err = err }), json.encode({ err = err.message }))
end
