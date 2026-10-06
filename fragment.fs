#version 330

in vec2 fragTexCoord;

uniform sampler2D texture0;
uniform float time;

out vec4 finalColor;

void main()
{
    vec2 uv = fragTexCoord;

    uv.x += sin(uv.y * 40.0 + time * 2.0) * 0.01;

    finalColor = texture(texture0, uv);
}
