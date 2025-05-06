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
import 'dart:async';
import 'dart:math';
import 'showFriends.dart';
import 'profile_page.dart';
import 'package:audio_waveforms/audio_waveforms.dart';

class VoiceScreen extends StatefulWidget {
  final User user;
  const VoiceScreen({super.key, required this.user});
  @override
  _VoiceScreenState createState() => _VoiceScreenState();
}

class _VoiceScreenState extends State<VoiceScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  late RecorderController _recorderController;
  late PlayerController _playerController;
  final FlutterSoundPlayer _player = FlutterSoundPlayer();
  String? _filePath;
  bool _isRecording = false;
  String? _currentlyPlayingId;
  bool _isPlaying = false;
  final TextEditingController _friendEmailController = TextEditingController();
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<double> _waveformData = List.filled(60, 0.0);
  double _maxAmplitude = 0.0;
  Timer? _recordingTimer;
  final Random _random = Random();

  // Map lưu trữ dữ liệu sóng âm cho mỗi tin nhắn
  final Map<String, List<double>> _messageWaveforms = {};

  @override
  void initState() {
    super.initState();
    _initRecorder();
    _initPlayer();
    _saveUserInfo();

    // Khởi tạo recorder controller với các thiết lập cho dạng sóng
    _recorderController =
        RecorderController()
          ..androidEncoder = AndroidEncoder.aac
          ..androidOutputFormat = AndroidOutputFormat.mpeg4
          ..iosEncoder = IosEncoder.kAudioFormatMPEG4AAC
          ..sampleRate = 16000
          ..bitRate = 64000; // Tăng bit rate để chất lượng tốt hơn

    // Khởi tạo player controller
    _playerController = PlayerController();
  }

  // Cập nhật biên độ âm thanh từ microphone
  void _updateAmplitude(double amplitude) {
    if (mounted && _isRecording) {
      setState(() {
        // Chuẩn hóa biên độ thành giá trị từ 0.0 đến 1.0
        double normalizedAmp = min(1.0, amplitude / 120);

        // Cập nhật giá trị cao nhất để làm mốc tham chiếu
        _maxAmplitude = max(_maxAmplitude, normalizedAmp);

        // Di chuyển tất cả các giá trị sang trái
        for (int i = 0; i < _waveformData.length - 1; i++) {
          _waveformData[i] = _waveformData[i + 1];
        }

        // Thêm giá trị mới vào cuối
        _waveformData[_waveformData.length - 1] = normalizedAmp;
      });
    }
  }

  Future<void> _initPlayer() async {
    await _player.openPlayer();

    _player.onProgress!.listen((e) {
      if (e != null && e.duration.inMilliseconds > 0) {
        if (e.position.inMilliseconds >= e.duration.inMilliseconds - 100) {
          if (mounted) {
            setState(() {
              _currentlyPlayingId = null;
              _isPlaying = false;
            });
          }
        }
      }
    });
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
      _showSnackBar("Vui lòng nhập email");
      return;
    }
    try {
      QuerySnapshot query =
          await _firestore
              .collection('users')
              .where('email', isEqualTo: friendEmail)
              .get();

      if (query.docs.isEmpty) {
        _showSnackBar("Không tìm thấy người dùng với email này");
        return;
      }
      String friendId = query.docs.first.id;
      if (friendId == widget.user.uid) {
        _showSnackBar("Không thể kết bạn với chính mình");
        return;
      }

      // Kiểm tra xem đã có mối quan hệ chưa
      QuerySnapshot existing =
          await _firestore
              .collection('friendships')
              .where('user1', isEqualTo: widget.user.uid)
              .where('user2', isEqualTo: friendId)
              .get();

      if (existing.docs.isNotEmpty) {
        _showSnackBar("Đã gửi yêu cầu hoặc đã là bạn");
        return;
      }

      // Tạo yêu cầu kết bạn
      await _firestore.collection('friendships').add({
        'user1': widget.user.uid,
        'user2': friendId,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });

      _showSnackBar("Đã gửi yêu cầu kết bạn");

      _friendEmailController.clear();
    } catch (e) {
      _showSnackBar("Lỗi khi gửi yêu cầu: $e");
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _initRecorder() async {
    await _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    var status = await Permission.microphone.status;
    if (!status.isGranted) {
      status = await Permission.microphone.request();
      if (!status.isGranted) {
        _showSnackBar("Cần quyền micro để ghi âm!");
      }
    }
  }

  // Widget hiển thị dãy sóng âm khi ghi âm
  Widget _buildWaveform() {
    if (!_isRecording) {
      return const SizedBox.shrink();
    }

    return Container(
      height: 120,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: AudioWaveforms(
        enableGesture: false,
        size: Size(MediaQuery.of(context).size.width, 120),
        recorderController: _recorderController,
        waveStyle: const WaveStyle(
          waveColor: Colors.blue,
          extendWaveform: true,
          showMiddleLine: false,
          spacing: 5.0,
          waveThickness: 3.5,
          showDurationLabel: true,
          durationLinesColor: Colors.grey,
          durationStyle: TextStyle(color: Colors.white, fontSize: 14),
        ),
        padding: const EdgeInsets.only(left: 18),
        margin: const EdgeInsets.symmetric(horizontal: 15),
      ),
    );
  }

  Future<void> _startRecording() async {
    if (await Permission.microphone.isGranted) {
      Directory dir = await getApplicationDocumentsDirectory();
      _filePath =
          '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.aac';
      _maxAmplitude = 0.0;

      await _recorderController.record(path: _filePath);

      setState(() => _isRecording = true);
      Future.delayed(Duration(seconds: 30), () {
        if (_isRecording) _stopRecording();
      });
    } else {
      await _requestPermissions();
    }
  }

  Future<void> _stopRecording() async {
    final path = await _recorderController.stop();

    setState(() => _isRecording = false);
    if (path != null) {
      _filePath = path;
      _showFriendSelection();
    }
  }

  void _showFriendSelection() {
    showDialog(
      context: context,
      builder:
          (context) => FriendSelectionDialog(
            userId: widget.user.uid,
            firestore: _firestore,
            onSend: _sendAudioMessage,
          ),
    );
  }

  Future<void> _sendAudioMessage(List<String> friendIds) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => const Dialog(
            child: Padding(
              padding: EdgeInsets.all(20.0),
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

    try {
      if (_filePath == null) return;
      String messageId = _firestore.collection('messages').doc().id;
      String storePath = 'audio/$messageId/voice.aac';
      File file = File(_filePath!);
      UploadTask task = _storage.ref(storePath).putFile(file);
      TaskSnapshot snapshot = await task;
      String audioURL = await snapshot.ref.getDownloadURL();

      // Gửi song song tin nhắn cho tất cả bạn bè
      await Future.wait(
        friendIds.map((friendId) {
          return _firestore.collection('messages').add({
            'senderId': widget.user.uid,
            'receiverId': friendId,
            'audioURL': audioURL,
            'timestamp': FieldValue.serverTimestamp(),
          });
        }),
      );

      _showSnackBar("Gửi thành công");
    } catch (e) {
      _showSnackBar("Lỗi khi gửi tin nhắn: $e");
    } finally {
      // Đóng các dialog
      Navigator.pop(context); // Đóng loading
      Navigator.pop(context); // Đóng dialog chọn bạn bè
    }
  }

  Future<void> _playMessage(String messageId, String audioURL) async {
    if (_currentlyPlayingId == messageId) {
      await _player.stopPlayer();
      setState(() {
        _currentlyPlayingId = null;
        _isPlaying = false;
      });
      return;
    }
    if (_currentlyPlayingId != null) {
      await _player.stopPlayer();
    }

    // Phát tin nhắn mới
    try {
      await _player.startPlayer(
        fromURI: audioURL,
        whenFinished: () {
          // Cập nhật khi phát xong
          if (mounted) {
            setState(() {
              _currentlyPlayingId = null;
              _isPlaying = false;
            });
          }
        },
      );
      setState(() {
        _currentlyPlayingId = messageId;
        _isPlaying = true;
      });
    } catch (e) {
      _showSnackBar("Lỗi phát tin nhắn: $e");
    }
  }

  // Phân tách UI thành các widget nhỏ hơn
  Widget _buildAddFriendSection() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _friendEmailController,
              decoration: const InputDecoration(
                labelText: "Nhập email bạn bè",
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 8.0),
          ElevatedButton(
            onPressed: () => _addFriend(_friendEmailController.text.trim()),
            child: const Text("Thêm bạn"),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordButton() {
    return Column(
      children: [
        // Hiển thị dạng sóng âm nếu đang ghi âm
        _buildWaveform(),
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _isRecording ? Colors.red : Colors.blue,
              shape: const CircleBorder(),
              padding: const EdgeInsets.all(24),
            ),
            onPressed: _isRecording ? _stopRecording : _startRecording,
            child: Icon(
              _isRecording ? Icons.stop : Icons.mic,
              size: 32,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  // Widget mới để hiển thị tin nhắn dạng thẻ lật
  Widget _buildCardSwiper() {
    return Expanded(
      child: StreamBuilder<QuerySnapshot>(
        stream:
            _firestore
                .collection('messages')
                .where('receiverId', isEqualTo: widget.user.uid)
                .orderBy('timestamp', descending: true)
                .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text("Lỗi: ${snapshot.error}"));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          List<DocumentSnapshot> messages = snapshot.data!.docs;
          if (messages.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.message_outlined,
                    size: 80,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    "Chưa có tin nhắn nào",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "Bạn hãy ghi âm và gửi cho bạn bè nhé",
                    style: TextStyle(fontSize: 14),
                  ),
                ],
              ),
            );
          }

          return Column(
            children: [
              // Khu vực thẻ lật
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  onPageChanged: (index) {
                    setState(() {
                      _currentPage = index;

                      // Dừng phát khi lật trang
                      if (_isPlaying) {
                        _player.stopPlayer();
                        _currentlyPlayingId = null;
                        _isPlaying = false;
                      }
                    });
                  },
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    var message =
                        messages[index].data() as Map<String, dynamic>;
                    String messageId = messages[index].id;
                    String senderId = message['senderId'];
                    String audioURL = message['audioURL'];
                    bool isPlaying = _currentlyPlayingId == messageId;

                    return FutureBuilder<DocumentSnapshot>(
                      future:
                          _firestore.collection('users').doc(senderId).get(),
                      builder: (context, userSnapshot) {
                        if (!userSnapshot.hasData) {
                          return _buildLoadingVoiceCard();
                        }

                        var senderData =
                            userSnapshot.data!.data() as Map<String, dynamic>;
                        String senderName =
                            senderData['displayName'] ?? 'Không tên';
                        String senderPhoto = senderData['photoURL'] ?? '';

                        return _buildVoiceCard(
                          senderName,
                          senderPhoto,
                          messageId,
                          audioURL,
                          isPlaying,
                        );
                      },
                    );
                  },
                ),
              ),

              // Thanh điều hướng
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios),
                      onPressed:
                          _currentPage > 0
                              ? () {
                                _pageController.previousPage(
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeInOut,
                                );
                              }
                              : null,
                    ),
                    const SizedBox(width: 32),
                    IconButton(
                      icon: const Icon(Icons.arrow_forward_ios),
                      onPressed:
                          _currentPage < messages.length - 1
                              ? () {
                                _pageController.nextPage(
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeInOut,
                                );
                              }
                              : null,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildLoadingVoiceCard() {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: const Center(child: CircularProgressIndicator()),
    );
  }

  // Widget thẻ âm thanh với sóng âm
  Widget _buildVoiceCard(
    String senderName,
    String senderPhoto,
    String messageId,
    String audioURL,
    bool isPlaying,
  ) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.blue.shade50, Colors.blue.shade100],
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Tên người gửi
            Text(
              senderName,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),

            // Avatar người gửi
            CircleAvatar(
              radius: 40,
              backgroundColor: Colors.white,
              backgroundImage:
                  senderPhoto.isNotEmpty ? NetworkImage(senderPhoto) : null,
              child:
                  senderPhoto.isEmpty
                      ? const Icon(Icons.person, size: 40)
                      : null,
            ),
            const SizedBox(height: 24),

            // Khu vực hiển thị sóng âm và nút phát căn giữa
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: GestureDetector(
                onTap: () => _playMessage(messageId, audioURL),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center, // Căn giữa
                  children: [
                    // Nút phát
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isPlaying ? Colors.red : Colors.blue,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 5,
                            offset: Offset(0, 3),
                          ),
                        ],
                      ),
                      child: IconButton(
                        icon: Icon(
                          isPlaying ? Icons.pause : Icons.play_arrow,
                          size: 32,
                          color: Colors.white,
                        ),
                        onPressed: () => _playMessage(messageId, audioURL),
                      ),
                    ),
                    const SizedBox(width: 16),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
              backgroundColor: Colors.grey[300],
              backgroundImage:
                  widget.user.photoURL != null
                      ? NetworkImage(widget.user.photoURL!)
                      : null,
              radius: 16,
              child:
                  widget.user.photoURL == null
                      ? const Icon(Icons.person)
                      : null,
            ),
          ),
        ),
        title: Text("Voicer - ${widget.user.displayName ?? 'Không tên'}"),
        actions: [
          IconButton(
            icon: const Icon(Icons.people),
            onPressed:
                () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder:
                        (context) => FriendListWidget(
                          userId: widget.user.uid,
                          firestore: _firestore,
                        ),
                  ),
                ),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildAddFriendSection(),
          _buildRecordButton(),
          _buildCardSwiper(),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _recorderController.dispose();
    _player.closePlayer();
    _friendEmailController.dispose();
    _pageController.dispose();
    super.dispose();
  }
}

// Class vẽ dạng sóng âm
class WaveformPainter extends CustomPainter {
  final List<double> waveformData;
  final Color color;
  final Gradient? gradient;

  WaveformPainter({
    required this.waveformData,
    required this.color,
    this.gradient,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = color
          ..style = PaintingStyle.fill;

    if (gradient != null) {
      paint.shader = gradient!.createShader(
        Rect.fromLTWH(0, 0, size.width, size.height),
      );
    }

    final width = size.width / waveformData.length;
    final centerY = size.height / 2;

    for (int i = 0; i < waveformData.length; i++) {
      final x = i * width;
      final barHeight =
          waveformData[i] * size.height * 0.75; // 75% của chiều cao tối đa

      // Vẽ thanh hình chữ nhật cho mỗi điểm dữ liệu
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(x + width / 2, centerY),
            width:
                width *
                0.6, // Chiều rộng thanh bằng 60% khoảng cách giữa các điểm
            height: barHeight,
          ),
          const Radius.circular(4.0),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
