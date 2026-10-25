#version 460 core
#include <flutter/runtime_effect.glsl>

// Frank's edge glow: light that lives on the phone's real rounded glass.
//
// Drawn only on a band path along the screen edge with BlendMode.plus, so
// interior pixels never run this shader. Layers, from the glass inward:
//   filament  a hairline of hot light on the glass itself
//   halo      saturated palette light hugging the edge
//   wash      a soft, dual-tone spill into the room (kept readable)
// modulated by periodic value noise that flows along the loop (the living
// quality), comets (tools and the comet styles), voice ripples, the bloom
// from where you touched, the white "done" sweep and an OLED dither.
//
// Coordinates are logical pixels. Uniform indices follow declaration order
// and are mirrored in EdgeGlowPainter; every uniform is read, so none are
// stripped and the indices never drift.

precision highp float;

uniform vec2 uSize;        // 0-1   canvas size
uniform float uRadius;     // 2     display corner radius
uniform float uDpr;        // 3     device pixel ratio
uniform float uBand;       // 4     inward depth the band path covers
uniform float uIntensity;  // 5     master brightness (mood x gain x boosts)
uniform float uDepth;      // 6     halo depth
uniform float uAmp;        // 7     voice / token energy 0..1
uniform float uFlow;       // 8     noise phase, wrapped to [0, 119)
uniform float uHue;        // 9     palette rotation in loops, [0, 1)
uniform float uBias;       // 10    +1 heavier at the bottom .. -1 at the top
uniform float uOrigin;     // 11    bloom origin in loop units
uniform float uReveal;     // 12    bloom mask 0..1
uniform float uFront;      // 13    brightness of the racing bloom fronts
uniform float uFlare;      // 14    ignition flare at the origin
uniform float uComet;      // 15    comet head 0..1, < 0 for none
uniform float uCometW;     // 16    comet width in loops
uniform float uCometGain;  // 17    comet brightness (spikes on tool events)
uniform float uTwin;       // 18    0 one head, 1 two heads apart, 2 a pair converging on the origin
uniform float uCometOnly;  // 19    0 flowing aura, 1 comet styles
uniform float uRingMix;    // 20    0 flowing, 1 steady ring
uniform float uFlash;      // 21    done sweep 0..1, < 0 for none
uniform vec4 uRip;         // 22-25 voice ripples (age0, strength0, age1, strength1)
uniform vec3 uC0;          // 26-28 palette, crossfaded on the CPU
uniform vec3 uC1;          // 29-31
uniform vec3 uC2;          // 32-34
uniform vec3 uC3;          // 35-37
uniform float uCap;        // 38    readability cap (luma) from uRead inward
uniform float uRead;       // 39    inset where reply text starts

out vec4 fragColor;

const float PI = 3.14159265;

float gauss(float x, float w) {
  float k = x / w;
  return exp(-k * k);
}

float hash11(float n) {
  return fract(sin(n * 91.3458) * 47453.5453);
}

float hash12(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

// Value noise that repeats every `period`, so it closes seamlessly where the
// loop meets itself at bottom centre.
float noiseP(float x, float period) {
  float i = floor(x);
  float f = fract(x);
  float s = f * f * (3.0 - 2.0 * f);
  return mix(hash11(mod(i, period)), hash11(mod(i + 1.0, period)), s);
}

// Distance inward from the two nearest straight edges, blended with a soft
// minimum whose softness grows with depth: smooth everywhere, so light deep
// in the room has rounded inner contours (like a real blur of the frame)
// with no mitred seams running in from the corners.
float softEdge(vec2 q, vec2 h) {
  vec2 d = h - abs(q);
  float k = 0.18 * (d.x + d.y) + 1.0;
  return min(d.x, d.y) - k * log(1.0 + exp(-abs(d.x - d.y) / k));
}

float sdRoundRect(vec2 q, vec2 h, float r) {
  vec2 d = abs(q) - h + r;
  return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - r;
}

// Arc-length position along the glass: 0 at bottom centre, up the right side
// to 0.5 at top centre, down the left side back to 1. Interior points take
// the parameter of the nearest edge. Mirrored in glow_geometry.dart.
float loopParam(vec2 q, vec2 h, float r) {
  vec2 a = vec2(abs(q.x), q.y);
  float sx = h.x - r;
  float sy = h.y - r;
  float halfP = 2.0 * sx + 2.0 * sy + PI * r;
  float pos;
  if (a.x > sx && a.y > sy) {
    pos = sx + (0.5 * PI - atan(a.y - sy, a.x - sx)) * r;
  } else if (a.x > sx && a.y < -sy) {
    pos = sx + 0.5 * PI * r + 2.0 * sy + atan(-a.y - sy, a.x - sx) * r;
  } else {
    float db = h.y - a.y;
    float dr = h.x - a.x;
    float dt = h.y + a.y;
    if (db <= dr && db <= dt) {
      pos = a.x;
    } else if (dr <= dt) {
      pos = sx + 0.5 * PI * r + (sy - a.y);
    } else {
      pos = halfP - a.x;
    }
  }
  float t = clamp(pos / halfP, 0.0, 1.0);
  return q.x >= 0.0 ? 0.5 * t : 1.0 - 0.5 * t;
}

vec3 palette(float t) {
  t = fract(t) * 4.0;
  vec3 a = uC0;
  vec3 b = uC1;
  if (t >= 3.0) {
    a = uC3;
    b = uC0;
  } else if (t >= 2.0) {
    a = uC2;
    b = uC3;
  } else if (t >= 1.0) {
    a = uC1;
    b = uC2;
  }
  return mix(a, b, smoothstep(0.0, 1.0, fract(t)));
}

float loopDist(float a, float b) {
  float d = abs(a - b);
  return min(d, 1.0 - d);
}

// A comet travelling towards +u: a gaussian nose and an exponential tail.
float comet(float u, float head, float w) {
  float behind = fract(head - u);
  float ahead = 1.0 - behind;
  return max(exp(-behind / (w * 2.5)), gauss(ahead, w * 0.6));
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 h = 0.5 * uSize;
  vec2 q = frag - h;
  float r = min(uRadius, min(h.x, h.y));
  float e = max(-sdRoundRect(q, h, r), 0.0);

  // On the glass, follow the true rounded edge; deeper in, hand over to the
  // smooth edge distance so the light's inner contour is a soft curve.
  float soft = mix(e, softEdge(q, h), smoothstep(0.0, max(0.75 * r, 1.0), e));
  if (uIntensity < 0.002 || soft > 0.95 * uBand) {
    fragColor = vec4(0.0);
    return;
  }

  // Parametrize with a corner radius that grows with depth: on the glass it
  // is the real corner, deeper in every point sits in a corner arc, so the
  // parameter (and the noise and hue riding on it) never jumps across the
  // corner diagonals.
  float u = loopParam(q, h, min(r + e, min(h.x, h.y)));
  float du = loopDist(u, uOrigin);

  // Bloom: the light grows from the origin along both sides at once and
  // meets at the opposite point. Two bright fronts race ahead of it.
  float rv = mix(-0.08, 0.58, uReveal);
  float mask = 1.0 - smoothstep(rv - 0.08, rv + 0.08, du);
  float spark = uFront * gauss(du - rv, 0.02) + uFlare * gauss(du, 0.035);

  // Liquid flow: two octaves drifting in opposite directions so the light
  // morphs instead of merely sliding. Integer speed ratios keep both octaves
  // periodic in the wrapped phase (119 = 7 * 17).
  float n = 0.6 * noiseP(u * 7.0 + uFlow, 7.0) +
            0.4 * noiseP(u * 17.0 - 2.0 * uFlow, 17.0);
  float flowMod = mix(0.5 + n, 1.0, uRingMix);

  // Lean: heavier on the favoured edge (mic below, speaker above), lighter
  // on the opposite one.
  float b = uBias * (q.y / h.y);
  float bias = b > 0.0 ? 1.0 + 0.6 * b * b : 1.0 - 0.3 * b * b;

  float rip = uRip.y * (1.0 - uRip.x) * gauss(du - uRip.x * 0.5, 0.03) +
              uRip.w * (1.0 - uRip.z) * gauss(du - uRip.z * 0.5, 0.03);

  float c = 0.0;
  if (uComet >= 0.0) {
    if (uTwin > 1.5) {
      float v = fract(u - uOrigin);
      c = max(comet(v, uComet, uCometW), comet(1.0 - v, uComet, uCometW));
    } else {
      c = comet(u, uComet, uCometW);
      if (uTwin > 0.5) {
        c = max(c, comet(u, fract(uComet + 0.5), uCometW));
      }
    }
  }
  float cg = c * uCometGain;

  float thick = uDepth * bias * flowMod * (1.0 + 0.8 * uAmp) + rip * uDepth;
  thick *= mix(1.0, mix(0.35, 1.6, c), uCometOnly);
  thick = clamp(thick, 1.0, uBand / 3.2);

  // The filament is about a physical pixel and a half wide on any screen.
  float core = gauss(e, 0.45 + 1.4 / uDpr);
  float halo = exp(-soft / (0.45 * thick)) * mix(0.75 + 0.5 * n, 1.0, uRingMix);
  float wash = gauss(soft, 1.15 * thick) * 0.38;

  float drift = n * 0.14 * (1.0 - uRingMix);
  vec3 col = palette(u + uHue + drift);
  vec3 deep = palette(u + uHue + 0.18 + drift * 1.25);
  vec3 hot = mix(col, vec3(1.0), 0.6);

  float coreW = mix(0.55 + 0.45 * cg, 0.25 + 0.75 * cg, uCometOnly);
  float bodyW = mix(1.0 + 0.6 * cg, 0.12 + 0.88 * cg, uCometOnly);

  vec3 rgb = hot * core * coreW + (col * halo + deep * wash) * bodyW;
  rgb *= mask;
  rgb += hot * spark * (1.2 * core + 0.8 * halo);

  if (uFlash >= 0.0) {
    float s = gauss(abs(u - 0.5) - uFlash * 0.5, 0.035);
    rgb += vec3(0.95, 0.97, 1.0) * s * (1.3 * core + 0.9 * halo + 0.3 * wash);
  }

  rgb *= uIntensity * (1.0 - smoothstep(0.65 * uBand, 0.95 * uBand, soft));

  // Readability: reply text starts uRead in from the glass. From there on,
  // the added light is softly compressed under uCap (Rec.709 luma), however
  // hard the gain, tokens or voice push the wash; the glass edge and the
  // near halo are untouched, and below the cap the falloff keeps its shape.
  float lum = dot(rgb, vec3(0.2126, 0.7152, 0.0722));
  if (lum > 1e-4) {
    float held = uCap * (1.0 - exp(-lum / uCap));
    rgb *= mix(1.0, held / lum, smoothstep(0.6 * uRead, uRead, soft));
  }

  // Hot light saturates towards white instead of clipping.
  vec3 over = max(rgb - 0.6, 0.0);
  rgb = min(rgb, 0.6) + 0.4 * (1.0 - exp(-over / 0.4));

  // OLED dither, per physical pixel: the faint tail would band without it.
  rgb = max(rgb + (hash12(floor(frag * uDpr)) - 0.5) / 255.0, 0.0);
  fragColor = vec4(rgb, clamp(max(rgb.r, max(rgb.g, rgb.b)), 0.0, 1.0));
}
