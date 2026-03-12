import "package:flutter/material.dart";

class ManageClassroomsScreen extends StatelessWidget {
  const ManageClassroomsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Manage Classrooms")),
      body: const Center(child: Text("Classroom management tools will appear here.")),
    );
  }
}
