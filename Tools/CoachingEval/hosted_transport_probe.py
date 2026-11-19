"""Opt-in transport timing for isolated hosted diagnostics, not production."""

from contextvars import ContextVar
import http.client
import math
import time
import urllib.request
import uuid

from Tools.CoachingEval.http_security import SameOriginAuthorizationRedirectHandler
from Tools.CoachingEval.openai_responses import OpenAIResponsesClient, OpenAIResponsesError


class TimedResponsesClient(OpenAIResponsesClient):
    def __init__(self, *args, emit, **kwargs):
        super().__init__(*args, **kwargs)
        self.emit = emit
        self._current_trace = ContextVar("coaching_transport_probe")
        self.opener = urllib.request.build_opener(
            SameOriginAuthorizationRedirectHandler(),
            _HTTPHandler(self._current_trace),
            _HTTPSHandler(self._current_trace),
        )

    def complete(self, **kwargs):
        trace = _Trace(self.emit)
        token = self._current_trace.set(trace)
        try:
            response = super().complete(**kwargs)
            trace.mark("complete", usage=response["usage"])
            return response
        except OpenAIResponsesError as error:
            trace.mark("failed", category=error.category)
            raise
        finally:
            self._current_trace.reset(token)


class _Trace:
    def __init__(self, emit):
        self.emit = emit
        self.started = time.monotonic()
        self.client_request_id = str(uuid.uuid4())

    def mark(self, stage, **fields):
        self.emit(dict(stage=stage, client_request_id=self.client_request_id,
                       elapsed_ms=round((time.monotonic() - self.started) * 1000, 3), **fields))


class _TimingConnection:
    def connect(self):
        super().connect()
        # For HTTPS this includes DNS, TCP and the verified TLS handshake.
        self._probe_trace.mark("connected")

    def endheaders(self, *args, **kwargs):
        self.putheader("X-Client-Request-Id", self._probe_trace.client_request_id)
        super().endheaders(*args, **kwargs)
        self._probe_trace.mark("request_sent")

    def getresponse(self):
        response = super().getresponse()
        fields = {"http_status": response.status}
        try:
            value = float(response.getheader("openai-processing-ms"))
            if math.isfinite(value) and 0 <= value <= 300_000:
                fields["provider_processing_ms"] = value
        except (TypeError, ValueError):
            pass
        self._probe_trace.mark("headers", **fields)
        return response


class _HTTPConnection(_TimingConnection, http.client.HTTPConnection):
    pass


class _HTTPSConnection(_TimingConnection, http.client.HTTPSConnection):
    pass


class _HTTPHandler(urllib.request.HTTPHandler):
    def __init__(self, current_trace):
        super().__init__()
        self.current_trace = current_trace

    def http_open(self, request):
        def connection(host, **kwargs):
            instance = _HTTPConnection(host, **kwargs)
            instance._probe_trace = self.current_trace.get()
            return instance
        return self.do_open(connection, request)


class _HTTPSHandler(urllib.request.HTTPSHandler):
    def __init__(self, current_trace):
        super().__init__()
        self.current_trace = current_trace

    def https_open(self, request):
        def connection(host, **kwargs):
            instance = _HTTPSConnection(host, **kwargs)
            instance._probe_trace = self.current_trace.get()
            return instance
        return self.do_open(connection, request, context=self._context)
