--- Что за значение лежит в настройках: пустота, 64-битное целое, список.
---
--- Три вопроса задают все модули пакета, и ответ на каждый должен быть
--- одним: чтение файла, запись и чтение по пути, разойдясь, пропустили бы
--- в одном месте то, что другое отвергает.

local ffi = require('ffi')

local collection = require('tnt.collection')

--- Тип значения по-русски — тот же, что в отказах `tnt-must`.
local kind_of = require('tnt.must.fail').kind

local Module = {}

--- `box.NULL`: так приходит `null` из YAML и JSON — и значит «не задано».
---@param value any
---@return boolean
function Module.is_null(value)
    return type(value) == 'cdata' and value == nil
end

--- 64-битное целое: так YAML и JSON отдают число за пределом 2^53.
---@param value any
---@return boolean
function Module.is_integer64(value)
    return ffi.istype('int64_t', value) or ffi.istype('uint64_t', value)
end

--- Список, а не словарь: помеченный как список либо с ключами 1..n.
---
--- Пустая таблица без пометки — не список: из кода `{}` пишут
--- и на месте словаря. А разобранный `[]` помечен, и он список: слитый
--- поверх словаря, он заменил бы его целиком, а не добавил бы ничего.
---@param value table
---@return boolean
function Module.is_list(value)
    return collection.is_array(value) and (next(value) ~= nil or getmetatable(value) ~= nil)
end

--- Вид значения словами: таблица — список либо словарь.
---@param value any
---@return string
function Module.described(value)
    if type(value) ~= 'table' then
        return kind_of(value)
    end

    if Module.is_list(value) then
        return 'список'
    end

    return 'словарь'
end

return Module
