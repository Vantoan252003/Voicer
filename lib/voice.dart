import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:rxdart/rxdart.dart';
import 'dart:io';

class VoiceScreen extends StatefulWidget {
  final User user;
  final bool showLoginSuccess;
  VoiceScreen({required this.user, this.showLoginSuccess = false});

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

  @override
  void initState() {
    super.initState();
    _initRecorder();
    _player.openPlayer();
    _saveUserInfo();

    if (widget.showLoginSuccess) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Đã đăng nhập thành công!")),
        );
      });
    }
  }
  Future<void> _saveUserInfo() async {
    try {
      await _firestore.collection('users').doc(widget.user.uid).set({
        'displayName': widget.user.displayName,
        'email': widget.user.email,
        'photoURL': widget.user.photoURL,
      }, SetOptions(merge: true));
    }
    catch(e){
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Loi lưu thông tin người dùng: $e")),
      );
    }
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
      builder: (context) => AlertDialog(
        title: Text("Gửi cho ai?"),
        content: StreamBuilder<List<QuerySnapshot>>(
          stream: CombineLatestStream.list([
            _firestore
                .collection('friendships')
                .where('user1', isEqualTo: widget.user.uid)
                .where('status', isEqualTo: 'accepted')
                .snapshots(),
            _firestore
                .collection('friendships')
                .where('user2', isEqualTo: widget.user.uid)
                .where('status', isEqualTo: 'accepted')
                .snapshots(),
          ]),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Text("Lỗi: ${snapshot.error}");
            }
            if (!snapshot.hasData) {
              return Center(child: CircularProgressIndicator());
            }

            List<DocumentSnapshot> docs = [];
            for (var querySnapshot in snapshot.data!) {
              docs.addAll(querySnapshot.docs);
            }

            if (docs.isEmpty) {
              return Text("Bạn chưa có bạn bè nào!");
            }

            return SingleChildScrollView(
              child: Column(
                children: docs.map((doc) {
                  String friendId = doc['user1'] == widget.user.uid
                      ? doc['user2']
                      : doc['user1'];
                  return FutureBuilder<DocumentSnapshot>(
                    future: _firestore.collection('users').doc(friendId).get(),
                    builder: (context, userSnapshot) {
                      if (!userSnapshot.hasData) {
                        return ListTile(title: Text("Đang tải..."));
                      }
                      var friendData = userSnapshot.data!.data() as Map<String, dynamic>;
                      return ListTile(
                        title: Text(friendData['displayName'] ?? 'Không tên'),
                        onTap: () {
                          _sendMessage(friendId);
                          Navigator.pop(context);
                        },
                      );
                    },
                  );
                }).toList(),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _sendMessage(String friendId) async {
    if (_filePath == null) return;
    try {
      String messageId = _firestore.collection('messages').doc().id;
      String storePath = 'audio/$messageId/voice.aac';
      File file = File(_filePath!);
      UploadTask task = _storage.ref(storePath).putFile(file);
      TaskSnapshot snapshot = await task;
      String audioURL = await snapshot.ref.getDownloadURL();
      await _firestore.collection('messages').doc(messageId).set({
        'senderId': widget.user.uid,
        'receiverId': friendId,
        'audioURL': audioURL,
        'timestamp': FieldValue.serverTimestamp(),
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Gửi thành công")),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Lỗi khi gửi tin nhắn: $e")),
      );
    }
  }

  Future<void> _playMessage(String audioURL) async {
    try {
      await _player.startPlayer(fromURI: audioURL);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Lỗi khi phát: $e")),
      );
    }
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
        title: Text("Nhắn Âm - ${widget.user.displayName ?? 'Người dùng'}"),
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
          // Phần hiển thị danh sách bạn bè
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "Danh sách bạn bè",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          SizedBox(
            height: 100,
            child: StreamBuilder<List<QuerySnapshot>>(
              stream: CombineLatestStream.list([
                _firestore
                    .collection('friendships')
                    .where('user1', isEqualTo: widget.user.uid)
                    .where('status', isEqualTo: 'accepted')
                    .snapshots(),
                _firestore
                    .collection('friendships')
                    .where('user2', isEqualTo: widget.user.uid)
                    .where('status', isEqualTo: 'accepted')
                    .snapshots(),
              ]),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text("Lỗi: ${snapshot.error}"));
                }
                if (!snapshot.hasData) {
                  return Center(child: CircularProgressIndicator());
                }

                List<DocumentSnapshot> docs = [];
                for (var querySnapshot in snapshot.data!) {
                  docs.addAll(querySnapshot.docs);
                }

                if (docs.isEmpty) {
                  return Center(child: Text("Bạn chưa có bạn bè nào"));
                }

                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    var doc = docs[index];
                    String friendId = doc['user1'] == widget.user.uid
                        ? doc['user2']
                        : doc['user1'];
                    return FutureBuilder<DocumentSnapshot>(
                      future: _firestore.collection('users').doc(friendId).get(),
                      builder: (context, userSnapshot) {
                        if (!userSnapshot.hasData) {
                          return ListTile(title: Text("Đang tải..."));
                        }
                        var friendData = userSnapshot.data!.data() as Map<String, dynamic>;
                        return ListTile(
                          title: Text(friendData['displayName'] ?? 'Không tên'),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
          // Phần hiển thị yêu cầu kết bạn
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "Yêu cầu kết bạn",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          SizedBox(
            height: 100,
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
              child: Text(_isRecording ? "Dừng" : "Ghi âm (10s)"),
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
                            icon: Icon(Icons.play_arrow),
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