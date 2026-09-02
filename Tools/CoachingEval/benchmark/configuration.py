"""Strict immutable configuration and price contracts for the benchmark."""

import hashlib
import json
import re
from dataclasses import dataclass
from decimal import Decimal, InvalidOperation
from pathlib import Path
from types import MappingProxyType
from typing import Any, Mapping

from CoachingServer.chess_native_compiler import compile_context, compile_follow_up_context


PROMPT_GENERATORS = {
    "chess-native-v13": (compile_context, compile_follow_up_context),
}
PROVIDERS = frozenset(("openai-responses-v1",))
RESPONSE_CONTRACTS = frozenset(("chess-native-v13",))
_SHA256 = re.compile(r"[0-9a-f]{64}\Z")
_CANDIDATE_KEYS = frozenset(
    (
        "schemaVersion",
        "id",
        "baseline",
        "provider",
        "model",
        "initialReasoningEffort",
        "followUpReasoningEffort",
        "conversationReuse",
        "maximumOutputTokens",
        "timeoutSeconds",
        "maximumAttempts",
        "systemPromptPath",
        "systemPromptSHA256",
        "userPromptGenerator",
        "responseContract",
        "pricingVersion",
    )
)
_JUDGE_KEYS = frozenset(
    (
        "schemaVersion",
        "id",
        "provider",
        "model",
        "reasoningEffort",
        "conversationReuse",
        "maximumOutputTokens",
        "timeoutSeconds",
        "systemPromptPath",
        "systemPromptSHA256",
        "calibrationPath",
        "calibrationSHA256",
        "reviewSeed",
    )
)


@dataclass(frozen=True)
class CandidateConfiguration:
    identifier: str
    baseline: bool
    provider: str
    model: str
    initial_reasoning_effort: str
    follow_up_reasoning_effort: str
    conversation_reuse: bool
    maximum_output_tokens: int
    timeout_seconds: float
    maximum_attempts: int
    system_prompt_path: Path
    system_prompt_sha256: str
    system_prompt: str
    user_prompt_generator: str
    response_contract: str
    pricing_version: str
    sha256: str
    raw: Mapping[str, Any]


@dataclass(frozen=True)
class JudgeConfiguration:
    identifier: str
    provider: str
    model: str
    reasoning_effort: str
    conversation_reuse: bool
    maximum_output_tokens: int
    timeout_seconds: float
    system_prompt_path: Path
    system_prompt_sha256: str
    system_prompt: str
    calibration_path: Path
    calibration_sha256: str
    review_seed: int
    sha256: str
    raw: Mapping[str, Any]


@dataclass(frozen=True)
class ModelPrice:
    uncached_input_per_million: Decimal
    cached_input_per_million: Decimal
    output_per_million: Decimal


@dataclass(frozen=True)
class PriceTable:
    version: str
    effective_date: str
    source_url: str
    models: Mapping[str, ModelPrice]
    sha256: str

    def estimate(self, model: str, usage: Mapping[str, int]) -> Decimal:
        if model not in self.models:
            raise ValueError(f"No price is pinned for model {model}")
        if not isinstance(usage, Mapping):
            raise ValueError("Usage must be an object")
        input_tokens = _nonnegative_usage(usage.get("inputTokens", 0), "inputTokens")
        cached_tokens = _nonnegative_usage(
            usage.get("cachedInputTokens", 0), "cachedInputTokens"
        )
        output_tokens = _nonnegative_usage(usage.get("outputTokens", 0), "outputTokens")
        _nonnegative_usage(usage.get("reasoningTokens", 0), "reasoningTokens")
        if cached_tokens > input_tokens:
            raise ValueError("Cached input tokens cannot exceed input tokens")
        price = self.models[model]
        million = Decimal(1_000_000)
        return (
            Decimal(input_tokens - cached_tokens) * price.uncached_input_per_million
            + Decimal(cached_tokens) * price.cached_input_per_million
            + Decimal(output_tokens) * price.output_per_million
        ) / million


def load_candidate(path: Path, repository_root: Path) -> CandidateConfiguration:
    raw, raw_bytes = _load_json(path)
    _exact_keys(raw, _CANDIDATE_KEYS, "Candidate")
    if raw["schemaVersion"] != "coaching-quality-candidate.v1":
        raise ValueError("Unsupported candidate schema")
    provider = _choice(raw["provider"], PROVIDERS, "provider")
    generator = _choice(raw["userPromptGenerator"], PROMPT_GENERATORS, "user prompt generator")
    contract = _choice(raw["responseContract"], RESPONSE_CONTRACTS, "response contract")
    prompt_path, prompt_sha, prompt_text = _load_pinned_text(
        repository_root, raw["systemPromptPath"], raw["systemPromptSHA256"], "System prompt"
    )
    return CandidateConfiguration(
        identifier=_string(raw["id"], "id"),
        baseline=_boolean(raw["baseline"], "baseline"),
        provider=provider,
        model=_string(raw["model"], "model"),
        initial_reasoning_effort=_reasoning(raw["initialReasoningEffort"]),
        follow_up_reasoning_effort=_reasoning(raw["followUpReasoningEffort"]),
        conversation_reuse=_boolean(raw["conversationReuse"], "conversationReuse"),
        maximum_output_tokens=_positive_int(raw["maximumOutputTokens"], "maximumOutputTokens"),
        timeout_seconds=float(_positive_number(raw["timeoutSeconds"], "timeoutSeconds")),
        maximum_attempts=_positive_int(raw["maximumAttempts"], "maximumAttempts"),
        system_prompt_path=prompt_path,
        system_prompt_sha256=prompt_sha,
        system_prompt=prompt_text,
        user_prompt_generator=generator,
        response_contract=contract,
        pricing_version=_string(raw["pricingVersion"], "pricingVersion"),
        sha256=hashlib.sha256(_canonical_bytes(raw)).hexdigest(),
        raw=_frozen_copy(raw),
    )


def load_judge(path: Path, repository_root: Path) -> JudgeConfiguration:
    raw, _raw_bytes = _load_json(path)
    _exact_keys(raw, _JUDGE_KEYS, "Judge")
    if raw["schemaVersion"] != "coaching-quality-judge.v1":
        raise ValueError("Unsupported judge schema")
    provider = _choice(raw["provider"], PROVIDERS, "provider")
    prompt_path, prompt_sha, prompt_text = _load_pinned_text(
        repository_root, raw["systemPromptPath"], raw["systemPromptSHA256"], "Judge prompt"
    )
    calibration_path, calibration_sha, _calibration_text = _load_pinned_text(
        repository_root,
        raw["calibrationPath"],
        raw["calibrationSHA256"],
        "Judge calibration",
    )
    review_seed = _positive_int(raw["reviewSeed"], "reviewSeed")
    return JudgeConfiguration(
        identifier=_string(raw["id"], "id"),
        provider=provider,
        model=_string(raw["model"], "model"),
        reasoning_effort=_reasoning(raw["reasoningEffort"]),
        conversation_reuse=_boolean(raw["conversationReuse"], "conversationReuse"),
        maximum_output_tokens=_positive_int(raw["maximumOutputTokens"], "maximumOutputTokens"),
        timeout_seconds=float(_positive_number(raw["timeoutSeconds"], "timeoutSeconds")),
        system_prompt_path=prompt_path,
        system_prompt_sha256=prompt_sha,
        system_prompt=prompt_text,
        calibration_path=calibration_path,
        calibration_sha256=calibration_sha,
        review_seed=review_seed,
        sha256=hashlib.sha256(_canonical_bytes(raw)).hexdigest(),
        raw=_frozen_copy(raw),
    )


def load_prices(path: Path) -> PriceTable:
    raw, _raw_bytes = _load_json(path)
    _exact_keys(
        raw,
        frozenset(("schemaVersion", "version", "effectiveDate", "sourceURL", "models")),
        "Price table",
    )
    if raw["schemaVersion"] != "coaching-quality-pricing.v1":
        raise ValueError("Unsupported pricing schema")
    models = raw["models"]
    if not isinstance(models, dict) or not models:
        raise ValueError("Pricing models must be a nonempty object")
    parsed = {}
    expected_keys = frozenset(
        ("uncachedInputPerMillion", "cachedInputPerMillion", "outputPerMillion")
    )
    for model, values in models.items():
        model = _string(model, "pricing model")
        if not isinstance(values, dict):
            raise ValueError("Model pricing must be an object")
        _exact_keys(values, expected_keys, "Model price")
        parsed[model] = ModelPrice(
            uncached_input_per_million=_nonnegative_decimal(
                values["uncachedInputPerMillion"], "uncached input price"
            ),
            cached_input_per_million=_nonnegative_decimal(
                values["cachedInputPerMillion"], "cached input price"
            ),
            output_per_million=_nonnegative_decimal(
                values["outputPerMillion"], "output price"
            ),
        )
    return PriceTable(
        version=_string(raw["version"], "version"),
        effective_date=_string(raw["effectiveDate"], "effectiveDate"),
        source_url=_string(raw["sourceURL"], "sourceURL"),
        models=MappingProxyType(parsed),
        sha256=hashlib.sha256(_canonical_bytes(raw)).hexdigest(),
    )


def _load_json(path: Path):
    path = Path(path)
    try:
        raw_bytes = path.read_bytes()
        raw = json.loads(raw_bytes.decode("utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise ValueError(f"Cannot load configuration: {path}") from error
    if not isinstance(raw, dict):
        raise ValueError("Configuration must be an object")
    return raw, raw_bytes


def _load_pinned_text(repository_root, relative_path, expected_sha, label):
    repository_root = Path(repository_root).resolve()
    relative_path = Path(_string(relative_path, f"{label} path"))
    if relative_path.is_absolute():
        raise ValueError(f"{label} path must be repository-relative")
    resolved = (repository_root / relative_path).resolve()
    try:
        resolved.relative_to(repository_root)
    except ValueError:
        raise ValueError(f"{label} path escapes repository root") from None
    try:
        data = resolved.read_bytes()
        text = data.decode("utf-8")
    except (OSError, UnicodeError) as error:
        raise ValueError(f"Cannot load {label.lower()}") from error
    expected_sha = _hash(expected_sha, f"{label} hash")
    actual_sha = hashlib.sha256(data).hexdigest()
    if actual_sha != expected_sha:
        raise ValueError(f"{label} hash does not match")
    return resolved, actual_sha, text


def _exact_keys(value, expected, label):
    if set(value) != set(expected):
        raise ValueError(f"{label} fields do not match the contract")


def _choice(value, choices, label):
    value = _string(value, label)
    if value not in choices:
        raise ValueError(f"Unsupported {label}: {value}")
    return value


def _string(value, label):
    if not isinstance(value, str) or not value:
        raise ValueError(f"{label} must be a nonempty string")
    return value


def _hash(value, label):
    value = _string(value, label)
    if _SHA256.fullmatch(value) is None:
        raise ValueError(f"{label} must be a lowercase SHA-256")
    return value


def _boolean(value, label):
    if not isinstance(value, bool):
        raise ValueError(f"{label} must be a boolean")
    return value


def _positive_int(value, label):
    if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
        raise ValueError(f"{label} must be a positive integer")
    return value


def _positive_number(value, label):
    if isinstance(value, bool) or not isinstance(value, (int, float)) or value <= 0:
        raise ValueError(f"{label} must be positive")
    return value


def _reasoning(value):
    return _choice(value, frozenset(("none", "low", "medium", "high")), "reasoning effort")


def _nonnegative_decimal(value, label):
    if not isinstance(value, str):
        raise ValueError(f"{label} must be a decimal string")
    try:
        result = Decimal(value)
    except InvalidOperation as error:
        raise ValueError(f"{label} must be a decimal string") from error
    if not result.is_finite() or result < 0:
        raise ValueError(f"{label} cannot be negative")
    return result


def _nonnegative_usage(value, label):
    if isinstance(value, bool) or not isinstance(value, int) or value < 0:
        raise ValueError(f"{label} must be a nonnegative integer")
    return value


def _canonical_bytes(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode("utf-8")


def _frozen_copy(value):
    copied = json.loads(json.dumps(value, sort_keys=True))
    return _deep_freeze(copied)


def _deep_freeze(value):
    if isinstance(value, dict):
        return MappingProxyType({key: _deep_freeze(item) for key, item in value.items()})
    if isinstance(value, list):
        return tuple(_deep_freeze(item) for item in value)
    return value
