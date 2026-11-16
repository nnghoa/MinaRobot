package com.mtc.mina_robot

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.BluetoothSocket
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import java.io.OutputStream
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

/**
 * Bộ điều khiển Robot hình người (BJROBOT SUPER-M V6.1 / MR-C3024FX) hỗ trợ kép:
 *  1. BLE 4.0/5.0 UART ([LE] HC-06, BT05, HM-10, DX-BT24, JDY-23, JDY-16, HC-08, HC-42, NUS...)
 *  2. Bluetooth Classic SPP 2.0 (HC-06 / HC-05 truyền thống RFCOMM UUID 00001101-...)
 *
 * Tự động phát hiện loại module ([LE] / Dual / Classic), dùng lại kết nối BLE sẵn có của hệ thống Android
 * nếu người dùng đã kết nối trong Cài đặt Bluetooth, hoặc tự quét BLE + mở kênh UART truyền 1 byte ASCII
 * (DEC 40..111) xuống chân ERX 9600 bps trên mạch SUPER-M V6.1.
 */
@SuppressLint("MissingPermission")
@Suppress("DEPRECATION")
object RobonovaBluetoothController {
    private const val TAG = "RobonovaBT"
    private const val PREFS_NAME = "mina_robonova_bt"
    private const val KEY_LAST_ADDR = "last_bt_address"
    private const val KEY_LAST_NAME = "last_bt_name"
    private const val KEY_BLE_TX_UUID = "preferred_ble_tx_uuid"

    private val SPP_UUID: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
    private val CCCD_UUID: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")

    // Thứ tự ưu tiên các Characteristic TX phổ biến trên module BLE UART (HM-10, BT05, DX-BT24, JDY, NUS, ISSC)
    private val PREFERRED_BLE_TX_CHAR_UUIDS: List<String> = listOf(
        "0000ffe1-0000-1000-8000-00805f9b34fb",
        "0000ffe2-0000-1000-8000-00805f9b34fb",
        "0000ffe9-0000-1000-8000-00805f9b34fb",
        "0000ffe3-0000-1000-8000-00805f9b34fb",
        "0000fff2-0000-1000-8000-00805f9b34fb",
        "0000fff1-0000-1000-8000-00805f9b34fb",
        "0000fff6-0000-1000-8000-00805f9b34fb",
        "6e400002-b5a3-f393-e0a9-e50e24dcca9e",
        "49535343-8841-43f4-a8d4-ecbe34729bb3",
        "49535343-1e4d-4bd9-ba61-23c647249616",
    )

    private val SYSTEM_GATT_SERVICES: Set<String> = setOf(
        "00001800-0000-1000-8000-00805f9b34fb",
        "00001801-0000-1000-8000-00805f9b34fb",
        "0000180a-0000-1000-8000-00805f9b34fb",
    )

    private val worker = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    // --- Kênh Classic RFCOMM ---
    @Volatile
    private var socket: BluetoothSocket? = null

    @Volatile
    private var outputStream: OutputStream? = null

    // --- Kênh BLE GATT ---
    @Volatile
    private var bluetoothGatt: BluetoothGatt? = null

    @Volatile
    private var bleTxCharacteristic: BluetoothGattCharacteristic? = null

    private val bleConnected = AtomicBoolean(false)

    @Volatile
    private var activeWriteLatch: CountDownLatch? = null

    private val lastWriteStatus = AtomicInteger(BluetoothGatt.GATT_SUCCESS)

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
    private val cachedDeviceObjects = ConcurrentHashMap<String, BluetoothDevice>()
    private val sequenceRunning = AtomicBoolean(false)

    val isConnected: Boolean
        get() = try {
            val rfcommOk = socket?.isConnected == true && outputStream != null
            val bleOk = bleConnected.get() && bluetoothGatt != null && bleTxCharacteristic != null
            rfcommOk || bleOk
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

            // 1. Các thiết bị BLE đang kết nối ở tầng hệ thống Android (Cài đặt Bluetooth)
            val btMgr = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
            val sysGattConnected = try {
                btMgr?.getConnectedDevices(BluetoothProfile.GATT) ?: emptyList()
            } catch (_: Throwable) {
                emptyList()
            }
            for (dev in sysGattConnected) {
                val addr = dev.address ?: continue
                val name = dev.name ?: discoveredDevices[addr] ?: "BLE-$addr"
                cachedDeviceObjects[addr] = dev
                if (seen.add(addr)) {
                    result.add(
                        mapOf(
                            "name" to name,
                            "address" to addr,
                            "paired" to true,
                            "connected" to (isConnected && addr.equals(connectedAddress, ignoreCase = true)),
                        )
                    )
                }
            }

            // 2. Các thiết bị đã ghép đôi (Bonded)
            val bonded = adapter.bondedDevices ?: emptySet()
            val sortedBonded = bonded.sortedByDescending { dev ->
                scoreDeviceName(dev.name ?: "")
            }
            for (dev in sortedBonded) {
                val addr = dev.address ?: continue
                val name = dev.name ?: discoveredDevices[addr] ?: "Thiết bị BT"
                cachedDeviceObjects[addr] = dev
                if (seen.add(addr)) {
                    result.add(
                        mapOf(
                            "name" to name,
                            "address" to addr,
                            "paired" to true,
                            "connected" to (isConnected && addr.equals(connectedAddress, ignoreCase = true)),
                        )
                    )
                }
            }
        } catch (t: Throwable) {
            Log.w(TAG, "getKnownDevices error: ${t.message}")
        }

        // 3. Các thiết bị vừa quét thấy (BLE + Classic)
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
            u.contains("HC-05") || u.contains("HC05") || u.contains("HC-08") || u.contains("HC-42") -> 95
            u.contains("ROBONOVA") || u.contains("BJROBOT") || u.contains("SUPER-M") || u.contains("ROBOT") -> 92
            u.contains("BT05") || u.contains("BT04") || u.contains("BT24") || u.contains("HM-10") || u.contains("HMSOFT") -> 88
            u.contains("JDY") || u.contains("DX-BT") || u.contains("SPP") || u.contains("BLE") -> 82
            else -> 10
        }
    }

    fun scanDevices(context: Context, durationMs: Long = 4000L, onDone: (Map<String, Any>) -> Unit) {
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
                    val dev = intent.getParcelableExtra<BluetoothDevice>(BluetoothDevice.EXTRA_DEVICE) ?: return
                    val addr = dev.address ?: return
                    val name = dev.name ?: discoveredDevices[addr] ?: "BT-$addr"
                    discoveredDevices[addr] = name
                    cachedDeviceObjects[addr] = dev
                    Log.i(TAG, "Discovered Classic/Dual BT: $name ($addr, type=${dev.type})")
                }
            }
        }

        val leScanner = try {
            adapter.bluetoothLeScanner
        } catch (_: Throwable) {
            null
        }

        val leCallback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult?) {
                val dev = result?.device ?: return
                val addr = dev.address ?: return
                val name = dev.name ?: result.scanRecord?.deviceName ?: discoveredDevices[addr] ?: "BLE-$addr"
                discoveredDevices[addr] = name
                cachedDeviceObjects[addr] = dev
                Log.i(TAG, "Discovered BLE device: $name ($addr, rssi=${result.rssi})")
            }
        }

        try {
            appCtx.registerReceiver(receiver, IntentFilter(BluetoothDevice.ACTION_FOUND))
            if (adapter.isDiscovering) adapter.cancelDiscovery()
            adapter.startDiscovery()
        } catch (t: Throwable) {
            Log.w(TAG, "startDiscovery error: ${t.message}")
        }

        try {
            val settings = ScanSettings.Builder()
                .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
                .build()
            leScanner?.startScan(null, settings, leCallback)
        } catch (t: Throwable) {
            Log.w(TAG, "BLE startScan error: ${t.message}")
        }

        lastStatusMessage = "Đang quét Bluetooth (BLE + Classic)..."

        mainHandler.postDelayed({
            try {
                leScanner?.stopScan(leCallback)
            } catch (_: Throwable) {
            }
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

    @Synchronized
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
        val btMgr = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        val sysGattDevs = try {
            btMgr?.getConnectedDevices(BluetoothProfile.GATT) ?: emptyList()
        } catch (_: Throwable) {
            emptyList()
        }
        for (d in sysGattDevs) {
            d.address?.let { cachedDeviceObjects[it] = d }
        }

        val bonded = try {
            adapter.bondedDevices?.toList() ?: emptyList()
        } catch (_: Throwable) {
            emptyList()
        }
        for (d in bonded) {
            d.address?.let { cachedDeviceObjects[it] = d }
        }

        var address = targetAddress?.trim() ?: ""
        if (address.isEmpty()) {
            val sysPreferred = sysGattDevs.maxByOrNull { scoreDeviceName(it.name ?: "") }
            val bondedPreferred = bonded.maxByOrNull { scoreDeviceName(it.name ?: "") }
            val savedAddr = prefs.getString(KEY_LAST_ADDR, "") ?: ""

            address = when {
                sysPreferred != null && scoreDeviceName(sysPreferred.name ?: "") >= 80 -> sysPreferred.address
                bondedPreferred != null && scoreDeviceName(bondedPreferred.name ?: "") >= 80 -> bondedPreferred.address
                savedAddr.isNotEmpty() -> savedAddr
                sysPreferred != null -> sysPreferred.address
                bondedPreferred != null -> bondedPreferred.address
                discoveredDevices.isNotEmpty() -> {
                    discoveredDevices.entries.maxByOrNull { scoreDeviceName(it.value) }?.key ?: ""
                }
                else -> ""
            }
        }

        // Nếu vẫn chưa có địa chỉ, quét nhanh BLE 2.5s để tìm module HC-06 BLE xung quanh
        if (address.isEmpty()) {
            val scanned = quickScanForBleTarget(adapter, null, 2500L)
            if (scanned != null) {
                address = scanned.address
                cachedDeviceObjects[address] = scanned
            }
        }

        if (address.isEmpty()) {
            lastStatusMessage = "Chưa tìm thấy HC-06. Hãy bật nguồn robot và bấm Quét."
            return Pair(false, lastStatusMessage)
        }

        if (isConnected && address.equals(connectedAddress, ignoreCase = true)) {
            lastStatusMessage = "Đã kết nối sẵn với $connectedName ($connectedAddress)"
            return Pair(true, lastStatusMessage)
        }

        disconnectBlocking()

        val device = try {
            cachedDeviceObjects[address] ?: adapter.getRemoteDevice(address)
        } catch (t: Throwable) {
            lastStatusMessage = "Địa chỉ Bluetooth không hợp lệ: $address"
            return Pair(false, lastStatusMessage)
        }

        val devName = try {
            device.name ?: discoveredDevices[address] ?: prefs.getString(KEY_LAST_NAME, null) ?: "HC-06"
        } catch (_: Throwable) {
            "HC-06"
        }

        val devType = try {
            device.type
        } catch (_: Throwable) {
            BluetoothDevice.DEVICE_TYPE_UNKNOWN
        }
        Log.i(TAG, "Connecting to $devName ($address), deviceType=$devType (1=Classic, 2=LE, 3=Dual)")

        // 1. Nếu thiết bị là BLE ([LE] HC-06, deviceType == 2) -> Kết nối thẳng qua BLE GATT!
        if (devType == BluetoothDevice.DEVICE_TYPE_LE) {
            val (bleOk, bleMsg) = connectBleWithRetry(context, adapter, device, devName)
            if (bleOk) {
                saveLastDevice(prefs, connectedAddress, connectedName)
                return Pair(true, bleMsg)
            }
            return Pair(false, bleMsg)
        }

        // 2. Nếu là Dual-Mode hoặc Classic/Unknown -> Thử Classic SPP trước, nếu lỗi tự động chuyển sang BLE GATT!
        val (sppOk, sppErr) = tryConnectClassicSpp(device, devName)
        if (sppOk) {
            saveLastDevice(prefs, connectedAddress, connectedName)
            return Pair(true, lastStatusMessage)
        }

        Log.i(TAG, "Classic SPP failed ($sppErr), falling back to BLE GATT for $devName ($address)...")
        val (bleOk, bleMsg) = connectBleWithRetry(context, adapter, device, devName)
        if (bleOk) {
            saveLastDevice(prefs, connectedAddress, connectedName)
            return Pair(true, bleMsg)
        }

        lastStatusMessage = "Không kết nối được $devName ($address): $bleMsg"
        Log.w(TAG, lastStatusMessage)
        return Pair(false, lastStatusMessage)
    }

    private fun saveLastDevice(prefs: android.content.SharedPreferences, addr: String, name: String) {
        prefs.edit()
            .putString(KEY_LAST_ADDR, addr)
            .putString(KEY_LAST_NAME, name)
            .apply()
    }

    private fun tryConnectClassicSpp(device: BluetoothDevice, devName: String): Pair<Boolean, String> {
        val address = device.address ?: ""
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
                lastStatusMessage = "Đã kết nối SPP với $devName ($address)"
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
        return Pair(false, lastErr)
    }

    private fun connectBleWithRetry(
        context: Context,
        adapter: BluetoothAdapter,
        initialDevice: BluetoothDevice,
        devName: String
    ): Pair<Boolean, String> {
        // Lần 1: Kết nối GATT trực tiếp (dùng lại liên kết BLE đang mở trong Cài đặt Android nếu có)
        val (ok1, err1) = attemptBleGattOnce(context, initialDevice, devName, 6000L)
        if (ok1) return Pair(true, err1)

        Log.w(TAG, "BLE GATT attempt #1 failed ($err1), scanning BLE to refresh RPA/cache...")
        Thread.sleep(250)

        // Lần 2: Quét BLE nhanh để làm mới địa chỉ Random/RPA trong Bluedroid rồi kết nối lại
        val freshDev = quickScanForBleTarget(adapter, initialDevice.address, 3000L) ?: initialDevice
        val freshName = try {
            freshDev.name ?: devName
        } catch (_: Throwable) {
            devName
        }
        val (ok2, err2) = attemptBleGattOnce(context, freshDev, freshName, 7500L)
        if (ok2) return Pair(true, err2)

        lastStatusMessage = "Không mở được kênh BLE $freshName: $err2"
        Log.w(TAG, lastStatusMessage)
        return Pair(false, lastStatusMessage)
    }

    private fun quickScanForBleTarget(
        adapter: BluetoothAdapter,
        targetAddress: String?,
        timeoutMs: Long
    ): BluetoothDevice? {
        val scanner = try {
            adapter.bluetoothLeScanner
        } catch (_: Throwable) {
            null
        } ?: return null

        val latch = CountDownLatch(1)
        var found: BluetoothDevice? = null

        val cb = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult?) {
                val dev = result?.device ?: return
                val addr = dev.address ?: return
                val name = dev.name ?: result.scanRecord?.deviceName ?: ""
                if (name.isNotEmpty()) discoveredDevices[addr] = name
                cachedDeviceObjects[addr] = dev

                val matchAddr = !targetAddress.isNullOrEmpty() && addr.equals(targetAddress, ignoreCase = true)
                val matchName = scoreDeviceName(name) >= 85
                if (matchAddr || matchName) {
                    found = dev
                    latch.countDown()
                }
            }
        }

        try {
            val settings = ScanSettings.Builder()
                .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
                .build()
            scanner.startScan(null, settings, cb)
            latch.await(timeoutMs, TimeUnit.MILLISECONDS)
        } catch (t: Throwable) {
            Log.w(TAG, "quickScanForBleTarget error: ${t.message}")
        } finally {
            try {
                scanner.stopScan(cb)
            } catch (_: Throwable) {
            }
        }
        return found
    }

    private fun attemptBleGattOnce(
        context: Context,
        device: BluetoothDevice,
        devName: String,
        timeoutMs: Long
    ): Pair<Boolean, String> {
        val readyLatch = CountDownLatch(1)
        var failReason = "Hết thời gian chờ phản hồi BLE"
        var chosenTx: BluetoothGattCharacteristic? = null
        var chosenNotify: BluetoothGattCharacteristic? = null
        var localGatt: BluetoothGatt? = null

        val callback = object : BluetoothGattCallback() {
            override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
                Log.i(TAG, "BLE onConnectionStateChange: status=$status newState=$newState addr=${gatt.device?.address}")
                if (newState == BluetoothProfile.STATE_CONNECTED && status == BluetoothGatt.GATT_SUCCESS) {
                    bleConnected.set(true)
                    mainHandler.postDelayed({
                        try {
                            gatt.discoverServices()
                        } catch (t: Throwable) {
                            failReason = "Lỗi discoverServices: ${t.message}"
                            readyLatch.countDown()
                        }
                    }, 120)
                } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                    val wasCurrent = (gatt == bluetoothGatt)
                    if (wasCurrent) {
                        bleConnected.set(false)
                        bleTxCharacteristic = null
                        try {
                            gatt.close()
                        } catch (_: Throwable) {
                        }
                        bluetoothGatt = null
                    }
                    if (readyLatch.count > 0) {
                        failReason = "Ngắt kết nối BLE (status=$status)"
                        readyLatch.countDown()
                    }
                    activeWriteLatch?.countDown()
                }
            }

            override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
                Log.i(TAG, "BLE onServicesDiscovered: status=$status services=${gatt.services.size}")
                if (status != BluetoothGatt.GATT_SUCCESS) {
                    failReason = "discoverServices thất bại (status=$status)"
                    readyLatch.countDown()
                    return
                }

                val writableCandidates = mutableListOf<BluetoothGattCharacteristic>()
                for (svc in gatt.services) {
                    val svcUuid = svc.uuid.toString().lowercase()
                    Log.i(TAG, "  GATT Service: $svcUuid")
                    for (chr in svc.characteristics) {
                        val chrUuid = chr.uuid.toString().lowercase()
                        val props = chr.properties
                        Log.i(TAG, "    Characteristic: $chrUuid props=0x${props.toString(16)}")
                        if (svcUuid in SYSTEM_GATT_SERVICES) continue

                        val canWrite = (props and (
                            BluetoothGattCharacteristic.PROPERTY_WRITE or
                                BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE
                            )) != 0
                        val canNotify = (props and (
                            BluetoothGattCharacteristic.PROPERTY_NOTIFY or
                                BluetoothGattCharacteristic.PROPERTY_INDICATE
                            )) != 0

                        if (canWrite) writableCandidates.add(chr)
                        if (canNotify && chosenNotify == null) chosenNotify = chr
                    }
                }

                // Ưu tiên override UUID nếu có lưu trong prefs, sau đó theo bảng chuẩn UART, cuối cùng là kênh ghi đầu tiên
                val customTxUuid = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                    .getString(KEY_BLE_TX_UUID, null)?.trim()?.lowercase()
                if (!customTxUuid.isNullOrEmpty()) {
                    chosenTx = writableCandidates.firstOrNull {
                        it.uuid.toString().lowercase().contains(customTxUuid)
                    }
                }
                if (chosenTx == null) {
                    for (prefUuid in PREFERRED_BLE_TX_CHAR_UUIDS) {
                        val hit = writableCandidates.firstOrNull { it.uuid.toString().equals(prefUuid, ignoreCase = true) }
                        if (hit != null) {
                            chosenTx = hit
                            break
                        }
                    }
                }
                if (chosenTx == null && writableCandidates.isNotEmpty()) {
                    chosenTx = writableCandidates.first()
                }

                if (chosenTx == null) {
                    failReason = "Không tìm thấy kênh ghi UART trên module BLE"
                    readyLatch.countDown()
                    return
                }

                Log.i(TAG, "Selected BLE UART TX characteristic: ${chosenTx?.uuid} (props=0x${chosenTx?.properties?.toString(16)})")

                // Bật thông báo RX (nếu có) để module BLE UART kích hoạt cầu nối trong suốt
                chosenNotify?.let { nChr ->
                    try {
                        gatt.setCharacteristicNotification(nChr, true)
                        val cccd = nChr.getDescriptor(CCCD_UUID)
                        if (cccd != null) {
                            cccd.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                            gatt.writeDescriptor(cccd)
                        }
                    } catch (_: Throwable) {
                    }
                }

                readyLatch.countDown()
            }

            override fun onCharacteristicWrite(
                gatt: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic,
                status: Int
            ) {
                lastWriteStatus.set(status)
                activeWriteLatch?.countDown()
            }
        }

        val startLatch = CountDownLatch(1)
        mainHandler.post {
            try {
                localGatt = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    device.connectGatt(context, false, callback, BluetoothDevice.TRANSPORT_LE)
                } else {
                    device.connectGatt(context, false, callback)
                }
            } catch (t: Throwable) {
                failReason = t.message ?: t.javaClass.simpleName
            } finally {
                startLatch.countDown()
            }
        }
        startLatch.await(1500, TimeUnit.MILLISECONDS)

        val gatt = localGatt ?: return Pair(false, failReason)
        val finished = readyLatch.await(timeoutMs, TimeUnit.MILLISECONDS)

        if (finished && bleConnected.get() && chosenTx != null) {
            // Chờ ngắn nếu vừa gửi writeDescriptor CCCD
            if (chosenNotify != null) {
                Thread.sleep(150)
            }
            bluetoothGatt = gatt
            bleTxCharacteristic = chosenTx
            connectedAddress = device.address ?: ""
            connectedName = devName
            lastStatusMessage = "Đã kết nối BLE với $devName ($connectedAddress)"
            Log.i(TAG, "$lastStatusMessage [TX=${chosenTx?.uuid}]")
            return Pair(true, lastStatusMessage)
        }

        bleConnected.set(false)
        try {
            gatt.disconnect()
        } catch (_: Throwable) {
        }
        try {
            gatt.close()
        } catch (_: Throwable) {
        }
        return Pair(false, failReason)
    }

    @Synchronized
    private fun transmitSingleByte(byteVal: Byte): Boolean {
        // 1. Ưu tiên gửi qua BLE GATT nếu đang kết nối BLE
        val gatt = bluetoothGatt
        val txChar = bleTxCharacteristic
        if (bleConnected.get() && gatt != null && txChar != null) {
            val props = txChar.properties
            val preferNoResp = (props and BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE) != 0
            val primaryWriteType = if (preferNoResp) {
                BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
            } else {
                BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
            }

            if (writeBleCharacteristicOnce(gatt, txChar, byteVal, primaryWriteType)) {
                return true
            }
            // Dự phòng đổi kiểu ghi nếu module yêu cầu ngược lại
            val altType = if (preferNoResp) {
                BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
            } else {
                BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
            }
            return writeBleCharacteristicOnce(gatt, txChar, byteVal, altType)
        }

        // 2. Gửi qua Classic RFCOMM OutputStream
        val out = outputStream ?: return false
        out.write(byteArrayOf(byteVal))
        out.flush()
        return true
    }

    private fun writeBleCharacteristicOnce(
        gatt: BluetoothGatt,
        txChar: BluetoothGattCharacteristic,
        byteVal: Byte,
        writeType: Int
    ): Boolean {
        val latch = CountDownLatch(1)
        activeWriteLatch = latch
        lastWriteStatus.set(-1)

        var initiated = false
        val postLatch = CountDownLatch(1)
        mainHandler.post {
            try {
                txChar.writeType = writeType
                txChar.value = byteArrayOf(byteVal)
                initiated = gatt.writeCharacteristic(txChar)
            } catch (t: Throwable) {
                Log.w(TAG, "writeCharacteristic exception: ${t.message}")
                initiated = false
            } finally {
                postLatch.countDown()
            }
        }
        postLatch.await(800, TimeUnit.MILLISECONDS)
        if (!initiated) {
            activeWriteLatch = null
            return false
        }

        val completed = latch.await(1000, TimeUnit.MILLISECONDS)
        activeWriteLatch = null
        return completed && lastWriteStatus.get() == BluetoothGatt.GATT_SUCCESS
    }

    fun disconnect() {
        worker.execute {
            disconnectBlocking()
        }
    }

    @Synchronized
    private fun disconnectBlocking() {
        sequenceRunning.set(false)
        bleConnected.set(false)
        bleTxCharacteristic = null
        try {
            bluetoothGatt?.disconnect()
        } catch (_: Throwable) {
        }
        try {
            bluetoothGatt?.close()
        } catch (_: Throwable) {
        }
        bluetoothGatt = null

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
     * Gửi 1 byte lệnh ASCII (DEC 40..111) tới mạch SUPER-M V6.1 qua BLE UART hoặc Classic SPP.
     * Nếu chưa kết nối thì tự động tìm và kết nối tới HC-06 đã lưu / ghép đôi.
     */
    fun sendActionByte(
        context: Context,
        asciiByte: Int,
        actionLabel: String,
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
            try {
                if (transmitSingleByte(asciiByte.toByte())) {
                    val msg = "Đã gửi '$actionLabel' (DEC $asciiByte / '${asciiByte.toChar()}') tới $connectedName"
                    lastStatusMessage = msg
                    Log.i(TAG, msg)
                    mainHandler.post { onResult(true, msg) }
                    return@execute
                }
                throw IllegalStateException("Ghi dữ liệu Bluetooth thất bại")
            } catch (t: Throwable) {
                Log.w(TAG, "Write error, reconnecting: ${t.message}")
                disconnectBlocking()
                val (reOk, reMsg) = connectBlocking(appCtx, null)
                if (reOk && transmitSingleByte(asciiByte.toByte())) {
                    val msg = "Đã kết nối lại và gửi '$actionLabel' tới $connectedName"
                    lastStatusMessage = msg
                    mainHandler.post { onResult(true, msg) }
                    return@execute
                }
                val errMsg = "Lỗi gửi lệnh '$actionLabel': ${t.message ?: reMsg}"
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
                    if (!transmitSingleByte(b.toByte())) {
                        throw IllegalStateException("Mất kết nối giữa chuỗi động tác")
                    }
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
