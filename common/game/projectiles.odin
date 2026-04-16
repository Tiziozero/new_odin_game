package game

import "vendor:raylib"
ProjectileData :: union {
    base_projectile_data,
};
ProjectileKind :: enum {
    PkBase,
};
ProjectileHandler :: proc(game: ^Game, self: ^Projectile);
ProjectileDrawHandler :: proc(camera: rect, self: ^Projectile);
Projectile :: struct { // effect and what not
    update: ProjectileHandler,
    draw: ProjectileDrawHandler,
    kind: ProjectileKind,
    data: ProjectileData,
    index, active: int, // index in projectiles array, check if active

    pos, dir, origin: raylib.Vector2,
    damage, range, radius, speed: f32,
    owner_handle: int,
};
