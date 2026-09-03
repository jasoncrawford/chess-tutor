"""Execute immutable coaching benchmark candidate matrices."""

import hashlib
import json
import math
import os
import re
import time
import uuid
from pathlib import Path
from typing import Any, Mapping, Sequence

from Tools.CoachingEval.benchmark.configuration import PROMPT_GENERATORS
from Tools.CoachingEval.chess_native_response import (
    ChessNativeResponseContract,
    ChessNativeResponseValidationError,
)
from Tools.CoachingEval.openai_responses import OpenAIResponsesError


_TRACE_MARKER = re.compile(r"<\s*/?\s*think\b|reasoning_content", re.IGNORECASE)
_MAXIMUM_METRIC = 1_000_000_000


def run_candidates(
    *,
    corpus,
    configurations: Sequence,
    mode: str,
    destination: Path,
    provider_factory,
    include_holdout: bool = False,
    price_table=None,
    diagnostic_subset: bool = False,
):
    """Run one fully preflighted quick or comparison matrix and publish atomically."""
    destination = Path(destination)
    if os.path.lexists(destination):
        raise ValueError(f"Refusing to overwrite benchmark run: {destination}")
    configurations = tuple(configurations)
    if not configurations:
        raise ValueError("At least one candidate configuration is required")
    identifiers = [configuration.identifier for configuration in configurations]
    if len(set(identifiers)) != len(identifiers):
        raise ValueError("Candidate configuration IDs must be unique")
    if mode not in ("quick", "comparison"):
        raise ValueError("Benchmark mode must be quick or comparison")
    if mode == "comparison" and not any(configuration.baseline for configuration in configurations):
        raise ValueError("Comparison mode requires a baseline configuration")
    _verify_corpus_binding(corpus)
    repetitions = 1 if mode == "quick" else 3
    turns = corpus.select(include_holdout=include_holdout)
    _validate_selected_groups(turns)

    preflight = _preflight(configurations, turns, repetitions)
    clients = {
        configuration.identifier: provider_factory(configuration)
        for configuration in configurations
    }
    records = []
    transcripts = {}
    prior_by_sequence = {}
    for cell in preflight:
        configuration = cell["configuration"]
        turn = cell["turn"]
        sequence_key = (
            configuration.identifier,
            cell["repetition"],
            turn.group_id,
        )
        prior = prior_by_sequence.get(sequence_key)
        if turn.step_index > 1 and prior is not None and not prior["valid"]:
            record = _base_record(cell)
            record["generationStatus"] = "blockedByPriorTurn"
            record["mechanicalValidation"] = {
                "valid": False,
                "categories": ["blockedByPriorTurn"],
            }
            records.append(record)
            prior_by_sequence[sequence_key] = {"valid": False, "responseID": None}
            continue

        previous_response_id = None
        if turn.step_index > 1 and configuration.conversation_reuse and prior is not None:
            previous_response_id = prior["responseID"]
        record = _execute_cell(
            cell,
            clients[configuration.identifier],
            previous_response_id=previous_response_id,
            price_table=price_table,
        )
        records.append(record)
        if _is_sequence(turns, turn.group_id):
            prior_by_sequence[sequence_key] = {
                "valid": record["mechanicalValidation"]["valid"],
                "responseID": record.get("providerResponseID") or None,
            }
        if record["mechanicalValidation"]["valid"]:
            transcripts[_transcript_name(record)] = _transcript(record)

    manifest = _manifest(
        corpus,
        configurations,
        mode,
        include_holdout,
        records,
        diagnostic_subset,
    )
    _publish(destination, manifest, records, transcripts)
    return manifest


def _preflight(configurations, turns, repetitions):
    cells = []
    sequence_ids = _sequence_ids(turns)
    for configuration in configurations:
        compilers = PROMPT_GENERATORS[configuration.user_prompt_generator]
        for repetition in range(1, repetitions + 1):
            for turn in turns:
                use_follow_up = (
                    turn.group_id in sequence_ids
                    and turn.step_index > 1
                    and configuration.conversation_reuse
                )
                compiler = compilers[1] if use_follow_up else compilers[0]
                compilation = compiler(turn.request, "tutor-v13")
                contract = ChessNativeResponseContract.from_markdown(compilation.markdown)
                schema = contract.json_schema()
                json.dumps(schema, sort_keys=True)
                cells.append(
                    {
                        "configuration": configuration,
                        "turn": turn,
                        "repetition": repetition,
                        "compilation": compilation,
                        "contract": contract,
                        "schema": schema,
                        "reasoningEffort": (
                            configuration.follow_up_reasoning_effort
                            if use_follow_up
                            else configuration.initial_reasoning_effort
                        ),
                    }
                )
    return cells


def _execute_cell(cell, client, *, previous_response_id, price_table):
    configuration = cell["configuration"]
    record = _base_record(cell)
    record["previousResponseIDUsed"] = previous_response_id
    response = None
    final_category = "providerError"
    final_http_status = None
    started = time.monotonic()
    for attempt in range(1, configuration.maximum_attempts + 1):
        record["attemptCount"] = attempt
        try:
            response = client.complete(
                system_prompt=configuration.system_prompt,
                user_prompt=cell["compilation"].markdown,
                schema=cell["schema"],
                model=configuration.model,
                reasoning_effort=cell["reasoningEffort"],
                maximum_output_tokens=configuration.maximum_output_tokens,
                timeout=configuration.timeout_seconds,
                previous_response_id=previous_response_id,
                store=False,
            )
            break
        except OpenAIResponsesError as error:
            final_category = error.category
            final_http_status = _bounded_http_status(error.http_status)
        except Exception:
            final_category = "providerError"
            final_http_status = None
    record["latencyMilliseconds"] = _bounded_float((time.monotonic() - started) * 1000)
    if response is None:
        record["generationStatus"] = final_category
        record["providerHTTPStatus"] = final_http_status
        record["mechanicalValidation"] = {
            "valid": False,
            "categories": [final_category],
        }
        return record

    response_id = _bounded_identifier(response.get("id"))
    provider_model = _bounded_identifier(response.get("model"))
    output = response.get("output_text")
    usage = _usage(response.get("usage"))
    record["providerResponseID"] = response_id
    record["providerModel"] = provider_model
    record["usage"] = usage
    if price_table is not None:
        record["candidateCostUSD"] = str(price_table.estimate(configuration.model, usage))
    if not isinstance(output, str) or not output or _TRACE_MARKER.search(output):
        record["generationStatus"] = "invalid"
        record["mechanicalValidation"] = {
            "valid": False,
            "categories": ["invalidResponse"],
        }
        return record
    try:
        parsed = cell["contract"].parse_and_validate(output)
    except ChessNativeResponseValidationError as error:
        categories = list(error.categories)
        record["generationStatus"] = "invalid"
        record["mechanicalValidation"] = {"valid": False, "categories": categories}
        return record
    except ValueError:
        record["generationStatus"] = "invalid"
        record["mechanicalValidation"] = {
            "valid": False,
            "categories": ["validation"],
        }
        return record

    record["generationStatus"] = "completed"
    record["sanitizedOutput"] = output
    record["parsedTurn"] = parsed
    record["mechanicalValidation"] = {"valid": True, "categories": []}
    return record


def _base_record(cell):
    configuration = cell["configuration"]
    turn = cell["turn"]
    repetition = cell["repetition"]
    user_prompt = cell["compilation"].markdown
    return {
        "schemaVersion": "coaching-quality-candidate-record.v1",
        "cellID": f"{configuration.identifier}|{turn.identifier}|r{repetition}",
        "configurationID": configuration.identifier,
        "caseID": turn.identifier,
        "groupID": turn.group_id,
        "stepIndex": turn.step_index,
        "split": turn.split,
        "category": turn.category,
        "repetition": repetition,
        "requestSHA256": _sha256(_canonical_json_bytes(turn.request)),
        "systemPromptSHA256": configuration.system_prompt_sha256,
        "userPrompt": user_prompt,
        "userPromptSHA256": _sha256(user_prompt.encode("utf-8")),
        "providerResponseID": "",
        "providerModel": "",
        "providerHTTPStatus": None,
        "sanitizedOutput": "",
        "parsedTurn": None,
        "mechanicalValidation": {"valid": False, "categories": ["notRun"]},
        "generationStatus": "notRun",
        "usage": {
            "inputTokens": 0,
            "cachedInputTokens": 0,
            "outputTokens": 0,
            "reasoningTokens": 0,
            "totalTokens": 0,
        },
        "latencyMilliseconds": 0.0,
        "timeToFirstTokenMilliseconds": None,
        "attemptCount": 0,
        "previousResponseIDUsed": None,
        "candidateCostUSD": None,
    }


def _bounded_http_status(value):
    if isinstance(value, bool) or not isinstance(value, int):
        return None
    return value if 100 <= value <= 599 else None


def _manifest(
    corpus,
    configurations,
    mode,
    include_holdout,
    records,
    diagnostic_subset,
):
    resolved = []
    for configuration in configurations:
        resolved.append(
            {
                "id": configuration.identifier,
                "configurationSHA256": configuration.sha256,
                "baseline": configuration.baseline,
                "provider": configuration.provider,
                "model": configuration.model,
                "initialReasoningEffort": configuration.initial_reasoning_effort,
                "followUpReasoningEffort": configuration.follow_up_reasoning_effort,
                "conversationReuse": configuration.conversation_reuse,
                "maximumOutputTokens": configuration.maximum_output_tokens,
                "timeoutSeconds": configuration.timeout_seconds,
                "maximumAttempts": configuration.maximum_attempts,
                "systemPromptSHA256": configuration.system_prompt_sha256,
                "systemPrompt": configuration.system_prompt,
                "userPromptGenerator": configuration.user_prompt_generator,
                "responseContract": configuration.response_contract,
                "pricingVersion": configuration.pricing_version,
            }
        )
    return {
        "schemaVersion": "coaching-quality-candidate-run.v1",
        "mode": mode,
        "diagnosticSubset": diagnostic_subset,
        "includeHoldout": include_holdout,
        "corpusSHA256": corpus.sha256,
        "sourceGitSHA": corpus.source_git_sha,
        "configurations": resolved,
        "recordIDs": [record["cellID"] for record in records],
        "recordsSHA256": _sha256(_jsonl_bytes(records)),
        "summary": {
            "recordCount": len(records),
            "validCount": sum(record["mechanicalValidation"]["valid"] for record in records),
            "failedCount": sum(not record["mechanicalValidation"]["valid"] for record in records),
        },
    }


def _publish(destination, manifest, records, transcripts):
    destination = Path(destination)
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.parent / f".{destination.name}.tmp-{uuid.uuid4()}"
    temporary.mkdir()
    try:
        records_bytes = _jsonl_bytes(records)
        (temporary / "records.jsonl").write_bytes(records_bytes)
        transcript_root = temporary / "transcripts"
        transcript_root.mkdir()
        for name, content in transcripts.items():
            (transcript_root / name).write_text(content, encoding="utf-8")
        (temporary / "run-manifest.json").write_bytes(_pretty_json_bytes(manifest))
        temporary.rename(destination)
    except Exception:
        _remove_tree(temporary)
        raise


def _validate_selected_groups(turns):
    groups = {}
    for turn in turns:
        groups.setdefault(turn.group_id, []).append(turn)
    for group in groups.values():
        if len(group) not in (1, 3):
            raise ValueError("Selected benchmark contains a partial sequence")
        if len(group) == 3 and [turn.step_index for turn in group] != [1, 2, 3]:
            raise ValueError("Selected benchmark sequence is out of order")


def _verify_corpus_binding(corpus):
    if corpus.raw_cases:
        raw_ids = [value.get("id") if isinstance(value, Mapping) else None for value in corpus.raw_cases]
        turn_ids = [turn.identifier for turn in corpus.turns]
        if raw_ids != turn_ids:
            raise ValueError("Loaded benchmark corpus order changed after validation")
    cases_path = Path(corpus.root) / "cases.jsonl"
    if cases_path.exists():
        if _sha256(cases_path.read_bytes()) != corpus.sha256:
            raise ValueError("Benchmark corpus bytes changed after validation")


def _sequence_ids(turns):
    counts = {}
    for turn in turns:
        counts[turn.group_id] = counts.get(turn.group_id, 0) + 1
    return frozenset(group_id for group_id, count in counts.items() if count == 3)


def _is_sequence(turns, group_id):
    return sum(turn.group_id == group_id for turn in turns) == 3


def _usage(value):
    value = value if isinstance(value, Mapping) else {}
    return {
        "inputTokens": _bounded_int(value.get("input_tokens")),
        "cachedInputTokens": _bounded_int(value.get("cached_input_tokens")),
        "outputTokens": _bounded_int(value.get("output_tokens")),
        "reasoningTokens": _bounded_int(value.get("reasoning_tokens")),
        "totalTokens": _bounded_int(value.get("total_tokens")),
    }


def _bounded_int(value):
    if isinstance(value, bool) or not isinstance(value, int) or value < 0:
        return 0
    return min(value, _MAXIMUM_METRIC)


def _bounded_float(value):
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return 0.0
    value = float(value)
    if not math.isfinite(value) or value < 0:
        return 0.0
    return min(value, 86_400_000.0)


def _bounded_identifier(value):
    if not isinstance(value, str) or not value:
        return ""
    return value[:256]


def _transcript_name(record):
    return f"{record['configurationID']}--{record['caseID']}--r{record['repetition']}.md"


def _transcript(record):
    return (
        f"# {record['cellID']}\n\n"
        "## User prompt\n\n"
        f"{record['userPrompt']}\n\n"
        "## Validated response\n\n"
        f"```json\n{record['sanitizedOutput']}\n```\n"
    )


def _canonical_json_bytes(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def _pretty_json_bytes(value):
    return (json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False) + "\n").encode("utf-8")


def _jsonl_bytes(values):
    return b"".join(_canonical_json_bytes(value) + b"\n" for value in values)


def _sha256(data):
    return hashlib.sha256(data).hexdigest()


def _remove_tree(path):
    if not path.exists():
        return
    for child in path.iterdir():
        if child.is_dir():
            _remove_tree(child)
        else:
            child.unlink()
    path.rmdir()
