import './style.css';
import * as THREE from 'three';
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';
import type { GLTF } from 'three/examples/jsm/loaders/GLTFLoader.js';

declare const __PROMOBU_MODEL_URL__: string | null;

const canvas = document.getElementById('app') as HTMLCanvasElement | null;
if (!canvas) {
  throw new Error('Canvas #app not found');
}

const modelPaths = __PROMOBU_MODEL_URL__
  ? [__PROMOBU_MODEL_URL__]
  : ['/model.glb', '/model.gltf', '/public/model.glb', '/public/model.gltf'];

const renderer = new THREE.WebGLRenderer({ canvas, antialias: true });
renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
renderer.setSize(window.innerWidth, window.innerHeight);
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFSoftShadowMap;

const scene = new THREE.Scene();
scene.background = new THREE.Color(0x16181d);

const camera = new THREE.PerspectiveCamera(55, window.innerWidth / window.innerHeight, 0.1, 2000);
camera.position.set(6, 4, 8);

const ambient = new THREE.AmbientLight(0xffffff, 0.75);
scene.add(ambient);

const sun = new THREE.DirectionalLight(0xfff1d6, 1.25);
sun.position.set(28, 42, 24);
sun.castShadow = true;
sun.shadow.mapSize.set(2048, 2048);
sun.shadow.bias = -0.0002;
sun.shadow.normalBias = 0.02;
sun.shadow.radius = 4;
sun.target.position.set(0, 0, 0);
scene.add(sun);
scene.add(sun.target);

const sunMarker = new THREE.Mesh(
  new THREE.CircleGeometry(1.15, 48),
  new THREE.MeshBasicMaterial({
    color: 0xffe3a3,
    transparent: true,
    opacity: 0.9,
    depthWrite: false
  })
);
sunMarker.position.copy(sun.position);
sunMarker.renderOrder = 10;
scene.add(sunMarker);

const shadowCatcher = new THREE.Mesh(
  new THREE.PlaneGeometry(1, 1),
  new THREE.ShadowMaterial({ color: 0x000000, opacity: 0.35 })
);
shadowCatcher.rotation.x = -Math.PI / 2;
shadowCatcher.receiveShadow = true;
shadowCatcher.visible = true;
scene.add(shadowCatcher);

const axes = new THREE.AxesHelper(2);
scene.add(axes);

const controls = new OrbitControls(camera, renderer.domElement);
controls.enableDamping = true;
controls.dampingFactor = 0.08;
controls.target.set(0, 0, 0);
controls.update();

let activeModel: THREE.Object3D | null = null;
let hasFramedInitialModel = false;
let errorEl: HTMLDivElement | null = null;
const loader = new GLTFLoader();

const showError = (message: string | null) => {
  if (errorEl) {
    errorEl.remove();
    errorEl = null;
  }
  if (!message) {
    return;
  }
  errorEl = document.createElement('div');
  errorEl.className = 'error';
  errorEl.textContent = message;
  document.body.appendChild(errorEl);
};

const loadOne = (url: string): Promise<GLTF> => {
  const sep = url.includes('?') ? '&' : '?';
  const bustedUrl = `${url}${sep}t=${Date.now()}`;
  return new Promise((resolve, reject) => {
    loader.load(bustedUrl, resolve, undefined, reject);
  });
};

const loadModel = async (keepCamera: boolean) => {
  for (const path of modelPaths) {
    try {
      const gltf = await loadOne(path);
      const model = gltf.scene;

      const box = new THREE.Box3().setFromObject(model);
      const center = box.getCenter(new THREE.Vector3());
      const size = box.getSize(new THREE.Vector3());
      const maxDim = Math.max(size.x, size.y, size.z);
      const bottomY = -size.y * 0.5;

      model.position.sub(center);
      model.traverse((child: THREE.Object3D) => {
        if ((child as THREE.Mesh).isMesh) {
          const mesh = child as THREE.Mesh;
          mesh.castShadow = true;
          mesh.receiveShadow = true;
        }
      });

      const shadowExtent = Math.max(maxDim * 3.0, 20);
      shadowCatcher.scale.set(shadowExtent, shadowExtent, 1);
      shadowCatcher.position.set(0, bottomY - 0.02, 0);

      const shadowFrustum = Math.max(maxDim * 1.8, 12);
      sun.shadow.camera.left = -shadowFrustum;
      sun.shadow.camera.right = shadowFrustum;
      sun.shadow.camera.top = shadowFrustum;
      sun.shadow.camera.bottom = -shadowFrustum;
      sun.shadow.camera.near = 0.5;
      sun.shadow.camera.far = Math.max(maxDim * 8.0, 120);
      sun.shadow.camera.updateProjectionMatrix();

      if (!keepCamera) {
        const fitDist = maxDim > 0 ? maxDim * 1.6 : 10;
        camera.position.set(fitDist, fitDist * 0.7, fitDist);
        camera.lookAt(0, 0, 0);
        controls.target.set(0, 0, 0);
        controls.update();
      }

      if (activeModel) {
        scene.remove(activeModel);
      }
      activeModel = model;
      scene.add(model);
      showError(null);
      return;
    } catch (err: unknown) {
      console.error('Failed to load model:', path, err);
    }
  }

  showError(`Failed to load model: ${modelPaths.join(', ')}`);
};

const reloadModel = () => {
  // Preserve current camera + orbit state while refreshing geometry.
  void loadModel(hasFramedInitialModel).finally(() => {
    if (!hasFramedInitialModel) {
      hasFramedInitialModel = true;
    }
  });
};

reloadModel();

if (import.meta.hot) {
  import.meta.hot.on('promobu:model-changed', () => {
    reloadModel();
  });
}

window.addEventListener('resize', () => {
  camera.aspect = window.innerWidth / window.innerHeight;
  camera.updateProjectionMatrix();
  renderer.setSize(window.innerWidth, window.innerHeight);
});

const animate = () => {
  controls.update();
  sunMarker.lookAt(camera.position);
  renderer.render(scene, camera);
  requestAnimationFrame(animate);
};

animate();
