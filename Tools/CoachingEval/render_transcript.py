#!/usr/bin/env python3
"""Render one trace-free coaching evaluation record for human inspection."""

import json
import os
import re


_FORBIDDEN_MARKERS = ("<think", "reasoning_content", "reasoningcontent")
_EMPTY_TEMPLATE_THINKING_CONTROL = re.compile(
    r"<\s*think\b[^>]*>\s*<\s*/\s*think\s*>",
    re.IGNORECASE,
)


def _json_block(value):
    return "```json\n" + json.dumps(value, indent=2, sort_keys=True) + "\n```"


def _text_block(value):
    fence = "```"
    while fence in value:
        fence += "`"
    return f"{fence}text\n{value}\n{fence}"


def _table(rows, columns):
    lines = [
        "| " + " | ".join(columns) + " |",
        "| " + " | ".join("---" for _ in columns) + " |",
    ]
    for row in rows:
        lines.append(
            "| "
            + " | ".join(str(row.get(column, "")).replace("|", "\\|") for column in columns)
            + " |"
        )
    if len(lines) == 2:
        lines.append("| " + " | ".join("—" for _ in columns) + " |")
    return "\n".join(lines)


def _assert_trace_and_secret_free(transcript, environment):
    lowered = _EMPTY_TEMPLATE_THINKING_CONTROL.sub("", transcript).lower()
    for marker in _FORBIDDEN_MARKERS:
        if marker in lowered:
            raise ValueError(f"Transcript contains forbidden trace marker: {marker}")
    for key, value in (environment or {}).items():
        if not isinstance(value, str) or not value:
            continue
        if not any(marker in key.upper() for marker in ("TOKEN", "KEY", "SECRET", "PASSWORD")):
            continue
        if value in transcript:
            raise ValueError(f"Transcript contains a secret environment value from {key}")


def render_transcript(
    record, *, rendered_prompt, repair_rendered_prompt=None, environment=None
):
    """Return the fixed-order readable transcript for one evaluation attempt."""
    compilation = record.get("evaluationCase", {}).get("compactContext", {})
    markdown = compilation.get("markdown", "")
    response = record.get("rawFinalContent") or "(no model response)"
    rendered_prompt_section = _text_block(rendered_prompt)
    if repair_rendered_prompt is not None:
        rendered_prompt_section = (
            "### First attempt\n\n"
            + _text_block(rendered_prompt)
            + "\n\n### Repair attempt\n\n"
            + _text_block(repair_rendered_prompt)
        )
    response_section = _text_block(response)
    if record.get("repairAttempted"):
        response_section = (
            "### First attempt\n\n"
            + _text_block(record.get("firstAttemptRawFinalContent") or "(no model response)")
            + "\n\n### Repair attempt\n\n"
            + _text_block(record.get("repairRawFinalContent") or "(no model response)")
        )
    identity = {
        key: record.get(key)
        for key in (
            "caseID",
            "caseSplit",
            "modelID",
            "mode",
            "seed",
            "requestID",
            "positionRevision",
            "modelArtifactSHA256",
            "llamaCppVersion",
            "evaluatorPromptVersion",
        )
    }
    validation = {
        "generationStatus": record.get("generationStatus"),
        "firstAttempt": record.get("firstAttemptValidation"),
        "repairAttempted": record.get("repairAttempted"),
        "repair": record.get("repairValidation"),
        "aliasRestorationErrors": record.get("aliasRestorationErrors", []),
        "errors": record.get("errors", []),
    }
    tokens = {
        "renderedPromptTokens": record.get("renderedPromptTokens"),
        "promptTokens": record.get("promptTokens"),
        "outputTokens": record.get("outputTokens"),
        "latencyMilliseconds": record.get("latencyMilliseconds"),
    }
    transcript = "\n\n".join(
        [
            "# Coaching evaluation transcript",
            "## Identity and provenance\n\n" + _json_block(identity),
            "## Model input Markdown\n\n" + _text_block(markdown),
            "## Exact rendered prompt\n\n" + rendered_prompt_section,
            "## Model response\n\n" + response_section,
            "## Alias turn\n\n" + _json_block(record.get("aliasTurn")),
            "## Stable-ID turn\n\n" + _json_block(record.get("stableTurn")),
            "## Validation\n\n" + _json_block(validation),
            "## Evidence accounting\n\n### Included bindings\n\n"
            + _table(
                compilation.get("referenceBindings", []),
                ("alias", "stableID", "category"),
            )
            + "\n\n### Omitted evidence\n\n"
            + _table(
                compilation.get("omissions", []),
                ("stableID", "category", "reason"),
            ),
            "## Tokens and timing\n\n"
            + f"Rendered prompt tokens: {int(record.get('renderedPromptTokens') or 0):,}\n\n"
            + _json_block(tokens),
        ]
    ) + "\n"
    _assert_trace_and_secret_free(transcript, os.environ if environment is None else environment)
    return transcript
