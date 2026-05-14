import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';

/// Compact avatar — circular accent-tint tile with mono caps initials.
///
/// PharmaGuide is privacy-first; the app never asks for a profile photo.
/// Initials in a calm tinted circle communicate identity without
/// pretending to be a social network.
///
/// **Initial derivation:** first character of [name], or first chars of
/// the first two whitespace-separated tokens when [twoLetters] is true.
class PGAvatar extends StatelessWidget {
  /// Display name. Initials come from this.
  final String name;

  /// Diameter in logical pixels.
  final double size;

  /// When true, derives 2-letter initials from the first two words
  /// (e.g. "Sean Cheick" → "SC"). Otherwise 1 letter.
  final bool twoLetters;

  /// Override foreground color (defaults to accent).
  final Color? foreground;

  /// Override background color (defaults to accent-tint).
  final Color? background;

  const PGAvatar({
    super.key,
    required this.name,
    this.size = 56,
    this.twoLetters = false,
    this.foreground,
    this.background,
  });

  String _initials(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return '·';
    if (!twoLetters) {
      return trimmed.characters.first.toUpperCase();
    }
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length == 1) {
      return parts.first.characters.first.toUpperCase();
    }
    return (parts.first.characters.first + parts[1].characters.first)
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final fg = foreground ?? V2Colors.accent;
    final bg = background ?? V2Colors.accentTint;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Text(
        _initials(name),
        style: V2Typography.eyebrow(color: fg).copyWith(
          fontSize: size * 0.35,
        ),
      ),
    );
  }
}
