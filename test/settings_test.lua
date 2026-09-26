local json = require('json')
local t = require('luatest')

local helper = dofile('test/helper.lua')

local g = t.group('tnt.config.settings')

local config = helper.config

--- Набор, на котором читают все проверки ниже.
---@return TntConfig
local function sample()
    return config.new({
        app = { name = 'demo', port = 8080, ratio = 0.5, debug = false, hosts = { 'a', 'b' } },
        mail = { smtp = { host = 'mx', port = '2525' } },
        role = { bucket_count = '3000', enabled = 'true', hosts = 'x, y', fraction = '0.25', broken = 'восемь' },
        labels = { ['app.kubernetes.io/name'] = 'orders' },
        empty = {},
    })
end

-- ── Слои ─────────────────────────────────────────────────────────────

g.test_layers_merge_deep_and_the_right_one_wins = function()
    local settings = config.new(
        { http = { timeout = 3, retries = 2 }, hosts = { 'a', 'b', 'c' } },
        nil,
        { http = { timeout = 5 }, hosts = { 'd' } },
        { http = { retries = box.NULL } }
    )

    -- Словари сливаются по ключам, список заменяется целиком,
    -- box.NULL значения не затирает, пустой слой пропускается.
    t.assert_equals(settings:all(), { http = { timeout = 5, retries = 2 }, hosts = { 'd' } })
end

g.test_the_set_is_a_snapshot_of_its_layers = function()
    local defaults = { http = { timeout = 3 } }
    local settings = config.new(defaults)

    defaults.http.timeout = 99

    t.assert_equals(settings:get('http.timeout'), 3)

    -- Отданная таблица — копия: правка её у себя набор не меняет.
    local http = settings:get('http')

    http.timeout = 42
    settings:all().http.timeout = 43
    settings:map('http').timeout = 44

    t.assert_equals(settings:get('http.timeout'), 3)
end

g.test_with_puts_layers_over_the_set_and_keeps_the_set = function()
    local base = config.new({ http = { timeout = 3, retries = 2 } })
    local tuned = base:with({ http = { timeout = 1 } }, nil, { extra = true })

    t.assert_equals(tuned:all(), { http = { timeout = 1, retries = 2 }, extra = true })
    t.assert_equals(base:all(), { http = { timeout = 3, retries = 2 } })
end

g.test_without_layers_the_set_is_empty = function()
    t.assert_equals(config.new():all(), {})
    t.assert_equals(config.new():has('app'), false)
end

g.test_a_layer_is_a_map_of_settings = function()
    local ok, err = pcall(config.new, { a = 1 }, 'app')

    t.assert_equals(ok, false)
    t.assert_equals(err, 'слой 2 — словарь настроек, а не строка')

    t.assert_equals(
        helper.blamed(function()
            config.new({ 'a', 'b' })
        end),
        'слой 1 — словарь настроек, а не список'
    )
    t.assert_equals(
        helper.blamed(function()
            config.new(json.decode('[]'))
        end),
        'слой 1 — словарь настроек, а не список'
    )
    t.assert_equals(
        helper.blamed(function()
            config.new({}):with(nil, 7)
        end),
        'слой 2 — словарь настроек, а не число'
    )

    -- Пустая таблица без пометки и разобранный `{}` — словари.
    t.assert_equals(config.new({}, json.decode('{}')):all(), {})
end

g.test_a_ring_in_a_layer_is_refused_at_the_caller = function()
    local ring = { a = 1 }

    ring.self = ring

    t.assert_equals(
        helper.blamed(function()
            config.new(ring)
        end),
        'merge_deep: таблица 1 содержит саму себя — слить кольцо нельзя'
    )
    t.assert_equals(
        helper.blamed(function()
            config.new({ a = 2 }):with(nil, { nested = ring })
        end),
        'merge_deep: таблица 2 содержит саму себя — слить кольцо нельзя'
    )
end

-- ── Чтение по пути ───────────────────────────────────────────────────

g.test_get_reads_by_path_with_a_default = function()
    local settings = sample()

    t.assert_equals(settings:get('app.name'), 'demo')
    t.assert_equals(settings:get({ 'labels', 'app.kubernetes.io/name' }), 'orders')
    t.assert_equals(settings:get('app.hosts.2'), 'b')
    t.assert_equals(settings:get('app.none', 'умолчание'), 'умолчание')
    t.assert_equals(settings:get('app.none'), nil)
    t.assert_equals(settings:get('app.debug', true), false, 'ложь — значение')
    t.assert_equals(settings:get('mail.smtp'), { host = 'mx', port = '2525' })
end

g.test_null_and_nan_are_not_values = function()
    local settings = config.new({ a = box.NULL, b = 0 / 0 })

    t.assert_equals(settings:get('a', 1), 1)
    t.assert_equals(settings:get('b', 2), 2)
    t.assert_equals(settings:has('a'), false)
    t.assert_equals(settings:has('b'), false)
end

g.test_has_tells_whether_a_setting_is_given = function()
    local settings = sample()

    t.assert_equals(settings:has('app.debug'), true)
    t.assert_equals(settings:has('app.name'), true)
    t.assert_equals(settings:has('app.none'), false)
    t.assert_equals(settings:has('none.deeper'), false)
end

g.test_a_bad_path_is_refused_at_the_caller = function()
    local settings = sample()

    t.assert_equals(
        helper.blamed(function()
            settings:get('app..name')
        end),
        'get: путь — непустые звенья через точку, а не «app..name»'
    )
    t.assert_equals(
        helper.blamed(function()
            settings:has('')
        end),
        'get: путь — непустые звенья через точку, а не «»'
    )
    t.assert_equals(
        helper.blamed(function()
            settings:string('')
        end),
        'get: путь — непустые звенья через точку, а не «»'
    )
end

-- ── Чтение с родом ───────────────────────────────────────────────────

g.test_typed_reads_give_the_value_of_its_kind = function()
    local settings = sample()

    t.assert_equals(settings:string('app.name'), 'demo')
    t.assert_equals(settings:integer('app.port'), 8080)
    t.assert_equals(settings:number('app.ratio'), 0.5)
    t.assert_equals(settings:number('app.port'), 8080)
    t.assert_equals(settings:boolean('app.debug'), false)
    t.assert_equals(settings:list('app.hosts'), { 'a', 'b' })
    t.assert_equals(settings:list('empty'), {})
    t.assert_equals(settings:map('mail.smtp'), { host = 'mx', port = '2525' })
    t.assert_equals(settings:map('empty'), {})
end

g.test_64_bit_integers_are_integers_and_numbers = function()
    local settings = config.new({ big = 18446744073709551615ULL, low = -5LL })

    t.assert_equals(settings:integer('big'), 18446744073709551615ULL)
    t.assert_equals(settings:number('low'), -5LL)
end

g.test_a_string_from_the_cluster_configuration_is_read_by_the_env_rules = function()
    local settings = sample()

    -- `{{ context.* }}` подставляет строку, даже если в окружении число.
    t.assert_equals(settings:integer('role.bucket_count'), 3000)
    t.assert_equals(settings:integer('mail.smtp.port'), 2525)
    t.assert_equals(settings:number('role.fraction'), 0.25)
    t.assert_equals(settings:boolean('role.enabled'), true)
    t.assert_equals(settings:list('role.hosts'), { 'x', 'y' })
end

g.test_without_a_default_a_typed_read_requires_the_setting = function()
    local settings = sample()

    t.assert_error_msg_equals('настройка app.none не задана', settings.string, settings, 'app.none')
    t.assert_error_msg_equals(
        'настройка labels.app.kubernetes.io/none не задана',
        settings.integer,
        settings,
        { 'labels', 'app.kubernetes.io/none' }
    )
end

g.test_with_a_default_a_typed_read_does_not = function()
    local settings = sample()

    t.assert_equals(settings:string('app.none', 'x'), 'x')
    t.assert_equals(settings:integer('app.none', 7), 7)
    t.assert_equals(settings:boolean('app.none', false), false)
    t.assert_equals(settings:list('app.none', { 'z' }), { 'z' })
    t.assert_equals(settings:map('app.none', { z = 1 }), { z = 1 })

    -- Умолчание nil — тоже умолчание: настройка необязательна.
    t.assert_equals(settings:string('app.none', nil), nil)
    t.assert_equals(settings:map('app.none', nil), nil)
end

g.test_a_value_of_another_kind_is_refused_with_the_path_and_without_the_value = function()
    local settings = sample()

    local cases = {
        { 'string', 'app.port', 'настройка app.port — строка, а не число' },
        {
            'integer',
            'app.ratio',
            'настройка app.ratio — целое число, а не нецелое число',
        },
        {
            'integer',
            'app.name',
            'настройка app.name — целое число, а строка им не читается',
        },
        {
            'integer',
            'role.fraction',
            'настройка role.fraction — целое число, а строка им не читается',
        },
        {
            'number',
            'role.broken',
            'настройка role.broken — число, а строка им не читается',
        },
        {
            'number',
            'app.debug',
            'настройка app.debug — число, а не логическое значение',
        },
        {
            'boolean',
            'app.port',
            'настройка app.port — логическое значение, а не число',
        },
        {
            'boolean',
            'app.name',
            'настройка app.name — логическое значение, а строка им не читается',
        },
        { 'list', 'mail.smtp', 'настройка mail.smtp — список, а не словарь' },
        { 'list', 'app.port', 'настройка app.port — список, а не число' },
        { 'map', 'app.hosts', 'настройка app.hosts — словарь, а не список' },
        { 'map', 'app.name', 'настройка app.name — словарь, а не строка' },
        { 'string', 'mail', 'настройка mail — строка, а не словарь' },
    }

    for _, case in ipairs(cases) do
        local kind, path, message = unpack(case)

        t.assert_error_msg_equals(message, settings[kind], settings, path)
    end
end

g.test_infinity_is_a_number_but_not_an_integer = function()
    local settings = config.new({ far = math.huge })

    t.assert_equals(settings:number('far'), math.huge)
    t.assert_error_msg_equals(
        'настройка far — целое число, а не нецелое число',
        settings.integer,
        settings,
        'far'
    )
end

g.test_a_parsed_map_is_not_a_list_and_a_parsed_list_is_not_a_map = function()
    local settings = config.new({ map = json.decode('{}'), list = json.decode('[]') })

    t.assert_equals(
        json.encode(settings:map('map')),
        '{}',
        'пометка вида не теряется в копии'
    )
    t.assert_equals(json.encode(settings:list('list')), '[]')
    t.assert_error_msg_equals(
        'настройка map — список, а не словарь',
        settings.list,
        settings,
        'map'
    )
    t.assert_error_msg_equals(
        'настройка list — словарь, а не список',
        settings.map,
        settings,
        'list'
    )
end

g.test_a_default_of_another_kind_is_refused_at_the_caller = function()
    local settings = sample()

    t.assert_equals(
        helper.blamed(function()
            settings:integer('app.port', helper.wrong('8080'))
        end),
        'умолчание app.port — целое число, а не строка'
    )
    t.assert_equals(
        helper.blamed(function()
            settings:boolean('app.none', helper.wrong(1))
        end),
        'умолчание app.none — логическое значение, а не число'
    )
    t.assert_equals(
        helper.blamed(function()
            settings:map({ 'a', 'b' }, helper.wrong({ 1 }))
        end),
        'умолчание a.b — словарь, а не список'
    )
end
