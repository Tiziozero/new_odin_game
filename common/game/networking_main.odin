// common/game/message.odin
package game

import "vendor:raylib"
import "core:fmt"
import "core:net"
import "project:common/buffer_io"

MsgKind :: enum u8 {
    Invalid,
    CONNECT,
    START_GAME,
    GET_STATE,
    PING,
    PING_RESPOND,
    GAME_DATA,
    GAME_MSG,
    USER_MSG,
}

UserMsgKind :: enum u8 {
    MOVE,
    ABILITY,
    DIRECTION,
}

GameMsgKind :: enum u8 {
    SPAWN_PROJECTILE,
    REMOVE_PROJECTILE,
}

// ---------------------------------------------------------------------
// Per-kind payloads. Msg.data is a union of these, so a Msg only ever
// carries the bytes for whichever kind it actually is, instead of every
// field for every kind at once (which is what the old flat struct did).
// ---------------------------------------------------------------------

ConnectMsg :: struct {
    user_id: u32,
}

StartGameMsg :: struct {
    user_id: u32,
}

GetStateMsg :: struct {}

PingMsg :: struct {
    user_id: u32,
    id:      u32,
}

PingRespondMsg :: struct {
    id: u32,
}

MoveMsg :: struct {
    pos: raylib.Vector2,
}

AbilityMsg :: struct {
    user_ability_index: u8,
    direction:          raylib.Vector2,
}

DirectionMsg :: struct {
    direction: raylib.Vector2,
}

UserMsg :: struct {
    user_id: u32,
    kind:    UserMsgKind,
    data: union {
        MoveMsg,
        AbilityMsg,
        DirectionMsg,
    },
}

SpawnProjectileMsg :: struct {
    projectile: Projectile,
}

RemoveProjectileMsg :: struct {
    projectile_id: u32,
}

GameMsg :: struct {
    kind: GameMsgKind,
    data: union {
        SpawnProjectileMsg,
        RemoveProjectileMsg,
    },
}

// One projectile-related thing that happened since the previous tick.
// GameData carries a list of these on every *normal* update instead of
// re-sending every projectile every time.
ProjectileEvent :: struct {
    kind: GameMsgKind, // .SPAWN_PROJECTILE or .REMOVE_PROJECTILE
    data: union {
        SpawnProjectileMsg,
        RemoveProjectileMsg,
    },
}

UserData :: struct {
    energy:    f32,
    abilities: [ABILITIES_COUNT]struct {
        active:     u8,
        ability_id: u32,
        level:      u32,
        cooldown:   f32,
    },
    move_to: raylib.Vector2,
}

EntityUpdate :: struct {
    id:    u32,
    delta: EntityDelta,
}

// GameData is the ONLY payload ever sent for MsgKind.GAME_DATA, and it
// always has the exact same shape on the wire - no more "sometimes the
// projectile section is there, sometimes it isn't". The one thing that
// varies is `full_sync`:
//
//   full_sync == false (the normal case, sent every tick):
//     - entities          delta-encoded changes since last tick
//     - projectile_events spawn/remove events since last tick
//                         (can legitimately be empty - that's a quiet
//                         tick, not a missing/corrupt field)
//     - full_projectiles  always empty
//
//   full_sync == true (sent once, right after CONNECT):
//     - entities          full state for every entity
//     - projectile_events always empty
//     - full_projectiles  every currently active projectile
GameData :: struct {
    user_data:         UserData,
    full_sync:         bool,
    entities:          []EntityUpdate,
    projectile_events: []ProjectileEvent,
    full_projectiles:  []Projectile,
}

Msg :: struct {
    kind: MsgKind,
    data: union {
        ConnectMsg,
        StartGameMsg,
        GetStateMsg,
        PingMsg,
        PingRespondMsg,
        GameData,
        GameMsg,
        UserMsg,
    },
}

// ADDR :: "172.31.138.162";
// SERVER_ENDPOINT :: "172.31.138.162:8081";
ADDR :: "127.0.0.1"
SERVER_ENDPOINT :: "127.0.0.1:8081"

init_udp_socket :: proc(port := 0) -> (net.UDP_Socket, net.Network_Error) {
    sock_addr := net.parse_address(ADDR, false)
    socket, err := net.make_bound_udp_socket(sock_addr, port)
    if err != net.Create_Socket_Error.None {
        fmt.println("Error in creating udp socket.", err)
        return {}, err
    }
    return socket, net.Create_Socket_Error.None
}

init_send_message :: proc() -> buffer_io.Buffer {
    return buffer_io.buffer_make(1024)
}

// send_message OWNS the buffer it's given: it sends, then destroys it.
// Callers must therefore pass a buffer they don't need afterward - never
// a long-lived/reused buffer (e.g. a receiver loop's recv buffer).
send_message :: proc(
    socket: net.UDP_Socket,
    endpoint: net.Endpoint,
    b: ^buffer_io.Buffer,
) -> net.UDP_Send_Error {
    written := buffer_io.buffer_written(b)
    if written == 0 {
        fmt.println("DATA:", b.data[:b.len])
        panic("attempted to send 0 bytes")
    }

    n, err := net.send(socket, b.data[:written], endpoint)
    assert(n == written)
    buffer_io.buffer_destroy(b)
    return err
}

// ---------------------------------------------------------------------
// Projectile "spawn data" - the fields needed to (re)create a projectile
// on the receiving end. Used both for a SPAWN_PROJECTILE event and for
// GameData.full_projectiles, so there's exactly one format for it.
// ---------------------------------------------------------------------

pack_projectile_spawn_data :: proc(buf: ^buffer_io.Buffer, p: Projectile) {
    buffer_io.buffer_write_u32(buf, p.id)
    buffer_io.buffer_write_u32(buf, p.projectile_id)
    buffer_io.buffer_write_u32(buf, p.owner)
    buffer_io.buffer_write_f32(buf, p.origin.x)
    buffer_io.buffer_write_f32(buf, p.origin.y)
    buffer_io.buffer_write_f32(buf, p.direction.x)
    buffer_io.buffer_write_f32(buf, p.direction.y)
    buffer_io.buffer_write_f32(buf, p.speed)
    buffer_io.buffer_write_f32(buf, p.range)
}

unpack_projectile_spawn_data :: proc(buf: ^buffer_io.Buffer) -> Projectile {
    p := Projectile{}
    ok := false
    p.id, ok = buffer_io.buffer_read_u32(buf);           assert(ok)
    p.projectile_id, ok = buffer_io.buffer_read_u32(buf); assert(ok)
    p.owner, ok = buffer_io.buffer_read_u32(buf);         assert(ok)
    p.origin.x, ok = buffer_io.buffer_read_f32(buf);      assert(ok)
    p.origin.y, ok = buffer_io.buffer_read_f32(buf);      assert(ok)
    p.direction.x, ok = buffer_io.buffer_read_f32(buf);   assert(ok)
    p.direction.y, ok = buffer_io.buffer_read_f32(buf);   assert(ok)
    p.speed, ok = buffer_io.buffer_read_f32(buf);         assert(ok)
    p.range, ok = buffer_io.buffer_read_f32(buf);         assert(ok)
    p.position = p.origin
    p.active = true
    return p
}

// ---------------------------------------------------------------------
// GameData pack/unpack - the single canonical path. The server's
// per-tick send and its post-CONNECT full-sync send both go through
// this, and so does the client's receive path. There is exactly one
// wire format now, not two.
// ---------------------------------------------------------------------

pack_user_data :: proc(buf: ^buffer_io.Buffer, u: UserData) {
    buffer_io.buffer_write_f32(buf, u.energy)
    for i in 0 ..< ABILITIES_COUNT {
        a := u.abilities[i]
        buffer_io.buffer_write_u8(buf, a.active)
        buffer_io.buffer_write_u32(buf, a.ability_id)
        buffer_io.buffer_write_u32(buf, a.level)
        buffer_io.buffer_write_f32(buf, a.cooldown)
    }
    buffer_io.buffer_write_f32(buf, u.move_to.x)
    buffer_io.buffer_write_f32(buf, u.move_to.y)
}

unpack_user_data :: proc(buf: ^buffer_io.Buffer) -> UserData {
    u := UserData{}
    ok := false
    u.energy, ok = buffer_io.buffer_read_f32(buf); assert(ok)
    for i in 0 ..< ABILITIES_COUNT {
        a := &u.abilities[i]
        a.active, ok = buffer_io.buffer_read_u8(buf);      assert(ok)
        a.ability_id, ok = buffer_io.buffer_read_u32(buf);  assert(ok)
        a.level, ok = buffer_io.buffer_read_u32(buf);       assert(ok)
        a.cooldown, ok = buffer_io.buffer_read_f32(buf);    assert(ok)
    }
    u.move_to.x, ok = buffer_io.buffer_read_f32(buf); assert(ok)
    u.move_to.y, ok = buffer_io.buffer_read_f32(buf); assert(ok)
    return u
}

pack_game_data :: proc(buf: ^buffer_io.Buffer, data: GameData) {
    pack_user_data(buf, data.user_data)

    full_sync_byte: u8 = 1 if data.full_sync else 0
    buffer_io.buffer_write_u8(buf, full_sync_byte)

    // entities - always present, same shape every time
    buffer_io.buffer_write_u32(buf, u32(len(data.entities)))
    for e in data.entities {
        buffer_io.buffer_write_u32(buf, e.id)
        delta := e.delta
        pack_entity(buf, &delta)
    }

    // projectile events - always present (possibly zero-length), even
    // on a full sync, so the reader never has to guess whether this
    // section exists
    buffer_io.buffer_write_u32(buf, u32(len(data.projectile_events)))
    for ev in data.projectile_events {
        buffer_io.buffer_write_u8(buf, u8(ev.kind))
        switch v in ev.data {
        case SpawnProjectileMsg:
            pack_projectile_spawn_data(buf, v.projectile)
        case RemoveProjectileMsg:
            buffer_io.buffer_write_u32(buf, v.projectile_id)
        }
    }

    // full projectile list - only meaningful when full_sync is set, but
    // the length prefix is always present so the format never branches
    buffer_io.buffer_write_u32(buf, u32(len(data.full_projectiles)))
    for p in data.full_projectiles {
        pack_projectile_spawn_data(buf, p)
    }
}

// Allocates its result slices with context.temp_allocator - callers
// should free_all(context.temp_allocator) once they're done consuming
// the returned GameData (typically right after applying it).
unpack_game_data :: proc(buf: ^buffer_io.Buffer) -> GameData {
    data := GameData{}
    ok := false

    data.user_data = unpack_user_data(buf)

    full_sync_byte: u8
    full_sync_byte, ok = buffer_io.buffer_read_u8(buf); assert(ok)
    data.full_sync = full_sync_byte != 0

    entity_count: u32
    entity_count, ok = buffer_io.buffer_read_u32(buf); assert(ok)
    entities := make([]EntityUpdate, entity_count, context.temp_allocator)
    for i in 0 ..< entity_count {
        id: u32
        id, ok = buffer_io.buffer_read_u32(buf); assert(ok)
        delta := EntityDelta{}
        unpack_entity(buf, &delta)
        entities[i] = EntityUpdate{id = id, delta = delta}
    }
    data.entities = entities

    event_count: u32
    event_count, ok = buffer_io.buffer_read_u32(buf); assert(ok)
    events := make([]ProjectileEvent, event_count, context.temp_allocator)
    for i in 0 ..< event_count {
        raw_kind: u8
        raw_kind, ok = buffer_io.buffer_read_u8(buf); assert(ok)
        kind := GameMsgKind(raw_kind)
        ev := ProjectileEvent{kind = kind}
        switch kind {
        case .SPAWN_PROJECTILE:
            ev.data = SpawnProjectileMsg{projectile = unpack_projectile_spawn_data(buf)}
        case .REMOVE_PROJECTILE:
            id: u32
            id, ok = buffer_io.buffer_read_u32(buf); assert(ok)
            ev.data = RemoveProjectileMsg{projectile_id = id}
        }
        events[i] = ev
    }
    data.projectile_events = events

    full_count: u32
    full_count, ok = buffer_io.buffer_read_u32(buf); assert(ok)
    full_projectiles := make([]Projectile, full_count, context.temp_allocator)
    for i in 0 ..< full_count {
        full_projectiles[i] = unpack_projectile_spawn_data(buf)
    }
    data.full_projectiles = full_projectiles

    return data
}

// ---------------------------------------------------------------------
// Msg pack/unpack
// ---------------------------------------------------------------------

pack_server_message :: proc(buf: ^buffer_io.Buffer, msg: Msg) {
    buffer_io.buffer_reset(buf)
    buffer_io.buffer_write_u8(buf, u8(msg.kind))

    switch msg.kind {
    case .Invalid:
        panic("invalid game message.")

    case .START_GAME:
        d := msg.data.(StartGameMsg)
        buffer_io.buffer_write_u32(buf, d.user_id)

    case .GAME_DATA:
        d := msg.data.(GameData)
        pack_game_data(buf, d)

    case .GAME_MSG:
        d := msg.data.(GameMsg)
        buffer_io.buffer_write_u8(buf, u8(d.kind))
        switch v in d.data {
        case SpawnProjectileMsg:
            pack_projectile_spawn_data(buf, v.projectile)
        case RemoveProjectileMsg:
            buffer_io.buffer_write_u32(buf, v.projectile_id)
        }

    case .PING_RESPOND:
        d := msg.data.(PingRespondMsg)
        buffer_io.buffer_write_u32(buf, d.id)

    case .CONNECT, .GET_STATE, .PING, .USER_MSG:
        panic("Server attempted to send a client message")

    case:
        fmt.println(msg.kind)
        panic("Invalid MsgKind")
    }
}

unpack_client_message :: proc(buf: ^buffer_io.Buffer) -> Msg {
    msg := Msg{}
    ok := false

    raw_kind: u8
    raw_kind, ok = buffer_io.buffer_read_u8(buf); assert(ok)
    msg.kind = MsgKind(raw_kind)

    switch msg.kind {
    case .Invalid:
        panic("invalid game message.")

    case .START_GAME:
        d := StartGameMsg{}
        d.user_id, ok = buffer_io.buffer_read_u32(buf); assert(ok)
        msg.data = d

    case .GAME_DATA:
        msg.data = unpack_game_data(buf)

    case .GAME_MSG:
        raw: u8
        raw, ok = buffer_io.buffer_read_u8(buf); assert(ok)
        kind := GameMsgKind(raw)
        gm := GameMsg{kind = kind}
        switch kind {
        case .SPAWN_PROJECTILE:
            gm.data = SpawnProjectileMsg{projectile = unpack_projectile_spawn_data(buf)}
        case .REMOVE_PROJECTILE:
            id: u32
            id, ok = buffer_io.buffer_read_u32(buf); assert(ok)
            gm.data = RemoveProjectileMsg{projectile_id = id}
        }
        msg.data = gm

    case .PING_RESPOND:
        d := PingRespondMsg{}
        d.id, ok = buffer_io.buffer_read_u32(buf); assert(ok)
        msg.data = d

    case .CONNECT, .GET_STATE, .PING, .USER_MSG:
        panic("Client received a client message")

    case:
        fmt.println(msg.kind)
        panic("Invalid MsgKind")
    }

    return msg
}

pack_client_message :: proc(buf: ^buffer_io.Buffer, msg: Msg) {
    buffer_io.buffer_reset(buf)
    buffer_io.buffer_write_u8(buf, u8(msg.kind))

    switch msg.kind {
    case .Invalid:
        panic("invalid game message.")

    case .START_GAME:
        d := msg.data.(StartGameMsg)
        buffer_io.buffer_write_u32(buf, d.user_id)

    case .CONNECT:
        d := msg.data.(ConnectMsg)
        buffer_io.buffer_write_u32(buf, d.user_id)

    case .GET_STATE:
        // no payload

    case .PING:
        d := msg.data.(PingMsg)
        buffer_io.buffer_write_u32(buf, d.user_id)
        buffer_io.buffer_write_u32(buf, d.id)

    case .USER_MSG:
        d := msg.data.(UserMsg)
        buffer_io.buffer_write_u32(buf, d.user_id)
        buffer_io.buffer_write_u8(buf, u8(d.kind))
        switch v in d.data {
        case MoveMsg:
            buffer_io.buffer_write_f32(buf, v.pos.x)
            buffer_io.buffer_write_f32(buf, v.pos.y)
        case AbilityMsg:
            buffer_io.buffer_write_u8(buf, v.user_ability_index)
            buffer_io.buffer_write_f32(buf, v.direction.x)
            buffer_io.buffer_write_f32(buf, v.direction.y)
        case DirectionMsg:
            buffer_io.buffer_write_f32(buf, v.direction.x)
            buffer_io.buffer_write_f32(buf, v.direction.y)
        }

    case .GAME_DATA, .GAME_MSG, .PING_RESPOND:
        panic("Client attempted to send a server message")

    case:
        fmt.println(msg.kind)
        panic("Invalid MsgKind")
    }
}

unpack_server_message :: proc(buf: ^buffer_io.Buffer) -> Msg {
    msg := Msg{}
    ok := false

    raw_kind: u8
    raw_kind, ok = buffer_io.buffer_read_u8(buf); assert(ok)
    msg.kind = MsgKind(raw_kind)

    switch msg.kind {
    case .Invalid:
        panic("invalid game message.")

    case .START_GAME:
        d := StartGameMsg{}
        d.user_id, ok = buffer_io.buffer_read_u32(buf); assert(ok)
        msg.data = d

    case .CONNECT:
        d := ConnectMsg{}
        d.user_id, ok = buffer_io.buffer_read_u32(buf); assert(ok)
        msg.data = d

    case .GET_STATE:
        msg.data = GetStateMsg{}

    case .PING:
        d := PingMsg{}
        d.user_id, ok = buffer_io.buffer_read_u32(buf); assert(ok)
        d.id, ok = buffer_io.buffer_read_u32(buf);      assert(ok)
        msg.data = d

    case .USER_MSG:
        d := UserMsg{}
        d.user_id, ok = buffer_io.buffer_read_u32(buf); assert(ok)
        raw_user_kind: u8
        raw_user_kind, ok = buffer_io.buffer_read_u8(buf); assert(ok)
        d.kind = UserMsgKind(raw_user_kind)

        switch d.kind {
        case .MOVE:
            m := MoveMsg{}
            m.pos.x, ok = buffer_io.buffer_read_f32(buf); assert(ok)
            m.pos.y, ok = buffer_io.buffer_read_f32(buf); assert(ok)
            d.data = m
        case .ABILITY:
            a := AbilityMsg{}
            a.user_ability_index, ok = buffer_io.buffer_read_u8(buf); assert(ok)
            a.direction.x, ok = buffer_io.buffer_read_f32(buf);       assert(ok)
            a.direction.y, ok = buffer_io.buffer_read_f32(buf);       assert(ok)
            d.data = a
        case .DIRECTION:
            dir := DirectionMsg{}
            dir.direction.x, ok = buffer_io.buffer_read_f32(buf); assert(ok)
            dir.direction.y, ok = buffer_io.buffer_read_f32(buf); assert(ok)
            d.data = dir
        case:
            panic("Invalid UserMsgKind")
        }
        msg.data = d

    case .GAME_DATA, .GAME_MSG, .PING_RESPOND:
        panic("Server received a server message")

    case:
        fmt.println(msg.kind)
        panic("Invalid MsgKind")
    }

    return msg
}
