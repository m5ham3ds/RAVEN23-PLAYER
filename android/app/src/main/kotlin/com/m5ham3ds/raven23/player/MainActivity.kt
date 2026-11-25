package com.m5ham3ds.raven23.player

import android.content.ContentUris
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.Locale
import java.util.UUID

class MainActivity : FlutterActivity() {
    private val channelName = "com.m5ham3ds.raven23.player/media_library"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "listVideos" -> result.success(scanMediaLibrary())
                        "cacheSubtitle" -> {
                            val rawUri = call.argument<String>("uri")
                            if (rawUri.isNullOrBlank()) {
                                result.error("INVALID_URI", "Subtitle URI is required.", null)
                            } else {
                                result.success(
                                    copyUriToCache(
                                        Uri.parse(rawUri),
                                        call.argument<String>("displayName"),
                                        "subtitles",
                                    ).absolutePath,
                                )
                            }
                        }
                        "cacheContentUri" -> {
                            val rawUri = call.argument<String>("uri")
                            if (rawUri.isNullOrBlank()) {
                                result.error("INVALID_URI", "Media URI is required.", null)
                            } else {
                                result.success(
                                    copyUriToCache(
                                        Uri.parse(rawUri),
                                        call.argument<String>("preferredName"),
                                        "transfer",
                                    ).absolutePath,
                                )
                            }
                        }
                        else -> result.notImplemented()
                    }
                } catch (error: SecurityException) {
                    result.error("MEDIA_PERMISSION_DENIED", error.message, null)
                } catch (error: Exception) {
                    result.error("MEDIA_LIBRARY_ERROR", error.message, null)
                }
            }
    }

    private fun scanMediaLibrary(): Map<String, Any> {
        return mapOf(
            "videos" to queryVideos(),
            "subtitles" to querySubtitleSidecars(),
        )
    }

    @Suppress("DEPRECATION")
    private fun queryVideos(): List<Map<String, Any?>> {
        val collection = MediaStore.Video.Media.EXTERNAL_CONTENT_URI
        val projection = mutableListOf(
            MediaStore.Video.Media._ID,
            MediaStore.Video.Media.DISPLAY_NAME,
            MediaStore.Video.Media.DURATION,
            MediaStore.Video.Media.SIZE,
            MediaStore.Video.Media.DATE_ADDED,
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            projection.add(MediaStore.MediaColumns.RELATIVE_PATH)
            projection.add(MediaStore.MediaColumns.IS_PENDING)
        } else {
            projection.add(MediaStore.Video.Media.DATA)
        }

        val selection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            MediaStore.MediaColumns.IS_PENDING + " = 0"
        } else {
            null
        }
        val rows = mutableListOf<Map<String, Any?>>()
        contentResolver.query(
            collection,
            projection.toTypedArray(),
            selection,
            null,
            MediaStore.Video.Media.DATE_ADDED + " DESC",
        )?.use { cursor ->
            val idColumn = cursor.getColumnIndexOrThrow(MediaStore.Video.Media._ID)
            val nameColumn = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.DISPLAY_NAME)
            val durationColumn = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.DURATION)
            val sizeColumn = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.SIZE)
            val dateColumn = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.DATE_ADDED)
            val pathColumn = cursor.getColumnIndex(MediaStore.Video.Media.DATA)
            val relativeColumn = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                cursor.getColumnIndex(MediaStore.MediaColumns.RELATIVE_PATH)
            } else {
                -1
            }

            while (cursor.moveToNext()) {
                val id = cursor.getLong(idColumn)
                val uri = ContentUris.withAppendedId(collection, id)
                rows.add(
                    mapOf(
                        "id" to id.toString(),
                        "displayName" to cursor.getString(nameColumn),
                        "path" to if (pathColumn >= 0 && !cursor.isNull(pathColumn)) {
                            cursor.getString(pathColumn)
                        } else {
                            null
                        },
                        "uri" to uri.toString(),
                        "durationMs" to cursor.getLong(durationColumn),
                        "sizeBytes" to cursor.getLong(sizeColumn),
                        "dateAddedSeconds" to cursor.getLong(dateColumn),
                        "relativePath" to if (relativeColumn >= 0 && !cursor.isNull(relativeColumn)) {
                            cursor.getString(relativeColumn)
                        } else {
                            ""
                        },
                    ),
                )
            }
        }
        return rows
    }

    @Suppress("DEPRECATION")
    private fun querySubtitleSidecars(): List<Map<String, Any?>> {
        val collection = MediaStore.Files.getContentUri("external")
        val nameColumn = MediaStore.MediaColumns.DISPLAY_NAME
        val extensions = listOf("%.srt", "%.vtt", "%.ass", "%.ssa")
        val selection = extensions.joinToString(" OR ") {
            "LOWER($nameColumn) LIKE ?"
        }
        val projection = mutableListOf(
            MediaStore.MediaColumns._ID,
            MediaStore.MediaColumns.DISPLAY_NAME,
            MediaStore.MediaColumns.MIME_TYPE,
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            projection.add(MediaStore.MediaColumns.RELATIVE_PATH)
            projection.add(MediaStore.MediaColumns.IS_PENDING)
        } else {
            projection.add(MediaStore.MediaColumns.DATA)
        }

        return try {
            val rows = mutableListOf<Map<String, Any?>>()
            val querySelection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                "(" + selection + ") AND " + MediaStore.MediaColumns.IS_PENDING + " = 0"
            } else {
                selection
            }
            contentResolver.query(
                collection,
                projection.toTypedArray(),
                querySelection,
                extensions.toTypedArray(),
                MediaStore.MediaColumns.DATE_ADDED + " DESC",
            )?.use { cursor ->
                val idColumn = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns._ID)
                val nameIndex = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DISPLAY_NAME)
                val mimeIndex = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.MIME_TYPE)
                val pathIndex = cursor.getColumnIndex(MediaStore.MediaColumns.DATA)
                val relativeIndex = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    cursor.getColumnIndex(MediaStore.MediaColumns.RELATIVE_PATH)
                } else {
                    -1
                }
                while (cursor.moveToNext()) {
                    val id = cursor.getLong(idColumn)
                    rows.add(
                        mapOf(
                            "id" to id.toString(),
                            "displayName" to cursor.getString(nameIndex),
                            "path" to if (pathIndex >= 0 && !cursor.isNull(pathIndex)) {
                                cursor.getString(pathIndex)
                            } else {
                                null
                            },
                            "uri" to ContentUris.withAppendedId(collection, id).toString(),
                            "mimeType" to cursor.getString(mimeIndex),
                            "relativePath" to if (relativeIndex >= 0 && !cursor.isNull(relativeIndex)) {
                                cursor.getString(relativeIndex)
                            } else {
                                ""
                            },
                        ),
                    )
                }
            }
            rows
        } catch (_: SecurityException) {
            // Android 13+ does not grant broad access to arbitrary document
            // files with READ_MEDIA_VIDEO. Phase 01 adds a SAF folder grant for
            // subtitle sidecars; this best-effort query still supports older OS.
            emptyList()
        }
    }

    private fun copyUriToCache(
        uri: Uri,
        displayName: String?,
        subdirectory: String,
    ): File {
        require(uri.scheme == "content") { "Only content URIs can be copied." }
        val sourceName = displayName
            ?.substringAfterLast('/')
            ?.takeIf { it.isNotBlank() }
            ?: "media"
        val extension = sourceName.substringAfterLast('.', "").lowercase(Locale.ROOT)
            .takeIf { it.matches(Regex("[a-z0-9]{1,8}")) }
            ?.let { ".$it" }
            ?: ""
        val directory = File(cacheDir, "raven23-player/$subdirectory")
        check(directory.exists() || directory.mkdirs()) {
            "Could not create temporary media directory."
        }
        val destination = File(directory, UUID.randomUUID().toString() + extension)
        val input = contentResolver.openInputStream(uri)
            ?: throw IllegalStateException("The media provider returned no readable stream.")
        input.use { source ->
            FileOutputStream(destination).use { target ->
                source.copyTo(target, 1024 * 1024)
                target.fd.sync()
            }
        }
        return destination
    }
}
