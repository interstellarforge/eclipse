package app.lumacut.media

import android.content.Context
import android.opengl.GLES20
import androidx.media3.common.util.Size
import androidx.media3.common.util.GlProgram
import androidx.media3.common.util.GlUtil
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.GlEffect
import androidx.media3.effect.GlShaderProgram
import androidx.media3.effect.BaseGlShaderProgram

/** One fragment shader pass over every video frame. `uniforms` is called per frame with the time inside the clip. */
@UnstableApi
class ShaderEffect(
    private val fragmentBody: String,
    private val uniforms: (timeUs: Long, sizePx: Size) -> Map<String, FloatArray> = { _, _ -> emptyMap() },
) : GlEffect {
    override fun toGlShaderProgram(context: Context, useHdr: Boolean): GlShaderProgram = Program(fragmentBody, uniforms, useHdr)

    private class Program(
        body: String,
        private val uniforms: (Long, Size) -> Map<String, FloatArray>,
        useHdr: Boolean,
    ) : BaseGlShaderProgram(useHdr, 1) {
        private val program: GlProgram = GlProgram(VERTEX, header + body)
        private var size = Size(1, 1)

        init {
            program.setBufferAttribute("aFramePosition", GlUtil.getNormalizedCoordinateBounds(), GlUtil.HOMOGENEOUS_COORDINATE_VECTOR_SIZE)
        }

        override fun configure(inputWidth: Int, inputHeight: Int): Size { size = Size(inputWidth, inputHeight); return size }

        override fun drawFrame(inputTexId: Int, presentationTimeUs: Long) {
            program.use()
            program.setSamplerTexIdUniform("uTexSampler", inputTexId, 0)
            program.setFloatsUniformIfPresent("uSize", floatArrayOf(size.width.toFloat(), size.height.toFloat()))
            program.setFloatsUniformIfPresent("uTime", floatArrayOf(presentationTimeUs / 1_000_000f))
            for ((name, v) in uniforms(presentationTimeUs, size)) {
                program.setFloatsUniformIfPresent(name, v)
            }
            program.bindAttributesAndUniforms()
            GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
        }

        override fun release() { super.release(); program.delete() }
    }

    companion object {
        private const val VERTEX = """
attribute vec4 aFramePosition;
varying vec2 vUv;
void main() {
  gl_Position = aFramePosition;
  vUv = aFramePosition.xy * 0.5 + 0.5;
}
"""
        val header = """
precision highp float;
varying vec2 vUv;
uniform sampler2D uTexSampler;
uniform vec2 uSize;
uniform float uTime;
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
vec4 tex(vec2 uv) { return texture2D(uTexSampler, clamp(uv, 0.0, 1.0)); }
vec3 blur(vec2 uv, float r) {
  vec3 c = vec3(0.0); float t = 0.0;
  for (int i = -3; i <= 3; i++) for (int j = -3; j <= 3; j++) {
    float w = 1.0 / (1.0 + float(i * i + j * j));
    c += tex(uv + vec2(float(i), float(j)) * r / uSize).rgb * w; t += w;
  }
  return c / t;
}
float luma(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }
"""
    }
}
