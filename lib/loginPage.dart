import 'package:flutter/material.dart';
import 'voice.dart';

class LoginPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Đăng nhập")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text("Vui lòng đăng nhập để sử dụng"),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => VoiceScreen()),
                );
              },
              child: Text("Đăng nhập"),
            ),
          ],
        ),
      ),
    );
  }
}
