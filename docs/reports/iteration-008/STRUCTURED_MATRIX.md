# Матрица JSON output на исходниках итерации 008

| Точка входа | JSON Object | JSON Schema | Поток | Реальный token constrained decoding |
| --- | --- | --- | --- | --- |
| Веб-чат | Поддерживается | Поддерживается | Буферизованный | Нет |
| OpenAI Chat Completions | `response_format.type=json_object` | `response_format.type=json_schema` + `json_schema` | Буферизованный | Нет |
| OpenAI Responses | `text.format.type=json_object` | `text.format.type=json_schema` с `name/schema/strict` | Буферизованный | Нет |
| Anthropic Messages | Нет отдельного JSON API-контракта здесь | Пока не добавлен | Обычный поток | Нет |

Примечание: обязательное наличие `jsonschema` для проверки именно схемы. Отсутствие пакета => HTTP 400, не подмена проверки только типом `object`. Невалидный результат модели => структурированная ошибка, не успешный ответ. Корневая схема в текущей реализации должна быть объектом. Отдельная поддержка реального constrained decoding — P0.
