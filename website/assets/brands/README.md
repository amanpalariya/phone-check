# Demo asset sources

Google Messages (`com.google.android.apps.messaging`), Gmail (`com.google.android.gm`),
and YouTube Music (`com.google.android.apps.youtube.music`) launcher icons were rasterized
from their installed Android packages on the API 37 emulator by the instrumentation
asset fixture. No user messages or app account data were read.

Track and artwork: [Patient Zero — Taylor Swift](https://music.apple.com/us/album/patient-zero/6814997249?i=6814997425).
Selected at the user's request; metadata checked October 30, 2026 using the official
iTunes API. Track duration is 225,868 ms. `music-source.json` records source URLs.
Artwork is displayed as the thumbnail in the synthetic media notification. No song
audio or lyrics are included. App icons and artwork remain their owners’ work.

Samsung handset bezel: [Hoverify Galaxy S26 frame](https://tryhoverify.com/tools/device-frames/galaxy-s26/),
[black WebP asset](https://tryhoverify.com/images/devices/galaxy_s26/black.webp).
The source page permits personal and commercial use. It is Hoverify’s existing
measurement-based device artwork, composited over the app capture.

Editor backdrop: actual VS Code screenshot on the user's Mac, showing this
repository’s `website/main.js`, captured October 30, 2026. Top window chrome was
cropped and the image blurred before compositing behind the native app. No code
is re-created as a visual. Raw capture is in `../captures/vscode-raw.png`.

Scanner chrome: actual Google code scanner captured through the production
`scanPairingCode` function in the API 37 emulator. The camera feed is staged with
a synthetic pairing QR; its native scanner controls and reticle are retained.

Current Mac motion clips use the production SwiftUI views and command controller,
recorded by `scripts/record-native.swift`. Only the isolated capture fixture's
window is selected. No desktop or unrelated application is recorded.
