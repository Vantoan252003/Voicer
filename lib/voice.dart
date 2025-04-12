import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'dart:io';

class VoiceScreen extends StatefulWidget {
  final User user; // Nhận thông tin người dùng
  final bool showLoginSuccess; // Cờ để hiển thị thông báo

  VoiceScreen({required this.user, this.showLoginSuccess = false});

  @override
  _VoiceScreenState createState() => _VoiceScreenState();
}

class _VoiceScreenState extends State<VoiceScreen> {
  FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  FlutterSoundPlayer _player = FlutterSoundPlayer();
  String? _filePath;
  bool _isRecording = false;
  List<Map<String, String>> _friends = [
    {'name': 'Minh Bò tuôi', 'id': '1'},
    {'name': 'Lan', 'id': '2'},
    {'name': 'Hùng', 'id': '3'},
  ];
  List<Map<String, dynamic>> _messages = [];

  @override
  void initState() {
    super.initState();
    _initRecorder();
    _player.openPlayer();

    // Hiển thị thông báo đăng nhập thành công
    if (widget.showLoginSuccess) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Đã đăng nhập thành công!")),
        );
      });
    }
  }

  Future<void> _initRecorder() async {
    await _recorder.openRecorder();
    await _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    var status = await Permission.microphone.status;
    if (!status.isGranted) {
      status = await Permission.microphone.request();
      if (!status.isGranted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Cần quyền micro để ghi âm!")),
        );
      }
    }
  }

  Future<void> _startRecording() async {
    if (await Permission.microphone.isGranted) {
      Directory dir = await getApplicationDocumentsDirectory();
      _filePath = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.aac';
      await _recorder.startRecorder(
        toFile: _filePath,
        codec: Codec.aacADTS,
      );
      setState(() => _isRecording = true);
      Future.delayed(Duration(seconds: 10), () {
        if (_isRecording) _stopRecording();
      });
    } else {
      await _requestPermissions();
    }
  }

  Future<void> _stopRecording() async {
    await _recorder.stopRecorder();
    setState(() => _isRecording = false);
    if (_filePath != null) {
      _showFriendSelection();
    }
  }

  void _showFriendSelection() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Gửi cho ai?"),
        content: SingleChildScrollView(
          child: Column(
            children: _friends.map((friend) {
              return ListTile(
                title: Text(friend['name']!),
                onTap: () {
                  _sendMessage(friend['id']!);
                  Navigator.pop(context);
                },
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  void _sendMessage(String friendId) {
    setState(() {
      _messages.add({
        'sender': widget.user.displayName ?? 'Tôi', // Dùng tên người dùng
        'receiverId': friendId,
        'filePath': _filePath!,
      });
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Đã gửi cho ${_friends.firstWhere((f) => f['id'] == friendId)['name']}")),
    );
  }

  Future<void> _playMessage(String path) async {
    await _player.startPlayer(fromURI: path);
  }

  Future<void> _signOut(BuildContext context) async {
    try {
      await FirebaseAuth.instance.signOut();
      await GoogleSignIn().signOut();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Đã đăng xuất")),
      );
    } catch (e) {
      print("Lỗi đăng xuất: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Lỗi đăng xuất: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Nhắn Âm - ${widget.user.displayName ?? 'Người dùng'}"), // Hiển thị tên
        actions: [
          IconButton(
            icon: Icon(Icons.logout),
            onPressed: () => _signOut(context),
            tooltip: "Đăng xuất",
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.all(16.0),
            child: ElevatedButton(
              onPressed: _isRecording ? _stopRecording : _startRecording,
              child: Text(_isRecording ? "Dừng" : "Ghi âm (10s)"),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                String receiverName = _friends
                    .firstWhere((f) => f['id'] == _messages[index]['receiverId'])['name']!;
                return ListTile(
                  title: Text("Gửi tới $receiverName"),
                  subtitle: Text("Từ ${_messages[index]['sender']}"),
                  trailing: IconButton(
                    icon: Icon(Icons.play_arrow),
                    onPressed: () => _playMessage(_messages[index]['filePath']),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _recorder.closeRecorder();
    _player.closePlayer();
    super.dispose();
  }
}