#!/usr/bin/env python3
"""App-scoped, screenshot-based Computer Use over MCP stdio and Cage."""
from __future__ import annotations

import base64
from contextlib import asynccontextmanager
from dataclasses import dataclass
from io import BytesIO
import json
import os
from pathlib import Path
import re
import shutil
import signal
import socket
import subprocess
import tempfile
import threading
import time
from typing import Annotated, Literal
import uuid

from mcp.server.fastmcp import FastMCP
from mcp.types import CallToolResult, ImageContent, TextContent, ToolAnnotations
from PIL import Image
from pydantic import Field


MAX_IMAGE_BYTES = 20 * 1024 * 1024
Coordinate = Annotated[int, Field(strict=True, ge=0, le=16383)]
Button = Literal["left", "right", "middle", "l", "r", "m"]
Direction = Literal["up", "down", "left", "right", "u", "d", "l", "r"]


@dataclass
class Session:
    id: str
    executable: str
    port: int
    display: str
    process: subprocess.Popen
    directory: tempfile.TemporaryDirectory
    frame_size: tuple[int, int] | None = None

    @property
    def unit(self) -> str:
        return f"cage-session-{self.id}.scope"

    def summary(self) -> dict:
        return {"id": self.id, "displayName": Path(self.executable).name,
                "isRunning": self.process.poll() is None}


class CageDesktop:
    """Own only sessions launched by this MCP connection; never attach by port."""

    def __init__(self):
        self.sessions: dict[str, Session] = {}
        self.lock = threading.RLock()

    @staticmethod
    def run(argv: list[str], *, env=None, data: bytes | None = None) -> bytes:
        try:
            result = subprocess.run(argv, input=data, stdout=subprocess.PIPE,
                                    stderr=subprocess.PIPE, env=env, timeout=15)
        except subprocess.TimeoutExpired as error:
            raise RuntimeError(f"{Path(argv[0]).name} timed out; inspect state before retrying") from error
        if result.returncode:
            detail = result.stderr.decode(errors="replace")[-1000:]
            raise RuntimeError(f"{Path(argv[0]).name} failed: {detail}")
        return result.stdout

    def get(self, app: str) -> Session:
        session = self.sessions.get(app)
        if session is None:
            raise ValueError("Unknown app ID. Use launch_app or list_apps on this connection.")
        if session.process.poll() is not None:
            raise RuntimeError("The app session has exited; close it or launch a new session.")
        return session

    def launch(self, executable: str, args: list[str]) -> dict:
        with self.lock:
            if len(self.sessions) >= 4:
                raise ValueError("Close an existing app before opening more than four sessions.")
            command = shutil.which(executable)
            if command is None:
                raise ValueError("Executable not found on this host.")
            if not os.environ.get("XDG_RUNTIME_DIR"):
                raise RuntimeError("Launch this server in a Linux login session with XDG_RUNTIME_DIR.")
            if any("\0" in arg for arg in args):
                raise ValueError("Arguments cannot contain NUL bytes.")
            with socket.socket() as reservation:
                reservation.bind(("127.0.0.1", 0))
                port = reservation.getsockname()[1]
            app = uuid.uuid4().hex
            directory = tempfile.TemporaryDirectory(prefix="cage-mcp-")
            log_path = Path(directory.name) / "session.log"
            process = None
            try:
                with log_path.open("wb") as log:
                    process = subprocess.Popen(
                        ["cage-session", "--port", str(port), "--name", app, "--", command, *args],
                        stdin=subprocess.DEVNULL, stdout=log, stderr=log, start_new_session=True)
                deadline = time.monotonic() + 15
                while time.monotonic() < deadline:
                    if process.poll() is not None:
                        raise RuntimeError("Cage failed to start: " + log_path.read_text(errors="replace")[-2000:])
                    with log_path.open("rb") as log:
                        startup = log.read(65536).decode(errors="replace")
                    match = re.search(r"^Cage display: ([A-Za-z0-9_.-]+)$", startup, re.MULTILINE)
                    if match:
                        session = Session(app, command, port, match[1], process, directory)
                        self.sessions[app] = session
                        return session.summary()
                    time.sleep(0.05)
                raise RuntimeError("Cage startup timed out.")
            except BaseException:
                if process is not None:
                    self.stop_process(app, process)
                directory.cleanup()
                raise

    @staticmethod
    def stop_process(app: str, process: subprocess.Popen):
        # A random per-connection unit name prevents stopping an unrelated session
        # if a TCP port is reused after this application's exit.
        try:
            subprocess.run(["systemctl", "--user", "stop", f"cage-session-{app}.scope"],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=8)
        except (OSError, subprocess.TimeoutExpired):
            pass
        if process.poll() is None:
            try:
                os.killpg(process.pid, signal.SIGTERM)
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait(timeout=3)
            except ProcessLookupError:
                pass

    def close(self, app: str) -> dict:
        with self.lock:
            session = self.sessions.get(app)
            if session is None:
                raise ValueError("Unknown app ID.")
            self.stop_process(app, session.process)
            session.directory.cleanup()
            del self.sessions[app]
            return {"app": app, "closed": True}

    def close_all(self):
        with self.lock:
            for app in list(self.sessions):
                self.close(app)

    def list_apps(self) -> list[dict]:
        with self.lock:
            return [session.summary() for session in self.sessions.values()]

    @staticmethod
    def environment(session: Session) -> dict[str, str]:
        return dict(os.environ, WAYLAND_DISPLAY=session.display)

    def capture(self, app: str) -> tuple[dict, bytes]:
        with self.lock:
            session = self.get(app)
            png = self.run(["grim", "-"], env=self.environment(session))
            if len(png) > MAX_IMAGE_BYTES:
                raise RuntimeError("Screenshot exceeds the 20 MiB response limit.")
            with Image.open(BytesIO(png)) as image:
                if image.format != "PNG":
                    raise RuntimeError("Screenshot backend returned a non-PNG image.")
                width, height = image.size
                if not (0 < width <= 16384 and 0 < height <= 16384):
                    raise RuntimeError("Unsupported screenshot dimensions.")
                image.verify()
            session.frame_size = (width, height)
            metadata = {"app": app, "target": "linux-cage", "displayName": Path(session.executable).name,
                        "screenshot": {"mimeType": "image/png", "width": width, "height": height,
                                       "coordinateSpace": "image-pixels", "scale": 1},
                        "text": "Screenshot-only state. No accessibility tree or element indices.",
                        "capabilities": {"coordinates": True, "keyboard": True,
                                         "accessibility": False, "clipboard": False}}
            return metadata, png

    @staticmethod
    def point(session: Session, x: int | None, y: int | None):
        if session.frame_size is None:
            raise ValueError("Call get_app_state before coordinate actions.")
        if type(x) is not int or type(y) is not int:
            raise ValueError("Both x and y must be integer screenshot coordinates.")
        width, height = session.frame_size
        if not (0 <= x < width and 0 <= y < height):
            raise ValueError(f"Coordinates are outside the last screenshot ({width}x{height}).")

    def vnc(self, session: Session, commands: list[str]):
        self.run(["vncdo", "-s", f"127.0.0.1::{session.port}", *commands])

    def click(self, app: str, x: int | None, y: int | None, mouse_button: Button,
              click_count: int, element_index: int | None):
        with self.lock:
            if element_index is not None:
                raise ValueError("Accessibility element_index is unsupported; use screenshot coordinates.")
            session = self.get(app)
            self.point(session, x, y)
            button = {"left": 1, "l": 1, "middle": 2, "m": 2, "right": 3, "r": 3}[mouse_button]
            commands = ["move", str(x), str(y)]
            for index in range(click_count):
                if index:
                    commands += ["pause", "0.08"]
                commands += ["click", str(button)]
            self.vnc(session, commands)

    def drag(self, app: str, from_x: int, from_y: int, to_x: int, to_y: int):
        with self.lock:
            session = self.get(app)
            self.point(session, from_x, from_y)
            self.point(session, to_x, to_y)
            self.vnc(session, ["move", str(from_x), str(from_y), "mousedown", "1",
                               "drag", str(to_x), str(to_y), "mouseup", "1"])

    def scroll(self, app: str, direction: Direction, pages: int, x: int, y: int,
               element_index: int | None):
        with self.lock:
            if element_index is not None:
                raise ValueError("Accessibility element_index is unsupported; use screenshot coordinates.")
            session = self.get(app)
            self.point(session, x, y)
            button = {"up": 4, "u": 4, "down": 5, "d": 5,
                      "left": 6, "l": 6, "right": 7, "r": 7}[direction]
            self.vnc(session, ["move", str(x), str(y)] + ["click", str(button)] * (pages * 8))

    def type_text(self, app: str, text: str):
        with self.lock:
            if "\0" in text:
                raise ValueError("Text cannot contain NUL bytes.")
            session = self.get(app)
            self.run(["wtype", "-"], env=self.environment(session), data=text.encode())

    def press_key(self, app: str, key: str):
        with self.lock:
            session = self.get(app)
            parts = key.split("+")
            aliases = {"ctrl": "ctrl", "control": "ctrl", "shift": "shift",
                       "alt": "alt", "super": "logo", "meta": "logo", "logo": "logo"}
            try:
                modifiers = [aliases[item.lower()] for item in parts[:-1]]
            except KeyError as error:
                raise ValueError("Use ctrl, shift, alt, or super modifiers joined with '+'.") from error
            keysym = parts[-1]
            if not re.fullmatch(r"[A-Za-z0-9_]{1,64}", keysym):
                raise ValueError("Use an XKB keysym such as Return, Tab, a, or plus.")
            command = ["wtype"]
            for modifier in modifiers:
                command += ["-M", modifier]
            command += ["-k", keysym]
            for modifier in reversed(modifiers):
                command += ["-m", modifier]
            self.run(command, env=self.environment(session))


def create_server(desktop: CageDesktop | None = None) -> FastMCP:
    desktop = desktop or CageDesktop()

    @asynccontextmanager
    async def lifespan(_server):
        try:
            yield {}
        finally:
            desktop.close_all()

    server = FastMCP("cage", lifespan=lifespan, instructions=(
        "Computer Use for task-specific Cage apps. launch_app creates an owned app ID. "
        "Use get_app_state to inspect its screenshot, then coordinate or keyboard tools. "
        "Actions return a fresh screenshot. Pixels use the screenshot's original dimensions. "
        "No accessibility tree, element_index actions, rich clipboard, or macOS global app access. "
        "close_app ends a session. Sessions close when this MCP connection exits."))

    def state(app: str) -> CallToolResult:
        metadata, png = desktop.capture(app)
        return CallToolResult(content=[TextContent(type="text", text=json.dumps(metadata)),
                                     ImageContent(type="image", mimeType="image/png",
                                                  data=base64.b64encode(png).decode())],
                              structuredContent=metadata)

    read_only = ToolAnnotations(readOnlyHint=True, destructiveHint=False, openWorldHint=False)
    action = ToolAnnotations(readOnlyHint=False, destructiveHint=True, openWorldHint=True)

    @server.tool(annotations=action)
    def launch_app(executable: str, args: list[str] | None = None) -> dict:
        """Launch a chosen executable in a new Cage session; returns its app ID.

        Arguments are literal argv entries, not a shell command. Browser sessions
        may need separate profiles. Use get_app_state next to inspect the app.
        """
        return desktop.launch(executable, args or [])

    @server.tool(annotations=read_only)
    def list_apps() -> list[dict]:
        """List this MCP connection's Cage app IDs and running state."""
        return desktop.list_apps()

    @server.tool(annotations=read_only)
    def get_app_state(app: str, disableDiff: bool = False) -> CallToolResult:
        """Return a native MCP PNG image and state metadata. Always a full snapshot.

        disableDiff is accepted for Sky-style callers; no accessibility diffs exist.
        This never launches an app implicitly: use launch_app first.
        """
        return state(app)

    @server.tool(annotations=action)
    def click(app: str, x: Coordinate | None = None, y: Coordinate | None = None,
              mouse_button: Button = "left", click_count: Annotated[int, Field(strict=True, ge=1, le=3)] = 1,
              element_index: int | None = None) -> CallToolResult:
        """Click screenshot coordinates in the app; element_index is unsupported."""
        with desktop.lock:
            desktop.click(app, x, y, mouse_button, click_count, element_index)
            return state(app)

    @server.tool(annotations=action)
    def drag(app: str, from_x: Coordinate, from_y: Coordinate,
             to_x: Coordinate, to_y: Coordinate) -> CallToolResult:
        """Drag the left mouse button between screenshot coordinates."""
        with desktop.lock:
            desktop.drag(app, from_x, from_y, to_x, to_y)
            return state(app)

    @server.tool(annotations=action)
    def scroll(app: str, direction: Direction, x: Coordinate, y: Coordinate,
               pages: Annotated[int, Field(strict=True, ge=1, le=10)] = 1,
               element_index: int | None = None) -> CallToolResult:
        """Scroll at screenshot coordinates. Each page is eight wheel steps."""
        with desktop.lock:
            desktop.scroll(app, direction, pages, x, y, element_index)
            return state(app)

    @server.tool(annotations=action)
    def press_key(app: str, key: Annotated[str, Field(min_length=1, max_length=128)]) -> CallToolResult:
        """Press an XKB/xdotool-style key or chord, such as Return or ctrl+a."""
        with desktop.lock:
            desktop.press_key(app, key)
            return state(app)

    @server.tool(annotations=action)
    def type_text(app: str, text: Annotated[str, Field(max_length=10000)]) -> CallToolResult:
        """Type UTF-8 text. Newlines can submit forms; this is not clipboard paste."""
        with desktop.lock:
            desktop.type_text(app, text)
            return state(app)

    @server.tool(annotations=action)
    def close_app(app: str) -> dict:
        """Stop this owned Cage app and clean up its display and VNC processes."""
        return desktop.close(app)

    return server


if __name__ == "__main__":
    create_server().run(transport="stdio")
