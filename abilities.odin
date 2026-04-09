package main
import "core:math"

AbilityCtx :: struct {
};

// just use owner in init
AbilityHandler :: proc(game: ^game, self: ^Ability, owner: ^Entity);
Ability :: struct {
    active, index, owner, level: int, // it's index in the enities ablity
    cooldown, cooldown_time, cost: f32,
    init, act: AbilityHandler,
};


// test for now
scale_damage :: proc(
    level: f32,
    max_level: f32,
    base_damage: f32,
    max_damage: f32,
    a: f32, // exponent for x^a
) -> f32 {
    // Normalize level to [0, 1]
    t := level / max_level;

    // Clamp just in case
    if t < 0 {
        t = 0;
    } else if t > 1 {
        t = 1;
    }

    // g(t) = (t^a * ln(t+1)) / ln(2)
    g := (math.pow(t, a) * math.ln_f32(t + 1)) / math.ln_f32(2);

    // f(x) = base + (max - base) * g(t)
    return base_damage + (max_damage - base_damage) * g;
}
