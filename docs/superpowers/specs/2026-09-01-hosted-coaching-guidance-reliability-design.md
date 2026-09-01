# Hosted Coaching Guidance Reliability

## Goal

Remove three avoidable failures from hosted coaching: literal Markdown around control titles, discovery questions that visually reveal their answer, and harmlessly verbose responses that become local 502 errors.

## Prompt behavior

Introduce immutable prompt `tutor-v12`; leave `tutor-v11` unchanged.

- Visible control titles may be named in ordinary prose, preferably in quotation marks. They must never be wrapped in Markdown or other formatting delimiters.
- A turn whose expected response is `findEndangeredPiece` or `findSafeCapture` must not focus any square or move. The child should discover the answer on the board rather than have it circled.
- The model should still aim for 18 words or fewer, but this is a writing preference rather than a response-validity boundary.

## Mechanical response boundary

The Python server validator and Swift device validator will accept messages longer than 18 words. They will continue to reject blank messages and chess notation. The existing structured-output schema remains capped at 256 Unicode code points, and both validators will enforce the same generous 256-code-point bound for defense in depth.

Both validators will also reject nonempty focus for the two discovery response types. The server will report content-free, specific categories for blank messages, overlong messages, chess notation, and discovery focus. No rejected provider text will enter logs.

## Version adoption

The server compiles and returns `tutor-v12`; the app sends and accepts `tutor-v12`. Compiler behavior for v12 is identical to v11 except for the response-validation policies above. Existing prompt versions and their tests remain intact.

## Verification

Tests will prove the new prompt wording, permissive word count with the 256-code-point limit, discovery-focus rejection in Python and Swift, precise safe log categories, v12 compiler parity, and v12 server/device adoption. Focused Python and Swift suites will run before the full repository checks.
