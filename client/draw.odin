package main

import "core:strings"
import "core:math"
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
flush_draws_2 :: proc(s: ^State) {
    vis := visible_rect()
    for cmd in s.draws {
        draw_command_2(s, cmd, vis) }
    clear(&s.draws)
}
bool_snap := false
snap_f32 :: proc(v: f32) -> f32 { if bool_snap { return math.round(v) } else {return v}}//math.round(v) }
snap_v2 :: proc(v: raylib.Vector2) -> raylib.Vector2 { return {snap(v.x), snap(v.y)} }
snap_rect :: proc(v: raylib.Rectangle) -> raylib.Rectangle { return {snap(v.x), snap(v.y), snap(v.width), snap(v.height)} }
snap :: proc {
    snap_f32,
    snap_v2,
    snap_rect,
}
// skips what's outside + move to top left
draw_command_2 :: proc(s: ^State, cmd: DrawCommand, vis: raylib.Rectangle) {
    x :f32= SCREEN_WIDTH*0.5*(1-1/SCREEN_FACTOR)
    y :f32= SCREEN_HEIGHT*0.5*(1-1/SCREEN_FACTOR)
    switch c in cmd {
    case DrawTextCommand:
        factor := SCREEN_FACTOR if !c.no_scale else 1.0
        measured := text_measure(c.text, c.size * factor, c.font, c.spacing)
        b := raylib.Rectangle{c.pos.x * factor, c.pos.y * factor, measured.x, measured.y}
        if c.no_scale { // don't move, scale is 1
            draw_command_text(s, c)
        } else {
            if rect_overlaps(b, vis) { // if it's visible then move
                copy : DrawTextCommand = c
                copy.pos -= snap(raylib.Vector2{x,y})
                // sub x/y from it
                draw_command_text(s, copy)
            }
        }

    case DrawSpriteCommand:
        factor := SCREEN_FACTOR if !c.no_scale else 1.0
        b := raylib.Rectangle{c.pos.x * factor, c.pos.y * factor,
                               c.size.x * factor, c.size.y * factor}
        if c.no_scale {
            draw_command_sprite(s, c)
        } else {
            if rect_overlaps(b, vis) {
                copy : DrawSpriteCommand = c
                copy.pos -= {x,y}
                // sub x/y from it
                draw_command_sprite(s, copy)
            }
        }

    case DrawSpriteSrcCommand:
        factor := SCREEN_FACTOR if !c.no_scale else 1.0
        b := raylib.Rectangle{
            c.body.x * factor, c.body.y * factor,
            c.body.width * factor, c.body.height * factor,
        }
        if c.no_scale {
            draw_command_sprite_src(s, c)
        } else {
            if rect_overlaps(b, vis) {
                copy : DrawSpriteSrcCommand = c
                copy.body.x -= snap(x)
                copy.body.y -= snap(y)
                // sub x/y from it
                draw_command_sprite_src(s, copy)
            }
        }

    case DrawRectCommand:
        factor := SCREEN_FACTOR if !c.no_scale else 1.0
        b := raylib.Rectangle{
            c.body.x * factor, c.body.y * factor,
            c.body.width * factor, c.body.height * factor,
        }
        if c.no_scale {
            draw_command_rect(s, c)
        } else {
            if rect_overlaps(b, vis) {
                copy : DrawRectCommand = c
                copy.body.x -= x
                copy.body.y -= y
                // sub x/y from it
                draw_command_rect(s, copy)
            }
        }
    }
}
draw_command_2_old :: proc(s: ^State, cmd: DrawCommand, vis: raylib.Rectangle) {
    x :f32= SCREEN_WIDTH*0.5*(1-1/SCREEN_FACTOR)
    y :f32= SCREEN_HEIGHT*0.5*(1-1/SCREEN_FACTOR)
    switch c in cmd {
    case DrawTextCommand:
        factor := SCREEN_FACTOR if !c.no_scale else 1.0
        measured := text_measure(c.text, c.size * factor, c.font, c.spacing)
        b := raylib.Rectangle{c.pos.x * factor, c.pos.y * factor, measured.x, measured.y}
        if c.no_scale { // don't move, scale is 1
            draw_command_text(s, c)
        } else {
            if rect_overlaps(b, vis) { // if it's visible then move
                copy : DrawTextCommand = c
                copy.pos -= {x,y}
                // sub x/y from it
                draw_command_text(s, copy)
            }
        }

    case DrawSpriteCommand:
        factor := SCREEN_FACTOR if !c.no_scale else 1.0
        b := raylib.Rectangle{c.pos.x * factor, c.pos.y * factor,
                               c.size.x * factor, c.size.y * factor}
        if c.no_scale {
            draw_command_sprite(s, c)
        } else {
            if rect_overlaps(b, vis) {
                copy : DrawSpriteCommand = c
                copy.pos -= {x,y}
                // sub x/y from it
                draw_command_sprite(s, copy)
            }
        }

    case DrawSpriteSrcCommand:
        factor := SCREEN_FACTOR if !c.no_scale else 1.0
        b := raylib.Rectangle{
            c.body.x * factor, c.body.y * factor,
            c.body.width * factor, c.body.height * factor,
        }
        if c.no_scale {
            draw_command_sprite_src(s, c)
        } else {
            if rect_overlaps(b, vis) {
                copy : DrawSpriteSrcCommand = c
                copy.body.x -= x
                copy.body.y -= y
                // sub x/y from it
                draw_command_sprite_src(s, copy)
            }
        }

    case DrawRectCommand:
        factor := SCREEN_FACTOR if !c.no_scale else 1.0
        b := raylib.Rectangle{
            c.body.x * factor, c.body.y * factor,
            c.body.width * factor, c.body.height * factor,
        }
        if c.no_scale {
            draw_command_rect(s, c)
        } else {
            if rect_overlaps(b, vis) {
                copy : DrawRectCommand = c
                copy.body.x -= x
                copy.body.y -= y
                // sub x/y from it
                draw_command_rect(s, copy)
            }
        }
    }
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
    raylib.DrawTextEx(font, cstr, snap(pos), snap(size), spacing, cmd.tint)
}

@(private="file")
draw_command_sprite :: proc(s: ^State, cmd: DrawSpriteCommand) {
    factor := SCREEN_FACTOR if !cmd.no_scale else 1.0
    pos    := cmd.pos  * factor
    size   := cmd.size * factor
    src    := raylib.Rectangle{0, 0, f32(cmd.texture.width), f32(cmd.texture.height)}
    dst    := raylib.Rectangle{pos.x, pos.y, size.x, size.y}
    /*if dst.x > s.camera.x + s.camera.width { return }
    if dst.x + dst.width < s.camera.x { return }
    if dst.y > s.camera.y + s.camera.height { return }
    if dst.y + dst.height < s.camera.y { return }*/
    raylib.DrawTexturePro(cmd.texture, snap(src), snap(dst), {0, 0}, 0, cmd.tint)
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
    /*if dst.x > s.camera.x + s.camera.width { return }
    if dst.x + dst.width < s.camera.x { return }
    if dst.y > s.camera.y + s.camera.height { return }
    if dst.y + dst.height < s.camera.y { return }*/
    raylib.DrawTexturePro(cmd.texture, snap(cmd.src), snap(dst), {0, 0}, 0, cmd.tint)
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
    /*dst := unapply_camera(s, body)
    if dst.x > s.camera.x + s.camera.width { return }
    if dst.x + dst.width < s.camera.x { return }
    if dst.y > s.camera.y + s.camera.height { return }
    if dst.y + dst.height < s.camera.y { return }*/
    raylib.DrawRectangleRec(snap(body), cmd.tint)
}
// in draw.odin or wherever flush_draws lives

visible_rect :: proc() -> raylib.Rectangle {
    x := f32(SCREEN_WIDTH)  * 0.5 * (SCREEN_FACTOR - 1)
    y := f32(SCREEN_HEIGHT) * 0.5 * (SCREEN_FACTOR - 1)
    // src used flipped Y, so the top-left in logical space is (x, y)
    return raylib.Rectangle{
        x      = x,
        y      = y,
        width  = f32(SCREEN_WIDTH),
        height = f32(SCREEN_HEIGHT),
    }
}

rect_overlaps :: proc(a, b: raylib.Rectangle) -> bool {
    return a.x < b.x + b.width  &&
           a.x + a.width  > b.x &&
           a.y < b.y + b.height &&
           a.y + a.height > b.y
}
