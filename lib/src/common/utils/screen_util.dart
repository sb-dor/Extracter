import 'package:flutter/widgets.dart';

/// Logical layout size, by window width:
/// phone < 600 dp · tablet 600..1023 dp · desktop ≥ 1024 dp.
enum ScreenSize {
  phone,
  tablet,
  desktop;

  static ScreenSize fromWidth(double width) => switch (width) {
    >= 1024 => ScreenSize.desktop,
    >= 600 => ScreenSize.tablet,
    _ => ScreenSize.phone,
  };
}

extension ScreenUtilExtension on BuildContext {
  ScreenSize get screenSize => ScreenSize.fromWidth(MediaQuery.sizeOf(this).width);

  /// Evaluates the callback for the current [screenSize], falling back to [orElse].
  T screenSizeMaybeWhen<T>({
    required T Function() orElse,
    T Function()? phone,
    T Function()? tablet,
    T Function()? desktop,
  }) => switch (screenSize) {
    ScreenSize.phone => (phone ?? orElse)(),
    ScreenSize.tablet => (tablet ?? orElse)(),
    ScreenSize.desktop => (desktop ?? orElse)(),
  };
}
