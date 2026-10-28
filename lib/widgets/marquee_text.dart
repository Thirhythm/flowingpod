import 'package:flutter/material.dart';
import 'package:marquee/marquee.dart';

/// Single line text that scrolls like a marquee **only when it does not fit**.
///
/// Short labels stay perfectly still, so nothing moves for content that already
/// fits the available width.
///
/// The scroll ticker is muted while the app is in the background or while an
/// ancestor [TickerMode] is disabled (e.g. the page is covered by another
/// route), so an off-screen marquee never keeps the device awake.
class MarqueeText extends StatefulWidget {
  const MarqueeText({
    super.key,
    required this.text,
    this.style,
    this.velocity = 40,
    this.blankSpace = 48,
    this.pauseAfterRound = const Duration(seconds: 1),
    this.alignment = Alignment.centerLeft,
  });

  final String text;
  final TextStyle? style;

  /// Scrolling speed in logical pixels per second.
  final double velocity;

  /// Gap inserted between repetitions of the text.
  final double blankSpace;

  /// Pause once a full round has been shown.
  final Duration pauseAfterRound;

  final Alignment alignment;

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText> with WidgetsBindingObserver {
  /// Whether the app is in the foreground and may animate.
  bool _appActive = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _appActive = _isResumed(WidgetsBinding.instance.lifecycleState);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final active = _isResumed(state);
    if (active != _appActive) setState(() => _appActive = active);
  }

  /// Only `resumed` counts as active: `inactive`, `hidden` and `paused` all
  /// pause the scroll. A null state means the platform has not reported one
  /// yet, which is treated as active.
  static bool _isResumed(AppLifecycleState? state) =>
      state == null || state == AppLifecycleState.resumed;

  @override
  Widget build(BuildContext context) {
    final effectiveStyle = DefaultTextStyle.of(context).style
        .merge(widget.style);

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        // Without a bounded width the text cannot be measured meaningfully.
        if (!maxWidth.isFinite || maxWidth <= 0) {
          return Text(
            widget.text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: effectiveStyle,
          );
        }

        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: effectiveStyle),
          maxLines: 1,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();

        if (painter.width <= maxWidth) {
          return Container(
            alignment: widget.alignment,
            child: Text(
              widget.text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: effectiveStyle,
            ),
          );
        }

        // `Marquee` lays the text out in a horizontal viewport, which requires
        // a bounded height; the measured line height supplies it.
        return SizedBox(
          height: painter.height,
          child: TickerMode(
            // Keep the ancestor's value: Flutter disables it for pages that are
            // covered by an opaque route.
            enabled: _appActive && TickerMode.valuesOf(context).enabled,
            child: Marquee(
              text: widget.text,
              style: effectiveStyle,
              velocity: widget.velocity,
              blankSpace: widget.blankSpace,
              pauseAfterRound: widget.pauseAfterRound,
              fadingEdgeStartFraction: 0.05,
              fadingEdgeEndFraction: 0.05,
            ),
          ),
        );
      },
    );
  }
}
