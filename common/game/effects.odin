package game

EffectData :: union {
};
EffectKind :: enum {
};
EffectHandler :: proc(element: ^Effect);
Effect :: struct {
    update, draw: EffectHandler,
    kind: EffectKind,
    data: EffectData,
};
