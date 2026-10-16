/// The motion layer, in one import.
///
/// Screens import this and get the springs, the reduced-motion gate, the
/// durations and every primitive. The pieces live in their own files so each
/// one is small enough to hold in your head while changing it.
///
/// What used to be here — a SortedMotion class of cubic easing constants, and
/// its own copies of the press and list-entrance widgets — is gone. The
/// timings live with the springs in spring_curve.dart and motion_access.dart,
/// which is also where the rules about using them are written down.
library;

export 'enter_stagger.dart';
export 'motion_access.dart';
export 'page_transitions.dart';
export 'paid_announcer.dart';
export 'press_scale.dart';
export 'reveal.dart';
