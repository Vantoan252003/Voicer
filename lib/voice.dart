import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:voicer/chat.dart';
import 'package:voicer/friend_list.dart';
import 'dart:io';
import 'showFriends.dart';
import 'profile_page.dart';

class VoiceScreen extends StatefulWidget {
  final User user;
  VoiceScreen({required this.user});
  @override
  _VoiceScreenState createState() => _VoiceScreenState();
}

class _VoiceScreenState extends State<VoiceScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  FlutterSoundPlayer _player = FlutterSoundPlayer();
  String? _filePath;
  bool _isRecording = false;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _initRecorder();
    _player.openPlayer();
    _saveUserInfo();

  }
  Future<void> _saveUserInfo() async {
      await _firestore.collection('users').doc(widget.user.uid).set({
        'displayName': widget.user.displayName,
        'email': widget.user.email,
        'photoURL': widget.user.photoURL,
      }, SetOptions(merge: true));

  }
  Future<void> _addFriend(String friendEmail) async {
    if (friendEmail.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Vui lòng nhập email")),
      );
      return;
    }
    try {
      // Tìm người dùng theo email
      QuerySnapshot query = await _firestore
          .collection('users')
          .where('email', isEqualTo: friendEmail)
          .get();

      if (query.docs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Không tìm thấy người dùng với email này")),
        );
        return;
      }
      String friendId = query.docs.first.id;
      if (friendId == widget.user.uid) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Không thể kết bạn với chính mình")),
        );
        return;
      }

      // Kiểm tra xem đã có mối quan hệ chưa
      QuerySnapshot existing = await _firestore
          .collection('friendships')
          .where('user1', isEqualTo: widget.user.uid)
          .where('user2', isEqualTo: friendId)
          .get();

      if (existing.docs.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Đã gửi yêu cầu hoặc đã là bạn")),
        );
        return;
      }

      // Tạo yêu cầu kết bạn
      await _firestore.collection('friendships').add({
        'user1': widget.user.uid,
        'user2': friendId,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Đã gửi yêu cầu kết bạn")),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Lỗi khi gửi yêu cầu: $e")),
      );
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
      builder: (context) => FriendSelectionDialog(
        userId: widget.user.uid,
        firestore: _firestore,
        onSend: (List<String> friendIds) async {
          // Hiển thị dialog loading
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => Dialog(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text("Đang gửi tin nhắn..."),
                  ],
                ),
              ),
            ),
          );
            // Upload file ghi âm 1 lần
            if (_filePath == null) return;
            String messageId = _firestore.collection('messages').doc().id;
            String storePath = 'audio/$messageId/voice.aac';
            File file = File(_filePath!);
            UploadTask task = _storage.ref(storePath).putFile(file);
            TaskSnapshot snapshot = await task;
            String audioURL = await snapshot.ref.getDownloadURL();

            // Gửi song song tin nhắn cho tất cả bạn bè
            await Future.wait(friendIds.map((friendId) {
              return _firestore.collection('messages').add({
                'senderId': widget.user.uid,
                'receiverId': friendId,
                'audioURL': audioURL,
                'timestamp': FieldValue.serverTimestamp(),
              });
            }));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("Gửi thành công")),
            );
            Navigator.pop(context); // Đóng loading
            Navigator.pop(context); // Đóng dialog chọn bạn bè
        },
      ),
    );
  }
  Future<void> _playMessage(String audioURL) async {
    await _player.startPlayer(fromURI: audioURL);
    setState(() => _isPlaying = true);

  }
  Future<void> _acceptFriend(String friendshipId) async {
    try {
      await _firestore.collection('friendships').doc(friendshipId).update({
        'status': 'accepted',
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Đã chấp nhận kết bạn")),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Lỗi khi chấp nhận: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextEditingController friendEmailController = TextEditingController();
    return Scaffold(
      appBar: AppBar(
        leading: GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ProfilePage(user: widget.user),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(5.0),
            child: CircleAvatar(
              //dịch sang phải xíu
              backgroundColor: Colors.grey[300],
              backgroundImage: widget.user.photoURL != null
                  ? NetworkImage(widget.user.photoURL!)
                  : null,
              child: widget.user.photoURL == null
                  ? Icon(Icons.person)
                  : null,
              radius: 16,
            ),
          ),
        ),
        title: Text(" ${widget.user.displayName ?? 'Không tên'}"),
        actions: [
          IconButton(
            icon: Icon(Icons.people),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => FriendListWidget(userId: widget.user.uid, firestore: _firestore))),
          ),
        ],
      ),
      body: Column(
        children: [
          // Phần thêm bạn
          Padding(
            padding: EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: friendEmailController,
                    decoration: InputDecoration(
                      labelText: "Nhập email bạn bè",
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                SizedBox(width: 8.0),
                ElevatedButton(
                  onPressed: () {
                    _addFriend(friendEmailController.text.trim());
                  },
                  child: Text("Thêm bạn"),
                ),
              ],
            ),
          ),
          // Phần hiển thị yêu cầu kết bạn
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "Yêu cầu kết bạn",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          SizedBox(
            height: 80,
            child: StreamBuilder<QuerySnapshot>(
              stream: _firestore
                  .collection('friendships')
                  .where('user2', isEqualTo: widget.user.uid)
                  .where('status', isEqualTo: 'pending')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text("Lỗi: ${snapshot.error}"));
                }
                if (!snapshot.hasData) {
                  return Center(child: CircularProgressIndicator());
                }
                List<DocumentSnapshot> requests = snapshot.data!.docs;
                if (requests.isEmpty) {
                  return Center(child: Text("Không có yêu cầu kết bạn"));
                }
                return ListView.builder(

                  itemCount: requests.length,
                  itemBuilder: (context, index) {
                    var request = requests[index];
                    String senderId = request['user1'];
                    return FutureBuilder<DocumentSnapshot>(
                      future: _firestore.collection('users').doc(senderId).get(),
                      builder: (context, userSnapshot) {
                        if (!userSnapshot.hasData) {
                          return ListTile(title: Text("Đang tải..."));
                        }
                        var senderData = userSnapshot.data!.data() as Map<String, dynamic>;
                        String senderName = senderData['displayName'] ?? 'Không tên';
                        return ListTile(
                          title: Text("Yêu cầu từ $senderName"),
                          trailing: ElevatedButton(
                            onPressed: () => _acceptFriend(request.id),
                            child: Text("Chấp nhận"),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
          // Nút ghi âm
          Padding(
            padding: EdgeInsets.all(16.0),
            child: ElevatedButton(
              onPressed: _isRecording ? _stopRecording : _startRecording,
              child: Icon(_isRecording ? Icons.stop : Icons.mic),
            ),
          ),
          // Danh sách tin nhắn
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _firestore
                  .collection('messages')
                  .where('receiverId', isEqualTo: widget.user.uid)
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text("Lỗi: ${snapshot.error}"));
                }
                if (!snapshot.hasData) {
                  return Center(child: CircularProgressIndicator());
                }
                List<DocumentSnapshot> messages = snapshot.data!.docs;
                if (messages.isEmpty) {
                  return Center(child: Text("Chưa có tin nhắn nào"));
                }
                return ListView.builder(
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    var message = messages[index].data() as Map<String, dynamic>;
                    String senderId = message['senderId'];
                    String audioURL = message['audioURL'];
                    return FutureBuilder<DocumentSnapshot>(
                      future: _firestore.collection('users').doc(senderId).get(),
                      builder: (context, userSnapshot) {
                        if (!userSnapshot.hasData) {
                          return ListTile(title: Text("Đang tải..."));
                        }
                        var senderData = userSnapshot.data!.data() as Map<String, dynamic>;
                        String senderName = senderData['displayName'] ?? 'Không tên';
                        return ListTile(
                          title: Text("Từ $senderName"),
                          subtitle: Text("Tin nhắn âm thanh"),
                          trailing: IconButton(
                            icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                            onPressed: () => _playMessage(audioURL),
                          ),
                        );
                      },
                    );
                  },
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