package com.example.aawara

import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.time.Instant

import com.samsung.android.sdk.health.data.HealthDataService
import com.samsung.android.sdk.health.data.HealthDataStore
import com.samsung.android.sdk.health.data.data.entries.ExerciseLocation
import com.samsung.android.sdk.health.data.data.entries.ExerciseLog
import com.samsung.android.sdk.health.data.data.entries.ExerciseSession
import com.samsung.android.sdk.health.data.data.entries.HeartRate
import com.samsung.android.sdk.health.data.data.entries.OxygenSaturation
import com.samsung.android.sdk.health.data.data.entries.SleepSession
import com.samsung.android.sdk.health.data.permission.AccessType
import com.samsung.android.sdk.health.data.permission.Permission
import com.samsung.android.sdk.health.data.request.DataType
import com.samsung.android.sdk.health.data.request.DataTypes
import com.samsung.android.sdk.health.data.request.InstantTimeFilter

/**
 * Bridges Flutter to the Samsung Health Data SDK. Reads workouts, sleep, and
 * vitals straight from the Samsung Health app (bypassing Health Connect).
 *
 * Every call is runtime-gated: returns a benign result on non-Samsung devices,
 * Android < 10, or when Samsung Health isn't installed, so the app stays usable
 * everywhere. Results are returned as JSON strings for easy Dart parsing.
 */
class SamsungHealthBridge(
    private val activity: Activity,
    messenger: io.flutter.plugin.common.BinaryMessenger,
) {
    companion object {
        const val CHANNEL = "aawara/samsung_health"
        private const val SHEALTH_PKG = "com.sec.android.app.shealth"
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val channel = MethodChannel(messenger, CHANNEL)

    // Read-permission set for everything we extract.
    private val readTypes: List<DataType> = listOf(
        DataTypes.EXERCISE,
        DataTypes.SLEEP,
        DataTypes.HEART_RATE,
        DataTypes.BLOOD_OXYGEN,
        DataTypes.STEPS,
        DataTypes.SKIN_TEMPERATURE,
        DataTypes.ACTIVITY_SUMMARY,
        DataTypes.BODY_COMPOSITION,
        DataTypes.FLOORS_CLIMBED,
        DataTypes.ENERGY_SCORE,
    )

    fun register() {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "isAvailable" -> result.success(isAvailable())
                "requestPermissions" -> launchReply(result) { requestPermissions() }
                "getGranted" -> launchReply(result) { grantedTypeNames() }
                "readExercises" -> launchReply(result) { readExercises(call).toString() }
                "readSleep" -> launchReply(result) { readSleep(call).toString() }
                "readVitalSeries" -> launchReply(result) { readVitalSeries(call).toString() }
                else -> result.notImplemented()
            }
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
    }

    // ── gating ──────────────────────────────────────────────────────────────

    private fun isAvailable(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return false
        return try {
            activity.packageManager.getPackageInfo(SHEALTH_PKG, 0)
            true
        } catch (_: PackageManager.NameNotFoundException) {
            false
        }
    }

    private fun store(): HealthDataStore = HealthDataService.getStore(activity as Context)

    private fun permissionSet(): Set<Permission> =
        readTypes.map { Permission.of(it, AccessType.READ) }.toSet()

    // ── permissions ─────────────────────────────────────────────────────────

    private suspend fun requestPermissions(): String {
        if (!isAvailable()) return "[]"
        val store = store()
        store.requestPermissions(permissionSet(), activity)
        return grantedTypeNames()
    }

    private suspend fun grantedTypeNames(): String {
        if (!isAvailable()) return "[]"
        val granted = store().getGrantedPermissions(permissionSet())
        val arr = JSONArray()
        granted.forEach { arr.put(it.dataType.name) }
        return arr.toString()
    }

    // ── reads ─────────────────────────────────────────────────────────────────

    private suspend fun readExercises(call: MethodCall): JSONArray {
        val arr = JSONArray()
        if (!isAvailable()) return arr
        val (from, to) = window(call)
        val req = DataTypes.EXERCISE.readDataRequestBuilder
            .setInstantTimeFilter(InstantTimeFilter.of(from, to))
            .build()
        val resp = withContext(Dispatchers.IO) { store().readData(req) }
        for (p in resp.dataList) {
            val sessions = p.getValue(DataType.ExerciseType.SESSIONS) ?: continue
            val exType = p.getValue(DataType.ExerciseType.EXERCISE_TYPE)
            for (s in sessions) arr.put(exerciseJson(p.uid, exType?.name, s))
        }
        return arr
    }

    private suspend fun readSleep(call: MethodCall): JSONArray {
        val arr = JSONArray()
        if (!isAvailable()) return arr
        val (from, to) = window(call)
        val req = DataTypes.SLEEP.readDataRequestBuilder
            .setInstantTimeFilter(InstantTimeFilter.of(from, to))
            .build()
        val resp = withContext(Dispatchers.IO) { store().readData(req) }
        for (p in resp.dataList) {
            val score = p.getValue(DataType.SleepType.SLEEP_SCORE)
            val sessions = p.getValue(DataType.SleepType.SESSIONS) ?: continue
            for (s in sessions) arr.put(sleepJson(p.uid, score, s))
        }
        return arr
    }

    /** Heart-rate or blood-oxygen series within a window (incl. SpO₂ samples). */
    private suspend fun readVitalSeries(call: MethodCall): JSONArray {
        val arr = JSONArray()
        if (!isAvailable()) return arr
        val (from, to) = window(call)
        val type = call.argument<String>("type")
        if (type == "BLOOD_OXYGEN") {
            val req = DataTypes.BLOOD_OXYGEN.readDataRequestBuilder
                .setInstantTimeFilter(InstantTimeFilter.of(from, to)).build()
            val resp = withContext(Dispatchers.IO) { store().readData(req) }
            for (p in resp.dataList) {
                p.getValue(DataType.BloodOxygenType.SERIES_DATA)?.forEach { o: OxygenSaturation ->
                    arr.put(seriesJson(o.startTime, o.endTime, o.oxygenSaturation, o.min, o.max))
                }
            }
        } else {
            val req = DataTypes.HEART_RATE.readDataRequestBuilder
                .setInstantTimeFilter(InstantTimeFilter.of(from, to)).build()
            val resp = withContext(Dispatchers.IO) { store().readData(req) }
            for (p in resp.dataList) {
                p.getValue(DataType.HeartRateType.SERIES_DATA)?.forEach { h: HeartRate ->
                    arr.put(seriesJson(h.startTime, h.endTime, h.heartRate, h.min, h.max))
                }
            }
        }
        return arr
    }

    // ── JSON mapping ──────────────────────────────────────────────────────────

    private fun exerciseJson(uid: String, type: String?, s: ExerciseSession) = JSONObject().apply {
        put("uid", uid)
        put("exerciseType", type)
        put("customTitle", s.customTitle)
        put("startTime", s.startTime.toString())
        put("endTime", s.endTime.toString())
        put("durationSeconds", s.duration?.seconds)
        put("calories", s.calories.toDouble())
        putOpt("distance", s.distance?.toDouble())
        putOpt("count", s.count)
        putOpt("meanHeartRate", s.meanHeartRate?.toDouble())
        putOpt("maxHeartRate", s.maxHeartRate?.toDouble())
        putOpt("minHeartRate", s.minHeartRate?.toDouble())
        putOpt("meanSpeed", s.meanSpeed?.toDouble())
        putOpt("maxSpeed", s.maxSpeed?.toDouble())
        putOpt("meanCadence", s.meanCadence?.toDouble())
        putOpt("maxCadence", s.maxCadence?.toDouble())
        putOpt("meanPower", s.meanPower?.toDouble())
        putOpt("maxPower", s.maxPower?.toDouble())
        putOpt("meanRpm", s.meanRpm?.toDouble())
        putOpt("maxRpm", s.maxRpm?.toDouble())
        putOpt("meanCalorieBurnRate", s.meanCalorieBurnRate?.toDouble())
        putOpt("maxCalorieBurnRate", s.maxCalorieBurnRate?.toDouble())
        putOpt("altitudeGain", s.altitudeGain?.toDouble())
        putOpt("altitudeLoss", s.altitudeLoss?.toDouble())
        putOpt("maxAltitude", s.maxAltitude?.toDouble())
        putOpt("minAltitude", s.minAltitude?.toDouble())
        putOpt("inclineDistance", s.inclineDistance?.toDouble())
        putOpt("declineDistance", s.declineDistance?.toDouble())
        putOpt("vo2Max", s.vo2Max?.toDouble())
        putOpt("autoDetected", s.autoDetected)
        putOpt("comment", s.comment)
        // GPS route
        val route = s.route
        if (!route.isNullOrEmpty()) {
            put("route", JSONArray().apply {
                route.forEach { loc: ExerciseLocation ->
                    put(JSONObject().apply {
                        put("t", loc.timestamp.toString())
                        put("lat", loc.latitude.toDouble())
                        put("lng", loc.longitude.toDouble())
                        putOpt("alt", loc.altitude?.toDouble())
                    })
                }
            })
        }
        // Per-sample log (HR/cadence/power/speed time-series)
        val log = s.log
        if (!log.isNullOrEmpty()) {
            put("log", JSONArray().apply {
                log.forEach { e: ExerciseLog ->
                    put(JSONObject().apply {
                        put("t", e.timestamp.toString())
                        putOpt("hr", e.heartRate?.toDouble())
                        putOpt("cadence", e.cadence?.toDouble())
                        putOpt("power", e.power?.toDouble())
                        putOpt("speed", e.speed?.toDouble())
                    })
                }
            })
        }
    }

    private fun sleepJson(uid: String, score: Int?, s: SleepSession) = JSONObject().apply {
        put("uid", uid)
        putOpt("score", score)
        put("startTime", s.startTime.toString())
        put("endTime", s.endTime.toString())
        put("durationSeconds", s.duration?.seconds)
        put("stages", JSONArray().apply {
            s.stages?.forEach { st ->
                put(JSONObject().apply {
                    put("stage", st.stage.name)
                    put("start", st.startTime.toString())
                    put("end", st.endTime.toString())
                })
            }
        })
    }

    private fun seriesJson(start: Instant, end: Instant, v: Float, min: Float, max: Float) =
        JSONObject().apply {
            put("start", start.toString())
            put("end", end.toString())
            put("v", v.toDouble())
            put("min", min.toDouble())
            put("max", max.toDouble())
        }

    // ── helpers ───────────────────────────────────────────────────────────────

    private fun window(call: MethodCall): Pair<Instant, Instant> {
        val from = Instant.parse(call.argument<String>("from"))
        val to = Instant.parse(call.argument<String>("to"))
        return from to to
    }

    private fun launchReply(result: MethodChannel.Result, block: suspend () -> Any?) {
        scope.launch {
            try {
                result.success(block())
            } catch (e: Throwable) {
                result.error("samsung_health_error", e.message, e.toString())
            }
        }
    }
}
