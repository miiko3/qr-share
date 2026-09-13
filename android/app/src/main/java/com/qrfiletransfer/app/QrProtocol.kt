package com.qrfiletransfer.app

import android.util.Base64
import org.json.JSONObject
import java.security.MessageDigest
import java.util.UUID
import java.util.zip.CRC32

/**
 * QrProtocol — формат содержимого QR-кодов.
 *
 * Каждый QR-код — это компактный JSON.
 *
 * Заголовок сессии ("t":"h"):
 *   {"v":1,"t":"h","sid":"<16 hex>","name":"photo.jpg","mime":"image/jpeg",
 *    "size":5242880,"sha":"<sha256 hex>","total":6554,"cs":800,"nonce":"<8 hex>"}
 *
 * Фрагмент данных ("t":"d"):
 *   {"v":1,"t":"d","sid":"<16 hex>","i":123,"d":"<base64>","c":"0a1b2c3d"}
 *     i   — номер фрагмента (1..total)
 *     d   — base64 фрагмента файла (CHUNK_RAW_SIZE байт)
 *     c   — CRC-32 фрагмента (8 hex)
 *
 * Каждая сессия начинается со случайного sid, а заголовок содержит случайный
 * nonce, поэтому QR-коды всегда разные — даже для одного и того же файла.
 */
object QrProtocol {
    const val VERSION = 1
    const val CHUNK_RAW_SIZE = 800
    const val MAX_FILE_SIZE = 99L * 1024 * 1024

    private const val TYPE_HEADER = "h"
    private const val TYPE_DATA = "d"

    fun newSessionId(): String =
        UUID.randomUUID().toString().replace("-", "").take(16)

    fun buildHeader(
        sid: String,
        name: String,
        mime: String,
        size: Long,
        sha256: String,
        totalChunks: Int,
        chunkRaw: Int = CHUNK_RAW_SIZE,
        nonce: String = UUID.randomUUID().toString().replace("-", "").take(8)
    ): String = JSONObject()
        .put("v", VERSION)
        .put("t", TYPE_HEADER)
        .put("sid", sid)
        .put("name", name)
        .put("mime", mime)
        .put("size", size)
        .put("sha", sha256)
        .put("total", totalChunks)
        .put("cs", chunkRaw)
        .put("nonce", nonce)
        .toString()

    fun buildData(sid: String, index: Int, raw: ByteArray, crc: Int): String = JSONObject()
        .put("v", VERSION)
        .put("t", TYPE_DATA)
        .put("sid", sid)
        .put("i", index)
        .put("d", encode(raw))
        .put("c", crcHex(crc))
        .toString()

    fun crc32(raw: ByteArray): Int {
        val c = CRC32()
        c.update(raw)
        return c.value.toInt()
    }

    fun crcHex(crc: Int): String = String.format("%08x", crc)

    fun sha256Hex(bytes: ByteArray): String {
        val d = MessageDigest.getInstance("SHA-256").digest(bytes)
        return d.joinToString("") { "%02x".format(it) }
    }

    fun encode(b: ByteArray): String = Base64.encodeToString(b, Base64.NO_WRAP)
    fun decode(s: String): ByteArray = Base64.decode(s, Base64.DEFAULT)

    fun chunkCount(size: Long, chunkRaw: Int = CHUNK_RAW_SIZE): Int =
        ((size + chunkRaw - 1) / chunkRaw).toInt()

    data class Header(
        val sid: String,
        val name: String,
        val mime: String,
        val size: Long,
        val sha256: String,
        val total: Int,
        val chunkRaw: Int
    )

    fun parseHeader(json: String): Header? = try {
        val j = JSONObject(json)
        if (j.optString("t") != TYPE_HEADER || j.optInt("v") != VERSION) {
            null
        } else {
            Header(
                sid = j.getString("sid"),
                name = j.getString("name"),
                mime = j.optString("mime", "application/octet-stream"),
                size = j.getLong("size"),
                sha256 = j.getString("sha"),
                total = j.getInt("total"),
                chunkRaw = j.optInt("cs", CHUNK_RAW_SIZE)
            )
        }
    } catch (e: Exception) {
        null
    }

    data class Chunk(
        val sid: String,
        val index: Int,
        val bytes: ByteArray,
        val crc: Int
    )

    fun parseChunk(json: String): Chunk? = try {
        val j = JSONObject(json)
        if (j.optString("t") != TYPE_DATA || j.optInt("v") != VERSION) {
            null
        } else {
            Chunk(
                sid = j.getString("sid"),
                index = j.getInt("i"),
                bytes = decode(j.getString("d")),
                crc = j.optString("c", "0").toInt(16)
            )
        }
    } catch (e: Exception) {
        null
    }
}