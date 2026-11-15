import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import '../database/app_database.dart';
import '../main.dart';
import '../services/language_settings_service.dart';
import '../services/word_list_sync_service.dart';
import 'language_selection_screen.dart';

typedef SplashScreen = AnimatedSplashScreen;

class AnimatedSplashScreen extends StatefulWidget {
  const AnimatedSplashScreen({super.key});

  @override
  State<AnimatedSplashScreen> createState() => _AnimatedSplashScreenState();
}

class _AnimatedSplashScreenState extends State<AnimatedSplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _mainController;

  // Phase 1: Piggy Bank Entrance Scale (0ms -> 800ms: 0.00 -> 0.40)
  late final Animation<double> _entranceScale;

  // Phase 2: Rupee Coin Drop (800ms -> 1200ms: 0.40 -> 0.60)
  late final Animation<double> _coinDropY;

  // Phase 3: Piggy Bank Impact Bounce (1200ms -> 1450ms: 0.60 -> 0.725)
  late final Animation<double> _impactBounce;

  // Phase 3: Financial Graph & Bar Chart Reveal (1200ms -> 1550ms: 0.60 -> 0.78)
  late final Animation<double> _graphProgress;

  // Phase 3: Sparkle Star (1350ms -> 1700ms: 0.68 -> 0.85)
  late final Animation<double> _sparkleProgress;

  // Text Entrance (Fade & Slide)
  late final Animation<double> _textFade;
  late final Animation<Offset> _textSlide;

  Timer? _splashTimer;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    debugPrint('[SPLASH] Explicit Animated Piggy Bank & Coin Drop started');

    // Total animation cycle ~2000ms
    _mainController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

    // Phase 1: Piggy Bank scales up from 0.0 to 1.0 with elastic bouncy curve over ~800ms
    _entranceScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.00, 0.40, curve: Curves.elasticOut),
      ),
    );

    // Phase 2: Rupee Coin drops straight down from above piggy bank into slot over ~400ms
    // Starts at top = 0.0 (above slot at 86.0), falls down to 86.0
    _coinDropY = Tween<double>(begin: 0.0, end: 86.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.40, 0.60, curve: Curves.easeIn),
      ),
    );

    // Phase 3: Exact moment coin lands inside, Piggy Bank bounces (1.0 -> 1.06 -> 0.98 -> 1.0)
    _impactBounce = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.06).chain(CurveTween(curve: Curves.easeOutQuad)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.06, end: 0.98).chain(CurveTween(curve: Curves.easeInOutQuad)),
        weight: 35,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 0.98, end: 1.0).chain(CurveTween(curve: Curves.easeOutQuad)),
        weight: 25,
      ),
    ]).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.60, 0.725),
      ),
    );

    // Phase 3: Financial growth graph & bar chart appear simultaneously on coin impact
    _graphProgress = CurvedAnimation(
      parent: _mainController,
      curve: const Interval(0.60, 0.78, curve: Curves.easeOutBack),
    );

    // Sparkle star near arrow tip
    _sparkleProgress = CurvedAnimation(
      parent: _mainController,
      curve: const Interval(0.68, 0.85, curve: Curves.elasticOut),
    );

    // Title and Tagline entrance
    _textFade = CurvedAnimation(
      parent: _mainController,
      curve: const Interval(0.40, 0.70, curve: Curves.easeOut),
    );
    _textSlide = Tween<Offset>(
      begin: const Offset(0, 0.25),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.40, 0.70, curve: Curves.easeOutCubic),
      ),
    );

    _startApp();
  }

  double get _currentPiggyScale {
    final t = _mainController.value;
    if (t < 0.40) {
      return _entranceScale.value;
    } else if (t < 0.60) {
      return 1.0;
    } else if (t < 0.725) {
      return _impactBounce.value;
    } else {
      return 1.0;
    }
  }

  void _startApp() async {
    _mainController.forward();

    final stopwatch = Stopwatch()..start();
    bool needsLanguageSetup = false;

    // Load background resources
    try {
      debugPrint('[SPLASH] Loading local DB...');
      await AppDatabase.instance.database;

      debugPrint('[SPLASH] Initializing Firebase...');
      await Firebase.initializeApp();

      debugPrint('[SPLASH] Checking wordlist sync...');
      await WordListSyncService.instance.syncOnStartup();

      // Check if language onboarding is needed
      needsLanguageSetup = await LanguageSettingsService.instance.shouldShowLanguageSetup();
    } catch (e) {
      debugPrint('[SPLASH] Init note: $e');
    }

    // Animation takes 2000ms + hold = 2500ms minimum
    final elapsed = stopwatch.elapsedMilliseconds;
    const minSplashDuration = 2500;
    final remaining = minSplashDuration - elapsed;
    if (remaining > 0) {
      _splashTimer = Timer(Duration(milliseconds: remaining), () {
        if (mounted) _proceed(needsLanguageSetup);
      });
    } else {
      _proceed(needsLanguageSetup);
    }
  }

  void _proceed(bool needsLanguageSetup) {
    if (_navigated || !mounted) return;
    _navigated = true;

    final Widget targetScreen = needsLanguageSetup
        ? const LanguageSelectionScreen()
        : const MainNavigationShell();

    debugPrint('[SPLASH] Complete. Navigating to ${needsLanguageSetup ? "LanguageSelection" : "Home"}');

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => targetScreen,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  @override
  void dispose() {
    _splashTimer?.cancel();
    _mainController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const vibrantRed = Color(0xFFE5212E);

    return Scaffold(
      backgroundColor: vibrantRed,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background ambient soft light accents
          Positioned(
            top: -100,
            right: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.06),
              ),
            ),
          ),
          Positioned(
            bottom: -100,
            left: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withOpacity(0.12),
              ),
            ),
          ),

          // Center Logo Assembly
          Center(
            child: AnimatedBuilder(
              animation: _mainController,
              builder: (context, child) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Stage for Piggy Bank and Rupee Coin Drop
                    SizedBox(
                      width: 250,
                      height: 250,
                      child: Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.center,
                        children: [
                          // 1. Piggy Bank Silhouette Card (scales in Phase 1, bounces on impact in Phase 3)
                          Transform.scale(
                            scale: _currentPiggyScale,
                            child: Container(
                              width: 250,
                              height: 250,
                              decoration: BoxDecoration(
                                color: vibrantRed,
                                borderRadius: BorderRadius.circular(56),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.30),
                                    blurRadius: 40,
                                    offset: const Offset(0, 18),
                                    spreadRadius: 2,
                                  ),
                                  BoxShadow(
                                    color: Colors.white.withOpacity(0.14),
                                    blurRadius: 10,
                                    offset: const Offset(-2, -3),
                                  ),
                                ],
                              ),
                              child: CustomPaint(
                                size: const Size(250, 250),
                                painter: PiggyBankPainter(
                                  graphProgress: _graphProgress.value,
                                  sparkleProgress: _sparkleProgress.value,
                                  redThemeColor: vibrantRed,
                                ),
                              ),
                            ),
                          ),

                          // 2. Rupee Coin Drop (drops from above into slot during Phase 2)
                          // Strictly invisible/off-screen during Phase 1 (t < 0.40)
                          if (_mainController.value >= 0.40 && _coinDropY.value < 86.0)
                            Positioned(
                              top: _coinDropY.value,
                              left: 99.0, // Centered horizontally: (250 - 52) / 2 = 99.0
                              child: ClipRect(
                                clipper: CoinSlotClipper(
                                  slotY: 86.0,
                                  coinCurrentY: _coinDropY.value,
                                ),
                                child: _buildRupeeCoin(vibrantRed),
                              ),
                            ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 38),

                    // App Title & Tagline with Slide and Fade
                    SlideTransition(
                      position: _textSlide,
                      child: FadeTransition(
                        opacity: _textFade,
                        child: Column(
                          children: [
                            const Text(
                              'AI Money Manager',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Voice AI • Smart Finances',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                letterSpacing: 1.2,
                                color: Colors.white.withOpacity(0.85),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),

          // Bottom Loading Indicator
          Positioned(
            bottom: 48,
            left: 0,
            right: 0,
            child: Center(
              child: SizedBox(
                width: 36,
                height: 3,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    backgroundColor: Colors.white.withOpacity(0.20),
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// White circular container with red Rupee symbol inside
  Widget _buildRupeeCoin(Color redColor) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.28),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Center(
        child: Text(
          '₹',
          style: TextStyle(
            color: redColor,
            fontSize: 28,
            fontWeight: FontWeight.w900,
            height: 1.1,
          ),
        ),
      ),
    );
  }
}

/// Custom clipper that lets the Rupee coin visually disappear "inside" the slot as it slides down
class CoinSlotClipper extends CustomClipper<Rect> {
  final double slotY;
  final double coinCurrentY;

  const CoinSlotClipper({
    required this.slotY,
    required this.coinCurrentY,
  });

  @override
  Rect getClip(Size size) {
    final localSlotY = slotY - coinCurrentY;
    if (localSlotY <= 0) {
      return Rect.zero;
    }
    // Retain shadow margin on left, top, right, strictly clip at localSlotY bottom
    return Rect.fromLTRB(-14, -14, size.width + 14, localSlotY);
  }

  @override
  bool shouldReclip(CoinSlotClipper oldClipper) {
    return oldClipper.slotY != slotY || oldClipper.coinCurrentY != coinCurrentY;
  }
}

/// Custom painter for Piggy Bank silhouette, internal bar chart,
/// upward growth arrow line, arrowhead, and sparkle star.
class PiggyBankPainter extends CustomPainter {
  final double graphProgress;
  final double sparkleProgress;
  final Color redThemeColor;

  const PiggyBankPainter({
    required this.graphProgress,
    required this.sparkleProgress,
    this.redThemeColor = const Color(0xFFE5212E),
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double cx = size.width / 2; // 125.0
    final double cy = size.height / 2 + 13; // 138.0

    // 1. Piggy Bank Body Components
    final bodyRect = Rect.fromCenter(center: Offset(cx, cy), width: 122, height: 104);
    final bodyPath = Path()..addOval(bodyRect);

    // Snout protruding on the left
    final snoutRRect = RRect.fromRectAndCorners(
      Rect.fromLTRB(cx - 81, cy - 14, cx - 49, cy + 16),
      topLeft: const Radius.circular(9),
      bottomLeft: const Radius.circular(9),
    );
    final snoutPath = Path()..addRRect(snoutRRect);

    // Ear on top-left
    final earPath = Path()
      ..moveTo(cx - 43, cy - 44)
      ..lineTo(cx - 57, cy - 74)
      ..quadraticBezierTo(cx - 53, cy - 82, cx - 43, cy - 78)
      ..lineTo(cx - 21, cy - 52)
      ..close();

    // Front Leg
    final frontLegRRect = RRect.fromRectAndCorners(
      Rect.fromLTRB(cx - 43, cy + 42, cx - 19, cy + 68),
      bottomLeft: const Radius.circular(8),
      bottomRight: const Radius.circular(8),
    );
    final frontLegPath = Path()..addRRect(frontLegRRect);

    // Back Leg
    final backLegRRect = RRect.fromRectAndCorners(
      Rect.fromLTRB(cx + 15, cy + 42, cx + 39, cy + 68),
      bottomLeft: const Radius.circular(8),
      bottomRight: const Radius.circular(8),
    );
    final backLegPath = Path()..addRRect(backLegRRect);

    // Slot Cutout at top
    final slotRRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, cy - 52), width: 34, height: 4),
      const Radius.circular(2),
    );
    final slotPath = Path()..addRRect(slotRRect);

    // Combine into unified Piggy Bank silhouette
    Path pig = Path.combine(PathOperation.union, bodyPath, snoutPath);
    pig = Path.combine(PathOperation.union, pig, earPath);
    pig = Path.combine(PathOperation.union, pig, frontLegPath);
    pig = Path.combine(PathOperation.union, pig, backLegPath);
    pig = Path.combine(PathOperation.difference, pig, slotPath);

    // Draw Piggy Bank with soft shadow
    canvas.drawShadow(pig, Colors.black.withOpacity(0.24), 12, true);
    final pigPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawPath(pig, pigPaint);

    // 2. Piggy Eye (Red circle cutout)
    final eyePaint = Paint()
      ..color = redThemeColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx - 53, cy - 16), 5.5, eyePaint);

    // 3. Bar Chart (3 vertical red bars inside pig)
    if (graphProgress > 0.0) {
      final barPaint = Paint()
        ..color = redThemeColor
        ..style = PaintingStyle.fill;

      const double barBaseY = 174.0;
      // Staggered heights
      final double p1 = ((graphProgress - 0.0) / 0.6).clamp(0.0, 1.0);
      final double p2 = ((graphProgress - 0.15) / 0.6).clamp(0.0, 1.0);
      final double p3 = ((graphProgress - 0.3) / 0.6).clamp(0.0, 1.0);

      final double h1 = 16.0 * Curves.easeOutBack.transform(p1);
      final double h2 = 28.0 * Curves.easeOutBack.transform(p2);
      final double h3 = 40.0 * Curves.easeOutBack.transform(p3);

      if (h1 > 0) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(cx - 23, barBaseY - h1, 11, h1),
            const Radius.circular(3),
          ),
          barPaint,
        );
      }
      if (h2 > 0) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(cx - 6, barBaseY - h2, 11, h2),
            const Radius.circular(3),
          ),
          barPaint,
        );
      }
      if (h3 > 0) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(cx + 11, barBaseY - h3, 11, h3),
            const Radius.circular(3),
          ),
          barPaint,
        );
      }

      // 4. Zigzag Graph Line (inside pig)
      final lineProgress = ((graphProgress - 0.1) / 0.8).clamp(0.0, 1.0);
      if (lineProgress > 0) {
        final linePaint = Paint()
          ..color = redThemeColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7.0
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;

        final pStart = Offset(cx - 49, cy + 20);
        final pPeak = Offset(cx - 13, cy - 18);
        final pDip = Offset(cx + 5, cy - 2);
        final pExit = Offset(cx + 43, cy - 40);
        final pTip = Offset(cx + 53, cy - 50);

        // Draw segmented line up to lineProgress
        final linePath = Path()..moveTo(pStart.dx, pStart.dy);
        if (lineProgress <= 0.3) {
          final t = lineProgress / 0.3;
          linePath.lineTo(
            Offset.lerp(pStart, pPeak, t)!.dx,
            Offset.lerp(pStart, pPeak, t)!.dy,
          );
        } else if (lineProgress <= 0.5) {
          linePath.lineTo(pPeak.dx, pPeak.dy);
          final t = (lineProgress - 0.3) / 0.2;
          linePath.lineTo(
            Offset.lerp(pPeak, pDip, t)!.dx,
            Offset.lerp(pPeak, pDip, t)!.dy,
          );
        } else if (lineProgress <= 0.8) {
          linePath.lineTo(pPeak.dx, pPeak.dy);
          linePath.lineTo(pDip.dx, pDip.dy);
          final t = (lineProgress - 0.5) / 0.3;
          linePath.lineTo(
            Offset.lerp(pDip, pExit, t)!.dx,
            Offset.lerp(pDip, pExit, t)!.dy,
          );
        } else {
          linePath.lineTo(pPeak.dx, pPeak.dy);
          linePath.lineTo(pDip.dx, pDip.dy);
          linePath.lineTo(pExit.dx, pExit.dy);
          final t = (lineProgress - 0.8) / 0.2;
          linePath.lineTo(
            Offset.lerp(pExit, pTip, t)!.dx,
            Offset.lerp(pExit, pTip, t)!.dy,
          );
        }
        canvas.drawPath(linePath, linePaint);

        // 5. White Arrowhead at pTip (pointing up-right)
        if (lineProgress >= 0.8) {
          final arrowT = ((lineProgress - 0.8) / 0.2).clamp(0.0, 1.0);
          final arrowScale = Curves.elasticOut.transform(arrowT);

          canvas.save();
          canvas.translate(pTip.dx, pTip.dy);
          canvas.scale(arrowScale);

          final arrowPath = Path()
            ..moveTo(12, -12) // Arrow tip pointing up-right
            ..lineTo(-8, -10) // Wing 1
            ..lineTo(-2, 0)   // Notch
            ..lineTo(10, 6)   // Wing 2
            ..close();

          canvas.drawShadow(arrowPath, Colors.black.withOpacity(0.25), 6, true);
          canvas.drawPath(
            arrowPath,
            Paint()
              ..color = Colors.white
              ..style = PaintingStyle.fill,
          );
          canvas.restore();
        }
      }
    }

    // 6. Sparkle Star (4-point star in top-right)
    if (sparkleProgress > 0.0) {
      final double starScale = Curves.elasticOut.transform(sparkleProgress.clamp(0.0, 1.0));
      final double sx = cx + 57;
      final double sy = cy - 78;
      final double r = 11.0 * starScale;

      final starPath = Path()
        ..moveTo(sx, sy - r)
        ..quadraticBezierTo(sx, sy, sx + r, sy)
        ..quadraticBezierTo(sx, sy, sx, sy + r)
        ..quadraticBezierTo(sx, sy, sx - r, sy)
        ..quadraticBezierTo(sx, sy, sx, sy - r)
        ..close();

      canvas.drawShadow(starPath, Colors.black.withOpacity(0.25), 5, true);
      canvas.drawPath(
        starPath,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.fill,
      );
    }
  }

  @override
  bool shouldRepaint(PiggyBankPainter oldDelegate) {
    return oldDelegate.graphProgress != graphProgress ||
        oldDelegate.sparkleProgress != sparkleProgress ||
        oldDelegate.redThemeColor != redThemeColor;
  }
}
