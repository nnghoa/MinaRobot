import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/mina_home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const MinaRobotApp());
}

class MinaRobotApp extends StatelessWidget {
  const MinaRobotApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mina Visbot',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: Colors.black,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E5FF),
          secondary: Color(0xFF00F5A0),
        ),
      ),
      home: const MinaHomeScreen(),
    );
  }
}
