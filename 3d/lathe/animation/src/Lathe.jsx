import React, {useEffect, useMemo, useState} from 'react';
import {
  AbsoluteFill, useCurrentFrame, useVideoConfig, interpolate,
  Easing, staticFile, delayRender, continueRender,
} from 'remotion';
import {ThreeCanvas} from '@remotion/three';
import {useThree} from '@react-three/fiber';
import * as THREE from 'three';
import {GLTFLoader} from 'three/examples/jsm/loaders/GLTFLoader.js';
import {RoomEnvironment} from 'three/examples/jsm/environments/RoomEnvironment.js';

export const FPS = 30;
export const TOTAL_FRAMES = 1260; // 42 秒

// ---- CAD 座標基準 (mm, Z-up; 模型最外層 group 旋轉 -90°X 轉成 three 的 Y-up) ----
const SPIN_Z = 900;          // 主軸中心高
const WP_X0 = 450, WP_X1 = 780, WP_R = 30; // 工件原始尺寸
const CUT_R = 22;            // 車削後外徑半徑
const HOLE_R = 15;           // 鑽孔半徑
const QUILL_REAR = 1090;     // 尾座套筒後端 x

const clamp = {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'};
const ease = {...clamp, easing: Easing.inOut(Easing.cubic)};

// ---------- 時間軸(影格) ----------
const T = {
  orbitEnd: 510,        // 全景環繞 + 部位介紹結束
  chuckCamEnd: 630,     // 推近卡盤
  machCamEnd: 690,      // 切到加工固定鏡頭
  spinUp: [660, 720],
  turn: [720, 960],     // 外圓車削
  toolIn: [690, 715],
  toolOut: [960, 985],
  tsSlide: [960, 1010], // 尾座滑近
  drill: [1020, 1105],  // 套筒伸出鑽孔
  drillBack: [1110, 1160],
  tsBack: [1165, 1205],
  spinDown: [1140, 1210],
  endCam: [1150, 1240],
};

// ---------- 字幕 ----------
const CAPTIONS = [
  {from: 8, to: 140, title: '車床加工模擬', sub: '從實心棒料到管件', big: true},
  {from: 150, to: 210, title: '床身與導軌', sub: '機器的基座，V 形導軌引導溜板精確移動', targets: ['bed', 'way_0', 'way_1', 'leg_0', 'leg_1']},
  {from: 210, to: 270, title: '主軸箱', sub: '內含齒輪變速機構，驅動主軸旋轉', targets: ['headstock', 'lever_0', 'knob_0', 'lever_1', 'knob_1']},
  {from: 270, to: 330, title: '三爪卡盤', sub: '三個卡爪同步收緊，夾持工件並帶動旋轉', targets: ['chuck_body', 'jaw_0', 'jaw_1', 'jaw_2']},
  {from: 330, to: 390, title: '溜板與刀架', sub: '承載車刀，控制縱向與橫向進給', targets: ['saddle', 'cross_slide', 'compound', 'toolpost', 'toolbit', 'apron']},
  {from: 390, to: 450, title: '尾座', sub: '支撐長工件，也可安裝鑽頭鑽孔', targets: ['tailstock_base', 'tailstock_body', 'quill', 'dead_center', 'ts_wheel']},
  {from: 450, to: 510, title: '導螺桿與光桿', sub: '把進給動力傳給溜板掛箱', targets: ['leadscrew', 'feedrod']},
  {from: 520, to: 625, title: '夾緊工件', sub: '三爪卡盤同步夾緊棒料'},
  {from: 715, to: 955, title: '外圓車削', sub: '工件高速旋轉，車刀沿縱向進給切除外層'},
  {from: 965, to: 1105, title: '尾座鑽孔', sub: '鑽頭從尾座伸入，鑽出內孔'},
  {from: 1170, to: 1256, title: '完成！', sub: '實心棒料已車削成一根管件'},
];

const STATIC_PARTS = [
  'leg_0', 'leg_1', 'chip_tray', 'bed', 'way_0', 'way_1', 'headstock',
  'lever_0', 'knob_0', 'lever_1', 'knob_1', 'leadscrew', 'feedrod',
];

// ---------- 動畫計算 ----------
const spinAngle = (f) => {
  const W = 0.38; // 最高轉速 rad/frame
  const [u0, u1] = T.spinUp, [d0, d1] = T.spinDown;
  const ru = u1 - u0, rd = d1 - d0;
  if (f <= u0) return 0;
  if (f <= u1) { const t = f - u0; return 0.5 * W * t * t / ru; }
  const a1 = 0.5 * W * ru;
  if (f <= d0) return a1 + W * (f - u1);
  const a2 = a1 + W * (d0 - u1);
  if (f <= d1) { const t = f - d0; return a2 + W * t - 0.5 * W * t * t / rd; }
  return a2 + 0.5 * W * rd;
};

// 車削切削邊界(已切到的 x 位置, 由右向左)
const cutX = (f) => interpolate(f, T.turn, [WP_X1, 470], clamp);
// 溜板 x 位移(刀尖 = 溜板基準 - 95 對齊切削邊界)
const carDX = (f) => cutX(f) - 625 - 720 + 720; // = cutX - 625
// 橫向進刀(0 = 切入, -45 = 退刀)
const toolEY = (f) =>
  interpolate(f, [...T.toolIn, ...T.toolOut], [-45, 0, 0, -45], clamp);
// 尾座滑移
const tsDX = (f) =>
  interpolate(f, [...T.tsSlide, ...T.tsBack], [0, -78, -78, 0], clamp);
// 套筒伸長倍率(以後端為支點)
const quillS = (f) =>
  interpolate(f, [...T.drill, ...T.drillBack], [1, 2.875, 2.875, 1], clamp);
// 鑽孔深度(只增不減)
const holeDepth = (f) => interpolate(f, [1024, 1105], [0, 148], clamp);
// 卡爪夾緊位移
const jawGrip = (f) => interpolate(f, [528, 565], [0, -5], ease);

// ---------- 相機 ----------
const lerp3 = (f, f0, f1, A, B, e = ease) => [
  interpolate(f, [f0, f1], [A[0], B[0]], e),
  interpolate(f, [f0, f1], [A[1], B[1]], e),
  interpolate(f, [f0, f1], [A[2], B[2]], e),
];

const orbitPos = (f) => {
  const a = interpolate(f, [0, T.orbitEnd], [-0.75, 0.5], {...clamp, easing: Easing.inOut(Easing.sin)});
  const h = interpolate(f, [0, T.orbitEnd], [1450, 1180], clamp);
  return [700 + 2150 * Math.sin(a), h, 2150 * Math.cos(a)];
};

const CHUCK_CAM = [835, 1120, 700], CHUCK_LA = [470, 890, 0];
const MACH_CAM = [1100, 1120, 900], MACH_LA = [640, 890, 10];
const END_CAM = [1360, 980, 430], END_LA = [792, 895, 0];

const cameraAt = (f) => {
  if (f <= T.orbitEnd) return {pos: orbitPos(f), la: [700, 680, 0]};
  if (f <= T.chuckCamEnd)
    return {
      pos: lerp3(f, T.orbitEnd, T.chuckCamEnd, orbitPos(T.orbitEnd), CHUCK_CAM),
      la: lerp3(f, T.orbitEnd, T.chuckCamEnd, [700, 680, 0], CHUCK_LA),
    };
  if (f <= T.machCamEnd)
    return {
      pos: lerp3(f, T.chuckCamEnd, T.machCamEnd, CHUCK_CAM, MACH_CAM),
      la: lerp3(f, T.chuckCamEnd, T.machCamEnd, CHUCK_LA, MACH_LA),
    };
  if (f <= T.endCam[0]) return {pos: MACH_CAM, la: MACH_LA};
  return {
    pos: lerp3(f, T.endCam[0], T.endCam[1], MACH_CAM, END_CAM),
    la: lerp3(f, T.endCam[0], T.endCam[1], MACH_LA, END_LA),
  };
};

// ---------- 工件(動態車削幾何: 毛坯/已加工 兩段不同材質) ----------
const WorkpieceMesh = ({frame}) => {
  const L = WP_X1 - WP_X0;
  const tc = Math.max(20, Math.min(L, cutX(frame) - WP_X0)); // 切削邊界(局部)
  const depth = holeDepth(frame);

  const rawGeo = useMemo(() => {
    const pts = [
      new THREE.Vector2(0.01, 0), new THREE.Vector2(WP_R, 0),
      new THREE.Vector2(WP_R, tc), new THREE.Vector2(0.01, tc),
    ];
    return new THREE.LatheGeometry(pts, 48);
  }, [tc]);

  const machGeo = useMemo(() => {
    if (tc >= L - 0.5) return null;
    const pts = [new THREE.Vector2(0.01, tc), new THREE.Vector2(CUT_R, tc), new THREE.Vector2(CUT_R, L)];
    if (depth > 0.5) {
      pts.push(new THREE.Vector2(HOLE_R, L));
      pts.push(new THREE.Vector2(HOLE_R, L - depth));
      pts.push(new THREE.Vector2(0.01, L - depth));
    } else {
      pts.push(new THREE.Vector2(0.01, L));
    }
    return new THREE.LatheGeometry(pts, 48);
  }, [tc, depth]);

  useEffect(() => () => { rawGeo.dispose(); machGeo?.dispose(); }, [rawGeo, machGeo]);
  return (
    <group position={[WP_X0, 0, SPIN_Z]} rotation={[0, 0, -Math.PI / 2]}>
      <mesh geometry={rawGeo}>
        <meshStandardMaterial color="#b9913f" metalness={0.55} roughness={0.45} />
      </mesh>
      {machGeo ? (
        <mesh geometry={machGeo}>
          <meshStandardMaterial color="#f0cf8a" metalness={0.85} roughness={0.18} side={THREE.DoubleSide} />
        </mesh>
      ) : null}
    </group>
  );
};

// ---------- 火花 ----------
const Sparks = ({frame}) => {
  const dirs = useMemo(() => {
    const rnd = (s) => { const x = Math.sin(s * 127.1 + 311.7) * 43758.5453; return x - Math.floor(x); };
    return Array.from({length: 16}, (_, i) => ({
      dx: (rnd(i) - 0.6) * 5, dy: -(2 + rnd(i + 40) * 5), dz: (1 + rnd(i + 80) * 5),
      phase: Math.floor(rnd(i + 120) * 9), life: 8 + Math.floor(rnd(i + 160) * 5),
    }));
  }, []);
  const [t0, t1] = T.turn;
  if (frame < t0 + 4 || frame > t1 - 2) return null;
  const tip = [cutX(frame), -26, SPIN_Z + 2];
  return (
    <group>
      <pointLight position={tip} color="#ffb84d" intensity={4} distance={600} decay={2} />
      <mesh position={tip}>
        <sphereGeometry args={[8, 10, 10]} />
        <meshBasicMaterial color="#ffd980" />
      </mesh>
      {dirs.map((d, i) => {
        const age = (frame + d.phase) % d.life;
        const t = age / d.life;
        const p = [tip[0] + d.dx * age * 1.5, tip[1] + d.dy * age * 1.5, tip[2] + d.dz * age * 1.5 - 0.35 * age * age];
        const s = 6 * (1 - t) + 1;
        return (
          <mesh key={i} position={p} scale={[s, s, s]}>
            <sphereGeometry args={[1, 6, 6]} />
            <meshBasicMaterial color={t < 0.45 ? '#ffd34d' : '#ff7a30'} transparent opacity={1 - t * 0.7} />
          </mesh>
        );
      })}
    </group>
  );
};

// ---------- 3D 場景 ----------
const Scene = ({gltf}) => {
  const frame = useCurrentFrame();
  const camera = useThree((s) => s.camera);
  const gl = useThree((s) => s.gl);
  const scene3 = useThree((s) => s.scene);

  useEffect(() => {
    const pmrem = new THREE.PMREMGenerator(gl);
    const env = pmrem.fromScene(new RoomEnvironment(), 0.04).texture;
    scene3.environment = env;
    return () => { scene3.environment = null; env.dispose(); pmrem.dispose(); };
  }, [gl, scene3]);

  const nodes = useMemo(() => {
    const map = {};
    gltf.scene.traverse((o) => {
      if (o.isMesh) {
        o.material = o.material.clone(); // 取消共用材質, 才能個別高亮
        o.material.metalness = 0.35;
        o.material.roughness = 0.5;
      }
    });
    gltf.scene.traverse((o) => { if (o.name) map[o.name] = o; });
    return map;
  }, [gltf]);

  // 卡爪徑向方向(YZ 平面)
  const jawDirs = useMemo(() => {
    return [0, 1, 2].map((i) => {
      const box = new THREE.Box3().setFromObject(nodes[`jaw_${i}`]);
      const c = box.getCenter(new THREE.Vector3());
      const v = new THREE.Vector2(c.y, c.z - SPIN_Z).normalize();
      return v;
    });
  }, [nodes]);

  // 相機(直接在 render body 更新 — remotion 同步渲染, useEffect 不會觸發重繪)
  {
    const {pos, la} = cameraAt(frame);
    camera.position.set(pos[0], pos[1], pos[2]);
    camera.fov = 40;
    camera.near = 10;
    camera.far = 20000;
    camera.lookAt(la[0], la[1], la[2]);
    camera.updateProjectionMatrix();
  }

  // 部位介紹高亮(每影格先全部歸零再點亮目標, 保持確定性)
  const active = CAPTIONS.find((c) => c.targets && frame >= c.from && frame < c.to);
  Object.values(nodes).forEach((o) => {
    o.traverse((m) => { if (m.isMesh && m.material.emissive) m.material.emissive.setRGB(0, 0, 0); });
  });
  if (active) {
    const k = 0.22 + 0.2 * (1 + Math.sin(frame * 0.32));
    active.targets.forEach((nm) => {
      nodes[nm]?.traverse((m) => { if (m.isMesh && m.material.emissive) m.material.emissive.setRGB(k, k * 0.95, k * 0.55); });
    });
  }

  const spin = spinAngle(frame);
  const dxc = carDX(frame);
  const ey = toolEY(frame);
  const dxts = tsDX(frame);
  const s = quillS(frame);
  const grip = jawGrip(frame);
  const drillVisible = frame >= 945;
  const apronSpin = -dxc * 0.06;
  const tsWheelSpin = (s - 1) * 6;
  const quillFront = QUILL_REAR + dxts - 80 * s;

  const P = (n) => <primitive object={nodes[n]} />;

  return (
    <>
      <hemisphereLight args={['#d6dde8', '#3a3d42', 0.95]} />
      <directionalLight position={[1500, 3200, 2600]} intensity={1.7} />
      <directionalLight position={[-1400, 1800, -1600]} intensity={0.45} />
      <mesh rotation={[-Math.PI / 2, 0, 0]} position={[700, -1, 0]}>
        <planeGeometry args={[14000, 14000]} />
        <meshStandardMaterial color="#23262c" roughness={1} metalness={0} />
      </mesh>

      {/* CAD 座標群組 (Z-up → Y-up) */}
      <group rotation={[-Math.PI / 2, 0, 0]}>
        {STATIC_PARTS.map((n) => <group key={n}>{P(n)}</group>)}

        {/* 主軸旋轉群組 */}
        <group position={[0, 0, SPIN_Z]}>
          <group rotation={[spin, 0, 0]}>
            <group position={[0, 0, -SPIN_Z]}>
              {P('spindle')}{P('chuck_body')}
              {[0, 1, 2].map((i) => (
                <group key={i} position={[0, jawDirs[i].x * grip, jawDirs[i].y * grip]}>
                  {P(`jaw_${i}`)}
                </group>
              ))}
              <WorkpieceMesh frame={frame} />
            </group>
          </group>
        </group>

        {/* 溜板群組 */}
        <group position={[dxc, 0, 0]}>
          {P('saddle')}{P('apron')}{P('apron_handle')}
          <group position={[660, 0, 670]}>
            <group rotation={[0, apronSpin, 0]}>
              <group position={[-660, 0, -670]}>{P('apron_wheel')}</group>
            </group>
          </group>
          <group position={[0, ey, 0]}>
            {P('cross_slide')}{P('compound')}{P('toolpost')}{P('toolbit')}
            {P('cross_wheel')}{P('cross_handle')}
          </group>
        </group>

        {/* 尾座群組 */}
        <group position={[dxts, 0, 0]}>
          {P('tailstock_base')}{P('tailstock_body')}{P('ts_handle')}
          <group position={[1270, 0, SPIN_Z]}>
            <group rotation={[tsWheelSpin, 0, 0]}>
              <group position={[-1270, 0, -SPIN_Z]}>{P('ts_wheel')}</group>
            </group>
          </group>
          {/* 套筒以後端為支點伸長 */}
          <group position={[QUILL_REAR, 0, SPIN_Z]}>
            <group scale={[s, 1, 1]}>
              <group position={[-QUILL_REAR, 0, -SPIN_Z]}>{P('quill')}</group>
            </group>
          </group>
          <group visible={!drillVisible}>{P('dead_center')}</group>
        </group>

        {/* 鑽頭(掛在套筒前端, 不隨倍率縮放) */}
        <group position={[quillFront, 0, SPIN_Z]} visible={drillVisible}>
          <mesh position={[-60, 0, 0]} rotation={[0, 0, Math.PI / 2]}>
            <cylinderGeometry args={[14.5, 14.5, 120, 24]} />
            <meshStandardMaterial color="#4a4e55" metalness={0.7} roughness={0.35} />
          </mesh>
          <mesh position={[-135, 0, 0]} rotation={[0, 0, Math.PI / 2]}>
            <coneGeometry args={[13, 30, 24]} />
            <meshStandardMaterial color="#5a5f66" metalness={0.7} roughness={0.3} />
          </mesh>
        </group>

        <Sparks frame={frame} />
      </group>
    </>
  );
};

// ---------- 字幕層 ----------
const Captions = () => {
  const frame = useCurrentFrame();
  const cap = CAPTIONS.find((c) => frame >= c.from && frame < c.to);
  if (!cap) return null;
  const op = interpolate(frame, [cap.from, cap.from + 12, cap.to - 12, cap.to], [0, 1, 1, 0], clamp);
  const fontStack = '"Noto Sans CJK TC", "Noto Sans CJK SC", "WenQuanYi Zen Hei", sans-serif';
  if (cap.big) {
    return (
      <AbsoluteFill style={{justifyContent: 'center', alignItems: 'center', opacity: op}}>
        <div style={{fontFamily: fontStack, color: '#fff', fontSize: 76, fontWeight: 700, textShadow: '0 4px 24px rgba(0,0,0,.8)', letterSpacing: 10}}>
          {cap.title}
        </div>
        <div style={{fontFamily: fontStack, color: '#dfe6ee', fontSize: 32, marginTop: 18, letterSpacing: 6, textShadow: '0 2px 12px rgba(0,0,0,.8)'}}>
          {cap.sub}
        </div>
      </AbsoluteFill>
    );
  }
  return (
    <AbsoluteFill style={{justifyContent: 'flex-end', alignItems: 'center', opacity: op}}>
      <div style={{
        fontFamily: fontStack, marginBottom: 44, padding: '18px 42px', borderRadius: 16,
        background: 'rgba(12,14,18,0.72)', backdropFilter: 'blur(4px)',
        border: '1px solid rgba(255,255,255,0.14)', textAlign: 'center', maxWidth: 980,
      }}>
        <div style={{color: '#ffd34d', fontSize: 36, fontWeight: 700, letterSpacing: 4}}>{cap.title}</div>
        {cap.sub ? <div style={{color: '#e8edf3', fontSize: 23, marginTop: 8, letterSpacing: 2}}>{cap.sub}</div> : null}
      </div>
    </AbsoluteFill>
  );
};

// ---------- 主組件 ----------
export const LatheVideo = () => {
  const {width, height} = useVideoConfig();
  const [gltf, setGltf] = useState(null);
  const [handle] = useState(() => delayRender('load lathe.glb'));

  useEffect(() => {
    new GLTFLoader().load(staticFile('lathe.glb'), (g) => {
      setGltf(g);
      continueRender(handle);
    });
  }, [handle]);

  return (
    <AbsoluteFill style={{background: 'radial-gradient(120% 90% at 50% 30%, #2d333d 0%, #181b20 70%, #101216 100%)'}}>
      {gltf ? (
        <ThreeCanvas width={width} height={height} gl={{alpha: true, antialias: true}}>
          <Scene gltf={gltf} />
        </ThreeCanvas>
      ) : null}
      <Captions />
    </AbsoluteFill>
  );
};
