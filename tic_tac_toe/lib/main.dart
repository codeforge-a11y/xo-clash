import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'dart:convert';
import 'dart:math';
import 'dart:async';

void main() => runApp(const MyApp());

// ════════════════════════════════════════════════════════════════
// APP COLORS
// ════════════════════════════════════════════════════════════════
class AppColors {
  static const Color bg1 = Color(0xFF0D0D1A);
  static const Color bg2 = Color(0xFF121228);
  static const Color bg3 = Color(0xFF1A1A3A);
  static const Color surface = Color(0xFF1E1E38);
  static const Color surfaceLight = Color(0xFF252545);
  static const Color accentBlue = Color(0xFF4DAFFF);
  static const Color accentGold = Color(0xFFFFD166);
  static const Color xColor = Color(0xFFFF4D6D);
  static const Color oColor = Color(0xFF4DAFFF);
  static const Color easy = Color(0xFF06D6A0);
  static const Color medium = Color(0xFFFFD166);
  static const Color hard = Color(0xFFFF4D6D);
}

// ════════════════════════════════════════════════════════════════
// SYMBOL THEME
// ════════════════════════════════════════════════════════════════
class SymbolTheme {
  final String name;
  final String xSymbol;
  final String oSymbol;
  final Color xColor;
  final Color oColor;
  final IconData icon;

  const SymbolTheme({
    required this.name,
    required this.xSymbol,
    required this.oSymbol,
    required this.xColor,
    required this.oColor,
    required this.icon,
  });
}

const List<SymbolTheme> kThemes = [
  SymbolTheme(
    name: 'Classic',
    xSymbol: 'X',
    oSymbol: 'O',
    xColor: Color(0xFFFF4D6D),
    oColor: Color(0xFF4DAFFF),
    icon: Icons.grid_3x3_rounded,
  ),
  SymbolTheme(
    name: 'Fire & Ice',
    xSymbol: '🔥',
    oSymbol: '❄️',
    xColor: Color(0xFFFF6B35),
    oColor: Color(0xFF74C7EC),
    icon: Icons.whatshot_rounded,
  ),
  SymbolTheme(
    name: 'Star & Moon',
    xSymbol: '⭐',
    oSymbol: '🌙',
    xColor: Color(0xFFFFD166),
    oColor: Color(0xFFB388FF),
    icon: Icons.star_rounded,
  ),
  SymbolTheme(
    name: 'Heart & Diamond',
    xSymbol: '❤️',
    oSymbol: '💎',
    xColor: Color(0xFFFF4D6D),
    oColor: Color(0xFF4DAFFF),
    icon: Icons.favorite_rounded,
  ),
  SymbolTheme(
    name: 'Cat & Dog',
    xSymbol: '🐱',
    oSymbol: '🐶',
    xColor: Color(0xFFFF9A9E),
    oColor: Color(0xFF96CEB4),
    icon: Icons.pets_rounded,
  ),
  SymbolTheme(
    name: 'Sword & Shield',
    xSymbol: '⚔️',
    oSymbol: '🛡️',
    xColor: Color(0xFFE8C547),
    oColor: Color(0xFF7EC8E3),
    icon: Icons.security_rounded,
  ),
];

// ════════════════════════════════════════════════════════════════
// DIFFICULTY
// ════════════════════════════════════════════════════════════════
enum Difficulty { easy, medium, hard }

extension DifficultyExt on Difficulty {
  String get label {
    switch (this) {
      case Difficulty.easy:
        return 'Easy';
      case Difficulty.medium:
        return 'Medium';
      case Difficulty.hard:
        return 'Hard';
    }
  }

  Color get color {
    switch (this) {
      case Difficulty.easy:
        return AppColors.easy;
      case Difficulty.medium:
        return AppColors.medium;
      case Difficulty.hard:
        return AppColors.hard;
    }
  }

  IconData get icon {
    switch (this) {
      case Difficulty.easy:
        return Icons.sentiment_satisfied_alt_rounded;
      case Difficulty.medium:
        return Icons.sentiment_neutral_rounded;
      case Difficulty.hard:
        return Icons.whatshot_rounded;
    }
  }
}

// ════════════════════════════════════════════════════════════════
// MATCH LOG ENTRY
// ════════════════════════════════════════════════════════════════
class MatchEntry {
  final String result;
  final String winnerName;
  final int moves;
  final DateTime time;

  const MatchEntry({
    required this.result,
    required this.winnerName,
    required this.moves,
    required this.time,
  });
}

// ════════════════════════════════════════════════════════════════
// SOUND MANAGER
// ════════════════════════════════════════════════════════════════
class SoundManager {
  bool soundOn = true;
  final AudioPlayer _tapPlayer = AudioPlayer();
  final AudioPlayer _winPlayer = AudioPlayer();
  final AudioPlayer _drawPlayer = AudioPlayer();

  Future<void> playTap() async {
    if (!soundOn) return;
    HapticFeedback.lightImpact();
    await _tapPlayer.play(AssetSource('sounds/tap.mp3'));
  }

  Future<void> playWin() async {
    if (!soundOn) return;
    HapticFeedback.heavyImpact();
    await _winPlayer.play(AssetSource('sounds/win.mp3'));
  }

  Future<void> playDraw() async {
    if (!soundOn) return;
    HapticFeedback.mediumImpact();
    await _drawPlayer.play(AssetSource('sounds/draw.mp3'));
  }

  void dispose() {
    _tapPlayer.dispose();
    _winPlayer.dispose();
    _drawPlayer.dispose();
  }
}

// ════════════════════════════════════════════════════════════════
// MULTIPLAYER SESSION — simple data holder
// ════════════════════════════════════════════════════════════════
class MultiplayerSession {
  final String code;
  final String hostName;
  String? guestName;
  bool isHost;

  MultiplayerSession({
    required this.code,
    required this.hostName,
    this.guestName,
    this.isHost = true,
  });
}

// ════════════════════════════════════════════════════════════════
// MULTIPLAYER SERVER — WebSocket client
// !! ONLY THIS CLASS CHANGED — replace your-app with real URL !!
// ════════════════════════════════════════════════════════════════
class MultiplayerServer {
  // ▶▶ REPLACE with your actual Render URL after deploying server.js
  static const String _serverUrl = 'ws://192.168.31.1:3000';

  static WebSocketChannel? _channel;
  static final _controller = StreamController<Map<String, dynamic>>.broadcast();
  static bool _isConnecting = false;
  static Timer? _pingTimer;

  static Stream<Map<String, dynamic>> get stream => _controller.stream;

  // Connect to WebSocket server
  static Future<bool> connect() async {
    if (_isConnecting) return false;
    _isConnecting = true;

    try {
      _channel = WebSocketChannel.connect(Uri.parse(_serverUrl));

      _channel!.stream.listen(
        (message) {
          try {
            final data = jsonDecode(message as String);
            _controller.add(Map<String, dynamic>.from(data as Map));
          } catch (e) {
            print('Parse error: $e');
          }
        },
        onDone: () {
          print('WebSocket disconnected');
          _isConnecting = false;
          _stopPing();
        },
        onError: (e) {
          print('WebSocket error: $e');
          _isConnecting = false;
          _stopPing();
        },
        cancelOnError: false,
      );

      // Start ping every 25s to keep connection alive
      _startPing();
      _isConnecting = false;
      return true;
    } catch (e) {
      print('Connection failed: $e');
      _isConnecting = false;
      return false;
    }
  }

  // Send message to server
  static void send(Map<String, dynamic> data) {
    if (_channel != null) {
      try {
        _channel!.sink.add(jsonEncode(data));
      } catch (e) {
        print('Send error: $e');
      }
    }
  }

  // Create game — tells server to generate a code
  static void createGame(String playerName) {
    send({'type': 'create', 'playerName': playerName});
  }

  // Join game — sends code to server
  static void joinGame(String code, String playerName) {
    send({'type': 'join', 'code': code, 'playerName': playerName});
  }

  // Send a board move to opponent
  static void sendMove(int index) {
    send({'type': 'move', 'index': index});
  }

  // Request rematch
  static void requestRematch() {
    send({'type': 'rematch'});
  }

  // Keep-alive ping
  static void _startPing() {
    _pingTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      send({'type': 'ping'});
    });
  }

  static void _stopPing() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  // Disconnect cleanly
  static void disconnect() {
    _stopPing();
    _channel?.sink.close();
    _channel = null;
    _isConnecting = false;
  }
}

// ════════════════════════════════════════════════════════════════
// SNACKBAR HELPER
// ════════════════════════════════════════════════════════════════
void showAppSnackbar(
  BuildContext context,
  String message, {
  Color color = AppColors.accentBlue,
  IconData icon = Icons.info_outline_rounded,
  Duration duration = const Duration(seconds: 3),
}) {
  ScaffoldMessenger.of(context).clearSnackBars();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      duration: duration,
      content: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.4)),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.2),
              blurRadius: 12,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// ════════════════════════════════════════════════════════════════
// CONFIRMATION DIALOG HELPER
// ════════════════════════════════════════════════════════════════
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  required IconData icon,
  Color confirmColor = AppColors.xColor,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withOpacity(0.6),
    builder: (_) => Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
          boxShadow: [
            BoxShadow(
              color: confirmColor.withOpacity(0.15),
              blurRadius: 30,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: confirmColor.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: confirmColor, size: 28),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: const TextStyle(
                color: Color(0x88FFFFFF),
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context, false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(14),
                        border:
                            Border.all(color: Colors.white.withOpacity(0.08)),
                      ),
                      child: const Center(
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context, true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            confirmColor,
                            confirmColor.withOpacity(0.75)
                          ],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: confirmColor.withOpacity(0.35),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          confirmLabel,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  return result ?? false;
}

// ════════════════════════════════════════════════════════════════
// APP ROOT
// ════════════════════════════════════════════════════════════════
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Tic Tac Toe',
      theme: ThemeData(
        colorScheme: const ColorScheme.dark(),
      ),
      home: const SplashScreen(),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// SPLASH SCREEN
// ════════════════════════════════════════════════════════════════
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _logoCtrl;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoFade;

  late final AnimationController _tagCtrl;
  late final Animation<double> _tagSlide;
  late final Animation<double> _tagFade;

  late final AnimationController _gridCtrl;
  late final Animation<double> _gridAnim;

  late final AnimationController _xoCtrl;
  late final Animation<double> _xScale;
  late final Animation<double> _oScale;

  late final AnimationController _barCtrl;
  late final Animation<double> _barAnim;

  @override
  void initState() {
    super.initState();

    _logoCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    _logoScale = CurvedAnimation(parent: _logoCtrl, curve: Curves.elasticOut);
    _logoFade = CurvedAnimation(parent: _logoCtrl, curve: Curves.easeIn);

    _tagCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _tagSlide = Tween<double>(begin: 30, end: 0)
        .animate(CurvedAnimation(parent: _tagCtrl, curve: Curves.easeOut));
    _tagFade = CurvedAnimation(parent: _tagCtrl, curve: Curves.easeIn);

    _gridCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _gridAnim = CurvedAnimation(parent: _gridCtrl, curve: Curves.easeInOut);

    _xoCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    _xScale = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(
        parent: _xoCtrl,
        curve: const Interval(0.0, 0.55, curve: Curves.elasticOut)));
    _oScale = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(
        parent: _xoCtrl,
        curve: const Interval(0.45, 1.0, curve: Curves.elasticOut)));

    _barCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2200));
    _barAnim = CurvedAnimation(parent: _barCtrl, curve: Curves.easeInOut);

    _runSequence();
  }

  Future<void> _runSequence() async {
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    _logoCtrl.forward();

    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    _tagCtrl.forward();

    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    _gridCtrl.forward();

    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    _xoCtrl.forward();
    _barCtrl.forward();

    await Future.delayed(const Duration(milliseconds: 2400));
    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, a, __) => const NameEntryScreen(),
        transitionsBuilder: (_, a, __, child) =>
            FadeTransition(opacity: a, child: child),
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  @override
  void dispose() {
    _logoCtrl.dispose();
    _tagCtrl.dispose();
    _gridCtrl.dispose();
    _xoCtrl.dispose();
    _barCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sw = MediaQuery.of(context).size.width;
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.bg1, AppColors.bg2, AppColors.bg3],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              top: -sw * 0.3,
              right: -sw * 0.3,
              child: Container(
                width: sw * 0.8,
                height: sw * 0.8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.xColor.withOpacity(0.04),
                ),
              ),
            ),
            Positioned(
              bottom: -sw * 0.2,
              left: -sw * 0.2,
              child: Container(
                width: sw * 0.6,
                height: sw * 0.6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.accentBlue.withOpacity(0.04),
                ),
              ),
            ),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ScaleTransition(
                  scale: _logoScale,
                  child: FadeTransition(
                    opacity: _logoFade,
                    child: _buildLogoBox(),
                  ),
                ),
                const SizedBox(height: 28),
                FadeTransition(
                  opacity: _logoFade,
                  child: const Text(
                    'TIC TAC TOE',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 7,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                AnimatedBuilder(
                  animation: _tagCtrl,
                  builder: (_, __) => Transform.translate(
                    offset: Offset(0, _tagSlide.value),
                    child: FadeTransition(
                      opacity: _tagFade,
                      child: const Text(
                        'The classic game, reimagined',
                        style: TextStyle(
                          color: Color(0x80FFFFFF),
                          fontSize: 14,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 60),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 60),
                  child: Column(
                    children: [
                      AnimatedBuilder(
                        animation: _barAnim,
                        builder: (_, __) => ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: _barAnim.value,
                            backgroundColor: Colors.white.withOpacity(0.08),
                            valueColor: const AlwaysStoppedAnimation<Color>(
                                AppColors.xColor),
                            minHeight: 3,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      AnimatedBuilder(
                        animation: _barAnim,
                        builder: (_, __) => Text(
                          _barAnim.value < 0.4
                              ? 'Loading…'
                              : _barAnim.value < 0.75
                                  ? 'Preparing board…'
                                  : 'Almost ready…',
                          style: const TextStyle(
                            color: Color(0x55FFFFFF),
                            fontSize: 11,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogoBox() {
    return Container(
      width: 110,
      height: 110,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.xColor, AppColors.accentBlue],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: AppColors.xColor.withOpacity(0.5),
            blurRadius: 30,
            spreadRadius: 4,
          ),
          BoxShadow(
            color: AppColors.accentBlue.withOpacity(0.3),
            blurRadius: 20,
            spreadRadius: 2,
            offset: const Offset(8, 8),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _gridAnim,
            builder: (_, __) => CustomPaint(
              size: const Size(70, 70),
              painter: _GridLinePainter(progress: _gridAnim.value),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ScaleTransition(
                scale: _xScale,
                child: const Text(
                  'X',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 26,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              ScaleTransition(
                scale: _oScale,
                child: const Text(
                  'O',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 26,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GridLinePainter extends CustomPainter {
  final double progress;
  _GridLinePainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.25)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    final lines = [
      [Offset(size.width * 0.35, 0), Offset(size.width * 0.35, size.height)],
      [Offset(size.width * 0.65, 0), Offset(size.width * 0.65, size.height)],
      [Offset(0, size.height * 0.35), Offset(size.width, size.height * 0.35)],
      [Offset(0, size.height * 0.65), Offset(size.width, size.height * 0.65)],
    ];

    for (int i = 0; i < lines.length; i++) {
      final t = ((progress - i * 0.2) / 0.4).clamp(0.0, 1.0);
      if (t <= 0) continue;
      final s = lines[i][0];
      final e = lines[i][1];
      canvas.drawLine(
        s,
        Offset(s.dx + (e.dx - s.dx) * t, s.dy + (e.dy - s.dy) * t),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_GridLinePainter old) => old.progress != progress;
}

// ════════════════════════════════════════════════════════════════
// NAME ENTRY SCREEN
// ════════════════════════════════════════════════════════════════
class NameEntryScreen extends StatefulWidget {
  const NameEntryScreen({super.key});

  @override
  State<NameEntryScreen> createState() => _NameEntryScreenState();
}

class _NameEntryScreenState extends State<NameEntryScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _p1Controller =
      TextEditingController(text: 'Player 1');
  final TextEditingController _p2Controller =
      TextEditingController(text: 'Player 2');

  String _mode = 'pvp';
  Difficulty _difficulty = Difficulty.medium;
  int _themeIndex = 0;

  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _p1Controller.dispose();
    _p2Controller.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  void _startGame() {
    final String p1 = _p1Controller.text.trim().isEmpty
        ? 'Player 1'
        : _p1Controller.text.trim();
    final String p2 = _mode == 'ai'
        ? 'Computer'
        : (_p2Controller.text.trim().isEmpty
            ? 'Player 2'
            : _p2Controller.text.trim());

    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, a, __) => TicTacToe(
          player1Name: p1,
          player2Name: p2,
          isAiMode: _mode == 'ai',
          difficulty: _difficulty,
          theme: kThemes[_themeIndex],
        ),
        transitionsBuilder: (_, a, __, child) =>
            FadeTransition(opacity: a, child: child),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  // ════════════════════════════════════════════════
  // CREATE GAME — connects to server, gets code,
  // then waits in LobbyScreen until guest joins
  // ════════════════════════════════════════════════
  Future<void> _showCreateGameDialog() async {
    final p1 = _p1Controller.text.trim().isEmpty
        ? 'Player 1'
        : _p1Controller.text.trim();

    // Show connecting indicator
    showAppSnackbar(
      context,
      'Connecting to server…',
      color: AppColors.accentBlue,
      icon: Icons.wifi_rounded,
    );

    // Connect WebSocket
    final connected = await MultiplayerServer.connect();
    if (!connected || !mounted) {
      showAppSnackbar(
        context,
        'Could not connect to server. Check internet.',
        color: AppColors.xColor,
        icon: Icons.wifi_off_rounded,
      );
      return;
    }

    // Tell server to create a game session
    MultiplayerServer.createGame(p1);

    // Listen for the code from server
    late StreamSubscription sub;
    sub = MultiplayerServer.stream.listen((data) {
      if (data['type'] == 'created') {
        sub.cancel();
        final code = data['code'] as String;
        final session = MultiplayerSession(
          code: code,
          hostName: p1,
          isHost: true,
        );
        if (mounted) {
          Navigator.push(
            context,
            PageRouteBuilder(
              pageBuilder: (_, a, __) => LobbyScreen(
                session: session,
                theme: kThemes[_themeIndex],
                difficulty: _difficulty,
              ),
              transitionsBuilder: (_, a, __, child) =>
                  FadeTransition(opacity: a, child: child),
              transitionDuration: const Duration(milliseconds: 400),
            ),
          );
        }
      } else if (data['type'] == 'error') {
        sub.cancel();
        if (mounted) {
          showAppSnackbar(
            context,
            data['message'] ?? 'Server error',
            color: AppColors.xColor,
            icon: Icons.error_outline_rounded,
          );
        }
      }
    });
  }

  // ════════════════════════════════════════════════
  // JOIN GAME — connects to server, sends code,
  // server validates and starts game on both sides
  // ════════════════════════════════════════════════
  void _showJoinGameDialog() {
    final codeCtrl = TextEditingController();
    final p2 = _p2Controller.text.trim().isEmpty
        ? 'Player 2'
        : _p2Controller.text.trim();

    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
            boxShadow: [
              BoxShadow(
                color: AppColors.accentGold.withOpacity(0.12),
                blurRadius: 30,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.accentGold.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.login_rounded,
                    color: AppColors.accentGold, size: 28),
              ),
              const SizedBox(height: 16),
              const Text(
                'Join a Game',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Enter the 6-character game code',
                style: TextStyle(color: Color(0x88FFFFFF), fontSize: 13),
              ),
              const SizedBox(height: 20),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.bg2,
                  borderRadius: BorderRadius.circular(14),
                  border:
                      Border.all(color: AppColors.accentGold.withOpacity(0.3)),
                ),
                child: TextField(
                  controller: codeCtrl,
                  textCapitalization: TextCapitalization.characters,
                  textAlign: TextAlign.center,
                  maxLength: 6,
                  style: const TextStyle(
                    color: AppColors.accentGold,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 6,
                  ),
                  decoration: const InputDecoration(
                    hintText: '------',
                    hintStyle: TextStyle(
                      color: Color(0x33FFFFFF),
                      fontSize: 26,
                      letterSpacing: 6,
                    ),
                    border: InputBorder.none,
                    counterText: '',
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Center(
                          child: Text('Cancel',
                              style: TextStyle(
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: () async {
                        final code = codeCtrl.text.trim().toUpperCase();
                        if (code.length < 6) {
                          showAppSnackbar(
                            context,
                            'Please enter a 6-character code',
                            color: AppColors.xColor,
                            icon: Icons.warning_amber_rounded,
                          );
                          return;
                        }

                        Navigator.pop(context);

                        // Show connecting
                        showAppSnackbar(
                          context,
                          'Connecting to server…',
                          color: AppColors.accentBlue,
                          icon: Icons.wifi_rounded,
                        );

                        // Connect WebSocket
                        final connected = await MultiplayerServer.connect();
                        if (!connected || !context.mounted) {
                          showAppSnackbar(
                            context,
                            'Could not connect. Check internet.',
                            color: AppColors.xColor,
                            icon: Icons.wifi_off_rounded,
                          );
                          return;
                        }

                        // Send join request
                        MultiplayerServer.joinGame(code, p2);

                        // Listen for server response
                        late StreamSubscription sub;
                        sub = MultiplayerServer.stream.listen((data) {
                          if (data['type'] == 'joined') {
                            sub.cancel();
                            final hostName = data['hostName'] as String;
                            final guestName = data['guestName'] as String;

                            if (!context.mounted) return;

                            showAppSnackbar(
                              context,
                              '$guestName joined $hostName\'s game!',
                              color: AppColors.easy,
                              icon: Icons.check_circle_outline_rounded,
                            );

                            // Navigate to game as guest (O)
                            Navigator.pushReplacement(
                              context,
                              PageRouteBuilder(
                                pageBuilder: (_, a, __) => TicTacToe(
                                  player1Name: hostName,
                                  player2Name: guestName,
                                  isAiMode: false,
                                  difficulty: _difficulty,
                                  theme: kThemes[_themeIndex],
                                  isOnlineMultiplayer: true,
                                  isHost: false,
                                ),
                                transitionsBuilder: (_, a, __, child) =>
                                    FadeTransition(opacity: a, child: child),
                                transitionDuration:
                                    const Duration(milliseconds: 400),
                              ),
                            );
                          } else if (data['type'] == 'error') {
                            sub.cancel();
                            if (!context.mounted) return;
                            showAppSnackbar(
                              context,
                              data['message'] ?? 'Invalid code! No game found.',
                              color: AppColors.xColor,
                              icon: Icons.error_outline_rounded,
                            );
                          }
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [AppColors.accentGold, Color(0xFFFFB347)],
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.accentGold.withOpacity(0.35),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Text(
                            'Find Game',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final confirmed = await showConfirmDialog(
          context,
          title: 'Exit App?',
          message: 'Are you sure you want to exit the game?',
          confirmLabel: 'Exit',
          icon: Icons.exit_to_app_rounded,
          confirmColor: AppColors.xColor,
        );
        if (confirmed) SystemNavigator.pop();
      },
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.bg1, AppColors.bg2, AppColors.bg3],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: SafeArea(
            child: FadeTransition(
              opacity: _fadeAnim,
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildLogo(),
                    const SizedBox(height: 32),
                    _buildModeSelector(),
                    const SizedBox(height: 20),
                    _buildNameFields(),
                    if (_mode == 'ai') ...[
                      const SizedBox(height: 20),
                      _buildDifficultySelector(),
                    ],
                    const SizedBox(height: 20),
                    _buildThemeSelector(),
                    const SizedBox(height: 28),
                    _buildStartButton(),
                    if (_mode == 'pvp') ...[
                      const SizedBox(height: 16),
                      _buildMultiplayerButtons(),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    final t = kThemes[_themeIndex];
    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [t.xColor, t.oColor],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: t.xColor.withOpacity(0.4),
                blurRadius: 20,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Center(
            child: Text(
              '${t.xSymbol} ${t.oSymbol}',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'TIC TAC TOE',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            letterSpacing: 6,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'The classic game, reimagined',
          style: TextStyle(
            color: Color(0x55FFFFFF),
            fontSize: 13,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }

  Widget _buildModeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('GAME MODE'),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withOpacity(0.06)),
          ),
          padding: const EdgeInsets.all(5),
          child: Row(
            children: [
              _modeButton(
                icon: Icons.people_alt_rounded,
                label: '2 Players',
                value: 'pvp',
              ),
              _modeButton(
                icon: Icons.smart_toy_rounded,
                label: 'vs Computer',
                value: 'ai',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _modeButton({
    required IconData icon,
    required String label,
    required String value,
  }) {
    final bool selected = _mode == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _mode = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            gradient: selected
                ? const LinearGradient(
                    colors: [AppColors.xColor, Color(0xFFFF6B8A)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: selected ? null : Colors.transparent,
            borderRadius: BorderRadius.circular(13),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: AppColors.xColor.withOpacity(0.35),
                      blurRadius: 12,
                    ),
                  ]
                : [],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected ? Colors.white : const Color(0x55FFFFFF),
              ),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : const Color(0x55FFFFFF),
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNameFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('PLAYERS'),
        _nameField(
          controller: _p1Controller,
          hint: _mode == 'ai' ? 'Your Name' : 'Player 1 Name',
          color: kThemes[_themeIndex].xColor,
          symbol: kThemes[_themeIndex].xSymbol,
        ),
        const SizedBox(height: 12),
        if (_mode == 'pvp')
          _nameField(
            controller: _p2Controller,
            hint: 'Player 2 Name',
            color: kThemes[_themeIndex].oColor,
            symbol: kThemes[_themeIndex].oSymbol,
          )
        else
          _computerTile(),
      ],
    );
  }

  Widget _nameField({
    required TextEditingController controller,
    required String hint,
    required Color color,
    required String symbol,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: TextField(
        controller: controller,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
        decoration: InputDecoration(
          prefixIcon: Container(
            margin: const EdgeInsets.all(10),
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                symbol,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
            ),
          ),
          hintText: hint,
          hintStyle: const TextStyle(color: Color(0x55FFFFFF), fontSize: 14),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
    );
  }

  Widget _computerTile() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.oColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Center(
              child: Text(
                'O',
                style: TextStyle(
                  color: AppColors.oColor,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Computer',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              Text(
                'AI Opponent',
                style: TextStyle(color: Color(0x55FFFFFF), fontSize: 11),
              ),
            ],
          ),
          const Spacer(),
          const Icon(
            Icons.smart_toy_rounded,
            color: AppColors.oColor,
            size: 20,
          ),
        ],
      ),
    );
  }

  Widget _buildDifficultySelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('DIFFICULTY'),
        Row(
          children: Difficulty.values.map((d) {
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: d != Difficulty.hard ? 8 : 0),
                child: _difficultyButton(d),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _difficultyButton(Difficulty d) {
    final bool selected = _difficulty == d;
    return GestureDetector(
      onTap: () => setState(() => _difficulty = d),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: selected ? d.color.withOpacity(0.15) : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? d.color.withOpacity(0.6)
                : Colors.white.withOpacity(0.06),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              d.icon,
              color: selected ? d.color : const Color(0x55FFFFFF),
              size: 22,
            ),
            const SizedBox(height: 5),
            Text(
              d.label,
              style: TextStyle(
                color: selected ? d.color : const Color(0x55FFFFFF),
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThemeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('SYMBOL THEME'),
        SizedBox(
          height: 80,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: kThemes.length,
            itemBuilder: (_, i) {
              final t = kThemes[i];
              final sel = _themeIndex == i;
              return GestureDetector(
                onTap: () => setState(() => _themeIndex = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  margin:
                      EdgeInsets.only(right: i < kThemes.length - 1 ? 10 : 0),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: sel ? t.xColor.withOpacity(0.15) : AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: sel
                          ? t.xColor.withOpacity(0.7)
                          : Colors.white.withOpacity(0.06),
                      width: sel ? 1.5 : 1,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(t.xSymbol, style: const TextStyle(fontSize: 18)),
                          const SizedBox(width: 4),
                          Text(t.oSymbol, style: const TextStyle(fontSize: 18)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        t.name,
                        style: TextStyle(
                          color: sel ? t.xColor : const Color(0x55FFFFFF),
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStartButton() {
    return SizedBox(
      width: double.infinity,
      height: 58,
      child: ElevatedButton(
        onPressed: _startGame,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          padding: EdgeInsets.zero,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
        child: Ink(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.xColor, Color(0xFFFF8FA3)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: AppColors.xColor.withOpacity(0.45),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: const Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.play_arrow_rounded, color: Colors.white, size: 26),
                SizedBox(width: 8),
                Text(
                  'START GAME',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2.5,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMultiplayerButtons() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('ONLINE MULTIPLAYER'),
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: _showCreateGameDialog,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  decoration: BoxDecoration(
                    color: AppColors.accentBlue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: AppColors.accentBlue.withOpacity(0.35)),
                  ),
                  child: const Column(
                    children: [
                      Icon(Icons.add_circle_outline_rounded,
                          color: AppColors.accentBlue, size: 26),
                      SizedBox(height: 6),
                      Text(
                        'Create Game',
                        style: TextStyle(
                          color: AppColors.accentBlue,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GestureDetector(
                onTap: _showJoinGameDialog,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  decoration: BoxDecoration(
                    color: AppColors.accentGold.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: AppColors.accentGold.withOpacity(0.35)),
                  ),
                  child: const Column(
                    children: [
                      Icon(Icons.login_rounded,
                          color: AppColors.accentGold, size: 26),
                      SizedBox(height: 6),
                      Text(
                        'Join Game',
                        style: TextStyle(
                          color: AppColors.accentGold,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════
// LOBBY SCREEN — Host waits here until guest joins
// ════════════════════════════════════════════════════════════════
class LobbyScreen extends StatefulWidget {
  final MultiplayerSession session;
  final SymbolTheme theme;
  final Difficulty difficulty;

  const LobbyScreen({
    super.key,
    required this.session,
    required this.theme,
    required this.difficulty,
  });

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;
  late StreamSubscription _sub;
  bool _cancelled = false;

  @override
  void initState() {
    super.initState();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      lowerBound: 0.92,
      upperBound: 1.08,
    )..repeat(reverse: true);
    _pulseAnim = CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut);

    // Listen for server telling us guest joined
    _sub = MultiplayerServer.stream.listen((data) {
      if (!mounted || _cancelled) return;

      if (data['type'] == 'start') {
        // Guest joined — go to game as host (X)
        final guestName = data['guestName'] as String;
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (_, a, __) => TicTacToe(
              player1Name: widget.session.hostName,
              player2Name: guestName,
              isAiMode: false,
              difficulty: widget.difficulty,
              theme: widget.theme,
              isOnlineMultiplayer: true,
              isHost: true,
            ),
            transitionsBuilder: (_, a, __, child) =>
                FadeTransition(opacity: a, child: child),
            transitionDuration: const Duration(milliseconds: 400),
          ),
        );
      } else if (data['type'] == 'error') {
        showAppSnackbar(
          context,
          data['message'] ?? 'Server error',
          color: AppColors.xColor,
          icon: Icons.error_outline_rounded,
        );
      }
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _cancelLobby() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Cancel Game?',
      message: 'This will close the lobby and remove the game code.',
      confirmLabel: 'Cancel Game',
      icon: Icons.cancel_rounded,
      confirmColor: AppColors.xColor,
    );
    if (confirmed && mounted) {
      _cancelled = true;
      MultiplayerServer.disconnect();
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const NameEntryScreen()),
      );
      showAppSnackbar(
        context,
        'Game session cancelled',
        color: Colors.white54,
        icon: Icons.cancel_outlined,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _cancelLobby();
      },
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.bg1, AppColors.bg2, AppColors.bg3],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Pulsing wifi icon
                  ScaleTransition(
                    scale: _pulseAnim,
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.accentBlue.withOpacity(0.12),
                        border: Border.all(
                          color: AppColors.accentBlue.withOpacity(0.35),
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.accentBlue.withOpacity(0.2),
                            blurRadius: 30,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.wifi_tethering_rounded,
                        color: AppColors.accentBlue,
                        size: 46,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  const Text(
                    'WAITING FOR PLAYER',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 3,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Share this code with your friend.\nGame starts automatically when they join.',
                    style: TextStyle(
                      color: Color(0x88FFFFFF),
                      fontSize: 13,
                      height: 1.6,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 36),

                  // Game code — tap to copy
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(
                          ClipboardData(text: widget.session.code));
                      showAppSnackbar(
                        context,
                        'Code copied to clipboard!',
                        color: AppColors.easy,
                        icon: Icons.copy_rounded,
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 28, vertical: 20),
                      decoration: BoxDecoration(
                        color: AppColors.accentBlue.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: AppColors.accentBlue.withOpacity(0.45),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.accentBlue.withOpacity(0.15),
                            blurRadius: 20,
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Text(
                            widget.session.code,
                            style: const TextStyle(
                              color: AppColors.accentBlue,
                              fontSize: 40,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 10,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.copy_rounded,
                                  color: Color(0x55FFFFFF), size: 14),
                              SizedBox(width: 5),
                              Text(
                                'Tap to copy',
                                style: TextStyle(
                                  color: Color(0x55FFFFFF),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Player slots
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white.withOpacity(0.06)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.xColor.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(widget.theme.xSymbol,
                              style: const TextStyle(fontSize: 18)),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.session.hostName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                            const Text(
                              'Host · Ready ✓',
                              style: TextStyle(
                                color: AppColors.easy,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(widget.theme.oSymbol,
                              style: const TextStyle(fontSize: 18)),
                        ),
                        const SizedBox(width: 12),
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Waiting…',
                              style: TextStyle(
                                color: Colors.white54,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              'Guest · Not joined',
                              style: TextStyle(
                                color: Color(0x55FFFFFF),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 40),
                  const _WaitingDots(),
                  const SizedBox(height: 40),

                  // Cancel button
                  SizedBox(
                    width: double.infinity,
                    child: GestureDetector(
                      onTap: _cancelLobby,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(16),
                          border:
                              Border.all(color: Colors.white.withOpacity(0.08)),
                        ),
                        child: const Center(
                          child: Text(
                            'CANCEL LOBBY',
                            style: TextStyle(
                              color: Colors.white54,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.5,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// WAITING DOTS ANIMATION
// ════════════════════════════════════════════════════════════════
class _WaitingDots extends StatefulWidget {
  const _WaitingDots();

  @override
  State<_WaitingDots> createState() => _WaitingDotsState();
}

class _WaitingDotsState extends State<_WaitingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  int _dot = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500))
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) {
          if (mounted) setState(() => _dot = (_dot + 1) % 3);
          _ctrl.forward(from: 0);
        }
      });
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (i) {
        final active = i == _dot;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.symmetric(horizontal: 5),
          width: active ? 12 : 8,
          height: active ? 12 : 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active
                ? AppColors.accentBlue
                : AppColors.accentBlue.withOpacity(0.25),
          ),
        );
      }),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// SECTION LABEL WIDGET
// ════════════════════════════════════════════════════════════════
class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0x55FFFFFF),
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 2,
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// CONFETTI PARTICLE + PAINTER
// ════════════════════════════════════════════════════════════════
class _ConfettiParticle {
  double x, y, vx, vy, rotation, rotationSpeed, size;
  Color color;

  _ConfettiParticle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.rotation,
    required this.rotationSpeed,
    required this.size,
    required this.color,
  });
}

class _ConfettiPainter extends CustomPainter {
  final List<_ConfettiParticle> particles;
  final double progress;

  _ConfettiPainter({required this.particles, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final paint = Paint()
        ..color = p.color.withOpacity((1 - progress * 0.7).clamp(0.0, 1.0));
      canvas.save();
      canvas.translate(p.x * size.width, p.y * size.height);
      canvas.rotate(p.rotation);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
              center: Offset.zero, width: p.size, height: p.size * 0.5),
          const Radius.circular(2),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => true;
}

// ════════════════════════════════════════════════════════════════
// GAME SCREEN
// ════════════════════════════════════════════════════════════════
class TicTacToe extends StatefulWidget {
  final String player1Name;
  final String player2Name;
  final bool isAiMode;
  final Difficulty difficulty;
  final SymbolTheme theme;
  final bool isOnlineMultiplayer; // NEW
  final bool isHost; // NEW — host = X, guest = O

  const TicTacToe({
    super.key,
    required this.player1Name,
    required this.player2Name,
    this.isAiMode = false,
    this.difficulty = Difficulty.medium,
    required this.theme,
    this.isOnlineMultiplayer = false, // NEW
    this.isHost = true, // NEW
  });

  @override
  State<TicTacToe> createState() => _TicTacToeState();
}

class _TicTacToeState extends State<TicTacToe> with TickerProviderStateMixin {
  List<String> board = List.filled(9, '');
  bool isXTurn = true;
  String winner = '';
  List<int> winningCells = [];
  int scoreX = 0;
  int scoreO = 0;
  int draws = 0;
  int gamesPlayed = 0;
  int movesThisRound = 0;
  bool aiThinking = false;
  bool _soundOn = true;

  final List<MatchEntry> _matchLog = [];
  final SoundManager _sound = SoundManager();
  final Random _random = Random();
  final GlobalKey _boardKey = GlobalKey();
  Size _boardSize = Size.zero;

  // Online multiplayer subscription
  StreamSubscription? _onlineSub;

  late final List<AnimationController> _cellControllers;
  late final List<Animation<double>> _cellAnimations;
  late final AnimationController _winGlowCtrl;
  late final Animation<double> _winGlowAnim;
  late final AnimationController _lineCtrl;
  late final Animation<double> _lineAnim;
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;
  late final AnimationController _turnCtrl;
  late final AnimationController _confettiCtrl;
  late final Animation<double> _confettiAnim;
  final List<_ConfettiParticle> _confettiParticles = [];

  SymbolTheme get _t => widget.theme;
  Color get _xC => _t.xColor;
  Color get _oC => _t.oColor;

  // Online: is it MY turn?
  bool get _myTurn {
    if (!widget.isOnlineMultiplayer) return true;
    return widget.isHost ? isXTurn : !isXTurn;
  }

  @override
  void initState() {
    super.initState();

    _winGlowCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _winGlowAnim =
        CurvedAnimation(parent: _winGlowCtrl, curve: Curves.easeInOut);
    _lineCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _lineAnim = CurvedAnimation(parent: _lineCtrl, curve: Curves.easeOut);
    _pulseCtrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 900),
        lowerBound: 0.95,
        upperBound: 1.05)
      ..repeat(reverse: true);
    _pulseAnim = CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut);
    _turnCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _turnCtrl.forward();
    _confettiCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2500));
    _confettiAnim =
        CurvedAnimation(parent: _confettiCtrl, curve: Curves.easeOut);
    _confettiCtrl.addListener(() {
      if (_confettiCtrl.isAnimating) {
        setState(() => _updateConfetti());
      }
    });
    _cellControllers = List.generate(
      9,
      (_) => AnimationController(
          vsync: this, duration: const Duration(milliseconds: 350)),
    );
    _cellAnimations = _cellControllers
        .map((c) => CurvedAnimation(parent: c, curve: Curves.elasticOut)
            as Animation<double>)
        .toList();

    // Start listening for opponent moves if online
    if (widget.isOnlineMultiplayer) {
      _listenOnline();
    }
  }

  // Listen for moves from opponent via WebSocket
  void _listenOnline() {
    _onlineSub = MultiplayerServer.stream.listen((data) {
      if (!mounted) return;

      if (data['type'] == 'move') {
        // Opponent made a move — apply it
        final index = data['index'] as int;
        _makeMove(index, isXTurn ? 'X' : 'O');
      } else if (data['type'] == 'opponent_left') {
        showAppSnackbar(
          context,
          'Opponent left the game!',
          color: AppColors.xColor,
          icon: Icons.person_off_rounded,
        );
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const NameEntryScreen()),
            );
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _onlineSub?.cancel();
    _winGlowCtrl.dispose();
    _lineCtrl.dispose();
    _pulseCtrl.dispose();
    _turnCtrl.dispose();
    _confettiCtrl.dispose();
    for (final c in _cellControllers) {
      c.dispose();
    }
    _sound.dispose();
    super.dispose();
  }

  void _launchConfetti() {
    final colors = [
      _xC,
      _oC,
      AppColors.accentGold,
      Colors.white,
      const Color(0xFF06D6A0),
      const Color(0xFFFF9A9E),
    ];
    _confettiParticles.clear();
    for (int i = 0; i < 120; i++) {
      _confettiParticles.add(_ConfettiParticle(
        x: _random.nextDouble(),
        y: _random.nextDouble() * 0.3,
        vx: (_random.nextDouble() - 0.5) * 0.012,
        vy: 0.004 + _random.nextDouble() * 0.008,
        rotation: _random.nextDouble() * pi * 2,
        rotationSpeed: (_random.nextDouble() - 0.5) * 0.15,
        size: 6 + _random.nextDouble() * 8,
        color: colors[_random.nextInt(colors.length)],
      ));
    }
    _confettiCtrl.forward(from: 0);
  }

  void _updateConfetti() {
    for (final p in _confettiParticles) {
      p.x += p.vx;
      p.y += p.vy;
      p.rotation += p.rotationSpeed;
      p.vy += 0.0003;
    }
  }

  void _handleTap(int index) {
    if (board[index] != '' || winner != '' || aiThinking) return;
    // Online: block if not my turn
    if (widget.isOnlineMultiplayer && !_myTurn) return;

    _sound.playTap();
    final mark = isXTurn ? 'X' : 'O';
    _makeMove(index, mark);

    // Online: send move to opponent
    if (widget.isOnlineMultiplayer) {
      MultiplayerServer.sendMove(index);
    }

    // AI mode
    if (widget.isAiMode && winner == '' && !isXTurn) {
      setState(() => aiThinking = true);
      final delay = widget.difficulty == Difficulty.easy ? 400 : 600;
      Future.delayed(Duration(milliseconds: delay), () {
        if (!mounted) return;
        final move = _getAiMove();
        if (move != -1) {
          _sound.playTap();
          _makeMove(move, 'O');
        }
        setState(() => aiThinking = false);
      });
    }
  }

  void _makeMove(int index, String mark) {
    setState(() {
      board[index] = mark;
      isXTurn = !isXTurn;
      movesThisRound++;
      _cellControllers[index].forward(from: 0);
      _checkWinner();
      if (winner == '') _turnCtrl.forward(from: 0);
    });
  }

  void _checkWinner() {
    const patterns = [
      [0, 1, 2],
      [3, 4, 5],
      [6, 7, 8],
      [0, 3, 6],
      [1, 4, 7],
      [2, 5, 8],
      [0, 4, 8],
      [2, 4, 6],
    ];
    for (final p in patterns) {
      final a = board[p[0]];
      final b = board[p[1]];
      final c = board[p[2]];
      if (a != '' && a == b && b == c) {
        winner = a;
        winningCells = List<int>.from(p);
        gamesPlayed++;
        if (winner == 'X') scoreX++;
        if (winner == 'O') scoreO++;
        final winnerName =
            winner == 'X' ? widget.player1Name : widget.player2Name;
        _matchLog.insert(
            0,
            MatchEntry(
              result: winner,
              winnerName: winnerName,
              moves: movesThisRound,
              time: DateTime.now(),
            ));
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _captureBoardLayout();
          _winGlowCtrl.forward(from: 0);
          _lineCtrl.forward(from: 0);
          _launchConfetti();
        });
        _sound.playWin();
        return;
      }
    }
    if (!board.contains('')) {
      winner = 'Draw';
      draws++;
      gamesPlayed++;
      _matchLog.insert(
          0,
          MatchEntry(
            result: 'Draw',
            winnerName: 'Draw',
            moves: movesThisRound,
            time: DateTime.now(),
          ));
      _sound.playDraw();
    }
  }

  void _captureBoardLayout() {
    final box = _boardKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null && mounted) {
      setState(() => _boardSize = box.size);
    }
  }

  int _getAiMove() {
    switch (widget.difficulty) {
      case Difficulty.easy:
        return _easyMove();
      case Difficulty.medium:
        return _mediumMove();
      case Difficulty.hard:
        return _bestMove();
    }
  }

  int _easyMove() {
    if (_random.nextDouble() < 0.25) {
      final w = _findWinningMove('O');
      if (w != -1) return w;
    }
    final empty = [
      for (int i = 0; i < 9; i++)
        if (board[i] == '') i
    ];
    return empty.isEmpty ? -1 : empty[_random.nextInt(empty.length)];
  }

  int _mediumMove() {
    final w = _findWinningMove('O');
    if (w != -1) return w;
    if (_random.nextDouble() < 0.7) {
      final b = _findWinningMove('X');
      if (b != -1) return b;
    }
    if (board[4] == '' && _random.nextDouble() < 0.6) return 4;
    final empty = [
      for (int i = 0; i < 9; i++)
        if (board[i] == '') i
    ];
    return empty.isEmpty ? -1 : empty[_random.nextInt(empty.length)];
  }

  int _findWinningMove(String mark) {
    for (int i = 0; i < 9; i++) {
      if (board[i] == '') {
        board[i] = mark;
        final win = _mmWinner(board) == mark;
        board[i] = '';
        if (win) return i;
      }
    }
    return -1;
  }

  int _bestMove() {
    int bestScore = -1000;
    int bestMove = -1;
    for (int i = 0; i < 9; i++) {
      if (board[i] == '') {
        board[i] = 'O';
        final s = _minimax(board, 0, false);
        board[i] = '';
        if (s > bestScore) {
          bestScore = s;
          bestMove = i;
        }
      }
    }
    return bestMove;
  }

  int _minimax(List<String> b, int depth, bool maximizing) {
    final r = _mmWinner(b);
    if (r == 'O') return 10 - depth;
    if (r == 'X') return depth - 10;
    if (!b.contains('')) return 0;
    if (maximizing) {
      int best = -1000;
      for (int i = 0; i < 9; i++) {
        if (b[i] == '') {
          b[i] = 'O';
          final v = _minimax(b, depth + 1, false);
          if (v > best) best = v;
          b[i] = '';
        }
      }
      return best;
    } else {
      int best = 1000;
      for (int i = 0; i < 9; i++) {
        if (b[i] == '') {
          b[i] = 'X';
          final v = _minimax(b, depth + 1, true);
          if (v < best) best = v;
          b[i] = '';
        }
      }
      return best;
    }
  }

  String _mmWinner(List<String> b) {
    const p = [
      [0, 1, 2],
      [3, 4, 5],
      [6, 7, 8],
      [0, 3, 6],
      [1, 4, 7],
      [2, 5, 8],
      [0, 4, 8],
      [2, 4, 6],
    ];
    for (final x in p) {
      if (b[x[0]] != '' && b[x[0]] == b[x[1]] && b[x[1]] == b[x[2]]) {
        return b[x[0]];
      }
    }
    return '';
  }

  void _resetRound() {
    setState(() {
      board = List.filled(9, '');
      winner = '';
      winningCells = [];
      isXTurn = true;
      aiThinking = false;
      movesThisRound = 0;
      _boardSize = Size.zero;
      _winGlowCtrl.reset();
      _lineCtrl.reset();
      _confettiCtrl.stop();
      _confettiCtrl.reset();
      _confettiParticles.clear();
      for (final c in _cellControllers) {
        c.reset();
      }
    });
    _turnCtrl.forward(from: 0);
    showAppSnackbar(
      context,
      'New round started!',
      color: AppColors.easy,
      icon: Icons.refresh_rounded,
    );
  }

  void _resetAll() {
    setState(() {
      scoreX = 0;
      scoreO = 0;
      draws = 0;
      gamesPlayed = 0;
      _matchLog.clear();
    });
    _resetRound();
    showAppSnackbar(
      context,
      'All scores reset!',
      color: AppColors.accentGold,
      icon: Icons.delete_sweep_rounded,
    );
  }

  Future<void> _confirmQuit() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Quit Game?',
      message: 'You\'ll lose your current scores. Are you sure?',
      confirmLabel: 'Quit',
      icon: Icons.exit_to_app_rounded,
      confirmColor: AppColors.xColor,
    );
    if (confirmed && mounted) {
      if (widget.isOnlineMultiplayer) MultiplayerServer.disconnect();
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const NameEntryScreen()),
      );
    }
  }

  Future<void> _confirmResetRound() async {
    if (board.every((c) => c.isEmpty) && winner.isEmpty) {
      _resetRound();
      return;
    }
    final confirmed = await showConfirmDialog(
      context,
      title: 'New Round?',
      message: 'Start a fresh round? Current board will be cleared.',
      confirmLabel: 'New Round',
      icon: Icons.refresh_rounded,
      confirmColor: AppColors.accentBlue,
    );
    if (confirmed) _resetRound();
  }

  Future<void> _confirmResetAll() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Reset Everything?',
      message: 'All scores and match history will be permanently deleted.',
      confirmLabel: 'Reset All',
      icon: Icons.delete_sweep_rounded,
      confirmColor: AppColors.xColor,
    );
    if (confirmed) _resetAll();
  }

  void _showScoreboard() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ScoreboardSheet(
        p1Name: widget.player1Name,
        p2Name: widget.player2Name,
        scoreX: scoreX,
        scoreO: scoreO,
        draws: draws,
        gamesPlayed: gamesPlayed,
        xColor: _xC,
        oColor: _oC,
        matchLog: _matchLog,
        onResetAll: () {
          Navigator.pop(context);
          _confirmResetAll();
        },
      ),
    );
  }

  Color get _statusColor {
    if (winner == 'X') return _xC;
    if (winner == 'O') return _oC;
    if (winner == 'Draw') return AppColors.accentGold;
    return isXTurn ? _xC : _oC;
  }

  (Offset, Offset)? _getWinLineOffsets() {
    if (winningCells.length < 3 || _boardSize == Size.zero) return null;
    const gap = 10.0;
    final cW = (_boardSize.width - gap * 2) / 3;
    final cH = (_boardSize.height - gap * 2) / 3;
    Offset centerOf(int idx) => Offset(
          (idx % 3) * (cW + gap) + cW / 2,
          (idx ~/ 3) * (cH + gap) + cH / 2,
        );
    final s = centerOf(winningCells.first);
    final e = centerOf(winningCells.last);
    final dir = e - s;
    final n = dir / dir.distance;
    return (s - n * 14, e + n * 14);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _confirmQuit();
      },
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.bg1, AppColors.bg2, AppColors.bg3],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: SafeArea(
            child: Stack(
              children: [
                Positioned.fill(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildHeader(),
                      _buildScoreBanner(),
                      const SizedBox(height: 20),
                      _buildTurnIndicator(),
                      const SizedBox(height: 20),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: _buildBoardArea(),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        child: _buildButtons(),
                      ),
                    ],
                  ),
                ),
                if (_confettiCtrl.isAnimating && _confettiParticles.isNotEmpty)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _ConfettiPainter(
                          particles: _confettiParticles,
                          progress: _confettiAnim.value,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          _iconButton(
            icon: Icons.arrow_back_ios_new_rounded,
            onTap: _confirmQuit,
          ),
          const Spacer(),
          Column(
            children: [
              const Text(
                'TIC TAC TOE',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  letterSpacing: 3,
                ),
              ),
              if (widget.isAiMode)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(widget.difficulty.icon,
                        size: 11, color: widget.difficulty.color),
                    const SizedBox(width: 4),
                    Text(
                      widget.difficulty.label.toUpperCase(),
                      style: TextStyle(
                        color: widget.difficulty.color,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
              if (widget.isOnlineMultiplayer)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.wifi_rounded,
                        size: 11, color: AppColors.easy),
                    const SizedBox(width: 4),
                    Text(
                      widget.isHost ? 'HOST' : 'GUEST',
                      style: const TextStyle(
                        color: AppColors.easy,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const Spacer(),
          _iconButton(
            icon: Icons.bar_chart_rounded,
            onTap: _showScoreboard,
            color: AppColors.accentGold,
          ),
        ],
      ),
    );
  }

  Widget _iconButton(
      {required IconData icon, required VoidCallback onTap, Color? color}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.06)),
          ),
          child: Icon(icon, color: color ?? Colors.white70, size: 18),
        ),
      ),
    );
  }

  Widget _buildScoreBanner() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(
        children: [
          _bannerScore(widget.player1Name, scoreX, _xC, _t.xSymbol),
          Expanded(
            child: Column(
              children: [
                const Text('VS',
                    style: TextStyle(
                      color: Color(0x55FFFFFF),
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                      letterSpacing: 2,
                    )),
                const SizedBox(height: 2),
                Text('$draws',
                    style: const TextStyle(
                      color: Color(0x55FFFFFF),
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    )),
                const Text('draws',
                    style: TextStyle(
                      color: Color(0x44FFFFFF),
                      fontSize: 9,
                      letterSpacing: 1,
                    )),
              ],
            ),
          ),
          _bannerScore(widget.player2Name, scoreO, _oC, _t.oSymbol,
              alignEnd: true),
        ],
      ),
    );
  }

  Widget _bannerScore(String name, int score, Color color, String symbol,
      {bool alignEnd = false}) {
    final label = name.length > 10 ? '${name.substring(0, 10)}…' : name;
    return Expanded(
      child: Column(
        crossAxisAlignment:
            alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Text('$score',
              style: TextStyle(
                color: color,
                fontSize: 28,
                fontWeight: FontWeight.w900,
                height: 1,
              )),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              )),
        ],
      ),
    );
  }

  Widget _buildTurnIndicator() {
    final bool gameOver = winner != '';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(
            child: _turnCard(
              name: widget.player1Name,
              symbol: _t.xSymbol,
              color: _xC,
              isActive: !gameOver && isXTurn,
              isWinner: winner == 'X',
              alignRight: false,
            ),
          ),
          const SizedBox(width: 8),
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: gameOver
                  ? _statusColor.withOpacity(0.15)
                  : AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: gameOver
                    ? _statusColor.withOpacity(0.5)
                    : Colors.white.withOpacity(0.06),
              ),
            ),
            child: Center(
              child: Icon(
                gameOver
                    ? (winner == 'Draw'
                        ? Icons.handshake_rounded
                        : Icons.emoji_events_rounded)
                    : (aiThinking
                        ? Icons.more_horiz_rounded
                        : Icons.arrow_forward_ios_rounded),
                color: gameOver ? _statusColor : Colors.white38,
                size: 16,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _turnCard(
              name: widget.player2Name,
              symbol: _t.oSymbol,
              color: _oC,
              isActive: !gameOver && !isXTurn,
              isWinner: winner == 'O',
              alignRight: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _turnCard({
    required String name,
    required String symbol,
    required Color color,
    required bool isActive,
    required bool isWinner,
    required bool alignRight,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isActive
            ? color.withOpacity(0.12)
            : isWinner
                ? color.withOpacity(0.18)
                : AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isActive || isWinner
              ? color.withOpacity(0.5)
              : Colors.white.withOpacity(0.05),
          width: isActive || isWinner ? 1.5 : 1,
        ),
        boxShadow: isActive
            ? [BoxShadow(color: color.withOpacity(0.2), blurRadius: 12)]
            : [],
      ),
      child: Row(
        mainAxisAlignment:
            alignRight ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: alignRight
            ? [
                Flexible(
                  child: Text(name,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: isActive || isWinner
                            ? Colors.white
                            : Colors.white54,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      )),
                ),
                const SizedBox(width: 6),
                Text(symbol, style: const TextStyle(fontSize: 16)),
              ]
            : [
                Text(symbol, style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isActive || isWinner
                            ? Colors.white
                            : Colors.white54,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      )),
                ),
              ],
      ),
    );
  }

  Widget _buildBoardArea() {
    return LayoutBuilder(builder: (context, constraints) {
      final size = constraints.biggest.shortestSide;
      return Center(
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            children: [
              GridView.builder(
                key: _boardKey,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                itemCount: 9,
                itemBuilder: (_, i) => _buildCell(i),
              ),
              if (winningCells.length == 3 && _boardSize != Size.zero)
                AnimatedBuilder(
                  animation: _lineAnim,
                  builder: (_, __) {
                    final off = _getWinLineOffsets();
                    if (off == null) return const SizedBox();
                    return CustomPaint(
                      size: Size(size, size),
                      painter: _WinLinePainter(
                        start: off.$1,
                        end: off.$2,
                        progress: _lineAnim.value,
                        color: winner == 'X' ? _xC : _oC,
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      );
    });
  }

  Widget _buildCell(int index) {
    final bool isWin = winningCells.contains(index);
    final String mark = board[index];
    final Color mColor = mark == 'X' ? _xC : _oC;
    final bool isEmpty = mark.isEmpty;
    // Online: only show tap hint on your turn
    final bool active =
        winner == '' && !aiThinking && (!widget.isOnlineMultiplayer || _myTurn);

    return GestureDetector(
      onTap: () => _handleTap(index),
      child: AnimatedBuilder(
        animation: _winGlowAnim,
        builder: (_, __) {
          final double glow = _winGlowAnim.value;
          final Widget cell = AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            decoration: BoxDecoration(
              color: isWin
                  ? mColor.withOpacity(0.15 + 0.1 * glow)
                  : isEmpty && active
                      ? AppColors.surfaceLight
                      : AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isWin
                    ? mColor.withOpacity(0.6 + 0.2 * glow)
                    : isEmpty && active
                        ? Colors.white.withOpacity(0.08)
                        : Colors.white.withOpacity(0.05),
                width: isWin ? 2 : 1.5,
              ),
              boxShadow: isWin
                  ? [
                      BoxShadow(
                          color: mColor.withOpacity(0.3 * glow),
                          blurRadius: 16,
                          spreadRadius: 2)
                    ]
                  : [],
            ),
            child: Center(
              child: isEmpty
                  ? (active
                      ? Icon(Icons.add_rounded,
                          color: Colors.white.withOpacity(0.07), size: 26)
                      : const SizedBox())
                  : Text(mark,
                      style: TextStyle(
                        fontSize: _isEmoji(mark) ? 34 : 42,
                        fontWeight: FontWeight.w900,
                        color: mColor,
                        shadows: [
                          Shadow(
                            color: mColor.withOpacity(0.5),
                            blurRadius: 14,
                          )
                        ],
                      )),
            ),
          );
          if (mark.isNotEmpty) {
            return ScaleTransition(scale: _cellAnimations[index], child: cell);
          }
          if (isWin) {
            return ScaleTransition(scale: _pulseAnim, child: cell);
          }
          return cell;
        },
      ),
    );
  }

  bool _isEmoji(String s) => s.runes.any((r) => r > 0x7F);

  Widget _buildButtons() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          _actionButton(
            icon: Icons.delete_sweep_rounded,
            label: 'Reset',
            color: Colors.white60,
            bg: AppColors.surface,
            onTap: _confirmResetAll,
          ),
          const SizedBox(width: 6),
          _actionButton(
            icon: _soundOn ? Icons.volume_up : Icons.volume_off,
            label: 'Sound',
            color: _soundOn ? Colors.green : Colors.red,
            bg: AppColors.surface,
            onTap: () {
              setState(() {
                _soundOn = !_soundOn;
                _sound.soundOn = _soundOn;
              });
              showAppSnackbar(
                context,
                _soundOn ? 'Sound turned on' : 'Sound muted',
                color: _soundOn ? AppColors.easy : Colors.white38,
                icon: _soundOn
                    ? Icons.volume_up_rounded
                    : Icons.volume_off_rounded,
              );
            },
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _confirmResetRound,
                borderRadius: BorderRadius.circular(16),
                child: Ink(
                  height: 54,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.xColor, Color(0xFFFF8FA3)],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.xColor.withOpacity(0.4),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      )
                    ],
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.refresh_rounded,
                          color: Colors.white, size: 20),
                      SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'NEW ROUND',
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          _actionButton(
            icon: Icons.history_rounded,
            label: 'History',
            color: AppColors.accentGold,
            bg: AppColors.surface,
            onTap: _showScoreboard,
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required Color color,
    required Color bg,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          width: 50,
          height: 54,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(height: 2),
              Text(label,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: TextStyle(
                    color: color,
                    fontSize: 8.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// SCOREBOARD + MATCH LOG BOTTOM SHEET
// ════════════════════════════════════════════════════════════════
class _ScoreboardSheet extends StatefulWidget {
  final String p1Name;
  final String p2Name;
  final int scoreX;
  final int scoreO;
  final int draws;
  final int gamesPlayed;
  final Color xColor;
  final Color oColor;
  final List<MatchEntry> matchLog;
  final VoidCallback onResetAll;

  const _ScoreboardSheet({
    required this.p1Name,
    required this.p2Name,
    required this.scoreX,
    required this.scoreO,
    required this.draws,
    required this.gamesPlayed,
    required this.xColor,
    required this.oColor,
    required this.matchLog,
    required this.onResetAll,
  });

  @override
  State<_ScoreboardSheet> createState() => _ScoreboardSheetState();
}

class _ScoreboardSheetState extends State<_ScoreboardSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.92,
      minChildSize: 0.4,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.accentGold.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.emoji_events_rounded,
                        color: AppColors.accentGold, size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Text('STATS & HISTORY',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                      )),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.close_rounded,
                        color: Color(0x55FFFFFF)),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.bg2,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TabBar(
                  controller: _tabCtrl,
                  indicator: BoxDecoration(
                    color: AppColors.xColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  labelColor: Colors.white,
                  unselectedLabelColor: const Color(0x55FFFFFF),
                  labelStyle: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 13),
                  tabs: const [Tab(text: 'Scores'), Tab(text: 'Match Log')],
                ),
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabCtrl,
                children: [
                  _buildScoresTab(scrollCtrl),
                  _buildLogTab(scrollCtrl),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScoresTab(ScrollController ctrl) {
    return ListView(
      controller: ctrl,
      padding: const EdgeInsets.all(24),
      children: [
        _scoreRow(
          name: widget.p1Name,
          score: widget.scoreX,
          color: widget.xColor,
          symbol: 'X',
          leading: widget.scoreX > widget.scoreO,
        ),
        const SizedBox(height: 12),
        _scoreRow(
          name: widget.p2Name,
          score: widget.scoreO,
          color: widget.oColor,
          symbol: 'O',
          leading: widget.scoreO > widget.scoreX,
        ),
        const SizedBox(height: 12),
        _drawRow(),
        const SizedBox(height: 20),
        _statsRow(),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: widget.onResetAll,
            icon: const Icon(Icons.refresh_rounded,
                color: Colors.white, size: 18),
            label: const Text('RESET ALL SCORES',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                )),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.xColor,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _scoreRow({
    required String name,
    required int score,
    required Color color,
    required String symbol,
    required bool leading,
  }) {
    final int total = widget.scoreX + widget.scoreO;
    final double pct = total > 0 ? score / total : 0.0;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: leading ? color.withOpacity(0.4) : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(symbol,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      )),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    )),
              ),
              if (leading && score > 0)
                const Icon(Icons.star_rounded,
                    color: AppColors.accentGold, size: 18),
              const SizedBox(width: 6),
              Text('$score',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w900,
                    fontSize: 26,
                  )),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct,
              backgroundColor: Colors.white.withOpacity(0.07),
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _drawRow() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.handshake_rounded,
                color: Color(0x55FFFFFF), size: 16),
          ),
          const SizedBox(width: 10),
          const Text('Draws',
              style: TextStyle(
                  color: Colors.white70, fontWeight: FontWeight.w600)),
          const Spacer(),
          Text('${widget.draws}',
              style: const TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w900,
                fontSize: 22,
              )),
        ],
      ),
    );
  }

  Widget _statsRow() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _statItem('Games', '${widget.gamesPlayed}', Icons.gamepad_rounded),
          Container(
              width: 1, height: 40, color: Colors.white.withOpacity(0.08)),
          _statItem(
            '${widget.p1Name.split(' ').first} Win%',
            widget.gamesPlayed > 0
                ? '${((widget.scoreX / widget.gamesPlayed) * 100).toStringAsFixed(0)}%'
                : '—',
            Icons.trending_up_rounded,
            color: widget.xColor,
          ),
          Container(
              width: 1, height: 40, color: Colors.white.withOpacity(0.08)),
          _statItem(
            '${widget.p2Name.split(' ').first} Win%',
            widget.gamesPlayed > 0
                ? '${((widget.scoreO / widget.gamesPlayed) * 100).toStringAsFixed(0)}%'
                : '—',
            Icons.trending_up_rounded,
            color: widget.oColor,
          ),
        ],
      ),
    );
  }

  Widget _statItem(String label, String value, IconData icon, {Color? color}) {
    return Column(
      children: [
        Icon(icon, color: color ?? const Color(0x55FFFFFF), size: 16),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(
              color: color ?? Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 16,
            )),
        Text(label,
            style: const TextStyle(color: Color(0x55FFFFFF), fontSize: 10),
            textAlign: TextAlign.center),
      ],
    );
  }

  Widget _buildLogTab(ScrollController ctrl) {
    if (widget.matchLog.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history_toggle_off_rounded,
                color: Colors.white24, size: 48),
            SizedBox(height: 12),
            Text('No matches yet',
                style: TextStyle(color: Color(0x55FFFFFF), fontSize: 14)),
          ],
        ),
      );
    }
    return ListView.builder(
      controller: ctrl,
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      itemCount: widget.matchLog.length,
      itemBuilder: (_, i) {
        final m = widget.matchLog[i];
        final color = m.result == 'X'
            ? widget.xColor
            : m.result == 'O'
                ? widget.oColor
                : AppColors.accentGold;
        final icon = m.result == 'Draw'
            ? Icons.handshake_rounded
            : Icons.emoji_events_rounded;
        final ts =
            '${m.time.hour.toString().padLeft(2, '0')}:${m.time.minute.toString().padLeft(2, '0')}';
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: color.withOpacity(0.07),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withOpacity(0.2)),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m.result == 'Draw'
                          ? "It's a Draw!"
                          : '${m.winnerName} Won',
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    Text('${m.moves} moves',
                        style: const TextStyle(
                          color: Color(0x55FFFFFF),
                          fontSize: 11,
                        )),
                  ],
                ),
              ),
              Text('Match ${widget.matchLog.length - i}',
                  style:
                      const TextStyle(color: Color(0x44FFFFFF), fontSize: 10)),
              const SizedBox(width: 8),
              Text(ts,
                  style:
                      const TextStyle(color: Color(0x55FFFFFF), fontSize: 11)),
            ],
          ),
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════
// WIN LINE PAINTER
// ════════════════════════════════════════════════════════════════
class _WinLinePainter extends CustomPainter {
  final Offset start;
  final Offset end;
  final double progress;
  final Color color;

  _WinLinePainter({
    required this.start,
    required this.end,
    required this.progress,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final cur = Offset(
      start.dx + (end.dx - start.dx) * progress,
      start.dy + (end.dy - start.dy) * progress,
    );
    canvas.drawLine(
        start,
        cur,
        Paint()
          ..color = color.withOpacity(0.25)
          ..strokeWidth = 18
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
    canvas.drawLine(
        start,
        cur,
        Paint()
          ..color = color.withOpacity(0.9)
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round);
    canvas.drawLine(
        start,
        cur,
        Paint()
          ..color = Colors.white.withOpacity(0.6)
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(_WinLinePainter old) =>
      old.progress != progress || old.color != color;
}
