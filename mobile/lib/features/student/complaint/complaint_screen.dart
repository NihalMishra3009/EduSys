import "dart:convert";

import "package:edusys_mobile/shared/services/api_service.dart";
import "package:flutter/material.dart";

class ComplaintScreen extends StatefulWidget {
  const ComplaintScreen({super.key});

  @override
  State<ComplaintScreen> createState() => _ComplaintScreenState();
}

class _ComplaintScreenState extends State<ComplaintScreen> {
  final ApiService _api = ApiService();
  final TextEditingController _subjectController = TextEditingController();
  final TextEditingController _descController = TextEditingController();

  bool _loading = false;
  List<dynamic> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _subjectController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await _api.myComplaints();
    setState(() {
      _loading = false;
      if (res.statusCode >= 200 && res.statusCode < 300) {
        _items = jsonDecode(res.body) as List<dynamic>;
      }
    });
  }

  Future<void> _submit() async {
    final subject = _subjectController.text.trim();
    final desc = _descController.text.trim();
    if (subject.length < 3 || desc.length < 5) {
      _snack("Enter valid subject and description");
      return;
    }
    final res = await _api.createComplaint(subject: subject, description: desc);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      _subjectController.clear();
      _descController.clear();
      _snack("Complaint submitted");
      await _load();
      return;
    }
    _snack(_extract(res.body, "Unable to submit complaint"));
  }

  String _extract(String body, String fallback) {
    try {
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      return (decoded["detail"] ?? fallback).toString();
    } catch (_) {
      return fallback;
    }
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Complaints")),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    TextField(
                      controller: _subjectController,
                      decoration: const InputDecoration(labelText: "Subject"),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _descController,
                      maxLines: 3,
                      decoration: const InputDecoration(labelText: "Description"),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(onPressed: _submit, child: const Text("Submit Complaint")),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (_loading)
              const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()))
            else if (_items.isEmpty)
              const Card(child: Padding(padding: EdgeInsets.all(12), child: Text("No complaints yet")))
            else
              ..._items.map(
                (item) => Card(
                  child: ListTile(
                    title: Text(item["subject"].toString()),
                    subtitle: Text(item["description"].toString()),
                    trailing: Text(item["status"].toString()),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

