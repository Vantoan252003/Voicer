import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'change_profile.dart';

class ProfilePage extends StatefulWidget {
  final User user;
  const ProfilePage({super.key, required this.user});
  @override
  _ProfilePageState createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Hồ sơ cá nhân")),
      body: FutureBuilder<DocumentSnapshot>(
        future: _firestore.collection('users').doc(widget.user.uid).get(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }
          Map<String, dynamic>? userData =
              snapshot.data?.data() as Map<String, dynamic>?;
          return SingleChildScrollView(
            padding: EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 50,
                  backgroundImage:
                      widget.user.photoURL != null
                          ? NetworkImage(widget.user.photoURL!)
                          : null,
                  child:
                      widget.user.photoURL == null
                          ? Icon(Icons.person, size: 50)
                          : null,
                ),
                InkWell(
                  // onTap: () => _changeProfilePhoto(),
                  child: Container(
                    padding: EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.blue,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.edit, color: Colors.white, size: 20),
                  ),
                ),
                SizedBox(height: 16),
                Text(
                  widget.user.displayName ?? "Không có tên",
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                // chưc nang thay đổi tên
                InkWell(
                  onTap: () {},
                  child: Text(
                    "Thay đổi tên",
                    style: TextStyle(color: Colors.blue),
                  ),
                ),
                Divider(height: 32),
                ListTile(
                  leading: Icon(Icons.email),
                  title: Text("Email"),
                  subtitle: Text(widget.user.email ?? "Không có"),
                ),
                ListTile(
                  leading: Icon(Icons.phone),
                  title: Text("Số điện thoại"),
                  subtitle: Text(widget.user.phoneNumber ?? "Chưa cập nhật"),
                ),
                ListTile(
                  leading: Icon(Icons.verified_user),
                  title: Text("Tình trạng xác thực"),
                  subtitle: Text(
                    widget.user.emailVerified ? "Đã xác thực" : "Chưa xác thực",
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.logout),
                  title: Text("Đăng xuất"),
                  onTap: () async {
                    await FirebaseAuth.instance.signOut();
                    await GoogleSignIn().signOut();
                    Navigator.of(context).pop();
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
