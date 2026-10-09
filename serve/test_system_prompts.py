"""Проверки системных инструкций из всех поддерживаемых протоколов."""

import unittest
import json
import urllib.request
from pathlib import Path

from serve.frontend import anthropic_to_messages, openai_to_messages
from serve.responses import input_messages
from serve.system_prompts import MAX_SYSTEM_PROMPT, apply_system_prompt, configured_prompt
from serve.server import ByteTokenizer, MockEngine, Service, serve
from serve.frontend import ChatTemplate


class Configuration(unittest.TestCase):
    def test_default_does_not_modify_the_request(self):
        original = [{"role": "user", "content": "hello"}]
        self.assertEqual(configured_prompt({}), ("", "client"))
        self.assertIs(apply_system_prompt(original, ""), original)

    def test_config_validation(self):
        self.assertEqual(configured_prompt({"system_prompt": "Hello", "system_prompt_priority": "server"}),
                         ("Hello", "server"))
        for cfg in ({"system_prompt": []}, {"system_prompt": "x" * (MAX_SYSTEM_PROMPT + 1)},
                    {"system_prompt": "x\0"}, {"system_prompt_priority": "other"},
                    {"system_prompt_priority": None}):
            with self.subTest(cfg=str(cfg)[:80]), self.assertRaises(ValueError):
                configured_prompt(cfg)


class Priority(unittest.TestCase):
    def setUp(self):
        self.user = {"role": "user", "content": "Hello"}
        self.explicit = {"role": "system", "content": "Client instruction"}

    def test_client_system_instruction_wins_by_default(self):
        messages = [self.explicit, self.user]
        self.assertIs(apply_system_prompt(messages, "Server", "client"), messages)

    def test_configured_instruction_applies_without_client_system(self):
        messages = [self.user]
        self.assertEqual(apply_system_prompt(messages, "Server"), [
            {"role": "system", "content": "Server"}, self.user])
        self.assertEqual(messages, [self.user])

    def test_server_replaces_only_initial_system(self):
        messages = [self.explicit, self.user, {"role": "tool", "content": "result"}]
        self.assertEqual(apply_system_prompt(messages, "Server", "server"), [
            {"role": "system", "content": "Server"}, *messages[1:]])
        self.assertEqual(messages[0], self.explicit)

    def test_merge_keeps_both_system_instructions_in_order(self):
        messages = [self.explicit, {"role": "system", "content": "Client 2"}, self.user]
        self.assertEqual(apply_system_prompt(messages, "Server", "merge"), [
            {"role": "system", "content": "Server\n\nClient instruction\n\nClient 2"}, self.user])

    def test_late_system_is_not_removed(self):
        messages = [self.user, self.explicit]
        self.assertEqual(apply_system_prompt(messages, "Server", "server"), [
            {"role": "system", "content": "Server"}, *messages])

    def test_invalid_priority_does_not_reach_model(self):
        with self.assertRaises(ValueError):
            apply_system_prompt([self.user], "Configured", "invalid")


class APIConversions(unittest.TestCase):
    def test_openai_client_system(self):
        messages, _, _ = openai_to_messages({"messages": [
            {"role": "developer", "content": "OpenAI developer"},
            {"role": "user", "content": "hi"}]})
        self.assertEqual(messages[0], {"role": "system", "content": "OpenAI developer"})
        self.assertEqual(apply_system_prompt(messages, "Server", "client"), messages)
        self.assertEqual(apply_system_prompt(messages, "Server", "server")[0]["content"], "Server")

    def test_anthropic_system_and_token_count_share_policy(self):
        messages, _, _ = anthropic_to_messages({
            "system": [{"type": "text", "text": "Anthropic system"}],
            "messages": [{"role": "user", "content": "hi"}]})
        self.assertEqual(messages[0], {"role": "system", "content": "Anthropic system"})
        self.assertEqual(apply_system_prompt(messages, "Server", "merge")[0]["content"],
                         "Server\n\nAnthropic system")

    def test_responses_instructions(self):
        messages = input_messages({"instructions": "Responses instruction",
                                   "input": [{"role": "user", "content": "hi"}]})
        self.assertEqual(messages[0]["content"], "Responses instruction")
        self.assertEqual(apply_system_prompt(messages, "Server", "client"), messages)
        self.assertEqual(apply_system_prompt(messages, "Server", "merge")[0]["content"],
                         "Server\n\nResponses instruction")

    def test_all_apis_get_default_without_explicit_instructions(self):
        chat, _, _ = openai_to_messages({"messages": [{"role": "user", "content": "hi"}]})
        anth, _, _ = anthropic_to_messages({"messages": [{"role": "user", "content": "hi"}]})
        resp = input_messages({"input": "hi"})
        for messages in (chat, anth, resp):
            self.assertEqual(apply_system_prompt(messages, "Configured", "client")[0],
                             {"role": "system", "content": "Configured"})


class RealHttpRouting(unittest.TestCase):
    """Проверяет, что HTTP-обработчики вызывают новую политику до сборки токенов."""

    @classmethod
    def setUpClass(cls):
        tok = ByteTokenizer()
        cls.svc = Service(MockEngine(tok, "</think>\n\nOK", max_context=8192), tok,
                          ChatTemplate(Path(__file__).with_name("chat_template.jinja")))
        cls.httpd = serve(cls.svc, port=0)
        cls.base = "http://127.0.0.1:%s" % cls.httpd.server_address[1]
        cls.original_encode = cls.svc.encode_prompt
        cls.captured = []

        def capture(messages, tools, kwargs):
            cls.captured.append(messages)
            return cls.original_encode(messages, tools, kwargs)

        cls.svc.encode_prompt = capture

    @classmethod
    def tearDownClass(cls):
        cls.httpd.shutdown()
        cls.httpd.server_close()

    def post(self, path, body):
        req = urllib.request.Request(self.base + path, data=json.dumps(body).encode(),
                                     headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=15) as resp:
            self.assertEqual(resp.status, 200)
            return json.loads(resp.read())

    def test_all_api_routes_and_policies(self):
        self.svc.system_prompt = "Configured"
        apis = [
            ("/v1/chat/completions", {"messages": [{"role": "system", "content": "Client"},
                                                    {"role": "user", "content": "hi"}], "max_tokens": 20}),
            ("/v1/messages", {"system": "Client", "messages": [{"role": "user", "content": "hi"}],
                              "max_tokens": 20}),
            ("/v1/responses", {"instructions": "Client", "input": "hi", "max_output_tokens": 20})
        ]
        for priority, expected in (("client", "Client"), ("server", "Configured"),
                                   ("merge", "Configured\n\nClient")):
            self.svc.system_prompt_priority = priority
            for path, body in apis:
                with self.subTest(priority=priority, path=path):
                    self.captured.clear()
                    self.post(path, body)
                    self.assertTrue(self.captured, "prompt was not tokenized")
                    self.assertEqual(self.captured[-1][0]["content"], expected)

    def test_no_config_default_preserves_api_client(self):
        self.svc.system_prompt = ""
        self.svc.system_prompt_priority = "client"
        self.captured.clear()
        self.post("/v1/chat/completions", {"messages": [{"role": "user", "content": "hi"}],
                                           "max_tokens": 16})
        self.assertEqual(self.captured[-1][0]["role"], "user")


if __name__ == "__main__":
    unittest.main()
