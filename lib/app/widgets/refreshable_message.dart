import 'package:flutter/material.dart';

/// Content that does not scroll on its own — a spinner, an empty state, a
/// failure — made draggable so the screen around it can still be pulled.
///
/// A `RefreshIndicator` listens to a scrolling child. Without this the states
/// where refreshing matters most, the ones with nothing on screen to scroll,
/// would be the only states that ignore the gesture.
class RefreshableMessage extends StatelessWidget {
  const RefreshableMessage({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight.isFinite
                  ? constraints.maxHeight
                  : 0,
            ),
            child: Center(child: child),
          ),
        );
      },
    );
  }
}
