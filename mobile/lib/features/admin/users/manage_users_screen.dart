import "package:flutter/material.dart";

class ManageUsersScreen extends StatelessWidget {
  const ManageUsersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Manage Users")),
      body: const Center(child: Text("User management tools will appear here.")),
    );
  }
}
