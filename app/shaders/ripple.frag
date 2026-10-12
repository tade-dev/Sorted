#version 460 core
#include <flutter/runtime_effect.glsl>

// Wavy "reading" distortion over the seller's photo while extraction runs.
uniform vec2 uSize;
uniform float uTime;
uniform sampler2D uTexture;

out vec4 fragColor;

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec2 centre = vec2(0.5, 0.5);
  float d = distance(uv, centre);

  // Rings travelling outward from the centre, fading towards the edges.
  float ripple = sin(d * 38.0 - uTime * 4.0) * 0.010 * (1.0 - smoothstep(0.0, 0.75, d));
  // A slow horizontal wave on top, so the whole sheet looks liquid.
  float wave = sin(uv.y * 14.0 + uTime * 2.2) * 0.006;

  vec2 dir = d > 0.0001 ? normalize(uv - centre) : vec2(0.0);
  vec2 p = clamp(uv + dir * ripple + vec2(wave, 0.0), 0.0, 1.0);
  vec4 colour = texture(uTexture, p);

  // A soft blue sheen riding the crests (#0070E0).
  float crest = smoothstep(0.6, 1.0, sin(d * 38.0 - uTime * 4.0)) * 0.18;
  fragColor = vec4(mix(colour.rgb, vec3(0.0, 0.44, 0.88), crest), colour.a);
}
