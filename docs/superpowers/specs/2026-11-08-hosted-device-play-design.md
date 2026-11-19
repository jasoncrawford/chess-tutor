# Hosted coaching for the family iPad

## Intent

Make the coaching experience already accepted in play-testing available on the
family iPad without the development Mac running. Local chess remains playable
offline; hosted coaching needs internet. This is private family testing, not an
App Store launch, new coaching model experiment, or public anonymous API.

## Approach

Use the existing Flask server on Vercel under the accessible `jasoncrawford`
team, in a new `chess-tutor-coaching` project. Vercel is the implementation
choice: the repository already has its entrypoint/routing and this account is
authenticated. A home Mac/LAN server would retain the dependency the user wants
to remove; another hosting provider would add setup without a current benefit.
No database, paid plan upgrade, new domain, or new account system is needed.

The deployment must explicitly select the exact current trial configuration,
`Tools/CoachingEval/benchmark/configs/models/astra-experience-v7-low-model.json`,
including its pinned prompt and grounded-v4 compiler. Do not accidentally deploy
the older Sol default, alter the accepted prompt, or claim new benchmark scores.

Keep the OpenAI key solely in encrypted hosting configuration. Provision a
separate random family access token, retain its local copy in macOS Keychain,
and store the endpoint and access token together in the iPad Keychain after
one setup launch. Ordinary Home-screen launches then need no launch variables.
The app must not store credentials in its bundle, source, logs, or preferences.

## Configuration behavior

- A valid explicit launch URL/token pair bootstraps or replaces the saved pair.
- With no launch configuration, use the saved pair after validating it.
- An explicit URL without a new token may reuse a saved token only for the
  same origin. Never send one server's saved credential to a different origin.
- Invalid configuration or a Keychain failure yields unavailable hosted help,
  not a silent switch to the older local coach. A never-configured app keeps
  its current behavior.
- HTTPS is required for family/Release configuration; preserve Debug-only
  private-LAN/loopback support for the existing development launcher.
- Save the pair as one Keychain item, so failed writes cannot mix endpoints and
  tokens. No new player-facing settings screen is needed for this family build.

## Reproducible delivery

Commit non-secret hosting configuration and scripts for deployment and device
setup. Runtime uploads must exclude iPad assets, local evaluation evidence,
virtual environments, build products, and all secret files. Package exactly the
server, its runtime Python dependencies, and its model/prompt resources.

Use the existing server's bearer authentication and request-size validation.
Set a 60-second hosting function ceiling around the existing 30-second provider
timeout. Verify public health, unauthorized rejection, authenticated validation,
and a very small end-to-end coaching smoke test. Do not run a paid benchmark.

Device setup should build/install/configure via one command with an explicit
device identifier, using `DEVICECTL_CHILD_` environment variables rather than
putting credentials in command-line arguments. Simulator verification must
include terminating and relaunching without setup variables. Physical install
requires the family's connected, trusted iPad; do not select an unrelated device.

## Boundaries and dependencies

PR #24 supplies the integrated coaching implementation and is not yet merged.
The deployment branch begins on current main; import the integrated main only
after the user authorizes that merge and required checks pass. Do not stack
another feature PR on the unmerged coaching branch.

Vercel runtime log retention is plan-limited. Document the actual account tier
and retention when verified; do not promise indefinite trace storage or silently
add a database/logging subscription. Keep existing game-ID JSON diagnostics.

No automatic PR merge or broad cleanup of old worktrees/evaluation artifacts.
User preference is concise updates and autonomous implementation rather than
another design-review cycle.
