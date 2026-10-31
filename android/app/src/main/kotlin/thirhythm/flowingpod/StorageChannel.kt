package thirhythm.flowingpod

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.Settings
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Storage helpers for downloads: shared-storage access and a folder picker.
 *
 * Android 11 and later can only write to shared folders with "all files"
 * access, so the permission is requested through the system settings screen.
 * The picked directory is resolved to an absolute path because downloads are
 * written with regular file IO.
 */
class StorageChannel(private val activity: Activity) {
    private var permissionResult: MethodChannel.Result? = null
    private var directoryResult: MethodChannel.Result? = null

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "hasAccess" -> result.success(hasAccess())
            "requestAccess" -> requestAccess(result)
            "pickDirectory" -> pickDirectory(result)
            else -> result.notImplemented()
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        when (requestCode) {
            REQUEST_ACCESS -> completePermission()
            REQUEST_DIRECTORY -> {
                val result = directoryResult ?: return
                directoryResult = null
                if (resultCode != Activity.RESULT_OK) {
                    result.success(null)
                    return
                }
                val uri = data?.data
                if (uri == null) {
                    result.success(null)
                    return
                }
                try {
                    activity.contentResolver.takePersistableUriPermission(
                        uri,
                        Intent.FLAG_GRANT_READ_URI_PERMISSION or
                            Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
                    )
                } catch (_: SecurityException) {
                    // The path below is still usable while all-files access is held.
                }
                result.success(treeUriToPath(uri))
            }
        }
    }

    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray) {
        if (requestCode == REQUEST_ACCESS) completePermission()
    }

    /**
     * Users may grant access and return through the recents screen, which does
     * not deliver an activity result; complete the pending request then.
     */
    fun onResume() {
        if (permissionResult != null && hasAccess()) completePermission()
    }

    private fun completePermission() {
        val result = permissionResult ?: return
        permissionResult = null
        result.success(hasAccess())
    }

    private fun hasAccess(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Environment.isExternalStorageManager()
        } else {
            activity.checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) ==
                PackageManager.PERMISSION_GRANTED
        }

    private fun requestAccess(result: MethodChannel.Result) {
        if (hasAccess()) {
            result.success(true)
            return
        }
        if (permissionResult != null) {
            result.error("busy", "Another storage permission request is running", null)
            return
        }
        permissionResult = result
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val intent = Intent(
                Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                Uri.parse("package:${activity.packageName}"),
            )
            try {
                activity.startActivityForResult(intent, REQUEST_ACCESS)
            } catch (_: Exception) {
                try {
                    activity.startActivityForResult(
                        Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION),
                        REQUEST_ACCESS,
                    )
                } catch (_: Exception) {
                    completePermission()
                }
            }
        } else {
            activity.requestPermissions(
                arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE),
                REQUEST_ACCESS,
            )
        }
    }

    private fun pickDirectory(result: MethodChannel.Result) {
        if (directoryResult != null) {
            result.error("busy", "Another folder picker is open", null)
            return
        }
        directoryResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
            )
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                putExtra(
                    DocumentsContract.EXTRA_INITIAL_URI,
                    Uri.parse("content://com.android.externalstorage.documents/document/primary%3AMusic"),
                )
            }
        }
        try {
            activity.startActivityForResult(intent, REQUEST_DIRECTORY)
        } catch (_: Exception) {
            directoryResult = null
            result.success(null)
        }
    }

    /** Maps a document tree to an absolute path; only local volumes map. */
    private fun treeUriToPath(uri: Uri): String? {
        val documentId = try {
            DocumentsContract.getTreeDocumentId(uri)
        } catch (_: Exception) {
            return null
        }
        val parts = documentId.split(":", limit = 2)
        val volume = parts.firstOrNull()?.takeIf { it.isNotEmpty() } ?: return null
        val relative = parts.getOrNull(1).orEmpty()
        val root = when (volume) {
            "primary" -> Environment.getExternalStorageDirectory()
            "home" -> Environment.getExternalStoragePublicDirectory(
                Environment.DIRECTORY_DOCUMENTS,
            )
            "downloads" -> Environment.getExternalStoragePublicDirectory(
                Environment.DIRECTORY_DOWNLOADS,
            )
            else -> File("/storage/$volume")
        }
        val directory = if (relative.isEmpty()) root else File(root, relative)
        return try {
            if (directory.exists() || directory.mkdirs()) directory.absolutePath else null
        } catch (_: Exception) {
            null
        }
    }

    private companion object {
        const val REQUEST_ACCESS = 5210
        const val REQUEST_DIRECTORY = 5211
    }
}
