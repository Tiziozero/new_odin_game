package main

import "core:math/rand"
import "core:sync"
import "core:math"
import "core:strings"
import "vendor:raylib"
import "core:net"
import "core:fmt"
import "project:common/game"
import "project:common/networking"
import "project:common/buffer_io"
MIN_ODIN :: "dev-2026-06"

when ODIN_VERSION < MIN_ODIN {
    #panic("Requires odin dev-2026-06")
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
    move_origin:raylib.Vector2,
    abilities: [ABILITIES_COUNT]game.EntityAbility,
    projectiles: [dynamic]game.Projectile,
}


ABILITIES_COUNT ::  game.ABILITIES_COUNT
Ability :: struct {
    kind: game.AbilityKind,
    action: proc(level: int)
}
@private
Game :: struct {
    abilities: map[int]Ability,
    entities: map[game.EntityHandle]Client,
    entities_lock: sync.Mutex,
    socket: net.UDP_Socket,
    assets: game.AssetManger,
    gmap: game.Map,
}

game_init :: proc() -> Game {
    g := Game{}
    g.assets = game.load_assets("imgs.json");
    g.gmap = game.new_map();
    game.generate_chunck(&g.gmap, 0,0);
    g.entities = make(map[game.EntityHandle]Client);
    return g;
}

init_server_socket :: proc(g: ^Game) {
    s, _ := networking.init_udp_socket(port=8081);
    g.socket = s;
}
game_handle_msg :: proc(g: ^Game, buf: ^buffer_io.Buffer) {
}
import "core:time"
import "core:thread"

handle_user_msg :: proc(g: ^Game, buf: ^buffer_io.Buffer, endpoint: net.Endpoint) {
    msg, ok := buffer_io.buffer_read_u8(buf);
    if !ok {
        panic("failed to read u8 from user msg buffer");
    }
    if msg == networking.MSG_CONNECT {
        fmt.println("Connect");
        id, ok := buffer_io.buffer_read_u32(buf);
        if !ok {
            panic("Failed to read u32, user id for connect");
        }
        fmt.printfln("\taccess token: %d", id);
        sync.mutex_lock(&g.entities_lock);
        c := Client{}
        c.endpoint = endpoint;
        c.max_health = 100
        c.attack = 15
        t := u32(rand.int31()%i32(len(g.assets.assets)));
        // fmt.println(t, len(g.assets.assets));
        c.entity = game.Entity{
            texture=t,
            health=c.max_health,
            body= raylib.Rectangle{0,0,32,32}
        };
        c.move_to = raylib.Vector2{0,0}
        c.move_origin = raylib.Vector2{0,0}
        c.last_ping = time.now();
        g.entities[game.EntityHandle(id)] = c;
        sync.mutex_unlock(&g.entities_lock);
        // send ok
        buffer_io.buffer_reset(buf);
        b := strings.builder_make()
        fmt.sbprint(&b, "ack");
        nn, e := net.send_udp(g.socket, b.buf[:], endpoint);
        strings.builder_destroy(&b)
    } else if msg == networking.MSG_GET_STATE {
        b := buffer_io.buffer_make(1024);
        sync.lock(&g.entities_lock)
        for k, c in g.entities {
            fmt.println(c.entity.id, c.entity.body)
        }
        sync.unlock(&g.entities_lock)
        n := game_pack_all(g, &b, all = true);
        nn, e := net.send_udp(g.socket, b.data[:n], endpoint);
        if e != .None{
            panic("Failed to send state to client?");
        }
        buffer_io.buffer_destroy(&b);
    } else if msg == networking.MSG_PING {
        // fmt.print("ping ");
        id, ok := buffer_io.buffer_read_u32(buf);
        if !ok {
            panic("Failed to read u32, user id for connect");
        }
        ping_id, pok := buffer_io.buffer_read_u32(buf);
        if !pok {
            panic("Failed to read u32, ping id for connect");
        }
        
        // fmt.println("from", id, "pinng id", ping_id);

        // update last ping
        sync.mutex_lock(&g.entities_lock);
        last, uok := g.entities[game.EntityHandle(id)];
        if !uok {
            fmt.println(id);
            panic("User doesn't exist");
        }
        last.last_ping = time.now();
        g.entities[game.EntityHandle(id)] = last;
        sync.mutex_unlock(&g.entities_lock);

        // write confirmation
        b := buffer_io.buffer_make(64);
        buffer_io.buffer_write_u8(&b, networking.MSG_PING_RESPOND);
        buffer_io.buffer_write_u32(&b, ping_id);
        net.send_udp(g.socket, b.data[:b.len], endpoint);
        buffer_io.buffer_destroy(&b);
    } else if msg == networking.MSG_USER_DATA {
        panic("no");
    } else if msg == networking.MSG_USER_MSG {
        id, ok := buffer_io.buffer_read_u32(buf);
        assert(ok);
        kind, kok := buffer_io.buffer_read_u8(buf);
        assert(kok);
        switch kind {
            case game.USR_MSG_MOVE: {
                new_x, new_y: f32;
                new_x, ok = buffer_io.buffer_read_f32(buf);
                assert(ok);
                new_y, ok = buffer_io.buffer_read_f32(buf);
                assert(ok);
                sync.lock(&g.entities_lock);
                last, eok := g.entities[id]
                assert(eok);
                last.move_to.x = new_x
                last.move_to.y = new_y
                last.move_origin.x = last.entity.body.x
                last.move_origin.y = last.entity.body.y
                g.entities[id] = last;
                sync.unlock(&g.entities_lock);
            }
            case game.USR_MSG_ABILITY: {
                index, ok := buffer_io.buffer_read_u8(buf);
                fmt.println("Ability cast:", index)
                cast_ability(g, id, index);
            }
        case: panic("Handle case");
        }
    } else {
        panic("unknown message");
    }
}
cast_ability :: proc(g: ^Game, id: u32, index: u8) {
    assert(index < ABILITIES_COUNT);
    sync.lock(&g.entities_lock)
    e, ok := g.entities[id]; assert(ok);
    sync.unlock(&g.entities_lock)
    ability := e.abilities[index]
    if ! ability.active {
        fmt.println("Ability", index, "is inactive.");
        return
    }
}
game_pack_all :: proc(g: ^Game, buf: ^buffer_io.Buffer, all := false) -> int {
    buffer_io.buffer_reset(buf);
    buffer_io.buffer_write_u32(buf, u32(len(g.entities)));
    sync.mutex_lock(&g.entities_lock);
    for k, e in g.entities {
        delta := game.get_entity_delta(e.last_entity, e.entity, all = all);
        if delta.delta > 0 {
            fmt.println("Delta:", delta);
        }
        buffer_io.buffer_write_u32(buf, u32(k));
        game.pack_entity(buf, &delta);
    }
    sync.mutex_unlock(&g.entities_lock);
    return buf.len;
}
handle_receiver_loop :: proc(g: ^Game) {
    buf := buffer_io.buffer_make(1024);
    for {
        n, endpoint, err := net.recv_udp(g.socket, buf.data[:]);
        if err != .None {
            if err == .Connection_Refused {
            }
            fmt.println(err)
            panic("recevied error");
        }
        buf.len = n;
        handle_user_msg(g, &buf, endpoint);
        buffer_io.buffer_reset(&buf);
    }
}
pack_game_loop_data :: proc(g: ^Game, buf: ^buffer_io.Buffer) {
    buffer_io.buffer_write_u32(buf, u32(len(g.entities)));
    for k, e in g.entities {
        buffer_io.buffer_write_u32(buf, u32(k));
        delta := game.get_entity_delta(e.last_entity, e.entity);
        game.pack_entity(buf, &delta);
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
            // v is new pos AFTER collision.
            // if the distance moved AFTER COLLISSION is less than a threashold,
            // then move was irrelevant/entity's stuck or can't move further,
            // so stop moving
            dist := raylib.Vector2Distance(current_pos, v) < 0.25
            fmt.println("Collision", dist);
            if  dist {
                fmt.println("same: ", current_pos, v)
                c.move_to = v;
            }

            c.entity.body.x = v.x
            c.entity.body.y = v.y
            // c.move_to = game.rect_pos(c.entity.body)
        } else {
            break
        }
        i+=1
    }
    // check for 2 walls.if there's a third collision the it's likely the
    // entity's bugged
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
// straight garbage basically. stress test, if you will
pack_user_specific_data :: proc(c: snapshot_entry, buf: ^buffer_io.Buffer) {
    buffer_io.buffer_write_f32(buf, c.energy)
    for i in 0..<ABILITIES_COUNT {
        buffer_io.buffer_write_u32(buf, c.abilities[i].ability_id)
        buffer_io.buffer_write_u32(buf, c.abilities[i].level)
        buffer_io.buffer_write_f32(buf, c.abilities[i].cooldown)
    }
    buffer_io.buffer_write_f32(buf, c.move_to.x)
    buffer_io.buffer_write_f32(buf, c.move_to.y)
    
}

snapshot_entry :: struct {
    k: game.EntityHandle,
    using c: Client,
}
// user message:
// [user specific data][game data]
handle_sender_loop :: proc(g: ^Game) {
    duration := time.Duration(10) * time.Millisecond
    buf := buffer_io.buffer_make(1024); // make once
    to_remove := make([dynamic]game.EntityHandle);
    endpoints := make([dynamic]snapshot_entry);
    dt : f32 = 0;
    user_buf := buffer_io.buffer_make(1024) // make once
    i := 0;
    for {
        start := time.now()
        sync.mutex_lock(&g.entities_lock);
        for k, e in g.entities {
            c := e;
            update_client(g, &c, dt);
            g.entities[k] = c;
        }
        sync.mutex_unlock(&g.entities_lock);
        // send data once every 3 updates
        if i < 3 {
            i+=1
        } else {
            i = 0
            //  write in loop before user specific data
            // buffer_io.buffer_write_u8(&buf, networking.MSG_GAME_DATA);
            sync.mutex_lock(&g.entities_lock);
            pack_game_loop_data(g, &buf);
            for k, e in g.entities {
                append(&endpoints, snapshot_entry{k,e})
            }
            sync.mutex_unlock(&g.entities_lock);
            last := time.now()
            for k in endpoints {
                elapsed := math.abs(time.diff(last, k.last_ping));
                         if elapsed > MAX_TIMEOUT {
                             append(&to_remove, k.k)
                         } else {
                             buffer_io.buffer_reset(&user_buf)
                             buffer_io.buffer_write_u8(&user_buf, networking.MSG_GAME_DATA);
                             pack_user_specific_data(k, &user_buf)
                             // only write to buf.len, which is bytes of relevant data
                             wrote, ok := buffer_io.buffer_write_bytes(&user_buf, buf.data[:buf.len])
                             if ! ok {
                                 fmt.println(user_buf.len, user_buf.cap, len(user_buf.data))
                                 fmt.println(buf.len, buf.cap, len(buf.data))
                             }
                             assert(ok);
                             assert(wrote == buf.len)
                             sn, err := net.send_udp(g.socket, user_buf.data[:user_buf.len], k.endpoint);
                             if err != .None {
                                 panic("err in sending to client");
                             }
                             if sn != user_buf.len {
                                 panic("Didn't send all bytes");
                             }
                         }
                     }
                     if len(to_remove) > 0 {
                         sync.mutex_lock(&g.entities_lock);
                         for k in to_remove {
                             fmt.println("Removing:", k, "from", len(g.entities), "entities");
                             delete_key(&g.entities,k);
                         }
                         clear_dynamic_array(&to_remove);
                         sync.mutex_unlock(&g.entities_lock);
                     }
                     // clear
                     buffer_io.buffer_reset(&buf);
                     clear_dynamic_array(&endpoints)

        }
        elapsed := time.since(start)
        if elapsed < duration {
            // inacurate on wls, sometimes jumps to 2.9 seconds wait
            time.sleep(duration - elapsed)
        }
        dt_elapsed := time.since(start) // with sleep
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
    // disable "ICMP"
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
        fmt.println("Running on an unsupported/unidentified OS.")
    }
    t_receiver := thread.create_and_start_with_data(data=&g, fn=thread_receiver_fn);
    t_sender := thread.create_and_start_with_data(data=&g, fn=thread_sender_fn);


    thread.join(t_receiver)
    thread.join(t_sender)
    delete(g.assets.assets);
    delete(g.entities);
    net.close(g.socket)
}
