"""Single-writer durable evidence for explicitly resumed benchmark grading."""

import fcntl
import hashlib
import json
import math
import os
import stat
import tempfile
from decimal import Decimal, InvalidOperation
from pathlib import Path

from Tools.CoachingEval.benchmark.judge_contract import (
    add_metrics,
    canonical_json_bytes,
    empty_metrics,
    incomplete_metrics,
    pretty_json_bytes,
)


class JudgeCheckpoint:
    """Own only grading persistence and single-writer/attempt invariants.

    The grader supplies exact bindings and validates *all* cached outputs on
    entry, before it can make a paid request. No provider errors are persisted.
    """

    def __init__(self, path, bindings, validate_output):
        self._path = Path(os.path.abspath(path))
        self._lock_path = self._path.with_name(self._path.name + ".lock")
        self._bindings = bindings
        self._validate_output = validate_output
        self._lock_fd = None
        self._state = None

    def __enter__(self):
        try:
            self._reject_symlinks()
            self._path.parent.mkdir(parents=True, exist_ok=True)
            self._lock_fd = os.open(
                self._lock_path, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600
            )
            if not stat.S_ISREG(os.fstat(self._lock_fd).st_mode):
                raise ValueError("Judge checkpoint lock must be a regular file")
            try:
                fcntl.flock(self._lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                raise ValueError("Judge checkpoint is already in use") from None
            if os.path.lexists(self._path):
                self._load()
            else:
                self._state = {
                    "schemaVersion": "coaching-quality-judge-checkpoint.v1",
                    "bindings": self._bindings,
                    "cells": {},
                    "inFlight": None,
                }
                self._save()
            # A previous process may have sent this request. Never count it as
            # free, and never recover it automatically without explicit resume.
            if self._state["inFlight"] is not None:
                self.failed(self._state["inFlight"], incomplete_metrics())
            return self
        except BaseException:
            self.__exit__(None, None, None)
            raise

    def __exit__(self, *_exception):
        if self._lock_fd is not None:
            os.close(self._lock_fd)  # flock is released even after process death.
            self._lock_fd = None

    def completed(self, key):
        cell = self._state["cells"].get(key)
        if cell is None or cell["output"] is None:
            return None
        metrics = empty_metrics()
        for attempt in cell["attempts"]:
            add_metrics(metrics, attempt["metrics"])
        return cell["output"], metrics

    def started(self, key):
        if self._state["inFlight"] is not None or self.completed(key) is not None:
            raise ValueError("Judge checkpoint attempt is not available")
        self._state["cells"].setdefault(key, {"output": None, "attempts": []})
        self._state["inFlight"] = key
        self._save()  # Must be durable before the caller sends a paid request.

    def failed(self, key, metrics):
        self._finish(key, "failed", metrics)

    def succeeded(self, key, output, metrics):
        self._validate_output(key, output)
        self._finish(key, "completed", metrics, output)
        return self.completed(key)

    def _finish(self, key, status, metrics, output=None):
        if self._state["inFlight"] != key:
            raise ValueError("Judge checkpoint has no matching in-flight attempt")
        self._validate_metrics(metrics)
        cell = self._state["cells"][key]
        cell["attempts"].append({"status": status, "metrics": metrics})
        cell["output"] = output
        self._state["inFlight"] = None
        self._save()

    def _load(self):
        try:
            descriptor = os.open(self._path, os.O_RDONLY | os.O_NOFOLLOW)
            with os.fdopen(descriptor, "rb") as source:
                if not stat.S_ISREG(os.fstat(source.fileno()).st_mode):
                    raise ValueError("Judge checkpoint must be a regular file")
                envelope = json.loads(source.read(), object_pairs_hook=self._strict_object)
            if not isinstance(envelope, dict) or set(envelope) != {"state", "sha256"}:
                raise ValueError("Invalid judge checkpoint envelope")
            state = envelope["state"]
            if hashlib.sha256(canonical_json_bytes(state)).hexdigest() != envelope["sha256"]:
                raise ValueError("Judge checkpoint integrity hash does not match")
            if not isinstance(state, dict) or set(state) != {
                "schemaVersion", "bindings", "cells", "inFlight"
            } or state["schemaVersion"] != "coaching-quality-judge-checkpoint.v1":
                raise ValueError("Invalid judge checkpoint state")
            if state["bindings"] != self._bindings:
                raise ValueError("Judge checkpoint bindings do not match")
            cells = state["cells"]
            if not isinstance(cells, dict):
                raise ValueError("Invalid judge checkpoint cells")
            in_flight = state["inFlight"]
            if in_flight is not None and (not isinstance(in_flight, str) or in_flight not in cells):
                raise ValueError("Invalid judge checkpoint in-flight attempt")
            for key, cell in cells.items():
                if key not in self._bindings["judgments"]:
                    raise ValueError("Unknown judge checkpoint judgment")
                if not isinstance(cell, dict) or set(cell) != {"output", "attempts"}:
                    raise ValueError("Invalid judge checkpoint cell")
                attempts = cell["attempts"]
                if not isinstance(attempts, list) or (not attempts and key != in_flight):
                    raise ValueError("Invalid judge checkpoint attempts")
                for index, attempt in enumerate(attempts):
                    if not isinstance(attempt, dict) or set(attempt) != {"status", "metrics"}:
                        raise ValueError("Invalid judge checkpoint attempt")
                    if attempt["status"] not in ("failed", "completed"):
                        raise ValueError("Invalid judge checkpoint attempt status")
                    if attempt["status"] == "completed" and index != len(attempts) - 1:
                        raise ValueError("Completed judge checkpoint judgment cannot be replaced")
                    self._validate_metrics(attempt["metrics"])
                completed = bool(attempts and attempts[-1]["status"] == "completed")
                if completed != (cell["output"] is not None) or (completed and key == in_flight):
                    raise ValueError("Invalid judge checkpoint completion")
                if completed:
                    self._validate_output(key, cell["output"])
            self._state = state
        except (OSError, UnicodeError, TypeError, json.JSONDecodeError) as error:
            raise ValueError("Cannot load judge checkpoint") from error

    def _save(self):
        self._reject_symlinks()
        state_bytes = canonical_json_bytes(self._state)
        envelope = {"state": self._state, "sha256": hashlib.sha256(state_bytes).hexdigest()}
        descriptor, name = tempfile.mkstemp(prefix=f".{self._path.name}.", dir=self._path.parent)
        temporary = Path(name)
        try:
            with os.fdopen(descriptor, "wb") as destination:
                destination.write(pretty_json_bytes(envelope))
                destination.flush()
                os.fsync(destination.fileno())
            os.replace(temporary, self._path)
            directory = os.open(self._path.parent, os.O_RDONLY)
            try:
                os.fsync(directory)
            finally:
                os.close(directory)
        finally:
            if temporary.exists():
                temporary.unlink()

    def _reject_symlinks(self):
        for path in (self._path, self._lock_path, *self._path.parents):
            if path.is_symlink():
                raise ValueError("Judge checkpoint paths must not be symlinks")

    @staticmethod
    def _strict_object(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError("Duplicate judge checkpoint field")
            result[key] = value
        return result

    @staticmethod
    def _validate_metrics(metrics):
        expected = empty_metrics()
        if not isinstance(metrics, dict) or set(metrics) != set(expected):
            raise ValueError("Invalid judge checkpoint metrics")
        usage = metrics["usage"]
        latency = metrics["latencyMilliseconds"]
        if (
            not isinstance(metrics["accountingComplete"], bool)
            or type(metrics["callCount"]) is not int or metrics["callCount"] != 1
            or isinstance(latency, bool) or not isinstance(latency, (int, float))
            or not math.isfinite(latency) or not 0 <= latency <= 86_400_000
            or not isinstance(usage, dict) or set(usage) != set(expected["usage"])
            or any(type(value) is not int or not 0 <= value <= 1_000_000_000 for value in usage.values())
        ):
            raise ValueError("Invalid judge checkpoint metrics")
        cost = metrics["estimatedCostUSD"]
        if not metrics["accountingComplete"] and cost is not None:
            raise ValueError("Invalid judge checkpoint incomplete cost")
        if cost is not None:
            try:
                if not isinstance(cost, str) or not Decimal(cost).is_finite() or Decimal(cost) < 0:
                    raise ValueError("Invalid judge checkpoint cost")
            except InvalidOperation:
                raise ValueError("Invalid judge checkpoint cost") from None
