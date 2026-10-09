"""Optional isolated Chromium interaction check for the Sampling stop field.

Run from repository root: python serve/test_stop_browser.py
Requires Playwright Python and an installed Chromium.  Does NOT talk to a live Strata server.
"""
from __future__ import annotations

import re
import shutil
from pathlib import Path

try:
    from playwright.sync_api import sync_playwright
except ImportError as exc:
    raise SystemExit("Не найден Playwright: установите python -m pip install playwright и Chromium") from exc

WEB = Path(__file__).resolve().parent / "web"
html = (WEB / "index.html").read_text(encoding="utf-8")
# The historical inline reasoning-budget widget requires a genuine HTTP origin.  This
# intentionally isolated check tests the native Sampling drawer without that widget.
html = html.replace('<script src="web/presets.js"></script>', "")
html = html.replace('<script src="web/app.js"></script>', "")
html = re.sub(r'<script id="strata-rb-v4-script">.*?</script>', "", html, flags=re.S)

with sync_playwright() as p:
    browser = p.chromium.launch(executable_path=shutil.which("chromium") or None,
                                headless=True, args=["--no-sandbox"])
    try:
        page = browser.new_page(viewport={"width": 375, "height": 812})
        errors: list[str] = []
        page.on("pageerror", lambda exc: errors.append(str(exc)))
        page.goto("about:blank")
        page.evaluate("""() => {
            const values = {};
            Object.defineProperty(window, 'localStorage', { configurable: true,
                value: {getItem: k => values[k] ?? null,
                        setItem: (k, v) => { values[k] = String(v); },
                        removeItem: k => { delete values[k]; }} });
            Object.defineProperty(document, 'cookie', { configurable: true,
                get: () => '', set: () => {} });
            history.replaceState = () => {};
            window.confirm = () => true;
            window.fetch = async () => ({ok: false, status: 503,
                json: async () => ({error: {message: 'offline isolated test'}})});
        }""")
        page.set_content(html, wait_until="domcontentloaded")
        for file in ("presets.js", "app.js"):
            page.add_script_tag(content=(WEB / file).read_text(encoding="utf-8"))
        assert not errors, errors
        page.locator("#sampling-btn").click()
        page.locator("#s-stop").fill("[DONE]\nГотово")
        page.locator("#preset-name").fill("Проверка 004")
        page.locator("#preset-save").click()
        doc = page.evaluate('JSON.parse(localStorage.getItem("strata.samplingPresetsV1"))')
        assert doc["version"] == 2
        assert doc["presets"][0]["settings"]["stop"] == ["[DONE]", "Готово"]
        page.locator("#s-stop").fill("OTHER")
        page.locator("#preset-select").select_option("Проверка 004")
        page.locator("#preset-load").click()
        assert page.locator("#s-stop").input_value() == "[DONE]\nГотово"
        page.locator("#s-apply").click()
        active = page.evaluate('JSON.parse(localStorage.getItem("strata.sampling"))')
        assert active["stop"] == ["[DONE]", "Готово"]
        assert not page.evaluate("document.documentElement.scrollWidth > innerWidth"), "панель шире экрана 375px"
        assert not errors, errors
        print("[OK] Chromium: save/load/apply stop sequences; preset v2; mobile width 375px")
    finally:
        browser.close()
