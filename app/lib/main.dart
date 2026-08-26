import 'package:flutter/material.dart';

import 'screens/scan_screen.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TelepoleApp());
}

class TelepoleApp extends StatelessWidget {
  const TelepoleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Telepole Survey Meter',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(),
      home: const ScanScreen(),
    );
  }
}
