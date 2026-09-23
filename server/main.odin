// server.odin
package main

import "core:sys/posix"
import "core:math/rand"
import "core:math"
import "core:sync"
import "core:time"
import "core:thread"
import "core:net"
import "core:fmt"
import "project:common/game"
import "project:common/buffer_io"
import "vendor:raylib"

MIN_ODIN :: "dev-2026-06"

when ODIN_VERSION < MIN_ODIN {
    // #panic("Requires odin dev-2026-06")
}

@private
Client :: struct {
    entity: game.Entity,
    energy: f32,
    max_energy: f32,
    max_health: f32,
    attack: f32,
    last_entity: game.Entity,
    endpoint: net.Endpoint,
    last_ping: time.Time,
    move_to: raylib.Vector2,
    move_origin: raylib.Vector2,
    facing: raylib.Vector2,
    abilities: [ABILITIES_COUNT]game.EntityAbility,

    // connection state
    no_send: bool,
}
PROJECTILES_COUNT :: 1024
ABILITIES_COUNT :: game.ABILITIES_COUNT
Ability :: struct {
    kind: game.AbilityKind,
    action: AbilityProc,
}
error :: distinct struct { error: string, ok: bool };
AbilityProc :: distinct proc(g: ^Game, c: ^Client, id, level: u32, target: raylib.Vector2) -> error;

@private
Game :: struct {
    abilities: map[u32]Ability,
    entities: map[game.EntityHandle]Client,
    projectiles: [PROJECTILES_COUNT]game.Projectile, // server_side_projectiles
    projectiles_count: u32,

    // projectile spawn/remove events accumulated since the last time a
    // tick's GameData was built; drained (and cleared) every tick.
    event_lock: sync.Mutex,
    loop_events: [dynamic]game.ProjectileEvent,

    entities_lock: sync.Mutex,
    socket: net.UDP_Socket,
    assets: game.AssetManger,
    gmap: game.Map,
}

game_add_projectile_event :: proc(g: ^Game, ev: game.ProjectileEvent) {
    sync.lock(&g.event_lock)
    append(&g.loop_events, ev)
    sync.unlock(&g.event_lock)
}

game_init :: proc() -> Game {
    g := Game{}
    g.assets = game.load_assets("imgs.json");
    g.gmap = game.new_map();
    game.generate_chunck(&g.gmap, 0,0);
    g.entities = make(map[game.EntityHandle]Client);
    g.abilities = make(map[u32]Ability);
    g.loop_events = make([dynamic]game.ProjectileEvent);
    g.abilities[1] = Ability{
        action=proc(g: ^Game, c: ^Client, id, level: u32, target:raylib.Vector2) -> error {
            assert(c.entity.id != 0)
            origin := game.rect_pos(c.entity.body) + 0.5* game.rect_size(c.entity.body);
            p := game.Projectile {
                owner=c.entity.id,
                origin=origin,
                position=origin,
                speed=100,
                range=200,
                direction=target,
            };
            game_spawn_projectile(g, p)
            return {"", true }
        },
    };
    return g;
}

global_projectile_id: u32 = 0
game_spawn_projectile :: proc(g: ^Game, _p: game.Projectile) {
    p := _p
    p.id = global_projectile_id
    global_projectile_id += 1
    p.active = true

    sync.mutex_lock(&g.entities_lock)
    g.projectiles[g.projectiles_count] = p
    g.projectiles_count += 1
    sync.mutex_unlock(&g.entities_lock)

    game_add_projectile_event(g, game.ProjectileEvent{
        kind = .SPAWN_PROJECTILE,
        data = game.SpawnProjectileMsg{projectile = p},
    })
}

init_server_socket :: proc(g: ^Game) {
    s, _ := game.init_udp_socket(port=8081);
    g.socket = s;
}

// ---------------------------------------------------------------------
// Incoming messages from clients
// ---------------------------------------------------------------------

handle_user_msg :: proc(g: ^Game, buf: ^buffer_io.Buffer, endpoint: net.Endpoint) {
    msg := game.unpack_server_message(buf)

    switch msg.kind {
    case .CONNECT:
        d := msg.data.(game.ConnectMsg)
        id := d.user_id
        fmt.println("Connect");
        fmt.printfln("\taccess token: %d", id);

        sync.mutex_lock(&g.entities_lock);
        c := Client{}
        c.endpoint = endpoint;
        c.max_health = 100
        c.attack = 15
        t := u32(rand.int31()%i32(len(g.assets.assets)));
        c.entity = game.Entity{
            texture=t,
            health=c.max_health,
            body= raylib.Rectangle{0,0,32,32},
            id=id,
        };
        c.last_entity = c.entity
        c.move_to = raylib.Vector2{0,0}
        c.move_origin = raylib.Vector2{0,0}
        c.last_ping = time.now();
        c.abilities[0].active = true;
        c.abilities[0].ability_id = 1;
        c.abilities[0].level = 1;
        c.no_send = true;
        g.entities[game.EntityHandle(id)] = c;
        sync.mutex_unlock(&g.entities_lock);

        // Full sync: every entity's full state plus every currently
        // active projectile, so a freshly-connected client always
        // starts from a complete, consistent snapshot.
        data := build_game_data(g, full_sync = true)
        data.user_data = build_user_data(c)

        b := game.init_send_message()
        game.pack_server_message(&b, game.Msg{kind = .GAME_DATA, data = data})
        game.send_message(g.socket, endpoint, &b)
        free_all(context.temp_allocator)

    case .START_GAME:
        d := msg.data.(game.StartGameMsg)
        id := d.user_id;
        sync.lock(&g.entities_lock);
        c, ok := g.entities[id];
        assert(ok);
        c.no_send = false;
        g.entities[id] = c;
        sync.unlock(&g.entities_lock);
        fmt.println("Starting game for:", id);

    case .PING:
        d := msg.data.(game.PingMsg)
        id := d.user_id
        ping_id := d.id

        sync.mutex_lock(&g.entities_lock);
        last, uok := g.entities[game.EntityHandle(id)];
        if !uok {
            fmt.println(id);
            panic("User doesn't exist");
        }
        last.last_ping = time.now();
        g.entities[game.EntityHandle(id)] = last;
        sync.mutex_unlock(&g.entities_lock);

        b := game.init_send_message()
        game.pack_server_message(&b, game.Msg{
            kind = .PING_RESPOND,
            data = game.PingRespondMsg{id = ping_id},
        })
        game.send_message(g.socket, endpoint, &b);

    case .USER_MSG:
        d := msg.data.(game.UserMsg)
        id := d.user_id

        switch v in d.data {
        case game.MoveMsg:
            sync.lock(&g.entities_lock);
            last, eok := g.entities[id]
            assert(eok);
            last.move_to.x = v.pos.x
            last.move_to.y = v.pos.y
            last.move_origin.x = last.entity.body.x
            last.move_origin.y = last.entity.body.y
            g.entities[id] = last;
            sync.unlock(&g.entities_lock);

        case game.AbilityMsg:
            cast_ability(g, id, v.user_ability_index, v.direction);

        case game.DirectionMsg:
            sync.lock(&g.entities_lock);
            last, eok := g.entities[id]
            assert(eok);
            last.facing = v.direction;
            g.entities[id] = last;
            sync.unlock(&g.entities_lock);
        }

    case .GET_STATE:
        // no payload / not currently used

    case .Invalid, .GAME_DATA, .GAME_MSG, .PING_RESPOND:
        panic("Server received an invalid or server-only message")
    }
}

gpid :u32= 0
add_projectile :: proc(g: ^Game, i: game.Projectile) {
    p := i
    sync.lock(&g.entities_lock);
    defer sync.unlock(&g.entities_lock);
    assert(g.projectiles_count < PROJECTILES_COUNT);
    p.active = true
    p.id = gpid
    gpid += 1;
    g.projectiles[g.projectiles_count] = p
    g.projectiles_count += 1;
}

cast_ability :: proc(g: ^Game, id: u32, index: u8, target: raylib.Vector2) {
    if index >= ABILITIES_COUNT {
        fmt.panicf("Ability index out of range: %d of %d.\n", index, ABILITIES_COUNT)
    }
    sync.lock(&g.entities_lock)
    e, ok := g.entities[id];
    if !ok {
        fmt.println("entity:", id);
        panic("Failed to get entity from game.")
    }
    sync.unlock(&g.entities_lock)
    user_ability := e.abilities[index]
    if ! user_ability.active {
        fmt.println("Ability", index, "is inactive.");
        return
    }
    ability_id := user_ability.ability_id;
    ability, aok := g.abilities[ability_id]; assert(aok);
    ability.action(g, &e, ability_id, user_ability.level, target)
}

// ---------------------------------------------------------------------
// GameData construction (used for both per-tick sends and the CONNECT
// full-sync send)
// ---------------------------------------------------------------------

build_user_data :: proc(c: Client) -> game.UserData {
    u := game.UserData{}
    u.energy = c.energy
    for i in 0 ..< ABILITIES_COUNT {
        a := c.abilities[i]
        u.abilities[i].active     = 1 if a.active else 0
        u.abilities[i].ability_id = a.ability_id
        u.abilities[i].level      = a.level
        u.abilities[i].cooldown   = a.cooldown
    }
    u.move_to = c.move_to
    return u
}

// Allocates its result slices with context.temp_allocator - callers
// must free_all(context.temp_allocator) once they're done sending it.
build_game_data :: proc(g: ^Game, full_sync: bool) -> game.GameData {
    data := game.GameData{full_sync = full_sync}

    sync.mutex_lock(&g.entities_lock)
    entities := make([dynamic]game.EntityUpdate, 0, len(g.entities), context.temp_allocator)
    for k, e in g.entities {
        delta := game.get_entity_delta(e.last_entity, e.entity, all = full_sync)
        append(&entities, game.EntityUpdate{id = u32(k), delta = delta})
    }

    if full_sync {
        full := make([]game.Projectile, g.projectiles_count, context.temp_allocator)
        copy(full, g.projectiles[:g.projectiles_count])
        data.full_projectiles = full
    }
    sync.mutex_unlock(&g.entities_lock)
    data.entities = entities[:]

    if !full_sync {
        sync.lock(&g.event_lock)
        events := make([]game.ProjectileEvent, len(g.loop_events), context.temp_allocator)
        copy(events, g.loop_events[:])
        clear(&g.loop_events)
        sync.unlock(&g.event_lock)
        data.projectile_events = events
    }

    return data
}

// ---------------------------------------------------------------------
// Simulation
// ---------------------------------------------------------------------

handle_receiver_loop :: proc(g: ^Game) {
    buf := buffer_io.buffer_make(1024);
    for {
        n, endpoint, err := net.recv_udp(g.socket, buf.data[:]);
        if err != .None {
            fmt.println(err)
            panic("recevied error");
        }
        if n == 0 {
            panic("Received 0 bytes?");
        }
        buf.len = n;
        handle_user_msg(g, &buf, endpoint);
        free_all(context.temp_allocator)
        buffer_io.buffer_reset(&buf);
    }
}

update_client :: proc(g: ^Game, c: ^Client, dt: f32) {
    last_current_entity := c.entity;
    current_pos := game.rect_pos(c.entity.body)
    d := raylib.Vector2Normalize(c.move_to - current_pos)
    assert(raylib.Vector2Length(d) <= 1.01)
    mag := game.ENTITY_SPEED * dt
    next_pos := current_pos + d * mag

    reached := raylib.Vector2Distance(current_pos, c.move_to) <=
               raylib.Vector2Distance(current_pos, next_pos)

    target := c.move_to if reached else next_pos

    c.entity.body.x = target.x
    c.entity.body.y = target.y
    i := 0
    for i < 3 { // 3 iterations because collision checks one wall at a time,
                // so if the entity's colliding against two perpendiculat walls,
                // only one's checked at a time
        if  v, ok := game.check_entity_map_collisions(&g.gmap, c.entity); ok {
            dist := raylib.Vector2Distance(current_pos, v) < 0.25
            if  dist {
                c.move_to = v;
            }
            c.entity.body.x = v.x
            c.entity.body.y = v.y
        } else {
            break
        }
        i+=1
    }
    if i == 3 {
        panic("Had to check 3 times for collisions");
    }
    c.last_entity = last_current_entity
    if c.entity.body.width <= 1 || c.entity.body.height <= 1 {
        fmt.println(c)
        panic("body size too small");
    }
}

MAX_TIMEOUT :: 10 * time.Second

snapshot_entry :: struct {
    k: game.EntityHandle,
    using c: Client,
}

p_in_rect :: proc(r: raylib.Rectangle, p: raylib.Vector2) -> bool {
    if p.x >= r.x && p.x <= r.x+r.width {
        if p.y >= r.y && p.y <= r.y+r.height { return true }
    }
    return false
}

// Returns the projectile's (possibly updated) state and whether it
// should be removed. When remove is true, the returned projectile's
// `id` is still valid - callers need it to emit a REMOVE_PROJECTILE
// event.
update_projectile :: proc(g: ^Game, last_p: game.Projectile, dt: f32) -> (game.Projectile, bool) {
    p := last_p
    pspeed := last_p.speed
    prev_pos := last_p.position
    new_pos := prev_pos + raylib.Vector2Normalize(last_p.direction) * pspeed * dt
    p.position = new_pos

    for _, e in g.entities {
        if e.entity.id == last_p.owner {
            continue
        }
        if p_in_rect(e.entity.body, p.position) {
            return p, true // hit
        }
    }

    if game.check_point_map_collisions(&g.gmap, p.position) {
        
        return p, true // hit wall
    }

    if raylib.Vector2Distance(p.position, last_p.origin) > p.range {
        return p, true // out of range
    }
    return p, false
}

update_game :: proc(g: ^Game, dt: f32) {
    sync.mutex_lock(&g.entities_lock);
    for k, e in g.entities {
        c := e;
        update_client(g, &c, dt);
        g.entities[k] = c;
    }

    i := u32(0)
    for i < g.projectiles_count {
        p := g.projectiles[i]
        np, remove := update_projectile(g, p, dt)

        if remove {
            game_add_projectile_event(g, game.ProjectileEvent{
                kind = .REMOVE_PROJECTILE,
                data = game.RemoveProjectileMsg{projectile_id = np.id},
            })

            last := g.projectiles_count - 1
            g.projectiles[i] = g.projectiles[last]
            g.projectiles_count -= 1
            // don't increment i - the projectile swapped into this slot
            // still needs to be processed
            continue
        }

        g.projectiles[i] = np
        i += 1
    }
    sync.mutex_unlock(&g.entities_lock);
}

send_game_data :: proc(
    g: ^Game,
    endpoints: ^[dynamic]snapshot_entry,
    to_remove: ^[dynamic]game.EntityHandle,
) {
    shared := build_game_data(g, full_sync = false)

    sync.lock(&g.entities_lock);
    for k, e in g.entities {
        append(endpoints, snapshot_entry{k, e})
    }
    sync.unlock(&g.entities_lock);

    last := time.now()
    for k in endpoints {
        if k.no_send {
            continue;
        }

        elapsed := math.abs(time.diff(last, k.last_ping));
        if elapsed > MAX_TIMEOUT {
            append(to_remove, k.k)
            continue
        }

        data := shared
        data.user_data = build_user_data(k.c)

        b := game.init_send_message()
        game.pack_server_message(&b, game.Msg{kind = .GAME_DATA, data = data})

        err := game.send_message(g.socket, k.endpoint, &b)
        if err != .None {
            panic("err in sending to client");
        }
    }

    if len(to_remove) > 0 {
        sync.mutex_lock(&g.entities_lock);
        for k in to_remove {
            fmt.println("Removing:", k, "from", len(g.entities), "entities");
            delete_key(&g.entities,k);
        }
        clear_dynamic_array(to_remove);
        sync.mutex_unlock(&g.entities_lock);
    }
    clear_dynamic_array(endpoints)
}

// server tick: [simulate] -> every 3rd tick, [send GameData to everyone]
handle_sender_loop :: proc(g: ^Game) {
    duration := time.Duration(10) * time.Millisecond
    to_remove := make([dynamic]game.EntityHandle);
    endpoints := make([dynamic]snapshot_entry);
    dt : f32 = 0;
    i := 0;
    for {
        start := time.now()
        update_game(g, dt)
        if i < 3 {
            i+=1
        } else {
            i = 0
            send_game_data(g, &endpoints, &to_remove)
        }
        free_all(context.temp_allocator)

        elapsed := time.since(start)
        if elapsed < duration {
            time.sleep(duration - elapsed)
        }
        dt_elapsed := time.since(start)
        dt = f32(dt_elapsed)/f32(time.Second)
    }
}

thread_receiver_fn :: proc(data: rawptr) {
    handle_receiver_loop(transmute(^Game)data);
}
thread_sender_fn :: proc(data: rawptr) {
    handle_sender_loop(transmute(^Game)data);
}

import "core:sys/windows"
main :: proc() {
    g := game_init()
    init_server_socket(&g)
    when ODIN_OS == .Windows {
        SIO_UDP_CONNRESET :: 0x9800000C
        bNewBehavior: windows.BOOL = false
        bytesReturned: u32
        if windows.WSAIoctl(cast(windows.SOCKET)g.socket, windows.SIO_UDP_CONNRESET,
            &bNewBehavior,
            size_of(bNewBehavior),
            nil, 0, &bytesReturned,
            nil,
            nil) != 0 {
            panic("Failed to set SIO_UDP_CONNRESET for windows socket");
        }
        fmt.println("Running on Windows.")
    } else when ODIN_OS == .Linux {
        fmt.println("Running on Linux.")
    } else {
        fmt.panicf("Running on an unsupported/unidentified OS.\n")
    }
    t_receiver := thread.create_and_start_with_data(data=&g, fn=thread_receiver_fn);
    t_sender := thread.create_and_start_with_data(data=&g, fn=thread_sender_fn);

    thread.join(t_receiver)
    thread.join(t_sender)
    delete(g.assets.assets);
    delete(g.entities);
    net.close(g.socket)
}
