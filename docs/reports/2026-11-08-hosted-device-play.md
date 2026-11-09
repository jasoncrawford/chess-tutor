# Hosted family-iPad play

## Delivery

PR #24 was merged with approval at `cc6930b98404bcf90ed4df76f32e43a4cea9b659`.
The deployment work is on `codex/hosted-device-play`, based on that integrated main.

The coaching server is live at **https://chess-tutor-coaching.vercel.app**.
The initial production deployment is
`chess-tutor-coaching-laidn8s7g-jasoncrawford1.vercel.app`
(`dpl_48frdq8jtfVTLE23ceeGBMSpnn6r`) in the existing `jasoncrawford` Vercel team.
No plan upgrade, database, new domain, or public anonymous coaching access was added.

The accepted policy is unchanged: `astra-experience-v7-low-model.json`, GPT-6
Astra with low reasoning, `tutor-v13-experience-v6.md`, grounded-v4 compiler,
2,048 output-token limit, one attempt, 30-second provider timeout. The pinned
prompt SHA-256 is
`d15b6f422607b4325089ca1a1522e5927d5afc46313bbdccb8cd90fd8b297225`.
There was no new model benchmark or prompt modification.

## Security and repeatability

- `CoachingServer/deployment.json` and the deploy script upload an explicit
  minimal runtime allowlist, verifying the pinned prompt before deployment.
- The OpenAI key is server-only. A separate random family token is retained in
  macOS Keychain and encrypted hosting configuration; credentials are never
  placed in command arguments, source, device bundles, or diagnostic output.
- The iPad saves its validated HTTPS origin and family token atomically in a
  device-only Keychain item. Ordinary Home-screen launches restore the pair.
- An explicit different origin cannot borrow the old token. Invalid saved
  settings and Keychain failures fail closed instead of enabling local coaching.
- The actual relaunch UI test uses its own UUID-scoped Keychain item and game
  library, and removes only its own data afterward. Its transport is real HTTP,
  not a mocked provider, and makes no paid requests.

## Verification evidence

Production checks returned health **200**, anonymous coaching **401**,
authenticated invalid envelope **400**, and source path `/vercel.json` **404**.
One real paid coaching request returned valid `hosted-coaching-turn.v3` advice:
1,946 input tokens, 107 output tokens, 4,637 ms provider latency. Its smoke game
ID was `1f637085-b803-4107-ab54-eb5994bdd072`. No paid evaluation suite was run.

Before the review fixes, all 1,007 native unit tests and 11 UI tests passed,
as did 65 server tests, 375 evaluation-tooling tests (including the 11 browser
tests), and the unsigned physical-device Release build.

The independent branch review found two important issues: permissive Debug
private-address parsing and a relaunch test that could replace normal simulator
settings. Both were reproduced by failing tests, corrected, and passed the
focused run (11 configuration tests plus the real relaunch UI test). The complete
post-review run passed **1,008 native unit tests, 11 UI tests, 65 server tests,
375 evaluation-tooling tests and 11 browser tests**, with no skipped tests.
Both unsigned and development-signed physical-device Release builds succeeded.
The native result bundle is `/tmp/chess-hosted-reviewed-full.xcresult`.

## Physical device status

The connected **Family iPad** is the ninth-generation target, running iPadOS
26.5.2. Trust succeeded and Apple's `devmodectl` confirms Developer Mode is
enabled. Xcode/CoreDevice still reports it as paired but unavailable, including
after a cable reconnect. A direct Xcode build targeting its UDID fails because
the destination is unavailable; a generic signed-device build succeeds. Direct
installation fails with CoreDevice error 4016 (trusted device services cannot be
acquired). No app installation or physical-device playtest is claimed yet. No
pairing reset or device-data reset was performed.

Once Xcode can connect, run from this worktree:

```bash
python3 scripts/install_hosted_coaching_device.py --device "Family iPad"
```

That builds/signs/installs and performs the one-time setup launch. Verify Help,
then close and reopen the app from Home and verify Help again. Chess remains
offline-capable; coaching needs internet, but no development Mac server.
Development signing/provisioning expiration still applies.

## Logs and limits

This existing Vercel Pro plan retains runtime logs for one day by default.
Copy the game ID from About and collect the trace promptly after a playtest.
There is no long-term archive. See [server operation instructions](../hosted-coaching-server.md).
The installed CLI's historical log summary exposes only the first message per
request; full trace collection should use request details, not that summary.

## Execution decisions

- Native test/build waits overlapped independent server/device-script work;
  related changes were checkpointed together. The tradeoff is a larger review
  range rather than separate task commits.
- The reviewer did not reassess unchanged prompt quality. This deployment keeps
  the accepted policy intact; prior coaching limitations remain unchanged.
- Physical signing/install/play remained outside the reviewer's evidence. It
  remains an explicit verification gate, not an assumed consequence of a
  successful simulator test or unsigned device build.
