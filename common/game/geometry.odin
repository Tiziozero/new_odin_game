package game

import "core:math"

point_rect_dist :: proc(p: vec2, r: rect) -> f32 {
    dx := max(r.x - p.x, 0)
    dx  = max(dx, p.x - (r.x + r.width))
    dy := max(r.y - p.y, 0)
    dy  = max(dy, p.y - (r.y + r.height))
    return math.sqrt(dx*dx + dy*dy)
}

point_in_rect :: proc(p: vec2, r: rect) -> bool {
    return p.x >= r.x && p.x <= r.x + r.width &&
           p.y >= r.y && p.y <= r.y + r.height
}

circle_rect_intersect :: proc(c: vec2, r: f32, re: rect) -> bool {
    closest_x := clamp(c.x, re.x, re.x + re.width)
    closest_y := clamp(c.y, re.y, re.y + re.height)
    dx := c.x - closest_x
    dy := c.y - closest_y
    return (dx*dx + dy*dy) <= r*r
}

line_intersect :: proc(p1, p2, q1, q2: vec2) -> bool {
    s1 := vec2{p2.x - p1.x, p2.y - p1.y}
    s2 := vec2{q2.x - q1.x, q2.y - q1.y}
    denom := -s2.x*s1.y + s1.x*s2.y
    s := (-s1.y * (p1.x - q1.x) + s1.x * (p1.y - q1.y)) / denom
    t := ( s2.x * (p1.y - q1.y) - s2.y * (p1.x - q1.x)) / denom
    return s >= 0 && s <= 1 && t >= 0 && t <= 1
}

line_rect_intersect :: proc(p1, p2: vec2, r: rect) -> bool {
    if point_in_rect(p1, r) || point_in_rect(p2, r) do return true
    tl := vec2{r.x,            r.y           }
    tr := vec2{r.x + r.width,  r.y           }
    bl := vec2{r.x,            r.y + r.height}
    br := vec2{r.x + r.width,  r.y + r.height}
    return line_intersect(p1, p2, tl, tr) ||
           line_intersect(p1, p2, tr, br) ||
           line_intersect(p1, p2, br, bl) ||
           line_intersect(p1, p2, bl, tl)
}

point_segment_dist :: proc(p, a, b: vec2) -> f32 {
    ab := vec2{b.x - a.x, b.y - a.y}
    ap := vec2{p.x - a.x, p.y - a.y}
    t  := clamp((ap.x*ab.x + ap.y*ab.y) / (ab.x*ab.x + ab.y*ab.y), 0, 1)
    closest := vec2{a.x + t*ab.x, a.y + t*ab.y}
    dx := p.x - closest.x
    dy := p.y - closest.y
    return math.sqrt(dx*dx + dy*dy)
}

line_segment_shortest_dist :: proc(a, b, c, d: vec2) -> f32 {
    return min(
        min(point_segment_dist(a, c, d), point_segment_dist(b, c, d)),
        min(point_segment_dist(c, a, b), point_segment_dist(d, a, b)),
    )
}

line_rect_shortest_dist :: proc(p1, p2: vec2, body: rect) -> f32 {
    tl := vec2{body.x,             body.y            }
    tr := vec2{body.x + body.width, body.y            }
    bl := vec2{body.x,             body.y + body.height}
    br := vec2{body.x + body.width, body.y + body.height}
    return min(
        min(line_segment_shortest_dist(p1, p2, tl, tr),
            line_segment_shortest_dist(p1, p2, bl, br)),
        min(line_segment_shortest_dist(p1, p2, tl, bl),
            line_segment_shortest_dist(p1, p2, tr, br)),
    )
}

