#version 460 core
#include <flutter/runtime_effect.glsl>

precision highp float;

// Frank's face: a liquid-plasma glass sphere.
//
// lib/widgets/frank_orb.dart sets these uniforms by index, in declaration
// order, so keep the two in sync. Lengths are in sphere units (radius 1).
uniform vec2 uSize;      // 0-1   painted square, logical px
uniform float uRadius;   // 2     sphere radius, logical px
uniform float uPixel;    // 3     one physical pixel, in sphere units
uniform float uTime;     // 4     seconds, wrapped on the CPU
uniform float uSwirl;    // 5     plasma rotation, radians (CPU-integrated)
uniform float uOrbit;    // 6     ring and spark orbit phase, radians
uniform float uEnergy;   // 7     0..1
uniform float uAmp;      // 8     voice or speech envelope, 0..1
uniform float uMembrane; // 9     surface wobble, 0..0.08
uniform float uRing;     // 10    thinking torus, 0..1
uniform float uSparks;   // 11    tool satellites, 0..1
uniform float uWaveA;    // 12    speaking ring progress 0..1, < 0 off
uniform float uWaveB;    // 13    a second speaking ring
uniform float uFlash;    // 14    done / wake flash, 0..1
uniform float uDesat;    // 15    0 full colour .. 1 grey
uniform float uShake;    // 16    head-shake offset, -1..1
uniform float uKey;      // 17    plasma key light: -1 from above, +1 from below
uniform float uHalo;     // 18    outer glow gain
uniform float uDetail;   // 19    0 tiny (16dp) .. 1 hero (72dp and up)
uniform float uDensity;  // 20    plasma scale (transcribing squeezes it)
uniform float uOpacity;  // 21
uniform vec3 uC0;        // 22-24 four cyclic palette stops
uniform vec3 uC1;        // 25-27
uniform vec3 uC2;        // 28-30
uniform vec3 uC3;        // 31-33

out vec4 fragColor;

const float TAU = 6.2831853;

// Octaves are rotated so the plasma never shows the noise lattice.
const mat2 OCTAVE = mat2(1.6, 1.2, -1.2, 1.6);

float gauss(float x, float w) {
  float k = x / w;
  return exp(-k * k);
}

float hash12(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  vec2 s = f * f * (3.0 - 2.0 * f);
  float a = hash12(i);
  float b = hash12(i + vec2(1.0, 0.0));
  float c = hash12(i + vec2(0.0, 1.0));
  float d = hash12(i + vec2(1.0, 1.0));
  return mix(mix(a, b, s.x), mix(c, d, s.x), s.y);
}

float fbm2(vec2 p) {
  return (vnoise(p) * 2.0 + vnoise(OCTAVE * p + vec2(11.7, 5.3))) / 3.0;
}

float fbm3(vec2 p) {
  float v = 0.0;
  float a = 0.5;
  for (int i = 0; i < 3; i++) {
    v += a * vnoise(p);
    p = OCTAVE * p + vec2(11.7, 5.3);
    a *= 0.5;
  }
  return v / 0.875;
}

vec3 pal(float t) {
  t = fract(t) * 4.0;
  float k = smoothstep(0.0, 1.0, fract(t));
  if (t < 1.0) {
    return mix(uC0, uC1, k);
  }
  if (t < 2.0) {
    return mix(uC1, uC2, k);
  }
  if (t < 3.0) {
    return mix(uC2, uC3, k);
  }
  return mix(uC3, uC0, k);
}

// Tone map, desaturate, fade and dither; returns premultiplied colour.
vec4 finish(vec3 rgb, float alpha, vec2 frag) {
  rgb = 1.0 - exp(-rgb * 1.3);
  float lum = dot(rgb, vec3(0.2126, 0.7152, 0.0722));
  rgb = mix(rgb, vec3(lum) * vec3(0.8, 0.85, 0.95), uDesat);
  alpha = clamp(alpha, 0.0, 1.0) * uOpacity;
  rgb *= uOpacity;
  // OLED dither so the halo never bands.
  rgb += (hash12(frag * 1.37) - 0.5) / 255.0 * alpha;
  return vec4(max(rgb, vec3(0.0)), alpha);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 p = (frag - 0.5 * uSize) / uRadius;
  p.x -= uShake * 0.12;

  float r = length(p);
  float ang = atan(p.y, p.x);
  float hueA = ang / TAU;
  float aa = 1.25 * uPixel;
  float reach = 0.5 * min(uSize.x, uSize.y) / uRadius;
  // Every light outside the glass fades out before the painted square ends.
  float fence = 1.0 - smoothstep(reach * 0.76, reach, r);

  // Liquid membrane: a seamless wobble of the silhouette (sampled on the
  // unit circle, so there is no seam where the angle wraps).
  float R = 1.0 + 0.06 * uFlash;
  if (uMembrane > 0.0005) {
    vec2 dir = p / max(r, 1e-4);
    float n = vnoise(dir * 1.7 + vec2(uTime * 0.9, -uTime * 0.7));
    float lobes = sin(3.0 * ang + uTime * 2.3);
    R *= 1.0 + uMembrane * (0.65 * (2.0 * n - 1.0) + 0.35 * lobes);
  }
  float edge = R - r;
  float inside = smoothstep(-aa, aa, edge);

  // Outer halo.
  float halo = exp(-max(-edge, 0.0) * mix(9.0, 5.5, uDetail)) * uHalo *
      (0.16 + 0.5 * uEnergy + 0.35 * uAmp + 0.8 * uFlash) * fence;

  // Speaking: rings that leave the surface and fade.
  float wave = 0.0;
  if (uWaveA >= 0.0) {
    float k = 1.0 - uWaveA;
    wave += gauss(r - R - uWaveA * 0.3, 0.02 + 0.03 * uWaveA) * k * k;
  }
  if (uWaveB >= 0.0) {
    float k = 1.0 - uWaveB;
    wave += gauss(r - R - uWaveB * 0.3, 0.02 + 0.03 * uWaveB) * k * k;
  }
  wave *= 0.9 * fence;

  // Thinking: a tilted torus with a bright head orbiting it. Its far half
  // passes behind the glass.
  vec3 ringLight = vec3(0.0);
  float ringA = 0.0;
  if (uRing > 0.001) {
    float tilt = -0.38 + 0.1 * sin(uTime * 0.45);
    float c = cos(tilt);
    float s = sin(tilt);
    vec2 rp = mat2(c, s, -s, c) * p;
    rp.y /= 0.34;
    float d = abs(length(rp) - 1.17 * R);
    float phi = atan(rp.y, rp.x);
    float trail = fract((uOrbit - phi) / TAU);
    float head = max(
      gauss(min(trail, 1.0 - trail), 0.035),
      exp(-trail * 4.0) * smoothstep(0.0, 0.04, trail)
    );
    float far = 1.0 - smoothstep(-0.12, 0.12, rp.y);
    float band = gauss(d, mix(0.07, 0.045, uDetail)) + 0.28 * gauss(d, 0.2);
    ringA = band * (0.26 + 0.74 * head) * uRing * mix(1.0, 0.4, far) *
        (1.0 - far * inside) * fence;
    vec3 tint = pal(phi / TAU + uTime * 0.05);
    ringLight = mix(tint, vec3(1.0), 0.3 * head) * ringA;
  }

  // Tool: three satellites, each with a faint trailing ghost, hidden by the
  // glass on the far side of their orbit.
  vec3 sparkLight = vec3(0.0);
  float sparkA = 0.0;
  if (uSparks > 0.001) {
    float c = cos(-0.32);
    float s = sin(-0.32);
    mat2 tilt = mat2(c, s, -s, c);
    for (int i = 0; i < 3; i++) {
      float a = uOrbit * 2.4 + float(i) * TAU / 3.0;
      float b = a - 0.32;
      vec2 sp = tilt * (vec2(cos(a), sin(a) * 0.38) * 1.16 * R);
      vec2 ghost = tilt * (vec2(cos(b), sin(b) * 0.38) * 1.16 * R);
      float dist = length(p - sp);
      float core = gauss(dist, 0.05);
      float glow = gauss(dist, 0.16) * 0.4 +
          gauss(length(p - ghost), 0.09) * 0.25;
      float vis = sin(a) < 0.0 ? 1.0 - inside : 1.0;
      vec3 tint = pal(float(i) / 3.0 + uTime * 0.1);
      sparkA += (core + glow) * vis;
      sparkLight += (vec3(1.0) * core + tint * glow) * vis;
    }
    sparkA *= uSparks * fence;
    sparkLight *= uSparks * fence;
  }

  vec3 outer = pal(hueA + uTime * 0.03) * halo +
      pal(0.25 + uTime * 0.02) * wave;
  // Light outside the glass is mostly additive (alpha below its colour).
  float glowA = max(max(halo, wave), max(ringA, sparkA)) * 0.7;

  if (edge < -aa) {
    fragColor = glowA < 0.001
        ? vec4(0.0)
        : finish(outer + ringLight + sparkLight, glowA, frag);
    return;
  }

  // The glass body.
  vec2 np = p / max(r, R);
  float rn = length(np);
  float z = sqrt(max(1.0 - rn * rn, 0.0));
  vec3 n = vec3(np, z);
  float keyLit = 0.5 + 0.5 * np.y * uKey;

  // Plasma seen through the glass: magnified in the middle, compressed
  // toward the rim, twisted into a slow vortex, then domain-warped twice so
  // it flows like smoke in liquid.
  float twist = uSwirl + 0.9 * rn * rn;
  float cs = cos(twist);
  float sn = sin(twist);
  vec2 q = mat2(cs, sn, -sn, cs) * (np / (0.55 + 0.45 * z));
  q *= 1.15 * uDensity * mix(0.75, 1.0, uDetail);
  float t = uTime;
  vec2 w1 = vec2(
    fbm2(q + vec2(t * 0.1, 0.0)),
    fbm2(q + vec2(5.2, 1.3 - t * 0.08))
  );
  float warp = 2.2 + 1.8 * uEnergy;
  vec2 w2 = vec2(
    fbm2(q + warp * w1 + vec2(1.7, 9.2 + t * 0.12)),
    fbm2(q + warp * w1 + vec2(8.3 - t * 0.1, 2.8))
  );
  float f = fbm3(q + warp * w2);

  float depth = 0.4 + 0.6 * z;
  float glow = 0.36 + 0.86 * uEnergy;

  // Deep glass, tinted by the palette, so shadows stay coloured.
  vec3 col = mix(vec3(0.02, 0.025, 0.05), pal(0.6 + w1.x * 0.5) * 0.1, 0.7);
  // Smoke: two palette hues blended by the warp, brightest where dense.
  vec3 smoke = mix(
    pal(0.55 + w1.y * 0.6 + t * 0.02),
    pal(0.05 + w2.x * 0.7 + t * 0.02),
    smoothstep(0.25, 0.75, f)
  );
  float dense = smoothstep(0.1, 0.95, f * f * 1.7);
  col += smoke * (0.22 + 0.78 * dense) * depth * glow * mix(0.75, 1.2, keyLit);
  // Silk: the densest folds catch the light and run toward white.
  float silk = smoothstep(0.52, 0.9, f) * smoothstep(0.35, 0.8, w2.y);
  col += mix(smoke, vec3(1.0), 0.5) * silk * silk * depth *
      (0.2 + 0.8 * uEnergy + 0.45 * uAmp);

  // The heart: a soft white-hot core that swells with energy and voice.
  float coreR = 0.28 + 0.18 * uEnergy + 0.1 * uAmp;
  float core = exp(-dot(np, np) / (coreR * coreR)) * (0.75 + 0.5 * f);
  col += mix(pal(0.1 + uTime * 0.03), vec3(0.96, 0.98, 1.0), 0.5) * core *
      (0.12 + 0.6 * uEnergy + 0.35 * uAmp);

  // Light gathered on the side away from the key light.
  float caustic = smoothstep(0.5, 1.0, rn) *
      smoothstep(0.0, 0.85, -np.y * uKey);
  col += pal(0.3 + uTime * 0.03) * caustic * (0.12 + 0.35 * uEnergy);

  // Fresnel rim in the palette: the silhouette, kept strong on tiny orbs.
  float fres = pow(1.0 - z, mix(1.5, 2.6, uDetail));
  col += pal(hueA + uTime * 0.04) * fres * (0.45 + 0.75 * uEnergy) *
      mix(1.7, 1.0, uDetail) * mix(0.8, 1.2, keyLit);

  // Glass: a sharp glint, a broad sheen and a lit lip along the top.
  vec3 L = normalize(vec3(-0.45, -0.62, 1.0));
  float nl = max(dot(n, L), 0.0);
  float glint = pow(nl, mix(28.0, 220.0, uDetail));
  float bloom = pow(nl, mix(10.0, 28.0, uDetail));
  col += vec3(1.0) *
      (glint * mix(0.6, 0.95, uDetail) + bloom * 0.16 + pow(nl, 4.0) * 0.05);
  float lip = gauss(rn - 0.9, 0.05) * smoothstep(0.1, 0.9, -np.y);
  col += vec3(0.9, 0.95, 1.0) * lip * 0.12 * uDetail;

  col += vec3(0.9, 0.95, 1.0) * uFlash * 0.55 * (0.5 + 0.5 * z);

  vec3 rgb = mix(outer, col, inside) + ringLight + sparkLight;
  fragColor = finish(rgb, inside + glowA * (1.0 - inside), frag);
}
