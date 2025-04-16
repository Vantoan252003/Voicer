import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:rxdart/rxdart.dart';

class FriendSelectionDialog extends StatefulWidget {
  final String userId;
  final FirebaseFirestore firestore;
  final Future<void> Function(List<String>) onSend;

  const FriendSelectionDialog({
    required this.userId,
    required this.firestore,
    required this.onSend,
  });

  @override
  _FriendSelectionDialogState createState() => _FriendSelectionDialogState();
}

class _FriendSelectionDialogState extends State<FriendSelectionDialog> {
  List<String> selectedFriends = [];
  bool selectAll = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Gửi cho ai?"),
      content: SizedBox(
        width: double.maxFinite,
        child: StreamBuilder<List<QuerySnapshot>>(
          stream: CombineLatestStream.list([
            widget.firestore
                .collection('friendships')
                .where('user1', isEqualTo: widget.userId)
                .where('status', isEqualTo: 'accepted')
                .snapshots(),
            widget.firestore
                .collection('friendships')
                .where('user2', isEqualTo: widget.userId)
                .where('status', isEqualTo: 'accepted')
                .snapshots(),
          ]).map((list) => list.cast<QuerySnapshot>()), // Ép kiểu List<dynamic> thành List<QuerySnapshot>
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Text("Lỗi: ${snapshot.error}");
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            List<DocumentSnapshot> docs = [];
            for (var querySnapshot in snapshot.data!) {
              docs.addAll(querySnapshot.docs);
            }

            if (docs.isEmpty) {
              return const Text("Bạn chưa có bạn bè nào!");
            }

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Chọn bạn bè"),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          selectAll = !selectAll;
                          selectedFriends = selectAll
                              ? docs
                              .map((doc) => doc['user1'] == widget.userId
                              ? doc['user2'] as String
                              : doc['user1'] as String)
                              .toList()
                              : [];
                        });
                      },
                      child: Text(selectAll ? "Bỏ chọn tất cả" : "Chọn tất cả"),
                    ),
                  ],
                ),
                SizedBox(
                  height: 200,
                  child: ListView.builder(
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      var doc = docs[index];
                      String friendId = doc['user1'] == widget.userId
                          ? doc['user2'] as String
                          : doc['user1'] as String;
                      return FutureBuilder<DocumentSnapshot>(
                        future: widget.firestore.collection('users').doc(friendId).get(),
                        builder: (context, userSnapshot) {
                          if (!userSnapshot.hasData) {
                            return const ListTile(title: Text("Đang tải..."));
                          }
                          if (userSnapshot.hasError) {
                            return ListTile(title: Text("Lỗi: ${userSnapshot.error}"));
                          }
                          var friendData = userSnapshot.data!.data() as Map<String, dynamic>?;
                          if (friendData == null) {
                            return const ListTile(title: Text("Không tìm thấy bạn bè"));
                          }
                          String friendName = friendData['displayName'] ?? 'Không tên';
                          bool isSelected = selectedFriends.contains(friendId);

                          return CheckboxListTile(
                            title: Text(friendName),
                            value: isSelected,
                            onChanged: (bool? value) {
                              setState(() {
                                if (value == true) {
                                  selectedFriends.add(friendId);
                                } else {
                                  selectedFriends.remove(friendId);
                                }
                                selectAll = selectedFriends.length == docs.length;
                              });
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Hủy"),
        ),
        ElevatedButton(
          onPressed: selectedFriends.isEmpty
              ? null
              : () => widget.onSend(selectedFriends),
          child: const Text("Gửi"),
        ),
      ],
    );
  }
}