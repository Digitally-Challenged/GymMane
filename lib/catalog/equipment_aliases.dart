import '../models/exercise.dart';

// General-purpose equipment does not create a new movement or replace history.
// Equipment identity: https://www.myarsenalstrength.com/product-listing
// Cable station capabilities:
// https://www.myarsenalstrength.com/strength-equipment/m-1/featured-m-1/m1-functional-trainer/
// https://www.myarsenalstrength.com/strength-equipment/m-1/upper-body/m1-bt
Exercise withEquipmentAliases(Exercise exercise) {
  final aliases = <String>[
    ...exercise.aliases,
    ...?kEquipmentAliases[exercise.name],
    if (exercise.equipment == 'Cable') ...[
      'Arsenal M-1 Functional Trainer ${exercise.name}',
      'Arsenal M1 Functional Trainer ${exercise.name}',
      'Arsenal M-1 Basic Trainer Cable Column ${exercise.name}',
    ],
    if (exercise.name.startsWith('Smith')) 'Arsenal Alpha Smith Machine ${exercise.name}',
  ];
  return aliases.isEmpty ? exercise : exercise.copyWith(aliases: List.unmodifiable(aliases.toSet()));
}

const kEquipmentAliases = <String, List<String>>{
  'Barbell Bench Press': ['Arsenal Alpha Olympic Flat Bench', 'Arsenal Alpha Competition Flat Bench'],
  'Barbell Incline Bench Press': ['Arsenal Alpha Olympic Incline Bench'],
  'Barbell Decline Bench Press': ['Arsenal Alpha Olympic Decline Bench'],
  'Barbell Seated Overhead Press': ['Arsenal Alpha Olympic Military Bench'],
  'Dumbbell Incline Bench Press': [
    'Arsenal Alpha Adjustable Lumbar Incline Bench',
    'Arsenal Alpha Multi Adjustable Bench',
    'Arsenal Bravo Multi Adjustable Bench',
  ],
  'Dumbbell Bench Press': ['Arsenal Alpha Flat Bench'],
  'Dumbbell Decline Bench Press': ['Arsenal Alpha Adjustable Decline Bench'],
  'Seated Dumbbell Shoulder Press': ['Arsenal Alpha Upright Utility Bench'],
  'One-Arm Dumbbell Row': ['Arsenal Alpha Dumbbell Row Kickback Bench Row'],
  'Dumbbell Triceps Kickback': ['Arsenal Alpha Dumbbell Row Kickback Bench Triceps Kickback'],
  'Barbell Full Squat': [
    'Arsenal Alpha Power Rack Squat',
    'Arsenal Alpha Half Rack Squat',
    'Arsenal Alpha Combo Rack Squat',
    'Arsenal Alpha Monolift Squat',
    'Arsenal Bravo Rack Squat',
    'Barbell Back Squat',
  ],
  'Barbell Bench Squat': ['Arsenal Alpha Squat Box', 'Barbell Box Squat'],
  'Dumbbell Incline Row': ['Dumbbell Chest Supported Row'],
  'Straight-Arm Pulldown': ['Cable Pullover', 'Cable Straight Arm Pulldown'],
};
