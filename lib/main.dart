import "package:flutter/material.dart";

void main() {
  runApp(const IApp());
}

class IApp extends StatelessWidget {
  const IApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "I",
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text(
            "i",
            style: TextStyle(
              fontSize: 64,
              color: Colors.white,
              fontWeight: FontWeight.w200,
              letterSpacing: 8,
            ),
          ),
        ),
      ),
    );
  }
}
