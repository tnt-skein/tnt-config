--- Набор настроек: слои, слитые вглубь, и чтение по пути.
---
--- Слои идут по порядку, правее — главнее: умолчания, файл, раздел
--- конфигурации кластера. Словари сливаются по ключам, списки и прочее
--- заменяются целиком, `box.NULL` значения не затирает (`tnt-collection`,
--- `merge_deep`). Набор — снимок: слои копируются при сборке, а таблица,
--- отданная чтением, — копия, и правка её у себя набор не меняет.
---
--- Чтение с родом (`string`, `integer`, `number`, `boolean`, `list`,
--- `map`) без умолчания требует значения, а с умолчанием — нет; значение
--- не того рода — отказ с путём. Строку читатель числа, логического
--- и списка приводит по правилам `tnt-env`: так приходит значение,
--- подставленное в конфигурацию кластера из `{{ context.* }}`, — строкой,
--- даже если в окружении было число, — и прочесть его обязан тот,
--- кто читает.
---
--- Отказ о настройке бросается без места: текст уходит оператору
--- (в alerts применения либо в терминал сборки) и называет путь, а место
--- в пакете отправило бы искать не туда. Значения в тексте нет: среди
--- настроек лежат пароли, а отличить их по пути пакет не берётся.
--- Негодный аргумент — путь, умолчание не того рода, слой не словарём —
--- ошибка в коде, и отказ о нём показывает на строку вызывающего.

local collection = require('tnt.collection')
local cast = require('tnt.env.cast')

local value_of = require('tnt.config.value')

--- Отказ без места: текст уходит оператору.
local raise = require('tnt.must.fail').raise

local Module = {}

---@class TntConfig Набор настроек: снимок слоёв
---@field values table Слитые слои
---@field string fun(self: TntConfig, path: string|any[], default?: string): string|nil Строка
---@field integer fun(self: TntConfig, path: string|any[], default?: integer): integer|nil Целое число
---@field number fun(self: TntConfig, path: string|any[], default?: number): number|nil Число
---@field boolean fun(self: TntConfig, path: string|any[], default?: boolean): boolean|nil Логическое значение
---@field list fun(self: TntConfig, path: string|any[], default?: any[]): any[]|nil Список
---@field map fun(self: TntConfig, path: string|any[], default?: table): table|nil Словарь
local Settings = {}
Settings.__index = Settings

--- Слои, слитые вглубь, с проверкой, что каждый — словарь.
---
--- Уровень считается как у `error` от публичной функции: 2 — её
--- вызывающий; своя глубина прибавляется здесь.
---@param level integer
---@param base table|nil Уже слитое — у `with`; в номера слоёв не входит
---@param ... table|nil
---@return TntConfig
local function layered(level, base, ...)
    for index = 1, select('#', ...) do
        local layer = select(index, ...)

        if layer ~= nil and (type(layer) ~= 'table' or value_of.is_list(layer)) then
            error(
                ('слой %d — словарь настроек, а не %s'):format(index, value_of.described(layer)),
                level + 1
            )
        end
    end

    -- Слои сливаются отдельно от базы: отказ о кольце называет таблицу
    -- по номеру, и номер обязан быть номером слоя, а не сдвинутым на базу.
    local ok, merged = pcall(collection.merge_deep, ...)

    if not ok then
        error(merged, level + 1)
    end

    if base ~= nil then
        merged = collection.merge_deep(base, merged)
    end

    return setmetatable({ values = merged }, Settings)
end

--- Набор из слоёв; правее — главнее, пустой слой пропускается.
---@param ... table|nil Слои: словари настроек
---@return TntConfig
function Module.new(...)
    local settings = layered(2, nil, ...)

    return settings
end

--- Значение по пути, как оно лежит в наборе.
---@param settings TntConfig
---@param path string|any[]
---@param level integer Как у `error` от публичного метода
---@return any
local function lookup(settings, path, level)
    local ok, value = pcall(collection.get, settings.values, path)

    if not ok then
        error(value, level + 1)
    end

    return value
end

--- Копия таблицы: правка отданного у себя не меняет набор.
---@param value any
---@return any
local function detached(value)
    if type(value) == 'table' then
        return table.deepcopy(value)
    end

    return value
end

--- Значение по пути; нет его — умолчание.
---
--- «Нет» — это и nil, и `box.NULL`, и NaN. Таблица отдаётся копией.
---@param path string|any[] Путь через точку либо список звеньев
---@param default any
---@return any
function Settings:get(path, default)
    local value = lookup(self, path, 2)

    if value == nil then
        return default
    end

    return detached(value)
end

--- Задана ли настройка.
---@param path string|any[]
---@return boolean
function Settings:has(path)
    return lookup(self, path, 2) ~= nil
end

--- Все настройки копией.
---@return table
function Settings:all()
    return table.deepcopy(self.values)
end

--- Новый набор: этот и слои поверх него.
---@param ... table|nil
---@return TntConfig
function Settings:with(...)
    local settings = layered(2, self.values, ...)

    return settings
end

---@class TntConfigKind Род значения при чтении с родом
---@field label string Как род зовётся в отказе
---@field accepts fun(value: any): boolean Годится ли значение как есть
---@field parse (fun(raw: string): any, string|nil)|nil Приведение строки; пусто — строка не приводится

--- Число без дробной части: бесконечность в него не входит.
---@param value any
---@return boolean
local function is_whole(value)
    return type(value) == 'number' and value % 1 == 0
end

--- Рода чтения.
---@type table<string, TntConfigKind>
local KINDS = {
    string = {
        label = 'строка',
        accepts = function(value)
            return type(value) == 'string'
        end,
    },
    integer = {
        label = 'целое число',
        accepts = function(value)
            return is_whole(value) or value_of.is_integer64(value)
        end,
        parse = cast.integer,
    },
    number = {
        label = 'число',
        accepts = function(value)
            return type(value) == 'number' or value_of.is_integer64(value)
        end,
        parse = cast.number,
    },
    boolean = {
        label = 'логическое значение',
        accepts = function(value)
            return type(value) == 'boolean'
        end,
        parse = cast.boolean,
    },
    list = {
        label = 'список',
        accepts = function(value)
            return type(value) == 'table' and collection.is_array(value)
        end,
        parse = cast.list,
    },
    map = {
        label = 'словарь',
        accepts = function(value)
            return type(value) == 'table' and not value_of.is_list(value)
        end,
    },
}

--- Вид значения в отказе: у числа — целое оно или нет.
---@param value any
---@return string
local function shown(value)
    if type(value) == 'number' and not is_whole(value) then
        return 'нецелое число'
    end

    return value_of.described(value)
end

--- Путь словами: список звеньев — через точку, как его и пишут.
---
--- Сюда путь доходит проверенным: звенья списка — строки и числа.
---@param path string|any[]
---@return string
local function path_text(path)
    if type(path) == 'table' then
        local parts = {}

        for index, part in ipairs(path) do
            parts[index] = tostring(part)
        end

        return table.concat(parts, '.')
    end

    return path
end

--- Чтение с родом.
---@param settings TntConfig
---@param kind TntConfigKind
---@param path string|any[]
---@param defaulted boolean Дано ли умолчание, пусть и nil
---@param default any
---@return any
local function typed(settings, kind, path, defaulted, default)
    -- Путь — первым: негодный путь сказал бы о себе и там, где умолчание
    -- не то, и назвать в отказе его было бы нечем.
    local value = lookup(settings, path, 3)
    local named = path_text(path)

    if default ~= nil and not kind.accepts(default) then
        error(('умолчание %s — %s, а не %s'):format(named, kind.label, shown(default)), 3)
    end

    if value == nil then
        if not defaulted then
            raise(('настройка %s не задана'):format(named))
        end

        return default
    end

    if kind.accepts(value) then
        return detached(value)
    end

    if type(value) == 'string' and kind.parse ~= nil then
        local parsed = kind.parse(value)

        if parsed ~= nil then
            return parsed
        end

        raise(('настройка %s — %s, а строка им не читается'):format(named, kind.label))
    end

    raise(('настройка %s — %s, а не %s'):format(named, kind.label, shown(value)))
end

for name, kind in pairs(KINDS) do
    Settings[name] = function(self, path, ...)
        local value = typed(self, kind, path, select('#', ...) > 0, ...)

        return value
    end
end

return Module
