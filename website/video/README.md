# Phone Check product demo

31.3 seconds at 1920 × 1080, 60 fps. The sequence covers QR pairing and the phone
scanner, an arriving notification, moving native media slider and pause, inline
reply, search, confirmed dismissal, cloud handover, and a held ending.

The Mac footage is a ScreenCaptureKit recording of production SwiftUI views at
3200 × 1864. The app itself renders at twice its usual layout scale before capture;
this is not an enlargement of the previous video. The recorded native column is
cropped to 1600 × 1700 and displayed at 960 × 1020, with zoom capped at 1.35×.
That retains source pixels for close-ups in the 1080p output.

After pairing, the handset fades away and the Mac takes focus. Feature captions
use title-only typography outside the interface. Focus cues vary by moment: a
single music glint, closer camera framing for dismissal, and a diffuse
cloud-handover bloom. Reply uses its native focus treatment without a shine
overlay. Pairing and search rely on their native UI changes. Effects never loop or enclose controls. The recorded column is feathered
on all edges into the IDE backdrop.

Recorded panel states dissolve over 240 ms using the previous clip’s final frame;
feature timing and total runtime stay unchanged. The recorded conversation
collapse is included before dismissal. An enlarged native macOS pointer asset
(AppKit `NSCursor.arrow`) follows eased 350–430 ms paths, with a brief press on actual
action frames. Its position shares the footage’s camera transform.

All source clips play at 1×. `prepare-native-clips.py` removes only idle gaps;
it does not retime or interpolate UI transitions. The native command controller
handles reply, music, and dismissal against simulated phone receipts. The actual
native hover cross is exposed by the existing `--hover` visual-fixture flag.
The media fixture includes seek capability, so the production Slider appears,
and playback advances at normal speed. Pause preserves its current position.

The phone scanner interface was captured from the real Google code scanner on
the Android emulator. Its camera view is staged with a demo Mac QR code using
`stage-scanner.py`. Pairing, notification content, and phone receipts are synthetic.
No real phone or cloud session is recorded. The soundtrack combines quiet Mixkit
instrumental music and softer user-selected taps synchronized to pointer presses.
Sources and license links are in `public/audio/README.md`. The website
uses the unlisted YouTube upload with muted autoplay and controls below the video.

```sh
npm ci
npm run dev -- --no-open
npx remotion render src/index.ts PhoneCheck ../public/assets/phone-check-demo.mp4 --codec h264 --crf 16
```

Rebuild clips and outgoing stills with
`uv run --with pillow python ../scripts/prepare-native-clips.py /path/to/source.mov`.
Source clips are in `public/native/`. Their source offsets and 1× playback rate
are recorded in `public/native/timeline.json`. The timing markers are retained in
`../assets/captures/native-timing.json`. Recording helpers live in `../scripts/`.
PNG intermediate frames avoid a JPEG generation before the final H.264 encode.
