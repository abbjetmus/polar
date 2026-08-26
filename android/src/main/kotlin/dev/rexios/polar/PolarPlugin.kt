package dev.rexios.polar

import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.lifecycle.Lifecycle.Event
import androidx.lifecycle.LifecycleEventObserver
import com.google.gson.ExclusionStrategy
import com.google.gson.FieldAttributes
import com.google.gson.GsonBuilder
import com.google.gson.JsonDeserializationContext
import com.google.gson.JsonDeserializer
import com.google.gson.JsonElement
import com.google.gson.JsonPrimitive
import com.google.gson.JsonSerializationContext
import com.google.gson.JsonSerializer
import com.polar.androidcommunications.api.ble.model.DisInfo
import com.polar.androidcommunications.api.ble.model.gatt.client.ChargeState
import com.polar.androidcommunications.api.ble.model.gatt.client.PowerSourcesState
import com.polar.androidcommunications.api.ble.exceptions.BleDisconnected
import com.polar.sdk.api.PolarBleApi
import com.polar.sdk.api.PolarBleApi.PolarBleSdkFeature
import com.polar.sdk.api.PolarBleApi.PolarDeviceDataType
import com.polar.sdk.api.PolarBleApiCallbackProvider
import com.polar.sdk.api.PolarBleApiDefaultImpl
import com.polar.sdk.api.PolarH10OfflineExerciseApi.RecordingInterval
import com.polar.sdk.api.PolarH10OfflineExerciseApi.SampleType
import com.polar.sdk.api.model.CheckFirmwareUpdateStatus
import com.polar.sdk.api.model.FirmwareUpdateStatus
import com.polar.sdk.api.model.LedConfig
import com.polar.sdk.api.model.PolarDeviceInfo
import com.polar.sdk.api.model.PolarExerciseEntry
import com.polar.sdk.api.model.PolarFirstTimeUseConfig
import com.polar.sdk.api.model.PolarHealthThermometerData
import com.polar.sdk.api.model.PolarHrData
import com.polar.sdk.api.model.PolarOfflineRecordingEntry
import com.polar.sdk.api.model.PolarOfflineRecordingTrigger
import com.polar.sdk.api.model.PolarOfflineRecordingTriggerMode
import com.polar.sdk.api.model.PolarSensorSetting
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.embedding.engine.plugins.lifecycle.FlutterLifecycleAdapter
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.EventChannel.EventSink
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.lang.reflect.Type
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Date
import java.util.UUID

object DateSerializer : JsonDeserializer<Date>, JsonSerializer<Date> {
    override fun deserialize(
        json: JsonElement?,
        typeOfT: Type?,
        context: JsonDeserializationContext?,
    ): Date = Date(json?.asJsonPrimitive?.asLong ?: 0)

    override fun serialize(
        src: Date?,
        typeOfSrc: Type?,
        context: JsonSerializationContext?,
    ): JsonElement = JsonPrimitive(src?.time)
}

private fun runOnUiThread(runnable: () -> Unit) {
    Handler(Looper.getMainLooper()).post { runnable() }
}

private val gson = GsonBuilder()
    .registerTypeAdapter(Date::class.java, DateSerializer)
    // polar-ble-sdk 8.x added a raw `rrs` field (1/1024s units) to PolarHrSample.
    // Exclude it from serialization so the JSON sent to Dart keeps the exact
    // same shape as with SDK 6.16.1.
    .addSerializationExclusionStrategy(object : ExclusionStrategy {
        override fun shouldSkipField(f: FieldAttributes): Boolean =
            f.declaringClass == PolarHrData.PolarHrSample::class.java && f.name == "rrs"

        override fun shouldSkipClass(clazz: Class<*>): Boolean = false
    })
    .create()

private fun PolarOfflineRecordingEntry.toJsonString(): String {
    val millis = date.atZone(ZoneId.systemDefault()).toInstant().toEpochMilli()
    return """{"path":"$path","size":$size,"date":$millis,"type":"${type.name}"}"""
}

private fun offlineEntryFromJson(json: String): PolarOfflineRecordingEntry {
    val map = gson.fromJson(json, Map::class.java)
    val dateValue = map["date"]
    val dateTime = when (dateValue) {
        is Number -> java.time.LocalDateTime.ofInstant(Instant.ofEpochMilli(dateValue.toLong()), ZoneId.systemDefault())
        is String -> java.time.LocalDateTime.parse(dateValue, java.time.format.DateTimeFormatter.ISO_DATE_TIME)
        else -> throw IllegalArgumentException("Unexpected date format: $dateValue")
    }
    return PolarOfflineRecordingEntry(
        path = map["path"] as String,
        size = (map["size"] as Number).toLong(),
        date = dateTime,
        type = PolarDeviceDataType.valueOf(map["type"] as String),
    )
}

private var wrapperInternal: PolarWrapper? = null
private val wrapper: PolarWrapper
    get() = wrapperInternal!!

/** PolarPlugin */
class PolarPlugin :
    FlutterPlugin,
    MethodCallHandler,
    EventChannel.StreamHandler,
    ActivityAware {
    // Binary messenger for dynamic EventChannel registration
    private lateinit var messenger: BinaryMessenger

    // Method channel
    private lateinit var methodChannel: MethodChannel

    // Event channel
    private lateinit var eventChannel: EventChannel

    // Search channel
    private lateinit var searchChannel: EventChannel

    // Context
    private lateinit var context: Context

    // Plugin coroutine scope. Main.immediate guarantees that MethodChannel /
    // EventChannel callbacks are always invoked on the main thread.
    private lateinit var scope: CoroutineScope

    // Streaming channels
    private val streamingChannels = mutableMapOf<String, StreamingChannel>()

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

        messenger = flutterPluginBinding.binaryMessenger

        methodChannel = MethodChannel(flutterPluginBinding.binaryMessenger, "polar/methods")
        methodChannel.setMethodCallHandler(this)

        eventChannel = EventChannel(flutterPluginBinding.binaryMessenger, "polar/events")
        eventChannel.setStreamHandler(this)

        searchChannel = EventChannel(flutterPluginBinding.binaryMessenger, "polar/search")
        searchChannel.setStreamHandler(searchHandler)

        context = flutterPluginBinding.applicationContext
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        searchChannel.setStreamHandler(null)
        streamingChannels.values.forEach { it.dispose() }
        shutDown()
        scope.cancel()
    }

    private fun initApi() {
        if (wrapperInternal == null) {
            wrapperInternal = PolarWrapper(context)
        }
    }

    override fun onMethodCall(
        call: MethodCall,
        result: Result,
    ) {
        initApi()

        when (call.method) {
            "connectToDevice" -> {
                try {
                    val identifier = call.arguments as String
                    android.util.Log.d("PolarPlugin", "connectToDevice: identifier=$identifier")
                    wrapper.api.connectToDevice(identifier)
                    result.success(null)
                } catch (e: Exception) {
                    android.util.Log.e("PolarPlugin", "connectToDevice error: ${e.message}", e)
                    runOnUiThread {
                        result.error("CONNECT_ERROR", e.message ?: "Unknown error", null)
                    }
                }
            }

            "disconnectFromDevice" -> {
                try {
                    val identifier = call.arguments as String
                    android.util.Log.d("PolarPlugin", "disconnectFromDevice: identifier=$identifier")
                    wrapper.api.disconnectFromDevice(identifier)
                    result.success(null)
                } catch (e: Exception) {
                    android.util.Log.e("PolarPlugin", "disconnectFromDevice error: ${e.message}", e)
                    runOnUiThread {
                        result.error("DISCONNECT_ERROR", e.message ?: "Unknown error", null)
                    }
                }
            }

            "getAvailableOnlineStreamDataTypes" -> getAvailableOnlineStreamDataTypes(call, result)
            "requestStreamSettings" -> requestStreamSettings(call, result)
            "createStreamingChannel" -> createStreamingChannel(call, result)
            "startRecording" -> startRecording(call, result)
            "stopRecording" -> stopRecording(call, result)
            "requestRecordingStatus" -> requestRecordingStatus(call, result)
            "listExercises" -> listExercises(call, result)
            "fetchExercise" -> fetchExercise(call, result)
            "removeExercise" -> removeExercise(call, result)
            "setLedConfig" -> setLedConfig(call, result)
            "doFactoryReset" -> doFactoryReset(call, result)
            "doRestart" -> doRestart(call, result)
            "enableSdkMode" -> enableSdkMode(call, result)
            "disableSdkMode" -> disableSdkMode(call, result)
            "setAutomaticOHRMeasurementEnabled" -> setAutomaticOHRMeasurementEnabled(call, result)
            "isSdkModeEnabled" -> isSdkModeEnabled(call, result)
            "getAvailableOfflineRecordingDataTypes" -> getAvailableOfflineRecordingDataTypes(
                call,
                result
            )
            "requestOfflineRecordingSettings" -> requestOfflineRecordingSettings(call, result)
            "startOfflineRecording" -> startOfflineRecording(call, result)
            "stopOfflineRecording" -> stopOfflineRecording(call, result)
            "getOfflineRecordingStatus" -> getOfflineRecordingStatus(call, result)
            "setOfflineRecordingTrigger" -> setOfflineRecordingTrigger(call, result)
            "listOfflineRecordings" -> listOfflineRecordings(call, result)
            "getOfflineRecord" -> getOfflineRecord(call, result)
            "removeOfflineRecord" -> removeOfflineRecord(call, result)
            "getChargerState" -> getChargerState(call, result)
            "getDiskSpace" -> getDiskSpace(call, result)
            "getLocalTime" -> getLocalTime(call, result)
            "foregroundEntered" -> {
                // Restarts BLE scan after screen-off power save so the SDK's
                // automatic reconnection can proceed (see PolarBleApi docs).
                wrapper.api.foregroundEntered()
                result.success(null)
            }
            "setLocalTime" -> setLocalTime(call, result)
            "doFirstTimeUse" -> doFirstTimeUse(call, result)
            "isFtuDone" -> isFtuDone(call, result)
            "deleteStoredDeviceData" -> deleteStoredDeviceData(call, result)
            "deleteDeviceDateFolders" -> deleteDeviceDateFolders(call, result)
            "getSteps" -> getSteps(call, result)
            "getSleep" -> getSleep(call, result)
            "getSleepRecordingState" -> getSleepRecordingState(call, result)
            "stopSleepRecording" -> stopSleepRecording(call, result)
            "getDistance" -> getDistance(call, result)
            "getActiveTime" -> getActiveTime(call, result)
            "getActivitySampleData" -> getActivitySampleData(call, result)
            "sendInitializationAndStartSyncNotifications" -> sendInitializationAndStartSyncNotifications(call, result)
            "sendTerminateAndStopSyncNotifications" -> sendTerminateAndStopSyncNotifications(call, result)
            "checkFirmwareUpdate" -> checkFirmwareUpdate(call, result)
            "updateFirmware" -> updateFirmware(call, result)
            else -> result.notImplemented()
        }
    }

    override fun onListen(
        arguments: Any?,
        events: EventSink,
    ) {
        initApi()
        val id = arguments as Int
        android.util.Log.d("PolarPlugin", "onListen: id=$id, registering event sink")
        wrapper.addSink(id, events)
    }

    override fun onCancel(arguments: Any?) {
        val id = arguments as Int
        android.util.Log.d("PolarPlugin", "onCancel: id=$id, canceling event sink")
        wrapper.removeSink(id)
    }

    private val searchHandler =
        object : EventChannel.StreamHandler {
            private var searchJob: Job? = null

            override fun onListen(
                arguments: Any?,
                events: EventSink,
            ) {
                initApi()

                searchJob =
                    scope.launch {
                        var errored = false
                        wrapper.api
                            .searchForDevice()
                            .catch {
                                errored = true
                                events.error(it.toString(), it.message, null)
                            }
                            .collect { events.success(gson.toJson(it)) }
                        if (!errored) events.endOfStream()
                    }
            }

            override fun onCancel(arguments: Any?) {
                searchJob?.cancel()
                searchJob = null
            }
        }

    private fun createStreamingChannel(
        call: MethodCall,
        result: Result,
    ) {
        val arguments = call.arguments as List<*>
        val name = arguments[0] as String
        val identifier = arguments[1] as String
        val feature = gson.fromJson(arguments[2] as String, PolarDeviceDataType::class.java)

        if (streamingChannels[name] == null) {
            streamingChannels[name] =
                StreamingChannel(messenger, name, wrapper.api, identifier, feature, scope)
        }

        result.success(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        val lifecycle = FlutterLifecycleAdapter.getActivityLifecycle(binding)
        lifecycle.addObserver(
            LifecycleEventObserver { _, event ->
                when (event) {
                    Event.ON_RESUME -> wrapperInternal?.api?.foregroundEntered()
                    Event.ON_DESTROY -> shutDown()
                    else -> {}
                }
            },
        )
    }

    override fun onDetachedFromActivityForConfigChanges() {}

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {}

    override fun onDetachedFromActivity() {}

    private fun shutDown() {
        if (wrapperInternal == null) return
        wrapper.shutDown()
    }

    private fun getAvailableOnlineStreamDataTypes(
        call: MethodCall,
        result: Result,
    ) {
        val identifier = call.arguments as String

        scope.launch {
            try {
                val dataTypes = wrapper.api.getAvailableOnlineStreamDataTypes(identifier)
                result.success(gson.toJson(dataTypes))
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                result.error(e.toString(), e.message, null)
            }
        }
    }

    private fun requestStreamSettings(
        call: MethodCall,
        result: Result,
    ) {
        val arguments = call.arguments as List<*>
        val identifier = arguments[0] as String
        val feature = gson.fromJson(arguments[1] as String, PolarDeviceDataType::class.java)

        scope.launch {
            try {
                val settings = wrapper.api.requestStreamSettings(identifier, feature)
                result.success(gson.toJson(settings))
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                result.error(e.toString(), e.message, null)
            }
        }
    }

    private fun startRecording(
        call: MethodCall,
        result: Result,
    ) {
        val arguments = call.arguments as List<*>
        val identifier = arguments[0] as String
        val exerciseId = arguments[1] as String
        val interval = gson.fromJson(arguments[2] as String, RecordingInterval::class.java)
        val sampleType = gson.fromJson(arguments[3] as String, SampleType::class.java)

        scope.launch {
            try {
                wrapper.api.startRecording(identifier, exerciseId, interval, sampleType)
                result.success(null)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                result.error(e.toString(), e.message, null)
            }
        }
    }

    private fun stopRecording(
        call: MethodCall,
        result: Result,
    ) {
        val identifier = call.arguments as String

        scope.launch {
            try {
                wrapper.api.stopRecording(identifier)
                result.success(null)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                result.error(e.toString(), e.message, null)
            }
        }
    }

    private fun requestRecordingStatus(
        call: MethodCall,
        result: Result,
    ) {
        val identifier = call.arguments as String

        scope.launch {
            try {
                val status = wrapper.api.requestRecordingStatus(identifier)
                result.success(listOf(status.first, status.second))
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                result.error(e.toString(), e.message, null)
            }
        }
    }

    private fun listExercises(
        call: MethodCall,
        result: Result,
    ) {
        val identifier = call.arguments as String

        scope.launch {
            val exercises = mutableListOf<String>()
            try {
                wrapper.api
                    .listExercises(identifier)
                    .collect { exercises.add(gson.toJson(it)) }
                result.success(exercises)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                result.error(e.toString(), e.message, null)
            }
        }
    }

    private fun fetchExercise(
        call: MethodCall,
        result: Result,
    ) {
        val arguments = call.arguments as List<*>
        val identifier = arguments[0] as String
        val entry = gson.fromJson(arguments[1] as String, PolarExerciseEntry::class.java)

        scope.launch {
            try {
                val exercise = wrapper.api.fetchExercise(identifier, entry)
                result.success(gson.toJson(exercise))
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                result.error(e.toString(), e.message, null)
            }
        }
    }

    private fun removeExercise(
        call: MethodCall,
        result: Result,
    ) {
        val arguments = call.arguments as List<*>
        val identifier = arguments[0] as String
        val entry = gson.fromJson(arguments[1] as String, PolarExerciseEntry::class.java)

        scope.launch {
            try {
                wrapper.api.removeExercise(identifier, entry)
                result.success(null)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                result.error(e.toString(), e.message, null)
            }
        }
    }

    private fun setLedConfig(
        call: MethodCall,
        result: Result,
    ) {
        val arguments = call.arguments as List<*>
        val identifier = arguments[0] as String
        val config = gson.fromJson(arguments[1] as String, LedConfig::class.java)

        scope.launch {
            try {
                wrapper.api.setLedConfig(identifier, config)
                result.success(null)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                result.error(e.toString(), e.message, null)
            }
        }
    }

    private fun doFactoryReset(
        call: MethodCall,
        result: Result,
    ) {
        val identifier = call.arguments as String

        scope.launch {
            try {
                wrapper.api.doFactoryReset(identifier)
                result.success(null)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                result.error(e.toString(), e.message, null)
            }
        }
    }

    private fun doRestart(
        call: MethodCall,
        result: Result,
    ) {
        val identifier = call.arguments as String

        scope.launch {
            try {
                wrapper.api.doRestart(identifier)
                result.success(null)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                result.error(e.toString(), e.message, null)
            }
        }
    }

    private fun enableSdkMode(
        call: MethodCall,
        result: Result,
    ) {
        val identifier = call.arguments as String

        scope.launch {
            try {
                wrapper.api.enableSDKMode(identifier)
                result.success(null)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                result.error(e.toString(), e.message, null)
            }
        }
    }

    private fun disableSdkMode(
        call: MethodCall,
        result: Result,
    ) {
        val identifier = call.arguments as String

        scope.launch {
            try {
                wrapper.api.disableSDKMode(identifier)
                result.success(null)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                result.error(e.toString(), e.message, null)
            }
        }
    }

    private fun setAutomaticOHRMeasurementEnabled(
        call: MethodCall,
        result: Result,
    ) {
        val args = call.arguments as List<*>
        val identifier = args[0] as String
        val enabled = args[1] as Boolean

        scope.launch {
            try {
                wrapper.api.setAutomaticOHRMeasurementEnabled(identifier, enabled)
                result.success(null)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                result.error(e.toString(), e.message, null)
            }
        }
    }

    private fun isSdkModeEnabled(
        call: MethodCall,
        result: Result,
    ) {
        val identifier = call.arguments as String

        scope.launch {
            try {
                val enabled = wrapper.api.isSDKModeEnabled(identifier)
                result.success(enabled)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                result.error(e.toString(), e.message, null)
            }
        }
    }

    private fun getAvailableOfflineRecordingDataTypes(call: MethodCall, result: Result) {
        val identifier = call.arguments as String

        scope.launch {
            try {
                val dataTypes = wrapper.api.getAvailableOfflineRecordingDataTypes(identifier)
                result.success(gson.toJson(dataTypes))
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                result.error(e.toString(), e.message, null)
            }
        }
    }

    private fun requestOfflineRecordingSettings(call: MethodCall, result: Result) {
        val arguments = call.arguments as List<*>
        val identifier = arguments[0] as String
        val feature = gson.fromJson(arguments[1] as String, PolarDeviceDataType::class.java)

        scope.launch {
            try {
                val settings = wrapper.api.requestOfflineRecordingSettings(identifier, feature)
                result.success(gson.toJson(settings))
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                result.error(e.toString(), e.message, null)
            }
        }
    }

    private fun startOfflineRecording(call: MethodCall, result: Result) {
        val arguments = call.arguments as List<*>
        val identifier = arguments[0] as String
        val feature = gson.fromJson(arguments[1] as String, PolarDeviceDataType::class.java)
        val settings = gson.fromJson(arguments[2] as String, PolarSensorSetting::class.java)

        scope.launch {
            try {
                wrapper.api.startOfflineRecording(identifier, feature, settings)
                result.success(null)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                result.error("ERROR_STARTING_RECORDING", e.message, null)
            }
        }
    }

    private fun stopOfflineRecording(call: MethodCall, result: Result) {
        val arguments = call.arguments as List<*>
        val identifier = arguments[0] as String
        val feature = gson.fromJson(arguments[1] as String, PolarDeviceDataType::class.java)

        scope.launch {
            try {
                wrapper.api.stopOfflineRecording(identifier, feature)
                result.success(null)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                result.error("ERROR_STOPPING_RECORDING", e.message, null)
            }
        }
    }

    private fun getOfflineRecordingStatus(call: MethodCall, result: Result) {
        val arguments = call.arguments as List<*>
        val identifier = arguments[0] as String

        scope.launch {
            try {
                val dataTypes = wrapper.api.getOfflineRecordingStatus(identifier)
                val dataTypeNames = dataTypes.map { it.name }
                result.success(dataTypeNames)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                result.error(e.toString(), e.message, null)
            }
        }
    }

    private fun setOfflineRecordingTrigger(call: MethodCall, result: Result) {
        val arguments = call.arguments as List<*>
        val identifier = arguments[0] as String
        val modeIndex = arguments[1] as Int
        @Suppress("UNCHECKED_CAST")
        val featuresList = arguments[2] as List<List<Any?>>

        val mode = PolarOfflineRecordingTriggerMode.values()[modeIndex]

        val triggerFeatures = mutableMapOf<PolarDeviceDataType, PolarSensorSetting?>()
        for (entry in featuresList) {
            val feature = gson.fromJson(entry[0] as String, PolarDeviceDataType::class.java)
            val settings = (entry[1] as String?)?.let {
                gson.fromJson(it, PolarSensorSetting::class.java)
            }
            triggerFeatures[feature] = settings
        }

        val trigger = PolarOfflineRecordingTrigger(mode, triggerFeatures)

        scope.launch {
            try {
                wrapper.api.setOfflineRecordingTrigger(identifier, trigger, null)
                result.success(null)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                result.error("ERROR_SETTING_TRIGGER", e.message, null)
            }
        }
    }

    private fun listOfflineRecordings(call: MethodCall, result: Result) {
        val identifier = call.arguments as String

        scope.launch {
            try {
                // PSFTP directory walk — keep it off the main dispatcher.
                val recordings = withContext(Dispatchers.IO) {
                    val list = mutableListOf<String>()
                    wrapper.api
                        .listOfflineRecordings(identifier)
                        .collect { list.add(it.toJsonString()) }
                    list
                }
                result.success(recordings)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                result.error(e.toString(), e.message, null)
            }
        }
    }

    private fun getOfflineRecord(call: MethodCall, result: Result) {
        val arguments = call.arguments as List<*>
        val identifier = arguments[0] as String
        val entry = offlineEntryFromJson(arguments[1] as String)

        scope.launch {
            try {
                // Multi-MB PSFTP file read + JSON serialization of the whole
                // record — keep both off the main dispatcher.
                val json = withContext(Dispatchers.IO) {
                    val record = wrapper.api.getOfflineRecord(identifier, entry)
                    gson.toJson(record)
                }
                result.success(json)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                result.error(e.toString(), e.message, null)
            }
        }
    }

    private fun removeOfflineRecord(call: MethodCall, result: Result) {
        val arguments = call.arguments as List<*>
        val identifier = arguments[0] as String
        val entry = offlineEntryFromJson(arguments[1] as String)

        scope.launch {
            try {
                wrapper.api.removeOfflineRecord(identifier, entry)
                result.success(null)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                result.error(e.toString(), e.message, null)
            }
        }
    }

    private fun getChargerState(call: MethodCall, result: Result) {
        val identifier = call.arguments as String
        // The SDK call is synchronous BLE-adjacent work — run it off the
        // platform channel thread instead of blocking it.
        scope.launch {
            try {
                val chargeState = withContext(Dispatchers.IO) {
                    wrapper.api.getChargerState(identifier)
                }
                result.success(chargeState.name)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                result.error("GET_CHARGER_STATE_ERROR", e.message, null)
            }
        }
    }

    private fun getDiskSpace(call: MethodCall, result: Result) {
        val identifier = call.arguments as String

        scope.launch {
            try {
                val (availableSpace, freeSpace) = wrapper.api.getDiskSpace(identifier)
                result.success(listOf(availableSpace, freeSpace))
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                result.error(e.toString(), e.message, null)
            }
        }
    }

    private fun getLocalTime(call: MethodCall, result: Result) {
        val identifier = call.arguments as? String ?: run {
            result.error("ERROR_INVALID_ARGUMENT", "Expected a single String argument", null)
            return
        }

        scope.launch {
            try {
                val deviceTime = wrapper.api.getLocalTime(identifier)
                try {
                    val timeString = deviceTime.format(DateTimeFormatter.ISO_LOCAL_DATE_TIME)
                    result.success(timeString)
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    result.error("ERROR_FORMATTING_TIME", e.message, null)
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                result.error(e.toString(), e.message, null)
            }
        }
    }

    private fun setLocalTime(call: MethodCall, result: Result) {
        val arguments = call.arguments as List<*>
        val identifier = arguments[0] as String
        val timestamp = arguments[1] as Double

        // Convert the timestamp to LocalDateTime
        val instant = java.time.Instant.ofEpochMilli((timestamp * 1000).toLong())
        val localDateTime = java.time.LocalDateTime.ofInstant(instant, ZoneId.systemDefault())

        scope.launch {
            try {
                wrapper.api.setLocalTime(identifier, localDateTime)
                result.success(null)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                result.error(e.toString(), e.message, null)
            }
        }
    }

    private fun doFirstTimeUse(call: MethodCall, result: Result) {
        val arguments = call.arguments as Map<*, *>
        val identifier = arguments["identifier"] as? String
        val configMap = arguments["config"] as? Map<*, *>

        if (identifier == null || configMap == null) {
            result.error(
                "INVALID_ARGUMENTS",
                "Expected identifier and config map",
                null
            )
            return
        }
        // Extract configuration values
        val gender = configMap["gender"] as? String
        val birthDateString = configMap["birthDate"] as? String
        val height = (configMap["height"] as? Int)?.toFloat()
        val weight = (configMap["weight"] as? Int)?.toFloat()
        val maxHeartRate = configMap["maxHeartRate"] as? Int
        val vo2Max = configMap["vo2Max"] as? Int
        val restingHeartRate = configMap["restingHeartRate"] as? Int
        val trainingBackground = configMap["trainingBackground"] as? Int
        val deviceTime = configMap["deviceTime"] as? String
        val typicalDay = configMap["typicalDay"] as? Int
        val sleepGoalMinutes = configMap["sleepGoalMinutes"] as? Int

        // Validate required parameters
        if (gender == null || birthDateString == null || height == null || weight == null ||
            maxHeartRate == null || vo2Max == null || restingHeartRate == null ||
            trainingBackground == null || deviceTime == null || typicalDay == null ||
            sleepGoalMinutes == null
        ) {
            result.error(
                "INVALID_CONFIG",
                "Invalid configuration parameters",
                null
            )
            return
        }

        // Parse birth date
        val birthDate = java.time.LocalDate.parse(birthDateString)

        // Map gender string to PolarFirstTimeUseConfig.Gender enum
        val genderEnum = when (gender) {
            "Male" -> PolarFirstTimeUseConfig.Gender.MALE
            "Female" -> PolarFirstTimeUseConfig.Gender.FEMALE
            else -> throw IllegalArgumentException("Invalid gender value")
        }

        // Map typicalDay to PolarFirstTimeUseConfig.TypicalDay enum
        val typicalDayEnum = when (typicalDay) {
            1 -> PolarFirstTimeUseConfig.TypicalDay.MOSTLY_MOVING
            2 -> PolarFirstTimeUseConfig.TypicalDay.MOSTLY_SITTING
            3 -> PolarFirstTimeUseConfig.TypicalDay.MOSTLY_STANDING
            else -> PolarFirstTimeUseConfig.TypicalDay.MOSTLY_SITTING // Default
        }

        // Create PolarFirstTimeUseConfig instance
        val ftuConfig = PolarFirstTimeUseConfig(
            genderEnum,
            birthDate,
            height,
            weight,
            maxHeartRate,
            vo2Max,
            restingHeartRate,
            trainingBackground,
            deviceTime,
            typicalDayEnum,
            sleepGoalMinutes
        )

        // Call the Polar API
        scope.launch {
            try {
                wrapper.api.doFirstTimeUse(identifier, ftuConfig)
                result.success(null)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                result.error(e.toString(), e.message, null)
            }
        }
    }

    private fun isFtuDone(call: MethodCall, result: Result) {
        val identifier = call.arguments as? String ?: run {
            result.error("ERROR_INVALID_ARGUMENT", "Expected a single String argument", null)
            return
        }

        scope.launch {
            try {
                val isFtuDone = wrapper.api.isFtuDone(identifier)
                result.success(isFtuDone)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                result.error(e.toString(), e.message, null)
            }
        }
    }

    private fun deleteStoredDeviceData(call: MethodCall, result: Result) {
        val arguments = call.arguments as List<*>
        val identifier = arguments[0] as String

        // Map Dart enum name to Kotlin enum
        // Dart: undefined, activity, autoSample, dailySummary, nightlyRecovery, sdlogs, sleep, sleepScore, skinContactChanges, skintemp
        // Kotlin: ACTIVITY, AUTO_SAMPLE, DAILY_SUMMARY, NIGHTLY_RECOVERY, SDLOGS, SLEEP, SLEEP_SCORE, SKIN_CONTACT_CHANGES, SKIN_TEMP
        val dataTypeName = arguments[1] as String
        val dataType: PolarBleApi.PolarStoredDataType = when (dataTypeName) {
            "undefined" -> throw IllegalArgumentException("Cannot delete undefined data type")
            "activity" -> PolarBleApi.PolarStoredDataType.ACTIVITY
            "autoSample" -> PolarBleApi.PolarStoredDataType.AUTO_SAMPLE
            "dailySummary" -> PolarBleApi.PolarStoredDataType.DAILY_SUMMARY
            "nightlyRecovery" -> PolarBleApi.PolarStoredDataType.NIGHTLY_RECOVERY
            "sdlogs" -> PolarBleApi.PolarStoredDataType.SDLOGS
            "sleep" -> PolarBleApi.PolarStoredDataType.SLEEP
            "sleepScore" -> PolarBleApi.PolarStoredDataType.SLEEP_SCORE
            "skinContactChanges" -> PolarBleApi.PolarStoredDataType.SKIN_CONTACT_CHANGES
            "skintemp" -> PolarBleApi.PolarStoredDataType.SKIN_TEMP
            else -> throw IllegalArgumentException("Invalid PolarStoredDataType: $dataTypeName")
        }

        val until = LocalDate.parse(arguments[2] as String)

        scope.launch {
            try {
                wrapper.api.deleteStoredDeviceData(identifier, dataType, until)
                result.success(null)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                result.error(e.toString(), e.message, null)
            }
        }
    }

    private fun deleteDeviceDateFolders(call: MethodCall, result: Result) {
        val arguments = call.arguments as List<*>
        val identifier = arguments[0] as String
        val fromDate = LocalDate.parse(arguments[1] as String)
        val toDate = LocalDate.parse(arguments[2] as String)

        scope.launch {
            try {
                wrapper.api.deleteDeviceDateFolders(identifier, fromDate, toDate)
                result.success(null)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                result.error(e.toString(), e.message, null)
            }
        }
    }

    private fun getSteps(call: MethodCall, result: Result) {
        try {
            android.util.Log.d("PolarPlugin", "getSteps called with arguments: ${call.arguments}")

            val arguments = call.arguments as? List<*>
            if (arguments == null) {
                android.util.Log.e("PolarPlugin", "Arguments are null or not a List")
                result.error("INVALID_ARGUMENTS", "Arguments must be a non-null List", null)
                return
            }

            if (arguments.size < 3) {
                android.util.Log.e("PolarPlugin", "Arguments list size is less than 3: ${arguments.size}")
                result.error("INVALID_ARGUMENTS", "Expected 3 arguments: identifier, fromDate, toDate", null)
                return
            }

            val identifier = arguments[0] as? String
            if (identifier == null) {
                android.util.Log.e("PolarPlugin", "Identifier is null or not a String")
                result.error("INVALID_ARGUMENTS", "Device identifier must be a non-null String", null)
                return
            }

            val fromDateString = arguments[1] as? String
            if (fromDateString == null) {
                android.util.Log.e("PolarPlugin", "fromDate is null or not a String")
                result.error("INVALID_ARGUMENTS", "fromDate must be a non-null String", null)
                return
            }

            val toDateString = arguments[2] as? String
            if (toDateString == null) {
                android.util.Log.e("PolarPlugin", "toDate is null or not a String")
                result.error("INVALID_ARGUMENTS", "toDate must be a non-null String", null)
                return
            }

            android.util.Log.d("PolarPlugin", "Parsing dates: fromDate=$fromDateString, toDate=$toDateString")

            val fromDate = LocalDate.parse(fromDateString)
            val toDate = LocalDate.parse(toDateString)

            android.util.Log.d("PolarPlugin", "Calling Polar API getSteps with identifier=$identifier, fromDate=$fromDate, toDate=$toDate")

            scope.launch {
                try {
                    // Handle common errors from the Polar API
                    val stepsDataList: List<com.polar.sdk.api.model.activity.PolarStepsData> = try {
                        wrapper.api.getSteps(identifier, fromDate, toDate)
                    } catch (error: CancellationException) {
                        throw error
                    } catch (error: Throwable) {
                        // Log the error for debugging
                        android.util.Log.e("PolarPlugin", "Error in getSteps API call: ${error.message}", error)

                        // Special handling for specific error types
                        if (error.toString().contains("PftpResponseError") && error.toString().contains("Error: 103")) {
                            android.util.Log.e("PolarPlugin", "PSFTP Protocol error 103 - likely no steps data available for the requested period")
                            // Return an empty list instead of throwing an error
                            emptyList()
                        } else {
                            // For other errors, throw them to be caught by the error handler
                            throw error
                        }
                    }

                    android.util.Log.d("PolarPlugin", "Received steps data: ${stepsDataList.size} entries")
                    val response = stepsDataList.map { stepsData ->
                        mapOf(
                            "date" to (stepsData.date?.format(DateTimeFormatter.ISO_LOCAL_DATE) ?: ""),
                            "steps" to stepsData.steps
                        )
                    }
                    android.util.Log.d("PolarPlugin", "Returning steps data as JSON")
                    result.success(gson.toJson(response))
                } catch (error: CancellationException) {
                    throw error
                } catch (error: Throwable) {
                    android.util.Log.e("PolarPlugin", "Error in getSteps subscription: ${error.message}", error)
                    result.error("GET_STEPS_ERROR", "Error fetching steps data: ${error.message}", null)
                }
            }
        } catch (e: Exception) {
            android.util.Log.e("PolarPlugin", "Exception in getSteps", e)
            result.error("UNEXPECTED_ERROR", "Unexpected error in getSteps: ${e.message}", null)
        }
    }

    private fun getSleepRecordingState(call: MethodCall, result: Result) {
        val arguments = call.arguments as List<*>
        val identifier = arguments[0] as String
        val timeoutMs = (arguments[1] as Number).toLong()

        scope.launch {
            try {
                // Uses the SDK's own timeout (8.2.0+) rather than the wrapper
                // workaround this replaced. That workaround existed because
                // 8.1.0 buffered PS-FTP notifications in a LinkedBlockingQueue,
                // so take(1) cancelling the flow left the producer parked in a
                // blocking wait that coroutine cancellation could not interrupt
                // — structured concurrency then waited on it forever, and even
                // a withTimeoutOrNull around the collector would have joined
                // that stuck child. We had to abandon the collector instead.
                //
                // 8.2.0 replaced that queue with a cancellable Channel behind a
                // shared hot flow (BlePsFtpClient.kt, 156+/277-), so cancellation
                // now actually propagates and the SDK's withTimeoutOrNull works.
                // Throws PolarTimeoutException when the device stays silent.
                val state = wrapper.api.getSleepRecordingState(identifier, timeoutMs)
                android.util.Log.d("PolarPlugin", "getSleepRecordingState=$state")
                result.success(state)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                android.util.Log.e("PolarPlugin", "Error in getSleepRecordingState: ${e.message}", e)
                result.error(e.toString(), e.message, null)
            }
        }
    }

    private fun stopSleepRecording(call: MethodCall, result: Result) {
        val identifier = call.arguments as String

        scope.launch {
            try {
                wrapper.api.stopSleepRecording(identifier)
                android.util.Log.d("PolarPlugin", "stopSleepRecording completed")
                result.success(null)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                android.util.Log.e("PolarPlugin", "Error in stopSleepRecording: ${e.message}", e)
                result.error(e.toString(), e.message, null)
            }
        }
    }

    private fun getSleep(call: MethodCall, result: Result) {
        try {
            android.util.Log.d("PolarPlugin", "getSleep called with arguments: ${call.arguments}")

            val arguments = call.arguments as? List<*>
            if (arguments == null) {
                android.util.Log.e("PolarPlugin", "Arguments are null or not a List")
                result.error("INVALID_ARGUMENTS", "Arguments must be a non-null List", null)
                return
            }

            if (arguments.size < 3) {
                android.util.Log.e("PolarPlugin", "Arguments list size is less than 3: ${arguments.size}")
                result.error("INVALID_ARGUMENTS", "Expected 3 arguments: identifier, fromDate, toDate", null)
                return
            }

            val identifier = arguments[0] as? String
            if (identifier == null) {
                android.util.Log.e("PolarPlugin", "Identifier is null or not a String")
                result.error("INVALID_ARGUMENTS", "Device identifier must be a non-null String", null)
                return
            }

            val fromDateString = arguments[1] as? String
            if (fromDateString == null) {
                android.util.Log.e("PolarPlugin", "fromDate is null or not a String")
                result.error("INVALID_ARGUMENTS", "fromDate must be a non-null String", null)
                return
            }

            val toDateString = arguments[2] as? String
            if (toDateString == null) {
                android.util.Log.e("PolarPlugin", "toDate is null or not a String")
                result.error("INVALID_ARGUMENTS", "toDate must be a non-null String", null)
                return
            }

            val fromDate = LocalDate.parse(fromDateString)
            val toDate = LocalDate.parse(toDateString)

            android.util.Log.d("PolarPlugin", "Calling Polar API getSleep with identifier=$identifier, fromDate=$fromDate, toDate=$toDate")

            scope.launch {
                try {
                    val sleepDataList: List<com.polar.sdk.api.model.sleep.PolarSleepData> = try {
                        wrapper.api.getSleep(identifier, fromDate, toDate)
                    } catch (error: CancellationException) {
                        throw error
                    } catch (error: Throwable) {
                        android.util.Log.e("PolarPlugin", "Error in getSleep API call: ${error.message}", error)
                        // No sleep data for the requested period is not an exceptional
                        // situation — return an empty list instead of throwing.
                        if (error.toString().contains("PftpResponseError") && error.toString().contains("Error: 103")) {
                            android.util.Log.e("PolarPlugin", "PSFTP Protocol error 103 - likely no sleep data available for the requested period")
                            emptyList()
                        } else {
                            throw error
                        }
                    }

                    android.util.Log.d("PolarPlugin", "getSleep: received ${sleepDataList.size} entries from device")
                    // The device returns one entry per day in the requested range,
                    // most with no actual sleep (null start/end). Keep only entries
                    // with a real sleep period so the payload carries real sleep only.
                    // Built imperatively with fully explicit types: the device returns
                    // one entry per day in the range, most with no actual sleep (null
                    // start/end), so we keep only entries with a real sleep period.
                    val response = ArrayList<Map<String, Any?>>()
                    for (sleepData in sleepDataList) {
                        val analysis = sleepData.result ?: continue
                        val start = analysis.sleepStartTime ?: continue
                        val end = analysis.sleepEndTime ?: continue

                        val phases = ArrayList<Map<String, Any?>>()
                        analysis.sleepWakePhases?.forEach { phase ->
                            phases.add(
                                mapOf<String, Any?>(
                                    "offsetSeconds" to phase.secondsFromSleepStart,
                                    "state" to phase.state.name
                                )
                            )
                        }

                        val cycles = ArrayList<Map<String, Any?>>()
                        analysis.sleepCycles?.forEach { cycle ->
                            cycles.add(
                                mapOf<String, Any?>(
                                    "offsetSeconds" to cycle.secondsFromSleepStart,
                                    "sleepDepthStart" to cycle.sleepDepthStart
                                )
                            )
                        }

                        val entry = HashMap<String, Any?>()
                        entry["date"] = (sleepData.date?.format(DateTimeFormatter.ISO_LOCAL_DATE)
                            ?: analysis.sleepResultDate?.format(DateTimeFormatter.ISO_LOCAL_DATE)
                            ?: "")
                        entry["sleepStartTime"] = start.toInstant().toString()
                        entry["sleepEndTime"] = end.toInstant().toString()
                        entry["sleepGoalMinutes"] = analysis.sleepGoalMinutes
                        entry["userSleepRating"] = analysis.userSleepRating?.value
                        entry["sleepWakePhases"] = phases
                        entry["sleepCycles"] = cycles
                        response.add(entry)
                    }
                    android.util.Log.d(
                        "PolarPlugin",
                        "getSleep: ${response.size} entr(ies) with real sleep after filtering ${sleepDataList.size} day(s)"
                    )
                    val json = gson.toJson(response)
                    android.util.Log.d("PolarPlugin", "getSleep: returning JSON -> $json")
                    result.success(json)
                } catch (error: CancellationException) {
                    throw error
                } catch (error: Throwable) {
                    android.util.Log.e("PolarPlugin", "Error in getSleep subscription: ${error.message}", error)
                    result.error("GET_SLEEP_ERROR", "Error fetching sleep data: ${error.message}", null)
                }
            }
        } catch (e: Exception) {
            android.util.Log.e("PolarPlugin", "Exception in getSleep", e)
            result.error("UNEXPECTED_ERROR", "Unexpected error in getSleep: ${e.message}", null)
        }
    }

    private fun getDistance(call: MethodCall, result: Result) {
        try {
            android.util.Log.d("PolarPlugin", "getDistance called with arguments: ${call.arguments}")

            val arguments = call.arguments as? List<*>
            if (arguments == null) {
                android.util.Log.e("PolarPlugin", "Arguments are null or not a List")
                result.error("INVALID_ARGUMENTS", "Arguments must be a non-null List", null)
                return
            }

            if (arguments.size < 3) {
                android.util.Log.e("PolarPlugin", "Arguments list size is less than 3: ${arguments.size}")
                result.error("INVALID_ARGUMENTS", "Expected 3 arguments: identifier, fromDate, toDate", null)
                return
            }

            val identifier = arguments[0] as? String
            if (identifier == null) {
                android.util.Log.e("PolarPlugin", "Identifier is null or not a String")
                result.error("INVALID_ARGUMENTS", "Device identifier must be a non-null String", null)
                return
            }

            val fromDateString = arguments[1] as? String
            if (fromDateString == null) {
                android.util.Log.e("PolarPlugin", "fromDate is null or not a String")
                result.error("INVALID_ARGUMENTS", "fromDate must be a non-null String", null)
                return
            }

            val toDateString = arguments[2] as? String
            if (toDateString == null) {
                android.util.Log.e("PolarPlugin", "toDate is null or not a String")
                result.error("INVALID_ARGUMENTS", "toDate must be a non-null String", null)
                return
            }

            android.util.Log.d("PolarPlugin", "Parsing dates: fromDate=$fromDateString, toDate=$toDateString")

            val fromDate = LocalDate.parse(fromDateString)
            val toDate = LocalDate.parse(toDateString)

            android.util.Log.d("PolarPlugin", "Calling Polar API getDistance with identifier=$identifier, fromDate=$fromDate, toDate=$toDate")

            scope.launch {
                try {
                    val distanceDataList: List<com.polar.sdk.api.model.activity.PolarDistanceData> = try {
                        wrapper.api.getDistance(identifier, fromDate, toDate)
                    } catch (error: CancellationException) {
                        throw error
                    } catch (error: Throwable) {
                        // Log the error for debugging
                        android.util.Log.e("PolarPlugin", "Error in getDistance API call: ${error.message}", error)

                        // Special handling for specific error types
                        if (error.toString().contains("PftpResponseError") && error.toString().contains("Error: 103")) {
                            android.util.Log.e("PolarPlugin", "PSFTP Protocol error 103 - likely no distance data available for the requested period")
                            // Return an empty list instead of throwing an error
                            emptyList()
                        } else {
                            // For other errors, throw them to be caught by the error handler
                            throw error
                        }
                    }

                    android.util.Log.d("PolarPlugin", "Received distance data: ${distanceDataList.size} entries")
                    val response = distanceDataList.map { distanceData ->
                        mapOf(
                            "date" to (distanceData.date?.format(DateTimeFormatter.ISO_LOCAL_DATE) ?: ""),
                            "distanceMeters" to distanceData.distanceMeters
                        )
                    }
                    android.util.Log.d("PolarPlugin", "Returning distance data as JSON")
                    result.success(gson.toJson(response))
                } catch (error: CancellationException) {
                    throw error
                } catch (error: Throwable) {
                    android.util.Log.e("PolarPlugin", "Error in getDistance subscription: ${error.message}", error)
                    result.error("GET_DISTANCE_ERROR", "Error fetching distance data: ${error.message}", null)
                }
            }
        } catch (e: Exception) {
            android.util.Log.e("PolarPlugin", "Exception in getDistance", e)
            result.error("UNEXPECTED_ERROR", "Unexpected error in getDistance: ${e.message}", null)
        }
    }

    private fun getActiveTime(call: MethodCall, result: Result) {
        try {
            android.util.Log.d("PolarPlugin", "getActiveTime called with arguments: ${call.arguments}")

            val arguments = call.arguments as? List<*>
            if (arguments == null) {
                android.util.Log.e("PolarPlugin", "Arguments are null or not a List")
                result.error("INVALID_ARGUMENTS", "Arguments must be a non-null List", null)
                return
            }

            if (arguments.size < 3) {
                android.util.Log.e("PolarPlugin", "Arguments list size is less than 3: ${arguments.size}")
                result.error("INVALID_ARGUMENTS", "Expected 3 arguments: identifier, fromDate, toDate", null)
                return
            }

            val identifier = arguments[0] as? String
            if (identifier == null) {
                android.util.Log.e("PolarPlugin", "Identifier is null or not a String")
                result.error("INVALID_ARGUMENTS", "Device identifier must be a non-null String", null)
                return
            }

            val fromDateString = arguments[1] as? String
            if (fromDateString == null) {
                android.util.Log.e("PolarPlugin", "fromDate is null or not a String")
                result.error("INVALID_ARGUMENTS", "fromDate must be a non-null String", null)
                return
            }

            val toDateString = arguments[2] as? String
            if (toDateString == null) {
                android.util.Log.e("PolarPlugin", "toDate is null or not a String")
                result.error("INVALID_ARGUMENTS", "toDate must be a non-null String", null)
                return
            }

            android.util.Log.d("PolarPlugin", "Parsing dates: fromDate=$fromDateString, toDate=$toDateString")

            val fromDate = LocalDate.parse(fromDateString)
            val toDate = LocalDate.parse(toDateString)

            android.util.Log.d("PolarPlugin", "Calling Polar API getActiveTime with identifier=$identifier, fromDate=$fromDate, toDate=$toDate")

            scope.launch {
                try {
                    val activeTimeDataList: List<com.polar.sdk.api.model.activity.PolarActiveTimeData> = try {
                        wrapper.api.getActiveTime(identifier, fromDate, toDate)
                    } catch (error: CancellationException) {
                        throw error
                    } catch (error: Throwable) {
                        // Log the error for debugging
                        android.util.Log.e("PolarPlugin", "Error in getActiveTime API call: ${error.message}", error)

                        // Special handling for specific error types
                        if (error.toString().contains("PftpResponseError") && error.toString().contains("Error: 103")) {
                            android.util.Log.e("PolarPlugin", "PSFTP Protocol error 103 - likely no active time data available for the requested period")
                            // Return an empty list instead of throwing an error
                            emptyList()
                        } else {
                            // For other errors, throw them to be caught by the error handler
                            throw error
                        }
                    }

                    android.util.Log.d("PolarPlugin", "Received active time data: ${activeTimeDataList.size} entries")
                    val response = activeTimeDataList.map { activeTimeData ->
                        mapOf(
                            "date" to (activeTimeData.date?.format(DateTimeFormatter.ISO_LOCAL_DATE) ?: ""),
                            "timeNonWear" to mapActiveTime(activeTimeData.timeNonWear),
                            "timeSleep" to mapActiveTime(activeTimeData.timeSleep),
                            "timeSedentary" to mapActiveTime(activeTimeData.timeSedentary),
                            "timeLightActivity" to mapActiveTime(activeTimeData.timeLightActivity),
                            "timeContinuousModerateActivity" to mapActiveTime(activeTimeData.timeContinuousModerateActivity),
                            "timeIntermittentModerateActivity" to mapActiveTime(activeTimeData.timeIntermittentModerateActivity),
                            "timeContinuousVigorousActivity" to mapActiveTime(activeTimeData.timeContinuousVigorousActivity),
                            "timeIntermittentVigorousActivity" to mapActiveTime(activeTimeData.timeIntermittentVigorousActivity)
                        )
                    }
                    android.util.Log.d("PolarPlugin", "Returning active time data as JSON")
                    result.success(gson.toJson(response))
                } catch (error: CancellationException) {
                    throw error
                } catch (error: Throwable) {
                    android.util.Log.e("PolarPlugin", "Error in getActiveTime subscription: ${error.message}", error)
                    result.error("GET_ACTIVE_TIME_ERROR", "Error fetching active time data: ${error.message}", null)
                }
            }
        } catch (e: Exception) {
            android.util.Log.e("PolarPlugin", "Exception in getActiveTime", e)
            result.error("UNEXPECTED_ERROR", "Unexpected error in getActiveTime: ${e.message}", null)
        }
    }

    // Helper function to map PolarActiveTime
    private fun mapActiveTime(time: com.polar.sdk.api.model.activity.PolarActiveTime?): Map<String, Int?>? {
        if (time == null) return null

        return mapOf(
            "hours" to time.hours,
            "minutes" to time.minutes,
            "seconds" to time.seconds,
            "millis" to time.millis
        )
    }

    private fun getActivitySampleData(call: MethodCall, result: Result) {
        try {
            android.util.Log.d("PolarPlugin", "getActivitySampleData called with arguments: ${call.arguments}")

            val arguments = call.arguments as? List<*>
            if (arguments == null) {
                android.util.Log.e("PolarPlugin", "Arguments are null or not a List")
                result.error("INVALID_ARGUMENTS", "Arguments must be a non-null List", null)
                return
            }

            if (arguments.size < 3) {
                android.util.Log.e("PolarPlugin", "Arguments list size is less than 3: ${arguments.size}")
                result.error("INVALID_ARGUMENTS", "Expected 3 arguments: identifier, fromDate, toDate", null)
                return
            }

            val identifier = arguments[0] as? String
            if (identifier == null) {
                android.util.Log.e("PolarPlugin", "Identifier is null or not a String")
                result.error("INVALID_ARGUMENTS", "Device identifier must be a non-null String", null)
                return
            }

            val fromDateString = arguments[1] as? String
            if (fromDateString == null) {
                android.util.Log.e("PolarPlugin", "fromDate is null or not a String")
                result.error("INVALID_ARGUMENTS", "fromDate must be a non-null String", null)
                return
            }

            val toDateString = arguments[2] as? String
            if (toDateString == null) {
                android.util.Log.e("PolarPlugin", "toDate is null or not a String")
                result.error("INVALID_ARGUMENTS", "toDate must be a non-null String", null)
                return
            }

            android.util.Log.d("PolarPlugin", "Parsing dates: fromDate=$fromDateString, toDate=$toDateString")

            val fromDate = LocalDate.parse(fromDateString)
            val toDate = LocalDate.parse(toDateString)

            android.util.Log.d("PolarPlugin", "Calling Polar API getActivitySampleData with identifier=$identifier, fromDate=$fromDate, toDate=$toDate")

            scope.launch {
                try {
                    val activitySampleDataList: List<com.polar.sdk.api.model.activity.PolarActivitySamplesDayData> = try {
                        wrapper.api.getActivitySampleData(identifier, fromDate, toDate)
                    } catch (error: CancellationException) {
                        throw error
                    } catch (error: Throwable) {
                        android.util.Log.e("PolarPlugin", "Error in getActivitySampleData API call: ${error.message}", error)

                        if (error.toString().contains("PftpResponseError") && error.toString().contains("Error: 103")) {
                            android.util.Log.e("PolarPlugin", "PSFTP Protocol error 103 - likely no activity sample data available for the requested period")
                            emptyList()
                        } else {
                            throw error
                        }
                    }

                    android.util.Log.d("PolarPlugin", "Received activity sample data: ${activitySampleDataList.size} entries")

                    val response = activitySampleDataList.map { dayData ->
                        // Extract all samples data for this day
                        val samplesDataList = mutableListOf<Map<String, Any?>>()

                        dayData.polarActivitySamplesDataList?.let { samplesList ->
                            for (samplesData in samplesList) {
                                // Extract activity info for this sample
                                val activityInfoList = mutableListOf<Map<String, Any?>>()
                                samplesData.activityInfoList?.let { infoList ->
                                    for (activityInfo in infoList) {
                                        activityInfoList.add(mapOf(
                                            "timeStamp" to activityInfo.timeStamp.toString(),
                                            "activityClass" to activityInfo.activityClass?.name,
                                            "factor" to activityInfo.factor
                                        ))
                                    }
                                }

                                // Create complete samples data object
                                samplesDataList.add(mapOf(
                                    "startTime" to samplesData.startTime.toString(),
                                    "metRecordingInterval" to samplesData.metRecordingInterval,
                                    "metSamples" to samplesData.metSamples,
                                    "stepRecordingInterval" to samplesData.stepRecordingInterval,
                                    "stepSamples" to samplesData.stepSamples,
                                    "activityInfoList" to activityInfoList
                                ))
                            }
                        }

                        // Use startTime's local date — this is the sensor's calendar date
                        // (sensor local time, set via setLocalTime, matches the date folder
                        // the SDK read from). Only null if the day had no sample data.
                        val date = dayData.polarActivitySamplesDataList?.firstOrNull()?.startTime?.toLocalDate()?.format(DateTimeFormatter.ISO_LOCAL_DATE)

                        mapOf(
                            "date" to date,
                            "samplesDataList" to samplesDataList
                        )
                    }

                    android.util.Log.d("PolarPlugin", "Returning activity sample data as JSON")
                    result.success(gson.toJson(response))
                } catch (error: CancellationException) {
                    throw error
                } catch (error: Throwable) {
                    android.util.Log.e("PolarPlugin", "Error in getActivitySampleData subscription: ${error.message}", error)
                    result.error("GET_ACTIVITY_SAMPLE_DATA_ERROR", "Error fetching activity sample data: ${error.message}", null)
                }
            }
        } catch (e: Exception) {
            android.util.Log.e("PolarPlugin", "Exception in getActivitySampleData", e)
            result.error("UNEXPECTED_ERROR", "Unexpected error in getActivitySampleData: ${e.message}", null)
        }
    }

    private fun sendInitializationAndStartSyncNotifications(call: MethodCall, result: Result) {
        val identifier = call.arguments as? String ?: run {
            result.error("ERROR_INVALID_ARGUMENT", "Expected a single String argument", null)
            return
        }

        scope.launch {
            try {
                val success = wrapper.api.sendInitializationAndStartSyncNotifications(identifier)
                result.success(success)
            } catch (e: CancellationException) {
                throw e
            } catch (error: Throwable) {
                result.error(error.toString(), error.message, null)
            }
        }
    }

    private fun sendTerminateAndStopSyncNotifications(call: MethodCall, result: Result) {
        val identifier = call.arguments as? String ?: run {
            result.error("ERROR_INVALID_ARGUMENT", "Expected a single String argument", null)
            return
        }

        scope.launch {
            try {
                wrapper.api.sendTerminateAndStopSyncNotifications(identifier)
                result.success(null)
            } catch (e: CancellationException) {
                throw e
            } catch (error: Throwable) {
                result.error(error.toString(), error.message, null)
            }
        }
    }

    private fun checkFirmwareUpdate(call: MethodCall, result: Result) {
        val identifier = call.arguments as? String ?: run {
            result.error("ERROR_INVALID_ARGUMENT", "Expected a single String argument", null)
            return
        }

        scope.launch {
            try {
                // In SDK 8.x checkFirmwareUpdate returns a Flow instead of a Single.
                // Forward every emitted status (in practice a single one) as an event
                // and complete the method call afterwards, like the Rx version did.
                wrapper.api
                    .checkFirmwareUpdate(identifier)
                    .collect {
                        val json = gson.toJson(checkFirmwareUpdateStatusToMap(it))
                        wrapper.success("firmwareUpdateCheckStatusReceived", listOf(identifier, json))
                    }
                result.success(null)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                result.error(e.toString(), e.message, null)
            }
        }
    }

    private fun updateFirmware(call: MethodCall, result: Result) {
        val identifier: String
        val firmwareUrl: String?

        if (call.arguments is String) {
            identifier = call.arguments as String
            firmwareUrl = null
        } else if (call.arguments is List<*>) {
            val args = call.arguments as List<*>
            identifier = args[0] as String
            firmwareUrl = args[1] as String
        } else {
            result.error("ERROR_INVALID_ARGUMENT", "Expected String or List arguments", null)
            return
        }

        // SDK 8.x rewrote updateFirmware from an RxJava Flowable (subscribeOn(Schedulers.io()))
        // to a cold Flow that runs in the collector's context. Collecting on the main dispatcher
        // makes the blocking firmware download throw NetworkOnMainThreadException, so move the
        // upstream to IO while keeping collection (event sink calls) on main.
        val statusFlow = (if (firmwareUrl != null) {
            wrapper.api.updateFirmware(identifier, firmwareUrl)
        } else {
            wrapper.api.updateFirmware(identifier)
        }).flowOn(Dispatchers.IO)

        scope.launch {
            var lastStatus: FirmwareUpdateStatus? = null

            try {
                statusFlow.collect {
                    lastStatus = it
                    val json = gson.toJson(firmwareUpdateStatusToMap(it))
                    wrapper.success("firmwareUpdateStatusReceived", listOf(identifier, json))
                }
                result.success(null)
            } catch (e: CancellationException) {
                throw e
            } catch (error: Throwable) {
                // During firmware update, the device reboots which causes a BleDisconnected.
                // If we were in the finalizing stage, this is expected and means success.
                if (error is BleDisconnected &&
                    (lastStatus is FirmwareUpdateStatus.FinalizingFwUpdate ||
                     lastStatus is FirmwareUpdateStatus.FwUpdateCompletedSuccessfully)) {
                    // Emit a completed status before finishing
                    val completedJson = gson.toJson(mapOf("type" to "completed", "details" to "Firmware update completed, device rebooting"))
                    wrapper.success("firmwareUpdateStatusReceived", listOf(identifier, completedJson))
                    result.success(null)
                } else {
                    result.error(error.toString(), error.message, null)
                }
            }
        }
    }

    private fun checkFirmwareUpdateStatusToMap(status: CheckFirmwareUpdateStatus): Map<String, Any?> {
        return when (status) {
            is CheckFirmwareUpdateStatus.CheckFwUpdateAvailable -> mapOf(
                "type" to "available",
                "version" to status.version
            )
            is CheckFirmwareUpdateStatus.CheckFwUpdateNotAvailable -> mapOf(
                "type" to "notAvailable",
                "details" to status.details
            )
            is CheckFirmwareUpdateStatus.CheckFwUpdateFailed -> mapOf(
                "type" to "failed",
                "details" to status.details
            )
        }
    }

    private fun firmwareUpdateStatusToMap(status: FirmwareUpdateStatus): Map<String, Any?> {
        return when (status) {
            is FirmwareUpdateStatus.FetchingFwUpdatePackage -> mapOf("type" to "fetching", "details" to status.details)
            is FirmwareUpdateStatus.PreparingDeviceForFwUpdate -> mapOf("type" to "preparing", "details" to status.details)
            is FirmwareUpdateStatus.WritingFwUpdatePackage -> mapOf("type" to "writing", "details" to status.details)
            is FirmwareUpdateStatus.FinalizingFwUpdate -> mapOf("type" to "finalizing", "details" to status.details)
            is FirmwareUpdateStatus.FwUpdateCompletedSuccessfully -> mapOf("type" to "completed", "details" to status.details)
            is FirmwareUpdateStatus.FwUpdateNotAvailable -> mapOf("type" to "notAvailable", "details" to status.details)
            is FirmwareUpdateStatus.FwUpdateFailed -> mapOf("type" to "failed", "details" to status.details)
        }
    }
}

class PolarWrapper(
    context: Context,
    val api: PolarBleApi =
        PolarBleApiDefaultImpl.defaultImplementation(
            context,
            PolarBleSdkFeature.values().toSet(),
        ),
    private val sinks: MutableMap<Int, EventSink> = mutableMapOf(),
) : PolarBleApiCallbackProvider {
    init {
        android.util.Log.d("PolarPlugin", "PolarWrapper init: setting API callback")
        api.setApiCallback(this)
    }

    fun addSink(
        id: Int,
        sink: EventSink,
    ) {
        sinks[id] = sink
        android.util.Log.d("PolarPlugin", "addSink: id=$id, total sinks=${sinks.size}")
    }

    fun removeSink(id: Int) {
        sinks.remove(id)
        android.util.Log.d("PolarPlugin", "removeSink: id=$id, remaining sinks=${sinks.size}")
    }

    internal fun success(
        event: String,
        data: Any?,
    ) {
        android.util.Log.d("PolarPlugin", "success: event=$event, sinks.size=${sinks.size}")
        runOnUiThread {
            if (sinks.isEmpty()) {
                android.util.Log.w("PolarPlugin", "success: No sinks registered for event=$event")
            }
            sinks.values.forEach { it.success(mapOf("event" to event, "data" to data)) }
        }
    }

    fun shutDown() {
        // Do not shutdown the api if other engines are still using it
        if (sinks.isNotEmpty()) return
        try {
            api.shutDown()
        } catch (e: Exception) {
            // This will throw if the API is already shut down
        }
    }

    override fun blePowerStateChanged(powered: Boolean) {
        success("blePowerStateChanged", powered)
    }

    override fun bleSdkFeatureReady(
        identifier: String,
        feature: PolarBleSdkFeature,
    ) {
        android.util.Log.d("PolarPlugin", "bleSdkFeatureReady: identifier=$identifier, feature=${feature.name}")
        success("sdkFeatureReady", listOf(identifier, feature.name))
    }

    override fun bleSdkFeaturesReadiness(
        identifier: String,
        ready: List<PolarBleSdkFeature>,
        unavailable: List<PolarBleSdkFeature>,
    ) {
        android.util.Log.d("PolarPlugin", "bleSdkFeaturesReadiness: identifier=$identifier, ready=${ready.map { it.name }}, unavailable=${unavailable.map { it.name }}")
        success("sdkFeaturesReadiness", listOf(identifier, ready.map { it.name }, unavailable.map { it.name }))
    }

    override fun deviceConnected(polarDeviceInfo: PolarDeviceInfo) {
        android.util.Log.d("PolarPlugin", "deviceConnected: deviceId=${polarDeviceInfo.deviceId}")
        success("deviceConnected", gson.toJson(polarDeviceInfo))
    }

    override fun deviceConnecting(polarDeviceInfo: PolarDeviceInfo) {
        android.util.Log.d("PolarPlugin", "deviceConnecting: deviceId=${polarDeviceInfo.deviceId}")
        success("deviceConnecting", gson.toJson(polarDeviceInfo))
    }

    override fun deviceDisconnected(polarDeviceInfo: PolarDeviceInfo) {
        android.util.Log.d("PolarPlugin", "deviceDisconnected: deviceId=${polarDeviceInfo.deviceId}")
        success(
            "deviceDisconnected",
            // The second argument is the `pairingError` field on iOS
            // Since Android doesn't implement that, always send false
            listOf(gson.toJson(polarDeviceInfo), false),
        )
    }

    override fun disInformationReceived(
        identifier: String,
        uuid: UUID,
        value: String,
    ) {
        success("disInformationReceived", listOf(identifier, uuid.toString(), value))
    }

    override fun disInformationReceived(
        identifier: String,
        disInfo: DisInfo,
    ) {
        success("disInformationReceived", listOf(identifier, disInfo.key, disInfo.value))
    }

    override fun batteryLevelReceived(
        identifier: String,
        level: Int,
    ) {
        success("batteryLevelReceived", listOf(identifier, level))
    }

    override fun batteryChargingStatusReceived(
        identifier: String,
        chargingStatus: ChargeState,
    ) {
        success("batteryChargingStatusReceived", listOf(identifier, chargingStatus.name))
    }

    override fun htsNotificationReceived(
        identifier: String,
        data: PolarHealthThermometerData,
    ) {
        // Do nothing
    }

    override fun hrNotificationReceived(
        identifier: String,
        data: PolarHrData.PolarHrSample,
    ) {
        // Do nothing
    }

    override fun powerSourcesStateReceived(
        identifier: String,
        powerSourcesState: PowerSourcesState,
    ) {
        success("powerSourcesStateReceived", listOf(identifier, gson.toJson(powerSourcesState)))
    }
}

class StreamingChannel(
    messenger: BinaryMessenger,
    name: String,
    private val api: PolarBleApi,
    private val identifier: String,
    private val feature: PolarDeviceDataType,
    private val scope: CoroutineScope,
    private val channel: EventChannel = EventChannel(messenger, name),
) : EventChannel.StreamHandler {
    private var job: Job? = null

    init {
        channel.setStreamHandler(this)
    }

    override fun onListen(
        arguments: Any?,
        events: EventSink,
    ) {
        // Will be null for some features
        val settings = gson.fromJson(arguments as String, PolarSensorSetting::class.java)

        val stream: Flow<Any> =
            when (feature) {
                PolarDeviceDataType.HR -> api.startHrStreaming(identifier)
                PolarDeviceDataType.ECG -> api.startEcgStreaming(identifier, settings)
                PolarDeviceDataType.ACC -> api.startAccStreaming(identifier, settings)
                PolarDeviceDataType.PPG -> api.startPpgStreaming(identifier, settings)
                PolarDeviceDataType.PPI -> api.startPpiStreaming(identifier)
                PolarDeviceDataType.GYRO -> api.startGyroStreaming(identifier, settings)
                PolarDeviceDataType.MAGNETOMETER ->
                    api.startMagnetometerStreaming(
                        identifier,
                        settings,
                    )

                PolarDeviceDataType.TEMPERATURE ->
                    api.startTemperatureStreaming(
                        identifier,
                        settings,
                    )
                PolarDeviceDataType.PRESSURE -> api.startPressureStreaming(identifier, settings)
                PolarDeviceDataType.SKIN_TEMPERATURE -> api.startSkinTemperatureStreaming(identifier, settings)
                PolarDeviceDataType.LOCATION -> api.startLocationStreaming(identifier, settings)
            }

        job =
            scope.launch {
                var errored = false
                stream
                    .catch {
                        errored = true
                        events.error(it.toString(), it.message, null)
                    }
                    .collect { events.success(gson.toJson(it)) }
                if (!errored) events.endOfStream()
            }
    }

    override fun onCancel(arguments: Any?) {
        job?.cancel()
        job = null
    }

    fun dispose() {
        job?.cancel()
        channel.setStreamHandler(null)
    }
}
