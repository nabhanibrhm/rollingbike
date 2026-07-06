package id.co.smma.rollingbike

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {

    private val channelName = "id.co.smma.rollingbike/share"
    private val instagramPackage = "com.instagram.android"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "shareToInstagram" -> handleShare(call.argument("filePath"),
                        call.argument("topColor"), call.argument("bottomColor"), result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun handleShare(
        filePath: String?,
        topColor: String?,
        bottomColor: String?,
        result: MethodChannel.Result,
    ) {
        if (filePath.isNullOrEmpty()) {
            result.error("no_path", "filePath is required", null)
            return
        }
        val file = File(filePath)
        if (!file.exists()) {
            result.error("missing_file", "Share image not found: $filePath", null)
            return
        }

        val uri: Uri = try {
            FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
        } catch (e: IllegalArgumentException) {
            result.error("provider_error", e.message, null)
            return
        }

        // Try Instagram Stories first; fall back to the system share sheet.
        if (shareToInstagramStory(uri, topColor, bottomColor)) {
            result.success("story")
        } else {
            shareViaChooser(uri)
            result.success("chooser")
        }
    }

    /**
     * Launches the Instagram Stories composer with our PNG as an interactive
     * sticker over a colour gradient. Returns false if Instagram can't handle it
     * (not installed / older version), so the caller can fall back.
     */
    private fun shareToInstagramStory(uri: Uri, top: String?, bottom: String?): Boolean {
        val intent = Intent("com.instagram.share.ADD_TO_STORY").apply {
            setPackage(instagramPackage)
            // Instagram's ADD_TO_STORY filter matches on a MIME type; without it
            // the intent won't resolve (even with the extras below).
            type = "image/png"
            putExtra("interactive_asset_uri", uri)
            if (!top.isNullOrEmpty()) putExtra("top_background_color", top)
            if (!bottom.isNullOrEmpty()) putExtra("bottom_background_color", bottom)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }

        // Instagram reads interactive_asset_uri in its own process — grant it
        // explicitly in addition to the intent flag.
        grantUriPermission(
            instagramPackage, uri, Intent.FLAG_GRANT_READ_URI_PERMISSION
        )

        // Launch directly and let ActivityNotFoundException drive the fallback —
        // more reliable than resolveActivity(), which is finicky for custom
        // actions / package visibility.
        return try {
            startActivity(intent)
            true
        } catch (e: ActivityNotFoundException) {
            false
        }
    }

    /** Standard Android share sheet fallback (image/png). */
    private fun shareViaChooser(uri: Uri) {
        val send = Intent(Intent.ACTION_SEND).apply {
            type = "image/png"
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivity(Intent.createChooser(send, "Share ride"))
    }
}
