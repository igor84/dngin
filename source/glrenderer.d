module glrenderer;

import winmain;
import derelict.opengl;

alias GLVertexShader = GLShader!GL_VERTEX_SHADER;
alias GLFragmentShader = GLShader!GL_FRAGMENT_SHADER;

struct GLShader(GLenum type) if (type == GL_VERTEX_SHADER || type == GL_FRAGMENT_SHADER) {
    GLuint id;

    this(const(char)[] src) {
        initWith(src);
    }
    
    bool initWith(const(char)[] src) in { assert(id == 0); }
    body {
        id = glCreateShader(type);
        string shaderHeader = "#version 330 core\n";
        const(char*)[2] allSrc = [shaderHeader.ptr, src.ptr];
        GLint[2] lengths = [cast(GLint)shaderHeader.length, cast(GLint)src.length];
        glShaderSource(id, allSrc.length, allSrc.ptr, lengths.ptr);
        glCompileShader(id);

        GLint success;
        glGetShaderiv(id, GL_COMPILE_STATUS, &success);

        if (!success) {
            del();

            GLsizei length;
            char[512] infoLog;
            glGetShaderInfoLog(id, 512, &length, infoLog.ptr);
            static if (type == GL_VERTEX_SHADER) {
                log!"Vertex shader compilation failed: %s"(infoLog[0..length]);
            } else {
                log!"Fragment shader compilation failed: %s"(infoLog[0..length]);
            }
        }

        return success != 0;
    }

    void del() {
        if (id == 0) return;
        glDeleteShader(id);
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

    bool init(GLuint vertexShader, GLuint fragmentShader) in { assert(id == 0); }
    body {
        id = glCreateProgram();
        glAttachShader(id, vertexShader);
        glAttachShader(id, fragmentShader);
        glLinkProgram(id);

        GLint success;
        glGetProgramiv(id, GL_LINK_STATUS, &success);

        if (!success) {
            del();

            GLsizei length;
            char[512] infoLog;
            glGetProgramInfoLog(id, 512, &length, infoLog.ptr);
            log!"Shader linking failed: %s"(infoLog[0..length]);
        }
        return success != 0;
    }

    pragma(inline, true)
    void use() {
        glUseProgram(id);
    }

    void setVec4(const(char)[] name, float x, float y, float z, float w) { 
        glUniform4f(glGetUniformLocation(id, name.ptr), x, y, z, w); 
    }

    void del() {
        if (id == 0) return;
        glDeleteProgram(id);
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

    this(GLfloat[] vertices, GLuint[] indices, GLVertexAttrib[] vertexAttribs) {
        glGenVertexArrays(1, &id);
        glBindVertexArray(id);

        GLuint vbo, ebo;
        glGenBuffers(1, &vbo);
        glGenBuffers(1, &ebo);

        glBindBuffer(GL_ARRAY_BUFFER, vbo);
        glBufferData(GL_ARRAY_BUFFER, vertices.length * GLfloat.sizeof, vertices.ptr, GL_STATIC_DRAW);

        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ebo);
        glBufferData(GL_ELEMENT_ARRAY_BUFFER, indices.length * GLuint.sizeof, indices.ptr, GL_STATIC_DRAW);

        foreach (GLuint index, vAttrib; vertexAttribs) {
            glVertexAttribPointer(index, vAttrib.components, vAttrib.type, GL_FALSE, vAttrib.stride, cast(void*)vAttrib.offset);
            glEnableVertexAttribArray(index);
        }

        // note that this is allowed, the call to glVertexAttribPointer registered VBO as the vertex attribute's bound vertex buffer object so afterwards we can safely unbind
        glBindBuffer(GL_ARRAY_BUFFER, 0); 
    }

    void draw() {
        glBindVertexArray(id);
        glDrawElements(GL_TRIANGLES, 6, GL_UNSIGNED_INT, null);
    }
}
