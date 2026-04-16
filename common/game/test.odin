package game

import "core:fmt";
import "core:math"
import "vendor:raylib";


base_projectile_data :: struct {
};
// index: ability index in entity
init_base :: proc(game:^ Game, e: ^Entity, index: int) -> Ability {
    fmt.println("Init test ability");
    a :Ability;
    a.owner = e.handle;
    a.act = proc(game: ^Game,  self: ^Ability, owner: ^Entity) {
        if self.cooldown > 0 {
            fmt.println("ablity cooldown", self.cooldown);
            return;
        }
        fmt.println("Act called.");
        p := init_test_projectile();
        p.kind = .PkBase;
        p.dir = raylib.Vector2Normalize(owner.direction);
        p.origin = rect_pos(owner.body) + 0.5 * rect_size(owner.body);
        p.pos = p.origin;
        p.range = 750;
        p.radius = 2.0;
        p.speed = 800.0;
        p.damage = 5 + math.exp(f32(self.level)*0.2); // random?
        self.cooldown = self.cooldown_time; // set to time
        fmt.println("cooldown,", self.cooldown, self.cooldown_time);
        game_add_projectile(game, &p);
    }
    a.update = proc(game: ^Game,  self: ^Ability, owner: ^Entity) {
        self.cooldown -= game.dt;
        if self.cooldown_time < 0 { self.cooldown = 0; }
    }

    a.cooldown_time = 0.5;
    return a;
}

init_test_projectile :: proc() -> Projectile { 
    p: Projectile;
    p.kind = .PkBase;
    p.update = proc(game: ^Game, self: ^Projectile) {
        new := self.pos + self.dir * self.speed * game.dt;
        to_remove := 0;
        if raylib.Vector2Length(new - self.origin) >= self.range {
            new = self.origin + self.dir * self.range; // set to max
            to_remove = 1; // to remove
        }
        // check collisions
        collisions := game_get_entity_line_collisions(game, self.pos, new);
        to_hit := -1;
        shortest : f32 = 0.0;
        for c in collisions {
            if c.handle == self.owner_handle { // not hit self
                continue;
            }
            if to_hit == -1 {
                to_hit = c.handle;
            } else if c.dist < shortest {
                to_hit = c.handle;
            }
        }
        // if there's a hit
        if to_hit != -1 {
            dmg : Damage = self.damage;
            game_damage_entity(game, to_hit, dmg);
            to_remove = 1;
        }
        if to_remove == 1 {
            game_remove_projectile(game, self.index);
        }
        self.pos = new;
    }
    p.draw = proc(camera: rect, self: ^Projectile) {
        // do +- radius cus radius goes behind and in from of projectile
        cam_pos := apply_camera(camera, self.pos);
        if cam_pos.x + self.radius < 0 ||
            cam_pos.x - self.radius > camera.width {
                return;
        }
        if cam_pos.y + self.radius < 0 ||
            cam_pos.y - self.radius > camera.height {
                return;
        }
        raylib.DrawCircleV(cam_pos, self.radius, raylib.BLACK);
    }
    return p;
}
