package com.hermes.hermes_app

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/**
 * Copies voice models from a folder the person picks (Android's folder
 * picker) into Hermsy's own model folder, so a new install does not have to
 * download them again. Only the model folders Dart names are copied; Dart
 * checks them afterwards.
 */
class ModelImport(private val activity: Activity, private val channel: MethodChannel) {
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private var pending: MethodChannel.Result? = null
    private var target: File? = null
    private var folders: List<String> = emptyList()

    /** Opens the picker; [result] gets the model folders copied. */
    fun pick(targetDir: String, modelFolders: List<String>, result: MethodChannel.Result) {
        if (pending != null) {
            result.error("busy", "An import is already running", null)
            return
        }
        pending = result
        target = File(targetDir)
        folders = modelFolders
        activity.startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE), REQUEST)
    }

    /** From MainActivity.onActivityResult. True when it was ours. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST) {
            return false
        }
        val result = pending ?: return true
        val tree = data?.data
        if (resultCode != Activity.RESULT_OK || tree == null) {
            pending = null
            result.success(emptyList<String>())
            return true
        }
        val into = target!!
        worker.execute {
            try {
                val copied = copyModels(tree, into)
                main.post {
                    pending = null
                    result.success(copied)
                }
            } catch (error: Exception) {
                main.post {
                    pending = null
                    result.error("copy", error.message ?: "Could not copy the models", null)
                }
            }
        }
        return true
    }

    private data class Entry(val id: String, val name: String, val isDir: Boolean, val size: Long)

    private fun children(tree: Uri, parentId: String): List<Entry> {
        val uri = DocumentsContract.buildChildDocumentsUriUsingTree(tree, parentId)
        val out = mutableListOf<Entry>()
        activity.contentResolver.query(
            uri,
            arrayOf(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                DocumentsContract.Document.COLUMN_MIME_TYPE,
                DocumentsContract.Document.COLUMN_SIZE,
            ),
            null,
            null,
            null,
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                out += Entry(
                    id = cursor.getString(0),
                    name = cursor.getString(1),
                    isDir = cursor.getString(2) == DocumentsContract.Document.MIME_TYPE_DIR,
                    size = if (cursor.isNull(3)) 0 else cursor.getLong(3),
                )
            }
        }
        return out
    }

    /**
     * Finds the model folders in the picked folder (or one level down, if
     * the person picked the folder that holds "voice_models") and copies
     * each one whole.
     */
    private fun copyModels(tree: Uri, into: File): List<String> {
        val rootId = DocumentsContract.getTreeDocumentId(tree)
        var top = children(tree, rootId)
        if (top.none { it.isDir && it.name in folders }) {
            val nested = top.firstOrNull { it.isDir && it.name == "voice_models" }
            if (nested != null) {
                top = children(tree, nested.id)
            }
        }
        val found = top.filter { it.isDir && it.name in folders }
        val total = found.sumOf { sizeOf(tree, it) }.coerceAtLeast(1)
        var done = 0L
        val copied = mutableListOf<String>()
        for (folder in found) {
            val dest = File(into, folder.name)
            val staging = File(into, "${folder.name}.importing")
            staging.deleteRecursively()
            copyTree(tree, folder, staging) { bytes ->
                done += bytes
                val fraction = done.toDouble() / total
                main.post { channel.invokeMethod("progress", fraction) }
            }
            // The app counts a model ready only once Dart has checked it.
            File(staging, ".ready").delete()
            dest.deleteRecursively()
            if (!staging.renameTo(dest)) {
                throw IllegalStateException("Could not move ${folder.name} into place")
            }
            copied += folder.name
        }
        return copied
    }

    private fun sizeOf(tree: Uri, entry: Entry): Long =
        if (!entry.isDir) entry.size else children(tree, entry.id).sumOf { sizeOf(tree, it) }

    private fun copyTree(tree: Uri, entry: Entry, dest: File, onBytes: (Long) -> Unit) {
        if (entry.isDir) {
            dest.mkdirs()
            for (child in children(tree, entry.id)) {
                copyTree(tree, child, File(dest, child.name), onBytes)
            }
            return
        }
        val uri = DocumentsContract.buildDocumentUriUsingTree(tree, entry.id)
        activity.contentResolver.openInputStream(uri)!!.use { input ->
            dest.outputStream().use { output ->
                val buffer = ByteArray(1 shl 20)
                while (true) {
                    val read = input.read(buffer)
                    if (read < 0) break
                    output.write(buffer, 0, read)
                    onBytes(read.toLong())
                }
            }
        }
    }

    companion object {
        private const val REQUEST = 7302
    }
}
