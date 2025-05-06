import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:rxdart/rxdart.dart';

class FriendRequest extends StatefulWidget {
  final String userId;
  final FirebaseFirestore firestore;
  const FriendRequest({
    super.key,
    required this.userId,
    required this.firestore,
  });

  @override
  _FriendRequestState createState() => _FriendRequestState();
}

class _FriendRequestState extends State<FriendRequest> {
  Future<void> _acceptFriend(String requestId) async {
    await widget.firestore.collection('friendships').doc(requestId).update({
      'status': 'accepted',
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text("Đã chấp nhận lời mời kết bạn")));
  }

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Danh sách lời mời kết bạn")),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "Yêu cầu kết bạn",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          SizedBox(
            height: 90,
            child: StreamBuilder<QuerySnapshot>(
              stream:
                  _firestore
                      .collection('friendships')
                      .where('user2', isEqualTo: widget.userId)
                      .where('status', isEqualTo: 'pending')
                      .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return Center(child: CircularProgressIndicator());
                }
                List<DocumentSnapshot> docs = snapshot.data!.docs;
                if (docs.isEmpty) {
                  return Center(child: Text("Không có yêu cầu kết bạn"));
                }
                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    var request = docs[index];
                    String senderId = request['user1'];
                    return FutureBuilder<DocumentSnapshot>(
                      future:
                          _firestore.collection('users').doc(senderId).get(),
                      builder: (context, userSnapshot) {
                        if (!userSnapshot.hasData) {
                          return ListTile(title: Text("Đang tải..."));
                        }
                        var senderData =
                            userSnapshot.data!.data() as Map<String, dynamic>;
                        String senderName =
                            senderData['displayName'] ?? 'Không tên';
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundImage:
                                senderData['photoURL'] != null
                                    ? NetworkImage(senderData['photoURL'])
                                    : null,
                            child:
                                senderData['photoURL'] == null
                                    ? Icon(Icons.person)
                                    : null,
                          ),
                          title: Text(senderName),
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
        ],
      ),
    );
  }
}
