// SPIKE SHIM for `package:flutter/material.dart`.
//
// Only `lib/core/models/stack_intelligence.dart` reaches material, and only
// for `Color` on the `StackTier` enum (a presentation concern inside a model).
// Production fix: move the tier→Color mapping into the widget layer.
export 'foundation.dart';

class Color {
  const Color(this.value);
  final int value;
}
