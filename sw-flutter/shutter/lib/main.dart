import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';

void main() => runApp(const ShutterApp());

class ShutterApp extends StatelessWidget {
  const ShutterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Shutter Control',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0D0D0F),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6366F1),
          secondary: Color(0xFF22D3EE),
          surface: Color(0xFF18181B),
        ),
      ),
      home: const ShutterHomePage(),
    );
  }
}

class ShutterHomePage extends StatefulWidget {
  const ShutterHomePage({super.key});

  @override
  State<ShutterHomePage> createState() => _ShutterHomePageState();
}

class _ShutterHomePageState extends State<ShutterHomePage>
    with TickerProviderStateMixin {
  // BLE State
  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _characteristic;
  bool _isScanning = false;
  bool _isConnected = false;
  String _statusText = 'Disconnected';

  // Animation controllers
  late AnimationController _pulseController;
  late AnimationController _upArrowController;
  late AnimationController _downArrowController;

  @override
  void initState() {
    super.initState();

    if (kDebugMode) {
      print('starting app');
    }

    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    _upArrowController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );

    _downArrowController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _upArrowController.dispose();
    _downArrowController.dispose();
    super.dispose();
  }

  // Future<void> _startScan() async {
  //   setState(() {
  //     _isScanning = true;
  //     _statusText = 'Scanning...';
  //   });

  //   FlutterBluePlus.startScan(timeout: const Duration(seconds: 4));

  //   FlutterBluePlus.scanResults.listen((results) {
  //     for (ScanResult r in results) {
  //       if (kDebugMode) {
  //         print('scan res: $r');
  //       }

  //       // Look for your ESP32 device by name or service UUID
  //       if (r.device.platformName.contains('ESP32') ||
  //           r.device.platformName.contains('Shutter')) {
  //         _connectToDevice(r.device);
  //         FlutterBluePlus.stopScan();
  //         break;
  //       }
  //     }
  //   });

  //   await Future.delayed(const Duration(seconds: 4));
  //   if (!_isConnected) {
  //     setState(() {
  //       _isScanning = false;
  //       _statusText = 'No device found';
  //     });
  //   }
  // }

  Future<void> _startScan() async {
    setState(() {
      _isScanning = true;
      _statusText = 'Requesting permissions...';
    });

    // Request permissions
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    if (statuses.values.any((status) => status != PermissionStatus.granted)) {
      setState(() {
        _isScanning = false;
        _statusText = 'Permissions denied';
      });
      return;
    }

    setState(() {
      _statusText = 'Scanning...';
    });

    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 4));

    FlutterBluePlus.scanResults.listen((results) {
      for (ScanResult r in results) {
        if (kDebugMode) {
          print('scan res: $r');
        }

        final name = r.device.platformName.toLowerCase();
        // Look for your ESP32 device by name
        if (name.contains('nimble') ||
            name.contains('esp32') ||
            name.contains('shutter') ||
            name.contains('bleprph')) {
          _connectToDevice(r.device);
          FlutterBluePlus.stopScan();
          break;
        }
      }
    });

    await Future.delayed(const Duration(seconds: 4));
    if (!_isConnected) {
      setState(() {
        _isScanning = false;
        _statusText = 'No device found';
      });
    }
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    try {
      await device.connect(license: License.free);
      setState(() {
        _connectedDevice = device;
        _isConnected = true;
        _isScanning = false;
        _statusText = 'Connected to ${device.platformName}';
      });

      // Discover services
      List<BluetoothService> services = await device.discoverServices();
      for (var service in services) {
        for (var char in service.characteristics) {
          if (char.properties.write) {
            _characteristic = char;
            break;
          }
        }
      }
    } catch (e) {
      setState(() {
        _isConnected = false;
        _isScanning = false;
        _statusText = 'Connection failed';
      });
    }
  }

  Future<void> _disconnect() async {
    await _connectedDevice?.disconnect();
    setState(() {
      _connectedDevice = null;
      _isConnected = false;
      _characteristic = null;
      _statusText = 'Disconnected';
    });
  }

  Future<void> _sendCommand(List<int> command) async {
    if (_characteristic != null) {
      await _characteristic!.write(command);
    }
  }

  void _onUpPressed() {
    _upArrowController.forward().then((_) => _upArrowController.reverse());
    _sendCommand([0x01]); // Command for UP
  }

  void _onDownPressed() {
    _downArrowController.forward().then((_) => _downArrowController.reverse());
    _sendCommand([0x02]); // Command for DOWN
  }

  void _onStopPressed() {
    _sendCommand([0x00]); // Command for STOP
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildStatusCard(),
            const Spacer(),
            _buildControlPanel(),
            const Spacer(),
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SHUTTER',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 4,
                  foreground: Paint()
                    ..shader = const LinearGradient(
                      colors: [Color(0xFF6366F1), Color(0xFF22D3EE)],
                    ).createShader(const Rect.fromLTWH(0, 0, 150, 30)),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Smart Control',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
          _buildConnectionButton(),
        ],
      ),
    );
  }

  Widget _buildConnectionButton() {
    return GestureDetector(
      onTap: _isConnected ? _disconnect : _startScan,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          gradient: _isConnected
              ? const LinearGradient(
                  colors: [Color(0xFF059669), Color(0xFF10B981)],
                )
              : null,
          color: _isConnected ? null : const Color(0xFF27272A),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _isConnected ? Colors.transparent : const Color(0xFF3F3F46),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isScanning)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            else
              Icon(
                _isConnected ? Icons.bluetooth_connected : Icons.bluetooth,
                size: 16,
                color: _isConnected ? Colors.white : const Color(0xFF6366F1),
              ),
            const SizedBox(width: 8),
            Text(
              _isConnected ? 'Connected' : 'Connect',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _isConnected ? Colors.white : Colors.grey[400],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          return Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF18181B),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _isConnected
                    ? Color.lerp(
                        const Color(0xFF059669),
                        const Color(0xFF10B981),
                        _pulseController.value,
                      )!
                    : const Color(0xFF27272A),
                width: 1.5,
              ),
              boxShadow: _isConnected
                  ? [
                      BoxShadow(
                        color: const Color(
                          0xFF10B981,
                        ).withValues(alpha: 0.1 * _pulseController.value),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: _isConnected
                        ? const Color(0xFF059669).withValues(alpha: 0.2)
                        : const Color(0xFF27272A),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    _isConnected ? Icons.sensors : Icons.sensors_off,
                    color: _isConnected
                        ? const Color(0xFF10B981)
                        : Colors.grey[600],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Device Status',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[500],
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _statusText,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isConnected
                        ? const Color(0xFF10B981)
                        : const Color(0xFFEF4444),
                    boxShadow: [
                      BoxShadow(
                        color:
                            (_isConnected
                                    ? const Color(0xFF10B981)
                                    : const Color(0xFFEF4444))
                                .withValues(alpha: 0.5),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildControlPanel() {
    return Column(
      children: [
        // UP Button
        _buildArrowButton(
          icon: Icons.keyboard_arrow_up_rounded,
          label: 'OPEN',
          controller: _upArrowController,
          onPressed: _onUpPressed,
          gradientColors: const [Color(0xFF6366F1), Color(0xFF818CF8)],
          isUp: true,
        ),
        const SizedBox(height: 12),
        // STOP Button
        GestureDetector(
          onTap: _onStopPressed,
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF27272A),
              border: Border.all(color: const Color(0xFF3F3F46), width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 15,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: const Center(
              child: Icon(
                Icons.stop_rounded,
                size: 36,
                color: Color(0xFFFAFAFA),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // DOWN Button
        _buildArrowButton(
          icon: Icons.keyboard_arrow_down_rounded,
          label: 'CLOSE',
          controller: _downArrowController,
          onPressed: _onDownPressed,
          gradientColors: const [Color(0xFF22D3EE), Color(0xFF06B6D4)],
          isUp: false,
        ),
      ],
    );
  }

  Widget _buildArrowButton({
    required IconData icon,
    required String label,
    required AnimationController controller,
    required VoidCallback onPressed,
    required List<Color> gradientColors,
    bool isUp = true,
  }) {
    return GestureDetector(
      onTap: _isConnected ? onPressed : null,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, child) {
          final scale = 1.0 - (controller.value * 0.1);
          return Transform.scale(
            scale: scale,
            child: SizedBox(
              width: 160,
              height: 120,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Outer glow
                  if (_isConnected)
                    Positioned(
                      top: isUp ? null : 20,
                      bottom: isUp ? 20 : null,
                      child: Container(
                        width: 80,
                        height: 40,
                        decoration: BoxDecoration(
                          boxShadow: [
                            BoxShadow(
                              color: gradientColors[0].withValues(alpha: 0.6),
                              blurRadius: 40,
                              spreadRadius: 10,
                            ),
                          ],
                        ),
                      ),
                    ),
                  // Arrow shape
                  CustomPaint(
                    size: const Size(160, 100),
                    painter: ArrowPainter(
                      isUp: isUp,
                      gradientColors: _isConnected
                          ? gradientColors
                          : [const Color(0xFF27272A), const Color(0xFF3F3F46)],
                      glowOpacity: _isConnected ? 0.3 : 0,
                    ),
                  ),
                  // Label
                  Positioned(
                    bottom: isUp ? 15 : null,
                    top: isUp ? null : 15,
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 3,
                        color: _isConnected
                            ? Colors.white.withValues(alpha: 0.9)
                            : Colors.grey[600],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBottomBar() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildBottomNavItem(Icons.home_rounded, 'Home', true),
          _buildBottomNavItem(Icons.schedule_rounded, 'Schedule', false),
          _buildBottomNavItem(Icons.settings_rounded, 'Settings', false),
        ],
      ),
    );
  }

  Widget _buildBottomNavItem(IconData icon, String label, bool isActive) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isActive
                ? const Color(0xFF6366F1).withValues(alpha: 0.2)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            icon,
            size: 24,
            color: isActive ? const Color(0xFF818CF8) : Colors.grey[600],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
            color: isActive ? const Color(0xFF818CF8) : Colors.grey[600],
          ),
        ),
      ],
    );
  }
}

class ArrowPainter extends CustomPainter {
  final bool isUp;
  final List<Color> gradientColors;
  final double glowOpacity;

  ArrowPainter({
    required this.isUp,
    required this.gradientColors,
    required this.glowOpacity,
  });

  // @override
  // void paint(Canvas canvas, Size size) {
  //   final paint = Paint()
  //     ..shader = LinearGradient(
  //       begin: isUp ? Alignment.bottomCenter : Alignment.topCenter,
  //       end: isUp ? Alignment.topCenter : Alignment.bottomCenter,
  //       colors: gradientColors,
  //     ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

  //   final path = Path();

  //   if (isUp) {
  //     // Chevron pointing up
  //     path.moveTo(size.width * 0.5, 0);
  //     path.lineTo(size.width * 0.85, size.height * 0.45);
  //     path.lineTo(size.width * 0.65, size.height * 0.45);
  //     path.lineTo(size.width * 0.65, size.height * 0.75);
  //     path.lineTo(size.width * 0.35, size.height * 0.75);
  //     path.lineTo(size.width * 0.35, size.height * 0.45);
  //     path.lineTo(size.width * 0.15, size.height * 0.45);
  //     path.close();
  //   } else {
  //     // Chevron pointing down
  //     path.moveTo(size.width * 0.35, size.height * 0.25);
  //     path.lineTo(size.width * 0.65, size.height * 0.25);
  //     path.lineTo(size.width * 0.65, size.height * 0.55);
  //     path.lineTo(size.width * 0.85, size.height * 0.55);
  //     path.lineTo(size.width * 0.5, size.height);
  //     path.lineTo(size.width * 0.15, size.height * 0.55);
  //     path.lineTo(size.width * 0.35, size.height * 0.55);
  //     path.close();
  //   }

  //   // Draw shadow/glow
  //   if (glowOpacity > 0) {
  //     canvas.drawShadow(path, gradientColors[0], 15, false);
  //   }

  //   canvas.drawPath(path, paint);

  //   // Add edge highlight
  //   final highlightPaint = Paint()
  //     ..style = PaintingStyle.stroke
  //     ..strokeWidth = 1.5
  //     ..shader = LinearGradient(
  //       begin: isUp ? Alignment.bottomCenter : Alignment.topCenter,
  //       end: isUp ? Alignment.topCenter : Alignment.bottomCenter,
  //       colors: [
  //         Colors.white.withValues(alpha: 0.3),
  //         Colors.white.withValues(alpha: 0.0),
  //       ],
  //     ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

  //   canvas.drawPath(path, highlightPaint);
  // }

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();

    if (isUp) {
      path.moveTo(size.width * 0.5, 0);
      path.lineTo(size.width * 0.85, size.height * 0.45);
      path.lineTo(size.width * 0.65, size.height * 0.45);
      path.lineTo(size.width * 0.65, size.height * 0.75);
      path.lineTo(size.width * 0.35, size.height * 0.75);
      path.lineTo(size.width * 0.35, size.height * 0.45);
      path.lineTo(size.width * 0.15, size.height * 0.45);
      path.close();
    } else {
      path.moveTo(size.width * 0.35, size.height * 0.25);
      path.lineTo(size.width * 0.65, size.height * 0.25);
      path.lineTo(size.width * 0.65, size.height * 0.55);
      path.lineTo(size.width * 0.85, size.height * 0.55);
      path.lineTo(size.width * 0.5, size.height);
      path.lineTo(size.width * 0.15, size.height * 0.55);
      path.lineTo(size.width * 0.35, size.height * 0.55);
      path.close();
    }

    // Soft blur shadow layers
    for (int i = 3; i >= 0; i--) {
      final shadowPaint = Paint()
        ..color = gradientColors[0].withValues(alpha: 0.08 * (4 - i))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 12.0 + (i * 6));
      canvas.drawPath(path, shadowPaint);
    }

    // Inner soft glow
    final innerGlowPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20);
    canvas.drawPath(path, innerGlowPaint);

    // Main gradient fill
    final paint = Paint()
      ..shader = LinearGradient(
        begin: isUp ? Alignment.bottomCenter : Alignment.topCenter,
        end: isUp ? Alignment.topCenter : Alignment.bottomCenter,
        colors: gradientColors,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(path, paint);

    // Edge highlight
    final highlightPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..shader = LinearGradient(
        begin: isUp ? Alignment.bottomCenter : Alignment.topCenter,
        end: isUp ? Alignment.topCenter : Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: 0.4),
          Colors.white.withValues(alpha: 0.1),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(path, highlightPaint);
  }

  @override
  bool shouldRepaint(covariant ArrowPainter oldDelegate) {
    return oldDelegate.gradientColors != gradientColors ||
        oldDelegate.glowOpacity != glowOpacity;
  }
}
