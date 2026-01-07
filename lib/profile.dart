import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:image_picker/image_picker.dart';
import 'main.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _auth = FirebaseAuth.instance;
  final _dbRef = FirebaseDatabase.instance.ref();
  final ImagePicker _picker = ImagePicker();

  String _displayName = "Loading...";
  String _address = "Loading...";
  String _email = "";
  String? _base64Image;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    final user = _auth.currentUser;
    if (user != null) {
      setState(() => _email = user.email ?? "No Email");

      try {
        final snapshot = await _dbRef.child('Users/${user.uid}/Profile').get();
        if (snapshot.exists) {
          final data = Map<String, dynamic>.from(snapshot.value as Map);
          setState(() {
            _displayName = data['name'] ?? "No Name Set";
            _address = data['address'] ?? "No Address Set";
            _base64Image = data['profile_picture'];
            _isLoading = false;
          });
        } else {
          setState(() {
            _displayName = "User";
            _address = "Tap edit to set address";
            _isLoading = false;
          });
        }
      } catch (e) {
        setState(() {
          _displayName = "Error loading";
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _pickAndUploadImage() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 50,
        maxWidth: 500,
      );

      if (image != null) {
        setState(() => _isLoading = true);

        final bytes = await image.readAsBytes();
        final String base64String = base64Encode(bytes);

        await _dbRef.child('Users/${user.uid}/Profile').update({
          'profile_picture': base64String,
        });

        setState(() {
          _base64Image = base64String;
          _isLoading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Profile picture updated!")),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error picking image: $e")));
    }
  }

  Future<void> _showEditProfileDialog() async {
    final nameController = TextEditingController(
      text: _displayName == "User" ? "" : _displayName,
    );
    final addressController = TextEditingController(
      text: _address.contains("Set") ? "" : _address,
    );

    await showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text("Edit Profile Info"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: "Full Name",
                    prefixIcon: Icon(Icons.person),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: addressController,
                  decoration: const InputDecoration(
                    labelText: "Address",
                    prefixIcon: Icon(Icons.home),
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Cancel"),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (nameController.text.isNotEmpty) {
                    await _saveProfile(
                      nameController.text,
                      addressController.text,
                    );
                    Navigator.pop(context);
                  }
                },
                child: const Text("Save"),
              ),
            ],
          ),
    );
  }

  Future<void> _saveProfile(String name, String address) async {
    final user = _auth.currentUser;
    if (user != null) {
      try {
        await _dbRef.child('Users/${user.uid}/Profile').update({
          'name': name,
          'address': address,
        });
        setState(() {
          _displayName = name;
          _address = address;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Info updated!")));
      } catch (e) {}
    }
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text("Log Out"),
            content: const Text("Are you sure you want to exit?"),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Cancel"),
              ),
              TextButton(
                onPressed: () async {
                  await FirebaseAuth.instance.signOut();
                  if (context.mounted) {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(
                        builder: (context) => const SplashToLogin(),
                      ),
                      (Route<dynamic> route) => false,
                    );
                  }
                },
                child: const Text(
                  "Log Out",
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ImageProvider? avatarImage;
    if (_base64Image != null && _base64Image!.isNotEmpty) {
      try {
        avatarImage = MemoryImage(base64Decode(_base64Image!));
      } catch (e) {
        print("Error decoding image: $e");
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("My Profile"),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_note),
            onPressed: _showEditProfileDialog,
            tooltip: "Edit Info",
          ),
        ],
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                child: Column(
                  children: [
                    const SizedBox(height: 30),

                    Center(
                      child: Stack(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.blue, width: 3),
                            ),
                            child: CircleAvatar(
                              radius: 60,
                              backgroundColor: Colors.grey.shade200,
                              backgroundImage: avatarImage,
                              child:
                                  avatarImage == null
                                      ? const Icon(
                                        Icons.person,
                                        size: 70,
                                        color: Colors.grey,
                                      )
                                      : null,
                            ),
                          ),

                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: GestureDetector(
                              onTap: _pickAndUploadImage,
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: const BoxDecoration(
                                  color: Colors.blue,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.camera_alt,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 15),

                    Text(
                      _displayName,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      _email,
                      style: const TextStyle(color: Colors.grey, fontSize: 14),
                    ),

                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.location_on,
                            size: 16,
                            color: Colors.blue,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _address,
                            style: const TextStyle(
                              color: Colors.blue,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 30),
                    const Divider(),

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        children: [
                          _buildListTile(
                            icon: Icons.code,
                            title: "Lead Developer",
                            subtitle: "Keith Vladimir E. Estante",
                          ),
                          _buildListTile(
                            icon: Icons.info_outline,
                            title: "App Version",
                            subtitle: "v1.3.0",
                          ),
                          _buildListTile(
                            icon: Icons.security,
                            title: "Security",
                            subtitle: "Protected by Firebase Auth",
                          ),

                          const SizedBox(height: 30),

                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red.shade50,
                                foregroundColor: Colors.red,
                                elevation: 0,
                                side: const BorderSide(color: Colors.red),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              icon: const Icon(Icons.logout),
                              label: const Text("Log Out"),
                              onPressed: () => _showLogoutDialog(context),
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
    );
  }

  Widget _buildListTile({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: Colors.blue),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle),
      ),
    );
  }
}
