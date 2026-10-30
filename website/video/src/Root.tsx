import { Composition } from "remotion";
import { PhoneCheckDemo } from "./Composition";

export const RemotionRoot = () => (
  <Composition
    id="PhoneCheck"
    component={PhoneCheckDemo}
    durationInFrames={1878}
    fps={60}
    width={1920}
    height={1080}
    defaultProps={{}}
  />
);
