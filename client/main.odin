package main

SCREEN_FACTOR := f32(1.0/1.0)

import "core:math/rand"
import "core:time"
import "core:net"
import "core:sync"
import "core:thread"
import raylib "vendor:raylib"
import "core:fmt";
import "core:strings";
import "core:mem";
import "project:common/game"
import "project:common/networking"
import "project:common/buffer_io"
ID :u32= 0;
apply_camera :: proc(camera: raylib.Rectangle, v: raylib.Vector2) -> raylib.Vector2 {
    return v - game.rect_pos(camera);
};
unapply_camera :: proc(camera: raylib.Rectangle, v: raylib.Vector2) -> raylib.Vector2 {
    return v + game.rect_pos(camera);
};


State :: struct {
    player_handle: int,
    entities_lock: sync.Mutex,
    // server entities
    state_entities: map[game.EntityHandle]game.Entity,
    // interpolates from server entities
    current_entities: map[game.EntityHandle]game.Entity,
    camera: raylib.Rectangle,
    assets: game.AssetManger,

    frame_arena: mem.Dynamic_Arena,
    logs: [dynamic]string,
    socket: net.UDP_Socket,
    connected: bool,
    server_endpoint: net.Endpoint,
    ping: f32,
    pings: map[u8]time.Time,
};
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
};
InputEvent :: struct {
    kind : InputEventKind,
    k : raylib.KeyboardKey,
    mb : raylib.MouseButton,
    click: raylib.Vector2,
    scroll_delta: f32,
}
rl_to_game :: proc(events: ^[dynamic]InputEvent) {
    clear(events);
    // Keyboard
    for keyc := 0; keyc < 348; keyc += 1 {
        k := raylib.KeyboardKey(keyc);

        if raylib.IsKeyPressed(k) {
            append(events, InputEvent{
                kind = .IE_KEY_PRESSED,
                k    = k,
            });
        }

        if raylib.IsKeyDown(k) {
            append(events, InputEvent{
                kind = .IE_KEY_DOWN,
                k    = k,
            });
        }
    }

    // Mouse buttons to check
    buttons := [?]raylib.MouseButton{.LEFT, .RIGHT, .MIDDLE};

    for mb in buttons {
        // Pressed (click)
        if raylib.IsMouseButtonPressed(mb) {
            append(events, InputEvent{
                kind  = .IE_MB_PRESSED,
                mb    = mb,
                click = raylib.GetMousePosition()/raylib.Vector2{
                    SCREEN_WIDTH,SCREEN_HEIGHT}, // 0 to 1
            });
        }

        // Held
        if raylib.IsMouseButtonDown(mb) {
            append(events, InputEvent{
                kind = .IE_MB_DOWN,
                mb   = mb,
            });
        }
    }
    // Scroll
    scroll := raylib.GetMouseWheelMove()
    if scroll != 0 {
        append(events, InputEvent{
            kind         = .IE_SCROLL,
            scroll_delta = scroll,
        })
    }
}
SCREEN_SCALE :: 300;
SCREEN_WIDTH :: 4*SCREEN_SCALE
SCREEN_HEIGHT :: 3*SCREEN_SCALE
SCALED_SCREEN_WIDTH :: proc() -> f32 {
    return f32(SCREEN_WIDTH*SCREEN_FACTOR)
}
SCALED_SCREEN_HEIGHT :: proc() -> f32 {
    return f32(SCREEN_HEIGHT*SCREEN_FACTOR)
}
draw_entity :: proc(s: ^State, camera: raylib.Rectangle, e: ^game.Entity) {
    p := apply_camera(camera, game.rect_pos(e.body));
    if e.body.width == 0 || e.body.height == 0 {
        fmt.println(e);
        panic("body is fucked");
    }
    raylib.DrawRectangleV(p, game.rect_size(e.body), raylib.RED);
    width := f32(s.assets.assets[e.texture].texture.width)
    height := f32(s.assets.assets[e.texture].texture.height)
    // src:=raylib.Rectangle{ x=0,y=0, width=width, height=height }
    src:=raylib.Rectangle{ x=1.2*(width/4),y=height/4,
        width=width/2,
        height=height/2
    }
    dest := raylib.Rectangle{p.x,p.y, e.body.width, e.body.height}
    raylib.DrawTexturePro(s.assets.assets[e.texture].texture, src, dest,
        raylib.Vector2{0,0}, 0, raylib.WHITE);
    // draw id
    str := fmt.aprintf("%d", e.id, allocator=s.frame_arena.block_allocator);
    cstr := strings.clone_to_cstring(str, allocator=s.frame_arena.block_allocator)
    w := raylib.MeasureText(cstr, 20)

    tpos := apply_camera(camera,
              game.rect_pos(e.body) + game.rect_size(e.body)*0.5 -
               (e.body.height/2+20)*raylib.Vector2{0,1} -
               raylib.Vector2{f32(w)/2, 0});

    raylib.DrawRectangle(i32(tpos.x)-2, i32(tpos.y), w + 4, 20, raylib.BLACK);
    raylib.DrawText(cstr, i32(tpos.x), i32(tpos.y), 20, raylib.WHITE);
    delete(cstr);
}
handle_input :: proc(e: ^InputEvent, s: ^State) {
    #partial switch e.kind {
    case. IE_SCROLL:
        {
            SCREEN_FACTOR += e.scroll_delta/100;
            if SCREEN_FACTOR > 1 { SCREEN_FACTOR = 1 }
            if SCREEN_FACTOR < 0.25 { SCREEN_FACTOR = 0.25 }
            fmt.println(SCREEN_FACTOR)
        }
    case .IE_KEY_DOWN:
        {
            #partial switch e.k {
            case .A: fmt.println("a");
            case .D: fmt.println("d");
            case .W: fmt.println("w");
            case .S: fmt.println("s");
            case:
            }
        }
    case .IE_MB_PRESSED:
        {
            if e.mb == .RIGHT { // move
                p := s.state_entities[ID].body
                sposx := (e.click.x-0.5)*SCALED_SCREEN_WIDTH()
                sposy := (e.click.y-0.5)*SCALED_SCREEN_HEIGHT()
                fmt.println(sposx, sposy, raylib.Vector2{sposx, sposy});
                /* send_pos := unapply_camera(s.camera,
                    raylib.Vector2{sposx, sposy} + game.rect_pos(p));*/
                send_pos := raylib.Vector2{sposx, sposy} + game.rect_pos(p)
                b := buffer_io.buffer_make(64)

                // move msg
                buffer_io.buffer_write_u8(&b,networking.MSG_USER_MSG);
                buffer_io.buffer_write_u32(&b,ID);
                buffer_io.buffer_write_u8(&b,game.USR_MSG_MOVE);
                buffer_io.buffer_write_f32(&b,send_pos.x);
                buffer_io.buffer_write_f32(&b,send_pos.y);
                n, ok := net.send_udp(s.socket, b.data[:b.len], s.server_endpoint);
                assert(ok == .None);
                buffer_io.buffer_destroy(&b);
            }
        }
    }
}
get_dt :: proc() -> f32 {
    return raylib.GetFrameTime();
}
state_loop :: proc(s: ^State) {
    mem.dynamic_arena_reset(&s.frame_arena);
    clear(&s.logs);
}
init_game_con :: proc(s: ^State) -> i32 {
    ID = u32(rand.int31())
    socket, err := net.make_unbound_udp_socket(.IP4);
    if err != .None {
        panic("Err is not none in creating socket");
    }
    // request_buf : [dynamic]byte;
    // append(&request_buf, networking.MSG_CONNECT);
    rbuf := buffer_io.buffer_make(1024)
    buffer_io.buffer_write_u8(&rbuf, networking.MSG_CONNECT)
    buffer_io.buffer_write_u32(&rbuf, ID)
    // resolve server endpoint
    server_endpoint, _ := net.resolve_ip4(networking.SERVER_ENDPOINT);
    n, serr := net.send_udp(socket, rbuf.data[:rbuf.len], server_endpoint);
    if serr != .None {
        panic("err in sending connection request");
    }
    fmt.printfln("Wrote %d bytes connection", n);
    // set endpoint
    s.socket = socket;
    s.server_endpoint = server_endpoint;

    // set timeout for receive
    net.set_option(socket, .Receive_Timeout, 3*time.Second);
    recv_buf : [1024]byte;
    rn, endp, rerr := net.recv_udp(socket, recv_buf[:]);
    if rerr != .None {
        panic("Err in receiving from server");
    }
    if endp != server_endpoint {
        panic("Received packet from someone not server");
    }

    if string(recv_buf[:rn]) != "ack" {
        panic("not ack");
    }
    buffer_io.buffer_reset(&rbuf)
    buffer_io.buffer_write_u8(&rbuf,networking.MSG_GET_STATE)
    n, serr = net.send_udp(socket, rbuf.data[:rbuf.len], server_endpoint);
    if serr != .None {
        panic("err in sending connection request");
    }
    fmt.printfln("Wrote %d bytes for request state", n);
    {
        recv_buf_b := buffer_io.buffer_make(1024);
        rn, endp, rerr := net.recv_udp(socket, recv_buf_b.data[:]);
        if rerr != .None {
            panic("Err in receiving from server");
        }
        if endp != server_endpoint {
            panic("Received packet from someone not server");
        }
        recv_buf_b.len = rn;
        count, ok := buffer_io.buffer_read_u32(&recv_buf_b);
        fmt.printfln("got %d entities count", count);
        for k in 0..<count {
            id, ok := buffer_io.buffer_read_u32(&recv_buf_b);
            if !ok {
                panic("Failed to read id");
            }
            delta := game.EntityDelta{};
            game.unpack_entity(&recv_buf_b, &delta);
            e := game.Entity{}
            e.body = delta.body
            e.status = delta.status;
            e.texture = delta.texture;
            s.state_entities[id] = e;
            e.id = id;
        }
        buffer_io.buffer_destroy(&recv_buf_b)
    }
    buffer_io.buffer_destroy(&rbuf)

    s.connected = true;
    return 0;
}
receiver_thread :: proc(s: ^State) {
    buf := buffer_io.buffer_make(1024);
    last := time.now()
    for s.connected {
        cur := time.now()
        d := time.diff(last, cur);
        // fmt.println("Since last msg:", f32(d)/f32(time.Millisecond));
        last = cur
        n, endpoint, err := net.recv_udp(s.socket, buf.data[:]);
        if err != .None {
            fmt.println(err, s.socket);
            panic("recevied error in loop");
        }
        if endpoint != s.server_endpoint {
            fmt.println(endpoint);
            panic("received msg from not server");
        }
        buf.len = n;
        msg, ok := buffer_io.buffer_read_u8(&buf);
        if !ok {
            panic("Failed to read message kind");
        }
        // fmt.printfln("got %d bytes (msg %d).", n, msg);
        if msg == networking.MSG_GAME_DATA {
            sync.mutex_lock(&s.entities_lock);
            count, ok := buffer_io.buffer_read_u32(&buf);
            assert(ok);
            for i in 0..<count {
                id, ok := buffer_io.buffer_read_u32(&buf);
                delta := game.EntityDelta{};
                game.unpack_entity(&buf, &delta);
                last, last_ok := s.state_entities[id];
                if !last_ok {
                    last = game.Entity{};
                }
                last.id = id;
                last.body = delta.body
                last.status = delta.status
                last.texture = delta.texture
                s.state_entities[id] = last;
            }
            sync.mutex_unlock(&s.entities_lock);
        } else if msg == networking.MSG_PING_RESPOND {
            pingid, ok := buffer_io.buffer_read_i32(&buf);
            assert(ok);
            last, pok := s.pings[u8(pingid)];
            if !pok {
                fmt.println(pingid);
                panic("Notnok for pihg id")
            }
            delete_key(&s.pings, u8(pingid));
            now := time.now();
            diff := time.diff(now,last);
            s.ping = f32(diff)/f32(time.Millisecond);
        }

        buffer_io.buffer_reset(&buf)
    }
    panic("Not connected anymore");
}
thread_receiver_fn :: proc(data: rawptr) {
    receiver_thread(transmute(^State)data);
}

colors : []raylib.Color = {
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
    return colors[(i)%len(colors)];
}

draw_chunk :: proc(s: ^State, cid: game.v2i,c: ^game.Chunk) {
    for i in 0..<game.CHUNK_SIZE { // rows
        for j in 0..<game.CHUNK_SIZE { // cols
            p := raylib.Vector2{};
            p.x = f32(game.TILES_SIZE*(cid.x * game.CHUNK_SIZE + i))
            p.y = f32(game.TILES_SIZE*(cid.y * game.CHUNK_SIZE + j))
            p = apply_camera(s.camera, p) // cast to screen pos
            b := raylib.Vector2{game.TILES_SIZE, game.TILES_SIZE};
            // fmt.println(c.tiles[j][i],tile_color_from_index(int(c.tiles[j][i].tileset_index)));
            index := int(c.tiles[j][i].tileset_index)%len(colors)
            raylib.DrawRectangleV(p, b,
                tile_color_from_index(index))
            str := fmt.aprintf("%d", index,
                allocator=s.frame_arena.block_allocator);
            cstr := strings.clone_to_cstring(str,
                      allocator=s.frame_arena.block_allocator)
            w := raylib.MeasureTextEx(raylib.GetFontDefault(),cstr, 20, 1)
            raylib.DrawText(cstr,
                i32(p.x + game.TILES_SIZE/2 - w.x/2),
                i32(p.y + game.TILES_SIZE/2 - w.y/2),
                20, raylib.WHITE);
        }
    }
}
main :: proc() {
    raylib.InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "Hellope!");
    raylib.SetTargetFPS(60);
    s := State{};
   s.assets = game.load_assets("imgs.json", load=true);
   if init_game_con(&s) != 0 {
        return;
    }

    t_receiver := thread.create_and_start_with_data(data=&s, fn=thread_receiver_fn);
    s.pings = make(map[u8]time.Time)



    player, pok := s.state_entities[ID];
    if !pok {
        panic("no player in entities");
    }

    events: [dynamic]InputEvent;
    mem.dynamic_arena_init(&s.frame_arena);
    f := raylib.LoadFont("font.ttf");
    s.camera = raylib.Rectangle{
        width=SCALED_SCREEN_WIDTH()/2,height=SCALED_SCREEN_HEIGHT()/2}
    i := 0;
    ping_id :u8= 0;
    pref : game.Entity
    m := game.Map{};
    m.chunks = make(map[game.v2i]game.Chunk);
    m.seed = 420
    m.octaves = 16
    chunkm1m1 := game.generate_chunck(&m, -1,-1);
    chunkm10 := game.generate_chunck(&m, -1, 0);
    chunk10 := game.generate_chunck(&m, 1, 0);
    chunk := game.generate_chunck(&m, 0,0);
    chunk11 := game.generate_chunck(&m, 1,1);
    target := raylib.LoadRenderTexture(
                i32(SCREEN_WIDTH), i32(SCREEN_HEIGHT))  // logical res
    // main loop
    for !raylib.WindowShouldClose() && s.connected {
        dt := raylib.GetFrameTime();
        // copy entities
        // clear_map(&s.current_entities)
        sync.lock(&s.entities_lock);
        for k, e in s.state_entities {
            copy := e;
            current, ok := s.current_entities[k];
            if !ok {
                fmt.println("New entity from server:", e);
            } else {
                new_pos: raylib.Vector2;
                // lerp positions
                p1 := game.rect_pos(current.body)
                p2 := game.rect_pos(copy.body)
                if raylib.Vector2Distance(p1, p2) > game.ENTITY_SPEED*dt {
                    d := raylib.Vector2Normalize(p2 - p1)
                    new_pos = p1 + d*game.ENTITY_SPEED*dt
                } else {
                    // copy body over
                    new_pos = p2;
                }
                copy.body.x = new_pos.x
                copy.body.y = new_pos.y
            }
            s.current_entities[k] = copy
        }
        sync.unlock(&s.entities_lock);
        // get player info
        pok: bool
        pref, pok = s.current_entities[ID];
        assert(pok);
        append(&s.logs, "Hello, World!!")
        rl_to_game(&events);
        append(&s.logs, "events!");
        append(&s.logs, fmt.aprintf("ID: %d", ID));
        append(&s.logs, fmt.aprintf("pos  :%.0f %.0f",
                player.body.x, player.body.y, allocator = s.frame_arena.block_allocator));
        append(&s.logs, fmt.aprintf("spos :%.0f %.0f",
                pref.body.x, pref.body.y, allocator = s.frame_arena.block_allocator));
        append(&s.logs, fmt.aprintf("ping? :%.5f", s.ping, allocator = s.frame_arena.block_allocator))
        for &k in events {
            handle_input(&k, &s);
        }

        // update camera
        s.camera.x = pref.body.x - SCREEN_WIDTH/2 + pref.body.width/2;
        s.camera.y = pref.body.y - SCREEN_HEIGHT/2 + pref.body.height/2;
        s.camera.width = SCALED_SCREEN_WIDTH()
        s.camera.height = SCALED_SCREEN_HEIGHT()

        // game loop
        // draw map to scaled
        raylib.BeginTextureMode(target)
        raylib.ClearBackground(raylib.PURPLE);

        draw_chunk(&s,game.v2i{-1,-1},&chunkm1m1)
        draw_chunk(&s,game.v2i{-1,0},&chunkm10)
        draw_chunk(&s,game.v2i{1,0},&chunk10)
        draw_chunk(&s,game.v2i{0,0},&chunk)
        draw_chunk(&s,game.v2i{1,1},&chunk11)
        // draw_chunk(&s,game.v2i{0,0}, &chunk)
        for k, e in s.current_entities {
            c := e;
           draw_entity(&s, s.camera, &c);
        }
        raylib.EndTextureMode()
        raylib.BeginDrawing();
        {
            // draw game first
            // scale up to screen
            x := SCREEN_WIDTH/2  - SCALED_SCREEN_WIDTH()/2
            y := SCREEN_HEIGHT/2  - SCALED_SCREEN_HEIGHT()/2
            src  := raylib.Rectangle{x, y, SCALED_SCREEN_WIDTH(), -SCALED_SCREEN_HEIGHT()}  // flipped Y
            dest := raylib.Rectangle{0, 0, SCREEN_WIDTH, SCREEN_HEIGHT} 
            raylib.DrawTexturePro(target.texture, src, dest, {0,0}, 0, raylib.WHITE)
        }
        { // i here conflicts with ping i
            i : i32= 0;
            for l in s.logs {
                cstr, err := strings.clone_to_cstring(l,
                    s.frame_arena.block_allocator);
                raylib.DrawTextEx(f, cstr,
                    raylib.Vector2{10, f32(10 + 24*i)}, 24, 2, raylib.WHITE);
                i += 1;
            }
        }
        // draw everything at 1:1 pixel scale

        raylib.EndDrawing();

        i += 1;
        if i%30 == 0 {
            i = 0;
            b := buffer_io.buffer_make(1024)
           // fmt.println("ping", ping_id, time.now())
           buffer_io.buffer_write_u8(&b,networking.MSG_PING)
           buffer_io.buffer_write_u32(&b, ID)
           buffer_io.buffer_write_u32(&b, u32(ping_id))

           s.pings[ping_id] = time.now();
           n, err :=net.send_udp(s.socket, b.data[:b.len], s.server_endpoint);
           if err !=.None {
               fmt.println(err);
               panic("Err in ping");
           }
           buffer_io.buffer_destroy(&b)
           ping_id+=1;
        }
        state_loop(&s);
        clear(&events);
    }
    s.connected = false;
    raylib.UnloadFont(f);
    raylib.CloseWindow();
    thread.join(t_receiver)
    net.close(s.socket)
    // init networking state
}
