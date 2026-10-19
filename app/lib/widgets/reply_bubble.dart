import 'package:flutter/material.dart';

import '../core/theme/sorted_colors.dart';
import 'sorted_icon.dart';

/// The outgoing chat bubble from Reply.dc.html and Nudge.dc.html: ink fill,
/// a tail at the bottom right, the message, then the checkout link in its
/// own darker chip so the seller can see it survived.
class ReplyBubble extends StatelessWidget {
  const ReplyBubble({
    super.key,
    this.text,
    this.placeholder,
    this.link,
    this.wrapMessage,
    this.wrapLink,
  });

  /// The message. When null, [placeholder] is shown in muted ink instead.
  final String? text;
  final Widget? placeholder;
  final String? link;

  /// Wraps the message. Reply ready crossfades a rewritten tone through this;
  /// Order detail and the nudge sheet leave it unset and the words just sit.
  final Widget Function(Widget child)? wrapMessage;

  /// Wraps the checkout-link chip. Reply ready lands the link a beat after
  /// the words through this. Other screens leave it unset.
  final Widget Function(Widget child)? wrapLink;

  @override
  Widget build(BuildContext context) {
    final c = SortedColors.of(context);
    final style = Theme.of(context).textTheme;
    final url = link?.trim() ?? '';
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: c.ink,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(22),
              topRight: Radius.circular(22),
              bottomLeft: Radius.circular(22),
              bottomRight: Radius.circular(6),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _message(style, c),
              if (url.isNotEmpty) ...[
                const SizedBox(height: 12),
                _linkChip(style, c, url),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// The words, keyed when something is going to crossfade them, so a new
  /// tone replaces the old one instead of repainting it.
  Widget _message(TextTheme style, SortedColors c) {
    final Widget message;
    if (text != null) {
      message = Text(
        text!,
        key: wrapMessage == null ? null : ValueKey(text),
        style: style.bodyLarge?.copyWith(color: c.background),
      );
    } else {
      final fallback = placeholder ?? const SizedBox.shrink();
      message = wrapMessage == null || fallback.key != null
          ? fallback
          : KeyedSubtree(
              key: const ValueKey('reply-placeholder'),
              child: fallback,
            );
    }
    final wrap = wrapMessage;
    return wrap == null ? message : wrap(message);
  }

  Widget _linkChip(TextTheme style, SortedColors c, String url) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: c.darkLink,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          SortedIcon(SortedIcons.link, size: 18, color: c.highlight),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              url,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style.bodySmall?.copyWith(
                color: c.highlight,
                decoration: TextDecoration.underline,
                decorationColor: c.highlight,
              ),
            ),
          ),
        ],
      ),
    );
    final wrap = wrapLink;
    return wrap == null ? chip : wrap(chip);
  }
}
