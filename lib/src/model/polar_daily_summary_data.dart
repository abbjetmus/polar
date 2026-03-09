/// Represents the daily balance feedback from a Polar device.
///
/// This enum provides personalized training load recommendations
/// based on recovery analysis calculated on the device.
enum PolarDailyBalanceFeedBack {
  notCalculated,
  sick,
  fatigueTryToReduceTrainingLoadInjured,
  fatigueTryToReduceTrainingLoad,
  limitedTrainingResponseOtherInjured,
  limitedTrainingResponseOther,
  respondingWellCanContinueIfInjuryAllows,
  respondingWellCanContinue,
  youCouldDoMoreTrainingIfInjuryAllows,
  youCouldDoMoreTraining,
  youSeemToBeStrainedInjured,
  youSeemToBeStrained;

  static PolarDailyBalanceFeedBack fromString(String value) {
    switch (value) {
      case 'NOT_CALCULATED':
        return PolarDailyBalanceFeedBack.notCalculated;
      case 'SICK':
        return PolarDailyBalanceFeedBack.sick;
      case 'FATIGUE_TRY_TO_REDUCE_TRAINING_LOAD_INJURED':
        return PolarDailyBalanceFeedBack.fatigueTryToReduceTrainingLoadInjured;
      case 'FATIGUE_TRY_TO_REDUCE_TRAINING_LOAD':
        return PolarDailyBalanceFeedBack.fatigueTryToReduceTrainingLoad;
      case 'LIMITED_TRAINING_RESPONSE_OTHER_INJURED':
        return PolarDailyBalanceFeedBack.limitedTrainingResponseOtherInjured;
      case 'LIMITED_TRAINING_RESPONSE_OTHER':
        return PolarDailyBalanceFeedBack.limitedTrainingResponseOther;
      case 'RESPONDING_WELL_CAN_CONTINUE_IF_INJURY_ALLOWS':
        return PolarDailyBalanceFeedBack
            .respondingWellCanContinueIfInjuryAllows;
      case 'RESPONDING_WELL_CAN_CONTINUE':
        return PolarDailyBalanceFeedBack.respondingWellCanContinue;
      case 'YOU_COULD_DO_MORE_TRAINING_IF_INJURY_ALLOWS':
        return PolarDailyBalanceFeedBack
            .youCouldDoMoreTrainingIfInjuryAllows;
      case 'YOU_COULD_DO_MORE_TRAINING':
        return PolarDailyBalanceFeedBack.youCouldDoMoreTraining;
      case 'YOU_SEEM_TO_BE_STRAINED_INJURED':
        return PolarDailyBalanceFeedBack.youSeemToBeStrainedInjured;
      case 'YOU_SEEM_TO_BE_STRAINED':
        return PolarDailyBalanceFeedBack.youSeemToBeStrained;
      default:
        return PolarDailyBalanceFeedBack.notCalculated;
    }
  }

  String toApiString() {
    switch (this) {
      case PolarDailyBalanceFeedBack.notCalculated:
        return 'NOT_CALCULATED';
      case PolarDailyBalanceFeedBack.sick:
        return 'SICK';
      case PolarDailyBalanceFeedBack.fatigueTryToReduceTrainingLoadInjured:
        return 'FATIGUE_TRY_TO_REDUCE_TRAINING_LOAD_INJURED';
      case PolarDailyBalanceFeedBack.fatigueTryToReduceTrainingLoad:
        return 'FATIGUE_TRY_TO_REDUCE_TRAINING_LOAD';
      case PolarDailyBalanceFeedBack.limitedTrainingResponseOtherInjured:
        return 'LIMITED_TRAINING_RESPONSE_OTHER_INJURED';
      case PolarDailyBalanceFeedBack.limitedTrainingResponseOther:
        return 'LIMITED_TRAINING_RESPONSE_OTHER';
      case PolarDailyBalanceFeedBack.respondingWellCanContinueIfInjuryAllows:
        return 'RESPONDING_WELL_CAN_CONTINUE_IF_INJURY_ALLOWS';
      case PolarDailyBalanceFeedBack.respondingWellCanContinue:
        return 'RESPONDING_WELL_CAN_CONTINUE';
      case PolarDailyBalanceFeedBack.youCouldDoMoreTrainingIfInjuryAllows:
        return 'YOU_COULD_DO_MORE_TRAINING_IF_INJURY_ALLOWS';
      case PolarDailyBalanceFeedBack.youCouldDoMoreTraining:
        return 'YOU_COULD_DO_MORE_TRAINING';
      case PolarDailyBalanceFeedBack.youSeemToBeStrainedInjured:
        return 'YOU_SEEM_TO_BE_STRAINED_INJURED';
      case PolarDailyBalanceFeedBack.youSeemToBeStrained:
        return 'YOU_SEEM_TO_BE_STRAINED';
    }
  }
}

/// Represents the daily summary data from a Polar device.
class PolarDailySummaryData {
  /// The date for which the summary is recorded.
  final DateTime date;

  /// The number of steps recorded for the date.
  final int? steps;

  /// Calories burned from activity.
  final int? activityCalories;

  /// Calories burned from training.
  final int? trainingCalories;

  /// Basal metabolic rate calories.
  final int? bmrCalories;

  /// Distance covered in meters.
  final double? activityDistance;

  /// Daily balance feedback from recovery analysis.
  final PolarDailyBalanceFeedBack? dailyBalanceFeedback;

  PolarDailySummaryData({
    required this.date,
    this.steps,
    this.activityCalories,
    this.trainingCalories,
    this.bmrCalories,
    this.activityDistance,
    this.dailyBalanceFeedback,
  });

  factory PolarDailySummaryData.fromJson(Map<String, dynamic> json) {
    return PolarDailySummaryData(
      date: DateTime.parse(json['date']),
      steps: json['steps'] as int?,
      activityCalories: json['activityCalories'] as int?,
      trainingCalories: json['trainingCalories'] as int?,
      bmrCalories: json['bmrCalories'] as int?,
      activityDistance: (json['activityDistance'] as num?)?.toDouble(),
      dailyBalanceFeedback: json['dailyBalanceFeedback'] != null
          ? PolarDailyBalanceFeedBack.fromString(
              json['dailyBalanceFeedback'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'date': date.toIso8601String(),
      if (steps != null) 'steps': steps,
      if (activityCalories != null) 'activityCalories': activityCalories,
      if (trainingCalories != null) 'trainingCalories': trainingCalories,
      if (bmrCalories != null) 'bmrCalories': bmrCalories,
      if (activityDistance != null) 'activityDistance': activityDistance,
      if (dailyBalanceFeedback != null)
        'dailyBalanceFeedback': dailyBalanceFeedback!.toApiString(),
    };
  }
}
