--- Запись настроек файлом данных Lua: собранное заранее.
---
--- Файл пишется так, чтобы читался обратно тем же и ничем иным:
---
--- * число — кратчайшей записью, которая читается тем же числом:
---   `%.14g` теряет знаки у `2^53` и у `0.1 + 0.2`, и тогда пишется
---   `%.17g`; бесконечность и NaN — `1/0`, `-1/0` и `0/0`, потому что
---   `inf` и `nan` в Lua — имена глобалов, и в пустом окружении они пусты;
--- * 64-битное целое — литералом `LL`/`ULL`: его разбирает сам LuaJIT;
--- * ключ-имя — голым, а слово Lua (`end`, `nil`, `goto`…) и прочие
---   строки — в скобках: `{ end = 1 }` файла не прочитал бы никто;
--- * ключи по порядку — числа по возрастанию, затем строки: файл
---   не меняется от прогона к прогону, и разница двух сборок видна глазом;
--- * `box.NULL` под ключом-строкой не пишется — он и значит «не задано»;
---   на месте в списке он оставил бы дыру, и это отказ.
---
--- Функция, объект Tarantool, ключ не строкой и не числом, кольцо — ошибка
--- программиста: настройки обязаны быть данными.
---
--- Подменяет файл `fs.replace`: читающий видит старое либо новое, но не
--- половину, а сорвавшаяся запись оставляет прежний файл целым. Права —
--- `0600`: в собранных настройках тайны лежат открытым текстом.

local fio = require('fio')

local fs = require('tnt.fs')
local must = require('tnt.must')

local value_of = require('tnt.config.value')

--- Тип значения по-русски — тот же, что в отказах `tnt-must`.
local kind_of = require('tnt.must.fail').kind

--- Бросок без места: место ставит тот, кто позвал запись.
local raise = require('tnt.must.fail').raise

local Module = {}

--- Права файла настроек: только владельцу.
Module.MODE = tonumber('600', 8)

--- Настройки записи.
local OPTIONS = { comment = '?string' }

--- Слова Lua: голым ключом их не записать.
---
--- Таблицей, а не разбором строки: у разбора образцом мутант «ноль и более»
--- добавил бы пустое слово, и отличить его было бы нечем.
---@type table<string, boolean>
local KEYWORDS = {
    ['and'] = true,
    ['break'] = true,
    ['do'] = true,
    ['else'] = true,
    ['elseif'] = true,
    ['end'] = true,
    ['false'] = true,
    ['for'] = true,
    ['function'] = true,
    ['goto'] = true,
    ['if'] = true,
    ['in'] = true,
    ['local'] = true,
    ['nil'] = true,
    ['not'] = true,
    ['or'] = true,
    ['repeat'] = true,
    ['return'] = true,
    ['then'] = true,
    ['true'] = true,
    ['until'] = true,
    ['while'] = true,
}

--- Число записью Lua, которая читается тем же числом.
---@param number number
---@return string
local function number_text(number)
    if number ~= number then
        return '0/0'
    end

    if number == math.huge then
        return '1/0'
    end

    if number == -math.huge then
        return '-1/0'
    end

    local short = ('%.14g'):format(number)

    if tonumber(short) == number then
        return short
    end

    return ('%.17g'):format(number)
end

--- Ключ записью Lua.
---@param key string|number
---@return string
local function key_text(key)
    if type(key) == 'string' and key:match('^[%a_][%w_]*$') and not KEYWORDS[key] then
        return key
    end

    if type(key) == 'string' then
        return ('[%q]'):format(key)
    end

    return ('[%s]'):format(number_text(key))
end

--- Значение записью Lua; объявлено здесь, а описано ниже: таблица
--- и значение зовут друг друга.
---
--- Отказы внутри записи бросаются без места (`fail.raise`): место
--- ставит тот, кто позвал запись, — `encode` либо `write`.
---@type fun(value: any, indent: string, where: string, visiting: table<table, boolean>): string
local encoded

--- Ключи таблицы по порядку: числа по возрастанию, затем строки.
---
--- Ключи раскладываются по двум полкам, и каждую упорядочивает сам Lua:
--- числа и строки он сравнивает без помощи, а «числа раньше строк»
--- задаёт порядок полок.
---@param value table
---@param where string
---@return (string|number)[]
local function ordered_keys(value, where)
    local numbers, names = {}, {}

    for key in pairs(value) do
        local kind = type(key)

        if kind == 'number' then
            table.insert(numbers, key)
        elseif kind == 'string' then
            table.insert(names, key)
        else
            raise(('%s: ключ — строка либо число, а не %s'):format(where, kind_of(key)))
        end
    end

    table.sort(numbers)
    table.sort(names)

    for _, name in ipairs(names) do
        table.insert(numbers, name)
    end

    return numbers
end

--- Таблица записью Lua.
---@param value table
---@param indent string
---@param where string
---@param visiting table<table, boolean> Таблицы на пути от корня: встреча с ними — кольцо
---@return string
local function table_text(value, indent, where, visiting)
    if visiting[value] then
        raise(
            ('%s содержит саму себя — кольцо в файл не записать'):format(where)
        )
    end

    visiting[value] = true

    local lines = {}
    local inner = indent .. '    '

    for _, key in ipairs(ordered_keys(value, where)) do
        local item = value[key]
        local place = where .. '.' .. tostring(key)

        if not value_of.is_null(item) then
            table.insert(lines, ('%s%s = %s,'):format(inner, key_text(key), encoded(item, inner, place, visiting)))
        elseif type(key) == 'number' then
            raise(
                ('%s — box.NULL на месте в списке: дыра прочиталась бы словарём'):format(
                    place
                )
            )
        end
    end

    -- Одна и та же таблица в двух местах — не кольцо: она пишется дважды.
    visiting[value] = nil

    if #lines == 0 then
        return '{}'
    end

    return '{\n' .. table.concat(lines, '\n') .. '\n' .. indent .. '}'
end

--- Значение записью Lua.
---@param value any
---@param indent string
---@param where string Путь значения от корня — для текста отказа
---@param visiting table<table, boolean>
---@return string
encoded = function(value, indent, where, visiting)
    local kind = type(value)

    if kind == 'string' then
        return ('%q'):format(value)
    end

    if kind == 'number' then
        return number_text(value)
    end

    if kind == 'boolean' then
        return tostring(value)
    end

    if kind == 'table' then
        return table_text(value, indent, where, visiting)
    end

    if not value_of.is_integer64(value) then
        raise(
            ('%s — %s, а в файл настроек ложатся только данные'):format(
                where,
                kind_of(value)
            )
        )
    end

    return tostring(value)
end

--- Текст файла: разбор при записи идёт под `pcall`, отказ — вторым ответом.
---@param settings table
---@return string|nil text
---@return string|nil complaint
local function rendered(settings)
    local ok, text = pcall(encoded, settings, '', 'настройки', {})

    if not ok then
        return nil, text
    end

    return 'return ' .. text .. '\n'
end

--- Настройки текстом файла данных Lua: `return { … }`.
---@param settings table
---@return string
function Module.encode(settings)
    must.at(2).table(settings, 'настройки')

    local text, complaint = rendered(settings)

    if text == nil then
        error(complaint, 2)
    end

    return text
end

--- Пишет настройки файлом данных Lua, заводя каталог.
---
--- `opts.comment` — строки шапки файла: каждая уходит комментарием,
--- пустые пропускаются.
--- Отказ диска — пара `nil, err` от `tnt-fs`; настройки не данными —
--- бросок с местом вызывающего.
---@param path string
---@param settings table
---@param opts { comment: string|nil }|nil
---@return true|nil ok
---@return TntFsFailure|nil err
function Module.write(path, settings, opts)
    local caller = must.at(2)

    caller.not_empty(path, 'путь к файлу настроек')
    caller.table(settings, 'настройки')
    caller.optional.options(opts, 'настройки записи', OPTIONS)

    local text, complaint = rendered(settings)

    if text == nil then
        error(complaint, 2)
    end

    local header = {}

    -- Режется по обоим переводам строки: `\r` Lua тоже считает концом
    -- строки, и хвост за ним вышел бы из комментария в код файла.
    for line in ((opts or {}).comment or ''):gmatch('[^\r\n]+') do
        table.insert(header, '-- ' .. line .. '\n')
    end

    local made, err = fs.make_tree(fio.dirname(path))

    if made == nil then
        return nil, err
    end

    return fs.replace(path, table.concat(header) .. text, { mode = Module.MODE })
end

return Module
