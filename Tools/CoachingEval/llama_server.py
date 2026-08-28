#!/usr/bin/env python3
"""Lifecycle and OpenAI-compatible HTTP client for a pinned llama-server."""

import json
import os
import signal
import socket
import subprocess
import time
import urllib.error
import urllib.request
from pathlib import Path

from http_security import SameOriginAuthorizationRedirectHandler


class LlamaServerError(RuntimeError):
    pass


class LlamaServerTimeout(LlamaServerError):
    pass


def build_chat_payload(
    *,
    system_prompt,
    request,
    schema,
    seed,
    maximum_output_tokens,
    temperature,
    top_p,
    enable_thinking,
    extra_messages=None,
    after_messages=None,
    model=None,
    include_chat_template_kwargs=True,
):
    messages = [{"role": "system", "content": system_prompt}]
    messages.extend(extra_messages or [])
    messages.append(
        {
            "role": "user",
            "content": json.dumps(request, sort_keys=True, separators=(",", ":")),
        }
    )
    messages.extend(after_messages or [])
    payload = {
        "messages": messages,
        "seed": seed,
        "max_tokens": maximum_output_tokens,
        "temperature": temperature,
        "top_p": top_p,
        "response_format": {
            "type": "json_schema",
            "json_schema": {
                "name": "model_coaching_turn",
                "strict": True,
                "schema": schema,
            },
        },
    }
    if include_chat_template_kwargs:
        payload["chat_template_kwargs"] = {"enable_thinking": bool(enable_thinking)}
    if model is not None:
        payload["model"] = model
    return payload


class OpenAIChatClient:
    def __init__(self, base_url, *, api_key=None, model=None):
        base_url = base_url.rstrip("/")
        if api_key and not base_url.lower().startswith("https://"):
            raise ValueError("Reference credentials require an HTTPS endpoint")
        if base_url.endswith("/chat/completions"):
            self.url = base_url
        elif base_url.endswith("/v1"):
            self.url = base_url + "/chat/completions"
        else:
            self.url = base_url + "/v1/chat/completions"
        self.api_key = api_key
        self.model = model
        self.opener = urllib.request.build_opener(SameOriginAuthorizationRedirectHandler())

    def complete(self, *, timeout, **arguments):
        payload = build_chat_payload(
            model=self.model,
            include_chat_template_kwargs=False,
            **arguments,
        )
        headers = {"Content-Type": "application/json"}
        if self.api_key:
            headers["Authorization"] = f"Bearer {self.api_key}"
        request_body = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        http_request = urllib.request.Request(
            self.url,
            data=request_body,
            headers=headers,
            method="POST",
        )
        try:
            with self.opener.open(http_request, timeout=timeout) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            detail = error.read().decode("utf-8", errors="replace")
            raise LlamaServerError(f"endpoint returned HTTP {error.code}: {detail}") from error
        except (OSError, ValueError, urllib.error.URLError) as error:
            raise LlamaServerError(f"endpoint request failed: {error}") from error


def _ephemeral_port():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as listener:
        listener.bind(("127.0.0.1", 0))
        return listener.getsockname()[1]


class LlamaServer:
    def __init__(
        self,
        executable,
        model_path,
        *,
        context_tokens,
        command_prefix=None,
        environment=None,
    ):
        self.executable = Path(executable)
        self.model_path = Path(model_path)
        self.context_tokens = context_tokens
        self.command_prefix = list(command_prefix or [])
        self.environment = None if environment is None else dict(environment)
        self.port = None
        self.process = None
        self.command = []

    @property
    def is_running(self):
        return self.process is not None and self.process.poll() is None

    @property
    def base_url(self):
        if self.port is None:
            raise LlamaServerError("Server has not been started")
        return f"http://127.0.0.1:{self.port}"

    def start(self, timeout=30):
        if self.is_running:
            raise LlamaServerError("Server is already running")
        self.port = _ephemeral_port()
        self.command = self.command_prefix + [
            str(self.executable),
            "-m",
            str(self.model_path),
            "-c",
            str(self.context_tokens),
            "--host",
            "127.0.0.1",
            "--port",
            str(self.port),
        ]
        self.process = subprocess.Popen(
            self.command,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            env=self.environment,
            start_new_session=True,
        )
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if self.process.poll() is not None:
                code = self.process.returncode
                self.process = None
                raise LlamaServerError(f"llama-server exited before readiness with status {code}")
            try:
                with urllib.request.urlopen(f"{self.base_url}/health", timeout=0.2) as response:
                    body = json.load(response)
                    if body.get("status") in {"ok", "ready"}:
                        return
            except (OSError, ValueError, urllib.error.URLError):
                pass
            time.sleep(0.05)
        self.stop()
        raise LlamaServerTimeout("llama-server did not report ready before the startup timeout")

    def stop(self):
        process = self.process
        if process is None:
            return
        if process.poll() is None:
            try:
                os.killpg(process.pid, signal.SIGTERM)
                process.wait(timeout=2)
            except (ProcessLookupError, subprocess.TimeoutExpired):
                if process.poll() is None:
                    try:
                        os.killpg(process.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                    process.wait(timeout=2)
        self.process = None

    def complete(
        self,
        *,
        system_prompt,
        request,
        schema,
        seed,
        maximum_output_tokens,
        temperature,
        top_p,
        enable_thinking,
        timeout,
        extra_messages=None,
        after_messages=None,
    ):
        payload = build_chat_payload(
            system_prompt=system_prompt,
            request=request,
            schema=schema,
            seed=seed,
            maximum_output_tokens=maximum_output_tokens,
            temperature=temperature,
            top_p=top_p,
            enable_thinking=enable_thinking,
            extra_messages=extra_messages,
            after_messages=after_messages,
        )
        request_body = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        http_request = urllib.request.Request(
            f"{self.base_url}/v1/chat/completions",
            data=request_body,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        try:
            with urllib.request.urlopen(http_request, timeout=timeout) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            detail = error.read().decode("utf-8", errors="replace")
            raise LlamaServerError(f"llama-server returned HTTP {error.code}: {detail}") from error
        except (TimeoutError, socket.timeout) as error:
            self.stop()
            raise LlamaServerTimeout("Generation timed out; server process group terminated") from error
        except urllib.error.URLError as error:
            if isinstance(error.reason, (TimeoutError, socket.timeout)):
                self.stop()
                raise LlamaServerTimeout("Generation timed out; server process group terminated") from error
            raise LlamaServerError(f"llama-server request failed: {error}") from error

    def __enter__(self):
        self.start()
        return self

    def __exit__(self, _error_type, _error, _traceback):
        self.stop()
