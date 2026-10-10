"""Isolated browser-only verification of the JSON output editor (no model and no GPU)."""
from pathlib import Path
import re
import shutil
from playwright.sync_api import sync_playwright

WEB = Path(__file__).resolve().parent / "web"
html = (WEB / "index.html").read_text(encoding="utf-8")
SCRIPTS = ("presets.js", "structured_output.js", "system_prompts.js", "chat_sessions.js", "app.js")
for filename in SCRIPTS:
    html = html.replace(f'<script src="web/{filename}"></script>', "")
html = re.sub(r'<script id="strata-rb-v4-script">.*?</script>', "", html, flags=re.S)

with sync_playwright() as p:
    browser = p.chromium.launch(executable_path=shutil.which("chromium") or None,
                                headless=True, args=["--no-sandbox"])
    try:
        page = browser.new_page(viewport={"width": 375, "height": 812})
        errors = []
        page.on("pageerror", lambda e: errors.append(str(e)))
        page.goto("about:blank")
        page.evaluate("""() => {
            const values = {};
            window.pendingBodies = [];
            Object.defineProperty(window, 'localStorage', {configurable:true, value: {
                getItem: k => values[k] ?? null, setItem: (k,v) => {values[k] = String(v);},
                removeItem: k => {delete values[k];}
            }});
            history.replaceState = () => {};
            window.confirm = () => true;
            window.fetch = async (url, opts) => {
                if (String(url).includes('v1/chat/completions')) {
                    window.pendingBodies.push(JSON.parse(opts.body));
                    const bytes = new TextEncoder().encode('data: [DONE]\\n\\n');
                    return {ok:true, status:200, body:new ReadableStream({start(c){c.enqueue(bytes); c.close();}})};
                }
                if (url === 'health') return {ok:true, json:async () => ({model:'mock',images:false,max_context:16384})};
                return {ok:false, status:503, json:async () => ({error:{message:'offline'}})};
            };
        }""")
        page.set_content(html, wait_until="domcontentloaded")
        for css in ("tokens.css", "components.css", "app.css"):
            page.add_style_tag(content=(WEB / css).read_text(encoding="utf-8"))
        for script in SCRIPTS:
            page.add_script_tag(content=(WEB / script).read_text(encoding="utf-8"))
        assert not errors, errors
        page.locator("#sampling-btn").click()
        page.locator("#s-format").select_option("json_schema")
        page.locator("#s-schema-name").fill("answer")
        schema = '{"type":"object","properties":{"answer":{"type":"string"}},"required":["answer"],"additionalProperties":false}'
        page.locator("#s-schema-text").fill(schema)
        page.locator("#preset-name").fill("JSON answers")
        page.locator("#preset-save").click()
        doc = page.evaluate('JSON.parse(localStorage.getItem("strata.samplingPresetsV1"))')
        assert doc["version"] == 3 and doc["presets"][0]["settings"]["format"] == "json_schema"
        page.locator("#s-apply").click()
        page.locator("#input").fill("Return an answer")
        page.locator("#send-btn").click()
        page.wait_for_function("window.pendingBodies.length === 1")
        body = page.evaluate("window.pendingBodies[0]")
        assert body["response_format"]["json_schema"]["schema"]["properties"]["answer"]["type"] == "string"
        assert body["response_format"]["json_schema"]["strict"] is True
        assert "strata_mcp" not in body
        page.locator("#sampling-btn").click()
        page.locator("#s-format").select_option("text")
        page.locator("#s-apply").click()
        page.locator("#input").fill("Return plain text")
        page.locator("#send-btn").click()
        page.wait_for_function("window.pendingBodies.length === 2")
        assert "response_format" not in page.evaluate("window.pendingBodies[1]")
        assert not page.evaluate("document.documentElement.scrollWidth > innerWidth"), "horizontal overflow at 375px"
        assert not errors, errors
        print("[OK] Chromium: JSON schema save/apply, chat payload, text fallback, 375px viewport")
    finally:
        browser.close()
