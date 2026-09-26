--- Чтение файла настроек: YAML, JSON либо данные Lua.
---
--- Формат выбирается расширением: `.yaml` и `.yml`, `.json`, `.lua`.
--- Иное расширение — ошибка программиста: угаданный по содержимому формат
--- однажды угадался бы неверно, а путь пишет код, а не оператор.
---
--- Файл обязан нести словарь настроек и только данные. Пустой файл,
--- `null`, список, функция внутри — отказ `invalid`, а не пустые
--- настройки: оборванный на записи файл, прочитанный как «настроек нет»,
--- поднял бы приложение без единой из них, и молча.
---
--- Файл Lua — данные, а не код: кусок грузится без байт-кода (`'t'`)
--- и с пустым окружением, так что ни `require`, ни `os`, ни иные глобалы
--- ему не видны. Это не песочница — цикл без конца он остановит так же,
--- как и в обычном коде, — но настройки, собранные заранее, ничего
--- не исполняют: что там не данные, то отказ.

local json = require('json')
local yaml = require('yaml')

local fs = require('tnt.fs')
local must = require('tnt.must')

local failure = require('tnt.config.failure')
local value_of = require('tnt.config.value')

--- Тип значения по-русски — тот же, что в отказах `tnt-must`.
local kind_of = require('tnt.must.fail').kind

--- Бросок без места: текст отказа разбора уже называет файл и строку.
local raise = require('tnt.must.fail').raise

local Module = {}

--- Данные Lua: кусок без байт-кода и без глобалов.
---
--- Имя куска — путь с `=`: отказ разбора называет файл и строку в нём,
--- а не «[string "return {…"]».
---@param text string
---@param path string
---@return any
local function lua_data(text, path)
    local chunk, err = load(text, '=' .. path, 't', {})

    if chunk == nil then
        raise(err)
    end

    return chunk()
end

--- Разбор по расширению.
---
--- Обёртки, а не сами `yaml.decode` и `json.decode`: вторым аргументом
--- разбору уходит путь, а у встроенных разборов второй аргумент — свои
--- настройки.
---@type table<string, fun(text: string, path: string): any>
local DECODERS = {
    yaml = function(text)
        return yaml.decode(text)
    end,
    json = function(text)
        return json.decode(text)
    end,
    lua = lua_data,
}

DECODERS.yml = DECODERS.yaml

--- Разбор по окончанию пути; пусто — расширение незнакомо.
---
--- Окончание сверяется целиком, а не вырезается образцом: у образца
--- «знаки до конца» мутанты «ноль и более» и «как можно меньше» дают
--- тот же ответ, и проверить его было бы нечем.
---@param path string
---@return (fun(text: string, path: string): any)|nil
local function decoder_of(path)
    for extension, decode in pairs(DECODERS) do
        if path:sub(-#extension - 1) == '.' .. extension then
            return decode
        end
    end

    return nil
end

--- Роды значений, которые считаются данными.
---@type table<string, boolean>
local DATA = { string = true, number = true, boolean = true }

--- Где лежит значение: путь от корня через точку.
---@param where string|nil Путь родителя; пусто — корень
---@param key string|number
---@return string
local function joined(where, key)
    if where == nil then
        return tostring(key)
    end

    return where .. '.' .. tostring(key)
end

--- Первое, что в значении не данные; пусто — всё данные.
---
--- Таблица, встреченная второй раз, не обходится снова: одна и та же
--- таблица в двух местах — не беда, а кольцо без этого обходилось бы
--- без конца. Слить кольцо откажет `config.new`.
---@param value any
---@param where string|nil
---@param seen table<table, boolean>
---@return string|nil complaint
local function complaint_in(value, where, seen)
    if type(value) == 'table' then
        if seen[value] then
            return nil
        end

        seen[value] = true

        for key, item in pairs(value) do
            local key_kind = type(key)

            if key_kind ~= 'string' and key_kind ~= 'number' then
                return ('%s: ключ — строка либо число, а не %s'):format(
                    where or 'корень',
                    kind_of(key)
                )
            end

            local complaint = complaint_in(item, joined(where, key), seen)

            if complaint ~= nil then
                return complaint
            end
        end

        return nil
    end

    if DATA[type(value)] or value_of.is_null(value) or value_of.is_integer64(value) then
        return nil
    end

    return ('%s — %s, а в файле настроек только данные'):format(where, kind_of(value))
end

--- Что не так с разобранным файлом; пусто — это словарь настроек.
---@param value any
---@return string|nil
local function shape_complaint(value)
    if type(value) ~= 'table' or value_of.is_list(value) then
        return ('в нём не словарь настроек, а %s'):format(value_of.described(value))
    end

    return complaint_in(value, nil, {})
end

--- Читает файл настроек.
---
--- Отказ — пара: диска — отказ `tnt-fs` с его родом (`missing`, `denied`…),
--- разбора — род `invalid`. Бросок — только путь не строкой
--- и незнакомое расширение: это ошибка в коде, а не в файле.
---@param path string Путь к файлу: `.yaml`, `.yml`, `.json` либо `.lua`
---@return table|nil settings
---@return TntFsFailure|TntConfigFailure|nil err
function Module.read(path)
    must.at(2).not_empty(path, 'путь к файлу настроек')

    local decode = decoder_of(path)

    if decode == nil then
        local message = ('файл настроек %s: расширение — .yaml, .yml, .json либо .lua'):format(
            path
        )

        error(message, 2)
    end

    local text, err = fs.read(path)

    if text == nil then
        return nil, err
    end

    local ok, value = pcall(decode, text, path)

    if not ok then
        return nil, failure.invalid(path, tostring(value))
    end

    local complaint = shape_complaint(value)

    if complaint ~= nil then
        return nil, failure.invalid(path, complaint)
    end

    -- Проверено выше: словарь настроек.
    return value --[[@as table]]
end

return Module
