# CloudKit Manual Setup

Most of the CloudKit spike is now represented in source: the app target has a CloudKit entitlement file, and the spike screen is launch-argument gated. The remaining steps require your Apple ID, developer team, and signed-in devices.

## What You Must Do

1. Use the selected bundle ID.

   The project is configured for `org.jasoncrawford.chesstutor`.

2. Select your signing team in Xcode.

   Open `ChessTutor.xcodeproj`, select the `ChessTutor` target, go to `Signing & Capabilities`, enable automatic signing, and choose your Apple ID team.

3. Create or allow Xcode to create the iCloud container.

   The entitlement is configured as `iCloud.$(PRODUCT_BUNDLE_IDENTIFIER)`, so the container should be `iCloud.org.jasoncrawford.chesstutor`.

4. Sign in to iCloud on the test iPads or simulators.

   CKShare testing needs two different iCloud participants. For the real product, these are the two people playing remotely.

5. Launch the spike with both debug arguments.

   Use `--cloudkit-share-spike --cloudkit-share-spike-use-cloudkit`. The first argument opens the spike screen; the second deliberately enables CloudKit calls.

## What I Can Do From The Repo

- Keep the CloudKit entitlements file checked in.
- Keep the XcodeGen project wiring checked in.
- Build and test the app locally.
- Launch the safe spike screen without CloudKit enabled.
- Help run the two-device CKShare checklist once the signed build exists.

## What I Cannot Do Without You

- Choose your permanent bundle ID namespace.
- Select your Apple Developer team.
- Create Apple-hosted identifiers or containers tied to your Apple account if authentication is required.
- Sign in to iCloud as the second participant.
