# Chess-native SmolLM3 pilot

Date: 2026-08-30

## Result

The frozen `tutor-v6` packet was run once against SmolLM3 3B Q4_K_M. The experiment used exactly eight prompts, seed 1103, bounded hidden thinking, strict v6 JSON validation, and no repair or retry.

- Completion attempts: 8
- Provider errors: 0
- Strictly valid responses: 5
- Strictly invalid responses: 3
- Prompt-token range under the SmolLM3 template: 638–726
- Hard prompt budget: 2,500 tokens

The context-length problem is gone for this packet. Quality is not yet consistent enough for the app. Several responses are useful or promising, but the model misses urgent chess context, confuses selection with movement, emits forbidden notation, makes one severe factual error, and produces one visibly broken sentence.

## Frozen configuration

- Model: `smollm3-3b-q4_k_m`
- Model SHA-256: `8334b850b7bd46238c16b0c550df2138f0889bf433809008cc17a8b05761863e`
- Runtime: llama.cpp `b10516`, commit `b95502ba9aa0eb73a2f4fc8878d7fbe6a847a0b9`
- Runtime binary SHA-256: `fa65f946a434fcb34de87520ab76a3f2d576f97ad9f5a81b3a6e4201daff137e`
- System prompt SHA-256: `0f434c5a7b4889442fc74f5846037d96a2332e479809e68790ee6dcebc1a6051`
- Source manifest SHA-256: `80eb1b8f5b57ea9fc04609909922ed1377e4dd702feb0e178a070aba4d3e15c7`
- Mode: bounded hidden thinking
- Seed: `1103`
- Maximum output tokens: 512
- Temperature: 0.2
- Top-p: 0.95

Run-manifest SHA-256: `459caf5144f38cc6be263e806ba86e1ffeadb10d27a37852c8cf254bffeb8ec6`

## Exact responses and assessment

### 01 — Quiet help

```json
{"message":"Look for a knight that can jump to a square that controls more of the board.","actions":[],"focus":[]}
```

Mechanically valid. This is a useful discovery-oriented opening prompt. It avoids prescribing an exact move, though it could be more concrete about developing a piece toward the center.

### 02 — Attacked piece

```json
{"message":"Look for a knight move to control the center, like Nf3 or Ng1.","actions":[],"focus":[]}
```

Invalid because the child-facing message contains SAN. More importantly, it misses the urgent fact that the pawn on e4 attacks the knight on f3. This is a substantive coaching failure, not merely formatting.

### 03 — Selected piece

```json
{"message":"You moved the knight to f3. Now you can go to d4 or e5 with the knight. Which? ","actions":[],"focus":[]}
```

Mechanically valid, but it says the child moved the knight when the child only selected it. It also fails to explain that the selected knight is under attack. The offered squares are legal, but the stage tracking and teaching purpose are weak.

### 04 — Replaced tentative move

```json
{"message":"Nice! You're moving the knight to f3. What do you think about the knight's position? Is it safe?","actions":[],"focus":[]}
```

Mechanically valid and responsive to the new tentative move. The question is appropriately exploratory, but generic; it does not use the available evidence that Black has no immediate capture, check, or mate reply.

### 05 — Tactical reply

```json
{"message":"What if you play Bb5? What can Black do?","actions":[],"focus":[]}
```

Invalid because it uses SAN. Pedagogically, the question points in the right direction: it asks the child to inspect Black's reply to the tentative bishop move. Rephrasing in ordinary language and using structured move focus could make this good.

### 06 — Inspected opponent reply

```json
{"message":"Look at the queen on h4. She can go to e4, f2, or h2. Which one do you'do?","actions":[],"focus":[]}
```

Mechanically valid, but not app-quality. It follows the tapped queen and names the relevant reply squares, yet the last sentence is visibly broken and it does not help distinguish why the replies matter.

### 07 — Answering check

```json
{"message":"What if you play Bxd2? That would take the bishop and put Black's queen in check.","actions":[],"focus":[]}
```

Invalid because it uses SAN. It is also factually wrong: Black's bishop can capture the blocking bishop and continue checking White's king; the move does not put Black's queen in check. This is a severe chess error.

### 08 — Longer history

```json
{"message":"Look for a knight move to control the center or attack Black's pieces.","actions":[],"focus":[]}
```

Mechanically valid and broadly sensible, but generic. It leaves the choice to the child and uses the position rather than echoing a supplied conclusion, which is directionally good.

## Conclusion

The new deterministic prompt compiler solved the dominant technical problem: every prompt is compact, role-safe, and comfortably inside context. SmolLM3 also followed the three-field response shape much better than in earlier experiments.

It did not produce consistently app-quality coaching. The most useful next step is another small prompt iteration using these eight exact failures as a qualitative lab, not another matrix. The prompt should more strongly distinguish selection from movement, require urgent danger to outrank quiet improvement, forbid chess notation with a plain-language replacement example, and encourage structured focus instead of spelling move notation into the message. After those changes, rerun only these eight prompts on the same model before comparing model sizes.
