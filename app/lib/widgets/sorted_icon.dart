import 'package:flutter/widgets.dart';
import 'package:hugeicons/hugeicons.dart';

/// A Hugeicons glyph (stroke-rounded SVG data).
typedef SortedIconData = List<List<dynamic>>;

/// Every icon the app uses, mapped from the design's Lucide icons to the
/// closest Hugeicons stroke-rounded glyph. Use these, never Material Icons.
abstract final class SortedIcons {
  // Tab bar
  static const home = HugeIcons.strokeRoundedHome01;
  static const orders = HugeIcons.strokeRoundedInvoice01;
  static const catalogue = HugeIcons.strokeRoundedGridView;
  static const settings = HugeIcons.strokeRoundedSlidersHorizontal;
  static const add = HugeIcons.strokeRoundedAdd01;

  // Headers and controls
  static const back = HugeIcons.strokeRoundedArrowLeft01;
  static const close = HugeIcons.strokeRoundedCancel01;
  static const minus = HugeIcons.strokeRoundedMinusSign;

  // Content
  static const shield = HugeIcons.strokeRoundedSecurityCheck;
  static const link = HugeIcons.strokeRoundedLink01;
  static const bell = HugeIcons.strokeRoundedNotification01;
  static const copy = HugeIcons.strokeRoundedCopy01;
  static const camera = HugeIcons.strokeRoundedCamera01;
  static const image = HugeIcons.strokeRoundedImage01;
  static const gallery = HugeIcons.strokeRoundedImage02;
  static const check = HugeIcons.strokeRoundedTick02;
  static const checkCircle = HugeIcons.strokeRoundedCheckmarkCircle02;
  static const circle = HugeIcons.strokeRoundedCircle;
  static const clock = HugeIcons.strokeRoundedClock01;
  static const alert = HugeIcons.strokeRoundedAlertCircle;
}

/// Drop-in for `Icon`: picks up size and colour from the surrounding
/// IconTheme (buttons, app bars) and draws at the design's 1.8 stroke.
class SortedIcon extends StatelessWidget {
  const SortedIcon(this.icon, {super.key, this.size, this.color, this.strokeWidth});

  final SortedIconData icon;
  final double? size;
  final Color? color;
  final double? strokeWidth;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final s = size ?? theme.size ?? 24;
    // Align loosens tight constraints (e.g. a 56 px Container), which would
    // otherwise stretch the SVG past [size]; factors of 1 keep it hugging.
    return Align(
      widthFactor: 1,
      heightFactor: 1,
      child: HugeIcon(
        icon: icon,
        size: s,
        color: color ?? theme.color,
        strokeWidth: strokeWidth ?? 1.8 * s / 24,
      ),
    );
  }
}
