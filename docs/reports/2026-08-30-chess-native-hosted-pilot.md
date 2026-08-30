# Chess-native hosted-model pilot

Date: 2026-08-30

## Result

The frozen `tutor-v6` packet was run once against `gpt-5.6-sol` through the OpenAI Responses API. The experiment used exactly eight prompts, high reasoning effort, strict request-specific Structured Outputs, the existing request-aware validator, and no retry, repair, or prompt mutation.

- Completion attempts: 8
- Provider errors: 0
- Strictly valid responses: 8
- Strictly invalid responses: 0
- Input tokens: 6,456 total; 684–969 per case
- Output tokens: 3,399 total, including 2,905 reasoning tokens
- Total tokens: 9,855
- Latency: 3.85–12.40 seconds; median 6.02 seconds

Unlike the local SmolLM3 pilot, the hosted model was consistently useful across this small visible set. It inferred important chess facts from FEN and move history, followed the latest interaction, kept each turn to one coaching purpose, used available actions and focus, avoided chess notation in child-facing copy, and made no observed factual chess error.

## Frozen configuration

- Provider API: OpenAI Responses API
- Model requested and returned: `gpt-5.6-sol`
- Reasoning effort: `high`
- Maximum output tokens: 2,048
- Storage: disabled (`store: false`)
- Prompt version: `tutor-v6`
- System prompt SHA-256: `0f434c5a7b4889442fc74f5846037d96a2332e479809e68790ee6dcebc1a6051`
- Source manifest SHA-256: `80eb1b8f5b57ea9fc04609909922ed1377e4dd702feb0e178a070aba4d3e15c7`
- Examples JSONL SHA-256: `8d9d28d904d060da791747083222c74a3ae29c87ec594792916f1dced757c75f`

Funded run directory:

`.coaching-eval/runs/gpt-5.6-sol/hosted-tutor-v6-pilot-20260830-funded`

- Run-manifest SHA-256: `08dda8bd28be6e6019dc59260a831cd42f23c4ddde748a4d5bbe163f5f1658fc`
- Review SHA-256: `433a2d6432e4265b07670142f9a931aa91399f09ae0fa13589bb603765abd7bc`

An earlier immutable attempt contains eight HTTP 429 failures caused by an empty API credit balance. It produced no model output and is excluded from the quality result.

## Exact responses and assessment

### 01 — Quiet help

```json
{"message":"Which middle pawn could move forward and open a path for a bishop?","actions":["hint"],"focus":[{"type":"square","square":"d2"},{"type":"square","square":"e2"}]}
```

Strong. It gives a concrete discovery clue without prescribing a move. Both focused pawns answer the question and can open a bishop's path.

### 02 — Attacked piece

```json
{"message":"The black pawn is attacking your knight. Can you find a safe square for the knight?","actions":[],"focus":[{"type":"square","square":"e4"},{"type":"square","square":"f3"}]}
```

Strong. The prompt supplied no explicit attack relationship; the model correctly inferred the urgent pawn attack from the FEN. It identifies the problem while leaving the child to choose the knight's destination.

### 03 — Selected piece

```json
{"message":"That black pawn is attacking your knight. Can you jump the knight to a safe square?","actions":["hint"],"focus":[{"type":"square","square":"e4"}]}
```

Strong and stage-aware. It understands that the child selected rather than moved the knight, keeps attention on the urgent attack, and uses child-friendly movement language. Focusing only the attacker is reasonable, though focusing the selected knight too could make the relationship clearer.

### 04 — Replaced tentative move

```json
{"message":"Good change! The knight comes toward the center and controls useful squares. Shall we play it?","actions":["playMove","tryAnotherMove"],"focus":[{"type":"move","from":"g1","to":"f3"}]}
```

Strong. It follows the replacement rather than discussing the superseded pawn move, gives a concise chess reason, and offers the correct completion choices. `Good change!` is slightly more evaluative than necessary, but not misleading.

### 05 — Tactical reply

```json
{"message":"Careful! The pawn beside your bishop can capture it. Can you find a safer move?","actions":["tryAnotherMove"],"focus":[{"type":"move","from":"a6","to":"b5"}]}
```

Strong. It notices the immediate tactical reply, explains it plainly, and keeps the child in discovery mode instead of naming a replacement move.

### 06 — Inspected opponent reply

```json
{"message":"Good spotting! Follow the black queen’s diagonal: which pawn near your king could she capture with check?","actions":["hint","tryAnotherMove"],"focus":[{"type":"move","from":"h4","to":"f2"}]}
```

Good and responsive. It follows the child's queen tap, distinguishes the dangerous checking reply from the other supplied queen captures, and makes the threat answerable through focus. The wording is slightly leading, and `Good spotting!` assumes intent, but the chess content and stage are sound.

### 07 — Answering check

```json
{"message":"The black bishop can capture your bishop and keep checking. Can you stop the check another way?","actions":["tryAnotherMove","hint"],"focus":[{"type":"move","from":"b4","to":"d2"},{"type":"move","from":"c1","to":"d2"}]}
```

Strong. It correctly explains why the legal blocking move is tactically poor and asks for another answer to the check. This directly avoids the severe factual error made by the local model on the same case.

### 08 — Longer history

```json
{"message":"Can your king and rook make their special safety move now?","actions":["hint"],"focus":[{"type":"square","square":"e1"},{"type":"square","square":"h1"}]}
```

Strong. It recognizes the castling opportunity from the position and full move history, avoids unexplained notation, and turns it into an age-appropriate discovery question.

## Local comparison

The frozen SmolLM3 pilot produced 5/8 strictly valid responses. It missed the urgent attack in case 02, confused selecting with moving in case 03, emitted chess notation in three cases, produced broken language in case 06, made a severe factual error in case 07, and never used actions or focus.

The hosted pilot produced 8/8 strictly valid responses. All eight were judged useful, all used request-available focus or actions, and none showed those failure classes. The improvement is therefore substantive, not merely better JSON compliance.

## Conclusion and next step

This pilot supports hosted coaching as the leading product direction. A capable hosted model appears able to supply the chess judgment and flexible teaching behavior that the deterministic local approach struggled to reproduce, while the app retains deterministic game-state compilation and strict output validation.

Eight single samples are not enough to establish reliability. The next evaluation should remain small: repeat the hardest stage-sensitive cases—02, 05, 06, and 07—three times each with the exact frozen prompts and settings. If those twelve responses remain factually correct, single-stage, child-appropriate, and useful, the next design task should be a stateless server endpoint and an app-side thinking/error state. No production networking or app integration should begin before that consistency check.
