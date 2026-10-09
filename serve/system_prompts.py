"""Необязательная системная инструкция для всех трёх API Strata.

Без явно заданного system_prompt существующие запросы проходят без изменений.
Политика выбирается администратором через конфигурацию, а не клиентским запросом.
"""

MAX_SYSTEM_PROMPT = 32768
POLICIES = ("client", "server", "merge")


def configured_prompt(cfg):
    """Проверить настройку при запуске, не приводя произвольные значения к строке."""
    prompt = cfg.get("system_prompt", "")
    policy = cfg.get("system_prompt_priority", "client")
    if not isinstance(prompt, str) or len(prompt) > MAX_SYSTEM_PROMPT or "\x00" in prompt:
        raise ValueError("system_prompt must be text of at most 32768 characters without NUL")
    if not isinstance(policy, str) or policy not in POLICIES:
        raise ValueError("system_prompt_priority must be client, server or merge")
    return prompt, policy


def apply_system_prompt(messages, prompt, policy="client"):
    """Один системный префикс; не изменяет объект входного запроса.

    client: при наличии явной системной инструкции клиента сохранить её.
    server: заменить только НАЧАЛЬНЫЕ системные инструкции клиента.
    merge: объединить инструкцию сервера и начальные инструкции клиента в один системный блок.
    Последующие сообщения/вызовы инструментов не переставляются и не изменяются.
    """
    if not prompt:
        return messages
    if policy not in POLICIES:
        raise ValueError("invalid system prompt priority")
    leading = 0
    for msg in messages:
        if msg.get("role") != "system":
            break
        leading += 1
    if policy == "client" and leading:
        return messages
    if policy == "server":
        return [{"role": "system", "content": prompt}, *messages[leading:]]
    if policy == "merge" and leading:
        texts = [msg.get("content", "") for msg in messages[:leading]]
        if not all(isinstance(text, str) for text in texts):
            raise ValueError("system instruction content must be text")
        merged = "\n\n".join([prompt, *[text for text in texts if text]])
        return [{"role": "system", "content": merged}, *messages[leading:]]
    return [{"role": "system", "content": prompt}, *messages]
