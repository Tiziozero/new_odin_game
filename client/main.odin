package main

SCREEN_FACTOR := f32(2.0)
MIN_ODIN :: "dev-2026-06"

when ODIN_VERSION < MIN_ODIN {
    #panic("Requires odin dev-2026-06")
}

import "core:fmt"
import "core:math/rand"
import "core:mem"
import "core:net"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"
import "project:common/buffer_io"
import "project:common/game"
import "project:common/networking"
import raylib "vendor:raylib"
ID: u32 = 0
apply_camera_v :: proc(camera: raylib.Rectangle, v: raylib.Vector2) -> raylib.Vector2 {
    return v - game.rect_pos(camera)
}
unapply_camera_v :: proc(camera: raylib.Rectangle, v: raylib.Vector2) -> raylib.Vector2 {
    return v + game.rect_pos(camera)
}
apply_camera_r :: proc(c: raylib.Rectangle, v: raylib.Rectangle) -> raylib.Rectangle {
    return {c.x-v.x, c.y-v.y, v.width,v.height}
}
unapply_camera_r :: proc(c: raylib.Rectangle, v: raylib.Rectangle) -> raylib.Rectangle {
    return {c.x+v.x, c.y+v.y, v.width,v.height}
}
apply_camera_s_v :: proc(s: ^State, v: raylib.Vector2) -> raylib.Vector2 {
    camera := s.camera
    return v - game.rect_pos(camera)
}
unapply_camera_s_v :: proc(s: ^State, v: raylib.Vector2) -> raylib.Vector2 {
    camera := s.camera
    return v + game.rect_pos(camera)
}
apply_camera_s_r :: proc(s: ^State, v: raylib.Rectangle) -> raylib.Rectangle {
    c := s.camera
    return {c.x-v.x, c.y-v.y, v.width,v.height}
}
unapply_camera_s_r :: proc(s: ^State, v: raylib.Rectangle) -> raylib.Rectangle {
    c := s.camera
    return {c.x+v.x, c.y+v.y, v.width,v.height}
}
apply_camera :: proc {
    apply_camera_v,
    apply_camera_r,
    apply_camera_s_v,
    apply_camera_s_r,
}
unapply_camera :: proc {
    unapply_camera_v,
    unapply_camera_r,
    unapply_camera_s_v,
    unapply_camera_s_r,
}

State :: struct {
    player_handle:    int,
    entities_lock:    sync.Mutex,
    // server entities
    state_entities:   map[game.EntityHandle]game.Entity,
    // interpolates from server entities
    current_entities: map[game.EntityHandle]game.Entity,
    camera:           raylib.Rectangle,
    assets:           game.AssetManger,
    frame_arena:      mem.Dynamic_Arena,
    logs:             [dynamic]string,
    socket:           net.UDP_Socket,
    connected:        bool,
    server_endpoint:  net.Endpoint,
    ping:             f32,
    pings:            map[u8]time.Time,
    draws:            [dynamic]DrawCommand,
    gmap:             game.Map,
    toggle_views:     bool,
}
InputHandler :: struct {
    action: proc(game: ^State),
}
InputEventKind :: enum {
    IE_CLICK,
    IE_KEY_PRESSED,
    IE_KEY_DOWN,
    IE_MB_PRESSED, // mouse button
    IE_MB_DOWN,
    IE_SCROLL, // add to InputEventKind
}
InputEvent :: struct {
    kind:         InputEventKind,
    k:            raylib.KeyboardKey,
    mb:           raylib.MouseButton,
    click:        raylib.Vector2,
    scroll_delta: f32,
}
rl_to_game :: proc(events: ^[dynamic]InputEvent) {
    clear(events)
    // Keyboard
    for keyc := 0; keyc < 348; keyc += 1 {
        k := raylib.KeyboardKey(keyc)

        if raylib.IsKeyPressed(k) {
            append(events, InputEvent{kind = .IE_KEY_PRESSED, k = k})
        }

        if raylib.IsKeyDown(k) {
            append(events, InputEvent{kind = .IE_KEY_DOWN, k = k})
        }
    }

    // Mouse buttons to check
    buttons := [?]raylib.MouseButton{.LEFT, .RIGHT, .MIDDLE}

    for mb in buttons {
        // Pressed (click)
        if raylib.IsMouseButtonPressed(mb) {
            append(
                events,
                InputEvent {
                    kind  = .IE_MB_PRESSED,
                    mb    = mb,
                    click = raylib.GetMousePosition(

                    ) / raylib.Vector2{SCREEN_WIDTH, SCREEN_HEIGHT}, // 0 to 1
                },
            )
        }

        // Held
        if raylib.IsMouseButtonDown(mb) {
            append(events, InputEvent{kind = .IE_MB_DOWN, mb = mb})
        }
    }
    // Scroll
    scroll := raylib.GetMouseWheelMove()
    if scroll != 0 {
        append(events, InputEvent{kind = .IE_SCROLL, scroll_delta = scroll})
    }
}
SCREEN_SCALE :: 300
SCREEN_WIDTH :: 4 * SCREEN_SCALE
SCREEN_HEIGHT :: 3 * SCREEN_SCALE
SCALED_SCREEN_WIDTH :: proc() -> f32 {
    return f32(SCREEN_WIDTH) / f32(SCREEN_FACTOR)
}
SCALED_SCREEN_HEIGHT :: proc() -> f32 {
    return f32(SCREEN_HEIGHT) / f32(SCREEN_FACTOR)
}
draw_entity :: proc(s: ^State, camera: raylib.Rectangle, e: ^game.Entity) {
    p := apply_camera(camera, game.rect_pos(e.body))
    if e.body.width == 0 || e.body.height == 0 {
        fmt.println(e)
        panic("body is fucked")
    }
    // raylib.DrawRectangleV(p, game.rect_size(e.body), raylib.RED);
    draw_rect(s, p, game.rect_size(e.body), raylib.RED)
    width := f32(s.assets.assets[e.texture].texture.width)
    height := f32(s.assets.assets[e.texture].texture.height)
    src := raylib.Rectangle {
        x      = 1.2 * (width / 4),
        y      = height / 4,
        width  = width / 2,
        height = height / 2,
    }
    src=raylib.Rectangle{ x=0,y=0, width=width, height=height }
    dest := raylib.Rectangle{p.x, p.y, e.body.width, e.body.height}
    draw_sprite_rect(s, texture = s.assets.assets[e.texture].texture, body = dest)
    // draw id
    str := fmt.aprintf("%d:%.1f", e.id, e.health, allocator = s.frame_arena.block_allocator)

    tpos := apply_camera(
        camera,
        game.rect_pos(e.body) +
        game.rect_size(e.body) * 0.5 -
        (e.body.height / 2 + 20) * raylib.Vector2{0, 1},
    )
    // raylib.DrawRectangle(i32(tpos.x)-2, i32(tpos.y), w + 4, 20, raylib.BLACK);
    // raylib.DrawText(cstr, i32(tpos.x), i32(tpos.y), 20, raylib.WHITE);
    draw_text_center(s, text = str, pos = tpos, size = 20, spacing = 5)
    // delete(cstr);
}
MAX_ZOOM_FACTOR :: 8
MOUSE_DELTA :: 25
handle_input :: proc(e: ^InputEvent, s: ^State) {
    #partial switch e.kind {
    case .IE_SCROLL:
        {
            // SCREEN_FACTOR += e.scroll_delta / MOUSE_DELTA
            // if SCREEN_FACTOR < 1 {SCREEN_FACTOR = 1}
            // if SCREEN_FACTOR > MAX_ZOOM_FACTOR {SCREEN_FACTOR = MAX_ZOOM_FACTOR}
        }
    case .IE_KEY_PRESSED:
        {
            #partial switch e.k {
            case .A:
                fmt.println("a")
            case .D:
                fmt.println("d")
            case .W:
                fmt.println("w")
            case .S:
                fmt.println("s")
            case .T:
                s.toggle_views = !s.toggle_views
            case .K:
                bool_snap = !bool_snap
            case:
            }
        }
    case .IE_MB_PRESSED:
        {
            if e.mb == .RIGHT {     // move
                p, ok := s.state_entities[ID]
                assert(ok)
                sposx := (e.click.x - 0.5) * SCALED_SCREEN_WIDTH()
                sposy := (e.click.y - 0.5) * SCALED_SCREEN_HEIGHT()
                send_pos := raylib.Vector2{sposx, sposy} + game.rect_pos(p.body)
                b := buffer_io.buffer_make(64)

                // move msg
                buffer_io.buffer_write_u8(&b, networking.MSG_USER_MSG);
                buffer_io.buffer_write_u32(&b, ID)
                buffer_io.buffer_write_u8(&b, game.USR_MSG_MOVE)
                buffer_io.buffer_write_f32(&b, send_pos.x)
                buffer_io.buffer_write_f32(&b, send_pos.y)
                n, nok := net.send_udp(s.socket, b.data[:b.len], s.server_endpoint)
                assert(nok == .None)
                buffer_io.buffer_destroy(&b)
            }
        }
    }
}
get_dt :: proc() -> f32 {
    return raylib.GetFrameTime()
}
state_loop :: proc(s: ^State) {
    mem.dynamic_arena_reset(&s.frame_arena)
    clear(&s.logs)
}
init_game_con :: proc(s: ^State) -> i32 {
    ID = u32(rand.int31())
    socket, err := net.make_unbound_udp_socket(.IP4)
    if err != .None {
        panic("Err is not none in creating socket")
    }
    // request_buf : [dynamic]byte;
    // append(&request_buf, networking.MSG_CONNECT);
    rbuf := buffer_io.buffer_make(1024)
    buffer_io.buffer_write_u8(&rbuf, networking.MSG_CONNECT)
    buffer_io.buffer_write_u32(&rbuf, ID)
    // resolve server endpoint
    server_endpoint, _ := net.resolve_ip4(networking.SERVER_ENDPOINT)
    n, serr := net.send_udp(socket, rbuf.data[:rbuf.len], server_endpoint)
    if serr != .None {
        panic("err in sending connection request")
    }
    fmt.printfln("Wrote %d bytes connection", n)
    // set endpoint
    s.socket = socket
    s.server_endpoint = server_endpoint

    // set timeout for receive
    net.set_option(socket, .Receive_Timeout, 3 * time.Second)
    recv_buf: [1024]byte
    rn, endp, rerr := net.recv_udp(socket, recv_buf[:])
    if rerr != .None {
        panic("Err in receiving from server")
    }
    if endp != server_endpoint {
        panic("Received packet from someone not server")
    }

    if string(recv_buf[:rn]) != "ack" {
        panic("not ack")
    }
    buffer_io.buffer_reset(&rbuf)
    buffer_io.buffer_write_u8(&rbuf, networking.MSG_GET_STATE)
    n, serr = net.send_udp(socket, rbuf.data[:rbuf.len], server_endpoint)
    if serr != .None {
        panic("err in sending connection request")
    }
    fmt.printfln("Wrote %d bytes for request state", n)
    {
        recv_buf_b := buffer_io.buffer_make(1024)
        rn, endp, rerr := net.recv_udp(socket, recv_buf_b.data[:])
        if rerr != .None {
            panic("Err in receiving from server")
        }
        if endp != server_endpoint {
            panic("Received packet from someone not server")
        }
        recv_buf_b.len = rn
        count, ok := buffer_io.buffer_read_u32(&recv_buf_b)
        fmt.printfln("got %d entities count", count)
        for k in 0 ..< count {
            id, ok := buffer_io.buffer_read_u32(&recv_buf_b)
            if !ok {
                panic("Failed to read id")
            }
            delta := game.EntityDelta{}
            game.unpack_entity(&recv_buf_b, &delta)
            e := s.state_entities[id];
            game.implement_entity_delta(&e, &delta);
            s.state_entities[id] = e
            e.id = id
        }
        buffer_io.buffer_destroy(&recv_buf_b)
    }
    buffer_io.buffer_destroy(&rbuf)

    s.connected = true
    return 0
}
receiver_thread :: proc(s: ^State) {
    buf := buffer_io.buffer_make(1024)
    last := time.now()
    for s.connected {
        cur := time.now()
        d := time.diff(last, cur)
        // fmt.println("Since last msg:", f32(d)/f32(time.Millisecond));
        last = cur
        n, endpoint, err := net.recv_udp(s.socket, buf.data[:])
        if err != .None {
            fmt.println(err, s.socket)
            panic("recevied error in loop")
        }
        if endpoint != s.server_endpoint {
            fmt.println(endpoint)
            panic("received msg from not server")
        }
        buf.len = n
        msg, ok := buffer_io.buffer_read_u8(&buf)
        if !ok {
            panic("Failed to read message kind")
        }
        // fmt.printfln("got %d bytes (msg %d).", n, msg);
        if msg == networking.MSG_GAME_DATA {
            sync.mutex_lock(&s.entities_lock)
            count, ok := buffer_io.buffer_read_u32(&buf)
            assert(ok)
            for i in 0 ..< count {
                id, ok := buffer_io.buffer_read_u32(&buf)
                delta := game.EntityDelta{}
                game.unpack_entity(&buf, &delta)
                last, last_ok := s.state_entities[id]
                if !last_ok {
                    last = game.Entity{}
                }
                last.id = id;
                game.implement_entity_delta(&last, &delta);
                s.state_entities[id] = last
            }
            sync.mutex_unlock(&s.entities_lock)
        } else if msg == networking.MSG_PING_RESPOND {
            pingid, ok := buffer_io.buffer_read_i32(&buf)
            assert(ok)
            last, pok := s.pings[u8(pingid)]
            if !pok {
                fmt.println(pingid)
                panic("Notnok for pihg id")
            }
            delete_key(&s.pings, u8(pingid))
            now := time.now()
            diff := time.diff(now, last)
            s.ping = f32(diff) / f32(time.Millisecond)
        }

        buffer_io.buffer_reset(&buf)
    }
    panic("Not connected anymore")
}
thread_receiver_fn :: proc(data: rawptr) {
    receiver_thread(transmute(^State)data)
}

colors: []raylib.Color = {
    raylib.LIGHTGRAY,
    raylib.GRAY,
    raylib.DARKGRAY,
    raylib.YELLOW,
    raylib.GOLD,
    raylib.ORANGE,
    raylib.PINK,
    raylib.RED,
    raylib.MAROON,
    raylib.GREEN,
    raylib.LIME,
    raylib.DARKGREEN,
    raylib.SKYBLUE,
    raylib.BLUE,
    raylib.DARKBLUE,
    raylib.PURPLE,
    raylib.VIOLET,
    raylib.DARKPURPLE,
    raylib.BEIGE,
    raylib.BROWN,
    raylib.DARKBROWN,
    raylib.WHITE,
    raylib.BLACK,
    raylib.BLANK,
    raylib.MAGENTA,
    raylib.RAYWHITE,
}
tile_color_from_index :: proc(i: int) -> raylib.Color {
    return colors[(i) % len(colors)]
}

tiles: raylib.Texture2D
get_ts_src_for_wall :: proc(t:game.Tile, n: game.WallNeighbours) -> string {
    if .South in n { return "s" }
    switch n {
    case {.West,.East}:fallthrough
    case {.North,.West,.East}:
        return "a3"
    case {.East}:fallthrough
    case {.North,.East}:
        return "l"
    case {.West}:fallthrough
    case {.North,.West}:
        return "r"
    case {.North}: fallthrough
    case {}: return "t"
    case: fmt.println(n); panic("handle case for walls");
    }
    fmt.println(n);
    panic("What");
}

main :: proc() {
    raylib.InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "Hellope!")
    raylib.SetTargetFPS(60)
    tiles = raylib.LoadTexture("imgs/ts9.png")
    s := State{}
    s.toggle_views = true
    s.assets = game.load_assets("imgs.json", load =false)
    if init_game_con(&s) != 0 {
        return
    }

    t_receiver := thread.create_and_start_with_data(data = &s, fn = thread_receiver_fn)
    s.pings = make(map[u8]time.Time)


    player, pok := s.state_entities[ID]
    if !pok {
        panic("no player in entities")
    }

    events: [dynamic]InputEvent
    mem.dynamic_arena_init(&s.frame_arena)
    f := raylib.LoadFont("font.ttf")
    s.camera = raylib.Rectangle {
        width  = SCALED_SCREEN_WIDTH(),
        height = SCALED_SCREEN_HEIGHT(),
    }
    i := 0
    ping_id: u8 = 0
    pref: game.Entity
    s.gmap = game.new_map();
    target := raylib.LoadRenderTexture(i32(SCREEN_WIDTH) * 4, i32(SCREEN_HEIGHT) * 4) // copy
                                                                                      // main loop
    fmt.println(ODIN_VERSION)
    // for sorted
    sorted := make([dynamic]SortedDrawElement)
    for !raylib.WindowShouldClose() && s.connected {
        dt := raylib.GetFrameTime()
        // copy entities
        // clear_map(&s.current_entities)
        sync.lock(&s.entities_lock)
        for k, e in s.state_entities {
            copy := e
            current, ok := s.current_entities[k]
            if !ok {
                fmt.println("New entity from server:", e)
            } else {
                new_pos: raylib.Vector2
                // lerp positions
                p1 := game.rect_pos(current.body)
                p2 := game.rect_pos(copy.body)
                if raylib.Vector2Distance(p1, p2) > game.ENTITY_SPEED * dt {
                    d := raylib.Vector2Normalize(p2 - p1)
                    new_pos = p1 + d * game.ENTITY_SPEED * dt
                } else {
                    // copy body over
                    new_pos = p2
                }
                copy.body.x = new_pos.x
                copy.body.y = new_pos.y
            }
            s.current_entities[k] = copy
        }
        sync.unlock(&s.entities_lock)
        // get player info
        pok: bool
        pref, pok = s.current_entities[ID]
        assert(pok)
        append(&s.logs, "Hello, World!!")
        rl_to_game(&events)
        append(&s.logs, "events!")
        append(&s.logs, fmt.aprintf("ID: %d", ID))
        append(
            &s.logs,
            fmt.aprintf(
                "pos  :%.0f %.0f",
                player.body.x,
                player.body.y,
                allocator = s.frame_arena.block_allocator,
            ),
        )
        append(
            &s.logs,
            fmt.aprintf(
                "spos :%.0f %.0f",
                pref.body.x,
                pref.body.y,
                allocator = s.frame_arena.block_allocator,
            ),
        )
        append(
            &s.logs,
            fmt.aprintf("ping? :%.5f", s.ping, allocator = s.frame_arena.block_allocator),
        )
        append(
            &s.logs,
            fmt.aprintf(
                "view :%d",
                int(s.toggle_views) + 0,
                allocator = s.frame_arena.block_allocator,
            ),
        )
        append(
            &s.logs,
            fmt.aprintf(
                "snap :%d",
                int(bool_snap) + 0,
                allocator = s.frame_arena.block_allocator,
            ),
        )
        for &k in events {
            handle_input(&k, &s)
        }

        append(
            &s.logs,
            fmt.aprintf(
                "cam size: :%.3f:%.3f",
                s.camera.width,
                s.camera.height,
                allocator = s.frame_arena.block_allocator,
            ),
        )
        // update camera
        s.camera.x = pref.body.x - SCREEN_WIDTH / 2 + pref.body.width / 2
        s.camera.y = pref.body.y - SCREEN_HEIGHT / 2 + pref.body.height / 2
        // not since all draw calls are scaled
        s.camera.width = SCALED_SCREEN_WIDTH()
        s.camera.height = SCALED_SCREEN_HEIGHT()

        draw_game(&s, pref, &sorted)
        // draw game first
        if false {
            if s.toggle_views {     // normal view with flush 2
                raylib.BeginTextureMode(target)
                raylib.ClearBackground(raylib.PURPLE)
                flush_draws(&s)
                raylib.EndTextureMode()
                raylib.BeginDrawing()
                // uses top left quarter and draws that (actually bottom left? inversion and what not)
                src := raylib.Rectangle{0, 3 * SCREEN_HEIGHT, SCREEN_WIDTH, -SCREEN_HEIGHT} // flipped Y
                dest := raylib.Rectangle{0, 0, SCREEN_WIDTH, SCREEN_HEIGHT}
                raylib.DrawTexturePro(target.texture, src, dest, {0, 0}, 0, raylib.WHITE)
            } else {     // draw 1 whole screen
                raylib.BeginTextureMode(target)
                raylib.ClearBackground(raylib.PURPLE)
                flush_draws(&s)
                raylib.EndTextureMode()
                raylib.BeginDrawing()
                src := raylib.Rectangle{0, 0, SCREEN_WIDTH * 4, -SCREEN_HEIGHT * 4} // flipped Y
                dest := raylib.Rectangle{0, 0, SCREEN_WIDTH, SCREEN_HEIGHT}
                raylib.DrawTexturePro(target.texture, src, dest, {0, 0}, 0, raylib.WHITE)
            }
        }
        flush_draws_scale(&s)
        // draw UI
        {// i here conflicts with ping i
            i: i32 = 0
            h: f32 = f32(len(s.logs) * 24 + 10 + 20)
            draw_rect_no_scale(&s, pos = {0, 0}, size = {200, h}, tint = {0, 0, 0, 123})
            for l in s.logs {
                cstr, err := strings.clone_to_cstring(l, s.frame_arena.block_allocator)
                draw_text_no_scale(
                    &s,
                    l,
                    pos = raylib.Vector2{10, f32(10 + 24 * i)},
                    size = 24,
                    font = f,
                )
                /*raylib.DrawTextEx(f, cstr,
                  raylib.Vector2{10, f32(10 + 24*i)}, 24, 2, raylib.WHITE);*/
                i += 1
            }
        }
        // draw everything at 1:1 pixel scale

        // draw to big canvas

        flush_draws(&s)
        raylib.EndDrawing()

        i += 1
        if i % 60 == 0 {
            i = 0
            b := buffer_io.buffer_make(1024)
            // fmt.println("ping", ping_id, time.now())
            buffer_io.buffer_write_u8(&b, networking.MSG_PING)
            buffer_io.buffer_write_u32(&b, ID)
            buffer_io.buffer_write_u32(&b, u32(ping_id))

            s.pings[ping_id] = time.now()
            n, err := net.send_udp(s.socket, b.data[:b.len], s.server_endpoint)
            if err != .None {
                fmt.println(err)
                panic("Err in ping")
            }
            buffer_io.buffer_destroy(&b)
            ping_id += 1
        }
        state_loop(&s)
        clear(&events)
    }
    s.connected = false
    raylib.UnloadFont(f)
    raylib.CloseWindow()
    thread.join(t_receiver)
    net.close(s.socket)
    // init networking state
}
