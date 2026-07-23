# webrtc-build

webrtc build scripts

## Build Tools

## Inline fork

This fork builds the LiveKit-prefixed Apple XCFramework from
[`inline-chat/webrtc`](https://github.com/inline-chat/webrtc). The default
source revision in `build/VERSION` is based on the exact WebRTC commit used by
LiveKitWebRTC `144.7559.11`, plus Inline's macOS AudioEngine split-route
hardening. The `build` workflow intentionally produces only the
`LiveKitWebRTC.xcframework.zip` artifact needed by Inline's Swift package.
