import 'package:flutter/material.dart';
import 'package:parcel_core/parcel_core.dart';

void main() {
  runApp(const ParcelApp());
}

class ParcelApp extends StatelessWidget {
  const ParcelApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: appName,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      ),
      home: const Scaffold(body: Center(child: Text(appName))),
    );
  }
}
