package com.qrfiletransfer.app.ui

import android.Manifest
import android.content.ContentValues
import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.util.Size
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.common.InputImage
import com.qrfiletransfer.app.QrProtocol
import java.io.File
import java.util.concurrent.Executors
import kotlinx.coroutines.delay

/** Статус сканирования для подсказок пользователю. */
private enum class ScanStatus { Idle, Reading, Interrupted, Success }

/** Собирает части одного файла, полученные из QR-кодов. */
private class ReceiveSession(val header: QrProtocol.Header) {
    val parts = arrayOfNulls<ByteArray>(header.total)
    var count = 0

    @Synchronized
    fun add(chunk: QrProtocol.Chunk): Boolean {
        if (chunk.index !in 1..header.total) return false
        val idx = chunk.index - 1
        if (parts[idx] != null) return false
        parts[idx] = chunk.bytes
        count++
        return true
    }

    fun assemble(): ByteArray {
        val size = parts.sumOf { it?.size ?: 0 }
        val out = ByteArray(size)
        var off = 0
        parts.forEach { p ->
            if (p != null) {
                p.copyInto(out, off)
                off += p.size
            }
        }
        return out
    }
}

@Composable
fun ReceiveScreen(onBack: () -> Unit) {
    val context = LocalContext.current
    val mainHandler = remember { Handler(Looper.getMainLooper()) }
    val sessions = remember { HashMap<String, ReceiveSession>() }

    val cameraAlreadyGranted = ContextCompat.checkSelfPermission(
        context, Manifest.permission.CAMERA
    ) == PackageManager.PERMISSION_GRANTED
    var cameraGranted by remember { mutableStateOf(cameraAlreadyGranted) }
    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted -> cameraGranted = granted }

    var progress by remember { mutableStateOf(0f) }
    var done by remember { mutableStateOf(0) }
    var total by remember { mutableStateOf(0) }
    var info by remember { mutableStateOf("Наведите камеру на QR-код отправителя") }
    var savedName by remember { mutableStateOf<String?>(null) }
    var savedLocation by remember { mutableStateOf("") }
    var failInfo by remember { mutableStateOf<String?>(null) }
    var scanStatus by remember { mutableStateOf(ScanStatus.Idle) }
    var lastActivity by remember { mutableStateOf(0L) }

    fun handle(text: String) {
        QrProtocol.parseHeader(text)?.let { h ->
            val s = sessions[h.sid]
            if (s == null) {
                sessions[h.sid] = ReceiveSession(h)
            }
            mainHandler.post {
                progress = 0f
                done = 0
                total = h.total
                info = "Получение: ${h.name} • ${h.total} частей"
                failInfo = null
                savedName = null
                scanStatus = ScanStatus.Reading
                lastActivity = System.currentTimeMillis()
            }
            return
        }

        val chunk = QrProtocol.parseChunk(text) ?: return
        val sid = chunk.sid
        val s = sessions[sid] ?: return
        if (chunk.crc != QrProtocol.crc32(chunk.bytes)) return

        val newlyAdded = s.add(chunk)
        if (!newlyAdded) return

        mainHandler.post {
            done = s.count
            progress = s.count.toFloat() / s.header.total
            scanStatus = ScanStatus.Reading
            lastActivity = System.currentTimeMillis()
        }

        if (s.count == s.header.total) {
            val full = s.assemble()
            if (QrProtocol.sha256Hex(full) != s.header.sha256) {
                mainHandler.post { failInfo = "Контрольная сумма не совпала. Отправьте файл заново." }
            } else {
                val saved = saveReceived(context, full, s.header.name, s.header.mime)
                mainHandler.post {
                    if (saved != null) {
                        info = "Готово: ${s.header.name}"
                        savedName = s.header.name
                        savedLocation = when {
                            s.header.mime.startsWith("image/") -> "галерею (Фото)"
                            s.header.mime.startsWith("video/") -> "галерею (Видео)"
                            else -> "Загрузки"
                        }
                        scanStatus = ScanStatus.Success
                    } else {
                        failInfo = "Не удалось сохранить файл"
                    }
                }
            }
        }
    }

    // Если отправитель долго не даёт новый QR-код — помечаем чтение прерванным.
    LaunchedEffect(total, done) {
        while (true) {
            if (total > 0 &&
                done < total &&
                scanStatus != ScanStatus.Success &&
                scanStatus == ScanStatus.Reading
            ) {
                if (System.currentTimeMillis() - lastActivity > 2500) {
                    scanStatus = ScanStatus.Interrupted
                }
            }
            delay(500)
        }
    }

    Column(Modifier.fillMaxSize()) {
        OutlinedButton(
            onClick = onBack,
            modifier = Modifier.padding(16.dp)
        ) {
            Text("← Назад")
        }

        BoxWithConstraints(Modifier.fillMaxSize()) {
            val scanSide = (minOf(maxWidth, maxHeight) * 0.68f).coerceIn(200.dp, 340.dp)
            val statusColor = when (scanStatus) {
                ScanStatus.Idle -> Color.White
                ScanStatus.Reading -> Color(0xFF4CAF50)
                ScanStatus.Interrupted -> Color(0xFFFFC107)
                ScanStatus.Success -> Color(0xFF4CAF50)
            }
            val statusText = when (scanStatus) {
                ScanStatus.Idle -> "Наведите камеру на квадрат"
                ScanStatus.Reading -> "Считывается: $done / $total"
                ScanStatus.Interrupted -> "Считывание прервано — поднесите ближе"
                ScanStatus.Success -> "Считывание прошло успешно — файл передан"
            }

            if (cameraGranted) {
                CameraPreview(
                    modifier = Modifier.fillMaxSize(),
                    onBarcode = ::handle
                )

                // Поле-квадрат для наведения сканера.
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(bottom = 160.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Box(
                        modifier = Modifier
                            .size(scanSide)
                            .border(3.dp, statusColor, RoundedCornerShape(20.dp))
                    ) {
                        Box(
                            modifier = Modifier
                                .align(Alignment.Center)
                                .size(scanSide * 0.92f)
                                .border(1.dp, statusColor.copy(alpha = 0.45f), RoundedCornerShape(14.dp))
                        )
                    }
                }

                // Статус поверх рамки.
                Box(
                    modifier = Modifier.fillMaxSize(),
                    contentAlignment = Alignment.TopCenter
                ) {
                    Text(
                        text = statusText,
                        color = statusColor,
                        textAlign = TextAlign.Center,
                        modifier = Modifier
                            .padding(top = 8.dp)
                            .background(Color(0xB3000000), RoundedCornerShape(12.dp))
                            .border(2.dp, statusColor, RoundedCornerShape(12.dp))
                            .padding(horizontal = 16.dp, vertical = 8.dp)
                    )
                }
            } else {
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(24.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center
                ) {
                    Text(
                        "Камера выключена. Для приёма файлов дайте доступ к камере.",
                        style = MaterialTheme.typography.titleMedium,
                        textAlign = TextAlign.Center
                    )
                    Spacer(modifier = Modifier.size(16.dp))
                    Button(onClick = { permissionLauncher.launch(Manifest.permission.CAMERA) }) {
                        Text("Разрешить доступ к камере")
                    }
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(
                        "Если кнопка не помогла, включите камеру в настройках приложения.",
                        style = MaterialTheme.typography.bodySmall,
                        textAlign = TextAlign.Center
                    )
                }
            }

            Column(
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .fillMaxWidth()
                    .widthIn(max = 520.dp)
                    .padding(16.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Text(info, style = MaterialTheme.typography.titleMedium, textAlign = TextAlign.Center)
                if (total > 0) {
                    Spacer(modifier = Modifier.size(8.dp))
                    LinearProgressIndicator(
                        progress = { progress.coerceIn(0f, 1f) },
                        modifier = Modifier.fillMaxWidth()
                    )
                    Text("Принято частей: $done / $total", style = MaterialTheme.typography.bodySmall)
                }
                savedName?.let {
                    Spacer(modifier = Modifier.size(8.dp))
                    Text(
                        "Файл сохранён в $savedLocation: $it",
                        color = Color(0xFF2E7D32),
                        textAlign = TextAlign.Center
                    )
                }
                failInfo?.let {
                    Spacer(modifier = Modifier.size(8.dp))
                    Text(it, color = MaterialTheme.colorScheme.error, textAlign = TextAlign.Center)
                }
            }
        }
    }
}

@Composable
private fun CameraPreview(
    modifier: Modifier = Modifier,
    onBarcode: (String) -> Unit
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val previewView = remember { PreviewView(context) }
    val analysis = remember {
        ImageAnalysis.Builder()
            .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
            .setTargetResolution(Size(1280, 720))
            .build()
    }
    val scanner = remember { BarcodeScanning.getClient() }
    val analyzerExecutor = remember { Executors.newSingleThreadExecutor() }

    DisposableEffect(lifecycleOwner) {
        val providerFuture = ProcessCameraProvider.getInstance(context)

        providerFuture.addListener({
            val provider = providerFuture.get()
            val preview = Preview.Builder().build().also {
                it.setSurfaceProvider(previewView.surfaceProvider)
            }
            analysis.setAnalyzer(analyzerExecutor) { image ->
                val mediaImage = image.image ?: run {
                    image.close()
                    return@setAnalyzer
                }
                val input = InputImage.fromMediaImage(mediaImage, image.imageInfo.rotationDegrees)
                scanner.process(input)
                    .addOnSuccessListener { barcodes ->
                        for (b in barcodes) {
                            b.rawValue?.let(onBarcode)
                        }
                    }
                    .addOnCompleteListener { image.close() }
            }
            try {
                provider.unbindAll()
                provider.bindToLifecycle(
                    lifecycleOwner,
                    CameraSelector.DEFAULT_BACK_CAMERA,
                    preview,
                    analysis
                )
            } catch (e: Exception) {
                // камера недоступна
            }
        }, ContextCompat.getMainExecutor(context))

        onDispose {
            analysis.clearAnalyzer()
            analyzerExecutor.shutdown()
            providerFuture.get().unbindAll()
        }
    }

    AndroidView(
        factory = { previewView },
        modifier = modifier
    )
}

/**
 * Сохраняет файл в галерею (фото/видео) или в «Загрузки».
 * Android 10+ — через MediaStore, на старых версиях — в публичные папки.
 */
@Suppress("DEPRECATION")
private fun saveReceived(context: Context, bytes: ByteArray, name: String, mime: String): Uri? {
    return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
        try {
            val isImage = mime.startsWith("image/")
            val isVideo = mime.startsWith("video/")
            val collection = when {
                isImage -> MediaStore.Images.Media.EXTERNAL_CONTENT_URI
                isVideo -> MediaStore.Video.Media.EXTERNAL_CONTENT_URI
                else -> MediaStore.Downloads.EXTERNAL_CONTENT_URI
            }
            val relativePath = when {
                isImage -> "Pictures/QRFileTransfer"
                isVideo -> "Movies/QRFileTransfer"
                else -> "Download/QRFileTransfer"
            }
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, name)
                put(MediaStore.MediaColumns.MIME_TYPE, mime)
                put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath)
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            val uri = context.contentResolver.insert(collection, values) ?: return null
            context.contentResolver.openOutputStream(uri)?.use { it.write(bytes) } ?: return null
            values.clear()
            values.put(MediaStore.MediaColumns.IS_PENDING, 0)
            context.contentResolver.update(uri, values, null, null)
            uri
        } catch (e: Exception) {
            null
        }
    } else {
        try {
            val isImage = mime.startsWith("image/")
            val isVideo = mime.startsWith("video/")
            val subDir = when {
                isImage -> Environment.DIRECTORY_PICTURES
                isVideo -> Environment.DIRECTORY_MOVIES
                else -> Environment.DIRECTORY_DOWNLOADS
            }
            val dir = File(
                Environment.getExternalStoragePublicDirectory(subDir),
                "QRFileTransfer"
            )
            dir.mkdirs()
            val f = File(dir, name)
            f.writeBytes(bytes)
            Uri.fromFile(f)
        } catch (e: Exception) {
            null
        }
    }
}