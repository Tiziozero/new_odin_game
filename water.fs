#version 330

in vec2 fragTexCoord;
in vec4 fragColor;
in vec2 fragPos;

uniform sampler2D texture0;
uniform vec4  colDiffuse;
uniform float time;
uniform vec2  view_origin; // world position of the render target's top-left pixel
uniform float view_zoom;   // SCREEN_FACTOR
uniform vec2  atlas_size;  // tileset size in pixels

const float TILE = 16.0;   // tile size in the atlas

// 1 = flood the water with red (test that the pass runs). Set to 0 for the real look.
#define DEBUG_TINT 0

out vec4 finalColor;

void main()
{
    // world position of this pixel, so the waves stay put when the camera moves
    vec2 world = view_origin + fragPos / view_zoom;

    // work in atlas pixels so the wobble can be clamped to the current tile
    vec2 px   = fragTexCoord * atlas_size;
    vec2 cell = floor(px / TILE) * TILE;

    // horizontal wobble (your old effect), driven by world y
    px.x += sin(world.y * 0.1 + time * 2.0) * 2.0*0.3;
    px = clamp(px, cell + 0.5, cell + TILE - 0.5);

    vec4 col = texture(texture0, px / atlas_size) * fragColor * colDiffuse;

    // moving shimmer, visible even when the tile itself is flat colour
    float shimmer = 0.5 + 0.5 * sin(world.x * 0.06 + world.y * 0.09 + time * 1.5);
    // brightness only (hue-neutral), so it reads the same whatever the water colour is
    col.rgb += vec3(0.07) * shimmer;

#if DEBUG_TINT
    col = vec4(1.0, 0.0, 0.0, 1.0);
#endif

    finalColor = col;
}
