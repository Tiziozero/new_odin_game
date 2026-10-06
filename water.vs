#version 330

in vec3 vertexPosition;
in vec2 vertexTexCoord;
in vec4 vertexColor;

uniform mat4 mvp;

out vec2 fragTexCoord;
out vec4 fragColor;
out vec2 fragPos; // position in render-target pixels (top-left origin)

void main()
{
    fragTexCoord = vertexTexCoord;
    fragColor    = vertexColor;
    fragPos      = vertexPosition.xy;
    gl_Position  = mvp * vec4(vertexPosition, 1.0);
}
