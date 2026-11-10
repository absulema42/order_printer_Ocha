import 'package:flutter/material.dart';

import 'app_state.dart';
import 'models.dart';
import 'screens/order_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final app = AppState();
  await app.load();
  runApp(OrderPrinterApp(app: app));
}

class OrderPrinterApp extends StatelessWidget {
  final AppState app;
  const OrderPrinterApp({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF2E7D32); // Thai green
    return MaterialApp(
      title: defaultRestaurantName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seed),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme:
            ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark),
        useMaterial3: true,
      ),
      home: OrderScreen(app: app),
    );
  }
}
