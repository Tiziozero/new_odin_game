// server.odin
package main

import "core:fmt"
import "core:math"
import "core:math/rand"
import "core:net"
import "core:sync"
import "core:sys/windows"
import "core:thread"
import "core:time"
import "project:common/buffer_io"
import "project:common/game"
import "vendor:raylib"

MIN_ODIN :: "dev-2026-06"

when ODIN_VERSION < MIN_ODIN {
    // #panic("Requires odin dev-2026-06")
}

PROJECTILES_COUNT :: 1024
ABILITIES_COUNT   :: game.ABILITIES_COUNT
MAX_TIMEOUT       :: 10 * time.Second
NPC_AGGRO_RADIUS  :: 300

// Damage a projectile does when its owner is gone or has no attack stat.
PROJECTILE_DAMAGE :: 10

// Max distance between wall samples along a projectile's path in one tick.
// Keep this at or below your thinnest wall.
PROJECTILE_WALL_STEP :: 8

// Where players spawn / respawn / arrive when entering a space.
SPAWN_POS :: raylib.Vector2{0, 0}

// Player entity handles == the client's user_id (the wire format identifies
// the player's own entity by it). NPC handles are allocated by the server
// starting here; server_alloc_handle skips anything already in use.
NPC_HANDLE_BASE :: game.EntityHandle(1 << 31)

// ---------------------------------------------------------------------
// Entities
// ---------------------------------------------------------------------

EntityKind :: enum {
    Player,
    Npc,
}

NpcBehavior :: enum {
    Idle,       // stands still
    Wander,     // roams around `home`
    Shopkeeper, // stands still, not targetable, will own shop interaction
    Hostile,    // chases players inside NPC_AGGRO_RADIUS
}

NpcData :: struct {
    behavior:      NpcBehavior,
    home:          raylib.Vector2,
    wander_radius: f32,
    wander_timer:  f32,
    shop_id:       u32, // for .Shopkeeper, indexes a (future) shop table
}

// Everything the server knows about one entity. `entity` is the part that
// is replicated to clients (via deltas); the rest is server-only.
ServerEntity :: struct {
    using entity: game.Entity,

    last_sent:        game.Entity, // state as of the last per-tick send, deltas diff against this
    needs_full_delta: bool,        // freshly added: next delta must carry every field

    kind:       EntityKind,
    targetable: bool, // projectiles only hit targetable entities

    energy, max_energy, max_health, attack: f32,

    move_to, move_origin, facing: raylib.Vector2,
    abilities: [ABILITIES_COUNT]game.EntityAbility,

    npc: NpcData, // only meaningful when kind == .Npc
}

// ---------------------------------------------------------------------
// Spaces: the open world and rooms (dungeons, towns, ...)
// ---------------------------------------------------------------------

SpaceId :: u32
OPEN_WORLD_ID :: SpaceId(0)

RoomPurpose :: enum {
    Dungeon,
    Town,
}

OpenWorld :: struct {
    // chunk streaming / world events etc. go here later
}

Room :: struct {
    purpose: RoomPurpose,
    seed:    u64,
}

SpaceVariant :: union {
    OpenWorld,
    Room,
}

// A Space owns its map, entities and projectiles. It does NOT own clients
// (the Server does); players inside a space are just entities with
// kind == .Player.
Space :: struct {
    id:         SpaceId,
    persistent: bool,
    variant:    SpaceVariant,

    gmap:     game.Map,
    entities: map[game.EntityHandle]ServerEntity,
    player_count: int,

    projectiles:       [PROJECTILES_COUNT]game.Projectile,
    projectiles_count: u32,

    // things that happened since the last per-tick GameData; drained by
    // build_game_data (or cleared when nobody is in the space)
    events:        [dynamic]game.ProjectileEvent,
    entity_events: [dynamic]game.EntityEvent,
}

space_make :: proc(id: SpaceId, persistent: bool, variant: SpaceVariant) -> ^Space {
    sp := new(Space)
    sp.id = id
    sp.persistent = persistent
    sp.variant = variant
    sp.gmap = game.new_map()
    sp.entities = make(map[game.EntityHandle]ServerEntity)
    sp.events = make([dynamic]game.ProjectileEvent)
    sp.entity_events = make([dynamic]game.EntityEvent)
    game.generate_chunck(&sp.gmap, 0, 0) // TODO: per-variant generation (seed, purpose)
    return sp
}

space_destroy :: proc(sp: ^Space) {
    delete(sp.entities)
    delete(sp.events)
    delete(sp.entity_events)
    // TODO: free sp.gmap once game.Map has a destroy proc
    free(sp)
}

space_get_entity :: proc(sp: ^Space, h: game.EntityHandle) -> ^ServerEntity {
    if sp == nil { return nil }
    if h in sp.entities { return &sp.entities[h] }
    return nil
}

space_emit_entity_event :: proc(sp: ^Space, ev: game.EntityEvent) {
    append(&sp.entity_events, ev)
}

// ---------------------------------------------------------------------
// Server
// ---------------------------------------------------------------------

// A connected player's session. The player's entity lives in a Space, found
// via `space` + EntityHandle(user_id).
Client :: struct {
    user_id:   u32,
    endpoint:  net.Endpoint,
    last_ping: time.Time,
    no_send:   bool, // connected but hasn't sent START_GAME yet
    space:     SpaceId,

    // where "leave space" brings the player back to
    return_space: SpaceId,
    return_pos:   raylib.Vector2,
}

// ok == true means success; otherwise `error` says why.
error :: distinct struct { error: string, ok: bool }
AbilityProc :: distinct proc(s: ^Server, sp: ^Space, caster: ^ServerEntity, id, level: u32, target: raylib.Vector2) -> error
Ability :: struct {
    kind:   game.AbilityKind,
    action: AbilityProc,
}

Server :: struct {
    // one lock for everything: receiver thread and tick thread both take it
    lock: sync.Mutex,

    socket:    net.UDP_Socket,
    assets:    game.AssetManger,
    abilities: map[u32]Ability,

    clients:      map[u32]Client,
    entity_index: map[game.EntityHandle]SpaceId, // every entity in every space -> where it lives

    open_world:    ^Space,
    rooms:         map[SpaceId]^Space,
    next_space_id: SpaceId,

    next_npc_handle:    game.EntityHandle,
    next_projectile_id: u32,
}

server_init :: proc(s: ^Server) {
    s.assets = game.load_assets("imgs.json")
    s.abilities = make(map[u32]Ability)
    s.clients = make(map[u32]Client)
    s.entity_index = make(map[game.EntityHandle]SpaceId)
    s.rooms = make(map[SpaceId]^Space)
    s.next_space_id = OPEN_WORLD_ID + 1
    s.next_npc_handle = NPC_HANDLE_BASE
    s.open_world = space_make(OPEN_WORLD_ID, true, OpenWorld{})

    s.abilities[1] = Ability{
        kind = .Projectile,
        action = proc(s: ^Server, sp: ^Space, caster: ^ServerEntity, id, level: u32, target: raylib.Vector2) -> error {
            origin := game.rect_pos(caster.body) + 0.5 * game.rect_size(caster.body)
            p := game.Projectile{
                owner     = caster.id,
                origin    = origin,
                position  = origin,
                speed     = 750,
                range     = 300,
                direction = target,
            }
            if !space_spawn_projectile(s, sp, p) {
                return {"projectile limit reached", false}
            }
            return {"", true}
        },
    }
}

init_server_socket :: proc(s: ^Server) {
    sock, _ := game.init_udp_socket(port = 8081)
    s.socket = sock
}

server_get_space :: proc(s: ^Server, id: SpaceId) -> ^Space {
    if id == OPEN_WORLD_ID { return s.open_world }
    if id in s.rooms { return s.rooms[id] }
    return nil
}

server_client :: proc(s: ^Server, user_id: u32) -> ^Client {
    if user_id in s.clients { return &s.clients[user_id] }
    return nil
}

// Resolves a user id to (session, space, entity). All nil if unknown.
server_player :: proc(s: ^Server, user_id: u32) -> (c: ^Client, sp: ^Space, e: ^ServerEntity) {
    c = server_client(s, user_id)
    if c == nil { return }
    sp = server_get_space(s, c.space)
    e = space_get_entity(sp, game.EntityHandle(user_id))
    return
}

random_texture :: proc(s: ^Server) -> u32 {
    return u32(rand.int31() % i32(len(s.assets.assets)))
}

// ---------------------------------------------------------------------
// Messaging: plain text to clients
// ---------------------------------------------------------------------

// Sends one text message to one client. sender == 0 means "the server".
send_string_msg :: proc(
    s: ^Server, c: ^Client, text: string,
    kind := game.StringMsgKind.INFO, sender: u32 = 0,
) {
    if c == nil { return }
    b := game.init_send_message()
    game.pack_server_message(&b, game.Msg{
        kind = .STRING_MSG,
        data = game.StringMsg{kind = kind, sender = sender, text = text},
    })
    if err := game.send_message(s.socket, c.endpoint, &b); err != .None {
        fmt.println("error sending string msg to client", c.user_id, err)
    }
}

// Sends a text message to every started client in `sp`, or to every started
// client on the server when sp == nil.
broadcast_string_msg :: proc(
    s: ^Server, sp: ^Space, text: string,
    kind := game.StringMsgKind.INFO, sender: u32 = 0,
) {
    for _, &c in s.clients {
        if c.no_send { continue }
        if sp != nil && c.space != sp.id { continue }
        send_string_msg(s, &c, text, kind, sender)
    }
}

// Tells a client it now lives in another space. A full sync should follow.
send_space_changed :: proc(s: ^Server, c: ^Client, space_id: SpaceId, pos: raylib.Vector2) {
    b := game.init_send_message()
    game.pack_server_message(&b, game.Msg{
        kind = .GAME_MSG,
        data = game.GameMsg{
            kind = .SPACE_CHANGED,
            data = game.SpaceChangedMsg{space_id = u32(space_id), pos = pos},
        },
    })
    if err := game.send_message(s.socket, c.endpoint, &b); err != .None {
        fmt.println("error sending space change to client", c.user_id, err)
    }
}

// ---------------------------------------------------------------------
// Entity management
// ---------------------------------------------------------------------

server_alloc_handle :: proc(s: ^Server) -> game.EntityHandle {
    for {
        h := s.next_npc_handle
        s.next_npc_handle += 1
        if h != 0 && h not_in s.entity_index {
            return h
        }
    }
}

server_add_entity :: proc(s: ^Server, sp: ^Space, e: ServerEntity) {
    ent := e
    ent.needs_full_delta = true // clients have never seen it: first delta carries everything
    sp.entities[ent.id] = ent
    s.entity_index[ent.id] = sp.id
    if ent.kind == .Player { sp.player_count += 1 }
}

// Removes the entity from the space and tells the space's clients to drop it.
server_remove_entity :: proc(s: ^Server, sp: ^Space, h: game.EntityHandle) -> (ServerEntity, bool) {
    e, ok := sp.entities[h]
    if !ok { return {}, false }
    delete_key(&sp.entities, h)
    delete_key(&s.entity_index, h)
    if e.kind == .Player { sp.player_count -= 1 }
    space_emit_entity_event(sp, game.EntityEvent{
        kind      = .REMOVED,
        entity_id = u32(h),
        health    = f32(e.health),
    })
    return e, true
}

make_player :: proc(s: ^Server, handle: game.EntityHandle) -> ServerEntity {
    e := ServerEntity{
        kind       = .Player,
        targetable = true,
        max_health = 100,
        attack     = 15,
        entity     = game.Entity{
            id      = handle,
            texture = random_texture(s),
            health  = 100,
            status  = .ESALIVE,
            body    = raylib.Rectangle{SPAWN_POS.x, SPAWN_POS.y, 32, 32},
        },
    }
    e.last_sent = e.entity
    e.abilities[0] = game.EntityAbility{ability_id = 1, level = 1, active = true}
    return e
}

server_spawn_npc :: proc(
    s: ^Server, sp: ^Space,
    pos: raylib.Vector2, texture: u32, behavior: NpcBehavior,
    wander_radius: f32 = 150,
) -> game.EntityHandle {
    h := server_alloc_handle(s)
    e := ServerEntity{
        kind       = .Npc,
        targetable = behavior != .Shopkeeper,
        max_health = 50,
        move_to    = pos,
        move_origin = pos,
        npc = NpcData{behavior = behavior, home = pos, wander_radius = wander_radius},
        entity = game.Entity{
            id      = h,
            texture = texture,
            health  = 50,
            status  = .ESALIVE,
            body    = raylib.Rectangle{pos.x, pos.y, 32, 32},
        },
    }
    e.last_sent = e.entity
    server_add_entity(s, sp, e)
    return h
}

entity_label :: proc(e: ^ServerEntity) -> string {
    if e.kind == .Player {
        return fmt.tprintf("Player %d", u32(e.id))
    }
    return fmt.tprintf("NPC %d", u32(e.id))
}

// What clients should show this entity as. Sent with every EntityUpdate.
entity_role :: proc(e: ^ServerEntity) -> game.EntityRole {
    switch e.kind {
    case .Player:
        return .Player
    case .Npc:
        switch e.npc.behavior {
        case .Idle:       return .Idle
        case .Wander:     return .Wanderer
        case .Shopkeeper: return .Shopkeeper
        case .Hostile:    return .Hostile
        }
    }
    return .Unknown
}

// ---------------------------------------------------------------------
// Damage & death
// ---------------------------------------------------------------------

// Applies damage and emits a DAMAGED event. Returns true if this hit took
// the entity to 0 health. It does NOT handle the death itself - the caller
// follows up with server_kill_entity (which may remove the entity, so
// don't use `target` afterwards).
entity_apply_damage :: proc(sp: ^Space, target: ^ServerEntity, amount: f32, source: game.EntityHandle) -> bool {
    if amount <= 0 || !target.targetable { return false }

    hp := f32(target.health)
    if hp <= 0 { return false } // already dead

    hp = max(hp - amount, 0)
    target.health = type_of(target.health)(hp)

    space_emit_entity_event(sp, game.EntityEvent{
        kind      = .DAMAGED,
        entity_id = u32(target.id),
        source_id = u32(source),
        amount    = amount,
        health    = hp,
    })
    return hp <= 0
}

// Players respawn immediately at SPAWN_POS with full health. (If you want a
// respawn timer later, this is the place.)
server_respawn_player :: proc(s: ^Server, sp: ^Space, e: ^ServerEntity) {
    e.health = type_of(e.health)(e.max_health)
    e.energy = e.max_energy
    e.body.x = SPAWN_POS.x
    e.body.y = SPAWN_POS.y
    e.move_to = SPAWN_POS
    e.move_origin = SPAWN_POS

    space_emit_entity_event(sp, game.EntityEvent{
        kind      = .RESPAWNED,
        entity_id = u32(e.id),
        health    = f32(e.health),
    })

    if c := server_client(s, u32(e.id)); c != nil {
        send_string_msg(s, c, "You died. Respawning...", .SYSTEM)
    }
}

// Handles an entity's death: emits DIED, broadcasts a message to the space,
// then respawns it (players) or removes it (NPCs).
// After this returns the victim pointer may be invalid.
server_kill_entity :: proc(s: ^Server, sp: ^Space, victim_h, killer_h: game.EntityHandle) {
    victim := space_get_entity(sp, victim_h)
    if victim == nil { return }
    killer := space_get_entity(sp, killer_h) // nil if the killer left / is gone

    space_emit_entity_event(sp, game.EntityEvent{
        kind      = .DIED,
        entity_id = u32(victim_h),
        source_id = u32(killer_h),
    })

    killer_name := "something" if killer == nil else entity_label(killer)
    broadcast_string_msg(
        s, sp,
        fmt.tprintf("%s was slain by %s", entity_label(victim), killer_name),
        .COMBAT,
    )

    switch victim.kind {
    case .Player:
        server_respawn_player(s, sp, victim)
    case .Npc:
        server_remove_entity(s, sp, victim_h)
    }
}

// Hook for on-hit effects. Projectiles live in the same space as the
// entities they hit, so `sp` is the only space we need to look at.
space_on_projectile_hit :: proc(s: ^Server, sp: ^Space, p: game.Projectile, target_h: game.EntityHandle) {
    target := space_get_entity(sp, target_h)
    if target == nil { return }

    damage := f32(PROJECTILE_DAMAGE)
    if owner := space_get_entity(sp, p.owner); owner != nil && owner.attack > 0 {
        damage = owner.attack
    }

    if entity_apply_damage(sp, target, damage, p.owner) {
        server_kill_entity(s, sp, target_h, p.owner)
    }
}

// ---------------------------------------------------------------------
// Rooms
// ---------------------------------------------------------------------

server_create_room :: proc(s: ^Server, purpose: RoomPurpose, persistent: bool, seed: u64 = 0) -> ^Space {
    id := s.next_space_id
    s.next_space_id += 1
    sp := space_make(id, persistent, Room{purpose = purpose, seed = seed})
    s.rooms[id] = sp
    fmt.println("Created room", id, purpose, "persistent:", persistent)
    return sp
}

server_destroy_room :: proc(s: ^Server, sp: ^Space) {
    for h in sp.entities {
        delete_key(&s.entity_index, h)
    }
    delete_key(&s.rooms, sp.id)
    fmt.println("Destroyed room", sp.id)
    space_destroy(sp)
}

// Frees temporary rooms once the last player has left. Never touches the
// open world or persistent rooms.
server_maybe_free_room :: proc(s: ^Server, sp: ^Space) {
    if sp == nil { return }
    if _, is_room := sp.variant.(Room); !is_room { return }
    if sp.persistent || sp.player_count > 0 { return }
    server_destroy_room(s, sp)
}

// ---------------------------------------------------------------------
// Clients joining / leaving / moving between spaces
// ---------------------------------------------------------------------

server_connect_client :: proc(s: ^Server, user_id: u32, endpoint: net.Endpoint) {
    fmt.println("Connect")
    fmt.printfln("\taccess token: %d", user_id)

    handle := game.EntityHandle(user_id)
    if handle == 0 {
        fmt.println("rejecting connect: user id 0 is reserved")
        return
    }
    if user_id in s.clients {
        server_remove_client(s, user_id) // reconnect with the same id
    }
    if handle in s.entity_index {
        fmt.println("rejecting connect: id collides with a non-player entity")
        return
    }

    s.clients[user_id] = Client{
        user_id      = user_id,
        endpoint     = endpoint,
        last_ping    = time.now(),
        no_send      = true,
        space        = OPEN_WORLD_ID,
        return_space = OPEN_WORLD_ID,
        return_pos   = SPAWN_POS,
    }
    server_add_entity(s, s.open_world, make_player(s, handle))
    send_full_sync(s, s.open_world, server_client(s, user_id))
}

server_remove_client :: proc(s: ^Server, user_id: u32) {
    c := server_client(s, user_id)
    if c == nil { return }
    sp := server_get_space(s, c.space)
    if sp != nil {
        server_remove_entity(s, sp, game.EntityHandle(user_id))
        server_maybe_free_room(s, sp)
    }
    delete_key(&s.clients, user_id)
}

// Moves a player into another space (portal, dungeon entrance, town...).
// Tells the client its space changed, then sends it a full sync of the new
// one. Low-level: no permission checks - use server_enter_space /
// server_leave_space for anything driven by a client request.
server_transfer_client :: proc(s: ^Server, user_id: u32, dest_id: SpaceId, pos: raylib.Vector2) -> bool {
    c := server_client(s, user_id)
    if c == nil { return false }
    dest := server_get_space(s, dest_id)
    if dest == nil { return false }
    if c.space == dest_id { return true }
    src := server_get_space(s, c.space)
    if src == nil { return false }

    e, ok := server_remove_entity(s, src, game.EntityHandle(user_id))
    if !ok { return false }
    e.body.x = pos.x
    e.body.y = pos.y
    e.move_to = pos
    e.move_origin = pos
    e.last_sent = e.entity
    server_add_entity(s, dest, e)
    c.space = dest_id

    server_maybe_free_room(s, src) // src may be gone after this line

    send_space_changed(s, c, dest_id, pos)
    send_full_sync(s, dest, c)
    return true
}

// Client-requested: enter `dest_id`. Remembers where the player came from so
// server_leave_space can bring them back.
server_enter_space :: proc(s: ^Server, user_id: u32, dest_id: SpaceId, pos := SPAWN_POS) -> error {
    c, _, e := server_player(s, user_id)
    if c == nil { return {"unknown player", false} }
    if e == nil { return {"player has no entity", false} }
    if c.no_send { return {"game has not started", false} }
    if c.space == dest_id { return {"you are already in that space", false} }
    if server_get_space(s, dest_id) == nil { return {"that space does not exist", false} }
    if f32(e.health) <= 0 { return {"you are dead", false} }

    // TODO: real entry validation - is the player standing at a portal /
    // dungeon entrance, is the room full or locked, party/level checks...
    // Right now any client can enter any existing space.

    from_space := c.space
    from_pos   := game.rect_pos(e.body)

    // `e` is invalid after the transfer, so don't touch it below.
    if !server_transfer_client(s, user_id, dest_id, pos) {
        return {"could not enter that space", false}
    }
    c.return_space = from_space
    c.return_pos   = from_pos
    return {"", true}
}

// Client-requested: leave the current space and go back to where the player
// entered it from (or the open world spawn if that no longer exists).
server_leave_space :: proc(s: ^Server, user_id: u32) -> error {
    c, _, e := server_player(s, user_id)
    if c == nil { return {"unknown player", false} }
    if e == nil { return {"player has no entity", false} }
    if c.no_send { return {"game has not started", false} }
    if c.space == OPEN_WORLD_ID { return {"you are already in the open world", false} }

    dest := c.return_space
    pos  := c.return_pos
    if dest == c.space || server_get_space(s, dest) == nil {
        dest = OPEN_WORLD_ID
        pos  = SPAWN_POS
    }

    if !server_transfer_client(s, user_id, dest, pos) {
        return {"could not leave this space", false}
    }
    c.return_space = OPEN_WORLD_ID
    c.return_pos   = SPAWN_POS
    return {"", true}
}

// ---------------------------------------------------------------------
// Projectiles & abilities
// ---------------------------------------------------------------------

space_spawn_projectile :: proc(s: ^Server, sp: ^Space, proj: game.Projectile) -> bool {
    if sp.projectiles_count >= PROJECTILES_COUNT {
        fmt.println("projectile limit reached in space", sp.id)
        return false
    }
    p := proj
    p.id = s.next_projectile_id
    s.next_projectile_id += 1
    p.active = true

    sp.projectiles[sp.projectiles_count] = p
    sp.projectiles_count += 1

    append(&sp.events, game.ProjectileEvent{
        kind = .SPAWN_PROJECTILE,
        data = game.SpawnProjectileMsg{projectile = p},
    })
    return true
}

cast_ability :: proc(s: ^Server, sp: ^Space, caster: ^ServerEntity, index: u8, target: raylib.Vector2) {
    if index >= ABILITIES_COUNT {
        fmt.printfln("Ability index out of range: %d of %d.", index, ABILITIES_COUNT)
        return
    }
    ua := caster.abilities[index]
    if !ua.active {
        fmt.println("Ability", index, "is inactive.")
        return
    }
    ability, ok := s.abilities[ua.ability_id]
    if !ok {
        fmt.println("Unknown ability id:", ua.ability_id)
        return
    }
    res := ability.action(s, sp, caster, ua.ability_id, ua.level, target)
    if !res.ok {
        fmt.println("Ability failed:", res.error)
    }
}

// ---------------------------------------------------------------------
// Incoming messages from clients
// ---------------------------------------------------------------------

handle_user_msg :: proc(s: ^Server, buf: ^buffer_io.Buffer, endpoint: net.Endpoint) {
    msg := game.unpack_server_message(buf)

    sync.mutex_lock(&s.lock)
    defer sync.mutex_unlock(&s.lock)

    switch msg.kind {
    case .CONNECT:
        d := msg.data.(game.ConnectMsg)
        server_connect_client(s, d.user_id, endpoint)

    case .START_GAME:
        d := msg.data.(game.StartGameMsg)
        c := server_client(s, d.user_id)
        if c == nil {
            fmt.println("START_GAME from unknown user:", d.user_id)
            return
        }
        c.no_send = false
        fmt.println("Starting game for:", d.user_id)

    case .PING:
        d := msg.data.(game.PingMsg)
        c := server_client(s, d.user_id)
        if c == nil {
            fmt.println("PING from unknown user:", d.user_id)
            return
        }
        c.last_ping = time.now()

        b := game.init_send_message()
        game.pack_server_message(&b, game.Msg{
            kind = .PING_RESPOND,
            data = game.PingRespondMsg{id = d.id},
        })
        game.send_message(s.socket, endpoint, &b)

    case .USER_MSG:
        d := msg.data.(game.UserMsg)
        c, sp, e := server_player(s, d.user_id)
        if e == nil {
            fmt.println("USER_MSG from unknown user:", d.user_id)
            return
        }

        // NOTE: after enter/leave space, sp and e are invalid - don't use them
        // past those cases.
        switch v in d.data {
        case game.MoveMsg:
            e.move_to.x = v.pos.x
            e.move_to.y = v.pos.y
            e.move_origin.x = e.body.x
            e.move_origin.y = e.body.y

        case game.AbilityMsg:
            cast_ability(s, sp, e, v.user_ability_index, v.direction)

        case game.DirectionMsg:
            e.facing = v.direction

        case game.EnterSpaceMsg:
            if res := server_enter_space(s, d.user_id, SpaceId(v.space_id)); !res.ok {
                send_string_msg(s, c, res.error, .ERROR)
            }

        case game.LeaveSpaceMsg:
            if res := server_leave_space(s, d.user_id); !res.ok {
                send_string_msg(s, c, res.error, .ERROR)
            }
        }

    case .GET_STATE:
        // no payload / not currently used

    case .Invalid, .GAME_DATA, .GAME_MSG, .PING_RESPOND, .STRING_MSG:
        fmt.println("Server received an invalid or server-only message")
    }
}

handle_receiver_loop :: proc(s: ^Server) {
    buf := buffer_io.buffer_make(1024)
    for {
        n, endpoint, err := net.recv_udp(s.socket, buf.data[:])
        if err != .None {
            fmt.println(err)
            panic("recevied error")
        }
        if n == 0 {
            panic("Received 0 bytes?")
        }
        buf.len = n
        handle_user_msg(s, &buf, endpoint)
        free_all(context.temp_allocator)
        buffer_io.buffer_reset(&buf)
    }
}

// ---------------------------------------------------------------------
// GameData construction (per tick, and full syncs on connect / transfer)
// ---------------------------------------------------------------------

build_user_data :: proc(e: ^ServerEntity) -> game.UserData {
    u := game.UserData{}
    u.energy = e.energy
    for i in 0 ..< ABILITIES_COUNT {
        a := e.abilities[i]
        u.abilities[i].active     = 1 if a.active else 0
        u.abilities[i].ability_id = a.ability_id
        u.abilities[i].level      = a.level
        u.abilities[i].cooldown   = a.cooldown
    }
    u.move_to = e.move_to
    return u
}

// Allocates its result slices with context.temp_allocator - callers must
// free_all(context.temp_allocator) once they're done sending it.
//
// Per-tick (non-full) builds advance each entity's `last_sent` and drain the
// space's projectile and entity events, so call it exactly once per space
// per send.
build_game_data :: proc(sp: ^Space, full_sync: bool) -> game.GameData {
    data := game.GameData{full_sync = full_sync, space_id = u32(sp.id)}

    entities := make([dynamic]game.EntityUpdate, 0, len(sp.entities), context.temp_allocator)
    for h, &e in sp.entities {
        all := full_sync || e.needs_full_delta
        delta := game.get_entity_delta(e.last_sent, e.entity, all = all)
        if !full_sync {
            e.last_sent = e.entity
            e.needs_full_delta = false
        }
        append(&entities, game.EntityUpdate{id = u32(h), role = entity_role(&e), delta = delta})
    }
    data.entities = entities[:]

    if full_sync {
        // a snapshot already reflects every past event, and the queued
        // events still belong to the next per-tick send for everyone else
        full := make([]game.Projectile, sp.projectiles_count, context.temp_allocator)
        copy(full, sp.projectiles[:sp.projectiles_count])
        data.full_projectiles = full
    } else {
        events := make([]game.ProjectileEvent, len(sp.events), context.temp_allocator)
        copy(events, sp.events[:])
        clear(&sp.events)
        data.projectile_events = events

        entity_events := make([]game.EntityEvent, len(sp.entity_events), context.temp_allocator)
        copy(entity_events, sp.entity_events[:])
        clear(&sp.entity_events)
        data.entity_events = entity_events
    }
    return data
}

// Complete, consistent snapshot of a space for one client.
send_full_sync :: proc(s: ^Server, sp: ^Space, c: ^Client) {
    data := build_game_data(sp, full_sync = true)
    if e := space_get_entity(sp, game.EntityHandle(c.user_id)); e != nil {
        data.user_data = build_user_data(e)
    }
    b := game.init_send_message()
    game.pack_server_message(&b, game.Msg{kind = .GAME_DATA, data = data})
    game.send_message(s.socket, c.endpoint, &b)
}

// ---------------------------------------------------------------------
// Simulation
// ---------------------------------------------------------------------

// Segment a->b vs rectangle r (slab method). On a hit, `t` is how far along
// the segment the first contact is, 0 = at `a`, 1 = at `b`. A segment that
// starts inside the rect hits at t = 0.
segment_rect_hit :: proc(a, b: raylib.Vector2, r: raylib.Rectangle) -> (t: f32, hit: bool) {
    d := b - a
    t_min := f32(0)
    t_max := f32(1)

    // x slab
    if abs(d.x) < 1e-6 {
        if a.x < r.x || a.x > r.x + r.width { return 0, false }
    } else {
        inv := 1 / d.x
        t1 := (r.x - a.x) * inv
        t2 := (r.x + r.width - a.x) * inv
        if t1 > t2 { t1, t2 = t2, t1 }
        t_min = max(t_min, t1)
        t_max = min(t_max, t2)
        if t_min > t_max { return 0, false }
    }

    // y slab
    if abs(d.y) < 1e-6 {
        if a.y < r.y || a.y > r.y + r.height { return 0, false }
    } else {
        inv := 1 / d.y
        t1 := (r.y - a.y) * inv
        t2 := (r.y + r.height - a.y) * inv
        if t1 > t2 { t1, t2 = t2, t1 }
        t_min = max(t_min, t1)
        t_max = min(t_max, t2)
        if t_min > t_max { return 0, false }
    }

    return t_min, true
}

// Segment a->b vs the map's walls. check_point_map_collisions only tests a
// single point, so sample the segment every PROJECTILE_WALL_STEP pixels or
// less. Returns the t (0..1) of the first sample inside a wall. Resolution
// is limited by the step size: walls thinner than it can still be skipped.
segment_wall_hit :: proc(sp: ^Space, a, b: raylib.Vector2) -> (t: f32, hit: bool) {
    d := b - a
    length := raylib.Vector2Length(d)
    steps := max(int(math.ceil(length / PROJECTILE_WALL_STEP)), 1)
    for i in 1 ..= steps {
        ti := f32(i) / f32(steps)
        if game.check_point_map_collisions(&sp.gmap, a + d * ti) {
            return ti, true
        }
    }
    return 0, false
}

// Shared by players and NPCs: walk towards move_to, then resolve wall collisions.
entity_update_movement :: proc(sp: ^Space, e: ^ServerEntity, dt: f32) {
    current_pos := game.rect_pos(e.body)
    d := raylib.Vector2Normalize(e.move_to - current_pos)
    mag := game.ENTITY_SPEED * dt
    next_pos := current_pos + d * mag

    reached := raylib.Vector2Distance(current_pos, e.move_to) <=
               raylib.Vector2Distance(current_pos, next_pos)

    target := e.move_to if reached else next_pos
    e.body.x = target.x
    e.body.y = target.y

    // 3 iterations because collision checks one wall at a time, so if the
    // entity's colliding against two perpendicular walls only one is
    // resolved per pass. Anything left over gets resolved next tick.
    for _ in 0 ..< 3 {
        v, hit := game.check_entity_map_collisions(&sp.gmap, e.entity)
        if !hit { break }
        if raylib.Vector2Distance(current_pos, v) < 0.25 {
            e.move_to = v
        }
        e.body.x = v.x
        e.body.y = v.y
    }

    if e.body.width <= 1 || e.body.height <= 1 {
        fmt.println(e^)
        panic("body size too small")
    }
}

npc_update :: proc(sp: ^Space, e: ^ServerEntity, dt: f32) {
    switch e.npc.behavior {
    case .Idle, .Shopkeeper:
        // stand still

    case .Wander:
        e.npc.wander_timer -= dt
        if e.npc.wander_timer <= 0 {
            e.npc.wander_timer = 2 + rand.float32() * 4
            angle := rand.float32() * math.TAU
            dist  := rand.float32() * e.npc.wander_radius
            e.move_to = e.npc.home + raylib.Vector2{math.cos(angle), math.sin(angle)} * dist
            e.move_origin = game.rect_pos(e.body)
        }

    case .Hostile:
        pos := game.rect_pos(e.body)
        best := f32(NPC_AGGRO_RADIUS)
        found := false
        for _, &other in sp.entities {
            if other.kind != .Player { continue }
            dist := raylib.Vector2Distance(pos, game.rect_pos(other.body))
            if dist < best {
                best = dist
                e.move_to = game.rect_pos(other.body)
                found = true
            }
        }
        if !found { e.move_to = pos } // lost target: stop
        // TODO: attack when in range (use entity_apply_damage + server_kill_entity)
    }
}

ProjectileOutcome :: enum {
    Flying,     // still in the air, keep it
    HitEntity,  // hit a targetable entity (handle returned alongside)
    HitWall,
    OutOfRange,
}

// Advances a projectile and reports what happened to it. The whole path from
// the old position to the new one is tested (not just the end point), so a
// fast projectile can't skip over an entity's corner or a thin wall. If
// several things lie on the path, the closest one to the start wins.
//
// Pure with respect to entities: it never mutates them, the caller applies
// any hit. For every outcome other than .Flying the projectile should be
// removed; on a hit its position is the impact point, and its `id` is still
// valid for the REMOVE_PROJECTILE event.
update_projectile :: proc(sp: ^Space, last_p: game.Projectile, dt: f32,
) -> (p: game.Projectile, outcome: ProjectileOutcome, hit: game.EntityHandle) {
    p = last_p
    from := last_p.position
    to   := from + raylib.Vector2Normalize(last_p.direction) * last_p.speed * dt
    p.position = to

    best_t := f32(2) // anything real is <= 1

    for h, &e in sp.entities {
        if h == last_p.owner || !e.targetable { continue }
        if t, ok := segment_rect_hit(from, to, e.body); ok && t < best_t {
            best_t  = t
            hit     = h
            outcome = .HitEntity
        }
    }

    if t, ok := segment_wall_hit(sp, from, to); ok && t < best_t {
        best_t  = t
        hit     = 0
        outcome = .HitWall
    }

    if outcome != .Flying {
        p.position = from + (to - from) * best_t
        return
    }

    if raylib.Vector2Distance(p.position, last_p.origin) > p.range {
        outcome = .OutOfRange
    }
    return
}

space_update :: proc(s: ^Server, sp: ^Space, dt: f32) {
    for _, &e in sp.entities {
        if e.kind == .Npc {
            npc_update(sp, &e, dt)
        }
        entity_update_movement(sp, &e, dt)
    }

    i := u32(0)
    for i < sp.projectiles_count {
        p := sp.projectiles[i]
        np, outcome, hit_h := update_projectile(sp, p, dt)

        // Entities are only mutated here, after update_projectile is done
        // iterating sp.entities. A kill may remove the entity from the map.
        if outcome == .HitEntity {
            space_on_projectile_hit(s, sp, np, hit_h)
        }

        if outcome != .Flying {
            append(&sp.events, game.ProjectileEvent{
                kind = .REMOVE_PROJECTILE,
                data = game.RemoveProjectileMsg{projectile_id = np.id},
            })
            last := sp.projectiles_count - 1
            sp.projectiles[i] = sp.projectiles[last]
            sp.projectiles_count -= 1
            // don't increment i - the projectile swapped into this slot still needs processing
            continue
        }

        sp.projectiles[i] = np
        i += 1
    }
}

server_update :: proc(s: ^Server, dt: f32) {
    sync.mutex_lock(&s.lock)
    defer sync.mutex_unlock(&s.lock)

    // the open world always simulates; rooms only while somebody is inside
    space_update(s, s.open_world, dt)
    for _, sp in s.rooms {
        if sp.player_count > 0 {
            space_update(s, sp, dt)
        }
    }
}

// ---------------------------------------------------------------------
// Sending
// ---------------------------------------------------------------------

send_space_updates :: proc(s: ^Server, sp: ^Space, now: time.Time, timed_out: ^[dynamic]u32) {
    if sp.player_count == 0 {
        clear(&sp.events)
        clear(&sp.entity_events)
        return
    }

    shared := build_game_data(sp, full_sync = false)

    for uid, &c in s.clients {
        if c.space != sp.id || c.no_send { continue }

        if time.diff(c.last_ping, now) > MAX_TIMEOUT {
            append(timed_out, uid)
            continue
        }

        e := space_get_entity(sp, game.EntityHandle(uid))
        if e == nil { continue }

        data := shared
        data.user_data = build_user_data(e)

        b := game.init_send_message()
        game.pack_server_message(&b, game.Msg{kind = .GAME_DATA, data = data})
        if err := game.send_message(s.socket, c.endpoint, &b); err != .None {
            fmt.println("error sending to client", uid, err)
        }
    }
}

server_send_updates :: proc(s: ^Server) {
    sync.mutex_lock(&s.lock)
    defer sync.mutex_unlock(&s.lock)

    now := time.now()
    timed_out := make([dynamic]u32, context.temp_allocator)

    send_space_updates(s, s.open_world, now, &timed_out)
    for _, sp in s.rooms {
        send_space_updates(s, sp, now, &timed_out)
    }

    for uid in timed_out {
        fmt.println("Removing:", uid, "from", len(s.clients), "clients")
        server_remove_client(s, uid)
    }
}

// server tick: [simulate] -> every 4th tick, [send GameData to everyone]
handle_sender_loop :: proc(s: ^Server) {
    duration := time.Duration(10) * time.Millisecond
    dt: f32 = 0
    i := 0
    for {
        start := time.now()
        server_update(s, dt)
        if i < 3 {
            i += 1
        } else {
            i = 0
            server_send_updates(s)
        }
        free_all(context.temp_allocator)

        elapsed := time.since(start)
        if elapsed < duration {
            time.sleep(duration - elapsed)
        }
        dt = f32(time.since(start)) / f32(time.Second)
    }
}

thread_receiver_fn :: proc(data: rawptr) {
    handle_receiver_loop((^Server)(data))
}
thread_sender_fn :: proc(data: rawptr) {
    handle_sender_loop((^Server)(data))
}

// ---------------------------------------------------------------------
// Startup
// ---------------------------------------------------------------------

// Temporary: some NPCs so there's something to look at.
server_seed_world :: proc(s: ^Server) {
    ow := s.open_world
    server_spawn_npc(s, ow, {200, 200}, random_texture(s), .Shopkeeper)
    server_spawn_npc(s, ow, {300, 150}, random_texture(s), .Wander)
    server_spawn_npc(s, ow, {100, 300}, random_texture(s), .Wander)
    // server_create_room(s, .Town, persistent = true)
}

main :: proc() {
    s := new(Server)
    server_init(s)
    init_server_socket(s)
    server_seed_world(s)

    when ODIN_OS == .Windows {
        SIO_UDP_CONNRESET :: 0x9800000C
        bNewBehavior: windows.BOOL = false
        bytesReturned: u32
        if windows.WSAIoctl(cast(windows.SOCKET)s.socket, windows.SIO_UDP_CONNRESET,
            &bNewBehavior,
            size_of(bNewBehavior),
            nil, 0, &bytesReturned,
            nil,
            nil) != 0 {
            panic("Failed to set SIO_UDP_CONNRESET for windows socket")
        }
        fmt.println("Running on Windows.")
    } else when ODIN_OS == .Linux {
        fmt.println("Running on Linux.")
    } else {
        fmt.panicf("Running on an unsupported/unidentified OS.\n")
    }

    t_receiver := thread.create_and_start_with_data(data = s, fn = thread_receiver_fn)
    t_sender   := thread.create_and_start_with_data(data = s, fn = thread_sender_fn)

    thread.join(t_receiver)
    thread.join(t_sender)

    delete(s.assets.assets)
    delete(s.clients)
    delete(s.entity_index)
    net.close(s.socket)
}
