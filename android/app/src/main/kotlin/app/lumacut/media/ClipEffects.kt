package app.lumacut.media

import android.graphics.Matrix
import androidx.media3.common.util.Size
import androidx.media3.common.Effect
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.Crop
import androidx.media3.effect.MatrixTransformation
import androidx.media3.effect.ScaleAndRotateTransformation
import app.lumacut.core.EffectType
import app.lumacut.core.Look
import kotlin.math.PI
import kotlin.math.exp
import kotlin.math.sin

/** Turns a clip's look and scene effects into Media3 video effects (GPU shaders and per-frame matrices). */
@UnstableApi
object ClipEffects {
    private fun hex(h: String?): FloatArray {
        val s = h?.trim('#')?.takeIf { it.length == 6 } ?: return floatArrayOf(0.5f, 0.5f, 0.5f)
        return floatArrayOf(s.substring(0, 2).toInt(16) / 255f, s.substring(2, 4).toInt(16) / 255f, s.substring(4, 6).toInt(16) / 255f)
    }

    /** Crop, rotation and mirroring first, then the colour look. */
    fun look(look: Look): List<Effect> {
        val out = mutableListOf<Effect>()
        if (look.cropLeft + look.cropRight + look.cropTop + look.cropBottom > 0)
            out += Crop((-1 + 2 * look.cropLeft).toFloat(), (1 - 2 * look.cropRight).toFloat(), (-1 + 2 * look.cropBottom).toFloat(), (1 - 2 * look.cropTop).toFloat())
        if (look.rotation != 0.0 || look.flipX || look.flipY)
            out += ScaleAndRotateTransformation.Builder().setRotationDegrees(look.rotation.toFloat()).setScale(if (look.flipX) -1f else 1f, if (look.flipY) -1f else 1f).build()
        val plain = look.brightness == 0.0 && look.contrast == 1.0 && look.saturation == 1.0 && look.sepia == 0.0 && look.blur == 0.0 && look.vignette == 0.0 &&
            look.warmth == 0.0 && look.fade == 0.0 && look.sharpen == 0.0 && look.splitAmount == 0.0
        if (!plain) out += ShaderEffect(LOOK_SHADER, { _, _ ->
            mapOf("uBright" to floatArrayOf(look.brightness.toFloat()), "uContrast" to floatArrayOf(look.contrast.toFloat()), "uSat" to floatArrayOf(look.saturation.toFloat()),
                "uSepia" to floatArrayOf(look.sepia.toFloat()), "uWarmth" to floatArrayOf(look.warmth.toFloat()), "uFade" to floatArrayOf(look.fade.toFloat()),
                "uVig" to floatArrayOf(look.vignette.toFloat()), "uSplit" to floatArrayOf(look.splitAmount.toFloat()), "uSharp" to floatArrayOf(look.sharpen.toFloat()),
                "uBlurAmt" to floatArrayOf(look.blur.toFloat()), "uShadow" to hex(look.splitShadows), "uHigh" to hex(look.splitHighlights))
        })
        return out
    }

    /**
     * Opacity, scale, offset, rotation, keyframes and fades for a clip that is the only video layer (no compositor is available then).
     * Opacity is applied against black, which is what lies below a single layer.
     */
    fun placement(clip: app.lumacut.core.Clip): List<Effect> {
        val animated = clip.keyframes.isNotEmpty()
        val plain = !animated && clip.opacity == 1.0 && clip.scale == 1.0 && clip.offsetX == 0.0 && clip.offsetY == 0.0 && clip.fadeIn == 0L && clip.fadeOut == 0L
        if (plain) return emptyList()
        fun state(tUs: Long): app.lumacut.core.Keyframe {
            val local = tUs / 1000.0
            return app.lumacut.core.Keyframe.interpolate(clip.keyframes, local) ?: app.lumacut.core.Keyframe(0, clip.opacity, clip.scale, clip.offsetX, clip.offsetY)
        }
        fun alpha(tUs: Long): Float {
            val local = tUs / 1000
            var a = state(tUs).opacity
            if (clip.fadeIn > 0 && local < clip.fadeIn) a *= local.toDouble() / clip.fadeIn
            if (clip.fadeOut > 0 && local > clip.duration - clip.fadeOut) a *= maxOf(0.0, (clip.duration - local).toDouble() / clip.fadeOut)
            return a.toFloat().coerceIn(0f, 1f)
        }
        val out = mutableListOf<Effect>()
        out += MatrixTransformation { t -> val k = state(t); Matrix().apply { postRotate(k.rotation.toFloat()); postScale(k.scale.toFloat(), k.scale.toFloat()); postTranslate((k.offsetX * 2).toFloat(), (k.offsetY * 2).toFloat()) } }
        out += ShaderEffect("uniform float uAlpha; void main(){ vec4 s=tex(vUv); gl_FragColor=vec4(s.rgb*uAlpha,1.0); }", { t, _ -> mapOf("uAlpha" to floatArrayOf(alpha(t))) })
        return out
    }

    /** Scene effects for a clip of `durationUs` (progress runs 0..1 over the clip). */
    fun scene(effects: List<app.lumacut.core.Effect>, durationUs: Long): List<Effect> {
        val out = mutableListOf<Effect>()
        for (e in effects) {
            val a = e.amount.toFloat().coerceIn(0f, 1f)
            fun progress(t: Long) = (t.toDouble() / maxOf(1L, durationUs)).coerceIn(0.0, 1.0)
            fun seconds(t: Long) = t / 1_000_000.0
            fun zoomAbout(s: Double, dx: Double = 0.0, dy: Double = 0.0, rot: Double = 0.0) = Matrix().apply { postRotate(rot.toFloat()); postScale(s.toFloat(), s.toFloat()); postTranslate(dx.toFloat(), dy.toFloat()) }
            when (e.type) {
                EffectType.kenBurnsIn -> out += MatrixTransformation { t -> zoomAbout(1 + 0.25 * a * progress(t)) }
                EffectType.kenBurnsOut -> out += MatrixTransformation { t -> zoomAbout(1 + 0.25 * a * (1 - progress(t))) }
                EffectType.panLeft -> out += MatrixTransformation { t -> zoomAbout(1 + 0.15 * a, -(0.5 - progress(t)) * 0.3 * a) }
                EffectType.panRight -> out += MatrixTransformation { t -> zoomAbout(1 + 0.15 * a, (0.5 - progress(t)) * 0.3 * a) }
                EffectType.shake -> out += MatrixTransformation { t ->
                    val f = (seconds(t) * 30).toInt()
                    fun r(s: Int) = (Math.abs(sin((f * 12.9898 + s * 78.233))) * 43758.5453 % 1.0)
                    zoomAbout(1 + 0.06 * a, (r(1) - 0.5) * 0.08 * a, (r(2) - 0.5) * 0.08 * a, (r(3) - 0.5) * 3 * a)
                }
                EffectType.pulse -> out += MatrixTransformation { t -> zoomAbout(1 + 0.07 * a * (0.5 + 0.5 * sin(2 * PI * 2 * seconds(t)))) }
                EffectType.punchIn -> out += MatrixTransformation { t -> zoomAbout(1 + 0.22 * a * maxOf(0.0, 1 - seconds(t) / 0.45)) }
                EffectType.dutchTilt -> out += MatrixTransformation { _ -> zoomAbout(1 + 0.4 * a, 0.0, 0.0, 0.2 * a * 180 / PI) }
                else -> shader(e.type, a, durationUs)?.let { out += it }
            }
        }
        return out
    }

    private fun shader(type: EffectType, a: Float, durationUs: Long): ShaderEffect? {
        val body = EFFECT_SHADERS[type] ?: return null
        return ShaderEffect(body, { t, _ -> mapOf("uAmt" to floatArrayOf(a), "uProg" to floatArrayOf((t.toDouble() / maxOf(1L, durationUs)).coerceIn(0.0, 1.0).toFloat())) })
    }

    private const val LOOK_SHADER = """
uniform float uBright, uContrast, uSat, uSepia, uWarmth, uFade, uVig, uSplit, uSharp, uBlurAmt;
uniform vec3 uShadow, uHigh;
void main() {
  vec4 src = tex(vUv);
  vec3 c = src.rgb;
  if (uBlurAmt > 0.0) c = blur(vUv, uBlurAmt * 10.0);
  if (uSharp > 0.0) { vec3 b = blur(vUv, 1.0); c = c + (c - b) * uSharp * 2.0; }
  c += uBright;
  c = (c - 0.5) * uContrast + 0.5;
  c = mix(vec3(luma(c)), c, uSat);
  vec3 sep = vec3(dot(c, vec3(0.393, 0.769, 0.189)), dot(c, vec3(0.349, 0.686, 0.168)), dot(c, vec3(0.272, 0.534, 0.131)));
  c = mix(c, sep, uSepia);
  c.r += uWarmth * 0.08; c.b -= uWarmth * 0.08;
  c = c * (1.0 - 0.3 * uFade) + 0.3 * uFade * 0.6;
  float l = luma(c);
  vec3 toned = c + (mix(uShadow, uHigh, l) - 0.5) * 0.5;
  c = mix(c, toned, uSplit);
  vec2 d = (vUv - 0.5) * vec2(uSize.x / uSize.y, 1.0);
  c *= 1.0 - uVig * smoothstep(0.3, 0.9, length(d) * 1.25);
  gl_FragColor = vec4(clamp(c, 0.0, 1.0), src.a);
}
"""

    private val EFFECT_SHADERS: Map<EffectType, String> = buildMap {
        val head = "uniform float uAmt; uniform float uProg;\n"
        fun add(t: EffectType, body: String) { put(t, head + body) }
        add(EffectType.vignette, "void main(){ vec4 s=tex(vUv); vec2 d=(vUv-0.5)*vec2(uSize.x/uSize.y,1.0); float v=smoothstep(0.25,0.95,length(d)*1.3); gl_FragColor=vec4(s.rgb*(1.0-uAmt*1.2*v),s.a); }")
        add(EffectType.glow, "void main(){ vec4 s=tex(vUv); vec3 b=blur(vUv,6.0+10.0*uAmt); float k=smoothstep(0.55,1.0,luma(b)); gl_FragColor=vec4(s.rgb+b*k*(0.5+1.2*uAmt),s.a); }")
        add(EffectType.flash, "void main(){ vec4 s=tex(vUv); float k=uAmt*max(0.0,1.0-uTime/0.5); gl_FragColor=vec4(mix(s.rgb,vec3(1.0),k),s.a); }")
        add(EffectType.lightLeak, "void main(){ vec4 s=tex(vUv); vec2 c=vec2(0.1+0.8*uProg,0.15); float d=length((vUv-c)*vec2(1.0,0.6)); vec3 leak=vec3(1.0,0.5,0.15)*smoothstep(0.65,0.0,d)*0.95*uAmt; gl_FragColor=vec4(1.0-(1.0-s.rgb)*(1.0-leak),s.a); }")
        add(EffectType.cinemaBars, "void main(){ vec4 s=tex(vUv); float bar=0.13*uAmt; float m=step(bar,vUv.y)*step(vUv.y,1.0-bar); gl_FragColor=vec4(s.rgb*m,s.a); }")
        add(EffectType.grain, "void main(){ vec4 s=tex(vUv); float n=hash(vUv*uSize+floor(uTime*30.0))-0.5; gl_FragColor=vec4(s.rgb+n*0.45*uAmt,s.a); }")
        add(EffectType.vhs, "void main(){ float sh=0.006*(0.5+uAmt); vec3 c=vec3(tex(vUv+vec2(sh,0.0)).r,tex(vUv).g,tex(vUv-vec2(sh,0.0)).b); float line=step(0.5,fract(vUv.y*uSize.y/4.0)); c*=1.0-0.28*uAmt*line; c+= (hash(vUv*uSize+uTime)-0.5)*0.25*uAmt; c=mix(vec3(luma(c)),c,1.2); gl_FragColor=vec4(c,1.0); }")
        add(EffectType.chromatic, "void main(){ float sh=0.012*uAmt; gl_FragColor=vec4(tex(vUv+vec2(sh,0.0)).r,tex(vUv).g,tex(vUv-vec2(sh,0.0)).b,1.0); }")
        add(EffectType.glitch, "void main(){ float f=floor(uTime*10.0); float burst=step(hash(vec2(f,4.0)),0.35*(0.4+uAmt)); float band=step(hash(vec2(f,floor(vUv.y*12.0))),0.25)*burst; vec2 uv=vUv+vec2((hash(vec2(f,7.0))-0.5)*0.18*uAmt*band,0.0); float sh=0.02*uAmt*burst; gl_FragColor=vec4(tex(uv+vec2(sh,0.0)).r,tex(uv).g,tex(uv-vec2(sh,0.0)).b,1.0); }")
        add(EffectType.blurIn, "void main(){ float r=14.0*uAmt*(1.0-uProg); gl_FragColor=vec4(r>0.2?blur(vUv,r):tex(vUv).rgb,1.0); }")
        add(EffectType.blurOut, "void main(){ float r=14.0*uAmt*uProg; gl_FragColor=vec4(r>0.2?blur(vUv,r):tex(vUv).rgb,1.0); }")
        add(EffectType.posterize, "void main(){ float n=max(2.0,9.0-7.0*uAmt); vec4 s=tex(vUv); gl_FragColor=vec4(floor(s.rgb*n+0.5)/n,s.a); }")
        add(EffectType.duotone, "void main(){ vec4 s=tex(vUv); float l=clamp((luma(s.rgb)-0.5)*1.2+0.5,0.0,1.0); vec3 d=mix(vec3(0.05,0.02,0.3),vec3(1.0,0.78,0.4),l); gl_FragColor=vec4(mix(s.rgb,d,min(1.0,uAmt*1.4)),s.a); }")
        add(EffectType.comic, "void main(){ vec4 s=tex(vUv); vec2 px=1.0/uSize; float e=abs(luma(tex(vUv+vec2(px.x*1.5,0.0)).rgb)-luma(tex(vUv-vec2(px.x*1.5,0.0)).rgb))+abs(luma(tex(vUv+vec2(0.0,px.y*1.5)).rgb)-luma(tex(vUv-vec2(0.0,px.y*1.5)).rgb)); vec3 c=floor(s.rgb*5.0+0.5)/5.0; c*=1.0-smoothstep(0.08,0.2,e); gl_FragColor=vec4(mix(s.rgb,c,min(1.0,uAmt*1.4)),s.a); }")
        add(EffectType.mirror, "void main(){ vec2 uv=vUv; if(uv.x>0.5) uv.x=1.0-uv.x; gl_FragColor=tex(uv); }")
        add(EffectType.tiltShift, "void main(){ float m=smoothstep(0.32,0.0,vUv.y)+smoothstep(0.68,1.0,vUv.y); vec3 c=mix(tex(vUv).rgb,blur(vUv,(3.0+8.0*uAmt)),clamp(m,0.0,1.0)); gl_FragColor=vec4(c,1.0); }")
        add(EffectType.dreamBlur, "void main(){ vec4 s=tex(vUv); vec3 b=blur(vUv,4.0+10.0*uAmt); vec3 c=mix(s.rgb,b,0.55); c+=b*smoothstep(0.6,1.0,luma(b))*(0.5+0.6*uAmt); gl_FragColor=vec4(c,1.0); }")
        add(EffectType.halftone, "void main(){ vec4 s=tex(vUv); float cell=max(4.0,uSize.x/90.0); vec2 g=floor(vUv*uSize/cell); vec2 ctr=(g+0.5)*cell/uSize; vec3 col=tex(ctr).rgb; float d=length(vUv*uSize-(g+0.5)*cell)/cell; float dot_=smoothstep(0.75*sqrt(luma(col)+0.1),0.0,d*1.2); gl_FragColor=vec4(mix(s.rgb,col*dot_,min(1.0,uAmt*1.4)),1.0); }")
        add(EffectType.pixelate, "void main(){ float px=max(2.0,uSize.x*(0.004+0.04*uAmt)); vec2 g=floor(vUv*uSize/px); gl_FragColor=vec4(tex((g+0.5)*px/uSize).rgb,1.0); }")
        add(EffectType.neonEdges, "void main(){ vec2 px=1.0/uSize; float gx=luma(tex(vUv+vec2(px.x,0.0)).rgb)-luma(tex(vUv-vec2(px.x,0.0)).rgb); float gy=luma(tex(vUv+vec2(0.0,px.y)).rgb)-luma(tex(vUv-vec2(0.0,px.y)).rgb); float e=clamp(length(vec2(gx,gy))*(3.0+9.0*uAmt),0.0,1.0); vec3 c=tex(vUv).rgb*0.4+vec3(0.2,0.9,1.0)*e; gl_FragColor=vec4(c,1.0); }")
        add(EffectType.invert, "void main(){ vec4 s=tex(vUv); gl_FragColor=vec4(mix(s.rgb,1.0-s.rgb,uAmt),s.a); }")
        add(EffectType.kaleidoscope, "void main(){ vec2 p=vUv-0.5; float ang=atan(p.y,p.x)+uProg*3.14159; float r=length(p); float seg=6.2831853/6.0; ang=abs(mod(ang,seg)-seg*0.5); vec2 uv=0.5+r*vec2(cos(ang),sin(ang)); gl_FragColor=vec4(mix(tex(vUv).rgb,tex(uv).rgb,min(1.0,uAmt*1.25)),1.0); }")
        add(EffectType.fisheye, "void main(){ vec2 p=vUv-0.5; float r=length(p*vec2(uSize.x/uSize.y,1.0)); float k=1.0-0.7*uAmt*smoothstep(0.7,0.0,r); gl_FragColor=tex(0.5+p*k); }")
        add(EffectType.strobe, "void main(){ vec4 s=tex(vUv); float on=step(fract(uTime*5.0),0.18); gl_FragColor=vec4(mix(s.rgb,vec3(1.0),0.85*uAmt*on),s.a); }")
    }
}
