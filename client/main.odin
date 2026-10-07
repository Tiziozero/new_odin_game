// client.odin
package main

SCREEN_FACTOR := f32(1.50)
MIN_ODIN :: "dev-2026-06"

when ODIN_VERSION < MIN_ODIN {
    #panic("Requires odin dev-2026-06")
}

import "core:fmt"
import "core:mem"
import "core:net"
import "core:sync"
import "core:thread"
import "core:time"
import "project:common/buffer_io"
import "project:common/game"
import "vendor:raylib"
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
    player_handle:      int,
    spref:              game.Entity,
    pdirection:         raylib.Vector2, // direction player's looking at
    mpos:               raylib.Vector2, // mouse pos in window pixels
    state_lock:         sync.Mutex,
    // server entities
    state_entities:     map[game.EntityHandle]game.Entity,
    // what each server entity is (player, shopkeeper, ...). Written by the
    // receiver thread under state_lock, alongside state_entities.
    entity_roles:       map[game.EntityHandle]game.EntityRole,
    // interpolates from server entities
    current_entities:   map[game.EntityHandle]game.Entity,
    // main-thread copy of entity_roles, matching current_entities. Draw code
    // reads this one so it never touches the receiver thread's map.
    current_roles:      map[game.EntityHandle]game.EntityRole,

    projectiles:        [dynamic]game.Projectile,
    projectiles_count:  u32,
    camera:             raylib.Rectangle,
    assets:             game.AssetManger,
    frame_arena:        mem.Dynamic_Arena,
    logs:               [dynamic]string,   // unbounded: cap or ring-buffer it
    socket:             net.UDP_Socket,
    connected:          bool,
    server_endpoint:    net.Endpoint,
    ping:               f32,
    pings:              map[u8]time.Time,
    layer:              Layer,                       // where draw_* currently queues
    layers:             [Layer][dynamic]DrawCommand, // replaces `draws`
    water:              WaterShader,
    gmap:               game.Map,
    debug:              bool,
    move_to:            raylib.Vector2,
    abilities:          [ABILITIES_COUNT]PlayerAbility, // client side abilities
    energy:             f32,
    debug_last_packet_size: u32,
}
PlayerAbility :: struct {
    active: u8,
    ability_id: u32,
    level: u32,
    cooldown: f32,
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
slog :: proc(s: ^State, format: string, str: ..any) {
    log := fmt.aprintf(format, ..str, allocator=s.frame_arena.block_allocator)
    append(&s.logs, log)
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

// ---------------------------------------------------------------------
// Screen <-> world conversion
//
// "screen" = window pixels (what GetMousePosition returns).
// "world"  = game coordinates (what entity bodies / the server use).
//
// Zoom is centered on the player: the middle of the player's body always
// sits at the middle of the screen, and everything else is scaled around
// that point by SCREEN_FACTOR:
//
//   screen = screen_center + (world - view_center) * SCREEN_FACTOR
//   world  = view_center   + (screen - screen_center) / SCREEN_FACTOR
//
// Use these instead of hand-rolled math so a zoom change can't desync
// mouse hit-testing from what's drawn.
// ---------------------------------------------------------------------

screen_center :: proc() -> raylib.Vector2 {
    return raylib.Vector2{SCREEN_WIDTH, SCREEN_HEIGHT} * 0.5
}

// World point that is currently drawn at the middle of the screen: the
// center of the (interpolated) player body, same entity the camera follows.
view_center_world :: proc(s: ^State) -> raylib.Vector2 {
    return game.rect_pos(s.spref.body) + game.rect_size(s.spref.body) * 0.5
}

screen_to_world :: proc(s: ^State, p: raylib.Vector2) -> raylib.Vector2 {
    return view_center_world(s) + (p - screen_center()) / SCREEN_FACTOR
}

world_to_screen :: proc(s: ^State, p: raylib.Vector2) -> raylib.Vector2 {
    return screen_center() + (p - view_center_world(s)) * SCREEN_FACTOR
}

screen_to_world_rect :: proc(s: ^State, r: raylib.Rectangle) -> raylib.Rectangle {
    pos := screen_to_world(s, raylib.Vector2{r.x, r.y})
    return {pos.x, pos.y, r.width / SCREEN_FACTOR, r.height / SCREEN_FACTOR}
}

world_to_screen_rect :: proc(s: ^State, r: raylib.Rectangle) -> raylib.Rectangle {
    pos := world_to_screen(s, raylib.Vector2{r.x, r.y})
    return {pos.x, pos.y, r.width * SCREEN_FACTOR, r.height * SCREEN_FACTOR}
}

// Where the mouse is in world coordinates right now.
mouse_world :: proc(s: ^State) -> raylib.Vector2 {
    return screen_to_world(s, s.mpos)
}

point_in_rect :: proc(r: raylib.Rectangle, p: raylib.Vector2) -> bool {
    return p.x >= r.x && p.x <= r.x + r.width && p.y >= r.y && p.y <= r.y + r.height
}

// Badge / label color for each kind of entity.
role_color :: proc(r: game.EntityRole) -> raylib.Color {
    switch r {
    case .Unknown:    return raylib.GRAY
    case .Player:     return raylib.SKYBLUE
    case .Idle:       return raylib.LIGHTGRAY
    case .Wanderer:   return raylib.GREEN
    case .Shopkeeper: return raylib.GOLD
    case .Hostile:    return raylib.RED
    }
    return raylib.GRAY
}

draw_entity :: proc(s: ^State, camera: raylib.Rectangle, e: ^game.Entity) {
    p := apply_camera(camera, game.rect_pos(e.body))
    if e.body.width == 0 || e.body.height == 0 {
        fmt.println(e)
        panic("body is fucked")
    }
    // Hover test happens in world space (mouse converted through the zoom),
    // so it matches the drawn body at any SCREEN_FACTOR.
    if point_in_rect(e.body, mouse_world(s)) {
        draw_rect(s, p, game.rect_size(e.body), raylib.YELLOW)
    } else {
        // raylib.DrawRectangleV(p, game.rect_size(e.body), raylib.RED);
        draw_rect(s, p, game.rect_size(e.body), raylib.RED)
    }
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

    // what is this entity? (main thread only map, see State.current_roles)
    role := s.current_roles[e.id] or_else game.EntityRole.Unknown
    color := role_color(role)

    // colored badge in the top-left corner of the body
    draw_rect(s, p + raylib.Vector2{0, -10}, raylib.Vector2{8, 8}, color)

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
    // role name one line above the id/health line
    draw_text_center(s, text = game.entity_role_name(role), pos = tpos - raylib.Vector2{0, 22}, size = 20, spacing = 5)
    // delete(cstr);
}
draw_projectile :: proc(s: ^State, p: ^game.Projectile) {
    dr := apply_camera(s, p.position);
    draw_rect(s, pos=dr, size=raylib.Vector2{5,5}, tint=raylib.YELLOW)
}
MAX_ZOOM_FACTOR :: 8
MOUSE_DELTA :: 25
handle_input :: proc(e: ^InputEvent, s: ^State) {
    #partial switch e.kind {
    case .IE_SCROLL: // no scroll
        {
            SCREEN_FACTOR += e.scroll_delta / MOUSE_DELTA
            if SCREEN_FACTOR < 1 {SCREEN_FACTOR = 1}
            if SCREEN_FACTOR > MAX_ZOOM_FACTOR {SCREEN_FACTOR = MAX_ZOOM_FACTOR}
        }
    case .IE_KEY_PRESSED:
        {
            #partial switch e.k {
            case .Q:
                send_user_ability(s, 0);
            case .W:
                send_user_ability(s, 1);
            case .E:
                send_user_ability(s, 2);
            case .R:
                send_user_ability(s, 3);
            case .T:
                s.debug = !s.debug
            case .K:
                bool_snap = !bool_snap
            case:
            }
        }
    case .IE_MB_PRESSED:
        {
            if e.mb == .RIGHT {     // move
                p := s.spref // player ref
                // e.click is the mouse as 0..1 of the window; back to pixels,
                // then through the zoom into world space. move_to is the
                // body's top-left, so subtract half the body to put the
                // body's center under the cursor.
                click_screen := e.click * raylib.Vector2{SCREEN_WIDTH, SCREEN_HEIGHT}
                send_pos := screen_to_world(s, click_screen) - game.rect_size(p.body) * 0.5
                b := game.init_send_message()
                game.pack_client_message(&b, game.Msg{
                    kind = .USER_MSG,
                    data = game.UserMsg{
                        user_id = ID,
                        kind    = .MOVE,
                        data    = game.MoveMsg{pos = send_pos},
                    },
                })
                err := game.send_message(s.socket, s.server_endpoint, &b)
                assert(err == .None)
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

ABILITIES_COUNT :: game.ABILITIES_COUNT
user_specific_data :: struct {
    energy: f32,

    abilities: [ABILITIES_COUNT]PlayerAbility,

    move_to: raylib.Vector2
}

// --- replace handle_server_msg entirely ---
handle_server_msg :: proc(s: ^State, buf: ^buffer_io.Buffer) {
    msg := game.unpack_client_message(buf)

    switch msg.kind {
    case .STRING_MSG: {
        fmt.println(msg.data.(game.StringMsg))
    }
    case .GAME_DATA:
        data := msg.data.(game.GameData)
        apply_game_data(s, data)

    case .GAME_MSG:
        // Projectile changes travel inside GameData.projectile_events.
        // The only thing sent out-of-band right now is SPACE_CHANGED, which
        // is just logged: the full sync that follows it replaces the world.
        fmt.println(msg.data.(game.GameMsg))

    case .PING_RESPOND:
        d := msg.data.(game.PingRespondMsg)
        sync.lock(&s.state_lock)
        last, pok := s.pings[u8(d.id)]
        if !pok {
            fmt.println(d.id)
            panic("Notnok for pihg id")
        }
        delete_key(&s.pings, u8(d.id))
        now := time.now()
        diff := time.diff(now, last)
        s.ping = f32(diff) / f32(time.Millisecond)
        sync.unlock(&s.state_lock)

    case .Invalid, .CONNECT, .START_GAME, .GET_STATE, .PING, .USER_MSG:
        fmt.println(msg.kind)
        panic("Unknown or client-only message received")
    }
}

// Applies one GameData snapshot to client state. Same function handles
// both a normal delta tick and a full sync - the only difference is which
// branch of the projectile logic runs, and that a full sync also drops any
// entity it doesn't list.
apply_game_data :: proc(s: ^State, data: game.GameData) {
    sync.lock(&s.state_lock)

    s.energy = data.user_data.energy
    for i in 0 ..< ABILITIES_COUNT {
        a := data.user_data.abilities[i]
        s.abilities[i].active     = a.active
        s.abilities[i].ability_id = a.ability_id
        s.abilities[i].level      = a.level
        s.abilities[i].cooldown   = a.cooldown
    }
    s.move_to = data.user_data.move_to

    // Removals first: if an id is removed and re-added in the same packet
    // (reconnect), the delta below must win. Prunes for current_entities /
    // current_roles happen on the main thread, in the frame copy loop.
    for ev in data.entity_events {
        if ev.kind == .REMOVED {
            h := game.EntityHandle(ev.entity_id)
            delete_key(&s.state_entities, h)
            delete_key(&s.entity_roles, h)
        }
    }

    for e in data.entities {
        h := game.EntityHandle(e.id)
        last, last_ok := s.state_entities[h]
        if !last_ok {
            last = game.Entity{}
        }
        last.id = e.id
        delta := e.delta
        game.implement_entity_delta(&last, &delta)
        s.state_entities[h] = last
        s.entity_roles[h] = e.role
    }

    if data.full_sync {
        // A full sync is the complete truth: forget everything it doesn't list.
        present := make(map[game.EntityHandle]struct{}, context.temp_allocator)
        for e in data.entities {
            present[game.EntityHandle(e.id)] = {}
        }
        stale := make([dynamic]game.EntityHandle, context.temp_allocator)
        for k in s.state_entities {
            if k not_in present {
                append(&stale, k)
            }
        }
        for k in stale {
            delete_key(&s.state_entities, k)
            delete_key(&s.entity_roles, k)
        }

        for u32(len(s.projectiles)) < u32(len(data.full_projectiles)) {
            append(&s.projectiles, game.Projectile{})
        }
        for i in 0 ..< len(data.full_projectiles) {
            p := data.full_projectiles[i]
            p.active = true
            s.projectiles[i] = p
        }
        for i in len(data.full_projectiles) ..< len(s.projectiles) {
            s.projectiles[i].active = false
        }
        s.projectiles_count = u32(len(data.full_projectiles))
    } else {
        for ev in data.projectile_events {
            switch v in ev.data {
            case game.SpawnProjectileMsg:
                p := v.projectile
                p.active = true
                for u32(len(s.projectiles)) <= s.projectiles_count {
                    append(&s.projectiles, game.Projectile{})
                }
                s.projectiles[s.projectiles_count] = p
                s.projectiles_count += 1

            case game.RemoveProjectileMsg:
                for i in 0 ..< s.projectiles_count {
                    if s.projectiles[i].id == v.projectile_id {
                        last := s.projectiles_count - 1
                        s.projectiles[i] = s.projectiles[last]
                        s.projectiles[last].active = false
                        s.projectiles_count -= 1
                        break
                    }
                }
                // if not found: the spawn+remove happened between two
                // of our ticks - nothing to do, safe to ignore
            }
        }
    }

    sync.unlock(&s.state_lock)
}

// --- send_user_ability: build the message through the new union ---
send_user_ability :: proc(s: ^State, ability_index: u8) {
    b := game.init_send_message()
    game.pack_client_message(&b, game.Msg{
        kind = .USER_MSG,
        data = game.UserMsg{
            user_id = ID,
            kind    = .ABILITY,
            data    = game.AbilityMsg{
                user_ability_index = ability_index,
                direction          = s.pdirection,
            },
        },
    })
    err := game.send_message(socket = s.socket, endpoint = s.server_endpoint, b = &b)
    assert(err == .None)
}


// --- receiver_thread: free the per-message temp allocations ---
receiver_thread :: proc(s: ^State) {
    buf := buffer_io.buffer_make(1024)
    last := time.now()
    for s.connected {
        cur := time.now()
        d := time.diff(last, cur)
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
        sync.lock(&s.state_lock)
        s.debug_last_packet_size = u32(n)
        sync.unlock(&s.state_lock)

        handle_server_msg(s, &buf);
        free_all(context.temp_allocator)

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

update_projectile_client :: proc(last_p: game.Projectile, dt: f32) -> (game.Projectile, bool) {
    p := last_p
    prev_pos := last_p.position
    new_pos := prev_pos + raylib.Vector2Normalize(last_p.direction) * last_p.speed * dt
    p.position = new_pos

    if raylib.Vector2Distance(p.position, last_p.origin) > p.range {
        return p, true // out of range - client should stop drawing/advancing it
    }
    return p, false
}
main :: proc() {
    flags : raylib.ConfigFlags
    flags  += {.MSAA_4X_HINT}
    raylib.InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "Hellope!")
    defer raylib.CloseWindow();
    raylib.SetTargetFPS(60)
    s := State{}
    // raylib.SetConfigFlags(flags);
    tiles = raylib.LoadTexture("imgs/ts9.png")
    s.debug = true
    s.assets = game.load_assets("imgs.json", load=true)

    r :=init_game_con(&s) 
    if r != 0 {
        return
    } else if r == 0 {
    }
    t_receiver := thread.create_and_start_with_data(data = &s, fn = thread_receiver_fn)
    s.pings = make(map[u8]time.Time)


    spref, pok := s.state_entities[ID]
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
    s.gmap = game.new_map();
    target := raylib.LoadRenderTexture(SCREEN_WIDTH, SCREEN_HEIGHT) // copy
    init_water_shader(&s, tiles);
    // for sorted
    sorted := make([dynamic]SortedDrawElement)
    prev_direction := raylib.Vector2{0,0}
    t :f32= 0.0;
    for !raylib.WindowShouldClose() && s.connected {
        dt := raylib.GetFrameTime()
        t += dt;
        rl_to_game(&events) // events
        mp := raylib.GetMousePosition()
        s.mpos = mp
        pdirection := mp - {SCREEN_WIDTH,SCREEN_HEIGHT}/2;
        if pdirection != prev_direction {
            s.pdirection = pdirection
            // send
            // b := game.init_send_message();
            // game.send_message(s.socket, s.server_endpoint, &b)
        }
        // copy entities
        // clear_map(&s.current_entities)
        sync.lock(&s.state_lock)
        other: [1024]game.Entity
        j := 0
        for k, e in s.state_entities {
            copy := e
            other[j]=e
            j+=1
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
                    s :f32 = game.ENTITY_SPEED
                    new_pos = p1 + d* s * dt
                } else {
                    // copy body over
                    new_pos = p2
                }
                copy.body.x = new_pos.x
                copy.body.y = new_pos.y
            }
            s.current_entities[k] = copy
            s.current_roles[k] = s.entity_roles[k] or_else game.EntityRole.Unknown
        }

        // Drop entities the server no longer has (died, disconnected, left the
        // space). Without this they stay in current_entities and get drawn
        // forever as ghosts nobody can hit.
        stale: [1024]game.EntityHandle
        stale_n := 0
        for k in s.current_entities {
            if k not_in s.state_entities && stale_n < len(stale) {
                stale[stale_n] = k
                stale_n += 1
            }
        }
        for k in stale[:stale_n] {
            delete_key(&s.current_entities, k)
            delete_key(&s.current_roles, k)
        }

        pref, pok := s.state_entities[ID] // set to server entity
        assert(pok)
        s.spref = s.current_entities[ID] // set spref to what player sees
        assert(pok)
        sync.unlock(&s.state_lock)
        sync.lock(&s.state_lock)
        for i in 0 ..< s.projectiles_count {
            p := s.projectiles[i]
            if !p.active {
                continue
            }
            updated, done := update_projectile_client(p, dt)
            if done {
                // don't remove from the array here - just freeze/hide it client-side;
                // the server's REMOVE_PROJECTILE event is what actually shrinks
                // projectiles_count. Marking inactive avoids it visibly overshooting
                // its range while waiting for that event to arrive.
                updated.active = false
            }
            s.projectiles[i] = updated
        }
        sync.unlock(&s.state_lock)
        debug_log(&s, pref);
        // get player info
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

        slog(&s, "%d projectiles", len(s.projectiles))
        // update camera
        s.camera.x = s.spref.body.x - SCREEN_WIDTH / 2 + pref.body.width / 2
        s.camera.y = s.spref.body.y - SCREEN_HEIGHT / 2 + pref.body.height / 2
        // not since all draw calls are scaled
        s.camera.width = SCALED_SCREEN_WIDTH()
        s.camera.height = SCALED_SCREEN_HEIGHT()

        draw_game(&s, pref, &sorted)
        if s.debug {
            for o in other[:j] {
                c := o
                draw_entity(&s, s.camera, &c);
            }
        }// --- draw projectiles ---
        sync.lock(&s.state_lock)
        for i in 0 ..< s.projectiles_count {
            p := s.projectiles[i]
            if p.active {
                draw_projectile(&s, &p)
            }
        }
        sync.unlock(&s.state_lock)

        // draw game first
        /* raylib.BeginTextureMode(target); // old
        flush_draws_scale(&s)
        raylib.EndTextureMode();
        raylib.BeginDrawing()
        raylib.BeginShaderMode(shader);
        raylib.DrawTextureRec(target.texture, raylib.Rectangle{0, 0, SCREEN_WIDTH, -SCREEN_HEIGHT}, raylib.Vector2{0, 0}, raylib.WHITE);
        raylib.EndShaderMode(); */
        // fancy, new drawing
        // world was queued earlier by draw_game (Terrain / Effects / Objects)
        update_water_uniforms(&s)

        // draw game first
        raylib.BeginTextureMode(target)
        raylib.ClearBackground(raylib.BLACK)
        flush_layer(&s, .Terrain)
        flush_layer(&s, .Effects)
        flush_layer(&s, .Objects)
        raylib.EndTextureMode()

        raylib.BeginDrawing()
        // no BeginShaderMode here anymore; the water shader runs per tile inside flush_layer
        raylib.DrawTextureRec(target.texture, raylib.Rectangle{0, 0, SCREEN_WIDTH, -SCREEN_HEIGHT}, raylib.Vector2{0, 0}, raylib.WHITE)

        s.layer = .UI // everything queued from here goes to the screen pass
        if raylib.Vector2Distance(game.rect_pos(s.spref.body), s.move_to) > 0.5 {
            draw_rect(&s, apply_camera(&s, s.move_to)+game.rect_size(s.spref.body)/2, raylib.Vector2{2,2});
        }
        // draw UI
        if s.debug {
            i: i32 = 0
            h: f32 = f32(len(s.logs) * 24 + 10 + 20)
            draw_rect_no_scale(&s, pos = {0, 0}, size = {SCREEN_WIDTH, h}, tint = {0, 0, 0, 123})
            for l in s.logs {
                draw_text_no_scale(
                    &s,
                    l,
                    pos = raylib.Vector2{10, f32(10 + 24 * i)},
                    size = 24,
                    font = f,
                )
                i += 1
            }
        }

        flush_layer(&s, .UI)
        s.layer = .Objects // so next frame's queuing doesn't start on .UI

        raylib.EndDrawing()

        i += 1
        if i % 60 == 0 {
            i = 0
            s.pings[ping_id] = time.now()
            b := game.init_send_message()
            game.pack_client_message(&b, {kind=.PING, data=game.PingMsg{user_id=ID, id=u32(ping_id)}});
            err := game.send_message(s.socket, s.server_endpoint, &b)
            if err != .None {
                fmt.println(err)
                panic("Err in ping")
            }
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
}
