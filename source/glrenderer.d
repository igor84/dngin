module glrenderer;

import derelict.opengl;
import std.experimental.logger.core;
import util.math;

mixin glContext!(GLVersion.gl45);
private GLContext ctx;

private V2 screenDim;

void initViewport(int width, int height) {
    screenDim = V2(width, height);
    ctx.glViewport(0, 0, width, height);
    initDefaultShaders();
    initDefaultGLObjects();
}

void clearColorBuffer(float r = 0f, float g = 0f, float b = 0f, float a = 0f) {
    ctx.glClearColor(r, g, b, a);
    ctx.glClear(GL_COLOR_BUFFER_BIT);
}

bool initGLContext() {
    return ctx.load() >= GLVersion.gl40;
}

pragma(inline, true)
GLShader GLVertexShader(const(char)[] src) {
    return GLShader(GL_VERTEX_SHADER, src);
}

pragma(inline, true)
GLShader GLFragmentShader(const(char)[] src) {
    return GLShader(GL_FRAGMENT_SHADER, src);
}

struct GLShader {
    GLuint id;

    this(uint type, const(char)[] src)
    in { assert(type == GL_VERTEX_SHADER || type == GL_FRAGMENT_SHADER); }
    body {
        initWith(type, src);
    }
    
    bool initWith(uint type, const(char)[] src)
    in {
        assert(type == GL_VERTEX_SHADER || type == GL_FRAGMENT_SHADER);
        assert(id == 0);
    }
    body {
        id = ctx.glCreateShader(type);
        string shaderHeader = "#version 330 core\n";
        const(char*)[2] allSrc = [shaderHeader.ptr, src.ptr];
        GLint[2] lengths = [cast(GLint)shaderHeader.length, cast(GLint)src.length];
        ctx.glShaderSource(id, allSrc.length, allSrc.ptr, lengths.ptr);
        ctx.glCompileShader(id);

        GLint success;
        ctx.glGetShaderiv(id, GL_COMPILE_STATUS, &success);

        if (!success) {
            del();

            GLsizei length;
            char[512] infoLog;
            ctx.glGetShaderInfoLog(id, 512, &length, infoLog.ptr);
            if (type == GL_VERTEX_SHADER) {
                infof("Vertex shader compilation failed: %s", infoLog[0..length]);
            } else {
                infof("Fragment shader compilation failed: %s", infoLog[0..length]);
            }
        }

        return success != 0;
    }

    void del() {
        if (id == 0) return;
        ctx.glDeleteShader(id);
        id = 0;
    }
}

struct GLShaderProgram {
    GLuint id;

    this(const(char)[] vertexShaderSrc, const(char)[] fragmentShaderSrc) {
        auto vs = GLVertexShader(vertexShaderSrc);
        auto fs = GLFragmentShader(fragmentShaderSrc);
        init(vs.id, fs.id);
        vs.del();
        fs.del();
    }

    this(GLuint vertexShader, GLuint fragmentShader) {
        init(vertexShader, fragmentShader);
    }

    bool init(GLuint vertexShader, GLuint fragmentShader)
    in { assert(id == 0); }
    body {
        id = ctx.glCreateProgram();
        ctx.glAttachShader(id, vertexShader);
        ctx.glAttachShader(id, fragmentShader);
        ctx.glLinkProgram(id);

        GLint success;
        ctx.glGetProgramiv(id, GL_LINK_STATUS, &success);

        if (!success) {
            del();

            GLsizei length;
            char[512] infoLog;
            ctx.glGetProgramInfoLog(id, 512, &length, infoLog.ptr);
            infof("Shader linking failed: %s", infoLog[0..length]);
        }

        return success != 0;
    }

    pragma(inline, true)
    void use() {
        ctx.glUseProgram(id);
    }

    pragma(inline, true)
    void setVec4(const(char)[] name, float x, float y, float z, float w) { 
        auto index = ctx.glGetUniformLocation(id, name.ptr);
        ctx.glUniform4f(index, x, y, z, w); 
    }

    pragma(inline, true)
    void setMat4(const(char)[] name, const(float)[] mat4x4) { 
        auto index = ctx.glGetUniformLocation(id, name.ptr);
        ctx.glUniformMatrix4fv(index, 1, GL_FALSE, mat4x4.ptr); 
    }

    pragma(inline, true)
    void setVec2Array(const(char)[] name, const(V2)[] vec2Array) { 
        auto index = ctx.glGetUniformLocation(id, name.ptr);
        ctx.glUniform2fv(index, cast(int)vec2Array.length, vec2Array[0].e.ptr); 
    }

    pragma(inline, true)
    void setVec3Array(const(char)[] name, const(V3)[] vec3Array) { 
        auto index = ctx.glGetUniformLocation(id, name.ptr);
        ctx.glUniform3fv(index, cast(int)vec3Array.length, vec3Array[0].e.ptr); 
    }

    void del() {
        if (id == 0) return;
        ctx.glDeleteProgram(id);
        id = 0;
    }
}

enum DefShader {
    none,
    colorRect,
    textureRect,

    count,
};

private GLShaderProgram[DefShader.count] defaultShaders;

private void initDefaultShaders() {
    immutable GLfloat[16] screenToClipSpace = [
        2f / screenDim.x, 0, 0, -1,
        0, -2f / screenDim.y, 0, 1,
        0, 0, 1, 0,
        0, 0, 0, 1,
    ];
    auto newShader = GLShaderProgram(
        q{
            layout (location = 0) in vec2 aPos;

            out vec3 ourColor;

            uniform mat4 screenToClipSpace;
            uniform vec4 coords;
            uniform vec3 colors[4];

            void main() {
                gl_Position = vec4(coords[uint(aPos.x)], coords[uint(aPos.y)], 0.0, 1.0) * screenToClipSpace;
                ourColor = colors[gl_VertexID];
            }
        },

        q{
            out vec4 FragColor;

            in vec3 ourColor;

            void main() {
                FragColor = vec4(ourColor, 1.0);
            }
        }
    );
    newShader.use();
    newShader.setMat4("screenToClipSpace", screenToClipSpace);
    defaultShaders[DefShader.colorRect] = newShader;
    newShader = GLShaderProgram(
        q{
            layout (location = 0) in vec2 aPos;

            out vec3 ourColor;
            out vec2 texCoord;

            uniform mat4 screenToClipSpace;
            uniform vec4 coords;
            uniform vec2 texCoords[4];

            void main() {
                gl_Position = vec4(coords[uint(aPos.x)], coords[uint(aPos.y)], 0.0, 1.0) * screenToClipSpace;
                texCoord = texCoords[gl_VertexID];
            }
        },

        q{
            out vec4 FragColor;

            in vec2 texCoord;

            uniform sampler2D fillTexture;

            void main() {
                FragColor = texture(fillTexture, texCoord);
            }
        }
    );
    newShader.use();
    newShader.setMat4("screenToClipSpace", screenToClipSpace);
    defaultShaders[DefShader.textureRect] = newShader;
}

struct GLVertexAttrib {
    GLint components;
    GLenum type;
    GLsizei stride;
    uint offset;
}

struct GLObject {
    GLuint id;

    this(GLfloat[] positions, GLuint[] indices, GLVertexAttrib[] vertexAttribs) {
        ctx.glGenVertexArrays(1, &id);
        ctx.glBindVertexArray(id);

        GLuint vbo, ebo;
        ctx.glGenBuffers(1, &vbo);
        ctx.glGenBuffers(1, &ebo);

        ctx.glBindBuffer(GL_ARRAY_BUFFER, vbo);
        ctx.glBufferData(GL_ARRAY_BUFFER, positions.length * typeof(positions[0]).sizeof, positions.ptr, GL_STATIC_DRAW);

        ctx.glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ebo);
        ctx.glBufferData(GL_ELEMENT_ARRAY_BUFFER, indices.length * GLuint.sizeof, indices.ptr, GL_STATIC_DRAW);

        foreach (GLuint index, vAttrib; vertexAttribs) {
            ctx.glVertexAttribPointer(index, vAttrib.components, vAttrib.type, GL_FALSE, vAttrib.stride, cast(void*)vAttrib.offset);
            ctx.glEnableVertexAttribArray(index);
        }

        // note that this is allowed, the call to glVertexAttribPointer registered VBO as the vertex attribute's
        // bound vertex buffer object so afterwards we can safely unbind
        ctx.glBindBuffer(GL_ARRAY_BUFFER, 0); 
    }

    void draw() {
        ctx.glBindVertexArray(id);
        ctx.glDrawElements(GL_TRIANGLES, 6, GL_UNSIGNED_INT, null);
    }
}

enum DefGLObject {
    none,
    rect,

    count,
}

private GLObject[DefGLObject.count] defaultGLObjects;

private void initDefaultGLObjects() {
    GLuint[6] rectIndices = [
        2, 1, 0,  // first Triangle
        3, 2, 0   // second Triangle
    ];
    // xpos, ypos where coords are in layout x1, y1, x2, y2 so xpos can be 0 or 2 and ypos can be 1 or 3
    GLfloat[4 * 2] positions = [0,1, 2,1, 2,3, 0,3];
    GLVertexAttrib[1] attribs = [{2, GL_FLOAT, 2 * GLfloat.sizeof, 0}];
    defaultGLObjects[DefGLObject.rect] = GLObject(positions, rectIndices, attribs);
}

uint createTexture(int width, int height, const(uint)[] pixels) {
    uint texture;
    ctx.glGenTextures(1, &texture);
    ctx.glBindTexture(GL_TEXTURE_2D, texture);
    // set the texture wrapping/filtering options (on the currently bound texture object)
    ctx.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);	
    ctx.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT);
    ctx.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    ctx.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    ctx.glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, pixels.ptr);
    return texture;
}

void drawRect(float x, float y, float w, float h, V3 color) {
    auto shader = defaultShaders[DefShader.colorRect];
    shader.use();
    shader.setVec4("coords", x, y, x + w, y + h);
    immutable V3[4] colors = [V3(1,0,0), V3(1,1,0), V3(0,1,0), V3(0,0,1)];
    shader.setVec3Array("colors", colors);
    
    defaultGLObjects[DefGLObject.rect].draw();
}

void drawImage(float x, float y, float w, float h, uint textureId) {
    auto shader = defaultShaders[DefShader.textureRect];
    shader.use();
    shader.setVec4("coords", x, y, x + w, y + h);
    immutable V2[4] texCoords = [V2(0,1), V2(1,1), V2(1,0), V2(0,0)];
    shader.setVec2Array("texCoords", texCoords);
    
    ctx.glBindTexture(GL_TEXTURE_2D, textureId);
    defaultGLObjects[DefGLObject.rect].draw();
}