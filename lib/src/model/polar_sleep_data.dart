/// Sleep/wake state of a single phase in the device's sleep hypnogram.
///
/// Mirrors Polar's `SleepWakeState`: `NONREM12` is light sleep, `NONREM3` is
/// deep sleep, `REM` is REM sleep, and `WAKE` is an interruption/awake period.
enum PolarSleepWakeState {
  /// State could not be determined.
  unknown,

  /// Awake / interruption during the sleep period.
  wake,

  /// REM sleep.
  rem,

  /// Light sleep (NREM stages 1–2).
  nonRem12,

  /// Deep sleep (NREM stage 3).
  nonRem3;

  /// Parses the native string value (`"WAKE"`, `"REM"`, `"NONREM12"`,
  /// `"NONREM3"`, `"UNKNOWN"`) into a [PolarSleepWakeState].
  static PolarSleepWakeState fromName(String? value) {
    switch (value) {
      case 'WAKE':
        return PolarSleepWakeState.wake;
      case 'REM':
        return PolarSleepWakeState.rem;
      case 'NONREM12':
        return PolarSleepWakeState.nonRem12;
      case 'NONREM3':
        return PolarSleepWakeState.nonRem3;
      default:
        return PolarSleepWakeState.unknown;
    }
  }

  /// The canonical native string value for this state.
  String get name {
    switch (this) {
      case PolarSleepWakeState.wake:
        return 'WAKE';
      case PolarSleepWakeState.rem:
        return 'REM';
      case PolarSleepWakeState.nonRem12:
        return 'NONREM12';
      case PolarSleepWakeState.nonRem3:
        return 'NONREM3';
      case PolarSleepWakeState.unknown:
        return 'UNKNOWN';
    }
  }
}

/// One phase of the sleep hypnogram: the [state] starting [offsetSeconds]
/// after [PolarSleepData.sleepStartTime] and lasting until the next phase.
class PolarSleepWakePhase {
  /// Seconds from sleep start at which this phase begins.
  final int offsetSeconds;

  /// The sleep/wake state of this phase.
  final PolarSleepWakeState state;

  /// Creates a new [PolarSleepWakePhase] instance.
  PolarSleepWakePhase({
    required this.offsetSeconds,
    required this.state,
  });

  /// Creates a [PolarSleepWakePhase] from a JSON map.
  factory PolarSleepWakePhase.fromJson(Map<String, dynamic> json) {
    return PolarSleepWakePhase(
      offsetSeconds: (json['offsetSeconds'] as num?)?.toInt() ?? 0,
      state: PolarSleepWakeState.fromName(json['state'] as String?),
    );
  }

  /// Converts this phase to a JSON map.
  Map<String, dynamic> toJson() => {
        'offsetSeconds': offsetSeconds,
        'state': state.name,
      };
}

/// One sleep cycle, beginning [offsetSeconds] after sleep start with the given
/// [sleepDepthStart] (0..1, where higher is deeper).
class PolarSleepCycle {
  /// Seconds from sleep start at which this cycle begins.
  final int offsetSeconds;

  /// Sleep depth at the start of the cycle (0..1).
  final double sleepDepthStart;

  /// Creates a new [PolarSleepCycle] instance.
  PolarSleepCycle({
    required this.offsetSeconds,
    required this.sleepDepthStart,
  });

  /// Creates a [PolarSleepCycle] from a JSON map.
  factory PolarSleepCycle.fromJson(Map<String, dynamic> json) {
    return PolarSleepCycle(
      offsetSeconds: (json['offsetSeconds'] as num?)?.toInt() ?? 0,
      sleepDepthStart: (json['sleepDepthStart'] as num?)?.toDouble() ?? 0,
    );
  }

  /// Converts this cycle to a JSON map.
  Map<String, dynamic> toJson() => {
        'offsetSeconds': offsetSeconds,
        'sleepDepthStart': sleepDepthStart,
      };
}

/// Represents the sleep analysis result for a single sleep period, as produced
/// by the Polar device's dedicated sleep algorithm (`PolarSleepApi.getSleep`).
///
/// This is the reliable on-device sleep detection — distinct from, and far more
/// accurate than, the `SLEEP` activity class found in activity sample data. In
/// addition to the sleep window it carries the full hypnogram
/// ([sleepWakePhases]: light/deep/REM/wake stages) and [sleepCycles].
class PolarSleepData {
  /// The date this sleep result belongs to (typically the wake-up date),
  /// in the device's local time. May be null if the device did not report it.
  final DateTime? date;

  /// Absolute start time of the detected sleep period. Null if unavailable.
  final DateTime? sleepStartTime;

  /// Absolute end time of the detected sleep period. Null if unavailable.
  final DateTime? sleepEndTime;

  /// The user's configured sleep goal in minutes, if reported.
  final int? sleepGoalMinutes;

  /// The user's self-rating of the sleep (-1 undefined .. 4 slept well), if any.
  final int? userSleepRating;

  /// The sleep hypnogram: ordered phases (light/deep/REM/wake) by offset from
  /// [sleepStartTime]. Empty if the device did not report stage data.
  final List<PolarSleepWakePhase> sleepWakePhases;

  /// The detected sleep cycles by offset from [sleepStartTime].
  final List<PolarSleepCycle> sleepCycles;

  /// Creates a new [PolarSleepData] instance.
  PolarSleepData({
    this.date,
    this.sleepStartTime,
    this.sleepEndTime,
    this.sleepGoalMinutes,
    this.userSleepRating,
    this.sleepWakePhases = const [],
    this.sleepCycles = const [],
  });

  /// Creates a [PolarSleepData] instance from a JSON map.
  factory PolarSleepData.fromJson(Map<String, dynamic> json) {
    DateTime? parse(dynamic value) {
      if (value == null) return null;
      final str = value as String;
      if (str.isEmpty) return null;
      return DateTime.tryParse(str);
    }

    return PolarSleepData(
      date: parse(json['date']),
      sleepStartTime: parse(json['sleepStartTime']),
      sleepEndTime: parse(json['sleepEndTime']),
      sleepGoalMinutes: (json['sleepGoalMinutes'] as num?)?.toInt(),
      userSleepRating: (json['userSleepRating'] as num?)?.toInt(),
      sleepWakePhases: ((json['sleepWakePhases'] as List?) ?? [])
          .map((e) => PolarSleepWakePhase.fromJson(e as Map<String, dynamic>))
          .toList(),
      sleepCycles: ((json['sleepCycles'] as List?) ?? [])
          .map((e) => PolarSleepCycle.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Converts this [PolarSleepData] instance to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'date': date?.toIso8601String(),
      'sleepStartTime': sleepStartTime?.toIso8601String(),
      'sleepEndTime': sleepEndTime?.toIso8601String(),
      'sleepGoalMinutes': sleepGoalMinutes,
      'userSleepRating': userSleepRating,
      'sleepWakePhases': sleepWakePhases.map((e) => e.toJson()).toList(),
      'sleepCycles': sleepCycles.map((e) => e.toJson()).toList(),
    };
  }
}
