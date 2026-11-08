# Pull Request CI Design

## Goal

Run the repository's Python and iPad test suites automatically for every pull
request, without credentials or live model calls.

## Design

GitHub Actions will run two independent jobs. An Ubuntu job installs Python
3.12 and the pinned requirements, then runs every `CoachingServer` and
`Tools/CoachingEval` unittest. A macOS 26 job uses Xcode 26.6 to run the full
`ChessTutor` scheme on the latest iPad (A16) simulator.

New pushes to the same pull request cancel older runs. Both jobs retain useful
failure evidence: the Python transcript and the Xcode result bundle. The
workflow has read-only repository permissions and receives no application or
provider secrets.

## Verification

The workflow's commands must first pass locally. A repository test will pin the
workflow's trigger, runner, test-command, timeout, concurrency, permission, and
failure-artifact contracts. The first run on GitHub is the end-to-end proof.
