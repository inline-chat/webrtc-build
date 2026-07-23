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
The macOS member is intentionally `arm64`-only, matching Inline's release,
bundle-thinning, post-check, and Sparkle hardware policy. Intel simulator and
Mac Catalyst members remain available for development; they do not imply Intel
support for the shipped macOS app. The packager rejects missing or unexpected
architectures in every final XCFramework member.
Every Apple slice must additionally export Grid's mixer key and effective
software/platform processing-state objects, and declare the callback, delay,
and configured graph-format runtime diagnostics. This lets the app reject a
fresh callback stream whose WebRTC graph still targets a stale physical sample
rate after a route change. A generic WebRTC framework that links but omits
those hardened audio APIs is not a valid Inline artifact.
