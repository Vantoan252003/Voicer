import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

class ChatScreen extends StatefulWidget {
  final String currentUserId;
  final String friendId;
  final String friendName;
  final String? friendPhotoURL;

  const ChatScreen({
    super.key,
    required this.currentUserId,
    required this.friendId,
    required this.friendName,
    this.friendPhotoURL,
  });

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;

  // Tạo chatId từ userId và friendId - luôn tạo ID giống nhau cho cùng 1 cặp users
  String getChatId() {
    List<String> ids = [widget.currentUserId, widget.friendId];
    ids.sort(); // Sắp xếp để đảm bảo thứ tự luôn nhất quán
    return ids.join('_');
  }

  void _sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    final String chatId = getChatId();

    setState(() {
      _isLoading = true;
    });

    try {
      await _firestore.collection('messagesChat').add({
        'chatId': chatId,
        'senderId': widget.currentUserId,
        'receiverId': widget.friendId,
        'text': text,
        'timestamp': FieldValue.serverTimestamp(),
      });

      _textController.clear();

      // Cuộn xuống tin nhắn mới nhất
      Future.delayed(Duration(milliseconds: 100), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            0,
            duration: Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Lỗi khi gửi tin nhắn: $e')));
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final String chatId = getChatId();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              backgroundImage:
                  widget.friendPhotoURL != null
                      ? NetworkImage(widget.friendPhotoURL!)
                      : null,
              radius: 18,
              child: widget.friendPhotoURL == null ? Icon(Icons.person) : null,
            ),
            SizedBox(width: 8),
            Text(widget.friendName),
          ],
        ),
      ),
      body: Column(
        children: [
          // Danh sách tin nhắn
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream:
                  _firestore
                      .collection('messagesChat')
                      .where('chatId', isEqualTo: chatId)
                      .orderBy('timestamp', descending: true)
                      .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text('Đã xảy ra lỗi: ${snapshot.error}'),
                  );
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(child: Text('Chưa có tin nhắn nào'));
                }

                var messages = snapshot.data!.docs;

                return ListView.builder(
                  controller: _scrollController,
                  reverse: true, // Hiển thị tin nhắn mới nhất ở dưới cùng
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    var message =
                        messages[index].data() as Map<String, dynamic>;
                    bool isMe = message['senderId'] == widget.currentUserId;

                    return Padding(
                      padding: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                      child: Align(
                        alignment:
                            isMe ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          decoration: BoxDecoration(
                            color: isMe ? Colors.blue[100] : Colors.grey[200],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: EdgeInsets.symmetric(
                            vertical: 12,
                            horizontal: 12,
                          ),
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.7,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                message['text'] ?? '',
                                style: TextStyle(fontSize: 16),
                              ),
                              SizedBox(height: 4),
                              Text(
                                message['timestamp'] != null
                                    ? _formatTimestamp(message['timestamp'])
                                    : 'Đang gửi...',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),

          // Phần nhập tin nhắn
          Container(
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  offset: Offset(0, -2),
                  blurRadius: 4,
                  color: Colors.black.withOpacity(0.1),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    decoration: InputDecoration(
                      hintText: 'Nhập tin nhắn...',
                      border: InputBorder.none,
                    ),
                    onSubmitted: _isLoading ? null : _sendMessage,
                  ),
                ),
                IconButton(
                  icon:
                      _isLoading
                          ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : Icon(Icons.send),
                  onPressed:
                      _isLoading
                          ? null
                          : () => _sendMessage(_textController.text),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(Timestamp timestamp) {
    DateTime dateTime = timestamp.toDate();
    DateTime now = DateTime.now();

    if (now.difference(dateTime).inHours < 24 && now.day == dateTime.day) {
      return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    } else {
      return '${dateTime.day}/${dateTime.month} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}
