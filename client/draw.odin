package main

import "core:strings"
import raylib "vendor:raylib"
import "project:common/game"


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

// ---- queuing ----------------------------------------------------------------

draw_text :: proc(s: ^State, text: string, pos: raylib.Vector2,
    tint := raylib.WHITE, size: f32 = 20.0, spacing: f32 = 1, font := raylib.Font{}) {
    append(&s.draws, DrawTextCommand{text=text, tint=tint, size=size, pos=pos, font=font, spacing=spacing})
}

draw_sprite :: proc {
    draw_sprite_v,
    draw_sprite_rect,
    draw_sprite_src_v,
    draw_sprite_src_rect,
}

draw_sprite_v :: proc(s: ^State, texture: raylib.Texture2D,
    pos, size: raylib.Vector2, tint := raylib.WHITE) {
    append(&s.draws, DrawSpriteCommand{texture=texture, pos=pos, size=size, tint=tint})
}

draw_sprite_rect :: proc(s: ^State, texture: raylib.Texture2D,
    body: raylib.Rectangle, tint := raylib.WHITE) {
    append(&s.draws, DrawSpriteCommand{
        texture = texture,
        pos     = game.rect_pos(body),
        size    = game.rect_size(body),
        tint    = tint,
    })
}

draw_sprite_src_v :: proc(s: ^State, texture: raylib.Texture2D,
    src_pos, src_size, pos, size: raylib.Vector2, tint := raylib.WHITE) {
    append(&s.draws, DrawSpriteSrcCommand{
        texture = texture,
        body    = {pos.x, pos.y, size.x, size.y},
        src     = {src_pos.x, src_pos.y, src_size.x, src_size.y},
        tint    = tint,
    })
}

draw_sprite_src_rect :: proc(s: ^State, texture: raylib.Texture2D,
    src, body: raylib.Rectangle, tint := raylib.WHITE) {
    append(&s.draws, DrawSpriteSrcCommand{
        texture = texture,
        body    = body,
        src     = src,
        tint    = tint,
    })
}

// ---- flushing ---------------------------------------------------------------

flush_draws :: proc(s: ^State) {
    for cmd in s.draws {
        draw_command(s, cmd)
    }
    clear(&s.draws)
}

draw_command :: proc(s: ^State, cmd: DrawCommand) {
    switch c in cmd {
    case DrawTextCommand:      draw_command_text(s, c)
    case DrawSpriteCommand:    draw_command_sprite(s, c)
    case DrawSpriteSrcCommand: draw_command_sprite_src(s, c)
    case DrawRectCommand: draw_command_rect(s, c)
    }
}

@(private="file")
draw_command_text :: proc(s: ^State, cmd: DrawTextCommand) {
    font   := cmd.font if cmd.font.texture.id != 0 else raylib.GetFontDefault()
    factor := SCREEN_FACTOR if !cmd.no_scale else 1.0
    pos    := cmd.pos  * factor
    size   := cmd.size * factor
    spacing:= cmd.spacing
    cstr   := strings.clone_to_cstring(cmd.text, allocator=s.frame_arena.block_allocator)
    raylib.DrawTextEx(font, cstr, pos, size, spacing, cmd.tint)
}

@(private="file")
draw_command_sprite :: proc(s: ^State, cmd: DrawSpriteCommand) {
    factor := SCREEN_FACTOR if !cmd.no_scale else 1.0
    pos    := cmd.pos  * factor
    size   := cmd.size * factor
    src    := raylib.Rectangle{0, 0, f32(cmd.texture.width), f32(cmd.texture.height)}
    dst    := raylib.Rectangle{pos.x, pos.y, size.x, size.y}
    raylib.DrawTexturePro(cmd.texture, src, dst, {0, 0}, 0, cmd.tint)
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
    raylib.DrawTexturePro(cmd.texture, cmd.src, dst, {0, 0}, 0, cmd.tint)
}
// ---- helpers ----------------------------------------------------------------

text_measure :: proc(text: string, size: f32, font := raylib.Font{},
    spacing: f32 = 1) -> raylib.Vector2 {
    font := font if font.texture.id != 0 else raylib.GetFontDefault()
    cstr := strings.clone_to_cstring(text, context.temp_allocator)
    return raylib.MeasureTextEx(font, cstr, size, spacing)
}

// ---- queuing ----------------------------------------------------------------

draw_text_center :: proc(s: ^State, text: string, pos: raylib.Vector2,
    tint := raylib.WHITE, size: f32=20, font:=raylib.Font{}, spacing:f32=1) {
    measured := text_measure(text, size, font)
    draw_text(s, text, pos - measured * 0.5, tint, size, font=font, spacing=spacing)
}

draw_text_center_no_scale :: proc(s: ^State, text: string, pos: raylib.Vector2,
    tint := raylib.WHITE, size: f32 = 20.0, font := raylib.Font{}, spacing: f32 = 1) {
    measured := text_measure(text, size, font)
    draw_text_no_scale(s, text, pos - measured * 0.5, tint=tint, size=size, font=font, spacing=spacing)
}

draw_text_no_scale :: proc(s: ^State, text: string, pos: raylib.Vector2,
    tint := raylib.WHITE, size: f32 = 20.0, font := raylib.Font{}, spacing:f32=1) {
    append(&s.draws, DrawTextCommand{text=text, tint=tint, size=size, pos=pos,
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
    append(&s.draws, DrawSpriteCommand{texture=texture, pos=pos, size=size,
        tint=tint, no_scale=true})
}

draw_sprite_rect_no_scale :: proc(s: ^State, texture: raylib.Texture2D,
    body: raylib.Rectangle, tint := raylib.WHITE) {
    append(&s.draws, DrawSpriteCommand{
        texture  = texture,
        pos      = game.rect_pos(body),
        size     = game.rect_size(body),
        tint     = tint,
        no_scale = true,
    })
}

draw_sprite_src_v_no_scale :: proc(s: ^State, texture: raylib.Texture2D,
    src_pos, src_size, pos, size: raylib.Vector2, tint := raylib.WHITE) {
    append(&s.draws, DrawSpriteSrcCommand{
        texture  = texture,
        body     = {pos.x, pos.y, size.x, size.y},
        src      = {src_pos.x, src_pos.y, src_size.x, src_size.y},
        tint     = tint,
        no_scale = true,
    })
}

draw_sprite_src_rect_no_scale :: proc(s: ^State, texture: raylib.Texture2D,
    src, body: raylib.Rectangle, tint := raylib.WHITE) {
    append(&s.draws, DrawSpriteSrcCommand{
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
    append(&s.draws, DrawRectCommand{body={pos.x, pos.y, size.x, size.y}, tint=tint})
}

draw_rect_rect :: proc(s: ^State, body: raylib.Rectangle, tint := raylib.WHITE) {
    append(&s.draws, DrawRectCommand{body=body, tint=tint})
}

draw_rect_no_scale :: proc {
    draw_rect_v_no_scale,
    draw_rect_rect_no_scale,
}

draw_rect_v_no_scale :: proc(s: ^State, pos, size: raylib.Vector2, tint := raylib.WHITE) {
    append(&s.draws, DrawRectCommand{body={pos.x, pos.y, size.x, size.y}, tint=tint, no_scale=true})
}

draw_rect_rect_no_scale :: proc(s: ^State, body: raylib.Rectangle, tint := raylib.WHITE) {
    append(&s.draws, DrawRectCommand{body=body, tint=tint, no_scale=true})
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
    raylib.DrawRectangleRec(body, cmd.tint)
}
