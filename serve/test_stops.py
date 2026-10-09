"""Regression tests for incremental stop sequences and all three server endpoints.
Run: python -m unittest serve.test_stops -v
"""
from __future__ import annotations

import json
import unittest
import urllib.error
import urllib.request
from pathlib import Path

from serve.frontend import ChatTemplate
from serve.server import ByteTokenizer, MockEngine, Service, serve
from serve.stops import StopMatcher, validate_stops


class Matching(unittest.TestCase):
    def test_fragment_boundaries_and_unicode(self):
        matcher = StopMatcher(["конец", "###"])
        fragments = ["Нач", "ало ко", "не", "ц и скрытый хвост"]
        out = []
        for frag in fragments:
            safe, stop = matcher.feed(frag)
            out.append(safe)
            if stop:
                break
        self.assertEqual("".join(out), "Начало ")
        self.assertEqual(stop, "конец")
        self.assertEqual(matcher.flush(), "")

    def test_partial_prefix_flushed_at_end_or_content_boundary(self):
        matcher = StopMatcher(["[STOP]"])
        self.assertEqual(matcher.feed("a[ST"), ("a", None))
        self.assertEqual(matcher.flush(), "[ST")
        self.assertEqual(matcher.feed("b"), ("b", None))

    def test_multiple_overlapping_delimiters(self):
        matcher = StopMatcher(["ABCD", "BCD", "END"])
        self.assertEqual(matcher.feed("qAB"), ("q", None))
        self.assertEqual(matcher.feed("CDtail"), ("", "ABCD"))

    def test_no_stop_does_not_buffer(self):
        matcher = StopMatcher([])
        self.assertEqual(matcher.feed("normal"), ("normal", None))

    def test_validation(self):
        self.assertEqual(validate_stops("x"), ["x"])
        self.assertEqual(validate_stops(None), [])
        for bad in ["", [""], ["x", "x"], [10], 3, {}, ["x"] * 17, ["x" * 257]]:
            with self.subTest(value=bad):
                with self.assertRaises(ValueError):
                    validate_stops(bad)


class HttpStops(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        tok = ByteTokenizer()
        cls.engine = MockEngine(tok, "</think>\n\nFirst конецSECRET-TAIL", max_context=4096)
        cls.svc = Service(cls.engine, tok, ChatTemplate(Path(__file__).resolve().parent / "chat_template.jinja"))
        cls.httpd = serve(cls.svc, port=0)
        cls.url = f"http://127.0.0.1:{cls.httpd.server_address[1]}"

    @classmethod
    def tearDownClass(cls):
        cls.httpd.shutdown()
        cls.httpd.server_close()

    def post(self, path, body):
        req = urllib.request.Request(self.url + path, data=json.dumps(body, ensure_ascii=False).encode("utf-8"),
                                     headers={"Content-Type": "application/json", "anthropic-version": "2023-06-01"})
        try:
            with urllib.request.urlopen(req, timeout=15) as resp:
                return resp.status, resp.read().decode("utf-8")
        except urllib.error.HTTPError as exc:
            return exc.code, exc.read().decode("utf-8")

    def test_openai_nonstream_and_stream(self):
        for streaming in (False, True):
            with self.subTest(streaming=streaming):
                status, raw = self.post("/v1/chat/completions", {"model": "m", "messages": [{"role": "user", "content": "hi"}],
                        "max_tokens": 300, "stop": ["конец"], "stream": streaming})
                self.assertEqual(status, 200, raw)
                self.assertNotIn("SECRET-TAIL", raw)
                self.assertNotIn("конец", raw)
                if streaming:
                    chunks = [json.loads(line[6:]) for line in raw.splitlines() if line.startswith("data: {")]
                    self.assertEqual("".join(c["choices"][0]["delta"].get("content", "") for c in chunks), "First ")
                    self.assertEqual(chunks[-1]["choices"][0]["finish_reason"], "stop")
                else:
                    result = json.loads(raw)
                    self.assertEqual(result["choices"][0]["message"]["content"], "First ")
                    self.assertEqual(result["choices"][0]["finish_reason"], "stop")

    def test_anthropic_nonstream_and_stream(self):
        for streaming in (False, True):
            status, raw = self.post("/v1/messages", {"model": "m", "messages": [{"role": "user", "content": "hi"}],
                         "max_tokens": 300, "stop_sequences": ["конец"], "stream": streaming})
            self.assertEqual(status, 200, raw)
            self.assertNotIn("SECRET-TAIL", raw)
            if streaming:
                events = [json.loads(line[6:]) for line in raw.splitlines() if line.startswith("data: {")]
                deltas = [e["delta"].get("text", "") for e in events if e.get("type") == "content_block_delta"]
                self.assertEqual("".join(deltas), "First ")
                self.assertEqual(events[-2]["delta"]["stop_reason"], "stop_sequence")
                self.assertEqual(events[-2]["delta"]["stop_sequence"], "конец")
            else:
                result = json.loads(raw)
                self.assertEqual(result["content"][-1]["text"], "First ")
                self.assertEqual(result["stop_reason"], "stop_sequence")
                self.assertEqual(result["stop_sequence"], "конец")

    def test_responses_nonstream(self):
        status, raw = self.post("/v1/responses", {"model": "m", "input": "hi", "max_output_tokens": 300,
                                                         "stop": ["конец"]})
        self.assertEqual(status, 200, raw)
        self.assertNotIn("конец", raw)
        self.assertNotIn("SECRET-TAIL", raw)
        self.assertIn("First ", raw)

    def test_responses_stream(self):
        status, raw = self.post("/v1/responses", {"model": "m", "input": "hi", "max_output_tokens": 300,
                                                      "stop": ["конец"], "stream": True})
        self.assertEqual(status, 200, raw)
        events = [json.loads(line[6:]) for line in raw.splitlines() if line.startswith("data: {")]
        content = "".join(e["delta"] for e in events if e.get("type") == "response.output_text.delta")
        self.assertEqual(content, "First ")
        self.assertNotIn("SECRET-TAIL", raw)

    def test_shared_stop_and_request_override(self):
        try:
            self.svc.set_shared({"stop": ["конец"]})
            status, raw = self.post("/v1/chat/completions", {"model": "m", "messages": [{"role": "user", "content": "hi"}]})
            self.assertEqual(status, 200, raw)
            self.assertEqual(json.loads(raw)["choices"][0]["message"]["content"], "First ")
            # A request with an explicit empty list deliberately disables the shared default.
            status, raw = self.post("/v1/chat/completions", {"model": "m", "messages": [{"role": "user", "content": "hi"}],
                                                                  "stop": []})
            self.assertEqual(status, 200, raw)
            self.assertIn("SECRET-TAIL", json.loads(raw)["choices"][0]["message"]["content"])
            status, raw = self.post("/v1/responses", {"model": "m", "input": "hi", "max_output_tokens": 300})
            self.assertEqual(status, 200, raw)
            self.assertNotIn("SECRET-TAIL", raw)
        finally:
            self.svc.set_shared(None)

    def test_invalid_requests_before_streaming(self):
        for path, req in [
            ("/v1/chat/completions", {"messages": [{"role": "user", "content": "hi"}], "stop": [""]}),
            ("/v1/messages", {"messages": [{"role": "user", "content": "hi"}], "stop_sequences": ["", "a"]}),
            ("/v1/responses", {"input": "hi", "stop": [""]}),
        ]:
            status, raw = self.post(path, {"model": "m", "stream": True, "max_tokens": 300, **req})
            self.assertEqual(status, 400, (path, raw))
