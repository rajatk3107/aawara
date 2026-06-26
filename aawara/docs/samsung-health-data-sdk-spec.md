# Samsung Health Data SDK — Capability Spec & vs. Health Connect

**SDK version:** 1.1.0 (`samsung-health-data-api-1.1.0.aar`)
**Source:** introspected directly from the bundled AAR (`/samsung-sdk/1.1.0 2/`) — class/field lists below are what the SDK actually exposes, not guesses.
**Date:** 2026-06-25

---

## 1. TL;DR

- The SDK reads **directly from the Samsung Health app's database on-device** (it `queries` `com.sec.android.app.shealth`). It does **not** depend on Health Connect, so it **sidesteps the problem that Samsung stopped exporting workouts to Health Connect.**
- For **workouts** it is **dramatically richer** than Health Connect: power, cadence, RPM, VO₂max, calorie-burn-rate, HR min/max/mean, full GPS route, **per-sample time-series logs**, swimming intervals, auto-detected flag, 113 exercise types.
- For **sleep** it gives the same stages as Health Connect **plus two things HC does not expose**: **`SLEEP_SCORE`** (Samsung's actual sleep score — read directly, no need to reverse-engineer it) and the **associated HR/SpO₂/skin-temperature series** for the night (HC only gave us **1** SpO₂ point; Samsung exposes the readings as a series with min/max).
- **Big caveat:** it is **Samsung-only** (Samsung phone + Samsung Health app, Android 10+), requires **Samsung partner registration / developer-mode allowlisting**, and—because the app is Flutter—needs a **native Kotlin bridge (platform channel)**, as there is no official Flutter package.

**Recommendation:** Use the Samsung Health Data SDK as the **primary source on Samsung devices** for workouts (mandatory — HC no longer has them) and to enrich sleep (real sleep score + SpO₂/HR series). Keep Health Connect as the **fallback** for non-Samsung devices.

---

## 2. How it differs from Health Connect (architecture)

| | Health Connect (current) | Samsung Health Data SDK |
|---|---|---|
| Data source | OS-level HC datastore; OEMs *write into* it | Samsung Health app's own DB, read directly |
| Samsung workouts | **Broken** — Samsung stopped exporting | **Available** (native source) |
| Coverage | Cross-OEM (Pixel, etc.) + many apps | **Samsung phones only** + Samsung Health |
| Sleep score | Not exposed | **`SLEEP_SCORE` field** |
| SpO₂ overnight | 1 aggregate point (observed) | Series of readings (min/max/avg) |
| Setup | Manifest permissions + runtime grant | Partner registration + Samsung Health grant UI |
| Flutter | `health` package exists | **No official package — needs native bridge** |

---

## 3. Prerequisites & caveats (read before committing)

- **Device:** Samsung phone with **Samsung Health 6.30.2+** installed; **Android 10+ (API 29)**; **no emulators** (real device only). Build toolchain needs **Java 17+**. Manifest `<queries>` targets `com.sec.android.app.shealth` / `com.samsung.android.wear.shealth`.
- **NO Samsung partnership needed to READ (personal use).** Per Samsung's docs, reading data only requires enabling **Developer Mode** in the Samsung Health app — and for **read** there is **no app registration at all** (no package name, no keystore hash). Steps: Samsung Health → ⋮ → Settings → About Samsung Health → tap the version line 10+ times → *Developer mode (Samsung Health Data SDK)* → agree → toggle **Developer Mode for Data Read** ON.
  - Partnership/access code is needed **only** to **write** data (access code + package name as Client ID) or to **distribute** the app publicly. Neither applies to a personal sideloaded app.
  - Samsung notes developer mode is "ONLY intended for testing/debugging your app, NOT for app users" — fine for a personal app, but not a public-release path.
- **Permissions:** runtime, granted **inside Samsung Health's own consent UI** via `requestPermissions(...)` per `(DataType, READ/WRITE)`.
- **Flutter integration:** the SDK is a Kotlin/Java **AAR**. You must write a **MethodChannel plugin** (Dart ⇄ Kotlin) that calls `HealthDataStore`, or a small companion module. Budget for this.
- **Not a Health Connect replacement everywhere:** on non-Samsung devices it does nothing — keep HC for those.
- Ships a **DataViewer APK** (`tool/DataViewer_1.1.0.apk`) you can sideload to browse exactly what data exists on the device before coding.

---

## 4. Full data-type catalog (all readable types)

From `DataTypes` (every entry is a readable `DataType`; ✔ = also in Health Connect, ➕ = Samsung-only / richer):

| Samsung DataType | In HC? | Notes |
|---|---|---|
| `EXERCISE` | ➕ much richer | workouts — see §5 |
| `EXERCISE_LOCATION` | ➕ | GPS route points |
| `SLEEP` | ➕ + score | stages **+ `SLEEP_SCORE`** — see §6 |
| `SLEEP_GOAL` | ✖ | user's sleep goal |
| `STEPS` / `STEPS_GOAL` | ✔ / ✖ | |
| `HEART_RATE` | ✔ | series w/ min/max/avg |
| `BLOOD_OXYGEN` | ✔ (sparse) | series w/ min/max/avg |
| `SKIN_TEMPERATURE` | partial | overnight skin temp |
| `BODY_TEMPERATURE` | ✔ | |
| `BLOOD_PRESSURE` | ✔ | |
| `BLOOD_GLUCOSE` | ✔ | |
| `BODY_COMPOSITION` | ✔ | weight, body fat, skeletal muscle, BMI… |
| `FLOORS_CLIMBED` | ✔ | |
| `ACTIVITY_SUMMARY` | ✖ | daily activity rollup (active time/cal) |
| `ACTIVE_CALORIES_BURNED_GOAL` / `ACTIVE_TIME_GOAL` | ✖ | goals |
| `WATER_INTAKE` / `WATER_INTAKE_GOAL` | ✔ / ✖ | |
| `NUTRITION` / `NUTRITION_GOAL` | ✔ / ✖ | food logs + targets |
| `ENERGY_SCORE` | ✖ | Samsung's daily **Energy Score** |
| `SLEEP_APNEA` | ✖ | sleep-apnea detection events |
| `IRREGULAR_HEART_RHYTHM_NOTIFICATION` | ✖ | AFib-style alerts |
| `USER_PROFILE` | ✖ | height/weight/age/sex/etc. |

Sleep stages enum: `UNDEFINED, AWAKE, LIGHT, DEEP, REM` (same granularity as HC).

---

## 5. WORKOUT — `EXERCISE` (the mandatory one)

### `ExerciseSession` fields (per workout)
`startTime, endTime, duration, exerciseType (one of 113), customTitle, calories, distance, count, countType, autoDetected, comment, vo2Max`

**Performance metrics (most absent from HC's exercise record):**
`maxSpeed, meanSpeed, maxCadence, meanCadence, maxHeartRate, meanHeartRate, minHeartRate, maxPower, meanPower, maxRpm, meanRpm, maxCalorieBurnRate, meanCalorieBurnRate, maxAltitude, minAltitude, altitudeGain, altitudeLoss, inclineDistance, declineDistance`

**Nested rich data:**
- `route: List<ExerciseLocation>` → GPS track: `latitude, longitude, altitude, accuracy, timestamp`
- `log: List<ExerciseLog>` → **per-sample time-series during the workout**: `timestamp, heartRate, cadence, power, speed, count`
- `swimmingLog: SwimmingLog` → `poolLength, totalDistance, totalDuration, swimmingIntervals[]` (per-lap stroke data)

**Aggregates:** `EXERCISE.TOTAL_CALORIES`, `EXERCISE.TOTAL_DURATION` via `aggregateData(...)` (e.g. weekly totals server-side).

### vs Health Connect
HC's `ExerciseSessionRecord` ≈ type + start/end + title + segments(reps) + laps + notes; HR/power/speed/cadence are **separate record streams you must correlate yourself**, and Samsung **no longer writes any of it**. Samsung's SDK returns **one self-contained session** with all aggregates + the route + the per-sample log. **Verdict: strictly and substantially better — and it's the only working source for Samsung workouts.**

### Exercise types
**113 predefined** (e.g. `WALKING, RUNNING, TRACK_RUNNING, STAIR_CLIMBING, CYCLING, SWIMMING, WEIGHT_MACHINE/strength, BASKETBALL, SOCCER, GOLF, …`) plus `OTHER` + `customTitle`, so the app's existing exercise list maps cleanly.

---

## 6. SLEEP — anything extra vs Health Connect?

**Yes — two meaningful wins.**

### `SLEEP` exposes:
- `SESSIONS: List<SleepSession>` where each session = `startTime, endTime, duration, stages: List<SleepStage>` and each stage = `startTime, endTime, stage(AWAKE/LIGHT/DEEP/REM)`. → same stage timeline we already build, but **straight from Samsung** (no Health-Connect gap-filling guesswork; our `inBed − awake` reconciliation becomes unnecessary).
- **`SLEEP_SCORE: Field<Integer>`** → **Samsung's real sleep score, read directly.** This eliminates the entire calibration effort (the 0.4–2 pt approximation work) — we can show Samsung's exact number.
- `DURATION`, `TOTAL_DURATION` aggregate, and `SLEEP_GOAL`.

### Associated vitals for the night
`HealthDataStore.readAssociatedData(AssociatedReadRequest)` + `AssociatedDataPoints.getDataPointOf(dataType)` lets you fetch the **HR / SpO₂ / skin-temperature points tied to a sleep session**. The `OxygenSaturation` and `HeartRate` entries each carry `oxygenSaturation/heartRate, min, max, startTime, endTime` and come back as a **series** — so the **overnight SpO₂ chart that Health Connect couldn't supply (only 1 point) is achievable here.** *(Exact sample density is device-dependent — verify with the DataViewer APK, but the SDK structure supports a series, unlike HC's single exported value.)*

### Plus Samsung-only sleep extras
- `SLEEP_APNEA` — apnea detection events.
- `SKIN_TEMPERATURE` — overnight skin-temp trend.
- `ENERGY_SCORE` — Samsung's daily readiness/energy score.

### vs Health Connect
| Sleep data | Health Connect | Samsung SDK |
|---|---|---|
| Stages (Awake/Light/Deep/REM) | ✔ | ✔ (native) |
| Sleep **score** | ✖ (we reverse-engineer it) | ✔ **`SLEEP_SCORE`** |
| Overnight SpO₂ series | ✖ (1 point observed) | ✔ series (min/max/avg) |
| Overnight HR series | ✔ | ✔ (min/max/avg) |
| Skin temperature | partial | ✔ |
| Sleep apnea | ✖ | ✔ |

**Verdict: better.** The two standout gains are **the real sleep score** and **a usable SpO₂ series**.

---

## 7. API model (how you'd actually read)

```
HealthDataService.getStore(context) -> HealthDataStore
store.requestPermissions({Permission.of(DataTypes.EXERCISE, AccessType.READ), …}, activity)
store.getGrantedPermissions(...)
store.readData(ReadDataRequest<…>)                  // filtered by LocalDateFilter / InstantTimeFilter, Ordering
store.readAssociatedData(AssociatedReadRequest)      // session + its HR/SpO₂/skin-temp
store.aggregateData(AggregateRequest<…>)             // e.g. weekly TOTAL_CALORIES / TOTAL_DURATION
store.readChanges(ChangedDataRequest<…>)             // incremental sync (deltas) — good for background sync
store.insert/update/deleteData(...)                  // write-back (we likely only need READ)
store.getDeviceManager()                             // which watch/phone produced the data
```
- **Permissions:** `Permission.of(DataType, AccessType.READ|WRITE)`, granted via Samsung Health's consent screen.
- **Filtering:** by local date / instant ranges, grouping units, ordering, and source filters.
- **Async styles:** Kotlin coroutines **and** `…Async()` Future variants (easier to call from a Kotlin MethodChannel handler).
- **Change feed:** `readChanges` gives deltas since a token — ideal for an efficient background sync instead of re-reading 30 days.

---

## 8. Recommended adoption path (for the Aawara app)

1. **Phase 0 — validate:** sideload `DataViewer_1.1.0.apk`, confirm Exercise + Sleep(+score) + SpO₂-series actually populate on this device. Register the app's package + debug-key hash for Samsung Health developer mode.
2. **Phase 1 — native bridge:** add the AAR to `android/app/libs`, write a `SamsungHealthChannel` (Kotlin) exposing `requestPermissions`, `readExercises(range)`, `readSleep(range)` (incl. `SLEEP_SCORE` + associated SpO₂/HR), `readChanges`. Expose to Dart via MethodChannel.
3. **Phase 2 — workouts (mandatory):** import Samsung exercise sessions into the workout DB (map 113 types → app exercises; store route/log if useful). Samsung-device only; HC fallback elsewhere.
4. **Phase 3 — sleep enrichment:** prefer Samsung `SLEEP_SCORE` over our computed score on Samsung devices; use the associated **SpO₂ series** to finally render the SpO₂ chart; optionally surface apnea / skin-temp / energy-score.
5. **Keep Health Connect** as the cross-OEM fallback and for non-Samsung users.

### Honest trade-offs
- ➕ Real Samsung data (workouts that HC lost), real sleep score, SpO₂ series, far richer workout metrics, incremental change feed.
- ➖ Samsung-only; partner approval; native bridge work; two code paths (Samsung SDK + HC) to maintain.
