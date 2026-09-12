package com.qrfiletransfer.app.ui

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.qrfiletransfer.app.QrGenerator
import com.qrfiletransfer.app.QrProtocol
import kotlinx.coroutines.delay

@Composable
fun SendScreen(onBack: () -> Unit) {
    val context = LocalContext.current
    var fileName by remember { mutableStateOf<String?>(null) }
    var fileInfo by remember { mutableStateOf("") }
    var sid by remember { mutableStateOf("") }
    var headerText by remember { mutableStateOf<String?>(null) }
    // chunks: пары (номер фрагмента, байты)
    var chunks by remember { mutableStateOf<List<Pair<Int, ByteArray>>>(emptyList()) }
    var currentIndex by remember { mutableStateOf(0) }
    var playing by remember { mutableStateOf(false) }
    var finished by remember { mutableStateOf(false) }
    var speedMs by remember { mutableStateOf(500) }
    var error by remember { mutableStateOf<String?>(null) }

    val picker = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocument()
    ) { uri ->
        uri ?: return@rememberLauncherForActivityResult
        try {
            val name = uri.lastPathSegment ?: "file"
            val mime = context.contentResolver.getType(uri) ?: "application/octet-stream"
            val bytes = context.contentResolver.openInputStream(uri)?.readBytes()
                ?: throw Exception("Не удалось прочитать файл")
            if (bytes.isEmpty()) throw Exception("Пустой файл")
            if (bytes.size > QrProtocol.MAX_FILE_SIZE) throw Exception("Файл больше 100 МБ")

            val total = QrProtocol.chunkCount(bytes.size.toLong())
            val newSid = QrProtocol.newSessionId()
            val header = QrProtocol.buildHeader(
                sid = newSid,
                name = name,
                mime = mime,
                size = bytes.size.toLong(),
                sha256 = QrProtocol.sha256Hex(bytes),
                totalChunks = total
            )
            val parts = (1..total).map { i ->
                val from = (i - 1) * QrProtocol.CHUNK_RAW_SIZE
                val to = minOf(from + QrProtocol.CHUNK_RAW_SIZE, bytes.size)
                i to bytes.copyOfRange(from, to)
            }
            sid = newSid
            headerText = header
            chunks = parts
            fileName = name
            fileInfo = "${bytes.size / 1024} КБ • $total частей"
            currentIndex = 0
            finished = false
            error = null
            playing = true
        } catch (e: Exception) {
            error = e.message
        }
    }

    // Автопрокрутка QR-кодов: показывает заголовок, затем фрагменты 1..total.
    LaunchedEffect(playing, currentIndex, chunks.size) {
        if (!playing) return@LaunchedEffect
        if (chunks.isEmpty()) return@LaunchedEffect
        if (currentIndex > chunks.size) {
            playing = false
            finished = true
            return@LaunchedEffect
        }
        delay(speedMs.toLong())
        currentIndex++
    }

    // Текст текущего QR-кода пересчитывается только при смене индекса.
    val qrText = remember(currentIndex, headerText, chunks) {
        when {
            headerText == null -> null
            currentIndex == 0 -> headerText
            else -> {
                val (idx, bytes) = chunks[currentIndex - 1]
                QrProtocol.buildData(sid, idx, bytes, QrProtocol.crc32(bytes))
            }
        }
    }
    val qrBitmap = remember(qrText) { qrText?.let { QrGenerator.encode(it) } }

    val totalSteps = chunks.size + 1
    val progress = (currentIndex.coerceAtMost(totalSteps)).toFloat() / totalSteps

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically
        ) {
            OutlinedButton(onClick = onBack) { Text("← Назад") }
            Spacer(modifier = Modifier.weight(1f))
            Text("Отправка", style = MaterialTheme.typography.headlineSmall)
            Spacer(modifier = Modifier.weight(1f))
        }

        Spacer(modifier = Modifier.height(16.dp))

        if (qrText == null) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(
                    "Выберите файл для отправки.\n" +
                        "Поднесите телефоны друг к другу и отсканируйте появившиеся QR-коды.",
                    textAlign = TextAlign.Center
                )
                Button(onClick = { picker.launch(arrayOf("*/*")) }) {
                    Text("Выбрать файл")
                }
            }
        } else {
            fileName?.let { Text(it, style = MaterialTheme.typography.titleMedium) }
            Text(fileInfo, style = MaterialTheme.typography.bodySmall)

            Spacer(modifier = Modifier.height(12.dp))

            qrBitmap?.let { bmp ->
                Image(
                    bitmap = bmp.asImageBitmap(),
                    contentDescription = "QR-код части файла",
                    modifier = Modifier.size(320.dp)
                )
            }

            Spacer(modifier = Modifier.height(16.dp))

            LinearProgressIndicator(
                progress = { progress },
                modifier = Modifier.fillMaxWidth()
            )
            Text(
                "Часть ${minOf(currentIndex.coerceAtLeast(1), chunks.size)} из ${chunks.size} • " +
                    "${(progress * 100).toInt()}%",
                style = MaterialTheme.typography.bodySmall
            )

            Spacer(modifier = Modifier.height(12.dp))

            Row {
                Button(onClick = { playing = !playing }) {
                    Text(if (playing) "Пауза" else "Продолжить")
                }
                if (finished) {
                    Spacer(modifier = Modifier.size(8.dp))
                    Button(onClick = {
                        headerText = null
                        chunks = emptyList()
                        fileName = null
                        currentIndex = 0
                        playing = false
                        finished = false
                    }) {
                        Text("Заново")
                    }
                }
            }

            Spacer(modifier = Modifier.height(12.dp))

            Text(
                "Скорость: ${speedMs.toInt()} мс на QR-код",
                style = MaterialTheme.typography.bodySmall
            )
            Slider(
                value = speedMs.toFloat(),
                onValueChange = { speedMs = it.toInt() },
                valueRange = 150f..2000f
            )

            if (finished) {
                Text(
                    "Готово! Все части показаны. Получатель должен собрать файл.",
                    color = Color(0xFF2E7D32),
                    textAlign = TextAlign.Center
                )
            }
        }

        error?.let {
            Spacer(modifier = Modifier.height(8.dp))
            Text(it, color = MaterialTheme.colorScheme.error)
        }
    }
}