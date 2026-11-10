package com.mtc.mina_robot

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothSocket
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Handler
import android.os.Looper
import android.util.Log
import java.io.OutputStream
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Bộ điều khiển Robot hình người Robonova-II (mạch MR-C3024FX) qua Bluetooth SPP (HC-06 / HC-05).
 *
 * - Chuẩn giao tiếp: RFCOMM SPP UUID 00001101-0000-1000-8000-00805F9B34FB (9600 baud ở phía HC-06 -> ERX).
 * - Mỗi hành động K1..K68 là 1 byte ASCII (DEC 40..108).
 * - Hỗ trợ tự động tìm và kết nối lại thiết bị HC-06 đã ghép đôi, hoặc gửi chuỗi liên hoàn quyền / vũ đạo.
 */
@SuppressLint("MissingPermission")
object RobonovaBluetoothController {
    private const val TAG = "RobonovaBT"
    private const val PREFS_NAME = "mina_robonova_bt"
    private const val KEY_LAST_ADDR = "last_bt_address"
    private const val KEY_LAST_NAME = "last_bt_name"

    private val SPP_UUID: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
    private val worker = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    private var socket: BluetoothSocket? = null

    @Volatile
    private var outputStream: OutputStream? = null

    @Volatile
    var connectedName: String = ""
        private set

    @Volatile
    var connectedAddress: String = ""
        private set

    @Volatile
    var lastStatusMessage: String = "Chưa kết nối Bluetooth HC-06"
        private set

    private val discoveredDevices = ConcurrentHashMap<String, String>()
    private val sequenceRunning = AtomicBoolean(false)

    val isConnected: Boolean
        get() = try {
            socket?.isConnected == true && outputStream != null
        } catch (_: Throwable) {
            false
        }

    fun getStatus(context: Context): Map<String, Any> {
        val adapter = BluetoothAdapter.getDefaultAdapter()
        val enabled = try {
            adapter?.isEnabled == true
        } catch (_: Throwable) {
            false
        }
        val list = getKnownDevices(context)
        return mapOf(
            "supported" to (adapter != null),
            "enabled" to enabled,
            "connected" to isConnected,
            "deviceName" to connectedName,
            "deviceAddress" to connectedAddress,
            "message" to lastStatusMessage,
            "devices" to list,
        )
    }

    fun getKnownDevices(context: Context): List<Map<String, Any>> {
        val adapter = BluetoothAdapter.getDefaultAdapter() ?: return emptyList()
        val result = mutableListOf<Map<String, Any>>()
        val seen = mutableSetOf<String>()

        try {
            if (!adapter.isEnabled) {
                adapter.enable()
            }
            val bonded = adapter.bondedDevices ?: emptySet()
            val sortedBonded = bonded.sortedByDescending { dev ->
                scoreDeviceName(dev.name ?: "")
            }
            for (dev in sortedBonded) {
                val addr = dev.address ?: continue
                val name = dev.name ?: "Thiết bị BT"
                seen.add(addr)
                result.add(
                    mapOf(
                        "name" to name,
                        "address" to addr,
                        "paired" to true,
                        "connected" to (isConnected && addr.equals(connectedAddress, ignoreCase = true)),
                    )
                )
            }
        } catch (t: Throwable) {
            Log.w(TAG, "getKnownDevices error: ${t.message}")
        }

        for ((addr, name) in discoveredDevices) {
            if (seen.add(addr)) {
                result.add(
                    mapOf(
                        "name" to name,
                        "address" to addr,
                        "paired" to false,
                        "connected" to (isConnected && addr.equals(connectedAddress, ignoreCase = true)),
                    )
                )
            }
        }
        return result
    }

    private fun scoreDeviceName(name: String): Int {
        val u = name.uppercase()
        return when {
            u.contains("HC-06") || u.contains("HC06") -> 100
            u.contains("HC-05") || u.contains("HC05") -> 95
            u.contains("ROBONOVA") || u.contains("ROBOT") -> 90
            u.contains("JDY") || u.contains("BT0") || u.contains("SPP") -> 80
            else -> 10
        }
    }

    fun scanDevices(context: Context, durationMs: Long = 4500L, onDone: (Map<String, Any>) -> Unit) {
        val appCtx = context.applicationContext
        val adapter = BluetoothAdapter.getDefaultAdapter()
        if (adapter == null) {
            lastStatusMessage = "Thiết bị này không có phần cứng Bluetooth"
            onDone(getStatus(appCtx))
            return
        }
        try {
            if (!adapter.isEnabled) {
                adapter.enable()
            }
        } catch (_: Throwable) {
        }

        val receiver = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context?, intent: Intent?) {
                if (intent?.action == BluetoothDevice.ACTION_FOUND) {
                    val dev = intent.getParcelableExtra<BluetoothDevice>(BluetoothDevice.EXTRA_DEVICE)
                    val addr = dev?.address ?: return
                    val name = dev.name ?: "BT-$addr"
                    discoveredDevices[addr] = name
                    Log.i(TAG, "Discovered BT device: $name ($addr)")
                }
            }
        }

        try {
            appCtx.registerReceiver(receiver, IntentFilter(BluetoothDevice.ACTION_FOUND))
            if (adapter.isDiscovering) adapter.cancelDiscovery()
            adapter.startDiscovery()
            lastStatusMessage = "Đang quét Bluetooth tìm HC-06..."
        } catch (t: Throwable) {
            Log.w(TAG, "startDiscovery error: ${t.message}")
        }

        mainHandler.postDelayed({
            try {
                adapter.cancelDiscovery()
            } catch (_: Throwable) {
            }
            try {
                appCtx.unregisterReceiver(receiver)
            } catch (_: Throwable) {
            }
            val list = getKnownDevices(appCtx)
            lastStatusMessage = "Tìm thấy ${list.size} thiết bị Bluetooth"
            onDone(getStatus(appCtx))
        }, durationMs)
    }

    fun connect(context: Context, targetAddress: String?, onResult: (Boolean, String) -> Unit) {
        val appCtx = context.applicationContext
        worker.execute {
            val (ok, msg) = connectBlocking(appCtx, targetAddress)
            mainHandler.post { onResult(ok, msg) }
        }
    }

    private fun connectBlocking(context: Context, targetAddress: String?): Pair<Boolean, String> {
        val adapter = BluetoothAdapter.getDefaultAdapter()
            ?: return Pair(false, "Không có phần cứng Bluetooth trên thiết bị này.")

        try {
            if (!adapter.isEnabled) {
                adapter.enable()
                Thread.sleep(1200)
            }
            if (adapter.isDiscovering) {
                adapter.cancelDiscovery()
            }
        } catch (_: Throwable) {
        }

        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        var address = targetAddress?.trim() ?: ""

        if (address.isEmpty()) {
            // 1. Thử tìm trong danh sách đã ghép đôi (ưu tiên HC-06 / HC-05 / ROBONOVA)
            val bonded = try {
                adapter.bondedDevices?.toList() ?: emptyList()
            } catch (_: Throwable) {
                emptyList()
            }
            val preferred = bonded.maxByOrNull { scoreDeviceName(it.name ?: "") }
            val savedAddr = prefs.getString(KEY_LAST_ADDR, "") ?: ""

            address = when {
                preferred != null && scoreDeviceName(preferred.name ?: "") >= 80 -> preferred.address
                savedAddr.isNotEmpty() -> savedAddr
                preferred != null -> preferred.address
                discoveredDevices.isNotEmpty() -> {
                    discoveredDevices.entries.maxByOrNull { scoreDeviceName(it.value) }?.key ?: ""
                }
                else -> ""
            }
        }

        if (address.isEmpty()) {
            lastStatusMessage = "Chưa ghép đôi HC-06. Hãy mở Cài đặt Bluetooth để ghép đôi HC-06 (PIN 1234)."
            return Pair(false, lastStatusMessage)
        }

        if (isConnected && address.equals(connectedAddress, ignoreCase = true)) {
            lastStatusMessage = "Đã kết nối sẵn với $connectedName ($connectedAddress)"
            return Pair(true, lastStatusMessage)
        }

        disconnectBlocking()

        val device = try {
            adapter.getRemoteDevice(address)
        } catch (t: Throwable) {
            lastStatusMessage = "Địa chỉ Bluetooth không hợp lệ: $address"
            return Pair(false, lastStatusMessage)
        }

        val devName = try {
            device.name ?: discoveredDevices[address] ?: "HC-06"
        } catch (_: Throwable) {
            "HC-06"
        }

        // Thử lần lượt 3 phương thức tạo RFCOMM socket để tương thích 100% với mọi module HC-06/HC-05 trên Android 8.1
        val socketFactories = listOf<() -> BluetoothSocket>(
            { device.createInsecureRfcommSocketToServiceRecord(SPP_UUID) },
            { device.createRfcommSocketToServiceRecord(SPP_UUID) },
            {
                val m = device.javaClass.getMethod("createRfcommSocket", Int::class.javaPrimitiveType)
                m.invoke(device, 1) as BluetoothSocket
            }
        )

        var lastErr = ""
        for (factory in socketFactories) {
            var candidate: BluetoothSocket? = null
            try {
                candidate = factory()
                candidate.connect()
                socket = candidate
                outputStream = candidate.outputStream
                connectedAddress = address
                connectedName = devName
                prefs.edit()
                    .putString(KEY_LAST_ADDR, address)
                    .putString(KEY_LAST_NAME, devName)
                    .apply()
                lastStatusMessage = "Đã kết nối Bluetooth với $devName ($address)"
                Log.i(TAG, lastStatusMessage)
                return Pair(true, lastStatusMessage)
            } catch (t: Throwable) {
                lastErr = t.message ?: t.javaClass.simpleName
                try {
                    candidate?.close()
                } catch (_: Throwable) {
                }
            }
        }

        lastStatusMessage = "Không kết nối được $devName ($address): $lastErr. Kiểm tra nguồn robot người & PIN 1234."
        Log.w(TAG, lastStatusMessage)
        return Pair(false, lastStatusMessage)
    }

    fun disconnect() {
        worker.execute {
            disconnectBlocking()
        }
    }

    private fun disconnectBlocking() {
        sequenceRunning.set(false)
        try {
            outputStream?.close()
        } catch (_: Throwable) {
        }
        try {
            socket?.close()
        } catch (_: Throwable) {
        }
        outputStream = null
        socket = null
        lastStatusMessage = "Đã ngắt kết nối Bluetooth"
    }

    /**
     * Gửi 1 byte lệnh ASCII (DEC 40..108) tới mạch MR-C3024FX qua HC-06.
     * Nếu chưa kết nối thì tự động thử kết nối tới HC-06 đã lưu / ghép đôi.
     */
    fun sendActionByte(
        context: Context,
        asciiByte: Int,
        actionLabel: String,
        onResult: (Boolean, String) -> Unit
    ) {
        val appCtx = context.applicationContext
        sequenceRunning.set(false) // Hủy chuỗi cũ nếu có
        worker.execute {
            if (!isConnected) {
                val (ok, msg) = connectBlocking(appCtx, null)
                if (!ok) {
                    mainHandler.post { onResult(false, msg) }
                    return@execute
                }
            }
            try {
                val out = outputStream ?: throw IllegalStateException("Chưa có luồng OutputStream")
                out.write(byteArrayOf(asciiByte.toByte()))
                out.flush()
                val msg = "Đã gửi lệnh '$actionLabel' (ASCII '$asciiByte' / '${asciiByte.toChar()}') tới $connectedName"
                lastStatusMessage = msg
                Log.i(TAG, msg)
                mainHandler.post { onResult(true, msg) }
            } catch (t: Throwable) {
                Log.w(TAG, "Write error, reconnecting: ${t.message}")
                disconnectBlocking()
                val (reOk, reMsg) = connectBlocking(appCtx, null)
                if (reOk) {
                    try {
                        outputStream?.write(byteArrayOf(asciiByte.toByte()))
                        outputStream?.flush()
                        val msg = "Đã kết nối lại và gửi '$actionLabel' tới $connectedName"
                        lastStatusMessage = msg
                        mainHandler.post { onResult(true, msg) }
                        return@execute
                    } catch (_: Throwable) {
                    }
                }
                val errMsg = "Lỗi gửi lệnh Bluetooth '$actionLabel': ${t.message ?: reMsg}"
                lastStatusMessage = errMsg
                mainHandler.post { onResult(false, errMsg) }
            }
        }
    }

    /**
     * Gửi một chuỗi liên hoàn các động tác (ví dụ: Bài biểu diễn Quyền thuật / Liên hoàn Vũ đạo).
     */
    fun sendActionSequence(
        context: Context,
        bytes: IntArray,
        delaysMs: LongArray,
        sequenceLabel: String,
        onResult: (Boolean, String) -> Unit
    ) {
        val appCtx = context.applicationContext
        sequenceRunning.set(false)
        worker.execute {
            if (!isConnected) {
                val (ok, msg) = connectBlocking(appCtx, null)
                if (!ok) {
                    mainHandler.post { onResult(false, msg) }
                    return@execute
                }
            }

            sequenceRunning.set(true)
            val startMsg = "Đang biểu diễn chuỗi '$sequenceLabel' (${bytes.size} động tác) qua $connectedName"
            lastStatusMessage = startMsg
            mainHandler.post { onResult(true, startMsg) }

            try {
                for (i in bytes.indices) {
                    if (!sequenceRunning.get()) break
                    val b = bytes[i]
                    val out = outputStream ?: break
                    out.write(byteArrayOf(b.toByte()))
                    out.flush()
                    Log.i(TAG, "Sequence [$sequenceLabel] step ${i + 1}/${bytes.size}: DEC $b ('${b.toChar()}')")
                    val waitMs = if (i < delaysMs.size) delaysMs[i] else 3500L
                    var slept = 0L
                    while (slept < waitMs && sequenceRunning.get()) {
                        Thread.sleep(100)
                        slept += 100
                    }
                }
            } catch (t: Throwable) {
                Log.w(TAG, "Sequence error: ${t.message}")
                disconnectBlocking()
            } finally {
                sequenceRunning.set(false)
            }
        }
    }
}
