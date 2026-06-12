// Phase 11.7b.1 — Product Detail v2 scroll anchor encapsulation.
//
// Owns the 3 GlobalKey anchors that Product Detail uses for:
//   • `?section=interactions|research|ingredients|alternatives` deep-link landing
//   • The unsafe-verdict sticky CTA's "See safer alternatives" jump
//
// Lives outside the screen state so:
//   • The screen's build method doesn't carry anchor bookkeeping.
//   • The scroll behavior is unit-testable without pumping a full screen.
//   • Future v2 routes (deep-link emails, share-back URLs) wire the
//     same way.
//
// Behavior mirrors production semantics — same 280ms easeOutCubic curve,
// same try/catch fallback so platform-edge failures (no Scrollable
// ancestor in some tree configurations, render object not yet laid out)
// don't surface as new Sentry error classes.

import 'package:flutter/material.dart';

class ProductDetailScrollAnchors {
  /// Controller used only for deep-link priming. SliverList may not build
  /// offscreen keyed sections until the viewport is close to them, so a
  /// pure `ensureVisible(key.currentContext)` retry can wait forever on a
  /// null context. Priming scrolls near the requested section once, then
  /// the normal key-based exact scroll finishes the landing.
  final ScrollController scrollController = ScrollController();

  /// Anchor for the Better Alternatives sliver. The unsafe-CTA's
  /// "See safer alternatives" primary scrolls here.
  final GlobalKey alternativesKey = GlobalKey();

  /// Anchor for `?section=interactions` deep-link landing.
  final GlobalKey interactionsKey = GlobalKey();

  /// Anchor for `?section=research` deep-link landing.
  final GlobalKey researchKey = GlobalKey();

  /// Anchor for `?section=ingredients` deep-link landing.
  final GlobalKey ingredientsKey = GlobalKey();

  bool _didScrollToInitialSection = false;
  double _lastPrimeMaxScrollExtent = -1;
  int _scrollAttempts = 0;

  /// Scroll to the Better Alternatives sliver. No-op when the sliver
  /// hasn't been laid out yet — caller takes no harm.
  void scrollToAlternatives() {
    final ctx = alternativesKey.currentContext;
    if (ctx == null) return;
    try {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        alignment: 0.1,
      );
    } on Exception {
      // No-op — the user is no worse off than the deferred-key case.
    }
  }

  /// Smooth-scroll to an arbitrary anchored [key] with the same
  /// prime-and-retry mechanism the `?section=` deep links use. SliverList
  /// lazily builds offscreen children, so `key.currentContext` is null
  /// for any section below the fold — a plain `ensureVisible` would
  /// silently no-op. This primes the viewport toward [primeFraction] of
  /// the max scroll extent, awaits a frame so the target builds, then
  /// retries `ensureVisible` — capped at [_kScrollToKeyMaxAttempts]
  /// frames so a target that never renders can't keep the loop alive.
  ///
  /// Used by the score-breakdown pillar deep-links ("See details →").
  static const int _kScrollToKeyMaxAttempts = 120;

  void scrollToKey(
    GlobalKey key, {
    required bool Function() isMounted,
    double primeFraction = 0.5,
  }) {
    var attempts = 0;
    void attempt() {
      if (!isMounted()) return;
      final ctx = key.currentContext;
      if (ctx != null) {
        try {
          Scrollable.ensureVisible(
            ctx,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutCubic,
            alignment: 0.1,
          );
          return;
        } on Exception {
          // Built but not yet laid out — fall through to a retry frame.
        }
      } else {
        _primeTowardFraction(primeFraction);
      }
      if (++attempts >= _kScrollToKeyMaxAttempts) return;
      WidgetsBinding.instance.addPostFrameCallback((_) => attempt());
    }

    attempt();
  }

  void _primeTowardFraction(double fraction) {
    if (!scrollController.hasClients) return;
    if (fraction <= 0) return;
    final position = scrollController.position;
    final max = position.maxScrollExtent;
    if (max <= 0) return;
    final target = (max * fraction).clamp(0.0, max);
    if ((target - position.pixels).abs() < 24) return;
    try {
      scrollController.jumpTo(target);
    } on Exception {
      // Best-effort only; the key-based retry remains the source of truth.
    }
  }

  void resetInitialScroll() {
    _didScrollToInitialSection = false;
    _lastPrimeMaxScrollExtent = -1;
    _scrollAttempts = 0;
    if (scrollController.hasClients) {
      try {
        scrollController.jumpTo(0);
      } on Exception {
        // Best-effort reset; the next scheduled section scroll will
        // still retry from the current viewport if this fails.
      }
    }
  }

  void dispose() {
    scrollController.dispose();
  }

  /// Schedule a deep-link section scroll. Re-arms via post-frame
  /// callback until the target context is laid out, then bails.
  /// Gives up after 300 frames so a section that never renders (e.g.
  /// blob errored, `?section=interactions` on a blocked product)
  /// doesn't keep the loop alive forever.
  ///
  /// The retry budget is intentionally larger than a typical one-frame
  /// anchor wait because connected Product Detail lays out deep-dive
  /// sections only after the async detail blob resolves. A short retry
  /// window races that load and silently drops valid `?section=...`
  /// deep links.
  ///
  /// [initialSection] — the `?section=` query param value
  /// [isMounted] — closure the caller passes so the loop can check
  ///   the screen's `mounted` flag without holding a state reference.
  void scheduleInitialScroll({
    required String? initialSection,
    required bool Function() isMounted,
  }) {
    if (_didScrollToInitialSection) return;
    if (initialSection == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!isMounted() || _didScrollToInitialSection) return;
      final ctx = keyForSection(initialSection)?.currentContext;
      if (ctx != null) {
        try {
          Scrollable.ensureVisible(
            ctx,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            alignment: 0.1,
          );
          _didScrollToInitialSection = true;
        } on Exception {
          // The keyed section can exist before the scrollable is fully
          // laid out. Retry instead of silently dropping the deep link.
          if (++_scrollAttempts >= 300) {
            _didScrollToInitialSection = true;
            return;
          }
          scheduleInitialScroll(
            initialSection: initialSection,
            isMounted: isMounted,
          );
        }
        return;
      }
      _primeOffscreenSection(initialSection);
      if (++_scrollAttempts >= 300) {
        _didScrollToInitialSection = true;
        return;
      }
      scheduleInitialScroll(
        initialSection: initialSection,
        isMounted: isMounted,
      );
    });
  }

  /// Map a `?section=` query value to the matching anchor key. Unknown
  /// values return null — the screen falls through to normal top-of-
  /// page landing.
  GlobalKey? keyForSection(String? section) {
    return switch (section) {
      'interactions' => interactionsKey,
      'research' => researchKey,
      'ingredients' => ingredientsKey,
      'alternatives' => alternativesKey,
      _ => null,
    };
  }

  void _primeOffscreenSection(String section) {
    if (!scrollController.hasClients) return;
    final position = scrollController.position;
    final max = position.maxScrollExtent;
    if (max <= 0) return;
    if ((max - _lastPrimeMaxScrollExtent).abs() < 24) return;

    final fraction = switch (section) {
      'interactions' => 0.30,
      'research' => 0.42,
      'ingredients' => 0.55,
      'alternatives' => 0.90,
      _ => 0.0,
    };
    if (fraction <= 0) return;

    final target = max * fraction;
    if ((target - position.pixels).abs() < 24) return;
    _lastPrimeMaxScrollExtent = max;
    try {
      scrollController.jumpTo(target.clamp(0.0, max));
    } on Exception {
      // Best-effort only; the key-based retry loop remains the source of
      // truth once the target section is built.
    }
  }
}
