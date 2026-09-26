--- Общие средства проверок настроек приложения.
---
--- Файлы проверки пишут и читают на настоящем диске, в своём временном
--- каталоге: пакет читает и подменяет файлы через `tnt-fs`, и двойник
--- диска проверял бы, что мы правильно разговариваем сами с собой.
--- Там, где исправный диск отказа не даст, подменяется `fio` у `tnt-fs`.
---
--- Исходники грузятся с диска, а не через `require`: у Tarantool свой
--- загрузчик `.rocks`, он идёт раньше `package.path` и подсунул бы
--- установленную копию пакета, если она есть. Проверки тогда шли бы
--- против вчерашнего кода, а покрытие считалось бы по нему. Поэтому
--- файлы читаются сами, в порядке зависимостей, и кладутся
--- в `package.loaded` под именами модулей: `require` изнутри пакета
--- находит их первыми. Зависимости — `tnt-collection`, `tnt-fs`, `tnt-env`
--- и `tnt-must` — берутся установленными из `.rocks` обычным `require`:
--- проверяется этот пакет, а не они.

local fio = require('fio')
local t = require('luatest')

local helper = {}

--- Модули пакета в порядке зависимостей.
helper.MODULES = {
    { name = 'tnt.config.failure', path = 'tnt/config/failure.lua' },
    { name = 'tnt.config.value', path = 'tnt/config/value.lua' },
    { name = 'tnt.config.reader', path = 'tnt/config/reader.lua' },
    { name = 'tnt.config.writer', path = 'tnt/config/writer.lua' },
    { name = 'tnt.config.settings', path = 'tnt/config/settings.lua' },
    { name = 'tnt.config', path = 'tnt/config.lua' },
}

--- Части пакета: имя модуля → его таблица.
---
--- Собираются при загрузке этого помощника, то есть по разу на каждый файл
--- проверок, который его берёт, — а не перед каждой проверкой: состояния
--- у пакета нет, а подмену `fio` у `tnt-fs` проверки снимают сами.
---@type table<string, any>
local PARTS = {}

for _, module in ipairs(helper.MODULES) do
    local chunk, failure = loadfile(fio.abspath(module.path))

    if chunk == nil then
        error(('исходник %s не читается: %s'):format(module.name, tostring(failure)))
    end

    local value = chunk()

    -- Пустое значение в `package.loaded` для `require` значит «не загружен»,
    -- и следующий модуль списка молча взял бы зависимость из `.rocks`.
    if value == nil then
        error(('исходник %s не вернул модуль'):format(module.name))
    end

    package.loaded[module.name] = value
    PARTS[module.name] = value
end

--- Фасад пакета из исходников.
helper.config = PARTS['tnt.config']

--- Файловая система, которой пользуется пакет: ей проверки подменяют `fio`.
helper.fs = require('tnt.fs')

--- Каталог действующей проверки.
---@type string
local root

--- Группа проверок, у каждой из которых свой каталог: заводится перед
--- проверкой и сносится после неё вместе с подменой `fio`.
---@param name string
---@return table
function helper.group(name)
    local g = t.group(name)

    g.before_each(function()
        root = fio.tempdir()
    end)

    g.after_each(function()
        helper.fs._set_source(nil)
        fio.rmtree(root)
    end)

    return g
end

--- Путь внутри каталога действующей проверки.
---@param name string
---@return string
function helper.file(name)
    return fio.pathjoin(root, name)
end

--- Кладёт файл настоящим `fio`, мимо пакета, заводя каталог.
---@param name string Путь от каталога проверки
---@param content string
---@return string path
function helper.put(name, content)
    local path = helper.file(name)

    fio.mktree(fio.dirname(path))

    local file = fio.open(path, { 'O_WRONLY', 'O_CREAT', 'O_TRUNC' }, tonumber('644', 8))

    file:write(content)
    file:close()

    return path
end

--- Читает файл настоящим `fio`, мимо пакета.
---@param path string
---@return string
function helper.get(path)
    local file = fio.open(path, { 'O_RDONLY' })
    local content = file:read()

    file:close()

    return content
end

--- Подменяет в `fio` у `tnt-fs` названные действия; прочее — настоящее.
---@param replaced table<string, function>
function helper.with_fio(replaced)
    helper.fs._set_source({ fio = setmetatable(replaced, { __index = fio }) })
end

--- Негодный аргумент — нарочно.
---
--- Анализатор типов о таком намерении знать не может и справедливо
--- ругается на каждую такую строку.
---@param value any
---@return any
function helper.wrong(value)
    return value
end

--- Текст броска вызова без места — и проверка, что место в нём — файл
--- проверок, откуда позвали, а не строка внутри пакета.
---
--- Сверяется файл, а не номер строки: следующий по стеку кадр лежит уже
--- в другом файле (у luatest либо здесь), так что уровень вины, съехавший
--- на кадр в любую сторону, проверка видит, а переформатирование
--- проверок номера строк не ломает.
---@param call fun()
---@return string|nil
function helper.blamed(call)
    local ok, err = pcall(call)

    t.assert_equals(ok, false, 'вызов не бросил')

    local file = (debug.getinfo(2, 'S') --[[@as { short_src: string }]]).short_src
    local place, text = tostring(err):match('^(.-):%d+: (.*)$')

    t.assert_equals(place, file, tostring(err))

    return text
end

return helper
