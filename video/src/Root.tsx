import { Composition } from "remotion";
import { Intro } from "./Intro";
import spec from "./tracks.json";

const common = { component: Intro, durationInFrames: spec.total, fps: spec.fps, width: 1920, height: 1080 } as const;
export const Root = () => (
  <>
    <Composition id="Intro" {...common} defaultProps={{ lang: "en" as const }} />
    <Composition id="IntroZh" {...common} defaultProps={{ lang: "zh" as const }} />
    <Composition id="Poster" {...common} defaultProps={{ lang: "en" as const, noCaptions: true }} />
  </>
);
