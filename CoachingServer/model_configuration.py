"""Strict immutable configuration for hosted coaching model execution."""

from __future__ import annotations

import hashlib
import json
import math
import re
from collections.abc import Mapping
from dataclasses import dataclass
from pathlib import Path
from types import MappingProxyType
from typing import Any


_CONFIGURATION_FIELDS = frozenset(
    (
        "schemaVersion",
        "provider",
        "model",
        "initialReasoningEffort",
        "tacticalFollowUpReasoningEffort",
        "simpleFollowUpReasoningEffort",
        "conversationReuse",
        "store",
        "maximumOutputTokens",
        "timeoutSeconds",
        "maximumAttempts",
        "systemPromptPath",
        "systemPromptSHA256",
        "userPromptGenerator",
        "responseContract",
    )
)
_PROVIDERS = frozenset(("openai-responses-v1",))
_PROMPT_GENERATORS = {"chess-native-v13": "tutor-v13"}
_RESPONSE_CONTRACTS = frozenset(("chess-native-v13",))
_REASONING_EFFORTS = frozenset(("none", "low", "medium", "high"))
_TACTICAL_FOLLOW_UP_EVENTS = frozenset(
    ("moveStaged", "moveReplaced", "squareInspected")
)
_SHA256 = re.compile(r"[0-9a-f]{64}\Z")


@dataclass(frozen=True)
class HostedModelConfiguration:
    path: Path
    provider: str
    model: str
    initial_reasoning_effort: str
    tactical_follow_up_reasoning_effort: str
    simple_follow_up_reasoning_effort: str
    conversation_reuse: bool
    store: bool
    maximum_output_tokens: int
    timeout_seconds: float
    maximum_attempts: int
    system_prompt_path: Path
    system_prompt_sha256: str
    system_prompt: str
    user_prompt_generator: str
    prompt_version: str
    response_contract: str
    sha256: str
    raw: Mapping[str, Any]

    @classmethod
    def load(
        cls,
        path: Path,
        repository_root: Path,
    ) -> "HostedModelConfiguration":
        repository_root = Path(repository_root).resolve()
        resolved_path = _repository_path(path, repository_root, "Configuration")
        try:
            raw_bytes = resolved_path.read_bytes()
            raw = json.loads(
                raw_bytes.decode("utf-8"),
                object_pairs_hook=_strict_object,
                parse_constant=_reject_json_constant,
            )
        except (OSError, UnicodeError, json.JSONDecodeError) as error:
            raise ValueError(f"Cannot load model configuration: {resolved_path}") from error
        if not isinstance(raw, dict):
            raise ValueError("Model configuration must be an object")
        _exact_fields(raw, _CONFIGURATION_FIELDS, "Model configuration")
        if raw["schemaVersion"] != "hosted-coaching-model.v1":
            raise ValueError("Unsupported hosted model configuration schema")

        provider = _choice(raw["provider"], _PROVIDERS, "provider")
        generator = _choice(
            raw["userPromptGenerator"],
            frozenset(_PROMPT_GENERATORS),
            "user prompt generator",
        )
        response_contract = _choice(
            raw["responseContract"],
            _RESPONSE_CONTRACTS,
            "response contract",
        )
        conversation_reuse = _boolean(raw["conversationReuse"], "conversationReuse")
        store = _boolean(raw["store"], "store")
        if conversation_reuse and not store:
            raise ValueError("Conversation reuse requires response storage")
        prompt_path, prompt_sha256, system_prompt = _load_pinned_prompt(
            repository_root,
            raw["systemPromptPath"],
            raw["systemPromptSHA256"],
        )
        return cls(
            path=resolved_path,
            provider=provider,
            model=_string(raw["model"], "model"),
            initial_reasoning_effort=_reasoning(raw["initialReasoningEffort"]),
            tactical_follow_up_reasoning_effort=_reasoning(
                raw["tacticalFollowUpReasoningEffort"]
            ),
            simple_follow_up_reasoning_effort=_reasoning(
                raw["simpleFollowUpReasoningEffort"]
            ),
            conversation_reuse=conversation_reuse,
            store=store,
            maximum_output_tokens=_positive_int(
                raw["maximumOutputTokens"], "maximumOutputTokens"
            ),
            timeout_seconds=float(
                _positive_number(raw["timeoutSeconds"], "timeoutSeconds")
            ),
            maximum_attempts=_positive_int(raw["maximumAttempts"], "maximumAttempts"),
            system_prompt_path=prompt_path,
            system_prompt_sha256=prompt_sha256,
            system_prompt=system_prompt,
            user_prompt_generator=generator,
            prompt_version=_PROMPT_GENERATORS[generator],
            response_contract=response_contract,
            sha256=hashlib.sha256(raw_bytes).hexdigest(),
            raw=_freeze(raw),
        )

    def reasoning_effort(
        self,
        request: Mapping[str, object],
        is_follow_up: bool,
    ) -> str:
        if not is_follow_up:
            return self.initial_reasoning_effort
        interaction = request["interaction"]
        latest_event = interaction["latestEvent"]
        kind = latest_event["kind"]
        references = latest_event["referencedIDs"]
        if kind in _TACTICAL_FOLLOW_UP_EVENTS:
            return self.tactical_follow_up_reasoning_effort
        if kind == "actionChosen" and "action:hint" in references:
            return self.tactical_follow_up_reasoning_effort
        return self.simple_follow_up_reasoning_effort


def _repository_path(path: Path, repository_root: Path, label: str) -> Path:
    path = Path(path)
    resolved = path.resolve() if path.is_absolute() else (repository_root / path).resolve()
    try:
        resolved.relative_to(repository_root)
    except ValueError:
        raise ValueError(f"{label} path escapes repository root") from None
    return resolved


def _load_pinned_prompt(repository_root, relative_path, expected_sha):
    relative_path = Path(_string(relative_path, "systemPromptPath"))
    if relative_path.is_absolute():
        raise ValueError("System prompt path must be repository-relative")
    resolved = _repository_path(relative_path, repository_root, "System prompt")
    try:
        prompt_bytes = resolved.read_bytes()
        prompt = prompt_bytes.decode("utf-8")
    except (OSError, UnicodeError) as error:
        raise ValueError("Cannot load system prompt") from error
    if not prompt.strip():
        raise ValueError("System prompt must be nonempty")
    expected_sha = _hash(expected_sha, "systemPromptSHA256")
    actual_sha = hashlib.sha256(prompt_bytes).hexdigest()
    if actual_sha != expected_sha:
        raise ValueError("System prompt hash does not match")
    return resolved, actual_sha, prompt


def _strict_object(pairs):
    value = {}
    for key, child in pairs:
        if key in value:
            raise ValueError(f"Duplicate configuration field: {key}")
        value[key] = child
    return value


def _reject_json_constant(_value):
    raise ValueError("Invalid JSON constant")


def _exact_fields(value, expected, label):
    if set(value) != set(expected):
        raise ValueError(f"{label} fields do not match the contract")


def _string(value, label):
    if not isinstance(value, str) or not value:
        raise ValueError(f"{label} must be a nonempty string")
    return value


def _choice(value, choices, label):
    value = _string(value, label)
    if value not in choices:
        raise ValueError(f"Unsupported {label}: {value}")
    return value


def _reasoning(value):
    return _choice(value, _REASONING_EFFORTS, "reasoning effort")


def _boolean(value, label):
    if not isinstance(value, bool):
        raise ValueError(f"{label} must be a boolean")
    return value


def _positive_int(value, label):
    if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
        raise ValueError(f"{label} must be a positive integer")
    return value


def _positive_number(value, label):
    if (
        isinstance(value, bool)
        or not isinstance(value, (int, float))
        or not math.isfinite(value)
        or value <= 0
    ):
        raise ValueError(f"{label} must be positive")
    return value


def _hash(value, label):
    value = _string(value, label)
    if _SHA256.fullmatch(value) is None:
        raise ValueError(f"{label} must be a lowercase SHA-256")
    return value


def _freeze(value):
    copied = json.loads(json.dumps(value, sort_keys=True))
    return _deep_freeze(copied)


def _deep_freeze(value):
    if isinstance(value, dict):
        return MappingProxyType(
            {key: _deep_freeze(child) for key, child in value.items()}
        )
    if isinstance(value, list):
        return tuple(_deep_freeze(child) for child in value)
    return value
