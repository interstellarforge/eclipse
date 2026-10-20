package app.lumacut

import android.os.Bundle
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.lifecycle.lifecycleScope
import androidx.media3.common.util.UnstableApi
import app.lumacut.core.*
import app.lumacut.media.Exporter
import kotlinx.coroutines.launch
import java.io.File

/** Debug aid: renders a sample project (look, effects, transition, title, overlay) headlessly and logs the result. */
@UnstableApi
class SpikeActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        lifecycleScope.launch {
            try {
                val audio = intent.getIntExtra("audio", 1) == 1
                val a = Asset(url = "file:///sdcard/Movies/beach-walk.mp4", duration = 8_000, hasVideo = true, hasAudio = audio)
                val b = Asset(url = "file:///sdcard/Movies/city-night.mp4", duration = 10_000, hasVideo = true, hasAudio = audio)
                val e = Editor()
                e.apply(Command.AddAsset(a)); e.apply(Command.AddAsset(b))
                val mode = intent.getIntExtra("mode", 9)
                val c1 = e.addClip(a, duration = 3_000)
                if (mode >= 2) { e.apply(Command.SetLook(c1.id, LookPresets.preset("Golden hour")!!)); e.apply(Command.AddEffect(c1.id, Effect(type = EffectType.vignette, amount = 0.6))) }
                if (mode >= 3) {
                    val c2 = e.addClip(b, sourceIn = 1_000, duration = 3_000)
                    e.apply(Command.AddEffect(c2.id, Effect(type = EffectType.kenBurnsIn, amount = 0.8)))
                    e.apply(Command.AddEffect(c2.id, Effect(type = EffectType.chromatic, amount = 0.5)))
                    if (mode >= 4) e.addTransitionAfter(c1.id, TransitionType.crossfade, 800)
                }
                if (mode == 7 || mode == 8) {   // two layers: B on a second video track
                    val e2 = Editor(); e2.apply(Command.AddAsset(a)); e2.apply(Command.AddAsset(b))
                    e2.addClip(a, duration = 3_000)
                    val top = e2.addTrack(TrackKind.video, onTop = true)
                    val l = e2.addClip(b, start = if (mode == 8) 1_000 else 0, sourceIn = 1_000, duration = 3_000, track = top)
                    e2.apply(Command.SetTransform(l.id, 0.5, 0.5, 0.2, 0.2))
                    val out2 = File(getExternalFilesDir(null), "spike$mode.mp4")
                    Exporter(this@SpikeActivity).export(e2.project, out2, onProgress = { Log.i("Spike", "progress $it") })
                    Log.i("Spike", "DONE ${out2.absolutePath} ${out2.length()}"); return@launch
                }
                if (mode >= 5) { val t = e.addTitle("Summer in Lisbon", start = 500, duration = 2_500); e.apply(Command.SetTextStyle(t.id, TitlePreset.movie.style)) }
                if (mode >= 6) e.addOverlay(GeneratorKind.confetti, start = 1_000, duration = 3_000, amount = 0.5)
                val out = File(getExternalFilesDir(null), "spike$mode.mp4")
                Log.i("Spike", "exporting mode $mode ${e.project.duration} ms")
                Exporter(this@SpikeActivity).export(e.project, out, onProgress = { Log.i("Spike", "progress $it") })
                Log.i("Spike", "DONE ${out.absolutePath} ${out.length()}")
            } catch (t: Throwable) { Log.e("Spike", "FAILED", t) }
        }
    }
}
