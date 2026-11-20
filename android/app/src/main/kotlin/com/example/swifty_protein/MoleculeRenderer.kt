package com.example.swifty_protein

import android.graphics.Bitmap
import android.graphics.Color
import android.opengl.GLES20.*
import android.opengl.GLES30.glBindVertexArray
import android.opengl.GLES30.glDrawElementsInstanced
import android.opengl.GLES30.glGenVertexArrays
import android.opengl.GLES30.glVertexAttribDivisor
import android.opengl.GLSurfaceView
import android.opengl.Matrix
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.opengles.GL10
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

internal class MoleculeRenderer(
    coordinates: DoubleArray,
    private val colors: IntArray,
    private val radii: DoubleArray,
    private val elementGroups: IntArray,
    bonds: IntArray,
    background: Int,
    bondColor: Int,
) : GLSurfaceView.Renderer {
    enum class Model { BALL_AND_STICK, SPACE_FILLING, STICK, WIREFRAME }

    data class Pose(
        val yaw: Float = 17f, val pitch: Float = 14f, val zoom: Float = 1f,
        val panX: Float = 0f, val panY: Float = 0f,
    )

    data class Palette(val background: Int, val bonds: Int)
    data class Highlight(val element: Int = -1, val a: Int = -1, val b: Int = -1, val c: Int = -1)
    data class Capture(
        val format: MoleculeImageFormat,
        val complete: (ByteArray?) -> Unit,
    )

    @Volatile var pose = Pose()
    @Volatile var palette = Palette(background, bondColor)
    @Volatile var model = Model.BALL_AND_STICK
    @Volatile var highlight = Highlight()
    @Volatile var capture: Capture? = null

    private val atoms = FloatArray(coordinates.size)
    private val bondInstances: FloatArray
    private val matrix = FloatArray(16)
    private val rotation = FloatArray(16)
    private val projection = FloatArray(16)
    private var width = 0
    private var height = 0
    private var radius = ATOM_RADIUS
    private lateinit var spheres: Batch
    private lateinit var cylinders: Batch
    private lateinit var lines: Batch
    private lateinit var points: Batch
    private var program = 0
    private var matrixUniform = 0
    private var rotationUniform = 0
    private var kindUniform = 0
    private var modelUniform = 0
    private var bondColorUniform = 0
    private var wireShadeUniform = 0
    private var lightingUniform = 0
    private var highlightUniform = 0
    private var highlightColorUniform = 0

    init {
        val center = DoubleArray(3)
        for (i in coordinates.indices) center[i % 3] += coordinates[i] / colors.size
        for (i in atoms.indices) atoms[i] = (coordinates[i] - center[i % 3]).toFloat()
        for (i in atoms.indices step 3) {
            val x = atoms[i]
            val y = atoms[i + 1]
            val z = atoms[i + 2]
            radius = maxOf(radius, sqrt(x * x + y * y + z * z) + radii[i / 3].toFloat())
        }
        val endpoints = FloatArray(bonds.size / 2 * INSTANCE_FLOATS)
        var offset = 0
        for (i in bonds.indices step 2) {
            val a = 3 * bonds[i]
            val b = 3 * bonds[i + 1]
            if ((0..2).all { atoms[a + it] == atoms[b + it] }) continue
            atoms.copyInto(endpoints, offset, a, a + 3)
            atoms.copyInto(endpoints, offset + 3, b, b + 3)
            setColor(endpoints, offset + 6, colors[bonds[i]])
            setColor(endpoints, offset + 9, colors[bonds[i + 1]])
            offset += INSTANCE_FLOATS
        }
        bondInstances = endpoints.copyOf(offset)
    }

    private fun setColor(data: FloatArray, offset: Int, color: Int) {
        data[offset] = Color.red(color) / 255f
        data[offset + 1] = Color.green(color) / 255f
        data[offset + 2] = Color.blue(color) / 255f
    }

    override fun onSurfaceCreated(gl: GL10?, config: EGLConfig?) {
        program = linkProgram()
        matrixUniform = glGetUniformLocation(program, "projection")
        rotationUniform = glGetUniformLocation(program, "rotation")
        kindUniform = glGetUniformLocation(program, "kind")
        modelUniform = glGetUniformLocation(program, "model")
        bondColorUniform = glGetUniformLocation(program, "bondColor")
        wireShadeUniform = glGetUniformLocation(program, "wireShade")
        lightingUniform = glGetUniformLocation(program, "lighting")
        highlightUniform = glGetUniformLocation(program, "highlight")
        highlightColorUniform = glGetUniformLocation(program, "highlightColor")
        val sphereData = FloatArray(colors.size * INSTANCE_FLOATS)
        for (i in colors.indices) {
            val offset = i * INSTANCE_FLOATS
            atoms.copyInto(sphereData, offset, i * 3, i * 3 + 3)
            sphereData[offset + 3] = radii[i].toFloat()
            sphereData[offset + 4] = elementGroups[i].toFloat()
            setColor(sphereData, offset + 6, colors[i])
        }
        val segments = if (colors.size > 600) 10 else 18
        val atomBuffer = Batch.uploadInstances(sphereData)
        val bondBuffer = Batch.uploadInstances(bondInstances)
        spheres = Batch(sphereMesh(segments, segments / 2), atomBuffer, colors.size)
        cylinders = Batch(cylinderMesh(if (colors.size > 600) 8 else 12),
            bondBuffer, bondInstances.size / INSTANCE_FLOATS)
        points = Batch(Mesh(FloatArray(6), shortArrayOf(0)), atomBuffer, colors.size)
        lines = Batch(
            Mesh(floatArrayOf(0f, 0f, 0f, 0f, 0f, 0f, 0f, 0f, 1f, 0f, 0f, 0f),
                shortArrayOf(0, 1)),
            bondBuffer, bondInstances.size / INSTANCE_FLOATS,
        )
        glEnable(GL_DEPTH_TEST)
    }

    override fun onSurfaceChanged(gl: GL10?, width: Int, height: Int) {
        this.width = width
        this.height = height
        glViewport(0, 0, width, height)
    }

    private fun updateMatrices() {
        val camera = pose
        val aspect = width.toFloat() / height
        val half = radius * 1.15f / camera.zoom
        val halfWidth = half * maxOf(1f, aspect)
        val halfHeight = half * maxOf(1f, 1f / aspect)
        val x = -camera.panX * halfWidth
        val y = -camera.panY * halfHeight

        Matrix.setIdentityM(rotation, 0)
        Matrix.rotateM(rotation, 0, camera.pitch, 1f, 0f, 0f)
        Matrix.rotateM(rotation, 0, camera.yaw, 0f, 1f, 0f)
        Matrix.orthoM(projection, 0, x - halfWidth, x + halfWidth,
            y - halfHeight, y + halfHeight, -radius * 2, radius * 2)
        Matrix.multiplyMM(matrix, 0, projection, 0, rotation, 0)
    }

    override fun onDrawFrame(gl: GL10?) {
        if (width == 0 || height == 0) return
        val paint = palette
        val bg = paint.background
        val darkBackground = Color.luminance(bg) <= .5f
        glClearColor(Color.red(bg) / 255f, Color.green(bg) / 255f, Color.blue(bg) / 255f, 1f)
        glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT)
        updateMatrices()
        glUseProgram(program)
        glUniformMatrix4fv(matrixUniform, 1, false, matrix, 0)
        glUniformMatrix4fv(rotationUniform, 1, false, rotation, 0)
        val selection = highlight
        glUniform4i(highlightUniform, selection.element, selection.a, selection.b, selection.c)
        if (darkBackground) {
            // Lift shadow detail and soften highlights against the dark background.
            glUniform4f(lightingUniform, .48f, .50f, .25f, .11f)
            glUniform3f(highlightColorUniform, 1f, .74f, .30f)
        } else {
            glUniform4f(lightingUniform, .40f, .55f, .19f, .16f)
            glUniform3f(highlightColorUniform, .72f, .33f, .07f)
        }
        glUniform3f(bondColorUniform, Color.red(paint.bonds) / 255f,
            Color.green(paint.bonds) / 255f, Color.blue(paint.bonds) / 255f)
        val representation = model
        glUniform1i(modelUniform, representation.ordinal)
        when (representation) {
            Model.WIREFRAME -> {
                glUniform1f(wireShadeUniform, if (darkBackground) 1f else .70f)
                glUniform1i(kindUniform, 2)
                lines.draw(GL_LINES)
                glUniform1i(kindUniform, 3)
                points.draw(GL_POINTS)
            }
            Model.SPACE_FILLING -> {
                glUniform1i(kindUniform, 0)
                spheres.draw()
            }
            Model.BALL_AND_STICK, Model.STICK -> {
                glUniform1i(kindUniform, 1)
                cylinders.draw()
                glUniform1i(kindUniform, 0)
                spheres.draw()
            }
        }
        capture?.let { request ->
            capture = null
            request.complete(runCatching { captureFrame(request.format) }.getOrNull())
        }
    }

    fun pick(x: Float, y: Float): Int? {
        if (width == 0 || height == 0) return null
        updateMatrices()
        val ndcX = x * 2 - 1
        val ndcY = 1 - y * 2
        val representation = model
        var closest = Float.POSITIVE_INFINITY
        var hit: Int? = null
        for (i in atoms.indices step 3) {
            val r = when (representation) {
                Model.BALL_AND_STICK -> ATOM_RADIUS
                Model.SPACE_FILLING -> radii[i / 3].toFloat()
                Model.STICK -> STICK_RADIUS
                Model.WIREFRAME -> 0f
            }
            // Give thin lines and junctions a small screen-space touch target.
            val rx = maxOf(projection[0] * r, 18f / width)
            val ry = maxOf(projection[5] * r, 18f / height)
            val a = atoms[i]
            val b = atoms[i + 1]
            val c = atoms[i + 2]
            val dx = (ndcX - (matrix[0] * a + matrix[4] * b + matrix[8] * c + matrix[12])) / rx
            val dy = (ndcY - (matrix[1] * a + matrix[5] * b + matrix[9] * c + matrix[13])) / ry
            val offset = dx * dx + dy * dy
            if (offset > 1) continue
            val depth = matrix[2] * a + matrix[6] * b + matrix[10] * c + matrix[14] +
                projection[10] * r * sqrt(1 - offset)
            if (depth < closest) {
                closest = depth
                hit = i / 3
            }
        }
        return hit
    }

    private fun captureFrame(format: MoleculeImageFormat): ByteArray {
        val rgba = ByteBuffer.allocateDirect(width * height * 4)
        glReadPixels(0, 0, width, height, GL_RGBA, GL_UNSIGNED_BYTE, rgba)
        val argb = IntArray(width * height)
        for (y in height - 1 downTo 0) {
            for (x in 0 until width) {
                val r = rgba.get().toInt() and 255
                val g = rgba.get().toInt() and 255
                val b = rgba.get().toInt() and 255
                rgba.get()
                argb[y * width + x] = Color.rgb(r, g, b)
            }
        }
        val bitmap = Bitmap.createBitmap(argb, width, height, Bitmap.Config.ARGB_8888)
        return try {
            ByteArrayOutputStream().use { output ->
                check(bitmap.compress(format.compression, format.quality, output))
                output.toByteArray()
            }
        } finally {
            bitmap.recycle()
        }
    }

    private class Batch(mesh: Mesh, instanceBuffer: Int, private val instanceCount: Int) {
        private val vao = IntArray(1)
        private val indexCount = mesh.indices.size

        init {
            val buffers = IntArray(2)
            glGenVertexArrays(1, vao, 0)
            glGenBuffers(2, buffers, 0)
            glBindVertexArray(vao[0])
            uploadFloats(buffers[0], mesh.vertices)
            attributes(start = 0, columns = 2, divisor = 0)
            glBindBuffer(GL_ARRAY_BUFFER, instanceBuffer)
            attributes(start = 2, columns = 4, divisor = 1)
            val indices = ByteBuffer.allocateDirect(mesh.indices.size * 2)
                .order(ByteOrder.nativeOrder()).asShortBuffer()
            indices.put(mesh.indices).position(0)
            glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, buffers[1])
            glBufferData(GL_ELEMENT_ARRAY_BUFFER, mesh.indices.size * 2, indices, GL_STATIC_DRAW)
            glBindVertexArray(0)
        }

        private fun attributes(start: Int, columns: Int, divisor: Int) {
            for (column in 0 until columns) {
                val location = start + column
                glEnableVertexAttribArray(location)
                glVertexAttribPointer(location, 3, GL_FLOAT, false, columns * 12, column * 12)
                glVertexAttribDivisor(location, divisor)
            }
        }

        fun draw(primitive: Int = GL_TRIANGLES) {
            if (instanceCount == 0) return
            glBindVertexArray(vao[0])
            glDrawElementsInstanced(primitive, indexCount, GL_UNSIGNED_SHORT, 0, instanceCount)
        }

        companion object {
            fun uploadInstances(data: FloatArray): Int {
                val buffer = IntArray(1)
                glGenBuffers(1, buffer, 0)
                uploadFloats(buffer[0], data)
                return buffer[0]
            }

            private fun uploadFloats(buffer: Int, data: FloatArray) {
                val floats = ByteBuffer.allocateDirect(data.size * 4)
                    .order(ByteOrder.nativeOrder()).asFloatBuffer()
                floats.put(data).position(0)
                glBindBuffer(GL_ARRAY_BUFFER, buffer)
                glBufferData(GL_ARRAY_BUFFER, data.size * 4, floats, GL_STATIC_DRAW)
            }
        }
    }

    private data class Mesh(val vertices: FloatArray, val indices: ShortArray)

    private fun sphereMesh(segments: Int, rings: Int): Mesh {
        val vertices = ArrayList<Float>()
        for (ring in 0..rings) {
            val phi = PI * ring / rings
            for (side in 0..segments) {
                val theta = 2 * PI * side / segments
                val x = (sin(phi) * cos(theta)).toFloat()
                val y = cos(phi).toFloat()
                val z = (sin(phi) * sin(theta)).toFloat()
                vertices.addAll(listOf(x, y, z, x, y, z))
            }
        }
        return Mesh(vertices.toFloatArray(), gridIndices(segments, rings))
    }

    private fun cylinderMesh(segments: Int): Mesh {
        val vertices = ArrayList<Float>()
        // Bond ends meet the centers of their spheres, which enclose the open ends.
        for (end in 0..1) {
            for (side in 0..segments) {
                val theta = 2 * PI * side / segments
                val x = cos(theta).toFloat()
                val y = sin(theta).toFloat()
                vertices.addAll(listOf(x, y, end.toFloat(), x, y, 0f))
            }
        }
        return Mesh(vertices.toFloatArray(), gridIndices(segments, 1))
    }

    private fun gridIndices(columns: Int, rows: Int): ShortArray {
        val indices = ArrayList<Short>()
        for (y in 0 until rows) {
            for (x in 0 until columns) {
                val a = y * (columns + 1) + x
                val b = a + columns + 1
                for (index in intArrayOf(a, b, a + 1, a + 1, b, b + 1)) {
                    indices.add(index.toShort())
                }
            }
        }
        return indices.toShortArray()
    }

    private fun compileShader(kind: Int, source: String): Int {
        val shader = glCreateShader(kind)
        glShaderSource(shader, source)
        glCompileShader(shader)
        val status = IntArray(1)
        glGetShaderiv(shader, GL_COMPILE_STATUS, status, 0)
        check(status[0] == GL_TRUE) { glGetShaderInfoLog(shader) }
        return shader
    }

    private fun linkProgram(): Int {
        val vertex = compileShader(GL_VERTEX_SHADER, VERTEX_SHADER)
        val fragment = compileShader(GL_FRAGMENT_SHADER, FRAGMENT_SHADER)
        val program = glCreateProgram()
        glAttachShader(program, vertex)
        glAttachShader(program, fragment)
        glLinkProgram(program)
        val status = IntArray(1)
        glGetProgramiv(program, GL_LINK_STATUS, status, 0)
        check(status[0] == GL_TRUE) { glGetProgramInfoLog(program) }
        glDeleteShader(vertex)
        glDeleteShader(fragment)
        return program
    }

    companion object {
        private const val INSTANCE_FLOATS = 12
        private const val ATOM_RADIUS = .32f
        private const val STICK_RADIUS = .13f

        private const val VERTEX_SHADER = """#version 300 es
layout(location = 0) in vec3 position;
layout(location = 1) in vec3 normal;
layout(location = 2) in vec3 center;
layout(location = 3) in vec3 endOrRadius;
layout(location = 4) in vec3 colorA;
layout(location = 5) in vec3 colorB;
uniform mat4 projection;
uniform mat4 rotation;
uniform int kind;
uniform int model;
uniform ivec4 highlight;
uniform vec3 bondColor;
out vec3 viewNormal;
flat out vec3 baseA;
flat out vec3 baseB;
out float alongBond;
flat out int primitiveKind;
flat out int highlighted;

const int SPACE_FILLING = 1;
const int STICK = 2;
const int SPHERE = 0;
const int CYLINDER = 1;
const int LINE = 2;
const int POINT = 3;

void main() {
    vec3 world = center;
    vec3 n = normal;
    baseA = colorA;
    baseB = colorA;
    alongBond = 0.0;
    primitiveKind = kind;
    bool atom = kind == SPHERE || kind == POINT;
    bool selected = atom && (int(endOrRadius.y) == highlight.x ||
        any(equal(ivec3(gl_InstanceID), highlight.yzw)));
    highlighted = selected ? 1 : 0;
    gl_PointSize = selected ? 10.0 : 6.0;
    if (kind == SPHERE) {
        float radius = model == SPACE_FILLING ? endOrRadius.x
                     : model == STICK ? 0.13 : 0.32;
        world += position * radius;
    } else if (kind == CYLINDER || kind == LINE) {
        alongBond = position.z;
        world = mix(center, endOrRadius, alongBond);
        baseB = colorB;
        if (kind == CYLINDER) {
            vec3 axis = normalize(endOrRadius - center);
            vec3 reference = abs(axis.z) < 0.9 ? vec3(0, 0, 1) : vec3(0, 1, 0);
            vec3 right = normalize(cross(reference, axis));
            n = right * normal.x + cross(axis, right) * normal.y;
            world += n * (model == STICK ? 0.13 : 0.10);
            if (model != STICK) {
                baseA = bondColor;
                baseB = bondColor;
            }
        }
    }
    viewNormal = mat3(rotation) * n;
    gl_Position = projection * vec4(world, 1);
}
"""

        private const val FRAGMENT_SHADER = """#version 300 es
precision highp float;
precision highp int;
in vec3 viewNormal;
flat in vec3 baseA;
flat in vec3 baseB;
in float alongBond;
flat in int primitiveKind;
flat in int highlighted;
uniform float wireShade;
uniform vec4 lighting;
uniform vec3 highlightColor;
out vec4 color;

void main() {
    vec3 baseColor = alongBond < 0.5 ? baseA : baseB;
    if (primitiveKind >= 2) {
        vec3 shade = baseColor * wireShade;
        if (primitiveKind == 3) {
            float edge = distance(gl_PointCoord, vec2(0.5));
            if (edge > 0.5) discard;
            if (highlighted == 1 && edge > 0.28) shade = highlightColor;
        }
        color = vec4(shade, 1);
        return;
    }
    vec3 normal = normalize(viewNormal);
    vec3 key = normalize(vec3(-0.50, 0.65, 1.0));
    vec3 fill = normalize(vec3(0.75, -0.1, 0.55));
    float light = lighting.x + lighting.y * max(dot(normal, key), 0.0)
                             + lighting.z * max(dot(normal, fill), 0.0);
    vec3 halfway = normalize(key + vec3(0, 0, 1));
    float shine = lighting.w * pow(max(dot(normal, halfway), 0.0), 28.0);
    vec3 shade = baseColor * light + vec3(shine);
    if (highlighted == 1) {
        float rim = pow(1.0 - max(normal.z, 0.0), 1.4);
        shade = mix(shade, highlightColor, 0.12 + 0.83 * rim);
    }
    color = vec4(shade, 1);
}
"""
    }
}
