--- Отказ чтения настроек: таблица с родом, которая читается и как строка.
---
--- Отказ диска приходит от `tnt-fs` как есть — с его родами (`missing`,
--- `denied`, `failed`…) и полями. Свой род у пакета один, `invalid`: файл
--- прочитан, а настроек в нём нет — он не разбирается, пуст, несёт код
--- вместо данных или отдаёт не словарь. Вид у отказа тот же, что у отказа
--- диска: поля `kind`, `message`, `path`, а строкой, в склейке и в JSON
--- он — свой текст. Вызывающему так не нужно помнить, чей это отказ:
--- решает он по роду.

local Module = {}

--- Файл прочитан, а настроек в нём нет.
Module.INVALID = 'invalid'

---@class TntConfigFailure Отказ разбора файла настроек
---@field kind string Род: `invalid`
---@field message string Что не удалось и почему — его и отдаёт `tostring`
---@field path string Файл, о котором шла речь

--- Поведение отказа: строкой, в JSON и в склейке он — свой текст.
local Failure = {}

--- Отказ разбора: файл прочитан, а настроек в нём нет.
---@param path string Файл настроек
---@param reason string Почему, словами
---@return TntConfigFailure
function Module.invalid(path, reason)
    return setmetatable({
        kind = Module.INVALID,
        path = path,
        message = ('файл настроек %s не разобран: %s'):format(path, reason),
    }, Failure)
end

--- Текст отказа: его отдают `tostring` и `json.encode`.
---@return string
function Failure:__tostring()
    return self.message
end

Failure.__serialize = Failure.__tostring

--- Склейка со строкой с любой стороны: `'причина: ' .. err`.
---@param left any
---@param right any
---@return string
function Failure.__concat(left, right)
    return tostring(left) .. tostring(right)
end

return Module
