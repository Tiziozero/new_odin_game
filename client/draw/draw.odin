package draw
import "vendor:raylib"

DrawSpriteCommand :: struct {
    texture: raylib.Texture2D,
    pos, size: raylib.Vector2,
}
DrawTextCommand :: struct {
    text: string,
    font: raylib.Font,
    pos: raylib.Vector2,
    tint: raylib.Color,
    size: f32,
}
draw_command :: proc {
    draw_command_spite,
    draw_command_text,
}
draw_command_text :: proc(s:^ State, cmd: DrawTextCommand) {
    pos := cmd.pos*SCREEN_FACTOR;
    cstr := strings.clone_to_cstring(cmd.text, allocator=s.frame_arena.block_allocator)
    raylib.DrawTextEx(cmd.font, cstr, pos, cmd.size*SCREEN_FACTOR, 1, cmd.tint)
}
draw_command_spite :: proc(s:^ State, cmd: DrawSpriteCommand) {
    texture := cmd.texture;
    pos := cmd.pos*SCREEN_FACTOR;
    size := cmd.size*SCREEN_FACTOR;
    raylib.DrawRectangleV(pos, size, raylib.RED)
}
