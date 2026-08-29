#!/usr/bin/env python3
"""Lifecycle and OpenAI-compatible HTTP client for a pinned llama-server."""

import json
import os
import re
import signal
import socket
import subprocess
import time
import urllib.error
import urllib.request
from pathlib import Path

import coaching_grammar
from http_security import SameOriginAuthorizationRedirectHandler


ERROR_CATEGORIES = frozenset(("generationError", "contextOverflow"))
MAXIMUM_ERROR_BODY_BYTES = 64 * 1024
CONTEXT_OVERFLOW_BODY = re.compile(
    r"(?:context|token).{0,80}(?:exceed|too[ -]?large|limit|maximum|size)"
    r"|(?:exceed|too[ -]?large).{0,80}(?:context|token)",
    re.IGNORECASE | re.DOTALL,
)


class LlamaServerError(RuntimeError):
    def __init__(self, message, *, category="generationError", http_status=None):
        super().__init__(message)
        self.category = category if category in ERROR_CATEGORIES else "generationError"
        self.http_status = http_status if isinstance(http_status, int) else None


class LlamaServerTimeout(LlamaServerError):
    pass


def _bounded_http_error(error, *, source):
    """Classify an HTTP failure without retaining or returning its response body."""
    body = error.read(MAXIMUM_ERROR_BODY_BYTES).decode("utf-8", errors="replace")
    category = (
        "contextOverflow"
        if error.code == 413 or CONTEXT_OVERFLOW_BODY.search(body)
        else "generationError"
    )
    message = f"{source} returned HTTP {error.code}"
    if category == "contextOverflow":
        message += " (context overflow)"
    return LlamaServerError(message, category=category, http_status=error.code)


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


def build_template_payload(
    *,
    system_prompt,
    request,
    enable_thinking,
    extra_messages=None,
    after_messages=None,
):
    """Build the exact conversation rendered by llama.cpp's model template."""
    payload = build_chat_payload(
        system_prompt=system_prompt,
        request=request,
        schema={},
        seed=0,
        maximum_output_tokens=1,
        temperature=0,
        top_p=1,
        enable_thinking=enable_thinking,
        extra_messages=extra_messages,
        after_messages=after_messages,
    )
    return {
        "messages": payload["messages"],
        "chat_template_kwargs": payload["chat_template_kwargs"],
    }


def build_text_template_payload(
    *,
    system_prompt,
    user_content,
    enable_thinking,
    extra_messages=None,
    after_messages=None,
):
    """Build a template request whose final user content is already rendered text."""
    messages = [{"role": "system", "content": system_prompt}]
    messages.extend(extra_messages or [])
    messages.append({"role": "user", "content": user_content})
    messages.extend(after_messages or [])
    return {
        "messages": messages,
        "chat_template_kwargs": {"enable_thinking": bool(enable_thinking)},
    }


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
            raise _bounded_http_error(error, source="reference endpoint") from error
        except (OSError, ValueError, urllib.error.URLError) as error:
            raise LlamaServerError("reference endpoint request failed") from error


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
        template_payload = build_template_payload(
            system_prompt=system_prompt,
            request=request,
            enable_thinking=enable_thinking,
            extra_messages=extra_messages,
            after_messages=after_messages,
        )
        response = self._post_json(
            "/apply-template", template_payload, timeout=timeout
        )
        prompt = response.get("prompt")
        if not isinstance(prompt, str):
            raise LlamaServerError("llama-server template response has no prompt")
        return self.complete_rendered(
            prompt=prompt,
            grammar=coaching_grammar.strict_grammar(
                schema,
                enable_thinking=enable_thinking,
            ),
            seed=seed,
            maximum_output_tokens=maximum_output_tokens,
            temperature=temperature,
            top_p=top_p,
            timeout=timeout,
        )

    def render_prompt(
        self,
        *,
        system_prompt,
        user_content,
        enable_thinking,
        timeout,
        extra_messages=None,
        after_messages=None,
    ):
        payload = build_text_template_payload(
            system_prompt=system_prompt,
            user_content=user_content,
            enable_thinking=enable_thinking,
            extra_messages=extra_messages,
            after_messages=after_messages,
        )
        prompt = self._post_json("/apply-template", payload, timeout=timeout).get("prompt")
        if not isinstance(prompt, str):
            raise LlamaServerError("llama-server template response has no prompt")
        return prompt

    def token_count(self, prompt, *, timeout):
        response = self._post_json(
            "/tokenize",
            {"content": prompt, "add_special": False, "parse_special": True},
            timeout=timeout,
        )
        tokens = response.get("tokens")
        if isinstance(tokens, list) and all(isinstance(token, int) for token in tokens):
            return len(tokens)
        count = response.get("count")
        if isinstance(count, int) and count >= 0:
            return count
        raise LlamaServerError("llama-server tokenization response has no token count")

    def complete_rendered(
        self,
        *,
        prompt,
        grammar,
        seed,
        maximum_output_tokens,
        temperature,
        top_p,
        timeout,
    ):
        payload = {
            "prompt": prompt,
            "seed": seed,
            "n_predict": maximum_output_tokens,
            "temperature": temperature,
            "top_p": top_p,
            "grammar": grammar,
        }
        response = self._post_json("/completion", payload, timeout=timeout)
        content = response.get("content")
        if not isinstance(content, str):
            raise LlamaServerError("llama-server completion response has no content")
        timings = response.get("timings", {})
        normalized = dict(response)
        normalized["choices"] = [
            {
                "message": {"role": "assistant", "content": content},
                "finish_reason": response.get("stop_type"),
            }
        ]
        normalized["usage"] = {
            "prompt_tokens": int(timings.get("prompt_n", 0) or 0),
            "completion_tokens": int(timings.get("predicted_n", 0) or 0),
        }
        return normalized

    def _post_json(self, path, payload, *, timeout):
        request_body = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        http_request = urllib.request.Request(
            f"{self.base_url}{path}",
            data=request_body,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        try:
            with urllib.request.urlopen(http_request, timeout=timeout) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            raise _bounded_http_error(error, source="llama-server") from error
        except (TimeoutError, socket.timeout) as error:
            self.stop()
            raise LlamaServerTimeout("Generation timed out; server process group terminated") from error
        except urllib.error.URLError as error:
            if isinstance(error.reason, (TimeoutError, socket.timeout)):
                self.stop()
                raise LlamaServerTimeout("Generation timed out; server process group terminated") from error
            raise LlamaServerError("llama-server request failed") from error

    def __enter__(self):
        self.start()
        return self

    def __exit__(self, _error_type, _error, _traceback):
        self.stop()
