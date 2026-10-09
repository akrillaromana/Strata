"""Изолированная проверка браузерного редактора; не подключается к настоящему серверу.

Запуск: python serve/test_system_browser.py
Требует Playwright Python и Chromium. Системные файлы пользователя не изменяет.
"""
from pathlib import Path
import re
import shutil
from playwright.sync_api import sync_playwright

WEB = Path(__file__).resolve().parent / "web"
html = (WEB / "index.html").read_text(encoding="utf-8")
for filename in ("presets.js", "system_prompts.js", "app.js"):
    html = html.replace(f'<script src="web/{filename}"></script>', "")
html = re.sub(r'<script id="strata-rb-v4-script">.*?</script>', '', html, flags=re.S)

with sync_playwright() as p:
    browser = p.chromium.launch(executable_path=shutil.which("chromium") or None, headless=True,
                                args=["--no-sandbox"])
    try:
        page = browser.new_page(viewport={"width": 375, "height": 812}, accept_downloads=True)
        errors = []
        page.on("pageerror", lambda error: errors.append(str(error)))
        page.goto("about:blank")
        page.evaluate("""() => {
            const stored = {};
            Object.defineProperty(window, 'localStorage', {configurable: true, value: {
                getItem: k => stored[k] ?? null, setItem: (k,v) => {stored[k] = String(v)},
                removeItem: k => {delete stored[k]}
            }});
            Object.defineProperty(document, 'cookie', {configurable: true, get: () => '', set: () => {}});
            history.replaceState = () => {};
            window.confirm = () => true;
            window.fetch = async (url, opts) => {
                if (String(url).includes('v1/chat/completions')) {
                    window.lastChatBody = JSON.parse(opts.body);
                    const bytes = new TextEncoder().encode('data: [DONE]\\n\\n');
                    return {ok: true, status: 200, body: new ReadableStream({start(c) {c.enqueue(bytes); c.close();}})};
                }
                if (url === 'health') return {ok: true, json: async () => ({model: 'mock', images: false, max_context: 262144})};
                return {ok: false, status: 503, json: async () => ({error: {message: 'offline'}})};
            };
        }""")
        page.set_content(html, wait_until="domcontentloaded")
        for css in ("tokens.css", "components.css", "app.css"):
            page.add_style_tag(content=(WEB / css).read_text(encoding="utf-8"))
        for source in ("presets.js", "system_prompts.js", "app.js"):
            page.add_script_tag(content=(WEB / source).read_text(encoding="utf-8"))
        assert not errors, errors
        page.locator("#sampling-btn").click()
        page.locator("#system-panel > summary").click()
        page.locator("#system-text").fill("Respond in Russian only")
        page.locator("#system-enabled").check()
        page.locator("#system-priority").select_option("system")
        page.locator("#system-preset-name").fill("Русский")
        page.locator("#system-save").click()
        assert page.locator("#system-preset-select option").count() == 2
        page.locator("#system-text").fill("Unsaved draft")
        page.locator("#system-preset-select").select_option("Русский")
        page.locator("#system-load").click()
        assert page.locator("#system-text").input_value() == "Respond in Russian only"
        # Save and load do not activate the new text.
        assert page.evaluate('localStorage.getItem("strata.activeSystemInstructionV1")') is None
        page.locator("#system-apply").click()
        page.locator("#drawer-close").click()
        page.locator("#input").fill("Hello")
        page.locator("#send-btn").click()
        page.wait_for_function("!!window.lastChatBody")
        body = page.evaluate("window.lastChatBody")
        assert body["messages"][0] == {"role": "system", "content": "Respond in Russian only"}, body
        assert body["messages"][1] == {"role": "user", "content": "Hello"}, body
        page.locator("#sampling-btn").click()
        page.locator("#system-priority").select_option("user")
        page.locator("#system-apply").click()
        assert page.evaluate('JSON.parse(localStorage.getItem("strata.activeSystemInstructionV1")).priority') == "user"
        assert not errors, errors
        assert not page.evaluate("document.documentElement.scrollWidth > innerWidth"), "mobile horizontal overflow"
        print("[OK] Chromium: templates, drafts, Apply, system priority, HTTP payload, 375px viewport")
    finally:
        browser.close()
