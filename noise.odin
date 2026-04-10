package main
import "core:math"
noise_hash :: proc(x, y: int) -> f32 {
    n := x * 1619 + y * 31337
    n = (n << 13) ~ n
    return 1.0 - f32((n * (n * n * 15731 + 789221) + 1376312589) & 0x7fffffff) / 1073741824.0
}

smoothstep :: proc(t: f32) -> f32 {
    return t * t * (3 - 2 * t)
}

noise2d :: proc(x, y: f32) -> f32 {
    ix := int(math.floor(x))
    iy := int(math.floor(y))
    fx := x - f32(ix)
    fy := y - f32(iy)

    // corners
    a := noise_hash(ix,     iy)
    b := noise_hash(ix + 1, iy)
    c := noise_hash(ix,     iy + 1)
    d := noise_hash(ix + 1, iy + 1)

    // smooth the interpolation
    ux := smoothstep(fx)
    uy := smoothstep(fy)

    // bilinear interpolation
    return math.lerp(math.lerp(a, b, ux), math.lerp(c, d, ux), uy)
}
fbm :: proc(x, y: f32, octaves: int) -> f32 {
    value    : f32 = 0
    amplitude: f32 = 0.5
    frequency: f32 = 1

    for i in 0..<octaves {
        value     += noise2d(x * frequency, y * frequency) * amplitude
        amplitude *= 0.5
        frequency *= 2
    }
    return value
}
