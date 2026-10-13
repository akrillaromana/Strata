"""Regression: queued generation is cancel-safe and makes SSE progress (#1619).

The real RTX/Windows stability check remains TEST-REQUESTS.ps1 against a running model.
"""
import threading
import http.client
import json
import unittest
from pathlib import Path
from unittest.mock import patch

from serve.frontend import ChatTemplate
from serve.server import ByteTokenizer, MockEngine, Service, serve


class QueueSafety(unittest.TestCase):
    def setUp(self):
        tokenizer = ByteTokenizer()
        self.service = Service(MockEngine(tokenizer, "ok"), tokenizer,
                               ChatTemplate(Path(__file__).parent / "chat_template.jinja"))
        self.patched = patch("serve.server.QUEUE_BEAT_S", 0.02)
        self.patched.start()
        self.addCleanup(self.patched.stop)
        self.assertTrue(self.service.fifo.acquire(timeout=1))
        self.addCleanup(lambda: self.service.fifo.release() if self.service.fifo.locked() else None)

    def queued_request_emits_a_ping(self):
        return self.service.run(self.service.tok.encode("ping"), False, None, 16, {}, threading.Event())

    def test_waiting_request_pings_without_stealing_the_turn(self):
        pending = self.queued_request_emits_a_ping()
        try:
            self.assertEqual(next(pending), ("ping", None))
            self.assertEqual(self.service.status["queued"], 1)
            self.assertTrue(self.service.fifo.locked())
        finally:
            pending.close()
        self.assertEqual(self.service.status["queued"], 0)

    def test_cancelled_request_exits_without_taking_turn(self):
        cancelled = threading.Event()
        pending = self.service.run([123], False, None, 16, {}, cancelled)
        self.assertEqual(next(pending), ("ping", None))
        cancelled.set()
        end = list(pending)
        self.assertEqual([name for name, _ in end], ["done"])
        self.assertEqual(end[0][1]["finish"], "cancel")
        self.assertEqual(self.service.status["queued"], 0)
        self.assertTrue(self.service.fifo.locked())

    def test_http_stream_stays_alive_while_waiting_for_slot(self):
        httpd = serve(self.service, port=0)
        self.addCleanup(httpd.server_close)
        self.addCleanup(httpd.shutdown)
        conn = http.client.HTTPConnection("127.0.0.1", httpd.server_address[1], timeout=10)
        self.addCleanup(conn.close)
        body = json.dumps({"stream": True, "messages": [{"role": "user", "content": "hi"}]})
        conn.request("POST", "/v1/chat/completions", body,
                     {"Content-Type": "application/json"})
        response = conn.getresponse()
        self.assertEqual(response.status, 200)
        observed = b"".join(response.fp.readline() for _ in range(5))
        self.assertIn(b"keep-alive", observed)
        self.assertEqual(self.service.status["queued"], 1)
        self.service.fifo.release()
        rest = response.read()
        self.assertIn(b"[DONE]", rest)
        self.assertEqual(self.service.status["queued"], 0)

    def test_finished_request_releases_lock(self):
        self.service.fifo.release()
        pending = self.service.run(self.service.tok.encode("hi"), False, None, 16,
                                   {}, threading.Event())
        self.assertEqual(list(pending)[-1][0], "done")
        self.assertFalse(self.service.fifo.locked())
        self.assertEqual(self.service.status["queued"], 0)


if __name__ == "__main__":
    unittest.main()
