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



@private
Client :: struct {
    entity: game.Entity,
    endpoint: net.Endpoint,
    last_ping: time.Time,
}
@private
Game :: struct {
    entities: map[game.EntityHandle]Client,
    entities_lock: sync.Mutex,
    socket: net.UDP_Socket,
    assets: game.AssetManger
}

game_init :: proc() -> Game {
    g := Game{}
    g.entities = make(map[game.EntityHandle]Client);
    g.assets = game.load_assets("imgs.json");
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
        t := u32(rand.int31()%i32(len(g.assets.assets)));
        fmt.println(t, len(g.assets.assets));
        c.entity = game.Entity{
            texture=t,
            body= raylib.Rectangle{0,0,100,100}
        };
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
        n := game_pack_all(g, &b);
        nn, e := net.send_udp(g.socket, b.data[:n], endpoint);
        if e != .None{
            panic("Failed to send state to client?");
        }
        buffer_io.buffer_destroy(&b);
    } else if msg == networking.MSG_PING {
        fmt.print("ping ");
        id, ok := buffer_io.buffer_read_u32(buf);
        if !ok {
            panic("Failed to read u32, user id for connect");
        }
        ping_id, pok := buffer_io.buffer_read_u32(buf);
        if !pok {
            panic("Failed to read u32, ping id for connect");
        }
        
        fmt.println("from", id, "pinng id", ping_id);

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
        id, ok := buffer_io.buffer_read_u32(buf);
        if !ok {
            panic("Failed to read u32, user id for connect");
        }
        delta := game.EntityDelta{};
       game.unpack_entity(buf, &delta);
        sync.mutex_lock(&g.entities_lock);
        last, lok := g.entities[game.EntityHandle(id)];
        if !lok {
            fmt.println(id)
            panic("entity doesn't exist");
        }
        last.entity.body = delta.body;
        last.last_ping = time.now();
        g.entities[game.EntityHandle(id)] = last;
        sync.mutex_unlock(&g.entities_lock);
    } else {
        panic("unknown message");
    }
}
game_pack_all :: proc(g: ^Game, buf: ^buffer_io.Buffer) -> int {
    buffer_io.buffer_reset(buf);
    buffer_io.buffer_write_u32(buf, u32(len(g.entities)));
    sync.mutex_lock(&g.entities_lock);
    for k, e in g.entities {
        delta := game.EntityDelta{};
        delta.body = e.entity.body;
        delta.status = e.entity.status;
        delta.texture = e.entity.texture;
        buffer_io.buffer_write_u32(buf, u32(k));
        game.pack_entity(buf, &delta);
    }
    sync.mutex_unlock(&g.entities_lock);
    return buf.len;
}
handle_receiver_loop :: proc(g: ^Game, n: int) {
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
        delta := game.EntityDelta{status=e.entity.status, body=e.entity.body,texture=e.entity.texture};
        game.pack_entity(buf, &delta);
    }
}
MAX_TIMEOUT :: 10
handle_sender_loop :: proc(g: ^Game, n: int) {
    duration := time.Duration(n) * time.Millisecond
    buf := buffer_io.buffer_make(1024);
    to_remove := make([dynamic]game.EntityHandle);
    snapshot_entry :: struct {
        endpoint:net.Endpoint,
        k: game.EntityHandle,
        last_ping:time.Time,
    }
    endpoints := make([dynamic]snapshot_entry);
    for {
        start := time.now()
        // for ping

        buffer_io.buffer_write_u8(&buf, networking.MSG_GAME_DATA);
        sync.mutex_lock(&g.entities_lock);
        pack_game_loop_data(g, &buf);
        for k, e in g.entities {
            append(&endpoints, snapshot_entry{e.endpoint,k,e.last_ping})
        }
        sync.mutex_unlock(&g.entities_lock);
        last := time.now()
        for k in endpoints {
            elapsed := math.abs(time.diff(last, k.last_ping));
             if elapsed > MAX_TIMEOUT *time.Second {
                 append(&to_remove, k.k)
             } else {
                 sn, err := net.send_udp(g.socket, buf.data[:buf.len], k.endpoint);
                 if err != .None {
                     panic("err in sending to client");
                 }
                 if sn != buf.len {
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

        elapsed := time.since(start)
        if elapsed < duration {
            // inacurate on wls, sometimes jumps to 2.9 seconds wait
            time.sleep(duration - elapsed)
        }
    }
}

thread_receiver_fn :: proc(data: rawptr) {
    handle_receiver_loop(transmute(^Game)data, 20);
}
thread_sender_fn :: proc(data: rawptr) {
    handle_sender_loop(transmute(^Game)data, 20);
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
