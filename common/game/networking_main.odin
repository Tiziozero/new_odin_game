package game

import "vendor:raylib"
import "core:fmt"
import "core:net";
import "project:common/buffer_io"
MsgKind :: enum u8 {
    CONNECT,
    GET_STATE,
    PING,
    PING_RESPOND,
    GAME_DATA,
    // USER_DATA,
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
    GAME_STATE,
}
UserData :: struct {
    energy: f32,
    abilities: [ABILITIES_COUNT]struct {
        active: u8,
        ability_id: u32,
        level: u32,
        cooldown: f32,
    },
    move_to: raylib.Vector2,
}
Msg :: struct {
    kind: MsgKind,

    connect: struct {
        user_id: u32,
    },

    get_state: struct {
        game_data: []byte,
    },

    ping: struct {
        user_id: u32,
        id: u32,
    },

    ping_response: u32,

    game_data: struct {
        user_data: UserData,
        game_data: []byte,
    },

    game_msg: struct {
        kind: GameMsgKind,

        spawn_projectile: struct {
            projectile: Projectile,
        },

        remove_projectile: struct {
            projectile_id: u32,
        },

        game_state: struct {
            game_data: []byte,
        },
    },

    user_msg: struct {
        user_id: u32,
        kind: UserMsgKind,

        move: struct {
            x, y: f32,
        },

        ability: struct {
            user_ability_index: u8,
            direction: raylib.Vector2,
        },

        direction: struct {
            x, y: f32,
        },
    },
}
// ADDR :: "172.31.138.162";
// SERVER_ENDPOINT :: "172.31.138.162:8081";
ADDR :: "127.0.0.1";
SERVER_ENDPOINT :: "127.0.0.1:8081";
init_udp_socket :: proc(port := 0) -> (net.UDP_Socket, net.Network_Error) {
    sock_addr := net.parse_address(ADDR, false);
    socket, err := net.make_bound_udp_socket(sock_addr, port);
    if err != net.Create_Socket_Error.None {
        fmt.println("Error in creating udp socket.", err);
        return {}, err;
    }
    return socket, net.Create_Socket_Error.None;
}
init_send_message :: proc() -> buffer_io.Buffer {
    b := buffer_io.buffer_make(1024)
    return b
}
send_message :: proc(socket: net.UDP_Socket, endpoint: net.Endpoint,
    b: ^buffer_io.Buffer) -> net.UDP_Send_Error {
    n, err := net.send(socket, b.data[:buffer_io.buffer_written(b)], endpoint)
    assert(n == buffer_io.buffer_written(b));
    buffer_io.buffer_destroy(b)
    return err;
}


unpack_server_message :: proc(buf: ^buffer_io.Buffer) -> Msg {
    msg := Msg{}

    raw_kind, ok := buffer_io.buffer_read_u8(buf)
    assert(ok)

    msg.kind = MsgKind(raw_kind)

    switch msg.kind {

    case .CONNECT:
        msg.connect.user_id, ok = buffer_io.buffer_read_u32(buf)
        assert(ok)

    case .GET_STATE:
        // GET_STATE has no fields currently.
        //
        // If you later add user_id, put it here.
        //

    case .PING:
        msg.ping.user_id, ok = buffer_io.buffer_read_u32(buf)
        assert(ok)

        msg.ping.id, ok = buffer_io.buffer_read_u32(buf)
        assert(ok)

    case .USER_MSG:
        msg.user_msg.user_id, ok = buffer_io.buffer_read_u32(buf)
        assert(ok)

        raw_user_kind, ok := buffer_io.buffer_read_u8(buf)
        assert(ok)

        msg.user_msg.kind = UserMsgKind(raw_user_kind)

        switch msg.user_msg.kind {

        case .MOVE:
            msg.user_msg.move.x, ok = buffer_io.buffer_read_f32(buf)
            assert(ok)

            msg.user_msg.move.y, ok = buffer_io.buffer_read_f32(buf)
            assert(ok)

        case .ABILITY:
            msg.user_msg.ability.user_ability_index, ok =
                buffer_io.buffer_read_u8(buf)
            assert(ok)

            msg.user_msg.ability.direction.x, ok =
                buffer_io.buffer_read_f32(buf)
            assert(ok)

            msg.user_msg.ability.direction.y, ok =
                buffer_io.buffer_read_f32(buf)
            assert(ok)

        case .DIRECTION:
            msg.user_msg.direction.x, ok =
                buffer_io.buffer_read_f32(buf)
            assert(ok)

            msg.user_msg.direction.y, ok =
                buffer_io.buffer_read_f32(buf)
            assert(ok)

        case:
            panic("Invalid UserMsgKind")
        }

    case .GAME_DATA, .GAME_MSG, .PING_RESPOND:
        panic("Server received a server message")

    case:
        panic("Invalid MsgKind")
    }

    return msg
}
pack_server_message :: proc(buf: ^buffer_io.Buffer, msg: Msg) {
    buffer_io.buffer_reset(buf)

    buffer_io.buffer_write_u8(buf, u8(msg.kind))

    switch msg.kind {

    case .GAME_DATA:
        buffer_io.buffer_write_f32(buf, msg.game_data.user_data.energy)

        for i in 0..<ABILITIES_COUNT {
            a := msg.game_data.user_data.abilities[i]

            buffer_io.buffer_write_u8(buf, a.active)
            buffer_io.buffer_write_u32(buf, a.ability_id)
            buffer_io.buffer_write_u32(buf, a.level)
            buffer_io.buffer_write_f32(buf, a.cooldown)
        }

        buffer_io.buffer_write_f32(
            buf,
            msg.game_data.user_data.move_to.x,
        )
        buffer_io.buffer_write_f32(
            buf,
            msg.game_data.user_data.move_to.y,
        )

        // game_data is deliberately the remainder of the packet.
        wrote, ok := buffer_io.buffer_write_bytes(
            buf,
            msg.game_data.game_data,
        )
        assert(ok)
        assert(wrote == len(msg.game_data.game_data))

    case .GAME_MSG:
        buffer_io.buffer_write_u8(
            buf,
            u8(msg.game_msg.kind),
        )

        switch msg.game_msg.kind {

        case .SPAWN_PROJECTILE:
            p := msg.game_msg.spawn_projectile.projectile

            buffer_io.buffer_write_u32(buf, p.id)
            buffer_io.buffer_write_u32(buf, p.projectile_id)

            buffer_io.buffer_write_f32(buf, p.origin.x)
            buffer_io.buffer_write_f32(buf, p.origin.y)

            buffer_io.buffer_write_f32(buf, p.direction.x)
            buffer_io.buffer_write_f32(buf, p.direction.y)

            buffer_io.buffer_write_f32(buf, p.position.x)
            buffer_io.buffer_write_f32(buf, p.position.y)

        case .REMOVE_PROJECTILE:
            buffer_io.buffer_write_u32(
                buf,
                msg.game_msg.remove_projectile.projectile_id,
            )

        case .GAME_STATE:
            wrote, ok := buffer_io.buffer_write_bytes(
                buf,
                msg.game_msg.game_state.game_data,
            )
            assert(ok)
            assert(wrote == len(msg.game_msg.game_state.game_data))

        case:
            panic("Invalid GameMsgKind")
        }

    case .PING_RESPOND:
        buffer_io.buffer_write_u32(buf, msg.ping_response)

    case .CONNECT, .GET_STATE, .PING, .USER_MSG:
        panic("Server attempted to send a client message")

    case:
        panic("Invalid MsgKind")
    }
}
pack_client_message :: proc(buf: ^buffer_io.Buffer, msg: Msg) {
    buffer_io.buffer_reset(buf)

    buffer_io.buffer_write_u8(buf, u8(msg.kind))

    switch msg.kind {

    case .CONNECT:
        buffer_io.buffer_write_u32(
            buf,
            msg.connect.user_id,
        )

    case .GET_STATE:
        // Currently no payload.

    case .PING:
        buffer_io.buffer_write_u32(
            buf,
            msg.ping.user_id,
        )

        buffer_io.buffer_write_u32(
            buf,
            msg.ping.id,
        )

    case .USER_MSG:
        buffer_io.buffer_write_u32(
            buf,
            msg.user_msg.user_id,
        )

        buffer_io.buffer_write_u8(
            buf,
            u8(msg.user_msg.kind),
        )

        switch msg.user_msg.kind {

        case .MOVE:
            buffer_io.buffer_write_f32(
                buf,
                msg.user_msg.move.x,
            )
            buffer_io.buffer_write_f32(
                buf,
                msg.user_msg.move.y,
            )

        case .ABILITY:
            buffer_io.buffer_write_u8(
                buf,
                msg.user_msg.ability.user_ability_index,
            )

            buffer_io.buffer_write_f32(
                buf,
                msg.user_msg.ability.direction.x,
            )

            buffer_io.buffer_write_f32(
                buf,
                msg.user_msg.ability.direction.y,
            )

        case .DIRECTION:
            buffer_io.buffer_write_f32(
                buf,
                msg.user_msg.direction.x,
            )

            buffer_io.buffer_write_f32(
                buf,
                msg.user_msg.direction.y,
            )

        case:
            panic("Invalid UserMsgKind")
        }

    case .GAME_DATA, .GAME_MSG, .PING_RESPOND:
        panic("Client attempted to send a server message")

    case:
        panic("Invalid MsgKind")
    }
}
unpack_client_message :: proc(buf: ^buffer_io.Buffer) -> Msg {
    msg := Msg{}

    raw_kind, ok := buffer_io.buffer_read_u8(buf)
    assert(ok)

    msg.kind = MsgKind(raw_kind)

    switch msg.kind {

    case .GAME_DATA:
        msg.game_data.user_data.energy, ok =
            buffer_io.buffer_read_f32(buf)
        assert(ok)

        for i in 0..<ABILITIES_COUNT {
            a := &msg.game_data.user_data.abilities[i]

            a.active, ok = buffer_io.buffer_read_u8(buf)
            assert(ok)

            a.ability_id, ok = buffer_io.buffer_read_u32(buf)
            assert(ok)

            a.level, ok = buffer_io.buffer_read_u32(buf)
            assert(ok)

            a.cooldown, ok = buffer_io.buffer_read_f32(buf)
            assert(ok)
        }

        msg.game_data.user_data.move_to.x, ok =
            buffer_io.buffer_read_f32(buf)
        assert(ok)

        msg.game_data.user_data.move_to.y, ok =
            buffer_io.buffer_read_f32(buf)
        assert(ok)

        // Everything remaining is game data.
        remaining := buf.len - buf.pos

        if remaining > 0 {
            msg.game_data.game_data = make([]byte, remaining)

            copy(
                msg.game_data.game_data,
                buf.data[buf.pos:buf.len],
            )

            buf.pos = buf.len
        }

    case .GAME_MSG:
        raw_game_kind, ok := buffer_io.buffer_read_u8(buf)
        assert(ok)

        msg.game_msg.kind = GameMsgKind(raw_game_kind)

        switch msg.game_msg.kind {

        case .SPAWN_PROJECTILE:
            p := &msg.game_msg.spawn_projectile.projectile

            p.id, ok = buffer_io.buffer_read_u32(buf)
            assert(ok)

            p.projectile_id, ok =
                buffer_io.buffer_read_u32(buf)
            assert(ok)

            p.origin.x, ok =
                buffer_io.buffer_read_f32(buf)
            assert(ok)

            p.origin.y, ok =
                buffer_io.buffer_read_f32(buf)
            assert(ok)

            p.direction.x, ok =
                buffer_io.buffer_read_f32(buf)
            assert(ok)

            p.direction.y, ok =
                buffer_io.buffer_read_f32(buf)
            assert(ok)

            p.position.x, ok =
                buffer_io.buffer_read_f32(buf)
            assert(ok)

            p.position.y, ok =
                buffer_io.buffer_read_f32(buf)
            assert(ok)

        case .REMOVE_PROJECTILE:
            msg.game_msg.remove_projectile.projectile_id, ok =
                buffer_io.buffer_read_u32(buf)
            assert(ok)

        case .GAME_STATE:
            remaining := buf.len - buf.pos

            if remaining > 0 {
                msg.game_msg.game_state.game_data =
                    make([]byte, remaining)

                copy(
                    msg.game_msg.game_state.game_data,
                    buf.data[buf.pos:buf.len],
                )

                buf.pos = buf.len
            }

        case:
            panic("Invalid GameMsgKind")
        }

    case .PING_RESPOND:
        msg.ping_response, ok =
            buffer_io.buffer_read_u32(buf)
        assert(ok)

    case .CONNECT, .GET_STATE, .PING, .USER_MSG:
        panic("Client received a client message")

    case:
        panic("Invalid MsgKind")
    }

    return msg
}
