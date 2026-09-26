--- Настройки приложения: слои, чтение по пути и файлы настроек.
---
---     local config = require('tnt.config')
---
---     local settings = config.new(defaults, file_layer, role_cfg)   -- правее — главнее
---
---     settings:get('mail.host', 'localhost')    -- значение либо умолчание
---     settings:integer('http.port')             -- целое; не задано — отказ
---     settings:boolean('http.debug', false)     -- 'true' из context читается истиной
---
---     local layer, err = config.read('config/site.yaml')         -- nil, err.kind == 'missing'
---     config.write('bootstrap/cache/config.lua', sections)        -- атомарно, права 0600
---
--- Граница с конфигурацией кластера: этот пакет держит настройки
--- приложения — пороги, паузы, переключатели, адреса чужих служб, —
--- а `config.yaml` (или etcd) читает сам Tarantool, и пакет его
--- не читает и в него не пишет. Что приложению нужно оттуда — раздел
--- роли из `roles_cfg`, место узла, — приходит от ядра слоем, и слой
--- этот кладут последним: записанное в кластере сильнее собранного
--- на узле. Строки, подставленные из `{{ context.* }}`, чтение с родом
--- приводит само.
---
--- Зависит от `tnt-collection` (слияние и путь), `tnt-fs` (файлы),
--- `tnt-env` (правила приведения строки) и `tnt-must` (проверки
--- аргументов). Состояния и настроек у пакета нет.

local failure = require('tnt.config.failure')
local reader = require('tnt.config.reader')
local settings = require('tnt.config.settings')
local writer = require('tnt.config.writer')

local Module = {}

--- Род отказа разбора: файл прочитан, а настроек в нём нет.
Module.INVALID = failure.INVALID

--- Права файла, который пишет `write`.
Module.MODE = writer.MODE

Module.new = settings.new
Module.read = reader.read
Module.write = writer.write
Module.encode = writer.encode

return Module
