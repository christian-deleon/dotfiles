"""Bedrock GovCloud appends a fake SSE server_error after a finished stream."""

from __future__ import annotations

import unittest

from bedrock_grok_proxy import filter_sse


COMPLETED = """\
data: {"type":"response.created","response":{"id":"resp_1"}}

data: {"type":"response.output_text.delta","delta":"Yo."}

data: {"sequence_number":19,"type":"response.completed"}

data: {"error":{"message":"The server had an error while processing your request. Sorry about that!","type":"server_error","param":null,"code":"internal_server_error"}}

data: [DONE]

"""

INCOMPLETE = """\
data: {"type":"response.incomplete"}

data: {"error":{"message":"The server had an error while processing your request. Sorry about that!","type":"server_error","param":null,"code":"internal_server_error"}}

data: [DONE]

"""

CHAT = """\
data: {"choices":[{"delta":{"content":"Yo."},"finish_reason":null,"index":0}]}

data: {"choices":[{"delta":{},"finish_reason":"stop","index":0}]}

data: {"error":{"message":"The server had an error while processing your request. Sorry about that!","type":"server_error","param":null,"code":"internal_server_error"}}

data: [DONE]

"""

REAL_ERROR_ONLY = """\
data: {"error":{"message":"The server had an error while processing your request. Sorry about that!","type":"server_error","param":null,"code":"internal_server_error"}}

data: [DONE]

"""


class FilterSseTest(unittest.TestCase):
    def test_strips_glitch_after_completed(self) -> None:
        out = filter_sse(COMPLETED)
        self.assertIn("response.completed", out)
        self.assertIn("Yo.", out)
        self.assertIn("data: [DONE]", out)
        self.assertNotIn("server_error", out)

    def test_strips_glitch_after_incomplete(self) -> None:
        out = filter_sse(INCOMPLETE)
        self.assertIn("response.incomplete", out)
        self.assertIn("data: [DONE]", out)
        self.assertNotIn("server_error", out)

    def test_strips_glitch_after_chat_finish(self) -> None:
        out = filter_sse(CHAT)
        self.assertIn("finish_reason", out)
        self.assertIn("Yo.", out)
        self.assertIn("data: [DONE]", out)
        self.assertNotIn("server_error", out)

    def test_keeps_error_when_stream_never_finished(self) -> None:
        out = filter_sse(REAL_ERROR_ONLY)
        self.assertIn("server_error", out)
        self.assertIn("data: [DONE]", out)


if __name__ == "__main__":
    unittest.main()
