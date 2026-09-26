# tnt-config

Настройки приложения одним набором: слои, слитые вглубь (умолчания,
файлы, раздел конфигурации кластера), чтение по пути с умолчанием,
чтение с родом и файлы настроек — YAML, JSON и данные Lua, в том числе
собранные заранее.

```lua
local config = require('tnt.config')

local settings = config.new(defaults, config.read('config/site.yaml'), role_cfg)   -- правее — главнее

settings:get('mail.host', 'localhost')   -- значение либо умолчание
settings:integer('mail.port')            -- обязательное целое; строка '2525' из context — 2525
settings:boolean('mail.tls', false)      -- необязательное логическое

config.read('config/none.yaml')                         --> nil, err.kind == 'missing'
config.write('bootstrap/cache/config.lua', sections)    --> true: подмена целиком, права 0600
```

Зависимости: [tnt-collection](https://github.com/tnt-skein/tnt-collection),
[tnt-fs](https://github.com/tnt-skein/tnt-fs),
[tnt-env](https://github.com/tnt-skein/tnt-env),
[tnt-must](https://github.com/tnt-skein/tnt-must).

## Зачем

- **Слияние по одним правилам.** Словари — по ключам, списки заменяются
  целиком, `null` значения не затирает; набор — снимок, и таблица,
  отданная чтением, — копия.
- **Отказ называет настройку.** `настройка mail.port не задана`,
  `настройка app.hosts — словарь, а не список` — вместо «attempt to index
  a nil value»; значения в тексте нет, среди настроек лежат пароли.
- **Граница с конфигурацией кластера.** Конфигурацию кластера читает
  Tarantool, пакет её не трогает; раздел роли кладут последним слоем,
  а строку, подставленную из `{{ context.* }}`, чтение с родом приводит
  по правилам `tnt-env`.
- **Файлы без ловушек.** Пустой файл и код вместо данных — отказ, а не
  пустые настройки; файл Lua грузится без байт-кода и без глобалов.
  Записанное читается обратно тем же: точные числа, слова Lua ключами,
  подмена файла целиком и права `0600`.

## Установка

```sh
tt rocks install tnt-config --server=https://tnt-skein.github.io/rocks
```

Или из исходников:

```sh
git clone https://github.com/tnt-skein/tnt-config.git
cd tnt-config && tt rocks make --server=https://tnt-skein.github.io/rocks
```

## Как пользоваться

| Вызов | Что делает |
|---|---|
| `config.new(...)` | набор из слоёв; правее — главнее, пустой слой пропускается |
| `settings:get(path, default)` | значение по пути либо умолчание; таблица — копией |
| `settings:has(path)` | задана ли настройка |
| `settings:string`, `integer`, `number`, `boolean`, `list`, `map` `(path, default)` | значение рода; без умолчания — обязательное |
| `settings:all()` | все настройки копией |
| `settings:with(...)` | новый набор: этот и слои поверх него |
| `config.read(path)` | файл настроек `.yaml`, `.yml`, `.json` либо `.lua`; отказ — пара |
| `config.write(path, settings, opts)` | файл данных Lua: каталог заводится, файл подменяется целиком, права `0600` |
| `config.encode(settings)` | текст такого файла: `return { … }` |

Путь — звенья через точку либо список звеньев, когда в ключе есть точка.
Строку, подставленную в конфигурацию кластера из `{{ context.* }}`,
чтение с родом приводит само, а отказ называет путь и не показывает
значения:

```lua
local role = config.new({ role = { bucket_count = '3000', hosts = 'r1, r2' } })

role:integer('role.bucket_count')   --> 3000
role:list('role.hosts')             --> { 'r1', 'r2' }
role:integer('role.workers')        --> бросок: настройка role.workers не задана
```

## Проверки

```sh
make deps          # luatest, luacheck, luacov, cluacov и зависимости пакета в .rocks
make check         # форматирование, линт, проверки, покрытие с порогом 100 %
make mutants-all   # мутационное тестирование утилитой tnt-mutants из PATH, порог 100 % убитых
```

Проверок — 45; покрытие строк — 100 %, убитых мутантов — 100 %
(285 мутантов в пяти модулях). Файлы проверки пишут и читают на настоящем
диске, в своём временном каталоге.

## Документ

Полное описание с обоснованием решений: [docs/config.md](docs/config.md).

## Лицензия

MIT.
