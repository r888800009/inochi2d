/*
    Copyright © 2020, Inochi2D Project
    Distributed under the 2-Clause BSD License, see LICENSE file.
    
    Authors: Luna Nielsen
*/
module inochi2d.render.dynmesh;
import inochi2d.math;
import inochi2d.render;
import bindbc.opengl;
import std.exception;
import std.algorithm.mutation : copy;

private GLuint vao;
private Shader dynMeshShader;
private Shader dynMeshDbg;
package(inochi2d) {
    void initDynMesh() {
        glGenVertexArrays(1, &vao);
        dynMeshShader = new Shader(import("dynmesh.vert"), import("dynmesh.frag"));
        dynMeshDbg = new Shader(import("dynmesh.vert"), import("dynmesh_dbg.frag"));
    }
}

/**
    A dynamic deformable textured mesh
*/
class DynMesh {
private:
    Shader shader;
    MeshData data;
    int activeTexture;
    GLuint ibo;
    GLuint vbo;
    GLuint uvbo;

    // View-projection matrix uniform location
    GLint mvp;

    // Whether this mesh is marked for an update
    bool marked;

    void setIndices() {
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ibo);
        glBufferData(GL_ELEMENT_ARRAY_BUFFER, data.indices.length*ushort.sizeof, data.indices.ptr, GL_STATIC_DRAW);
    }

    void genUVs() {
        // Generate the appropriate UVs
        vec2[] uvs = data.genUVsFor(activeTexture);

        glBindBuffer(GL_ARRAY_BUFFER, uvbo);
        glBufferData(GL_ARRAY_BUFFER, uvs.length*vec2.sizeof, uvs.ptr, GL_STATIC_DRAW);
    }

    void setPoints() {

        // Important check since the user can change this every frame
        enforce(
            points.length == data.points.length, 
            "Data length mismatch, if you want to change the mesh you need to change its data with DynMesh.rebuffer."
        );
        glBindBuffer(GL_ARRAY_BUFFER, vbo);
        glBufferData(GL_ARRAY_BUFFER, points.length*vec2.sizeof, points.ptr, GL_DYNAMIC_DRAW);
    }

public:

    /**
        The mesh's transform
    */
    Transform transform;

    /**
        Points in the dynamic mesh
    */
    vec2[] points;

    /**
        Constructs a dynamic mesh
    */
    this(MeshData data, Shader shader = null) {
        this.shader = shader is null ? dynMeshShader : shader;
        this.data = data;
        this.transform = new Transform();

        // Set the deformable points to their initial position
        this.points = data.points.dup;

        // Generate the buffers
        glGenBuffers(1, &vbo);
        glGenBuffers(1, &uvbo);
        glGenBuffers(1, &ibo);

        mvp = this.shader.getUniformLocation("mvp");

        // Update the indices and UVs
        this.setIndices();
        this.genUVs();
        this.setPoints();
    }

    /**
        Changes this mesh's data
    */
    final void rebuffer(MeshData data) {
        this.data = data;
        this.resetDeform();
        this.setIndices();
        this.genUVs();
    }

    /**
        Gets all points in a radius around the specified point
    */
    size_t[] pointsAround(size_t i, float radius = 128f) {
        size_t[] p;
        vec2 pointPos = points[i];
        foreach(j, point; points) {
            
            // We don't want to add the point itself
            if (j == i) continue;

            // Add any points inside the search area to the list
            if (point.distance(pointPos) < radius) p ~= j;
        }
        return p;
    }

    /**
        Gets all points in a radius around the specified vector
    */
    size_t[] pointsAround(vec2 pos, float radius = 128f) {
        size_t[] p;
        foreach(j, point; points) {

            // Add any points inside the search area to the list
            if (point.distance(pos) < radius) p ~= j;
        }
        return p;
    }

    /**
        Pulls a vertex and surrounding verticies in a specified direction
    */
    void pull(size_t ix, vec2 direction, float smoothArea = 128f) {
        vec2 pointPos = points[ix];
				
        points[ix] -= vec2(direction.x, direction.y);

        foreach(i, point; points) {
            
            // We don't want to double pull on our vertex
            if (i == ix) continue;

            // We want to subtly pull other surrounding points
            if (point.distance(pointPos) < smoothArea) {

                // Pulling power decreases linearly the further out we go
                immutable(float) pullPower = (smoothArea-point.distance(pointPos))/smoothArea;

                points[i] -= vec2(direction.x*pullPower, direction.y*pullPower);
            }
        }
    }

    /**
        Returns a copy of the origin points
    */
    final vec2[] originPoints() {
        return data.points.dup;
    }

    /**
        Resets any deformation that has been done to the mesh
    */
    final void resetDeform() {
        this.points = data.points.dup;
    }

    /**
        Mark this mesh as modified
    */
    final void mark() {
        this.marked = true;
    }
    
    /**
        Draw the mesh using the camera matrix
    */
    void draw(mat4 vp) {

        // Update the points in the mesh if it's marked for an update.
        if (marked) {
            this.setPoints();
            marked = false;
        }

        // Bind our vertex array
        glBindVertexArray(vao);

        // Apply camera
        shader.setUniform(mvp, vp * transform.matrix());
        
        // Use the shader
        shader.use();

        // Bind the texture
        data.textures[activeTexture].texture.bind();

        // Enable points array
        glEnableVertexAttribArray(0);
        glBindBuffer(GL_ARRAY_BUFFER, vbo);
        glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, null);

        // Enable UVs array
        glEnableVertexAttribArray(1); // uvs
        glBindBuffer(GL_ARRAY_BUFFER, uvbo);
        glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, 0, null);

        // Bind element array and draw our mesh
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ibo);
        glDrawElements(GL_TRIANGLES, cast(int)data.indices.length, GL_UNSIGNED_SHORT, null);

        // Disable the vertex attribs after use
        glDisableVertexAttribArray(0);
        glDisableVertexAttribArray(1);
    }

    /**
        Draw debug points
    */
    void drawDebug(bool line = false)(mat4 vp, int size = 8) {

        // Set debug point size
        static if (line) glLineWidth(size);
        else glPointSize(size);

        // Bind our vertex array
        glBindVertexArray(vao);

        // Apply camera
        shader.setUniform(mvp, vp * transform.matrix());
        
        // Use the shader
        dynMeshDbg.use();

        // Bind the texture
        data.textures[activeTexture].texture.bind();

        // Enable points array
        glEnableVertexAttribArray(0);
        glBindBuffer(GL_ARRAY_BUFFER, vbo);
        glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, null);

        // Enable UVs array
        glEnableVertexAttribArray(1); // uvs
        glBindBuffer(GL_ARRAY_BUFFER, uvbo);
        glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, 0, null);

        // Bind element array and draw our mesh
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ibo);
        static if (line) glDrawElements(GL_LINES, cast(int)data.indices.length, GL_UNSIGNED_SHORT, null);
        else glDrawElements(GL_POINTS, cast(int)data.indices.length, GL_UNSIGNED_SHORT, null);

        // Disable the vertex attribs after use
        glDisableVertexAttribArray(0);
        glDisableVertexAttribArray(1);
    }
}