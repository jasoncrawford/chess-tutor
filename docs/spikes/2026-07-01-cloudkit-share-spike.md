# CKShare Remote Game Spike

This spike adds a debug-only screen for validating whether `CKShare` can support the private remote game flow without leaking generic iCloud sharing UI into the product experience.

## Scope

- The normal app still launches `ContentView`.
- The spike launches only with `--cloudkit-share-spike`.
- CloudKit operations are enabled only with the additional `--cloudkit-share-spike-use-cloudkit` argument.
- The spike creates one shared root game record and child move records.
- The owner writes through the private database.
- The participant writes through the shared database after accepting the share.
- The spike stores the accepted root record pointer locally so relaunch can be checked.

## Not In Scope

- Production remote play UI.
- Invite code records.
- Subscriptions or push notifications.
- Real game move encoding.
- Entitlements or CloudKit container setup.

## Setup

The repository includes a CloudKit entitlements file that points at `iCloud.$(PRODUCT_BUNDLE_IDENTIFIER)`. Before running this spike against CloudKit:

1. Use an Apple Developer team and a real bundle ID.
2. Add the iCloud capability and CloudKit service to the app target.
3. Configure the app to use the CloudKit container for that bundle ID.
4. Launch the debug app with `--cloudkit-share-spike --cloudkit-share-spike-use-cloudkit`.
5. Sign in to iCloud on both test devices or simulators.

For the current bundle ID, the expected container name is `iCloud.org.jasoncrawford.chesstutor`.

## Manual Test Plan

Owner device:

1. Tap `Check iCloud Account`; expect `available`.
2. Tap `Create Shared Game`; expect a root record name and share URL.
3. Send the share URL to the participant device.
4. Tap `Write Owner Move`.
5. Tap `Fetch Owner Moves`; expect to see the owner move note.

Participant device:

1. Launch with `--cloudkit-share-spike`.
2. Paste the share URL and tap `Accept Share URL`, or open the share URL and then tap `Refresh Share Accepted By App Delegate`.
3. Tap `Write Accepted Move`.
4. Tap `Fetch Accepted Moves`; expect to see the participant move note.
5. Relaunch and tap `Refresh Share Accepted By App Delegate`; expect the accepted root pointer to still load.

Owner follow-up:

1. Tap `Fetch Owner Moves` again.
2. Confirm the participant move appears on the owner side.

## Questions To Answer

- Does creating a `CKShare` programmatically return a share URL without showing generic sharing UI?
- Can the participant accept the share from an app-managed URL flow?
- Does accepting a share force any OS-level UI that would affect the child-friendly invite experience?
- Can both users write child move records under the shared root?
- Does `publicPermission = .readWrite` work for a no-UI URL invite, and is that acceptable for our security model?
- Can the app hide all CloudKit record and participant details from normal users?
- What exact errors appear for no iCloud account, restricted iCloud, offline launch, and declined share acceptance?

## Manual Result

Manual test completed on 2026-07-05 with bundle ID `org.jasoncrawford.chesstutor` and expected container `iCloud.org.jasoncrawford.chesstutor`.

The test used one physical iPad, switching between two iCloud accounts to simulate owner and participant. The iPad simulator was not used for the participant path because simulator iCloud sign-in rejected multiple known-good Apple Account credentials.

Observed result:

1. Owner iCloud account reported `available`.
2. Owner created a shared game root and received a share URL.
3. Owner wrote a move and fetched it from the private database.
4. Participant iCloud account accepted the same share URL through the spike UI.
5. Participant wrote a move through the shared database.
6. Participant fetched moves and saw both the owner move and participant move.
7. Owner iCloud account fetched moves again and saw both moves.

This validates the core CKShare data path for a private two-player game: programmatic share creation, app-managed share acceptance, owner writes through the private database, participant writes through the shared database, and both sides can read the shared move history.

Remaining risks and follow-ups:

- Test on two simultaneous physical devices to confirm behavior without account switching.
- Confirm whether accepting by opening the share URL directly invokes any OS-level UI we would want to avoid.
- Test offline, no-iCloud-account, restricted-account, and declined/invalid-share error states.
- Decide whether `publicPermission = .readWrite` is acceptable for the invite security model or whether accepted participants should be constrained differently.
- Add subscriptions/push notification behavior in a separate spike or implementation phase.

## Expected Decision

The manual test confirms programmatic create, accept, read, and write on the core shared-record path. Production remote play can use `CKShare` for accepted games and a short-lived public invite record only for rendezvous, while keeping the transport boundary in place so the app can switch to private app records or a custom server later if later UI, permission, or notification tests expose problems.
