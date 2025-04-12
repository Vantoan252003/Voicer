import 'package:flutter/material.dart';
import 'voice.dart';
import 'loginPage.dart';
void main(){
  runApp(Voicer());
}
class Voicer extends StatelessWidget{
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: LoginPage(),
    );
  }
}