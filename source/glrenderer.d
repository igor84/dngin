module glrenderer;

import derelict.opengl;
import std.experimental.logger.core;

mixin glContext!(GLVersion.gl45);
private GLContext ctx;

void initViewport(int width, int height) {
    ctx.glViewport(0, 0, width, height);
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

    @property static GLShaderProgram plainFill() {
        auto vertexShaderSrc = q{
            layout (location = 0) in vec3 aPos;
            layout (location = 1) in vec3 aColor;

            out vec3 ourColor;

            void main() {
                gl_Position = vec4(aPos, 1.0);
                ourColor = aColor;
            }
        };

        auto fragmentShaderSrc = q{
            out vec4 FragColor;

            in vec3 ourColor;

            void main() {
                FragColor = vec4(ourColor, 1f);
            }
        };

        return GLShaderProgram(vertexShaderSrc, fragmentShaderSrc);
    }

    @property static GLShaderProgram textureFill() {
        auto vertexShaderSrc = q{
            layout (location = 0) in vec3 aPos;
            layout (location = 1) in vec3 aColor;
            layout (location = 2) in vec2 aTexCoord;

            out vec3 ourColor;
            out vec2 texCoord;

            void main() {
                gl_Position = vec4(aPos, 1.0);
                ourColor = aColor;
                texCoord = aTexCoord;
            }
        };

        auto fragmentShaderSrc = q{
            out vec4 FragColor;

            in vec3 ourColor;
            in vec2 texCoord;

            uniform sampler2D fillTexture;

            void main() {
                FragColor = texture(fillTexture, texCoord);
            }
        };

        return GLShaderProgram(vertexShaderSrc, fragmentShaderSrc);
    }

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

    void setVec4(const(char)[] name, float x, float y, float z, float w) { 
        ctx.glUniform4f(ctx.glGetUniformLocation(id, name.ptr), x, y, z, w); 
    }

    void del() {
        if (id == 0) return;
        ctx.glDeleteProgram(id);
        id = 0;
    }
}

struct GLVertexAttrib {
    GLint components;
    GLenum type;
    GLsizei stride;
    uint offset;
}

struct GLObject {
    GLuint id;

    private GLuint vboId;

    @property static GLObject rect() {
        GLfloat[24] vertices = [
             0.5f,  0.5f, 0.0f, 1.0f, 1.0f, 0.0f,  // top right
             0.5f, -0.5f, 0.0f, 1.0f, 0.0f, 0.0f,  // bottom right
            -0.5f, -0.5f, 0.0f, 0.0f, 0.0f, 1.0f,  // bottom left
            -0.5f,  0.5f, 0.0f, 0.0f, 1.0f, 0.0f,  // top left 
        ];
        GLuint[6] indices = [  // note that we start from 0!
            0, 1, 3,  // first Triangle
            1, 2, 3   // second Triangle
        ];
        GLVertexAttrib[2] attribs = [
            {3, GL_FLOAT, 6 * GLfloat.sizeof, 0},
            {3, GL_FLOAT, 6 * GLfloat.sizeof, 3 * GLfloat.sizeof},
        ];
        return GLObject(vertices, indices, attribs);
    }

    @property static GLObject textureRect() {
        GLfloat[32] vertices = [
             0.5f,  0.5f, 0.0f,   1.0f, 1.0f, 0.0f,  1.0f, 1.0f,  // top right
             0.5f, -0.5f, 0.0f,   1.0f, 0.0f, 0.0f,  1.0f, 0.0f,  // bottom right
            -0.5f, -0.5f, 0.0f,   0.0f, 0.0f, 1.0f,  0.0f, 0.0f,  // bottom left
            -0.5f,  0.5f, 0.0f,   0.0f, 1.0f, 0.0f,  0.0f, 1.0f,  // top left 
        ];
        GLuint[6] indices = [  // note that we start from 0!
            0, 1, 3,  // first Triangle
            1, 2, 3   // second Triangle
        ];
        GLVertexAttrib[3] attribs = [
            {3, GL_FLOAT, 8 * GLfloat.sizeof, 0},
            {3, GL_FLOAT, 8 * GLfloat.sizeof, 3 * GLfloat.sizeof},
            {2, GL_FLOAT, 8 * GLfloat.sizeof, 6 * GLfloat.sizeof},
        ];
        return GLObject(vertices, indices, attribs);
    }

    this(GLfloat[] vertices, GLuint[] indices, GLVertexAttrib[] vertexAttribs) {
        ctx.glGenVertexArrays(1, &id);
        ctx.glBindVertexArray(id);

        GLuint vbo, ebo;
        ctx.glGenBuffers(1, &vbo);
        ctx.glGenBuffers(1, &ebo);

        ctx.glBindBuffer(GL_ARRAY_BUFFER, vbo);
        ctx.glBufferData(GL_ARRAY_BUFFER, vertices.length * GLfloat.sizeof, vertices.ptr, GL_STATIC_DRAW);

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

    void draw(uint textureId = 0) {
        if (textureId) ctx.glBindTexture(GL_TEXTURE_2D, textureId);
        ctx.glBindVertexArray(id);
        ctx.glDrawElements(GL_TRIANGLES, 6, GL_UNSIGNED_INT, null);
    }
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