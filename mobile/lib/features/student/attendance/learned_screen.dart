import "dart:convert";
import "dart:async";

import "package:edusys_mobile/providers/auth_provider.dart";
import "package:edusys_mobile/shared/services/api_service.dart";
import "package:edusys_mobile/shared/widgets/app_card.dart";
import "package:edusys_mobile/shared/widgets/empty_state_widget.dart";
import "package:edusys_mobile/shared/widgets/glass_toast.dart";
import "package:edusys_mobile/shared/widgets/loading_skeleton.dart";
import "package:edusys_mobile/shared/widgets/section_title.dart";
import "package:edusys_mobile/shared/widgets/status_badge.dart";
import "package:edusys_mobile/core/utils/time_format.dart";
import "package:file_picker/file_picker.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:provider/provider.dart";
import "package:url_launcher/url_launcher.dart";

// ─────────────────────────────────────────────────────────────────────────────
// LearnEd entry — subject list
// ─────────────────────────────────────────────────────────────────────────────

class LearnEdScreen extends StatefulWidget {
  const LearnEdScreen({super.key});

  @override
  State<LearnEdScreen> createState() => _LearnEdScreenState();
}

class _LearnEdScreenState extends State<LearnEdScreen> {
  final _api = ApiService();
  List<Map<String, dynamic>> _subjects = [];
  bool _loading = true;
  Timer? _syncTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _syncTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _load(silent: true);
    });
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() => _loading = true);
    }
    try {
      final res = await _api.learnedListSubjects();
      if (!mounted) return;
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final decoded = jsonDecode(res.body) as List<dynamic>;
        final list = decoded.whereType<Map<String, dynamic>>().toList();
        await _api.saveCache("learned_subjects", list);
        setState(() { _subjects = list; _loading = false; });
      } else {
        final cached = await _api.readCache("learned_subjects") as List<dynamic>?;
        setState(() {
          _subjects = cached?.whereType<Map<String, dynamic>>().toList() ?? [];
          _loading = false;
        });
      }
    } catch (_) {
      final cached = await _api.readCache("learned_subjects") as List<dynamic>?;
      if (mounted) {
        setState(() {
          _subjects = cached?.whereType<Map<String, dynamic>>().toList() ?? [];
          _loading = false;
        });
      }
    }
  }

  String _detail(String body) {
    try {
      final m = jsonDecode(body) as Map<String, dynamic>;
      return (m["detail"] ?? "Request failed").toString();
    } catch (_) {
      return "Request failed";
    }
  }

  Future<void> _showCreateDialog() async {
    final nameCtrl = TextEditingController();
    final codeCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Create subject"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "Subject name (e.g. Computational Thinking)")),
              const SizedBox(height: 10),
              TextField(
                controller: codeCtrl,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: "Short code (e.g. CT, DBMS)"),
              ),
              const SizedBox(height: 10),
              TextField(controller: descCtrl, decoration: const InputDecoration(labelText: "Description (optional)")),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Create")),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final res = await _api.learnedCreateSubject(
      name: nameCtrl.text.trim(),
      code: codeCtrl.text.trim(),
      description: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
    );
    if (!mounted) return;
    if (res.statusCode >= 200 && res.statusCode < 300) {
      GlassToast.show(context, "Subject created!", icon: Icons.check_circle_outline);
      await _load();
    } else {
      GlassToast.show(context, _detail(res.body), icon: Icons.error_outline);
    }
  }

  Future<void> _showJoinDialog() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Join subject"),
        content: TextField(
          controller: ctrl,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: "6-character join code",
            hintText: "e.g. CT3B9X",
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Join")),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final res = await _api.learnedJoinSubject(ctrl.text.trim());
    if (!mounted) return;
    if (res.statusCode >= 200 && res.statusCode < 300) {
      GlassToast.show(context, "Joined!", icon: Icons.check_circle_outline);
      await _load();
    } else {
      GlassToast.show(context, _detail(res.body), icon: Icons.error_outline);
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = context.watch<AuthProvider>().role ?? "STUDENT";
    final isProfessor = role == "PROFESSOR";

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 40),
        children: [
          Row(
            children: [
              const Expanded(
                child: Text("LearnEd", style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700)),
              ),
              IconButton(
                onPressed: isProfessor ? _showCreateDialog : _showJoinDialog,
                icon: const Icon(Icons.add_circle_rounded),
                tooltip: isProfessor ? "Create subject" : "Join with code",
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_loading)
            const LoadingSkeleton(height: 140)
          else if (_subjects.isEmpty)
            EmptyStateWidget(
              message: isProfessor
                  ? "No subjects yet. Tap + to create your first subject."
                  : "You haven't joined any subjects. Ask your professor for the join code, then tap +.",
              icon: Icons.school_outlined,
            )
          else
            ..._subjects.map((s) {
              final id = (s["id"] as num).toInt();
              final name = s["name"]?.toString() ?? "Subject";
              final code = s["code"]?.toString() ?? "";
              final joinCode = s["join_code"]?.toString() ?? "";
              final count = (s["member_count"] as num?)?.toInt() ?? 0;

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: AppCard(
                  gradient: LinearGradient(
                    colors: [
                      Theme.of(context).colorScheme.primary.withValues(alpha: 0.88),
                      Theme.of(context).colorScheme.secondary.withValues(alpha: 0.78),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => _SubjectScreen(
                          subjectId: id,
                          subjectName: name,
                          subjectCode: code,
                          joinCode: joinCode,
                          isProfessor: isProfessor,
                        ),
                      ),
                    ).then((_) => _load()),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text(code, style: const TextStyle(color: Colors.white70, fontSize: 14)),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            const Icon(Icons.people_outline, color: Colors.white70, size: 16),
                            const SizedBox(width: 4),
                            Text("$count members", style: const TextStyle(color: Colors.white70, fontSize: 13)),
                            const Spacer(),
                            if (isProfessor)
                              GestureDetector(
                                onTap: () {
                                  Clipboard.setData(ClipboardData(text: joinCode));
                                  GlassToast.show(context, "Join code copied: $joinCode", icon: Icons.copy);
                                },
                                child: Row(
                                  children: [
                                    const Icon(Icons.vpn_key_rounded, color: Colors.white54, size: 14),
                                    const SizedBox(width: 4),
                                    Text(
                                      joinCode,
                                      style: const TextStyle(color: Colors.white70, fontSize: 13, letterSpacing: 2),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Subject screen with 5 tabs
// ─────────────────────────────────────────────────────────────────────────────

class _SubjectScreen extends StatefulWidget {
  const _SubjectScreen({
    required this.subjectId,
    required this.subjectName,
    required this.subjectCode,
    required this.joinCode,
    required this.isProfessor,
  });

  final int subjectId;
  final String subjectName;
  final String subjectCode;
  final String joinCode;
  final bool isProfessor;

  @override
  State<_SubjectScreen> createState() => _SubjectScreenState();
}

class _SubjectScreenState extends State<_SubjectScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _api = ApiService();

  List<Map<String, dynamic>> _posts = [];
  List<Map<String, dynamic>> _members = [];
  List<Map<String, dynamic>> _syllabus = [];
  List<Map<String, dynamic>> _leaderboard = [];
  bool _loading = true;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 5, vsync: this);
    _load();
    _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _refreshRealtime();
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() => _loading = true);
    }
    try {
      final results = await Future.wait([
        _api.learnedListPosts(widget.subjectId),
        _api.learnedListMembers(widget.subjectId),
        _api.learnedListSyllabus(widget.subjectId),
        _api.learnedLeaderboard(widget.subjectId),
      ]);
      if (!mounted) return;
      setState(() {
        if (results[0].statusCode >= 200 && results[0].statusCode < 300) {
          _posts = (jsonDecode(results[0].body) as List<dynamic>).whereType<Map<String, dynamic>>().toList();
        }
        if (results[1].statusCode >= 200 && results[1].statusCode < 300) {
          _members = (jsonDecode(results[1].body) as List<dynamic>).whereType<Map<String, dynamic>>().toList();
        }
        if (results[2].statusCode >= 200 && results[2].statusCode < 300) {
          _syllabus = (jsonDecode(results[2].body) as List<dynamic>).whereType<Map<String, dynamic>>().toList();
        }
        if (results[3].statusCode >= 200 && results[3].statusCode < 300) {
          _leaderboard = (jsonDecode(results[3].body) as List<dynamic>).whereType<Map<String, dynamic>>().toList();
        }
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refreshRealtime() async {
    await _load(silent: true);
  }

  List<Map<String, dynamic>> get _allPosts => _posts;
  List<Map<String, dynamic>> get _materialPosts => _posts.where((p) => p["type"] == "MATERIAL").toList();
  List<Map<String, dynamic>> get _assignmentPosts => _posts.where((p) => p["type"] == "ASSIGNMENT").toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.subjectName, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            Text(widget.subjectCode, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400)),
          ],
        ),
        actions: [
          if (widget.isProfessor)
            IconButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: widget.joinCode));
                GlassToast.show(context, "Join code: ${widget.joinCode}", icon: Icons.copy);
              },
              icon: const Icon(Icons.share_rounded),
              tooltip: "Share join code",
            ),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(text: "Stream"),
            Tab(text: "Classwork"),
            Tab(text: "Assignments"),
            Tab(text: "People"),
            Tab(text: "Syllabus"),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabs,
              children: [
                _StreamTab(posts: _allPosts, subjectId: widget.subjectId, isProfessor: widget.isProfessor, onRefresh: _load, api: _api),
                _ClassworkTab(posts: _materialPosts, subjectId: widget.subjectId, isProfessor: widget.isProfessor, onRefresh: _load, api: _api),
                _AssignmentsTab(posts: _assignmentPosts, subjectId: widget.subjectId, isProfessor: widget.isProfessor, onRefresh: _load, api: _api),
                _PeopleTab(members: _members, leaderboard: _leaderboard),
                _SyllabusTab(units: _syllabus, subjectId: widget.subjectId, isProfessor: widget.isProfessor, onRefresh: _load, api: _api),
              ],
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stream tab
// ─────────────────────────────────────────────────────────────────────────────

class _StreamTab extends StatefulWidget {
  const _StreamTab({required this.posts, required this.subjectId, required this.isProfessor, required this.onRefresh, required this.api});
  final List<Map<String, dynamic>> posts;
  final int subjectId;
  final bool isProfessor;
  final VoidCallback onRefresh;
  final ApiService api;

  @override
  State<_StreamTab> createState() => _StreamTabState();
}

class _StreamTabState extends State<_StreamTab> {
  final _ctrl = TextEditingController();
  bool _posting = false;

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _post() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _posting = true);
    final res = await widget.api.learnedCreatePost(widget.subjectId, {"type": "ANNOUNCEMENT", "body": text});
    if (!mounted) return;
    setState(() => _posting = false);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      _ctrl.clear();
      widget.onRefresh();
    } else {
      GlassToast.show(context, "Failed to post", icon: Icons.error_outline);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 40),
      children: [
        if (widget.isProfessor) ...[
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _ctrl,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(hintText: "Announce something to your class...", border: InputBorder.none),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: _posting ? null : _post,
                    icon: const Icon(Icons.send_rounded, size: 16),
                    label: Text(_posting ? "Posting..." : "Post"),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (widget.posts.isEmpty)
          const EmptyStateWidget(message: "No posts yet. The stream will show announcements, materials, and assignments.", icon: Icons.dynamic_feed_outlined)
        else
          ...widget.posts.map((p) => _PostCard(post: p, subjectId: widget.subjectId, isProfessor: widget.isProfessor, onRefresh: widget.onRefresh, api: widget.api, showSubmit: false)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Classwork tab
// ─────────────────────────────────────────────────────────────────────────────

class _ClassworkTab extends StatefulWidget {
  const _ClassworkTab({required this.posts, required this.subjectId, required this.isProfessor, required this.onRefresh, required this.api});
  final List<Map<String, dynamic>> posts;
  final int subjectId;
  final bool isProfessor;
  final VoidCallback onRefresh;
  final ApiService api;

  @override
  State<_ClassworkTab> createState() => _ClassworkTabState();
}

class _ClassworkTabState extends State<_ClassworkTab> {
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  String? _attachmentUrl;
  String? _attachmentName;
  bool _uploading = false;

  @override
  void dispose() { _titleCtrl.dispose(); _bodyCtrl.dispose(); super.dispose(); }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ["pdf", "doc", "docx", "ppt", "pptx", "xls", "xlsx", "txt", "png", "jpg", "jpeg"],
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null) return;
    setState(() => _uploading = true);
    final res = await widget.api.uploadAttachment(filePath: path, purpose: "classwork");
    if (!mounted) return;
    setState(() => _uploading = false);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      setState(() {
        _attachmentUrl = data["url"]?.toString();
        _attachmentName = result.files.single.name;
      });
      GlassToast.show(context, "File attached: ${result.files.single.name}", icon: Icons.check_circle_outline);
    } else {
      GlassToast.show(context, "Upload failed", icon: Icons.error_outline);
    }
  }

  Future<void> _post() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      GlassToast.show(context, "Title is required", icon: Icons.info_outline);
      return;
    }
    final res = await widget.api.learnedCreatePost(widget.subjectId, {
      "type": "MATERIAL",
      "title": title,
      "body": _bodyCtrl.text.trim().isEmpty ? null : _bodyCtrl.text.trim(),
      "attachment_url": _attachmentUrl,
      "attachment_name": _attachmentName,
    });
    if (!mounted) return;
    if (res.statusCode >= 200 && res.statusCode < 300) {
      _titleCtrl.clear();
      _bodyCtrl.clear();
      setState(() { _attachmentUrl = null; _attachmentName = null; });
      widget.onRefresh();
      GlassToast.show(context, "Material posted", icon: Icons.check_circle_outline);
    } else {
      GlassToast.show(context, "Failed to post", icon: Icons.error_outline);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 40),
      children: [
        if (widget.isProfessor) ...[
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Post material", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 10),
                TextField(controller: _titleCtrl, decoration: const InputDecoration(labelText: "Title")),
                const SizedBox(height: 8),
                TextField(controller: _bodyCtrl, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: "Description (optional)")),
                const SizedBox(height: 10),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _uploading ? null : _pickFile,
                      icon: const Icon(Icons.attach_file_rounded, size: 16),
                      label: Text(_uploading ? "Uploading..." : _attachmentName != null ? "✓ ${_attachmentName!}" : "Attach file"),
                    ),
                    const Spacer(),
                    FilledButton(onPressed: _post, child: const Text("Post")),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (widget.posts.isEmpty)
          const EmptyStateWidget(message: "No classwork material posted yet", icon: Icons.folder_open_outlined)
        else
          ...widget.posts.map((p) => _PostCard(post: p, subjectId: widget.subjectId, isProfessor: widget.isProfessor, onRefresh: widget.onRefresh, api: widget.api, showSubmit: false)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Assignments tab
// ─────────────────────────────────────────────────────────────────────────────

class _AssignmentsTab extends StatefulWidget {
  const _AssignmentsTab({required this.posts, required this.subjectId, required this.isProfessor, required this.onRefresh, required this.api});
  final List<Map<String, dynamic>> posts;
  final int subjectId;
  final bool isProfessor;
  final VoidCallback onRefresh;
  final ApiService api;

  @override
  State<_AssignmentsTab> createState() => _AssignmentsTabState();
}

class _AssignmentsTabState extends State<_AssignmentsTab> {
  final _titleCtrl = TextEditingController();
  final _instrCtrl = TextEditingController();
  DateTime? _dueAt;
  int _maxMarks = 100;

  @override
  void dispose() { _titleCtrl.dispose(); _instrCtrl.dispose(); super.dispose(); }

  Future<void> _pickDue() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 3)),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _dueAt = picked);
  }

  Future<void> _create() async {
    if (_titleCtrl.text.trim().isEmpty || _instrCtrl.text.trim().isEmpty) {
      GlassToast.show(context, "Title and instructions are required", icon: Icons.info_outline);
      return;
    }
    final res = await widget.api.learnedCreatePost(widget.subjectId, {
      "type": "ASSIGNMENT",
      "title": _titleCtrl.text.trim(),
      "body": _instrCtrl.text.trim(),
      "due_at": _dueAt?.toUtc().toIso8601String(),
      "max_marks": _maxMarks,
    });
    if (!mounted) return;
    if (res.statusCode >= 200 && res.statusCode < 300) {
      _titleCtrl.clear();
      _instrCtrl.clear();
      setState(() { _dueAt = null; _maxMarks = 100; });
      widget.onRefresh();
      GlassToast.show(context, "Assignment created", icon: Icons.check_circle_outline);
    } else {
      GlassToast.show(context, "Failed to create assignment", icon: Icons.error_outline);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 40),
      children: [
        if (widget.isProfessor) ...[
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Create assignment", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 10),
                TextField(controller: _titleCtrl, decoration: const InputDecoration(labelText: "Assignment title")),
                const SizedBox(height: 8),
                TextField(
                  controller: _instrCtrl,
                  minLines: 3,
                  maxLines: 6,
                  decoration: const InputDecoration(labelText: "Instructions / what to submit", alignLabelWithHint: true),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickDue,
                        icon: const Icon(Icons.calendar_today_rounded, size: 16),
                        label: Text(_dueAt == null ? "Set due date" : TimeFormat.formatDate(_dueAt!)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 110,
                      child: TextField(
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: "Max marks"),
                        onChanged: (v) => _maxMarks = int.tryParse(v) ?? 100,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(width: double.infinity, child: FilledButton(onPressed: _create, child: const Text("Assign to class"))),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (widget.posts.isEmpty)
          const EmptyStateWidget(message: "No assignments yet", icon: Icons.assignment_outlined)
        else
          ...widget.posts.map((p) => _PostCard(post: p, subjectId: widget.subjectId, isProfessor: widget.isProfessor, onRefresh: widget.onRefresh, api: widget.api, showSubmit: true)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// People tab
// ─────────────────────────────────────────────────────────────────────────────

class _PeopleTab extends StatelessWidget {
  const _PeopleTab({required this.members, required this.leaderboard});
  final List<Map<String, dynamic>> members;
  final List<Map<String, dynamic>> leaderboard;

  @override
  Widget build(BuildContext context) {
    final professors = members.where((m) => m["role"] == "PROFESSOR").toList();
    final students = members.where((m) => m["role"] == "STUDENT").toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 40),
      children: [
        if (leaderboard.isNotEmpty) ...[
          const SectionTitle("Top Students"),
          const SizedBox(height: 8),
          ...leaderboard.map((row) {
            final name = (row["name"] ?? "Student").toString();
            final total = (row["total_marks"] ?? 0).toString();
            final submissions = (row["submissions"] ?? 0).toString();
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AppCard(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.18),
                    child: Text(name[0].toUpperCase(),
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w700)),
                  ),
                  title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text("$submissions submissions"),
                  trailing: Text("$total marks",
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            );
          }),
          const SizedBox(height: 14),
        ],
        if (professors.isNotEmpty) ...[
          const SectionTitle("Teachers"),
          const SizedBox(height: 8),
          ...professors.map((m) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.18),
                  child: Text((m["name"] ?? "T").toString()[0].toUpperCase(), style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700)),
                ),
                title: Text((m["name"] ?? "Professor").toString(), style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text((m["email"] ?? "").toString()),
              ),
            ),
          )),
          const SizedBox(height: 14),
        ],
        SectionTitle("Students (${students.length})"),
        const SizedBox(height: 8),
        if (students.isEmpty)
          const EmptyStateWidget(message: "No students have joined yet. Share the join code with your class.", icon: Icons.people_outline)
        else
          ...students.map((m) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.18),
                  child: Text((m["name"] ?? "S").toString()[0].toUpperCase()),
                ),
                title: Text((m["name"] ?? "Student").toString(), style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text((m["email"] ?? "").toString()),
              ),
            ),
          )),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Syllabus tab
// ─────────────────────────────────────────────────────────────────────────────

class _SyllabusTab extends StatefulWidget {
  const _SyllabusTab({required this.units, required this.subjectId, required this.isProfessor, required this.onRefresh, required this.api});
  final List<Map<String, dynamic>> units;
  final int subjectId;
  final bool isProfessor;
  final VoidCallback onRefresh;
  final ApiService api;

  @override
  State<_SyllabusTab> createState() => _SyllabusTabState();
}

class _SyllabusTabState extends State<_SyllabusTab> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  @override
  void dispose() { _titleCtrl.dispose(); _descCtrl.dispose(); super.dispose(); }

  Future<void> _addUnit() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) return;
    final nextNum = widget.units.isEmpty
        ? 1
        : ((widget.units.last["unit_number"] as num?)?.toInt() ?? 0) + 1;
    final res = await widget.api.learnedAddSyllabusUnit(widget.subjectId, {
      "unit_number": nextNum,
      "unit_title": title,
      "description": _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
    });
    if (!mounted) return;
    if (res.statusCode >= 200 && res.statusCode < 300) {
      _titleCtrl.clear();
      _descCtrl.clear();
      widget.onRefresh();
    } else {
      GlassToast.show(context, "Failed to add unit", icon: Icons.error_outline);
    }
  }

  Future<void> _deleteUnit(int unitId) async {
    await widget.api.learnedDeleteSyllabusUnit(widget.subjectId, unitId);
    widget.onRefresh();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 40),
      children: [
        if (widget.isProfessor) ...[
          AppCard(
            child: Column(
              children: [
                TextField(controller: _titleCtrl, decoration: const InputDecoration(labelText: "Unit title (e.g. Unit 1: Introduction)")),
                const SizedBox(height: 8),
                TextField(controller: _descCtrl, minLines: 2, maxLines: 3, decoration: const InputDecoration(labelText: "Topics covered (optional)")),
                const SizedBox(height: 10),
                Align(alignment: Alignment.centerRight, child: FilledButton(onPressed: _addUnit, child: const Text("Add unit"))),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (widget.units.isEmpty)
          const EmptyStateWidget(message: "No syllabus units added yet", icon: Icons.menu_book_outlined)
        else
          ...widget.units.map((u) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: AppCard(
              child: Row(
                children: [
                  CircleAvatar(radius: 18, child: Text("${u["unit_number"]}")),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text((u["unit_title"] ?? "").toString(), style: const TextStyle(fontWeight: FontWeight.w700)),
                        if ((u["description"] ?? "").toString().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              (u["description"] ?? "").toString(),
                              style: TextStyle(color: Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.7), fontSize: 13),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (widget.isProfessor)
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded),
                      onPressed: () => _deleteUnit((u["id"] as num).toInt()),
                    ),
                ],
              ),
            ),
          )),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared post card
// ─────────────────────────────────────────────────────────────────────────────

class _PostCard extends StatelessWidget {
  const _PostCard({
    required this.post,
    required this.subjectId,
    required this.isProfessor,
    required this.onRefresh,
    required this.api,
    required this.showSubmit,
  });

  final Map<String, dynamic> post;
  final int subjectId;
  final bool isProfessor;
  final VoidCallback onRefresh;
  final ApiService api;
  final bool showSubmit;

  String _fmtDate(dynamic raw) {
    final dt = TimeFormat.parseToIst(raw?.toString());
    return dt == null ? "" : TimeFormat.formatDateTime12hIst(dt);
  }

  @override
  Widget build(BuildContext context) {
    final type = post["type"]?.toString() ?? "ANNOUNCEMENT";
    final title = post["title"]?.toString();
    final body = post["body"]?.toString();
    final attachUrl = post["attachment_url"]?.toString();
    final attachName = post["attachment_name"]?.toString();
    final dueAt = post["due_at"];
    final maxMarks = post["max_marks"];
    final authorName = post["author_name"]?.toString() ?? "Professor";
    final postId = (post["id"] as num).toInt();
    final subCount = (post["submission_count"] as num?)?.toInt() ?? 0;
    final mySub = post["my_submission"] as Map<String, dynamic>?;

    final typeColor = switch (type) {
      "ASSIGNMENT" => Colors.orange,
      "MATERIAL"   => Colors.blue,
      _             => Theme.of(context).colorScheme.primary,
    };
    final typeIcon = switch (type) {
      "ASSIGNMENT" => Icons.assignment_rounded,
      "MATERIAL"   => Icons.description_outlined,
      _             => Icons.campaign_rounded,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: typeColor.withValues(alpha: 0.14),
                  child: Icon(typeIcon, color: typeColor, size: 16),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (title != null && title.isNotEmpty)
                        Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                      Text(
                        authorName,
                        style: TextStyle(color: Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.65), fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Text(
                  _fmtDate(post["created_at"]),
                  style: TextStyle(color: Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.55), fontSize: 11),
                ),
              ],
            ),
            // Body
            if (body != null && body.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(body),
            ],
            // Due date + marks
            if (dueAt != null) ...[
              const SizedBox(height: 6),
              Row(children: [
                const Icon(Icons.access_time_rounded, size: 14),
                const SizedBox(width: 4),
                Text("Due: ${_fmtDate(dueAt)}", style: const TextStyle(fontSize: 13)),
                if (maxMarks != null) ...[
                  const SizedBox(width: 12),
                  Text("$maxMarks marks", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ],
              ]),
            ],
            // Attachment
            if (attachUrl != null && attachUrl.isNotEmpty) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  final uri = Uri.tryParse(attachUrl);
                  if (uri == null) {
                    GlassToast.show(
                      context,
                      "Invalid attachment URL.",
                      icon: Icons.error_outline,
                    );
                    return;
                  }
                  try {
                    final ok = await launchUrl(
                      uri,
                      mode: LaunchMode.externalApplication,
                    );
                    if (!ok && context.mounted) {
                      GlassToast.show(
                        context,
                        "Unable to open attachment.",
                        icon: Icons.error_outline,
                      );
                    }
                  } catch (_) {
                    if (context.mounted) {
                      GlassToast.show(
                        context,
                        "Unable to open attachment.",
                        icon: Icons.error_outline,
                      );
                    }
                  }
                },
                icon: const Icon(Icons.attach_file_rounded, size: 15),
                label: Text(attachName ?? "Attachment", overflow: TextOverflow.ellipsis),
                style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
              ),
            ],
            // Professor: submission count + view
            if (isProfessor && type == "ASSIGNMENT") ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Text("$subCount submission${subCount == 1 ? "" : "s"}", style: const TextStyle(fontWeight: FontWeight.w600)),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => _SubmissionsScreen(
                          subjectId: subjectId,
                          postId: postId,
                          postTitle: title ?? "Assignment",
                          api: api,
                        ),
                      ),
                    ).then((_) => onRefresh()),
                    child: const Text("View submissions"),
                  ),
                ],
              ),
            ],
            // Student: status + submit
            if (!isProfessor && showSubmit && type == "ASSIGNMENT") ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          mySub == null ? "Not submitted" : "Submitted",
                          style: TextStyle(color: mySub == null ? Colors.orange : Colors.green, fontWeight: FontWeight.w600),
                        ),
                        if (mySub != null && mySub["marks"] != null)
                          Text("Marks: ${mySub["marks"]}/${maxMarks ?? 100}", style: const TextStyle(fontWeight: FontWeight.w700)),
                        if (mySub != null && (mySub["feedback"] ?? "").toString().isNotEmpty)
                          Text("Feedback: ${mySub["feedback"]}", style: const TextStyle(fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => _openSubmitSheet(context, mySub, postId, maxMarks),
                    child: Text(mySub == null ? "Submit" : "Update"),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _openSubmitSheet(BuildContext context, Map<String, dynamic>? existing, int postId, dynamic maxMarks) async {
    final answerCtrl = TextEditingController(text: existing?["answer_text"]?.toString() ?? "");
    String? attachUrl = existing?["attachment_url"]?.toString();
    String? attachName = existing?["attachment_name"]?.toString();
    bool uploading = false;

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => Padding(
          padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(existing == null ? "Submit assignment" : "Update submission",
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              TextField(
                controller: answerCtrl,
                minLines: 4,
                maxLines: 8,
                decoration: const InputDecoration(labelText: "Your answer", alignLabelWithHint: true),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: uploading
                    ? null
                    : () async {
                        final result = await FilePicker.platform.pickFiles(
                          type: FileType.custom,
                          allowedExtensions: ["pdf", "doc", "docx", "png", "jpg", "jpeg"],
                        );
                        if (result == null || result.files.isEmpty) return;
                        final path = result.files.single.path;
                        if (path == null) return;
                        setLocal(() => uploading = true);
                        final res = await api.uploadAttachment(filePath: path, purpose: "submission");
                        if (res.statusCode >= 200 && res.statusCode < 300) {
                          final data = jsonDecode(res.body) as Map<String, dynamic>;
                          setLocal(() {
                            attachUrl = data["url"]?.toString();
                            attachName = result.files.single.name;
                            uploading = false;
                          });
                        } else {
                          setLocal(() => uploading = false);
                        }
                      },
                icon: const Icon(Icons.attach_file_rounded, size: 16),
                label: Text(uploading ? "Uploading..." : attachName != null ? "✓ $attachName" : "Attach file"),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(existing == null ? "Submit" : "Update submission"),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (ok != true || !context.mounted) return;
    final res = await api.learnedSubmit(subjectId, postId, {
      "answer_text": answerCtrl.text.trim(),
      "attachment_url": attachUrl,
      "attachment_name": attachName,
    });
    if (!context.mounted) return;
    if (res.statusCode >= 200 && res.statusCode < 300) {
      GlassToast.show(context, "Submitted!", icon: Icons.check_circle_outline);
      onRefresh();
    } else {
      GlassToast.show(context, "Submission failed", icon: Icons.error_outline);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Submissions screen (professor)
// ─────────────────────────────────────────────────────────────────────────────

class _SubmissionsScreen extends StatefulWidget {
  const _SubmissionsScreen({required this.subjectId, required this.postId, required this.postTitle, required this.api});
  final int subjectId;
  final int postId;
  final String postTitle;
  final ApiService api;

  @override
  State<_SubmissionsScreen> createState() => _SubmissionsScreenState();
}

class _SubmissionsScreenState extends State<_SubmissionsScreen> {
  List<Map<String, dynamic>> _submissions = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await widget.api.learnedListSubmissions(widget.subjectId, widget.postId);
    if (!mounted) return;
    setState(() {
      if (res.statusCode >= 200 && res.statusCode < 300) {
        _submissions = (jsonDecode(res.body) as List<dynamic>).whereType<Map<String, dynamic>>().toList();
      }
      _loading = false;
    });
  }

  Future<void> _grade(Map<String, dynamic> sub) async {
    final marksCtrl = TextEditingController(text: sub["marks"]?.toString() ?? "");
    final feedbackCtrl = TextEditingController(text: sub["feedback"]?.toString() ?? "");
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Grade — ${(sub["student_name"] ?? "Student")}"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: marksCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Marks (0 – 100)")),
            const SizedBox(height: 10),
            TextField(controller: feedbackCtrl, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: "Feedback (optional)")),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Save")),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final res = await widget.api.learnedGrade(
      widget.subjectId,
      (sub["id"] as num).toInt(),
      {"marks": int.tryParse(marksCtrl.text.trim()), "feedback": feedbackCtrl.text.trim()},
    );
    if (!mounted) return;
    if (res.statusCode >= 200 && res.statusCode < 300) {
      GlassToast.show(context, "Graded!", icon: Icons.check_circle_outline);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Submissions — ${widget.postTitle}")),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _submissions.isEmpty
              ? const Center(child: EmptyStateWidget(message: "No submissions yet"))
              : ListView.separated(
                  padding: const EdgeInsets.all(14),
                  itemCount: _submissions.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final s = _submissions[i];
                    final hasGrade = s["marks"] != null;
                    return AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text((s["student_name"] ?? "Student").toString(), style: const TextStyle(fontWeight: FontWeight.w700)),
                              ),
                              if (hasGrade)
                                StatusBadge(label: "${s["marks"]}/100", color: Colors.green),
                            ],
                          ),
                          Text(
                            (s["student_email"] ?? "").toString(),
                            style: TextStyle(color: Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.65), fontSize: 12),
                          ),
                          const SizedBox(height: 8),
                          if ((s["answer_text"] ?? "").toString().isNotEmpty)
                            Text((s["answer_text"] ?? "").toString(), maxLines: 5, overflow: TextOverflow.ellipsis),
                          if ((s["attachment_url"] ?? "").toString().isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Row(children: [
                              const Icon(Icons.attach_file_rounded, size: 14),
                              const SizedBox(width: 4),
                              Text((s["attachment_name"] ?? "Attachment").toString(), style: const TextStyle(fontSize: 12)),
                            ]),
                          ],
                          if ((s["feedback"] ?? "").toString().isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text("Feedback: ${s["feedback"]}", style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 13)),
                          ],
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () => _grade(s),
                              child: Text(hasGrade ? "Update grade" : "Grade"),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
