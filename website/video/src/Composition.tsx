import { Audio, Video } from "@remotion/media";
import {
  AbsoluteFill,
  CanvasImage,
  Easing,
  interpolate,
  Sequence,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";

const clamp = {
  extrapolateLeft: "clamp" as const,
  extrapolateRight: "clamp" as const,
  easing: Easing.bezier(0.22, 1, 0.36, 1),
};

// Editorial titles stay outside the native interface, without callout chrome.
const FeatureTitle = ({
  x,
  y,
  title,
  opacity = 1,
  width = 480,
}: {
  x: number;
  y: number;
  title: string;
  opacity?: number;
  width?: number;
}) => (
  <div
    style={{
      position: "absolute",
      left: x,
      top: y,
      width,
      opacity,
      color: "#f5f7f2",
      fontFamily: "-apple-system,BlinkMacSystemFont,sans-serif",
      fontSize: 50,
      fontWeight: 500,
      letterSpacing: -1.8,
      lineHeight: 1.12,
      textShadow: "0 2px 24px #0005",
      textWrap: "balance",
    }}
  >
    {title}
  </div>
);

// A single, short glint beside the real control. No loops or enclosing shapes.
const Glint = ({ x, y, at }: { x: number; y: number; at: number }) => {
  const t = useCurrentFrame() / useVideoConfig().fps;
  return (
    <svg
      width="38"
      height="38"
      viewBox="0 0 38 38"
      style={{
        position: "absolute",
        left: x - 19,
        top: y - 19,
        overflow: "visible",
        opacity: interpolate(
          t,
          [at, at + 0.12, at + 0.3, at + 0.7],
          [0, 0.72, 0.48, 0],
          clamp,
        ),
        scale: interpolate(t, [at, at + 0.2, at + 0.7], [0.55, 1, 0.7], clamp),
        filter: "drop-shadow(0 0 5px #e6f3dc55)",
      }}
    >
      <path
        d="M19 4 C20 15 23 18 34 19 C23 20 20 23 19 34 C18 23 15 20 4 19 C15 18 18 15 19 4Z"
        fill="#edf7e7"
      />
      <path
        d="M34 -3 Q34 3 40 3 Q34 3 34 9 Q34 3 28 3 Q34 3 34 -3Z"
        fill="#edf7e7"
        opacity="0.5"
      />
    </svg>
  );
};

// A single diffuse bloom marks the transport change without enclosing the icon.
const CloudBloom = ({ x, y, at }: { x: number; y: number; at: number }) => {
  const t = useCurrentFrame() / useVideoConfig().fps;
  return (
    <div
      style={{
        position: "absolute",
        left: x - 100,
        top: y - 45,
        width: 200,
        height: 90,
        pointerEvents: "none",
        background:
          "radial-gradient(ellipse, #dfefcb40, #dfefcb12 35%, transparent 70%)",
        opacity: interpolate(t, [at, at + 0.22, at + 0.9], [0, 0.85, 0], clamp),
        scale: interpolate(t, [at, at + 0.9], [0.7, 1.15], clamp),
      }}
    />
  );
};

// Native macOS pointer, registered to the footage and its camera transform.
const DemoPointer = () => {
  const t = useCurrentFrame() / useVideoConfig().fps;
  const times = [
    8.7, 9.25, 9.62, 10.3, 10.68, 11.55, 11.94, 12.98, 13.38, 13.88, 14.2,
    15.55, 15.94, 16.7, 17.06, 17.46, 20.5, 20.93, 21.3, 21.67, 22.3, 22.65,
  ];
  const xs = [
    1600, 1600, 1416, 1416, 1610, 1610, 1743, 1743, 1416, 1416, 1390, 1390,
    1236, 1236, 1510, 1300, 1300, 1743, 1743, 1785, 1785, 1840,
  ];
  const ys = [
    600, 600, 500, 500, 570, 570, 355, 355, 675, 675, 666, 666, 840, 840, 480,
    200, 200, 355, 355, 308, 308, 410,
  ];
  const travel = { ...clamp, easing: Easing.bezier(0.45, 0, 0.2, 1) };
  const presses = [9.73, 12.02, 13.56, 16.05, 17.58, 21.1, 21.79];
  const scale = presses.reduce(
    (value, at) =>
      Math.min(
        value,
        interpolate(t, [at - 0.045, at, at + 0.12], [1, 0.87, 1], clamp),
      ),
    1,
  );
  return (
    <CanvasImage
      src={staticFile("mac-pointer.png")}
      style={{
        position: "absolute",
        left: interpolate(t, times, xs, travel) - 8,
        top: interpolate(t, times, ys, travel) - 4,
        width: 56,
        height: 83,
        transformOrigin: "8px 4px",
        scale,
        opacity: interpolate(t, [8.7, 8.9, 22.65, 22.9], [0, 1, 1, 0], clamp),
        filter: "drop-shadow(0 1px 2px #0006)",
      }}
    />
  );
};

const DemoAudio = () => {
  const { fps } = useVideoConfig();
  return (
    <>
      <Audio
        src={staticFile("audio/valley-sunset.mp3")}
        premountFor={fps}
        volume={(frame) =>
          interpolate(
            frame / fps,
            [0, 1.4, 28.4, 31.3],
            [0, 0.13, 0.13, 0],
            clamp,
          )
        }
      />
      {[9.73, 12.02, 13.56, 16.05, 17.58, 21.1, 21.79].map((at) => (
        <Sequence
          key={at}
          name="Pointer tap"
          from={Math.round(at * fps)}
          durationInFrames={Math.round(0.4 * fps)}
          premountFor={fps}
        >
          <Audio
            src={staticFile("audio/ui-double-tap.mp3")}
            trimBefore={Math.round(0.05 * fps)}
            volume={0.55}
            premountFor={fps}
          />
        </Sequence>
      ))}
    </>
  );
};

const nativeFrameStyle = {
  position: "absolute" as const,
  left: 960,
  width: 960,
  height: 1020,
  maskImage:
    "linear-gradient(to right, transparent, black 65px, black calc(100% - 100px), transparent), linear-gradient(to bottom, transparent, black 45px, black 91%, transparent)",
  maskComposite: "intersect",
};

const NativeClip = ({
  name,
  previous,
}: {
  name: string;
  previous?: string;
}) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const dissolveFrames = Math.round(0.24 * fps);
  return (
    <>
      {previous && frame < dissolveFrames && (
        <CanvasImage
          src={staticFile(`native/${previous}-tail.webp`)}
          style={nativeFrameStyle}
        />
      )}
      <Video
        src={staticFile(`native/${name}.mp4`)}
        muted
        premountFor={fps}
        style={{
          ...nativeFrameStyle,
          opacity: previous
            ? interpolate(frame, [0, dissolveFrames], [0, 1], clamp)
            : 1,
        }}
      />
    </>
  );
};

const Handset = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const t = frame / fps;
  return (
    <div
      style={{
        position: "absolute",
        left: 85,
        top: 65,
        width: 520,
        height: 1072,
        filter: "drop-shadow(0 20px 30px #0008)",
        opacity: interpolate(t, [4.45, 5.05], [1, 0], clamp),
        translate: interpolate(
          t,
          [4.45, 5.05],
          ["0px 0px", "-70px 12px"],
          clamp,
        ),
      }}
    >
      <div
        style={{
          position: "absolute",
          left: 23.64,
          top: 23.64,
          width: 472.72,
          height: 1024,
          borderRadius: 36.8,
          overflow: "hidden",
        }}
      >
        <CanvasImage
          src={staticFile("android-pairing.webp")}
          style={{
            position: "absolute",
            inset: 0,
            width: "100%",
            height: "100%",
            objectFit: "fill",
          }}
        />
        <CanvasImage
          src={staticFile("android-scanner-staged.webp")}
          style={{
            position: "absolute",
            inset: 0,
            width: "100%",
            height: "100%",
            objectFit: "fill",
            opacity: interpolate(
              t,
              [1.05, 1.3, 4.02, 4.2],
              [0, 1, 1, 0],
              clamp,
            ),
            translate: interpolate(
              t,
              [1.05, 1.3],
              ["0px 14px", "0px 0px"],
              clamp,
            ),
          }}
        />
        <CanvasImage
          src={staticFile("android-connected.webp")}
          style={{
            position: "absolute",
            inset: 0,
            width: "100%",
            height: "100%",
            objectFit: "fill",
            opacity: interpolate(t, [4.02, 4.2], [0, 1], clamp),
          }}
        />
      </div>
      <CanvasImage
        src={staticFile("galaxy-s26-frame.webp")}
        style={{
          position: "absolute",
          inset: 0,
          width: "100%",
          height: "100%",
        }}
      />
    </div>
  );
};

export const PhoneCheckDemo = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const t = frame / fps;
  const appear = (start: number, end: number) =>
    interpolate(t, [start, start + 0.2, end - 0.2, end], [0, 1, 1, 0], clamp);
  return (
    <AbsoluteFill
      style={{
        background: "#111719",
        overflow: "hidden",
        fontFamily: "-apple-system,BlinkMacSystemFont,sans-serif",
      }}
    >
      <CanvasImage
        src={staticFile("vscode-ending.jpg")}
        style={{
          position: "absolute",
          inset: 0,
          width: "100%",
          height: "100%",
          objectFit: "cover",
          opacity: 0.55,
        }}
      />
      <AbsoluteFill
        style={{
          translate: interpolate(
            t,
            [4.5, 5.15],
            ["0px 0px", "-210px 0px"],
            clamp,
          ),
        }}
      >
        <AbsoluteFill
          style={{
            transformOrigin: "0 0",
            scale: interpolate(
              t,
              [
                0, 4.5, 7.15, 7.8, 11.1, 11.7, 16.7, 17.3, 20.4, 21, 24, 24.8,
                27.2, 28.3,
              ],
              [
                1, 1, 1.03, 1.15, 1.15, 1.08, 1.08, 1.1, 1.1, 1.12, 1.12, 1.35,
                1.35, 1,
              ],
              clamp,
            ),
            translate: interpolate(
              t,
              [
                0, 4.5, 7.15, 7.8, 11.1, 11.7, 16.7, 17.3, 20.4, 21, 24, 24.8,
                27.2, 28.3,
              ],
              [
                "0px 0px",
                "0px 0px",
                "-50px -10px",
                "-230px -75px",
                "-230px -75px",
                "-160px -20px",
                "-160px -20px",
                "-180px -30px",
                "-180px -30px",
                "-400px 20px",
                "-400px 20px",
                "-480px 0px",
                "-480px 0px",
                "0px 0px",
              ],
              clamp,
            ),
          }}
        >
          <Sequence
            name="Pair and open scanner"
            from={0}
            durationInFrames={270}
            premountFor={fps}
          >
            <NativeClip name="pairing" />
          </Sequence>
          <Sequence
            name="Notification arrives"
            from={270}
            durationInFrames={180}
            premountFor={fps}
          >
            <NativeClip name="arrival" previous="pairing" />
          </Sequence>
          <Sequence
            name="Music advances and pauses"
            from={450}
            durationInFrames={240}
            premountFor={fps}
          >
            <NativeClip name="music" previous="arrival" />
          </Sequence>
          <Sequence
            name="Expand conversation"
            from={690}
            durationInFrames={96}
            premountFor={fps}
          >
            <NativeClip name="reply-expand" previous="music" />
          </Sequence>
          <Sequence
            name="Open inline reply"
            from={786}
            durationInFrames={66}
            premountFor={fps}
          >
            <NativeClip name="reply-open" previous="reply-expand" />
          </Sequence>
          <Sequence
            name="Type reply"
            from={852}
            durationInFrames={84}
            premountFor={fps}
          >
            <NativeClip name="reply-type" previous="reply-open" />
          </Sequence>
          <Sequence
            name="Send reply"
            from={936}
            durationInFrames={84}
            premountFor={fps}
          >
            <NativeClip name="reply-send" previous="reply-type" />
          </Sequence>
          <Sequence
            name="Search notifications"
            from={1020}
            durationInFrames={180}
            premountFor={fps}
          >
            <NativeClip name="search" previous="reply-send" />
          </Sequence>
          <Sequence
            name="Clear native search"
            from={1200}
            durationInFrames={42}
            premountFor={fps}
          >
            <NativeClip name="search-clear" previous="search" />
          </Sequence>
          <Sequence
            name="Collapse conversation"
            from={1242}
            durationInFrames={48}
            premountFor={fps}
          >
            <NativeClip name="collapse" previous="search-clear" />
          </Sequence>
          <Sequence
            name="Dismiss using actual native button"
            from={1290}
            durationInFrames={168}
            premountFor={fps}
          >
            <NativeClip name="dismiss" previous="collapse" />
          </Sequence>
          <Sequence
            name="Cloud handover"
            from={1458}
            durationInFrames={240}
            premountFor={fps}
          >
            <NativeClip name="cloud" previous="dismiss" />
          </Sequence>
          <Glint x={1450} y={460} at={9.35} />
          <DemoPointer />
          <CloudBloom x={1167} y={120} at={25.2} />
        </AbsoluteFill>
      </AbsoluteFill>
      <DemoAudio />
      <Handset />
      <FeatureTitle
        x={655}
        y={500}
        width={330}
        title="Pair in a scan."
        opacity={appear(0.15, 4.3)}
      />
      <FeatureTitle
        x={160}
        y={690}
        title="Your alerts. Right here."
        opacity={appear(5.1, 7.45)}
      />
      <FeatureTitle
        x={160}
        y={435}
        title="Music, in reach."
        opacity={appear(7.55, 11.45)}
      />
      <FeatureTitle
        x={160}
        y={660}
        title="Reply right here."
        opacity={appear(11.6, 16.95)}
      />
      <FeatureTitle
        x={160}
        y={180}
        title="Find it in a moment."
        opacity={appear(17.05, 20.6)}
      />
      <FeatureTitle
        x={1480}
        y={300}
        width={330}
        title={t < 22.25 ? "Dismiss on phone." : "Cleared on phone."}
        opacity={appear(21.5, 24.2)}
      />
      <FeatureTitle
        x={160}
        y={115}
        width={450}
        title={t < 25.38 ? "Prefers local Wi-Fi." : "Can sync over cloud."}
        opacity={appear(24.4, 28.05)}
      />
      <AbsoluteFill
        style={{
          opacity: interpolate(t, [28.1, 28.65], [0, 1], clamp),
          background: "#111719",
        }}
      >
        <CanvasImage
          src={staticFile("vscode-ending.jpg")}
          style={{
            position: "absolute",
            inset: 0,
            width: "100%",
            height: "100%",
            objectFit: "cover",
            opacity: 0.22,
          }}
        />
        <div
          style={{
            position: "absolute",
            inset: 0,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            flexDirection: "column",
            color: "#f4f5f0",
            translate: interpolate(
              t,
              [28.1, 28.85],
              ["0px 16px", "0px 0px"],
              clamp,
            ),
          }}
        >
          <CanvasImage
            src={staticFile("app-icon.png")}
            style={{
              width: 144,
              height: 144,
              borderRadius: 34,
              marginBottom: 28,
            }}
          />
          <div style={{ fontSize: 68, fontWeight: 550, letterSpacing: -2.2 }}>
            Phone Check
          </div>
          <div style={{ fontSize: 35, color: "#c4d0c0", marginTop: 17 }}>
            Your phone, a little less often.
          </div>
          <div
            style={{
              fontSize: 21,
              color: "#89958d",
              marginTop: 34,
              letterSpacing: 2,
            }}
          >
            ANDROID + MAC
          </div>
        </div>
      </AbsoluteFill>
      <AbsoluteFill
        style={{
          background: "#111719",
          opacity: interpolate(t, [0, 0.28, 30.85, 31.3], [1, 0, 0, 1], clamp),
        }}
      />
    </AbsoluteFill>
  );
};
