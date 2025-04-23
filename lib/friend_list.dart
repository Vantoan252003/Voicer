import 'package:flutter/material.dart';
import 'package:rxdart/rxdart.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:voicer/chat.dart';
import 'package:voicer/friend_request.dart';

class FriendListWidget extends StatelessWidget {
  final String userId;
  final FirebaseFirestore firestore;

  FriendListWidget({required this.userId, required this.firestore}) {
    print("User ID: $userId"); // Debug userId
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Danh sách bạn bè"),
        // leading: GestureDetector(
        //   onTap: () {
        //     Navigator.push(context, MaterialPageRoute(builder: (context) => FriendRequest()));
        //   },
        //   child: Icon(Icons.add_alert_sharp, color: Colors.white)
        // )
        actions: [
          IconButton(
            icon: Icon(Icons.add_alert_sharp),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => FriendRequest())),
          ),
        ],
      ),
      body: StreamBuilder<List<QuerySnapshot>>(
        stream: CombineLatestStream.list([
          firestore
              .collection('friendships')
              .where('user1', isEqualTo: userId)
              .where('status', isEqualTo: 'accepted')
              .snapshots(),
          firestore
              .collection('friendships')
              .where('user2', isEqualTo: userId)
              .where('status', isEqualTo: 'accepted')
              .snapshots(),
        ]),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            print("Error: ${snapshot.error}");
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
              String friendId = doc['user1'] == userId ? doc['user2'] : doc['user1'];
              return FutureBuilder<DocumentSnapshot>(
                future: firestore.collection('users').doc(friendId).get(),
                builder: (context, userSnapshot) {
                  if (!userSnapshot.hasData) {
                    return ListTile(title: Text("Đang tải..."));
                  }
                  var friendData = userSnapshot.data!.data() as Map<String, dynamic>?;
                  if (friendData == null) {
                    return ListTile(title: Text("Không có dữ liệu người dùng"));
                  }
                  return ListTile(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ChatScreen(
                            currentUserId: userId,
                            friendId: friendId,
                            friendName: friendData['displayName'] ?? 'Không tên',
                            friendPhotoURL: friendData['photoURL'],
                          ),
                        ),
                      );
                    },
                    onLongPress: (){
                      _showDeleteFriendDialog(context, doc.id, friendData['displayName']);
                    },
                    leading: CircleAvatar(
                      backgroundImage: friendData['photoURL'] != null
                          ? NetworkImage(friendData['photoURL'])
                          : null,
                      child: friendData['photoURL'] == null ? Icon(Icons.person) : null,
                    ),
                    title: Text(friendData['displayName'] ?? 'Không tên'),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
  void _showDeleteFriendDialog(BuildContext context, String friendshipId, String friendName){
    showDialog(context: context, builder: (BuildContext context){
      return AlertDialog(
        title: Text("Xóa bạn bè"),
        content: Text("Bạn có chắc chắn muốn xóa $friendName khỏi danh sách bạn bè không ?"),
        actions: [
          TextButton(onPressed: (){
            Navigator.of(context).pop();
          } , child: Text("Hủy")),
          TextButton(onPressed: () async {
              await firestore.collection('friendships').doc(friendshipId).delete();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text("Đã xóa $friendName khỏi danh sách bạn bè")),
              );
            Navigator.of(context).pop(); // Đóng dialog
          }, child: Text("Xóa", style: TextStyle(color: Colors.red),) ),
        ],

      );
    });
  }
}