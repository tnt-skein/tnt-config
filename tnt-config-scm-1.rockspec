rockspec_format = '3.0'

package = 'tnt-config'
version = 'scm-1'

source = {
    url = 'git+https://github.com/tnt-skein/tnt-config.git',
    branch = 'main',
}

description = {
    summary = 'Настройки приложения: слои, чтение по пути с родом, файлы настроек и собранное заранее',
    detailed = [[
        Набор настроек из слоёв — умолчания, файлы, раздел конфигурации
        кластера, — слитых вглубь: правее главнее, списки заменяются
        целиком, null значения не затирает. Чтение по пути с умолчанием
        и чтение с родом (строка, целое, число, логическое, список,
        словарь): без умолчания настройка обязательна, не того рода —
        отказ с путём и без значения. Строку, подставленную
        в конфигурацию кластера из context, читатель числа
        и логического приводит сам.

        Файлы настроек — YAML, JSON и данные Lua: отказ парой с родом,
        пустой файл и код вместо данных — отказ, а не пустые настройки.
        Собранное заранее пишется файлом данных Lua, который читается
        обратно тем же: точные числа, слова Lua ключами, подмена файла
        атомарно и права 0600.

        Конфигурацию кластера пакет не читает и не пишет — её читает
        Tarantool. Зависит от tnt-collection, tnt-fs, tnt-env и tnt-must.
        Покрытие строк и убитых мутантов — 100 %.
    ]],
    homepage = 'https://github.com/tnt-skein/tnt-config',
    issues_url = 'https://github.com/tnt-skein/tnt-config/issues',
    maintainer = 'tnt-skein',
    license = 'MIT',
    labels = { 'tarantool', 'config', 'settings', 'yaml', 'json' },
}

dependencies = {
    'lua >= 5.1',
    -- Слияние слоёв вглубь, чтение по пути и вид таблицы.
    'tnt-collection',
    -- Чтение файла, запись подменой и заведение каталога.
    'tnt-fs',
    -- Правила приведения строки к числу, логическому и списку.
    'tnt-env',
    -- Проверки аргументов на строке вызывающего и бросок без места.
    'tnt-must',
}

build = {
    type = 'builtin',
    modules = {
        ['tnt.config'] = 'tnt/config.lua',
        ['tnt.config.failure'] = 'tnt/config/failure.lua',
        ['tnt.config.reader'] = 'tnt/config/reader.lua',
        ['tnt.config.settings'] = 'tnt/config/settings.lua',
        ['tnt.config.value'] = 'tnt/config/value.lua',
        ['tnt.config.writer'] = 'tnt/config/writer.lua',
    },
}
