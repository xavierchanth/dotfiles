#!/usr/bin/env python3
"""Backend contract tests and a real MCP stdio handshake using a fake display."""
from __future__ import annotations

from io import BytesIO
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

ROOT = Path(os.environ.get("TEST_ROOT", Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(ROOT / "scripts"))
from cage_mcp import CageDesktop, Session, create_server
from PIL import Image


def png_bytes():
    output = BytesIO()
    Image.new("RGB", (800, 600), "white").save(output, "PNG")
    return output.getvalue()


class FakeDesktop(CageDesktop):
    def __init__(self):
        super().__init__()
        self.calls = []

    def launch(self, executable, args):
        session = Session("owned", executable, 5905, "wayland-test",
                          Mock(poll=Mock(return_value=None)), tempfile.TemporaryDirectory())
        self.sessions[session.id] = session
        return session.summary()

    def run(self, argv, *, env=None, data=None):
        self.calls.append((argv, env, data))
        return png_bytes() if argv[0] == "grim" else b""

    def stop_process(self, app, process):
        pass

    def close_all(self):
        super().close_all()
        if marker := os.environ.get("CAGE_TEST_CLOSED"):
            Path(marker).write_text("closed")


class BackendTests(unittest.TestCase):
    def setUp(self):
        self.desktop = FakeDesktop()
        self.desktop.launch("test-app", [])
        self.addCleanup(self.desktop.close_all)

    def test_requires_owned_session_and_observed_coordinates(self):
        with self.assertRaises(ValueError):
            self.desktop.capture("not-owned")
        with self.assertRaises(ValueError):
            self.desktop.click("owned", 1, 1, "left", 1, None)
        self.desktop.capture("owned")
        for x, y in [(800, 0), (-1, 0), (0, 600), (True, 1)]:
            with self.assertRaises(ValueError):
                self.desktop.click("owned", x, y, "left", 1, None)
        with self.assertRaisesRegex(ValueError, "unsupported"):
            self.desktop.click("owned", 1, 1, "left", 1, 42)
        self.assertFalse(any(call[0][0] == "vncdo" for call in self.desktop.calls))

    def test_capture_reports_original_pixel_dimensions(self):
        metadata, png = self.desktop.capture("owned")
        self.assertEqual(metadata["screenshot"]["width"], 800)
        self.assertEqual(metadata["screenshot"]["height"], 600)
        self.assertEqual(metadata["screenshot"]["scale"], 1)
        self.assertFalse(metadata["capabilities"]["accessibility"])
        self.assertEqual(png, png_bytes())

    def test_move_and_click_share_vnc_connection(self):
        self.desktop.capture("owned")
        self.desktop.click("owned", 10, 20, "right", 2, None)
        self.assertEqual(self.desktop.calls[-1][0], ["vncdo", "-s", "127.0.0.1::5905",
                         "move", "10", "20", "click", "3", "pause", "0.08", "click", "3"])

    def test_drag_releases_button_and_scroll_is_bounded(self):
        self.desktop.capture("owned")
        self.desktop.drag("owned", 1, 2, 30, 40)
        self.assertEqual(self.desktop.calls[-1][0][-10:],
                         ["move", "1", "2", "mousedown", "1", "drag", "30", "40", "mouseup", "1"])
        self.desktop.scroll("owned", "down", 1, 10, 20, None)
        self.assertEqual(self.desktop.calls[-1][0].count("click"), 8)

    def test_text_is_stdin_not_shell_or_cli_options(self):
        text = '--help $(touch /tmp/never)\nλ'
        self.desktop.type_text("owned", text)
        argv, env, data = self.desktop.calls[-1]
        self.assertEqual(argv, ["wtype", "-"])
        self.assertEqual(env["WAYLAND_DISPLAY"], "wayland-test")
        self.assertEqual(data, text.encode())

    def test_key_chords_release_modifiers(self):
        self.desktop.press_key("owned", "ctrl+shift+a")
        self.assertEqual(self.desktop.calls[-1][0],
                         ["wtype", "-M", "ctrl", "-M", "shift", "-k", "a", "-m", "shift", "-m", "ctrl"])
        with self.assertRaises(ValueError):
            self.desktop.press_key("owned", "bad+a")

    def test_close_drops_ownership_and_preserves_other_apps(self):
        self.desktop.close("owned")
        self.assertEqual(self.desktop.list_apps(), [])
        with self.assertRaises(ValueError):
            self.desktop.close("unrelated")

    def test_cleanup_uses_owned_unit_not_port(self):
        process = Mock(pid=1234, poll=Mock(return_value=0))
        with patch("subprocess.run") as run:
            CageDesktop.stop_process("unique-id", process)
        self.assertEqual(run.call_args.args[0],
                         ["systemctl", "--user", "stop", "cage-session-unique-id.scope"])

    def test_tool_failure_is_not_retried(self):
        with patch("subprocess.run", side_effect=subprocess.TimeoutExpired("wtype", 15)) as run:
            with self.assertRaisesRegex(RuntimeError, "inspect state"):
                CageDesktop.run(["wtype", "-"])
        self.assertEqual(run.call_count, 1)

    def test_launch_uses_literal_argv_and_unique_unit(self):
        desktop = CageDesktop()
        process = Mock(poll=Mock(return_value=None))
        def start(argv, **kwargs):
            kwargs["stdout"].write(b"Cage display: wayland-17\n")
            return process
        with patch.dict(os.environ, {"XDG_RUNTIME_DIR": "/tmp"}), \
             patch("shutil.which", return_value="/bin/test-app"), \
             patch("subprocess.Popen", side_effect=start) as spawn, \
             patch.object(desktop, "stop_process"):
            result = desktop.launch("test-app", ["a b", "$(touch never)"])
            argv = spawn.call_args.args[0]
            self.assertEqual(argv[-3:], ["/bin/test-app", "a b", "$(touch never)"])
            self.assertEqual(argv[argv.index("--name") + 1], result["id"])
            self.assertEqual(desktop.get(result["id"]).display, "wayland-17")
            desktop.close_all()


class ProtocolTests(unittest.IsolatedAsyncioTestCase):
    async def test_stdio_images_errors_and_disconnect_cleanup(self):
        from mcp import ClientSession, StdioServerParameters
        from mcp.client.stdio import stdio_client
        with tempfile.TemporaryDirectory() as directory:
            marker = Path(directory) / "closed"
            params = StdioServerParameters(command=sys.executable, args=[str(Path(__file__)), "--serve-fake"],
                                           env={"CAGE_TEST_CLOSED": str(marker), "PYTHONDONTWRITEBYTECODE": "1"})
            async with stdio_client(params) as (reader, writer):
                async with ClientSession(reader, writer) as client:
                    await client.initialize()
                    tools = {tool.name: tool for tool in (await client.list_tools()).tools}
                    self.assertEqual(set(tools), {"launch_app", "list_apps", "get_app_state", "click",
                                                   "drag", "scroll", "press_key", "type_text", "close_app"})
                    self.assertTrue(tools["get_app_state"].annotations.readOnlyHint)
                    self.assertFalse(tools["click"].annotations.readOnlyHint)
                    await client.call_tool("launch_app", {"executable": "test-app"})
                    state = await client.call_tool("get_app_state", {"app": "owned"})
                    self.assertFalse(state.isError)
                    self.assertEqual(state.structuredContent["screenshot"]["width"], 800)
                    self.assertEqual(state.content[1].type, "image")
                    self.assertEqual(state.content[1].mimeType, "image/png")
                    for args in [{"app": "other", "x": 1, "y": 2},
                                 {"app": "owned", "element_index": 1},
                                 {"app": "owned", "x": True, "y": 2},
                                 {"app": "owned", "x": 1, "y": 2, "click_count": 0}]:
                        result = await client.call_tool("click", args)
                        self.assertTrue(result.isError, args)
                    result = await client.call_tool("click", {"app": "owned", "x": 10, "y": 20})
                    self.assertFalse(result.isError)
                    self.assertEqual(result.content[1].type, "image")
            self.assertEqual(marker.read_text(), "closed")


if __name__ == "__main__":
    if "--serve-fake" in sys.argv:
        create_server(FakeDesktop()).run(transport="stdio")
    else:
        unittest.main()
