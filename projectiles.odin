package main

import "vendor:raylib"
ProjectileData :: union {
    base_projectile_data,
};
ProjectileKind :: enum {
    PkBase,
};
ProjectileHandler :: proc(game: ^game, self: ^Projectile);
Projectile :: struct { // effect and what not
    update, draw: ProjectileHandler,
    kind: ProjectileKind,
    data: ProjectileData,
    index, active: int, // index in projectiles array, check if active

    pos, dir, origin: raylib.Vector2,
    damage, range, radius, speed: f32,
    owner_handle: int,
};
