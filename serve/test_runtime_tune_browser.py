"""Isolated Chromium verification that Web PCIe/MTP controls reach the request and only engine ACK is shown."""
from pathlib import Path
import re
import shutil
from playwright.sync_api import sync_playwright

WEB = Path(__file__).resolve().parent / "web"
html = (WEB / "index.html").read_text(encoding="utf-8")
SCRIPTS = ("presets.js", "structured_output.js", "system_prompts.js", "chat_sessions.js", "runtime_tune.js", "app.js")
for filename in SCRIPTS:
    html = html.replace(f'<script src="web/{filename}"></script>', "")
html = re.sub(r'<script id="strata-rb-v4-script">.*?</script>', "", html, flags=re.S)

with sync_playwright() as p:
    browser = p.chromium.launch(executable_path=shutil.which("chromium") or None, headless=True,
                                args=["--no-sandbox"])
    try:
        page = browser.new_page(viewport={"width": 900, "height": 900})
        errors = []
        page.on("pageerror", lambda e: errors.append(str(e)))
        page.goto("about:blank")
        page.evaluate("""() => {
            const stored = {};
            Object.defineProperty(window, 'localStorage', {configurable: true, value: {
                getItem: k => stored[k] ?? null,
                setItem: (k,v) => {stored[k] = String(v)},
                removeItem: k => {delete stored[k]}
            }});
            Object.defineProperty(document, 'cookie', {configurable: true, get: () => '', set: () => {}});
            history.replaceState = () => {};
            window.confirm = () => true;
            window.chatBodies = [];
            window.fetch = async (url, opts = {}) => {
                const u = String(url);
                if (u === 'health') return {ok:true, status:200, json:async () => ({model:'mock', images:false, max_context:262144})};
                if (u === 'settings') return {ok:true, status:200, json:async () => ({
                    shared:false,
                    defaults:{},
                    model_tune:{pcie_frac:0.0, spec_min_p:0.9},
                    runtime_tune_current:{pcie_frac:0.0, spec_min_p:0.9},
                    runtime_tune_supported:true
                })};
                if (u === 'runtime-tune') {
                    const body = JSON.parse(opts.body);
                    window.runtimeTuneBody = body;
                    return {ok:true, status:200, json:async () => ({
                        status:'applied', pcie_frac:Number(body.set.pcie_frac),
                        spec_min_p:Number(body.set.spec_min_p), pcie_num:Math.round(Number(body.set.pcie_frac) * 256)
                    })};
                }
                if (u === 'mcp') return {ok:true, status:200, json:async () => ({servers:[], tools:0})};
                if (u.includes('v1/chat/completions')) {
                    const body = JSON.parse(opts.body);
                    window.chatBodies.push(body);
                    const ack = {
                        id:'x', object:'chat.completion.chunk', choices:[{index:0, delta:{content:'ok'}, finish_reason:null}],
                        strata_tune:{pcie_frac:0.37, spec_min_p:1.0}, strata_tune_applied:true,
                        timings:{prompt_per_second:123.4, predicted_per_second:15.6, pcie_offloaded_entries:123}
                    };
                    const done = {id:'x', object:'chat.completion.chunk', choices:[{index:0, delta:{}, finish_reason:'stop'}],
                        usage:{completion_tokens:1}, strata_tune:{pcie_frac:0.37, spec_min_p:1.0}, strata_tune_applied:true,
                        timings:{prompt_per_second:123.4, predicted_per_second:15.6, pcie_offloaded_entries:123}};
                    const payload = `data: ${JSON.stringify(ack)}\\n\\ndata: ${JSON.stringify(done)}\\n\\ndata: [DONE]\\n\\n`;
                    const bytes = new TextEncoder().encode(payload);
                    return {ok:true, status:200, body:new ReadableStream({start(c){c.enqueue(bytes); c.close();}})};
                }
                return {ok:false, status:503, json:async () => ({error:{message:'offline'}})};
            };
        }""")
        page.set_content(html, wait_until="domcontentloaded")
        for css in ("tokens.css", "components.css", "app.css"):
            page.add_style_tag(content=(WEB / css).read_text(encoding="utf-8"))
        for source in SCRIPTS:
            page.add_script_tag(content=(WEB / source).read_text(encoding="utf-8"))
        assert not errors, errors

        page.locator("#sampling-btn").click()
        page.wait_for_function("!document.querySelector('#s-pcie-default').disabled")
        assert page.locator("#s-pcie-model").inner_text().startswith("Model: 0")
        assert page.locator("#s-mtp-model").inner_text().startswith("Model: 0.9")

        page.locator("#s-pcie-default").uncheck()
        page.locator("#n-pcie").fill("0.37")
        page.locator("#s-mtp-default").uncheck()
        page.locator("#n-mtp").fill("1.00")
        page.locator("#s-apply").click()
        page.wait_for_function("window.runtimeTuneBody && window.runtimeTuneBody.set.pcie_frac === 0.37")
        applied = page.evaluate("window.runtimeTuneBody")
        assert applied["set"] == {"pcie_frac": 0.37, "spec_min_p": 1}, applied
        page.wait_for_function("document.body.innerText.includes('scheduler 95/256')")

        page.locator("#input").fill("test")
        page.locator("#send-btn").click()
        page.wait_for_function("window.chatBodies.length === 1")
        body = page.evaluate("window.chatBodies[0]")
        assert body["strata_tune"] == {"pcie_frac": 0.37, "spec_min_p": 1}, body
        page.wait_for_function("document.querySelector('#chat').lastElementChild && document.querySelector('#chat').lastElementChild.innerText.includes('PCIe 0.37')")
        text = page.locator("#chat").last.inner_text()
        assert "PCIe 0.37" in text, text
        assert "MTP 1" in text, text
        assert "Decode 15.6 tok/s" in text, text
        assert "PCIe offload 123 entries" in text, text
        assert "runtime tune NOT applied" not in text, text
        assert not errors, errors
        print("[OK] Chromium: Apply performs live TUNE, request carries PCIe/MTP, UI shows engine ACK/offload")
    finally:
        browser.close()
