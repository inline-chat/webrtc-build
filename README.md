# webrtc-build

webrtc build scripts

## Build Tools

## Inline fork

This fork builds the LiveKit-prefixed Apple XCFramework from
[`inline-chat/webrtc`](https://github.com/inline-chat/webrtc). The default
source revision in `build/VERSION` is based on the exact WebRTC commit used by
LiveKitWebRTC `144.7559.11`, plus Inline's macOS AudioEngine split-route
hardening, callback-quiescent APM resets, and recoverable route transactions.
The `build` workflow intentionally produces only the
`LiveKitWebRTC.xcframework.zip` artifact needed by Inline's Swift package and
runs the focused native audio regression gates before upload. Packaging also
verifies the final macOS binary's required Objective-C exports so a
header-only framework cannot be published accidentally.
The gate additionally requires Grid's mixer key, effective software and
platform processing-state objects, and callback/delay runtime diagnostics. A
generic WebRTC framework that links but omits those hardened audio APIs is not
a valid Inline artifact.
