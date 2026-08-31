# Chess coaching consistency comparison

Date: 2026-08-30

## Result

The small comparison answered both open questions clearly:

- GPT-5.6 Sol remained strong. The two new samples for each of the four hard cases were all mechanically valid and useful. Combined with the first funded pilot, the model produced 12/12 good hard-case responses across three samples per case.
- Qwen3 1.7B followed the strict JSON grammar on all eight frozen cases, but it did not provide usable coaching. It ignored urgent facts, confused selections with moves, echoed action identifiers as child-facing copy, and made factual chess errors.

This strengthens the hosted-first product direction. Qwen3 1.7B is not a plausible offline fallback for the current prompt and quality bar. The next work should design the stateless hosted endpoint and app-side thinking/error behavior, not run a broad model matrix.

## Frozen comparison

Both runs used the exact same deterministic prompt packet:

- Prompt version: `tutor-v6`
- Source manifest SHA-256: `80eb1b8f5b57ea9fc04609909922ed1377e4dd702feb0e178a070aba4d3e15c7`
- Examples inventory SHA-256: `8d9d28d904d060da791747083222c74a3ae29c87ec594792916f1dced757c75f`
- System prompt SHA-256: `0f434c5a7b4889442fc74f5846037d96a2332e479809e68790ee6dcebc1a6051`
- No examples, prompt mutation, retry, repair, or hidden data
- Exact request-specific `message`, `actions`, and `focus` validation

### Hosted consistency settings

- Model: `gpt-5.6-sol`
- Reasoning effort: `high`
- Maximum output tokens: 2,048
- Cases: 02, 05, 06, and 07
- New samples: 2 per case; 8 serial calls total
- Storage: disabled (`store: false`)

Artifact directory:

`.coaching-eval/runs/gpt-5.6-sol/hosted-tutor-v6-consistency-20260830`

- Run manifest SHA-256: `b8d8579f98cd635a7bbd7623ffe3d8dd732db28e9b32de8777c5f9d5ddc0c0ef`
- Review SHA-256: `ca108295488d50ba161f9ea6bcc8ce7603c75b393b1b4194e7ce25f973da602a`
- Valid responses: 8/8
- Provider errors: 0
- Input tokens: 6,614 total
- Output tokens: 4,108 total, including 3,585 reasoning tokens
- Total tokens: 10,722
- Latency: 3.60–19.25 seconds; median 6.90 seconds

### Local Qwen settings

- Model: `qwen3-1.7b-q4_k_m`
- Quantization: Q4_K_M
- Model bytes: 1,282,439,264
- Model SHA-256: `d2387ca2dbfee2ffabce7120d3770dadca0b293052bc2f0e138fdc940d9bc7b5`
- Resolved revision: `daeb8e2d528a760970442092f6bf1e55c3b659eb`
- Runtime: llama.cpp b10516, commit `b95502ba9aa0eb73a2f4fc8878d7fbe6a847a0b9`
- Mode: bounded thinking
- Seed: 1103
- Temperature: 0.2
- Top-p: 0.95
- Maximum output tokens: 512

Artifact directory:

`.coaching-eval/chess-native-pilot/qwen3-1.7b-seed-1103-tutor-v6-v1`

- Run manifest SHA-256: `d34f0f7a7703b431a97b856b5c256fed33986876d6e6426f93ed32fd70d49715`
- Review SHA-256: `92bc2e86b1c574a132fd45c9a8171803fb3231f8558f0efdde4528c59ba5de07`
- Valid responses: 8/8 mechanically
- Provider errors: 0
- Rendered prompt size: 607–695 tokens
- Output tokens: 656 total
- Latency: 1.84–3.68 seconds; median 2.00 seconds

## Hosted hard-case consistency

All twelve hosted samples—the original funded response plus the two new responses below—were factually sound, stage-aware, single-purpose, and usable without editing.

### Case 02: attacked piece

Sample 2:

```json
{"message":"The black pawn is attacking your knight. Can you move the knight somewhere safe?","actions":[],"focus":[{"type":"square","square":"e4"},{"type":"square","square":"f3"}]}
```

Sample 3:

```json
{"message":"The black pawn is attacking your knight. Find a safe square where the knight can jump.","actions":[],"focus":[{"type":"square","square":"e4"},{"type":"square","square":"f3"}]}
```

Both infer the pawn attack from the FEN and leave the destination for the child to discover.

### Case 05: tactical reply

Sample 2:

```json
{"message":"Careful—the black pawn can capture your bishop there. Can you find a safer move?","actions":["tryAnotherMove"],"focus":[{"type":"move","from":"c4","to":"b5"},{"type":"move","from":"a6","to":"b5"}]}
```

Sample 3:

```json
{"message":"Careful! The pawn can capture your bishop there. Try another move.","actions":["tryAnotherMove"],"focus":[{"type":"move","from":"a6","to":"b5"}]}
```

Both identify the exact immediate reply and stay on the tentative-move decision.

### Case 06: inspected opponent reply

Sample 2:

```json
{"message":"The black queen is eyeing your center pawn. Your knight move would protect it. Shall we play it?","actions":["playMove","tryAnotherMove"],"focus":[{"type":"move","from":"h4","to":"e4"},{"type":"move","from":"b1","to":"c3"}]}
```

Sample 3:

```json
{"message":"Good spotting! Your knight move guards the center pawn from that queen. Ready to play it?","actions":["playMove","tryAnotherMove"],"focus":[{"type":"move","from":"b1","to":"c3"},{"type":"move","from":"h4","to":"e4"}]}
```

Both follow the child's queen tap, connect the inspected `Qxe4+` reply to the tentative knight move, and return to the current move decision. The original sample instead explored `Qxf2+`; all three are legitimate readings of the supplied immediate replies.

### Case 07: answering check

Sample 2:

```json
{"message":"That blocks the check. Before choosing, can the black bishop capture your bishop there?","actions":["tryAnotherMove"],"focus":[{"type":"move","from":"b4","to":"d2"}]}
```

Sample 3:

```json
{"message":"Before deciding, notice: the black bishop can capture your bishop and give check again.","actions":["tryAnotherMove"],"focus":[{"type":"move","from":"b4","to":"d2"}]}
```

Both correctly distinguish a legal block from a good move and identify `Bxd2+` without mixing in another coaching stage.

## Qwen3 1.7B responses

The grammar made every response parseable, but none met the full tutoring bar.

### 01 — Quiet help

```json
{"message":"help me find a move","actions":["hint"],"focus":[{"type":"square","square":"e5"}]}
```

Generic and backwards: the tutor asks the child to help it, with an unexplained square.

### 02 — Attacked piece

```json
{"message":"help me find a move","actions":["hint"],"focus":[{"type":"square","square":"e5"}] }
```

Severe stage failure. It ignores the attacked knight and repeats the generic opening response.

### 03 — Selected piece

```json
{
  "message": "Great move! Your knight is ready to support the queen. Let's see if it can help control the中心.",
  "actions": ["hint"],
  "focus": [{"type": "square", "square": "d4"}, {"type": "square", "square": "e5"}, {"type": "move", "from": "f3", "to": "d4"}]
}
```

It treats a selection as a completed move, supplies a dubious reason, and emits a non-English fragment.

### 04 — Replaced tentative move

```json
{"message":"tryAnotherMove","actions":["playMove","tryAnotherMove"],"focus":[{"type":"move","from":"g1","to":"f3"}]}
```

The focus follows the replacement, but the child-facing message is merely an internal action identifier.

### 05 — Tactical reply

```json
{"message":"a6 is a good square to protect.","actions":["hint"],"focus":[{"type":"square","square":"a6"}]}
```

Severe chess/perspective error. The black pawn on a6 is the piece that can capture the child's bishop; it is not a safe square or a protective idea for White.

### 06 — Inspected opponent reply

```json
{"message":"tryAnotherMove","actions":["tryAnotherMove"],"focus":[{"type":"move","from":"b1","to":"c3"}]}
```

It ignores the queen tap and supplies no reason for rejecting the tentative move.

### 07 — Answering check

```json
{"message":"Try another move to avoid immediate checkmate.","actions":["tryAnotherMove"],"focus":[{"type":"move","from":"b4","to":"d2"}]}
```

Severe factual error. The position contains check and a poor legal block, not immediate checkmate.

### 08 — Longer history

```json
{"message":"help me find a good move","actions":["hint"],"focus":[{"type":"square","square":"d5"},{"type":"square","square":"e5"}]}
```

Generic and unrelated to the available castling opportunity that the move history establishes.

## Decision

GPT-5.6 Sol has now passed the intended small consistency gate. Across three samples of each hard case, it consistently inferred the chess situation, followed the latest interaction, chose one useful teaching purpose, and produced UI-aligned output.

Qwen3 1.7B demonstrates why mechanical validity is not enough. The concise prompt solved the earlier context-overflow and malformed-output problems, and local latency is attractive, but the model still lacks the chess and interaction judgment needed for unsupervised coaching.

Recommended next step: design a stateless hosted coaching endpoint, with the app retaining deterministic prompt compilation and strict response validation. The app should show the already-approved thinking state after a short delay and offer a calm retry/close path for network or validation failure. Offline coaching should remain a future research track rather than a requirement for the first hosted iteration.
