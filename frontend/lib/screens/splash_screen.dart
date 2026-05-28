import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';
import 'home_screen.dart';

class SplashScreen extends StatefulWidget {
  final bool needsUpdate;
  final String updateUrl;
  
  const SplashScreen({super.key, required this.needsUpdate, required this.updateUrl});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late AnimationController _crescentController;
  late AnimationController _crossController;
  late AnimationController _titleController;

  late Animation<double> _crescentDraw;
  late Animation<double> _starScale;
  late Animation<double> _titleOpacity;
  
  late Animation<double> _crossAngle;
  late Animation<double> _crossTranslateX;
  late Animation<double> _crossTranslateY;
  late Animation<double> _crossOpacity;

  @override
  void initState() {
    super.initState();

    _crescentController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
    _crossController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000));
    _titleController = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));

    _crescentDraw = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _crescentController, curve: Curves.easeOut),
    );

    _starScale = TweenSequence([
      TweenSequenceItem(tween: Tween<double>(begin: 0, end: 1.3), weight: 60),
      TweenSequenceItem(tween: Tween<double>(begin: 1.3, end: 1.0), weight: 40),
    ]).animate(CurvedAnimation(parent: _crescentController, curve: Curves.easeOut));

    _titleOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _titleController, curve: Curves.easeIn),
    );

    _crossAngle = Tween<double>(begin: 0, end: pi / 4.5).animate(
      CurvedAnimation(parent: _crossController, curve: Curves.easeInOut),
    );

    // Moves them towards the center when crossing
    _crossTranslateX = Tween<double>(begin: 0, end: 25).animate(
      CurvedAnimation(parent: _crossController, curve: Curves.easeInOut),
    );
    
    // Moves them slightly down when crossing to align the X beautifully
    _crossTranslateY = Tween<double>(begin: 0, end: 15).animate(
      CurvedAnimation(parent: _crossController, curve: Curves.easeInOut),
    );

    // Controls the fade-in and fade-out of the sword and pen
    _crossOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _crossController, curve: Curves.easeInOut),
    );

    _startSequence();
  }

  Future<void> _startSequence() async {
    // 1. Draw crescent & star
    await _crescentController.forward();
    // 2. Sword & Pen cross
    await _crossController.forward();
    // 3. Title fades in
    _titleController.forward();

    // 4. Simulate loading resources (Waiting period while crossed)
    await Future.wait([
      Future.delayed(const Duration(milliseconds: 800)),
      _fakeAppInit(),
    ]);

    // 5. App resources loaded: Return sword & pen to parallel position, then navigate
    await _crossController.reverse();
    if (mounted) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 400),
          pageBuilder: (_, __, ___) => HomeScreen(needsUpdate: widget.needsUpdate, updateUrl: widget.updateUrl),
          transitionsBuilder: (_, animation, __, child) => FadeTransition(opacity: animation, child: child),
        ),
      );
    }
  }

  Future<void> _fakeAppInit() async {
    await Future.delayed(const Duration(milliseconds: 500));
  }

  @override
  void dispose() {
    _crescentController.dispose();
    _crossController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF8B0000), // Dark Red base
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            colors: [Color(0xFFD32F2F), Color(0xFF8B0000)], // Bright Red center to Dark Red edges
            radius: 1.0,
            center: Alignment.center,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // --- Crescent & Star ---
              AnimatedBuilder(
                animation: _crescentController,
                builder: (context, child) {
                  return SizedBox(
                    width: 140,
                    height: 140,
                    child: CustomPaint(
                      painter: _CrescentStarPainter(
                        drawProgress: _crescentDraw.value,
                        starScale: _starScale.value,
                        color: Colors.white, // White Crescent & Star
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 28),

              // --- Sword & Pen Crossing ---
              AnimatedBuilder(
                animation: _crossController,
                builder: (context, child) {
                  return Opacity(
                    opacity: _crossOpacity.value,
                    child: SizedBox(
                      height: 160,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Pen (on the left)
                          Transform.translate(
                            offset: Offset(-25 + _crossTranslateX.value, _crossTranslateY.value),
                            child: Transform.rotate(
                              angle: (pi / 2) + _crossAngle.value,
                              child: _buildPen(),
                            ),
                          ),
                          // Sword (on the right)
                          Transform.translate(
                            offset: Offset(25 - _crossTranslateX.value, _crossTranslateY.value),
                            child: Transform.rotate(
                              angle: (pi / 2) - _crossAngle.value,
                              child: _buildSword(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 40),

              // --- App Title ---
              FadeTransition(
                opacity: _titleOpacity,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: const [
                      Text(
                        'ميثاق الدية العشائرية',
                        textDirection: TextDirection.rtl,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          fontFamily: 'Amiri',
                          shadows: [Shadow(offset: Offset(1, 1), blurRadius: 4, color: Colors.black54)],
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'لعشائر البو حمدان',
                        textDirection: TextDirection.rtl,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          fontFamily: 'Amiri',
                          shadows: [Shadow(offset: Offset(1, 1), blurRadius: 4, color: Colors.black54)],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FadeTransition(
                opacity: _titleOpacity,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                  decoration: const BoxDecoration(
                    border: Border(
                      top: BorderSide(color: Color(0xFFD4AF37), width: 1.5), // Gold Border
                      bottom: BorderSide(color: Color(0xFFD4AF37), width: 1.5),
                    ),
                  ),
                  child: const Text(
                    'أصالة، عدالة، وتسامح',
                    textDirection: TextDirection.rtl,
                    style: TextStyle(
                      fontSize: 18,
                      color: Color(0xFFD4AF37), // Gold Text
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSword() {
    return SizedBox(
      width: 140, // Length
      height: 40, // Height bound
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Blade (Pointy at the left end)
          CustomPaint(
            size: const Size(90, 12),
            painter: _BladePainter(),
          ),
          // Hilt Guard
          Container(
            width: 8,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFD4AF37), // Gold
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.black, width: 1.5),
            ),
          ),
          // Handle
          Container(
            width: 25,
            height: 10,
            decoration: const BoxDecoration(
              color: Colors.black, // Black Handle on Red Background
              border: Border(
                top: BorderSide(color: Colors.black, width: 1.5),
                bottom: BorderSide(color: Colors.black, width: 1.5),
              ),
            ),
          ),
          // Pommel
          Container(
            width: 12,
            height: 16,
            decoration: BoxDecoration(
              color: const Color(0xFFD4AF37), // Gold
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.black, width: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPen() {
    return SizedBox(
      width: 140, // Same total length
      height: 20,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // Nib
          CustomPaint(
            size: const Size(25, 12),
            painter: _NibPainter(),
          ),
          // Gold band
          Container(
            width: 6,
            height: 14,
            decoration: BoxDecoration(
              color: const Color(0xFFD4AF37), // Gold
              border: Border.all(color: Colors.black, width: 1.5),
            ),
          ),
          // Body
          Container(
            width: 85,
            height: 16,
            decoration: const BoxDecoration(
              color: Colors.black, // Black Body
              border: Border(
                top: BorderSide(color: Colors.black, width: 1.5),
                bottom: BorderSide(color: Colors.black, width: 1.5),
              ),
            ),
          ),
          // End Cap
          Container(
            width: 14,
            height: 16,
            decoration: BoxDecoration(
              color: Colors.black, // Black End Cap
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(8),
                bottomRight: Radius.circular(8),
              ),
              border: Border.all(color: Colors.black, width: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _BladePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFF5F5F5) // White/Silver blade
      ..style = PaintingStyle.fill;
      
    final borderPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final path = Path();
    path.moveTo(0, size.height / 2); // Sharp tip
    path.lineTo(20, 0); // Slope up
    path.lineTo(size.width, 0); // Flat top
    path.lineTo(size.width, size.height); // Flat bottom
    path.lineTo(20, size.height); // Slope down
    path.close();

    canvas.drawPath(path, paint);
    
    // Middle line for the sword
    canvas.drawLine(Offset(10, size.height / 2), Offset(size.width, size.height / 2), borderPaint);
    
    canvas.drawPath(path, borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _NibPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFD4AF37) // Gold nib
      ..style = PaintingStyle.fill;
      
    final borderPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final path = Path();
    path.moveTo(0, size.height / 2); // Sharp writing tip
    path.lineTo(size.width, 0); // Top back
    path.lineTo(size.width, size.height); // Bottom back
    path.close();

    canvas.drawPath(path, paint);
    
    // Draw the slit in the nib
    canvas.drawLine(Offset(4, size.height / 2), Offset(size.width - 5, size.height / 2), borderPaint);
    
    // Draw the breather hole
    canvas.drawCircle(Offset(size.width - 6, size.height / 2), 1.5, Paint()..color = Colors.black);

    canvas.drawPath(path, borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// رسم الهلال والنجمة يدوياً
class _CrescentStarPainter extends CustomPainter {
  final double drawProgress;
  final double starScale;
  final Color color;

  _CrescentStarPainter({required this.drawProgress, required this.starScale, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.38;

    canvas.save();
    
    // 1. Clip drawing progress (sweep angle)
    if (drawProgress < 1.0) {
      final sweepAngle = 2 * pi * drawProgress;
      // Make the clip rect slightly larger to prevent edge artifacts
      final arcRect = Rect.fromCircle(center: center, radius: radius * 1.2);
      final clipPath = Path()
        ..moveTo(center.dx, center.dy)
        ..arcTo(arcRect, -pi / 2, sweepAngle, false)
        ..close();
      canvas.clipPath(clipPath);
    }

    // 2. Draw true transparent crescent using Path.combine
    final outerCircle = Path()..addOval(Rect.fromCircle(center: center, radius: radius));
    final innerCircle = Path()..addOval(Rect.fromCircle(center: center + const Offset(-18, -10), radius: radius * 0.82));
    
    // The difference between outer and inner creates a true crescent path
    final crescentPath = Path.combine(PathOperation.difference, outerCircle, innerCircle);
    canvas.drawPath(crescentPath, paint);

    canvas.restore();

    if (starScale > 0.05) {
      // Placing the star in the center of the crescent's inner curve
      final starCenter = center + const Offset(-12, -10);
      _drawStar(canvas, starCenter, 14 * starScale, 6 * starScale, paint);
    }
  }

  void _drawStar(Canvas canvas, Offset center, double outerR, double innerR, Paint paint) {
    final path = Path();
    const points = 5;
    for (int i = 0; i < points * 2; i++) {
      final r = (i % 2 == 0) ? outerR : innerR;
      final angle = (i * pi) / points - pi / 2;
      final x = center.dx + r * cos(angle);
      final y = center.dy + r * sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CrescentStarPainter old) =>
      old.drawProgress != drawProgress || old.starScale != starScale || old.color != color;
}
