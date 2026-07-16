/* Salty Air — 3D hero scene: house, environment, and the dirty→clean
   transformation, all driven by a single progress value (0 = grimy overcast,
   1 = sparkling golden hour).
   Loads assets/models/house.glb when present; otherwise builds a placeholder
   cottage so the choreography can be developed/tested without the asset. */

import * as THREE from "three";
import { GLTFLoader } from "three/addons/loaders/GLTFLoader.js";
import { MeshoptDecoder } from "three/addons/libs/meshopt_decoder.module.js";
import { RoomEnvironment } from "three/addons/environments/RoomEnvironment.js";

// Shared grime uniforms (one set drives every patched material)
const uGrime = { value: 1 };  // stain intensity
const uWipe = { value: 0 };   // wipe front: 0 all dirty → 1 all clean
const uMinY = { value: 0 };
const uMaxY = { value: 6 };

const COL = {
  skyDirty: new THREE.Color(0x76838b), skyClean: new THREE.Color(0xbfe6ef),
  fogDirty: new THREE.Color(0x76838b), fogClean: new THREE.Color(0xd9f0ef),
  hemiDirty: new THREE.Color(0x8a949b), hemiClean: new THREE.Color(0xcfe9ff),
  sunDirty: new THREE.Color(0x9aa4ab), sunClean: new THREE.Color(0xffd9a4),
  lawnDirty: new THREE.Color(0x8a7f57), lawnClean: new THREE.Color(0x62a852),
};

function patchGrime(material) {
  if (!material || !material.isMeshStandardMaterial || material.userData.grimed) return;
  material.userData.grimed = true;
  material.onBeforeCompile = (shader) => {
    shader.uniforms.uGrime = uGrime;
    shader.uniforms.uWipe = uWipe;
    shader.uniforms.uMinY = uMinY;
    shader.uniforms.uMaxY = uMaxY;

    shader.vertexShader = shader.vertexShader
      .replace("#include <common>", "#include <common>\nvarying vec3 vGrimeWorld;")
      .replace("#include <begin_vertex>",
        "#include <begin_vertex>\nvGrimeWorld = (modelMatrix * vec4(transformed, 1.0)).xyz;");

    shader.fragmentShader = shader.fragmentShader
      .replace("#include <common>", `#include <common>
varying vec3 vGrimeWorld;
uniform float uGrime, uWipe, uMinY, uMaxY;
float ghash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float gnoise(vec2 p) {
  vec2 i = floor(p), f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  return mix(mix(ghash(i), ghash(i + vec2(1, 0)), f.x),
             mix(ghash(i + vec2(0, 1)), ghash(i + vec2(1, 1)), f.x), f.y);
}`)
      .replace("#include <color_fragment>", `#include <color_fragment>
{
  float ny = (vGrimeWorld.y - uMinY) / max(uMaxY - uMinY, 0.001);
  float front = 1.12 - uWipe * 1.55;                      // descends roof → ground
  float cleanMask = smoothstep(front, front + 0.22, ny);
  float stains = 0.45 + 0.4 * gnoise(vGrimeWorld.xz * 1.6 + vGrimeWorld.y)
               + 0.35 * gnoise(vec2(vGrimeWorld.x * 5.0 + vGrimeWorld.z * 5.0, vGrimeWorld.y * 1.3));
  float g = uGrime * (1.0 - cleanMask) * clamp(stains, 0.0, 1.0);
  float lum = dot(diffuseColor.rgb, vec3(0.299, 0.587, 0.114));
  vec3 dirty = mix(diffuseColor.rgb, vec3(lum) * vec3(0.62, 0.58, 0.5), 0.55) * 0.7;
  diffuseColor.rgb = mix(diffuseColor.rgb, dirty, g);
}`)
      .replace("#include <roughnessmap_fragment>", `#include <roughnessmap_fragment>
{
  float ny = (vGrimeWorld.y - uMinY) / max(uMaxY - uMinY, 0.001);
  float front = 1.12 - uWipe * 1.55;
  float g = uGrime * (1.0 - smoothstep(front, front + 0.22, ny));
  roughnessFactor = mix(roughnessFactor, min(1.0, roughnessFactor * 1.3 + 0.25), g);
}`);
  };
  material.needsUpdate = true;
}

function buildPlaceholderHouse() {
  const g = new THREE.Group();
  const mWall = new THREE.MeshStandardMaterial({ color: 0xefe8d8, roughness: 0.85 });
  const mRoof = new THREE.MeshStandardMaterial({ color: 0x54626c, roughness: 0.9 });
  const mTrim = new THREE.MeshStandardMaterial({ color: 0x3a4a55, roughness: 0.7 });

  const body = new THREE.Mesh(new THREE.BoxGeometry(7, 3, 5.5), mWall);
  body.position.y = 1.5;
  g.add(body);

  const roofShape = new THREE.Shape([
    new THREE.Vector2(-3.9, 0), new THREE.Vector2(3.9, 0), new THREE.Vector2(0, 2.2),
  ]);
  const roof = new THREE.Mesh(
    new THREE.ExtrudeGeometry(roofShape, { depth: 6.1, bevelEnabled: false }), mRoof);
  roof.position.set(0, 3, -3.05);
  g.add(roof);

  const garage = new THREE.Mesh(new THREE.BoxGeometry(3.4, 2.4, 4.2), mWall);
  garage.position.set(5.1, 1.2, 0.4);
  g.add(garage);
  const gRoofShape = new THREE.Shape([
    new THREE.Vector2(-1.9, 0), new THREE.Vector2(1.9, 0), new THREE.Vector2(0, 1.1),
  ]);
  const gRoof = new THREE.Mesh(
    new THREE.ExtrudeGeometry(gRoofShape, { depth: 4.6, bevelEnabled: false }), mRoof);
  gRoof.position.set(5.1, 2.4, -1.9);
  g.add(gRoof);

  const door = new THREE.Mesh(new THREE.BoxGeometry(1.1, 2.1, 0.08), mTrim);
  door.position.set(-0.6, 1.05, 2.79);
  g.add(door);
  for (const x of [-2.4, 1.6]) {
    const win = new THREE.Mesh(new THREE.BoxGeometry(1.4, 1.2, 0.08), mTrim);
    win.position.set(x, 1.7, 2.79);
    g.add(win);
  }
  return g;
}

let particleTex = null;
function getParticleTexture() {
  if (particleTex) return particleTex;
  const c = document.createElement("canvas");
  c.width = c.height = 64;
  const ctx = c.getContext("2d");
  const grad = ctx.createRadialGradient(32, 32, 0, 32, 32, 32);
  grad.addColorStop(0, "rgba(255,255,255,1)");
  grad.addColorStop(0.35, "rgba(255,255,255,0.7)");
  grad.addColorStop(1, "rgba(255,255,255,0)");
  ctx.fillStyle = grad;
  ctx.fillRect(0, 0, 64, 64);
  particleTex = new THREE.CanvasTexture(c);
  return particleTex;
}

function makeParticles(count, size, color, spread, yBase, yTop) {
  const pos = new Float32Array(count * 3);
  for (let i = 0; i < count; i++) {
    pos[i * 3] = (Math.random() - 0.5) * spread;
    pos[i * 3 + 1] = yBase + Math.random() * (yTop - yBase);
    pos[i * 3 + 2] = (Math.random() - 0.5) * spread;
  }
  const geo = new THREE.BufferGeometry();
  geo.setAttribute("position", new THREE.BufferAttribute(pos, 3));
  const mat = new THREE.PointsMaterial({
    color, size, transparent: true, opacity: 0, map: getParticleTexture(),
    depthWrite: false, blending: THREE.AdditiveBlending, sizeAttenuation: true,
  });
  return new THREE.Points(geo, mat);
}

export async function createScene(canvas) {
  const renderer = new THREE.WebGLRenderer({ canvas, antialias: true });
  renderer.setPixelRatio(Math.min(devicePixelRatio, window.innerWidth > 960 ? 2 : 1.5));
  renderer.setSize(innerWidth, innerHeight, false);
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  renderer.shadowMap.enabled = true;
  renderer.shadowMap.type = THREE.PCFSoftShadowMap;

  const scene = new THREE.Scene();
  scene.background = new THREE.Color();
  scene.fog = new THREE.FogExp2(0x76838b, 0.028);
  const pmrem = new THREE.PMREMGenerator(renderer);
  scene.environment = pmrem.fromScene(new RoomEnvironment(renderer), 0.04).texture;
  scene.environmentIntensity = 0.25;

  const camera = new THREE.PerspectiveCamera(42, innerWidth / innerHeight, 0.1, 300);
  const fitFov = () => {
    const a = innerWidth / innerHeight;
    camera.fov = a >= 1.4 ? 42 : a >= 1 ? 48 : 58; // wider lens on narrow screens
  };
  fitFov();

  const hemi = new THREE.HemisphereLight(0x8a949b, 0x55524a, 0.9);
  scene.add(hemi);
  const sun = new THREE.DirectionalLight(0x9aa4ab, 0.4);
  sun.position.set(-14, 6, 10);
  sun.castShadow = true;
  sun.shadow.mapSize.set(2048, 2048);
  sun.shadow.camera.left = sun.shadow.camera.bottom = -14;
  sun.shadow.camera.right = sun.shadow.camera.top = 14;
  sun.shadow.bias = -0.0004;
  scene.add(sun);

  const lawnMat = new THREE.MeshStandardMaterial({ color: 0x8a7f57, roughness: 1 });
  const lawn = new THREE.Mesh(new THREE.CircleGeometry(80, 48), lawnMat);
  lawn.rotation.x = -Math.PI / 2;
  lawn.receiveShadow = true;
  scene.add(lawn);

  // House: real model if present, placeholder otherwise
  let house;
  try {
    const loader = new GLTFLoader().setMeshoptDecoder(MeshoptDecoder);
    const gltf = await loader.loadAsync("assets/models/house.glb");
    house = gltf.scene;
    // Normalize: sit on ground, center at origin, ~8 world units wide
    const box = new THREE.Box3().setFromObject(house);
    const sizeV = box.getSize(new THREE.Vector3());
    const s = 8 / Math.max(sizeV.x, sizeV.z);
    house.scale.setScalar(s);
    box.setFromObject(house);
    const c = box.getCenter(new THREE.Vector3());
    house.position.set(-c.x, -box.min.y, -c.z);
  } catch {
    house = buildPlaceholderHouse();
  }
  scene.add(house);

  const hbox = new THREE.Box3().setFromObject(house);
  uMinY.value = hbox.min.y;
  uMaxY.value = hbox.max.y;
  house.traverse((o) => {
    if (o.isMesh) {
      o.castShadow = true;
      o.receiveShadow = true;
      const mats = Array.isArray(o.material) ? o.material : [o.material];
      mats.forEach(patchGrime);
    }
  });
  patchGrime(lawnMat);

  const dust = makeParticles(360, 0.09, 0xa89a7c, 26, 0.2, 6.5);
  const sparkles = makeParticles(220, 0.14, 0xffe9c0, 20, 0.5, 7.5);
  scene.add(dust, sparkles);

  // Camera path (positions + look targets), scrubbed by progress
  const camPath = new THREE.CatmullRomCurve3([
    new THREE.Vector3(-10, 2.6, 13.5),
    new THREE.Vector3(-3, 3.0, 15.5),
    new THREE.Vector3(10.5, 3.6, 11),
    new THREE.Vector3(1.5, 4.8, 18.5),
  ]);
  const lookPath = new THREE.CatmullRomCurve3([
    new THREE.Vector3(0, 1.9, 0),
    new THREE.Vector3(0, 2.0, 0),
    new THREE.Vector3(0, 2.0, 0),
    new THREE.Vector3(-7, 2.5, 0),
  ]);

  const _pos = new THREE.Vector3();
  const _look = new THREE.Vector3();
  const _dir = new THREE.Vector3();

  function update(p, pointer, t) {
    const e = p * p * (3 - 2 * p); // smoothstep ease on the whole journey

    // Transformation timing: grime wipe runs 0.15→0.85 of the scroll
    const wipe = Math.min(1, Math.max(0, (p - 0.15) / 0.7));
    uWipe.value = wipe * wipe * (3 - 2 * wipe);
    uGrime.value = 1;

    const env = Math.min(1, Math.max(0, (p - 0.1) / 0.75)); // sky/light ramp
    scene.background.lerpColors(COL.skyDirty, COL.skyClean, env);
    scene.fog.color.lerpColors(COL.fogDirty, COL.fogClean, env);
    scene.fog.density = 0.021 - 0.017 * env;
    hemi.color.lerpColors(COL.hemiDirty, COL.hemiClean, env);
    hemi.intensity = 1.05 + 0.4 * env;
    sun.color.lerpColors(COL.sunDirty, COL.sunClean, env);
    sun.intensity = 0.55 + 2.05 * env;
    sun.position.set(-14 + 26 * env, 6 + 14 * env, 10 + 4 * env);
    renderer.toneMappingExposure = 0.85 + 0.42 * env;
    scene.environmentIntensity = 0.25 + 0.85 * env;
    lawnMat.color.lerpColors(COL.lawnDirty, COL.lawnClean, env);

    dust.material.opacity = 0.5 * (1 - Math.min(1, p * 1.8));
    dust.rotation.y = t * 0.00004;
    const sp = Math.min(1, Math.max(0, (p - 0.68) / 0.25));
    sparkles.material.opacity = sp * (0.65 + 0.35 * Math.sin(t * 0.004));
    sparkles.position.y = sp * 1.6;
    sparkles.rotation.y = -t * 0.00006;

    camPath.getPoint(e, _pos);
    lookPath.getPoint(e, _look);
    // keep the house centered on portrait screens (the sideways look offset
    // only makes sense when there's copy beside it); there, drop it below the
    // stacked copy instead
    const wide = THREE.MathUtils.clamp(camera.aspect - 0.9, 0, 1);
    const finaleWeight = Math.abs(_look.x) / 7; // 0 early in the path → 1 at the finale
    _look.x *= wide;
    _look.y += (1 - wide) * 1.4 * finaleWeight;
    // gentle mouse parallax
    _pos.x += pointer.x * 0.7;
    _pos.y += -pointer.y * 0.4;
    // dolly out on narrow screens so the house fits horizontally (~14 units)
    _dir.subVectors(_pos, _look);
    const span = camera.aspect < 1 ? 16 : 14;
    const dNeed = span / (2 * Math.tan(THREE.MathUtils.degToRad(camera.fov / 2)) * camera.aspect);
    if (dNeed > _dir.length()) _dir.setLength(dNeed);
    camera.position.copy(_look).add(_dir);
    camera.lookAt(_look);

    renderer.render(scene, camera);
  }

  function resize() {
    camera.aspect = innerWidth / innerHeight;
    fitFov();
    camera.updateProjectionMatrix();
    renderer.setSize(innerWidth, innerHeight, false);
  }

  return { update, resize };
}
