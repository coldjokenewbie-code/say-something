import {Composition} from 'remotion';
import {LatheVideo, TOTAL_FRAMES, FPS} from './Lathe';

export const Root = () => (
  <Composition
    id="Lathe"
    component={LatheVideo}
    durationInFrames={TOTAL_FRAMES}
    fps={FPS}
    width={1280}
    height={720}
  />
);
