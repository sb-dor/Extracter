import 'package:extracter/src/common/dependencies/dependencies.dart';
import 'package:flutter/widgets.dart';

/// Provides [Dependencies] to the widget tree.
class DependenciesScope extends InheritedWidget {
  const DependenciesScope({required this.dependencies, required super.child, super.key});

  final Dependencies dependencies;

  static Dependencies of(BuildContext context) {
    final widget = context.getElementForInheritedWidgetOfExactType<DependenciesScope>()?.widget;
    assert(widget != null, 'DependenciesScope was not found in element tree');
    return (widget! as DependenciesScope).dependencies;
  }

  @override
  bool updateShouldNotify(covariant DependenciesScope oldWidget) => false;
}
