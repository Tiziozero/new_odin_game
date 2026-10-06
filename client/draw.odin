package main

import "core:c"
import "core:fmt"
import "core:math"
import "core:mem"
import "core:strings"
import raylib "vendor:raylib"
import "project:common/game"

// Terrain -> Effects -> Objects are flushed inside the render target (BeginTextureMode).
// UI is flushed straight to the screen after the target has been blitted.
// `Objects` is the zero value on purpose: anything queued without picking a layer
// lands above the map instead of silently under it. Reset s.layer = .Objects at the
// end of each frame so the next frame doesn't start on .UI.
Layer :: enum { Objects, Terrain, Effects, UI }

// Per-command post effect. Commands with an effect are drawn inside BeginShaderMode.
Effect :: enum u8 { None, Water }

WaterShader :: struct {
    shader:     raylib.Shader,
    loc_time:   c.int,
    loc_origin: c.int,
    loc_zoom:   c.int,
}

DrawSpriteCommand :: struct {
    texture:  raylib.Texture2D,
    pos, size: raylib.Vector2,
    tint:     raylib.Color,
    no_scale: bool,
}
DrawSpriteSrcCommand :: struct {
    texture:  raylib.Texture2D,
    body, src: raylib.Rectangle,
    tint:     raylib.Color,
    no_scale: bool,
    effect:   Effect,
}
DrawTextCommand :: struct {
    text:     string,
    font:     raylib.Font,
    pos:      raylib.Vector2,
    tint:     raylib.Color,
    size:     f32,
    spacing:  f32,
    no_scale: bool,
}
DrawRectCommand :: struct {
    body:     raylib.Rectangle,
    tint:     raylib.Color,
    no_scale: bool,
}
DrawCommand :: union {
    DrawSpriteCommand,
    DrawSpriteSrcCommand,
    DrawTextCommand,
    DrawRectCommand,
}

draw :: proc {
    draw_text,
}

// ---- allocators -------------------------------------------------------------

// NOTE: `arena.block_allocator` is the allocator the arena gets its *blocks* from
// (the heap), so allocating from it directly bypasses the arena and is never freed.
// Always go through dynamic_arena_allocator, and call
// mem.dynamic_arena_reset(&s.frame_arena) once per frame.
frame_allocator :: proc(s: ^State) -> mem.Allocator {
    return mem.dynamic_arena_allocator(&s.frame_arena)
}

// ---- queuing ----------------------------------------------------------------

queue :: proc(s: ^State, cmd: DrawCommand) {
    append(&s.layers[s.layer], cmd)
}

draw_text :: proc(s: ^State, text: string, pos: raylib.Vector2,
    tint := raylib.WHITE, size: f32 = 20.0, spacing: f32 = 1, font := raylib.Font{}) {
    queue(s, DrawTextCommand{text=text, tint=tint, size=size, pos=pos, font=font, spacing=spacing})
}

draw_sprite :: proc {
    draw_sprite_v,
    draw_sprite_rect,
    draw_sprite_src_v,
    draw_sprite_src_rect,
}

draw_sprite_v :: proc(s: ^State, texture: raylib.Texture2D,
    pos, size: raylib.Vector2, tint := raylib.WHITE) {
    queue(s, DrawSpriteCommand{texture=texture, pos=pos, size=size, tint=tint})
}

draw_sprite_rect :: proc(s: ^State, texture: raylib.Texture2D,
    body: raylib.Rectangle, tint := raylib.WHITE) {
    queue(s, DrawSpriteCommand{
        texture = texture,
        pos     = game.rect_pos(body),
        size    = game.rect_size(body),
        tint    = tint,
    })
}

draw_sprite_src_v :: proc(s: ^State, texture: raylib.Texture2D,
    src_pos, src_size, pos, size: raylib.Vector2, tint := raylib.WHITE) {
    queue(s, DrawSpriteSrcCommand{
        texture = texture,
        body    = {pos.x, pos.y, size.x, size.y},
        src     = {src_pos.x, src_pos.y, src_size.x, src_size.y},
        tint    = tint,
    })
}

draw_sprite_src_rect :: proc(s: ^State, texture: raylib.Texture2D,
    src, body: raylib.Rectangle, tint := raylib.WHITE, effect := Effect.None) {
    queue(s, DrawSpriteSrcCommand{
        texture = texture,
        body    = body,
        src     = src,
        tint    = tint,
        effect  = effect,
    })
}

// ---- flushing ---------------------------------------------------------------

// Draws and clears one layer. Call inside BeginTextureMode, once per layer,
// in the order you want them stacked.
flush_layer :: proc(s: ^State, layer: Layer) {
    active := Effect.None
    for cmd in s.layers[layer] {
        want := command_effect(cmd)
        if want != active {
            set_effect(s, active, want)
            active = want
        }
        draw_command(s, cmd)
    }
    set_effect(s, active, .None)
    clear(&s.layers[layer])
}

command_effect :: proc(cmd: DrawCommand) -> Effect {
    if c, ok := cmd.(DrawSpriteSrcCommand); ok { return c.effect }
    return .None
}

set_effect :: proc(s: ^State, from, to: Effect) {
    if from != .None { raylib.EndShaderMode() }
    switch to {
    case .None:
    case .Water: raylib.BeginShaderMode(s.water.shader)
    }
}

// ---- water shader -----------------------------------------------------------

// Loaded from these files (relative to the working directory, like fragment.fs was);
// if they don't exist the embedded copies at the bottom of this file are used.
WATER_VS_PATH :: "water.vs"
WATER_FS_PATH :: "water.fs"

// Builds the shader and only swaps it in if it compiled and has our uniforms, so a
// bad edit during an F5 reload keeps the previous working shader. Returns success.
load_water_shader :: proc(s: ^State, atlas: raylib.Texture2D, force_embedded := false) -> bool {
    from_files := !force_embedded && raylib.FileExists(WATER_VS_PATH) && raylib.FileExists(WATER_FS_PATH)

    shader: raylib.Shader
    if from_files {
        shader = raylib.LoadShader(WATER_VS_PATH, WATER_FS_PATH)
    } else {
        shader = raylib.LoadShaderFromMemory(WATER_VS, WATER_FS)
    }

    loc_time   := raylib.GetShaderLocation(shader, "time")
    loc_origin := raylib.GetShaderLocation(shader, "view_origin")
    loc_zoom   := raylib.GetShaderLocation(shader, "view_zoom")
    loc_atlas  := raylib.GetShaderLocation(shader, "atlas_size")

    // A failed compile falls back to raylib's default shader, which has none of these.
    if loc_time == -1 || loc_origin == -1 || loc_zoom == -1 || loc_atlas == -1 {
        fmt.eprintln("water shader FAILED (see raylib SHADER log above); from files:", from_files)
        raylib.UnloadShader(shader) // no-op for the default shader
        return false
    }

    if s.water.shader.id != 0 { raylib.UnloadShader(s.water.shader) }
    s.water = WaterShader{shader = shader, loc_time = loc_time, loc_origin = loc_origin, loc_zoom = loc_zoom}

    atlas_size := raylib.Vector2{f32(atlas.width), f32(atlas.height)}
    raylib.SetShaderValue(shader, loc_atlas, &atlas_size, .VEC2)

    fmt.println("water shader loaded from", "files" if from_files else "embedded source", "id:", shader.id)
    return true
}

init_water_shader :: proc(s: ^State, atlas: raylib.Texture2D) {
    if !load_water_shader(s, atlas) {
        _ = load_water_shader(s, atlas, force_embedded = true)
    }
}

// World position of the top-left pixel of the render target, so the shader can
// anchor the waves to the world instead of the screen (no "swimming" when the
// camera moves). Assumes apply_camera(cam, p) == p - cam.xy; adjust here if not.
update_water_uniforms :: proc(s: ^State) {
    if raylib.IsKeyPressed(.F5) { _ = load_water_shader(s, tiles) } // hot reload
    w := &s.water
    now  := f32(raylib.GetTime())
    zoom := f32(SCREEN_FACTOR)

    origin := raylib.Vector2{s.camera.x, s.camera.y}
    if bool_center_scale {
        origin += raylib.Vector2{f32(SCREEN_WIDTH), f32(SCREEN_HEIGHT)} * (zoom - 1) / (2 * zoom)
    }

    raylib.SetShaderValue(w.shader, w.loc_time,   &now,    .FLOAT)
    raylib.SetShaderValue(w.shader, w.loc_zoom,   &zoom,   .FLOAT)
    raylib.SetShaderValue(w.shader, w.loc_origin, &origin, .VEC2)
}

// ---- snapping / scaling -----------------------------------------------------

bool_snap := false
snap_f32 :: proc(v: f32) -> f32 { if bool_snap { return math.round(v) } else { return v } }
snap_v2 :: proc(v: raylib.Vector2) -> raylib.Vector2 { return {snap(v.x), snap(v.y)} }
snap_rect :: proc(v: raylib.Rectangle) -> raylib.Rectangle { return {snap(v.x), snap(v.y), snap(v.width), snap(v.height)} }
snap :: proc {
    snap_f32,
    snap_v2,
    snap_rect,
}

bool_center_scale := true
center_scaled_v :: proc(v: raylib.Vector2, factor: f32) -> raylib.Vector2 {
    if bool_center_scale {
        return v - {SCREEN_WIDTH, SCREEN_HEIGHT} * (factor - 1) / 2
    } else { return v }
}
center_scaled_r :: proc(v: raylib.Rectangle, factor: f32) -> raylib.Rectangle {
    if bool_center_scale {
        p := game.rect_pos(v) - {SCREEN_WIDTH, SCREEN_HEIGHT} * (factor - 1) / 2
        return {p.x, p.y, v.width, v.height}
    } else { return v }
}

center_scaled :: proc {
    center_scaled_v,
    center_scaled_r,
}

// ---- command execution ------------------------------------------------------

draw_command :: proc(s: ^State, cmd: DrawCommand) {
    switch c in cmd {
    case DrawTextCommand:      draw_command_text(s, c)
    case DrawSpriteCommand:    draw_command_sprite(s, c)
    case DrawSpriteSrcCommand: draw_command_sprite_src(s, c)
    case DrawRectCommand:      draw_command_rect(s, c)
    }
}

@(private="file")
draw_command_text :: proc(s: ^State, cmd: DrawTextCommand) {
    font   := cmd.font if cmd.font.texture.id != 0 else raylib.GetFontDefault()
    factor := SCREEN_FACTOR if !cmd.no_scale else 1.0
    pos    := center_scaled(cmd.pos * factor, factor)
    size   := cmd.size * factor
    cstr   := strings.clone_to_cstring(cmd.text, frame_allocator(s))
    raylib.DrawTextEx(font, cstr, snap(pos), snap(size), cmd.spacing, cmd.tint)
}

@(private="file")
draw_command_sprite :: proc(s: ^State, cmd: DrawSpriteCommand) {
    factor := SCREEN_FACTOR if !cmd.no_scale else 1.0
    pos    := center_scaled(cmd.pos * factor, factor)
    size   := cmd.size * factor
    dst    := raylib.Rectangle{pos.x, pos.y, size.x, size.y}
    if !on_screen(dst) { return }
    src    := raylib.Rectangle{0, 0, f32(cmd.texture.width), f32(cmd.texture.height)}
    raylib.DrawTexturePro(cmd.texture, src, snap(dst), {0, 0}, 0, cmd.tint)
}

@(private="file")
draw_command_sprite_src :: proc(s: ^State, cmd: DrawSpriteSrcCommand) {
    factor := SCREEN_FACTOR if !cmd.no_scale else 1.0
    dst    := raylib.Rectangle{
        cmd.body.x      * factor,
        cmd.body.y      * factor,
        cmd.body.width  * factor,
        cmd.body.height * factor,
    }
    dst = center_scaled(dst, factor)
    if !on_screen(dst) { return }
    raylib.DrawTexturePro(cmd.texture, cmd.src, snap(dst), {0, 0}, 0, cmd.tint)
}

@(private="file")
draw_command_rect :: proc(s: ^State, cmd: DrawRectCommand) {
    factor := SCREEN_FACTOR if !cmd.no_scale else 1.0
    body := raylib.Rectangle{
        cmd.body.x      * factor,
        cmd.body.y      * factor,
        cmd.body.width  * factor,
        cmd.body.height * factor,
    }
    body = center_scaled(body, factor)
    if !on_screen(body) { return }
    raylib.DrawRectangleRec(snap(body), cmd.tint)
}

// ---- visibility -------------------------------------------------------------

// Final (post-scale) rectangle of the render target.
on_screen :: proc(r: raylib.Rectangle) -> bool {
    return rect_overlaps(r, {0, 0, f32(SCREEN_WIDTH), f32(SCREEN_HEIGHT)})
}

// The part of *logical* (pre-scale) space that ends up on screen. Use it to skip
// queuing things that would be culled anyway. Inverse of: final = pos*F - W*(F-1)/2.
logical_view :: proc() -> raylib.Rectangle {
    f := f32(SCREEN_FACTOR)
    w := f32(SCREEN_WIDTH)
    h := f32(SCREEN_HEIGHT)
    if !bool_center_scale { return {0, 0, w / f, h / f} }
    return {w * (f - 1) / (2 * f), h * (f - 1) / (2 * f), w / f, h / f}
}

rect_overlaps :: proc(a, b: raylib.Rectangle) -> bool {
    return a.x < b.x + b.width  &&
           a.x + a.width  > b.x &&
           a.y < b.y + b.height &&
           a.y + a.height > b.y
}

// ---- helpers ----------------------------------------------------------------

text_measure :: proc(text: string, size: f32, font := raylib.Font{},
    spacing: f32 = 1) -> raylib.Vector2 {
    font := font if font.texture.id != 0 else raylib.GetFontDefault()
    cstr := strings.clone_to_cstring(text, context.temp_allocator)
    return raylib.MeasureTextEx(font, cstr, size, spacing)
}

draw_text_center :: proc(s: ^State, text: string, pos: raylib.Vector2,
    tint := raylib.WHITE, size: f32 = 20, font := raylib.Font{}, spacing: f32 = 1) {
    measured := text_measure(text, size, font, spacing)
    draw_text(s, text, pos - measured * 0.5, tint, size, font=font, spacing=spacing)
}

draw_text_center_no_scale :: proc(s: ^State, text: string, pos: raylib.Vector2,
    tint := raylib.WHITE, size: f32 = 20.0, font := raylib.Font{}, spacing: f32 = 1) {
    measured := text_measure(text, size, font, spacing)
    draw_text_no_scale(s, text, pos - measured * 0.5, tint=tint, size=size, font=font, spacing=spacing)
}

draw_text_no_scale :: proc(s: ^State, text: string, pos: raylib.Vector2,
    tint := raylib.WHITE, size: f32 = 20.0, font := raylib.Font{}, spacing: f32 = 1) {
    queue(s, DrawTextCommand{text=text, tint=tint, size=size, pos=pos,
        spacing=spacing, font=font, no_scale=true})
}

draw_sprite_no_scale :: proc {
    draw_sprite_v_no_scale,
    draw_sprite_rect_no_scale,
    draw_sprite_src_v_no_scale,
    draw_sprite_src_rect_no_scale,
}

draw_sprite_v_no_scale :: proc(s: ^State, texture: raylib.Texture2D,
    pos, size: raylib.Vector2, tint := raylib.WHITE) {
    queue(s, DrawSpriteCommand{texture=texture, pos=pos, size=size,
        tint=tint, no_scale=true})
}

draw_sprite_rect_no_scale :: proc(s: ^State, texture: raylib.Texture2D,
    body: raylib.Rectangle, tint := raylib.WHITE) {
    queue(s, DrawSpriteCommand{
        texture  = texture,
        pos      = game.rect_pos(body),
        size     = game.rect_size(body),
        tint     = tint,
        no_scale = true,
    })
}

draw_sprite_src_v_no_scale :: proc(s: ^State, texture: raylib.Texture2D,
    src_pos, src_size, pos, size: raylib.Vector2, tint := raylib.WHITE) {
    queue(s, DrawSpriteSrcCommand{
        texture  = texture,
        body     = {pos.x, pos.y, size.x, size.y},
        src      = {src_pos.x, src_pos.y, src_size.x, src_size.y},
        tint     = tint,
        no_scale = true,
    })
}

draw_sprite_src_rect_no_scale :: proc(s: ^State, texture: raylib.Texture2D,
    src, body: raylib.Rectangle, tint := raylib.WHITE) {
    queue(s, DrawSpriteSrcCommand{
        texture  = texture,
        body     = body,
        src      = src,
        tint     = tint,
        no_scale = true,
    })
}

draw_rect :: proc {
    draw_rect_v,
    draw_rect_rect,
}

draw_rect_v :: proc(s: ^State, pos, size: raylib.Vector2, tint := raylib.WHITE) {
    queue(s, DrawRectCommand{body={pos.x, pos.y, size.x, size.y}, tint=tint})
}

draw_rect_rect :: proc(s: ^State, body: raylib.Rectangle, tint := raylib.WHITE) {
    queue(s, DrawRectCommand{body=body, tint=tint})
}

draw_rect_no_scale :: proc {
    draw_rect_v_no_scale,
    draw_rect_rect_no_scale,
}

draw_rect_v_no_scale :: proc(s: ^State, pos, size: raylib.Vector2, tint := raylib.WHITE) {
    queue(s, DrawRectCommand{body={pos.x, pos.y, size.x, size.y}, tint=tint, no_scale=true})
}

draw_rect_rect_no_scale :: proc(s: ^State, body: raylib.Rectangle, tint := raylib.WHITE) {
    queue(s, DrawRectCommand{body=body, tint=tint, no_scale=true})
}

// ---- water shader source: fallback used when water.vs / water.fs are not found -------

WATER_VS :: `#version 330

in vec3 vertexPosition;
in vec2 vertexTexCoord;
in vec4 vertexColor;

uniform mat4 mvp;

out vec2 fragTexCoord;
out vec4 fragColor;
out vec2 fragPos; // position in render-target pixels (top-left origin)

void main()
{
    fragTexCoord = vertexTexCoord;
    fragColor    = vertexColor;
    fragPos      = vertexPosition.xy;
    gl_Position  = mvp * vec4(vertexPosition, 1.0);
}
`

WATER_FS :: `#version 330

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
    px.x += sin(world.y * 0.1 + time * 2.0) * 2.0;
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
`
