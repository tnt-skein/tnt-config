local errno = require('errno')
local fio = require('fio')
local t = require('luatest')

local helper = dofile('test/helper.lua')

local g = helper.group('tnt.config.writer')

local config = helper.config

--- Текст одного значения, как его пишет запись: `return { v = … }`.
---@param value any
---@return string
local function written(value)
    return config.encode({ v = value }):match('^return {\n    v = (.-),\n}\n$')
end

--- Что прочитается из текста, который написала запись.
---@param text string
---@return table
local function loaded(text)
    return assert(load(text, '=encoded', 't', {}))()
end

-- ── Вид файла ────────────────────────────────────────────────────────

g.test_the_file_is_lua_data_with_keys_in_order = function()
    local text = config.encode({
        mail = { host = 'mx', port = 25 },
        app = { name = 'demo', hosts = { 'a', 'b' }, empty = {} },
    })

    t.assert_equals(
        text,
        table.concat({
            'return {',
            '    app = {',
            '        empty = {},',
            '        hosts = {',
            '            [1] = "a",',
            '            [2] = "b",',
            '        },',
            '        name = "demo",',
            '    },',
            '    mail = {',
            '        host = "mx",',
            '        port = 25,',
            '    },',
            '}',
            '',
        }, '\n')
    )
    t.assert_equals(config.encode({}), 'return {}\n')
end

g.test_numbers_come_before_names_and_both_are_sorted = function()
    -- На трёх-четырёх ключах порядок совпадает и у сортировки с ошибкой
    -- в сравнении, а на широком словаре — уже нет; числа сравниваются
    -- числами: строкой 1000 встала бы раньше 4.
    local wide = {}
    local names = {}

    for index = 1, 26 do
        local name = string.char(string.byte('z') - index + 1) .. 'k'

        wide[name] = index
        table.insert(names, 1, name)
    end

    wide[1000] = 'тысяча'
    wide[4] = 'четыре'
    wide[-1] = 'минус'
    wide[0.5] = 'половина'

    local keys = {}

    for key in config.encode(wide):gmatch('\n    ([^\n]-) = ') do
        table.insert(keys, key)
    end

    local expected = { '[-1]', '[0.5]', '[4]', '[1000]' }

    for _, name in ipairs(names) do
        table.insert(expected, name)
    end

    t.assert_equals(keys, expected)
end

g.test_a_key_that_is_not_a_name_is_written_in_brackets = function()
    t.assert_equals(
        config.encode({
            ['a-b'] = 1,
            ['end'] = 2,
            ['goto'] = 3,
            ['nil'] = 4,
            ['9lives'] = 5,
            ['_ok'] = 6,
            ['ok_1'] = 7,
            [''] = 8,
            [math.huge] = 9,
        }),
        table.concat({
            'return {',
            '    [1/0] = 9,',
            '    [""] = 8,',
            '    ["9lives"] = 5,',
            '    _ok = 6,',
            '    ["a-b"] = 1,',
            '    ["end"] = 2,',
            '    ["goto"] = 3,',
            '    ["nil"] = 4,',
            '    ok_1 = 7,',
            '}',
            '',
        }, '\n')
    )
end

g.test_every_lua_word_is_a_bracketed_key = function()
    local words = {
        'and',
        'break',
        'do',
        'else',
        'elseif',
        'end',
        'false',
        'for',
        'function',
        'goto',
        'if',
        'in',
        'local',
        'nil',
        'not',
        'or',
        'repeat',
        'return',
        'then',
        'true',
        'until',
        'while',
    }
    local settings = {}

    for index, word in ipairs(words) do
        settings[word] = index
    end

    local text = config.encode(settings)

    for _, word in ipairs(words) do
        t.assert_str_contains(text, ('\n    ["%s"] = '):format(word))
    end

    t.assert_equals(loaded(text), settings)
end

g.test_numbers_are_written_to_read_back_the_same = function()
    t.assert_equals(written(25), '25')
    t.assert_equals(written(-7), '-7')
    t.assert_equals(written(0.5), '0.5')
    t.assert_equals(written(0.1), '0.1')
    t.assert_equals(written(2 ^ 53), '9007199254740992')
    t.assert_equals(written(0.1 + 0.2), '0.30000000000000004')
    t.assert_equals(written(1e300), '1e+300')
    t.assert_equals(written(math.huge), '1/0')
    t.assert_equals(written(-math.huge), '-1/0')
    t.assert_equals(written(0 / 0), '0/0')
    t.assert_equals(written(18446744073709551615ULL), '18446744073709551615ULL')
    t.assert_equals(written(-5LL), '-5LL')
    t.assert_equals(written(true), 'true')
    t.assert_equals(written(false), 'false')

    local back = loaded(config.encode({ a = 2 ^ 53, b = 0.1 + 0.2, c = -math.huge, d = 0 / 0, e = 5ULL }))

    t.assert_equals(back.a, 2 ^ 53)
    t.assert_equals(back.b, 0.1 + 0.2)
    t.assert_equals(back.c, -math.huge)
    t.assert_not_equals(back.d, back.d)
    t.assert_equals(back.e, 5ULL)
end

g.test_strings_are_written_to_read_back_the_same = function()
    local text = 'кавычка " и черта \\,\nперевод\r\0ноль\1'

    t.assert_equals(loaded(config.encode({ v = text })).v, text)
    t.assert_equals(written('узел'), '"узел"')
end

g.test_null_under_a_name_is_not_written = function()
    -- box.NULL и значит «не задано»: прочитанный набор отдал бы умолчание.
    t.assert_equals(config.encode({ a = box.NULL, b = { c = box.NULL } }), 'return {\n    b = {},\n}\n')
end

g.test_the_same_table_twice_is_written_twice = function()
    local shared = { a = 1 }

    t.assert_equals(loaded(config.encode({ x = shared, y = { z = shared } })), {
        x = { a = 1 },
        y = { z = { a = 1 } },
    })
end

-- ── Не данные ────────────────────────────────────────────────────────

g.test_what_is_not_data_is_refused_at_the_caller_with_its_place = function()
    local ring = { a = 1 }

    ring.inner = { back = ring }

    local cases = {
        {
            { app = { handler = print } },
            'настройки.app.handler — функция, а в файл настроек ложатся только данные',
        },
        {
            { id = require('uuid').new() },
            'настройки.id — cdata, а в файл настроек ложатся только данные',
        },
        {
            { app = { [true] = 1 } },
            'настройки.app: ключ — строка либо число, а не логическое значение',
        },
        {
            { [false] = 1 },
            'настройки: ключ — строка либо число, а не логическое значение',
        },
        {
            { hosts = { 'a', box.NULL, 'c' } },
            'настройки.hosts.2 — box.NULL на месте в списке: дыра прочиталась бы словарём',
        },
        {
            { ring = ring },
            'настройки.ring.inner.back содержит саму себя — кольцо в файл не записать',
        },
    }

    for _, case in ipairs(cases) do
        t.assert_equals(
            helper.blamed(function()
                config.encode(case[1])
            end),
            case[2]
        )
        t.assert_equals(
            helper.blamed(function()
                config.write(helper.file('config.lua'), case[1])
            end),
            case[2]
        )
    end

    t.assert_equals(fio.path.exists(helper.file('config.lua')), false, 'файл не заведён')
end

g.test_arguments_are_checked_at_the_caller = function()
    local cases = {
        {
            function()
                config.encode(helper.wrong('x'))
            end,
            'настройки — таблица, а не строка',
        },
        {
            function()
                config.write(helper.wrong(nil), {})
            end,
            'путь к файлу настроек — непустая строка, а не nil',
        },
        {
            function()
                config.write('config.lua', helper.wrong(7))
            end,
            'настройки — таблица, а не число',
        },
        {
            function()
                config.write('config.lua', {}, helper.wrong({ header = 'x' }))
            end,
            'настройки записи: ключа «header» нет, есть comment',
        },
        {
            function()
                config.write('config.lua', {}, helper.wrong({ comment = 7 }))
            end,
            'настройки записи.comment — строка, а не число',
        },
    }

    for _, case in ipairs(cases) do
        t.assert_equals(helper.blamed(case[1]), case[2])
    end
end

-- ── Запись ───────────────────────────────────────────────────────────

g.test_write_puts_the_file_with_its_directory_and_it_reads_back = function()
    local path = helper.file('bootstrap/cache/config.lua')
    local settings = { app = { name = 'demo', limit = 2 ^ 53, big = 5ULL }, ['end'] = { far = math.huge } }

    t.assert_equals(config.write(path, settings), true)
    t.assert_equals(config.read(path), settings)
    t.assert_equals(helper.get(path), config.encode(settings))
end

g.test_the_file_is_for_the_owner_only_even_over_a_wider_one = function()
    -- В собранных настройках тайны лежат открытым текстом.
    local path = helper.put('config.lua', 'return {}\n')

    fio.chmod(path, tonumber('644', 8) --[[@as integer]])

    t.assert_equals(config.write(path, { secret = 'x' }), true)
    t.assert_equals(fio.stat(path).mode % 512, tonumber('600', 8))
    t.assert_equals(config.MODE, tonumber('600', 8))
end

g.test_the_comment_goes_first_line_by_line = function()
    local path = helper.file('config.lua')

    config.write(
        path,
        { a = 1 },
        { comment = 'Собрано заранее.\n\nОкружение не читается.' }
    )

    t.assert_equals(
        helper.get(path),
        '-- Собрано заранее.\n-- Окружение не читается.\nreturn {\n    a = 1,\n}\n'
    )

    config.write(path, { a = 2 }, {})

    t.assert_equals(helper.get(path), 'return {\n    a = 2,\n}\n')

    -- `\r` Lua тоже читает концом строки: хвост за ним не выходит в код.
    config.write(path, { a = 3 }, { comment = 'первая\rвторая\r\nтретья' })

    t.assert_equals(helper.get(path), '-- первая\n-- вторая\n-- третья\nreturn {\n    a = 3,\n}\n')
    t.assert_equals(config.read(path), { a = 3 })
end

g.test_a_directory_that_cannot_be_made_is_the_refusal_of_the_disk = function()
    local blocker = helper.put('bootstrap', 'файл на месте каталога')
    local ok, err = config.write(blocker .. '/cache/config.lua', { a = 1 })

    t.assert_equals(ok, nil)
    t.assert_equals(err.kind, 'exists')
    t.assert_str_contains(tostring(err), ('каталог %s/cache не создан'):format(blocker))
end

g.test_a_failed_replace_keeps_the_old_file = function()
    local path = helper.put('config.lua', 'return { a = 1 }\n')

    helper.with_fio({
        rename = function()
            return false, { errno = errno.EXDEV }
        end,
    })

    local ok, err = config.write(path, { a = 2 })

    t.assert_equals(ok, nil)
    t.assert_equals(err.kind, 'failed')
    t.assert_equals(tostring(err), ('файл %s не заменён: %s'):format(path, errno.strerror(errno.EXDEV)))

    helper.fs._set_source(nil)

    t.assert_equals(config.read(path), { a = 1 })
    t.assert_equals(fio.listdir(fio.dirname(path)), { 'config.lua' }, 'временного файла нет')
end

g.test_a_relative_path_is_written_in_the_working_directory = function()
    local previous = fio.cwd()

    fio.chdir(helper.file(''))

    local ok = config.write('config.lua', { a = 1 })

    fio.chdir(previous)

    t.assert_equals(ok, true)
    t.assert_equals(config.read(helper.file('config.lua')), { a = 1 })
end
