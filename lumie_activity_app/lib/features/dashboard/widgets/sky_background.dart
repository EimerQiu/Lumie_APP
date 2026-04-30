import 'package:flutter/material.dart';

/// Visual mood of the sky background. Computed from wellness scores —
/// see [SkyMood.fromScores].
enum SkyMood {
  /// Bright blue sky, golden sun, soft white clouds — peak/high-score day.
  brightSky,

  /// Warm orange + pink horizon — good activity but poor sleep.
  warmTwilight,

  /// Dark stormy sky — high stress.
  stormy,

  /// Flat overcast grey — sedentary / low-activity day.
  overcast,

  /// Deep navy starfield — late night.
  starryNight,

  /// Aurora borealis over a galaxy — readiness + sleep + activity all peak.
  aurora,

  /// Soft pastel sunrise — average / maintenance day.
  pastelSunrise;

  /// Pick a mood from the day's wellness signals.
  ///
  /// All score arguments are 0–100 where higher = better; in this app
  /// `stressScore` already follows that convention (higher = more restored).
  ///
  /// Pass `null` for any signal that has no data — it's then ignored by the
  /// classifier. [now] determines the late-night override.
  static SkyMood fromScores({
    required DateTime now,
    int? sleepScore,
    int? activityScore,
    int? stressScore,
    bool isRestDay = false,
  }) {
    // Late night check-in always wins (after 10 PM until 5 AM).
    if (now.hour >= 22 || now.hour < 5) return SkyMood.starryNight;

    final activityHas = activityScore != null;
    final sleepHas = sleepScore != null && sleepScore > 0;
    final stressHas = stressScore != null && stressScore > 0;

    // Aurora — every available signal needs to be peak.
    final allTracked = sleepHas && activityHas && stressHas;
    if (allTracked &&
        sleepScore >= 85 &&
        activityScore >= 85 &&
        stressScore >= 80) {
      return SkyMood.aurora;
    }

    // High stress — low stress score (= more strain).
    if (stressHas && stressScore < 40) return SkyMood.stormy;

    // Good activity but poor sleep — twilight.
    if (activityHas && sleepHas && activityScore >= 70 && sleepScore < 50) {
      return SkyMood.warmTwilight;
    }

    // Low / sedentary day.
    if (activityHas && !isRestDay && activityScore < 30) {
      return SkyMood.overcast;
    }

    // Bright sky — solid all-around scores.
    if (sleepHas && activityHas &&
        sleepScore >= 70 && activityScore >= 70 &&
        (!stressHas || stressScore >= 60)) {
      return SkyMood.brightSky;
    }

    return SkyMood.pastelSunrise;
  }
}

/// Photographic sky background fetched from Unsplash's CDN. Each mood maps to
/// a real photo URL (no generated/illustrated art per the spec). A soft warm
/// gold tint is layered on top so the sky stays consistent with the app's
/// yellow theme without hiding the photo. A fallback gradient renders while
/// the image is downloading or if the network fails.
class SkyBackground extends StatelessWidget {
  final SkyMood mood;

  /// How long the new sky image takes to fade in over the previous one.
  final Duration crossfade;

  const SkyBackground({
    super.key,
    required this.mood,
    this.crossfade = const Duration(milliseconds: 700),
  });

  // Photo IDs are stable Unsplash CDN slugs — `images.unsplash.com/photo-{id}`
  // resolves to the original asset and is safe to embed without an API key.
  // Each mood lists multiple candidates so we can rotate between visits if we
  // ever want to; for now we just use the first.
  //
  // If a URL ever 404s, swap it for another sky photo of the same mood — the
  // [_FallbackSky] gradient ensures the screen stays usable in the meantime.
  static const Map<SkyMood, List<String>> _photoUrls = {
    SkyMood.brightSky: [
      // Blue sky with soft clouds — Andrew Welch, very widely embedded.
      'https://images.unsplash.com/photo-1419242902214-272b3f66ee7a?w=1200&q=80&fit=crop',
    ],
    SkyMood.warmTwilight: [
      // Pink + orange dusk horizon.
      'https://images.unsplash.com/photo-1495923898894-7cbcb4eef005?w=1200&q=80&fit=crop',
    ],
    SkyMood.stormy: [
      // Dark heavy storm clouds.
      'https://images.unsplash.com/photo-1605727216801-e27ce1d0cc28?w=1200&q=80&fit=crop',
    ],
    SkyMood.overcast: [
      // Flat grey overcast sky.
      'https://images.unsplash.com/photo-1428592953211-077101b2021b?w=1200&q=80&fit=crop',
    ],
    SkyMood.starryNight: [
      // Milky-way starfield with crescent moon.
      'https://images.unsplash.com/photo-1532978879514-6cf3e0bd7717?w=1200&q=80&fit=crop',
    ],
    SkyMood.aurora: [
      // Aurora borealis ribbons over a galaxy backdrop.
      'https://images.unsplash.com/photo-1483347756197-71ef80e95f73?w=1200&q=80&fit=crop',
    ],
    SkyMood.pastelSunrise: [
      // Soft pastel sunrise — pink fading to peach.
      'https://images.unsplash.com/photo-1495567720989-cebdbdd97913?w=1200&q=80&fit=crop',
    ],
  };

  String get _url => _photoUrls[mood]!.first;

  /// Warm gold tint layered on top of every sky photo. Low alpha so the photo
  /// stays the dominant visual layer.
  static const _tintGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0x33FBBF24), // amber-400 @ 20%
      Color(0x1AFEF3C7), // amber-100 @ 10%
    ],
  );

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Photo layer — keyed by mood so AnimatedSwitcher crossfades between
        // moods without flicker.
        AnimatedSwitcher(
          duration: crossfade,
          switchInCurve: Curves.easeInOut,
          switchOutCurve: Curves.easeInOut,
          child: Image.network(
            _url,
            key: ValueKey(_url),
            fit: BoxFit.cover,
            // Filter quality 'medium' is more than enough for a background
            // image; 'high' costs noticeably more on iOS.
            filterQuality: FilterQuality.medium,
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return _FallbackSky(mood: mood);
            },
            errorBuilder: (context, error, stack) => _FallbackSky(mood: mood),
            // Width and height help the engine pick the right cache bucket.
            width: double.infinity,
            height: double.infinity,
          ),
        ),
        // Warm gold tint overlay — keeps the screen on-brand without hiding
        // the photo.
        const DecoratedBox(
          decoration: BoxDecoration(gradient: _tintGradient),
          child: SizedBox.expand(),
        ),
      ],
    );
  }
}

/// Solid-colour gradient shown while the photo loads or if the network call
/// fails. Roughly matches the photo's dominant tone so the transition into
/// the real image isn't jarring.
class _FallbackSky extends StatelessWidget {
  final SkyMood mood;

  const _FallbackSky({required this.mood});

  Gradient _gradient() {
    switch (mood) {
      case SkyMood.brightSky:
        return const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF60A5FA), Color(0xFFE0F2FE)],
        );
      case SkyMood.warmTwilight:
        return const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF7C3AED), Color(0xFFEC4899), Color(0xFFFBBF24)],
        );
      case SkyMood.stormy:
        return const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF111827), Color(0xFF374151)],
        );
      case SkyMood.overcast:
        return const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF94A3B8), Color(0xFFE2E8F0)],
        );
      case SkyMood.starryNight:
        return const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF030712), Color(0xFF1E293B)],
        );
      case SkyMood.aurora:
        return const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF020617), Color(0xFF1E1B4B)],
        );
      case SkyMood.pastelSunrise:
        return const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFE4E6), Color(0xFFFEF3C7), Color(0xFFE0F2FE)],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(decoration: BoxDecoration(gradient: _gradient()));
  }
}
