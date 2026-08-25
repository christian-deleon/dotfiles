"""Grok cannot register managed AWS MCP tools named aws___*.

Independent expected names: the 9 tools returned by
https://aws-mcp.us-east-1.api.aws/mcp tools/list (2026-08-24 handshake).
Grok namespaces as server__tool, so the session registry must see call_aws
not aws___call_aws.
"""

from __future__ import annotations

import unittest

from aws_mcp_grok_shim import NameMap, rewrite_client_message, rewrite_server_message

# Captured from the managed AWS MCP tools/list, not computed by the shim.
AWS_BACKEND_TOOLS = (
    "aws___call_aws",
    "aws___get_presigned_url",
    "aws___get_tasks",
    "aws___run_script",
    "aws___get_regional_availability",
    "aws___list_regions",
    "aws___read_documentation",
    "aws___retrieve_skill",
    "aws___search_documentation",
)
GROK_TOOLS = (
    "call_aws",
    "get_presigned_url",
    "get_tasks",
    "run_script",
    "get_regional_availability",
    "list_regions",
    "read_documentation",
    "retrieve_skill",
    "search_documentation",
)


class RewriteServerListTests(unittest.TestCase):
    def test_tools_list_strips_aws_triple_underscore_prefix(self) -> None:
        names = NameMap()
        incoming = {
            "jsonrpc": "2.0",
            "id": 2,
            "result": {
                "tools": [
                    {
                        "name": backend,
                        "description": "d",
                        "inputSchema": {"type": "object"},
                        "_meta": {"fastmcp": {"tags": []}},
                        "outputSchema": {
                            "type": "object",
                            "x-fastmcp-wrap-result": True,
                        },
                    }
                    for backend in AWS_BACKEND_TOOLS
                ]
            },
        }
        out = rewrite_server_message(incoming, names)
        got = [t["name"] for t in out["result"]["tools"]]
        self.assertEqual(list(GROK_TOOLS), got)
        for tool in out["result"]["tools"]:
            self.assertNotIn("_meta", tool)
            self.assertNotIn("outputSchema", tool)

    def test_initialize_result_is_unchanged(self) -> None:
        names = NameMap()
        incoming = {
            "jsonrpc": "2.0",
            "id": 1,
            "result": {
                "protocolVersion": "2025-11-25",
                "serverInfo": {"name": "MCP Proxy for AWS", "version": "1.6.3"},
            },
        }
        self.assertEqual(incoming, rewrite_server_message(incoming, names))


class RewriteClientCallTests(unittest.TestCase):
    def test_tools_call_restores_backend_name_after_list(self) -> None:
        names = NameMap()
        rewrite_server_message(
            {
                "jsonrpc": "2.0",
                "id": 2,
                "result": {
                    "tools": [
                        {"name": "aws___call_aws", "inputSchema": {"type": "object"}}
                    ]
                },
            },
            names,
        )
        outgoing = {
            "jsonrpc": "2.0",
            "id": 3,
            "method": "tools/call",
            "params": {
                "name": "call_aws",
                "arguments": {"cli_command": "aws sts get-caller-identity"},
            },
        }
        rewritten = rewrite_client_message(outgoing, names)
        self.assertEqual("aws___call_aws", rewritten["params"]["name"])
        self.assertEqual(
            "aws sts get-caller-identity",
            rewritten["params"]["arguments"]["cli_command"],
        )

    def test_tools_call_before_list_adds_prefix(self) -> None:
        names = NameMap()
        outgoing = {
            "jsonrpc": "2.0",
            "id": 3,
            "method": "tools/call",
            "params": {"name": "run_script", "arguments": {"code": "print(1)"}},
        }
        rewritten = rewrite_client_message(outgoing, names)
        self.assertEqual("aws___run_script", rewritten["params"]["name"])


if __name__ == "__main__":
    unittest.main()
