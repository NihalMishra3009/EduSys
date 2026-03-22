import "dart:convert";
import "dart:async";
import "dart:math" as math;
import "dart:ui";
import "dart:io";

import "package:edusys_mobile/core/animations/app_transitions.dart";
import "package:edusys_mobile/core/constants/app_colors.dart";
import "package:edusys_mobile/core/utils/perf_config.dart";
import "package:edusys_mobile/core/utils/time_format.dart";
import "package:edusys_mobile/providers/auth_provider.dart";
import "package:edusys_mobile/providers/theme_provider.dart";
import "package:edusys_mobile/features/admin/dashboard/admin_dashboard_screen.dart";
import "package:edusys_mobile/features/hello_casts/hello_casts_screen.dart";
import "package:edusys_mobile/features/student/railway/railway_concession_screen.dart";
import "package:edusys_mobile/features/student/profile/profile_screen.dart";
import "package:edusys_mobile/features/student/attendance/active_lecture_screen.dart";
import "package:edusys_mobile/features/student/attendance/learned_screen.dart";
import "package:edusys_mobile/shared/services/api_service.dart";
import "package:edusys_mobile/shared/services/device_binding_service.dart";
import "package:edusys_mobile/shared/services/smart_attendance_service.dart";
import "package:edusys_mobile/shared/widgets/app_button.dart";
import "package:edusys_mobile/shared/widgets/app_card.dart";
import "package:edusys_mobile/shared/widgets/empty_state_widget.dart";
import "package:edusys_mobile/shared/widgets/glass_toast.dart";
import "package:edusys_mobile/shared/widgets/loading_skeleton.dart";
import "package:edusys_mobile/shared/widgets/section_title.dart";
import "package:edusys_mobile/shared/widgets/status_badge.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:provider/provider.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:flutter_webrtc/flutter_webrtc.dart";
import "package:file_picker/file_picker.dart";
import "package:permission_handler/permission_handler.dart";

const bool kUseDemoDataEverywhere = false;
const double kDockScrollBottomInset = 96;

const List<Map<String, dynamic>> _demoProfessorClasses = [
  {"id": 1, "name": "AI Lab 601"},
  {"id": 2, "name": "DS Lab 602A"},
  {"id": 3, "name": "Classroom 715"},
  {"id": 4, "name": "Mini Project Room"},
];

const Map<int, List<Map<String, dynamic>>> _demoClassStudents = {
  1: [
    {"id": 201, "name": "Aarav Patil"},
    {"id": 202, "name": "Diya Shinde"},
    {"id": 203, "name": "Rohan Kale"},
  ],
  2: [
    {"id": 204, "name": "Meera Joshi"},
    {"id": 205, "name": "Kabir Nair"},
    {"id": 206, "name": "Sara Khan"},
  ],
  3: [
    {"id": 207, "name": "Tanvi Deshpande"},
    {"id": 208, "name": "Ishaan Gupta"},
    {"id": 209, "name": "Riya Sen"},
  ],
  4: [
    {"id": 210, "name": "Neel Vora"},
    {"id": 211, "name": "Sana Sheikh"},
    {"id": 212, "name": "Om Kulkarni"},
  ],
};

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _index = 0;
  static const List<String> _tabTitles = [
    "Home",
    "LearnEd",
    "ConnectEd",
    "AttendEd",
    "Profile",
  ];

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _onTabSelected(int value) {
    if (value == _index) {
      return;
    }
    setState(() => _index = value);
  }

  Future<void> _openClassExplorer() async {
    if (!mounted) {
      return;
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _ClassExplorerSheet(),
    );
  }

  Future<void> _openCalendarPlanner(String role) async {
    if (!mounted) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CalendarPlannerSheet(
        isProfessor: role == "PROFESSOR",
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final role = context.watch<AuthProvider>().role ?? "STUDENT";
    final hasSidebar = role == "STUDENT" || role == "PROFESSOR";
    final lowEnd = PerfConfig.lowEnd(context);
    final pages = role == "ADMIN"
        ? [
            const _AdminHomeTab(),
            const _NotesTab(),
            const _LearningTab(),
            const _AttendanceTab(),
            const _SettingsTab()
          ]
        : [
            _HomeTab(
              onOpenAttendance: () => _onTabSelected(3),
              onOpenConnected: () => _onTabSelected(2),
            ),
            const _NotesTab(),
            const _LearningTab(),
            const _AttendanceTab(),
            const _SettingsTab()
          ];

    return Scaffold(
      key: _scaffoldKey,
      drawer: hasSidebar ? const _StudentMenuDrawer() : null,
      extendBody: true,
      body: Stack(
        children: [
          Positioned.fill(
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(top: 68),
                child: IndexedStack(
                  index: _index,
                  children: pages,
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: SizedBox(
                  height: 46,
                  child: hasSidebar
                      ? Stack(
                          alignment: Alignment.center,
                          children: [
                            Positioned(
                              left: 0,
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(22),
                                  onTap: () => _scaffoldKey.currentState?.openDrawer(),
                                  child: const CircleAvatar(
                                    radius: 22,
                                    child: Icon(Icons.menu_rounded),
                                  ),
                                ),
                              ),
                            ),
                            Text(
                              _tabTitles[_index],
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.2,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            Positioned(
                          right: 0,
                          child: Row(
                            children: [
                                  Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(22),
                                      onTap: () => _openCalendarPlanner(role),
                                      child: const CircleAvatar(
                                        radius: 22,
                                        child: Icon(Icons.calendar_month_rounded),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(22),
                                onTap: () => _openCalendarPlanner(role),
                                child: const CircleAvatar(
                                  radius: 22,
                                  child: Icon(Icons.calendar_month_rounded),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(22),
                                onTap: () {
                                  _onTabSelected(4);
                                },
                                child: CircleAvatar(
                                  radius: 22,
                                  child: Icon(
                                    Icons.person_rounded,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 10,
            child: _BottomTabSection(
              selectedIndex: _index,
              onTap: _onTabSelected,
            ),
          ),
          Positioned(
            right: 14,
            bottom: 94,
            child: SafeArea(
              child: Container(
                height: 46,
                constraints: BoxConstraints(
                  minWidth: 56,
                  maxWidth: 108,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surface
                      .withValues(alpha: 0.96),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.14),
                  ),
                  boxShadow: lowEnd
                      ? null
                      : [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.12),
                            blurRadius: 14,
                            offset: const Offset(0, 6),
                          ),
                        ],
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      SizedBox(
                        width: 54,
                        child: IconButton(
                          tooltip: "Classes",
                          onPressed: _openClassExplorer,
                          icon: const Icon(Icons.groups_2_rounded),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ClassExplorerSheet extends StatefulWidget {
  const _ClassExplorerSheet();

  @override
  State<_ClassExplorerSheet> createState() => _ClassExplorerSheetState();
}

class _StudentMenuDrawer extends StatelessWidget {
  const _StudentMenuDrawer();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final name = (auth.name ?? "Student").toString();
    final role = (auth.role ?? "STUDENT").toString();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final bg = isDark ? AppColors.darkSurfaceElevated : AppColors.lightSurfaceSoft;
    final fg = scheme.onSurface;
    return Drawer(
      width: 300,
      backgroundColor: bg,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 34,
                          backgroundColor: fg.withValues(alpha: 0.14),
                          backgroundImage: const NetworkImage(
                            "https://i.pravatar.cc/200?img=12",
                          ),
                          onBackgroundImageError: (_, __) {},
                          child: null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name.toUpperCase(),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: fg,
                                  fontSize: 26,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.4,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                role,
                                style: TextStyle(color: fg.withValues(alpha: 0.75), fontSize: 22),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 40),
                ],
              ),
              const SizedBox(height: 18),
              const _DrawerSectionLabel("Main"),
              _DrawerItem(
                title: "Home",
                active: true,
                onTap: () => Navigator.of(context).pop(),
              ),
              _DrawerItem(
                title: "Settings",
                onTap: () {
                  Navigator.of(context).pop();
                  final shell =
                      context.findAncestorStateOfType<_AppShellState>();
                  shell?._onTabSelected(4);
                },
              ),
              _DrawerItem(
                title: "Cast",
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    AppTransitions.fadeSlide(const HelloCastsScreen()),
                  );
                },
              ),
              _DrawerItem(
                title: "Profile",
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    AppTransitions.fadeSlide(const ProfileScreen()),
                  );
                },
              ),
              const SizedBox(height: 8),
              const _DrawerSectionLabel("Services"),
              _DrawerItem(
                title: "Notifications",
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    AppTransitions.fadeSlide(const _StudentNotificationsScreen()),
                  );
                },
              ),
              _DrawerItem(
                title: "Documentation",
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    AppTransitions.fadeSlide(const _StudentDocumentationScreen()),
                  );
                },
              ),
              if (role == "STUDENT")
                _DrawerItem(
                  title: "Railway Concession",
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const RailwayConcessionScreen()),
                    );
                  },
                ),
              const SizedBox(height: 8),
              const _DrawerSectionLabel("Support"),
              _DrawerItem(title: "Departments", onTap: () => Navigator.of(context).pop()),
              _DrawerItem(title: "About", onTap: () => Navigator.of(context).pop()),
              _DrawerItem(title: "Report a bug", onTap: () => Navigator.of(context).pop()),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () async {
                    Navigator.of(context).pop();
                    await context.read<AuthProvider>().logout();
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: fg.withValues(alpha: 0.12),
                    foregroundColor: const Color(0xFFFF6464),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text("Logout", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  const _DrawerItem({
    required this.title,
    required this.onTap,
    this.active = false,
  });

  final String title;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return ListTile(
      dense: true,
      visualDensity: const VisualDensity(horizontal: -1, vertical: -1),
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      title: Text(
        title,
        style: TextStyle(
          color: active ? Theme.of(context).colorScheme.primary : onSurface,
          fontSize: 18,
          fontWeight: active ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      onTap: onTap,
    );
  }
}

class _DrawerSectionLabel extends StatelessWidget {
  const _DrawerSectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 2),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          letterSpacing: 1.1,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55),
        ),
      ),
    );
  }
}

class _StudentNotificationsScreen extends StatelessWidget {
  const _StudentNotificationsScreen();

  static const List<Map<String, String>> _sampleNotifications = [
    {
      "title": "Profile Updated",
      "body": "Your profile details were updated successfully.",
      "time": "Just now",
    },
    {
      "title": "Concession Request Submitted",
      "body": "Your railway concession request is under review.",
      "time": "10 min ago",
    },
    {
      "title": "Attendance Reminder",
      "body": "Lecture starts at 3:30 PM. Please mark presence on time.",
      "time": "1 hour ago",
    },
    {
      "title": "Document Verification",
      "body": "Your uploaded ID card has been verified.",
      "time": "Today, 9:15 AM",
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Notifications")),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        children: [
          const SectionTitle("Recent"),
          const SizedBox(height: 8),
          ..._sampleNotifications.map((row) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.notifications_active_rounded, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            row["title"] ?? "Notification",
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Text(
                          row["time"] ?? "",
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.color
                                ?.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(row["body"] ?? ""),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _StudentDocumentationScreen extends StatefulWidget {
  const _StudentDocumentationScreen();

  @override
  State<_StudentDocumentationScreen> createState() =>
      _StudentDocumentationScreenState();
}

class _StudentDocumentationScreenState extends State<_StudentDocumentationScreen> {
  final Map<String, String?> _admissionDocs = {
    "10th Marksheet": null,
    "12th Marksheet": null,
    "Leaving Certificate": null,
    "Aadhaar Card": null,
    "Passport Photo": null,
  };

  final Map<String, String?> _throughoutDocs = {
    "Semester Result": null,
    "Bonafide Certificate": null,
    "Internship Letter": null,
    "Fee Receipt": null,
  };

  Future<void> _pickDoc({
    required bool admission,
    required String key,
  }) async {
    final file = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: const ["pdf", "jpg", "jpeg", "png"],
    );
    if (file == null || file.files.isEmpty) {
      return;
    }
    final name = file.files.first.name;
    if (!mounted) {
      return;
    }
    setState(() {
      if (admission) {
        _admissionDocs[key] = name;
      } else {
        _throughoutDocs[key] = name;
      }
    });
  }

  Widget _docSection({
    required String title,
    required Map<String, String?> docs,
    required bool admission,
  }) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          ...docs.entries.map((entry) {
            final uploaded = entry.value != null;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withValues(alpha: 0.35),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.description_outlined, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(entry.key,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                          Text(
                            entry.value ?? "Not uploaded",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.color
                                  ?.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => _pickDoc(admission: admission, key: entry.key),
                      child: Text(uploaded ? "Replace" : "Upload"),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Documentation")),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        children: [
          AppCard(
            child: Text(
              "Upload all required college documents here. You can update files anytime.",
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: 12),
          _docSection(
            title: "Admission Documents",
            docs: _admissionDocs,
            admission: true,
          ),
          const SizedBox(height: 12),
          _docSection(
            title: "Throughout College Documents",
            docs: _throughoutDocs,
            admission: false,
          ),
          const SizedBox(height: 12),
          AppButton(
            label: "Submit All Documents",
            icon: Icons.cloud_upload_rounded,
            onPressed: () {
              GlassToast.show(
                context,
                "Sample: Documents submitted successfully.",
                icon: Icons.check_circle_outline,
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ShareItScreen extends StatefulWidget {
  const _ShareItScreen();

  @override
  State<_ShareItScreen> createState() => _ShareItScreenState();
}

class _ShareItScreenState extends State<_ShareItScreen> {
  final ApiService _api = ApiService();
  bool _loading = false;
  bool _offline = false;
  List<Map<String, dynamic>> _appointments = [];
  List<Map<String, dynamic>> _students = [];
  Timer? _syncTimer;

  final TextEditingController _documentTypeController =
      TextEditingController(text: "Hall Ticket");
  final TextEditingController _venue = TextEditingController();
  final TextEditingController _notes = TextEditingController();
  String? _selectedClass;
  final Set<int> _selectedStudentIds = <int>{};
  DateTime? _selectedDate;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;

  static const List<Map<String, dynamic>> _demoStudents = [
    {"id": 101, "name": "Aarav Patil", "email": "aarav@sigce.edu.in", "class_name": "AIDS-A"},
    {"id": 102, "name": "Diya Shinde", "email": "diya@sigce.edu.in", "class_name": "AIDS-A"},
    {"id": 103, "name": "Rohan Kale", "email": "rohan@sigce.edu.in", "class_name": "AIDS-B"},
    {"id": 104, "name": "Meera Joshi", "email": "meera@sigce.edu.in", "class_name": "AIDS-B"},
  ];

  @override
  void initState() {
    super.initState();
    final now = TimeFormat.nowIst().add(const Duration(days: 1));
    _selectedDate = DateTime(now.year, now.month, now.day);
    _startTime = TimeOfDay(hour: 10, minute: 0);
    _endTime = TimeOfDay(hour: 11, minute: 0);
    _load();
    _syncTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _load(silent: true);
    });
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _documentTypeController.dispose();
    _venue.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    setState(() => _loading = true);
    final res = await _api.listShareItAppointments();
    final studentRes = await _api.studentsList();
    final isOffline = !(await _api.isBackendOnlineCached());
    List<Map<String, dynamic>> nextRows = _appointments;
    List<Map<String, dynamic>> nextStudents = _students;
    if (isOffline) {
      nextRows =
          (await _api.readCache("share_it_appointments") as List<dynamic>?)
                  ?.whereType<Map<String, dynamic>>()
                  .toList() ??
              nextRows;
      nextStudents = (await _api.readCache("share_it_students") as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .toList() ??
          (nextStudents.isEmpty ? _demoStudents : nextStudents);
    } else if (res.statusCode >= 200 && res.statusCode < 300) {
      nextRows = (jsonDecode(res.body) as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .toList();
      await _api.saveCache("share_it_appointments", nextRows);
      if (studentRes.statusCode >= 200 && studentRes.statusCode < 300) {
        nextStudents = (jsonDecode(studentRes.body) as List<dynamic>)
            .whereType<Map<String, dynamic>>()
            .toList();
        await _api.saveCache("share_it_students", nextStudents);
      } else if (nextStudents.isEmpty) {
        nextStudents = _demoStudents;
      }
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _loading = false;
      _offline = isOffline;
      _appointments = nextRows;
      _students = nextStudents;
      final classes = _classOptions();
      if (classes.isNotEmpty) {
        _selectedClass ??= classes.first;
      }
    });
    final calendarRows = <_CalendarEntry>[];
    for (final row in nextRows) {
      final id = (row["id"] ?? "").toString();
      if (id.isEmpty) {
        continue;
      }
      final when = TimeFormat.parseToIst(row["appointment_at"]?.toString()) ??
          _CalendarSync.parseFlexibleDateTime(
              row["appointment_at"]?.toString() ?? "") ??
          TimeFormat.nowIst();
      final start = (when.hour * 60) + when.minute;
      final status = (row["status"] ?? "PENDING").toString();
      final docType = (row["document_type"] ?? "Document").toString();
      final student = (row["student_name"] ?? "Student").toString();
      calendarRows.add(
        _CalendarEntry(
          id: "doced-appointment-$id",
          dayKey:
              "${when.year}-${when.month.toString().padLeft(2, "0")}-${when.day.toString().padLeft(2, "0")}",
          title: "DocEd: $docType",
          details: "$student • Status: $status",
          type: "EVENT",
          startMinutes: start,
          endMinutes: (start + 60).clamp(0, 1439),
        ),
      );
    }
    await _CalendarSync.upsertBatch(calendarRows);
  }

  String _detail(String body, {String fallback = "Request failed"}) {
    try {
      final map = jsonDecode(body) as Map<String, dynamic>;
      return (map["detail"] ?? fallback).toString();
    } catch (_) {
      return fallback;
    }
  }

  Future<void> _create() async {
    final docType = _documentTypeController.text.trim();
    if (docType.isEmpty ||
        _selectedClass == null ||
        _selectedStudentIds.isEmpty ||
        _selectedDate == null ||
        _startTime == null ||
        _endTime == null) {
      return;
    }
    final startDate = DateTime(
      _selectedDate!.year,
      _selectedDate!.month,
      _selectedDate!.day,
      _startTime!.hour,
      _startTime!.minute,
    );
    final endDate = DateTime(
      _selectedDate!.year,
      _selectedDate!.month,
      _selectedDate!.day,
      _endTime!.hour,
      _endTime!.minute,
    );
    final startLabel = TimeFormat.formatMinutes12h(
      (_startTime!.hour * 60) + _startTime!.minute,
    );
    final endLabel = TimeFormat.formatMinutes12h(
      (_endTime!.hour * 60) + _endTime!.minute,
    );
    final mergedNotes = [
      if (_notes.text.trim().isNotEmpty) _notes.text.trim(),
      "Window: $startLabel - $endLabel",
      "Class: $_selectedClass",
    ].join(" | ");

    final selected = _students
        .where((s) => _selectedStudentIds.contains((s["id"] as num?)?.toInt()))
        .toList();
    var success = 0;
    for (final student in selected) {
      final res = await _api.createShareItAppointment(
        documentType: docType,
        studentName: (student["name"] ?? "Student").toString(),
        studentEmail: (student["email"] ?? "").toString().trim().toLowerCase(),
        appointmentAt: startDate.toUtc().toIso8601String(),
        venue: _venue.text.trim(),
        notes: mergedNotes,
      );
      if (res.statusCode >= 200 && res.statusCode < 300) {
        success += 1;
      }
    }
    if (success > 0) {
      await _CalendarSync.upsert(
        id: "doced-created-${DateTime.now().microsecondsSinceEpoch}",
        when: startDate,
        title: "DocEd Appointment Created",
        details: "$docType • $_selectedClass • $success students",
        durationMinutes:
            endDate.difference(startDate).inMinutes <= 0 ? 60 : endDate.difference(startDate).inMinutes,
      );
      _venue.clear();
      _notes.clear();
      _selectedStudentIds.clear();
      await _load();
      if (!mounted) {
        return;
      }
      GlassToast.show(
        context,
        "Created $success appointment(s).",
        icon: Icons.check_circle_outline,
      );
      return;
    }
    if (!mounted) {
      return;
    }
    GlassToast.show(
      context,
      "Unable to create appointments. Please retry.",
      icon: Icons.error_outline,
    );
  }

  List<String> _classOptions() {
    final set = <String>{};
    for (final s in _students) {
      final label = _classLabel(s);
      if (label.isNotEmpty) {
        set.add(label);
      }
    }
    final list = set.toList()..sort();
    return list;
  }

  String _classLabel(Map<String, dynamic> s) {
    final candidates = [
      s["class_name"],
      s["classroom"],
      s["division"],
      s["section"],
      s["department_name"],
      s["department_id"] == null ? null : "Class ${s["department_id"]}",
    ];
    for (final c in candidates) {
      final text = (c ?? "").toString().trim();
      if (text.isNotEmpty) {
        return text;
      }
    }
    return "";
  }

  List<Map<String, dynamic>> _studentsForClass() {
    final selected = _selectedClass;
    if (selected == null || selected.isEmpty) {
      return const [];
    }
    return _students.where((s) => _classLabel(s) == selected).toList();
  }

  Future<void> _pickDate() async {
    final now = TimeFormat.nowIst();
    final initial = _selectedDate ?? DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) {
      return;
    }
    setState(() => _selectedDate = picked);
  }

  Future<void> _pickTime({required bool isStart}) async {
    final current = isStart ? _startTime : _endTime;
    final picked = await showTimePicker(
      context: context,
      initialTime: current ?? const TimeOfDay(hour: 10, minute: 0),
    );
    if (picked == null) {
      return;
    }
    setState(() {
      if (isStart) {
        _startTime = picked;
      } else {
        _endTime = picked;
      }
    });
  }

  String _fmtDate(DateTime? date) {
    if (date == null) {
      return "Select date";
    }
    return TimeFormat.formatDate(date);
  }

  String _fmtTime(TimeOfDay? t) {
    if (t == null) {
      return "--:--";
    }
    return TimeFormat.formatMinutes12h((t.hour * 60) + t.minute);
  }

  Future<void> _markCollected(int id) async {
    final res = await _api.markShareItCollected(id);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      await _CalendarSync.upsert(
        id: "doced-collected-$id",
        when: TimeFormat.nowIst(),
        title: "DocEd Document Collected",
        details: "Appointment #$id marked as collected",
      );
      await _load();
      return;
    }
    if (!mounted) {
      return;
    }
    GlassToast.show(
      context,
      _detail(res.body),
      icon: Icons.error_outline,
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final role = auth.role ?? "STUDENT";
    final canManage = role == "PROFESSOR" || role == "ADMIN";
    return Scaffold(
      appBar: AppBar(title: const Text("DocEd")),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 20),
        children: [
            if (_offline)
              const Card(
                child: ListTile(
                  leading: Icon(Icons.wifi_off_rounded),
                  title: Text("Offline mode"),
                  subtitle: Text("Showing last synced appointments."),
                ),
              ),
            if (_offline) const SizedBox(height: 10),
            const Text(
              "Appointment-based document distribution for railway concession, results, hall tickets, ID cards, etc.",
            ),
            const SizedBox(height: 12),
            if (canManage)
              AppCard(
                child: Column(
                  children: [
                    TextField(
                      controller: _documentTypeController,
                      decoration: const InputDecoration(
                        labelText: "Document Type",
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedClass,
                      decoration: const InputDecoration(labelText: "Class"),
                      items: _classOptions()
                          .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                          .toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedClass = value;
                          _selectedStudentIds.clear();
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    Builder(
                      builder: (_) {
                        final classStudents = _studentsForClass();
                        final total = classStudents.length;
                        final selectedCount = classStudents
                            .where((s) => _selectedStudentIds
                                .contains((s["id"] as num?)?.toInt()))
                            .length;
                        final allSelected = total > 0 && selectedCount == total;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  "Students ($selectedCount/$total)",
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700),
                                ),
                                const Spacer(),
                                TextButton(
                                  onPressed: total == 0
                                      ? null
                                      : () {
                                          setState(() {
                                            if (allSelected) {
                                              _selectedStudentIds.removeWhere(
                                                (id) => classStudents.any(
                                                  (s) =>
                                                      (s["id"] as num?)?.toInt() ==
                                                      id,
                                                ),
                                              );
                                            } else {
                                              _selectedStudentIds.addAll(
                                                classStudents
                                                    .map((s) =>
                                                        (s["id"] as num?)?.toInt())
                                                    .whereType<int>(),
                                              );
                                            }
                                          });
                                        },
                                  child: Text(allSelected ? "Unselect All" : "Select All"),
                                ),
                              ],
                            ),
                            if (classStudents.isEmpty)
                              const Padding(
                                padding: EdgeInsets.only(top: 4),
                                child: Text("No students in selected class."),
                              )
                            else
                              ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxHeight: 180),
                                child: ListView(
                                  shrinkWrap: true,
                                  children: classStudents.map((student) {
                                    final id =
                                        (student["id"] as num?)?.toInt() ?? -1;
                                    final checked =
                                        _selectedStudentIds.contains(id);
                                    return CheckboxListTile(
                                      contentPadding: EdgeInsets.zero,
                                      value: checked,
                                      onChanged: (_) {
                                        setState(() {
                                          if (checked) {
                                            _selectedStudentIds.remove(id);
                                          } else {
                                            _selectedStudentIds.add(id);
                                          }
                                        });
                                      },
                                      title: Text(
                                          (student["name"] ?? "Student").toString()),
                                      subtitle: Text(
                                          (student["email"] ?? "-").toString()),
                                      controlAffinity:
                                          ListTileControlAffinity.leading,
                                    );
                                  }).toList(),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _pickDate,
                            icon: const Icon(Icons.calendar_today_rounded, size: 16),
                            label: Text(_fmtDate(_selectedDate)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _pickTime(isStart: true),
                            child: Text("Start ${_fmtTime(_startTime)}"),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _pickTime(isStart: false),
                            child: Text("End ${_fmtTime(_endTime)}"),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _venue,
                      decoration: const InputDecoration(
                        labelText: "Venue / Counter",
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _notes,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: "Notes / Required proof",
                        alignLabelWithHint: true,
                      ),
                    ),
                    const SizedBox(height: 10),
                    AppButton(
                      label: "Create Appointment",
                      onPressed: _create,
                      icon: Icons.event_available_rounded,
                    ),
                  ],
                ),
              ),
            if (canManage) const SizedBox(height: 12),
            if (_loading)
              const LoadingSkeleton(height: 120)
            else if (_appointments.isEmpty)
              const EmptyStateWidget(message: "No DocEd appointments yet")
            else
              ..._appointments.map(
                (row) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                (row["document_type"] ?? "-").toString(),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            StatusBadge(
                              label: (row["status"] ?? "PENDING").toString(),
                              color: (row["status"] ?? "PENDING")
                                          .toString()
                                          .toUpperCase() ==
                                      "COLLECTED"
                                  ? Colors.green
                                  : Colors.orange,
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          "Student: ${(row["student_name"] ?? "-")} (${(row["student_email"] ?? "-")})",
                        ),
                        Text("Appointment: ${(row["appointment_at"] ?? "-")}"),
                        if ((row["venue"] ?? "").toString().isNotEmpty)
                          Text("Venue: ${(row["venue"] ?? "").toString()}"),
                        if ((row["notes"] ?? "").toString().isNotEmpty)
                          Text("Notes: ${(row["notes"] ?? "").toString()}"),
                        if (canManage &&
                            (row["status"] ?? "").toString().toUpperCase() !=
                                "COLLECTED")
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () => _markCollected(
                                (row["id"] as num?)?.toInt() ?? -1,
                              ),
                              child: const Text("Mark Collected"),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _ClassExplorerSheetState extends State<_ClassExplorerSheet> {
  final ApiService _api = ApiService();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _students = [];
  Map<int, _AttendanceSummary> _attendanceByStudent = {};
  int _step = 0;
  _ClassGroup? _selectedClass;
  Map<String, dynamic>? _selectedStudent;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (kUseDemoDataEverywhere) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = null;
        _students = [
          {
            "id": 101,
            "name": "Aarav Patil",
            "email": "aarav@edusys.edu",
            "department_id": 1,
            "role": "STUDENT"
          },
          {
            "id": 102,
            "name": "Diya Shinde",
            "email": "diya@edusys.edu",
            "department_id": 1,
            "role": "STUDENT"
          },
          {
            "id": 103,
            "name": "Rohan Kale",
            "email": "rohan@edusys.edu",
            "department_id": 2,
            "role": "STUDENT"
          },
          {
            "id": 104,
            "name": "Sara Thomas",
            "email": "sara@edusys.edu",
            "department_id": 2,
            "role": "STUDENT"
          },
        ];
        _attendanceByStudent = {
          101: _AttendanceSummary(
              present: 22, absent: 3, presenceDuration: 56000),
          102: _AttendanceSummary(
              present: 19, absent: 6, presenceDuration: 50200),
          103: _AttendanceSummary(
              present: 21, absent: 4, presenceDuration: 54400),
          104: _AttendanceSummary(
              present: 17, absent: 8, presenceDuration: 46800),
        };
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final usersResp = await _api.usersStudents();
      List<dynamic> rawStudents = [];

      if (usersResp.statusCode >= 200 && usersResp.statusCode < 300) {
        rawStudents = (jsonDecode(usersResp.body) as List<dynamic>);
      } else {
        final fallbackResp = await _api.studentsList();
        if (fallbackResp.statusCode >= 200 && fallbackResp.statusCode < 300) {
          rawStudents = (jsonDecode(fallbackResp.body) as List<dynamic>);
        }
      }

      final normalized = rawStudents
          .whereType<Map<String, dynamic>>()
          .map((student) => <String, dynamic>{
                "id": student["id"],
                "name": (student["name"] ?? "Unknown").toString(),
                "email": (student["email"] ?? "-").toString(),
                "department_id": student["department_id"],
                "role": (student["role"] ?? "STUDENT").toString(),
              })
          .toList();
      if (normalized.isEmpty) {
        normalized.addAll([
          {
            "id": 101,
            "name": "Aarav Mehta",
            "email": "aarav@edusys.edu",
            "department_id": 1,
            "role": "STUDENT"
          },
          {
            "id": 102,
            "name": "Diya Rao",
            "email": "diya@edusys.edu",
            "department_id": 1,
            "role": "STUDENT"
          },
          {
            "id": 103,
            "name": "Kabir Shah",
            "email": "kabir@edusys.edu",
            "department_id": 2,
            "role": "STUDENT"
          },
          {
            "id": 104,
            "name": "Sara Thomas",
            "email": "sara@edusys.edu",
            "department_id": 2,
            "role": "STUDENT"
          },
          {
            "id": 105,
            "name": "Rohan Iyer",
            "email": "rohan@edusys.edu",
            "department_id": 3,
            "role": "STUDENT"
          },
        ]);
      }

      final attendanceResp = await _api.adminAllAttendance();
      final attendance = <int, _AttendanceSummary>{};
      if (attendanceResp.statusCode >= 200 &&
          attendanceResp.statusCode < 300) {
        final rows = jsonDecode(attendanceResp.body) as List<dynamic>;
        for (final row in rows) {
          if (row is! Map<String, dynamic>) {
            continue;
          }
          final studentId = row["student_id"];
          if (studentId is! int) {
            continue;
          }
          final summary =
              attendance.putIfAbsent(studentId, _AttendanceSummary.new);
          final status = (row["status"] ?? "").toString().toUpperCase();
          if (status == "PRESENT") {
            summary.present += 1;
          } else if (status == "ABSENT") {
            summary.absent += 1;
          }
          summary.presenceDuration +=
              (row["presence_duration"] as num?)?.toInt() ?? 0;
        }
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _students = normalized;
        _attendanceByStudent = attendance;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = "Unable to load class data right now.";
      });
    }
  }

  List<_ClassGroup> _buildClassGroups() {
    final map = <String, List<Map<String, dynamic>>>{};
    for (final student in _students) {
      final dep = student["department_id"];
      final key = dep == null ? "General Class" : "Class $dep";
      map.putIfAbsent(key, () => []).add(student);
    }
    return map.entries
        .map((entry) => _ClassGroup(name: entry.key, students: entry.value))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  _AttendanceSummary _summaryFor(int studentId) {
    final existing = _attendanceByStudent[studentId];
    if (existing != null) {
      return existing;
    }
    final seed = (studentId % 8) + 2;
    return _AttendanceSummary(
      present: seed + 8,
      absent: seed ~/ 2,
      presenceDuration: (seed + 8) * 2400,
    );
  }

  List<String> _syntheticResults(int studentId) {
    final seed = (studentId % 5) + 75;
    return [
      "Semester GPA: ${(seed / 10).toStringAsFixed(1)}",
      "Mathematics: ${seed + 8}%",
      "Computer Science: ${seed + 10}%",
      "Physics: ${seed + 4}%",
    ];
  }

  List<String> _syntheticCerts(int studentId) {
    final seed = studentId % 3;
    final certs = [
      "Python Programming Certificate",
      "Data Analytics Fundamentals",
      "Cloud Basics (AWS Academy)",
    ];
    return certs.take(seed + 1).toList();
  }

  List<String> _syntheticAchievements(int studentId) {
    final seed = studentId % 4;
    final achievements = [
      "Top 10% Attendance consistency",
      "Inter-college coding finalist",
      "Department project showcase winner",
      "Hackathon participation",
    ];
    return achievements.take(seed + 1).toList();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final groups = _buildClassGroups();

    return DraggableScrollableSheet(
      initialChildSize: 0.74,
      minChildSize: 0.44,
      maxChildSize: 0.94,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color.alphaBlend(
                  scheme.primary.withValues(alpha: dark ? 0.12 : 0.08),
                  scheme.surface,
                ),
                scheme.surface,
              ],
            ),
            border: Border.all(
              color: scheme.onSurface.withValues(alpha: dark ? 0.18 : 0.10),
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.onSurface.withValues(alpha: 0.24),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 12, 6),
                child: Row(
                  children: [
                    if (_step > 0)
                      IconButton(
                        onPressed: () {
                          setState(() {
                            if (_step == 2) {
                              _selectedStudent = null;
                            }
                            if (_step == 1) {
                              _selectedClass = null;
                            }
                            _step -= 1;
                          });
                        },
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                    Expanded(
                      child: Text(
                        _step == 0
                            ? "Classes"
                            : _step == 1
                                ? (_selectedClass?.name ?? "Students")
                                : (_selectedStudent?["name"]?.toString() ??
                                    "Student Details"),
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? Center(
                            child: Text(
                              _error!,
                              style: TextStyle(color: scheme.error),
                            ),
                          )
                        : _step == 0
                            ? ListView.separated(
                                controller: scrollController,
                                padding: const EdgeInsets.all(14),
                                itemCount: groups.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 10),
                                itemBuilder: (context, index) {
                                  final group = groups[index];
                                  return AppCard(
                                    child: ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      leading: Icon(Icons.class_rounded,
                                          color: scheme.primary),
                                      title: Text(group.name,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w700)),
                                      subtitle: Text(
                                          "${group.students.length} students"),
                                      trailing: const Icon(
                                          Icons.chevron_right_rounded),
                                      onTap: () {
                                        setState(() {
                                          _selectedClass = group;
                                          _step = 1;
                                        });
                                      },
                                    ),
                                  );
                                },
                              )
                            : _step == 1
                                ? ListView.separated(
                                    controller: scrollController,
                                    padding: const EdgeInsets.all(14),
                                    itemCount:
                                        _selectedClass?.students.length ?? 0,
                                    separatorBuilder: (_, __) =>
                                        const SizedBox(height: 10),
                                    itemBuilder: (context, index) {
                                      final student =
                                          _selectedClass!.students[index];
                                      final id = student["id"] as int? ?? 0;
                                      final summary = _summaryFor(id);
                                      return AppCard(
                                        child: ListTile(
                                          contentPadding: EdgeInsets.zero,
                                          leading: CircleAvatar(
                                            backgroundColor: scheme.primary
                                                .withValues(alpha: 0.14),
                                            child: Icon(Icons.person_rounded,
                                                color: scheme.primary),
                                          ),
                                          title:
                                              Text(student["name"].toString()),
                                          subtitle: Text(
                                            "${student["email"]}\nP: ${summary.present}  A: ${summary.absent}",
                                          ),
                                          isThreeLine: true,
                                          trailing: const Icon(
                                              Icons.chevron_right_rounded),
                                          onTap: () {
                                            setState(() {
                                              _selectedStudent = student;
                                              _step = 2;
                                            });
                                          },
                                        ),
                                      );
                                    },
                                  )
                                : _buildStudentDetail(scrollController),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStudentDetail(ScrollController scrollController) {
    final scheme = Theme.of(context).colorScheme;
    final student = _selectedStudent;
    if (student == null) {
      return const SizedBox.shrink();
    }
    final id = student["id"] as int? ?? 0;
    final summary = _summaryFor(id);
    final total = summary.present + summary.absent;
    final percent = total == 0 ? 0 : ((summary.present / total) * 100).round();

    final results = _syntheticResults(id);
    final certs = _syntheticCerts(id);
    final achievements = _syntheticAchievements(id);

    Widget section(String title, List<String> items) {
      return AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            ...items.map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("• ", style: TextStyle(color: scheme.primary)),
                      Expanded(child: Text(item)),
                    ],
                  ),
                )),
          ],
        ),
      );
    }

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.all(14),
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Name: ${student["name"]}",
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text("Email: ${student["email"]}"),
              const SizedBox(height: 6),
              Text("ID: $id"),
              const SizedBox(height: 6),
              Text("Class: ${_selectedClass?.name ?? "General Class"}"),
            ],
          ),
        ),
        section("Attendance", [
          "Present: ${summary.present}",
          "Absent: ${summary.absent}",
          "Attendance %: $percent%",
          "Presence Duration: ${summary.presenceDuration ~/ 60} minutes",
        ]),
        section("Results", results),
        section("Certifications", certs),
        section("Achievements", achievements),
      ],
    );
  }
}

class _ClassGroup {
  _ClassGroup({
    required this.name,
    required this.students,
  });

  final String name;
  final List<Map<String, dynamic>> students;
}

class _AttendanceSummary {
  _AttendanceSummary({
    this.present = 0,
    this.absent = 0,
    this.presenceDuration = 0,
  });

  int present;
  int absent;
  int presenceDuration;
}

const String kCalendarEntriesStorageKey = "calendar_entries_v1";

class _CalendarSync {
  static Future<List<_CalendarEntry>> _readEntries() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(kCalendarEntriesStorageKey);
    if (raw == null || raw.isEmpty) {
      return <_CalendarEntry>[];
    }
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(_CalendarEntry.fromJson)
          .toList();
    } catch (_) {
      return <_CalendarEntry>[];
    }
  }

  static Future<void> _writeEntries(List<_CalendarEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(entries.map((entry) => entry.toJson()).toList());
    await prefs.setString(kCalendarEntriesStorageKey, raw);
  }

  static String _dayKey(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    final mm = d.month.toString().padLeft(2, "0");
    final dd = d.day.toString().padLeft(2, "0");
    return "${d.year}-$mm-$dd";
  }

  static DateTime? parseFlexibleDateTime(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final direct = TimeFormat.parseToIst(trimmed);
    if (direct != null) {
      return direct;
    }
    final cleaned = trimmed.replaceAll(" IST", "").trim();
    final fallback = TimeFormat.parseToIst(cleaned);
    if (fallback != null) {
      return fallback;
    }
    final match = RegExp(
      r"^(\d{2})/(\d{2})/(\d{4})\s+(\d{1,2}):(\d{2})\s*(AM|PM)$",
      caseSensitive: false,
    ).firstMatch(cleaned.toUpperCase());
    if (match == null) {
      return null;
    }
    final dd = int.tryParse(match.group(1) ?? "");
    final mm = int.tryParse(match.group(2) ?? "");
    final yyyy = int.tryParse(match.group(3) ?? "");
    var hh = int.tryParse(match.group(4) ?? "");
    final min = int.tryParse(match.group(5) ?? "");
    final period = (match.group(6) ?? "AM").toUpperCase();
    if (dd == null || mm == null || yyyy == null || hh == null || min == null) {
      return null;
    }
    hh = hh % 12;
    if (period == "PM") {
      hh += 12;
    }
    return DateTime(yyyy, mm, dd, hh, min);
  }

  static Future<void> upsert({
    required String id,
    required DateTime when,
    required String title,
    required String details,
    String type = "EVENT",
    int? durationMinutes,
  }) async {
    final start = (when.hour * 60) + when.minute;
    final safeDuration =
        (durationMinutes == null || durationMinutes <= 0) ? 60 : durationMinutes;
    final end = (start + safeDuration).clamp(0, 1439);
    final entry = _CalendarEntry(
      id: id,
      dayKey: _dayKey(when),
      title: title,
      details: details,
      type: type,
      startMinutes: start,
      endMinutes: end,
    );
    final entries = await _readEntries();
    final idx = entries.indexWhere((e) => e.id == id);
    if (idx >= 0) {
      entries[idx] = entry;
    } else {
      entries.add(entry);
    }
    await _writeEntries(entries);
  }

  static Future<void> upsertBatch(List<_CalendarEntry> items) async {
    if (items.isEmpty) {
      return;
    }
    final entries = await _readEntries();
    for (final item in items) {
      final idx = entries.indexWhere((e) => e.id == item.id);
      if (idx >= 0) {
        entries[idx] = item;
      } else {
        entries.add(item);
      }
    }
    await _writeEntries(entries);
  }
}

class _CalendarPlannerSheet extends StatefulWidget {
  const _CalendarPlannerSheet({
    required this.isProfessor,
  });

  final bool isProfessor;

  @override
  State<_CalendarPlannerSheet> createState() => _CalendarPlannerSheetState();
}

class _CalendarPlannerSheetState extends State<_CalendarPlannerSheet> {
  late DateTime _focusedMonth;
  late DateTime _selectedDay;
  bool _loading = true;
  final List<_CalendarEntry> _entries = [];

  @override
  void initState() {
    super.initState();
    final now = TimeFormat.nowIst();
    _focusedMonth = DateTime(now.year, now.month);
    _selectedDay = DateTime(now.year, now.month, now.day);
    _loadEntries();
  }

  Future<void> _loadEntries() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(kCalendarEntriesStorageKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as List<dynamic>;
        _entries
          ..clear()
          ..addAll(decoded
              .whereType<Map<String, dynamic>>()
              .map(_CalendarEntry.fromJson));
      } catch (_) {}
    }
    final monthStart = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final monthEnd = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0);
    final seedStart = monthStart.subtract(const Duration(days: 7));
    final seedEnd = monthEnd.add(const Duration(days: 7));
    final timetableSeed = _timetableEntriesForRange(seedStart, seedEnd);
    if (timetableSeed.isNotEmpty) {
      final byId = {for (final entry in _entries) entry.id: entry};
      for (final entry in timetableSeed) {
        byId[entry.id] = entry;
      }
      _entries
        ..clear()
        ..addAll(byId.values);
      await _saveEntries();
    }
    if (!mounted) {
      return;
    }
    setState(() => _loading = false);
  }

  Future<void> _saveEntries() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(_entries.map((entry) => entry.toJson()).toList());
    await prefs.setString(kCalendarEntriesStorageKey, raw);
  }

  String _dayKey(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    final mm = d.month.toString().padLeft(2, "0");
    final dd = d.day.toString().padLeft(2, "0");
    return "${d.year}-$mm-$dd";
  }

  int _eventCount(DateTime date) =>
      _entries.where((entry) => entry.dayKey == _dayKey(date)).length;

  List<_CalendarEntry> _eventsForSelectedDay() {
    final key = _dayKey(_selectedDay);
    final items = _entries.where((entry) => entry.dayKey == key).toList();
    items.sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
    return items;
  }

  DateTime _dateFromKey(String key) {
    final parts = key.split("-");
    if (parts.length != 3) {
      final now = TimeFormat.nowIst();
      return DateTime(now.year, now.month, now.day);
    }
    return DateTime(
      int.tryParse(parts[0]) ?? TimeFormat.nowIst().year,
      int.tryParse(parts[1]) ?? TimeFormat.nowIst().month,
      int.tryParse(parts[2]) ?? TimeFormat.nowIst().day,
    );
  }

  bool _isExpired(_CalendarEntry entry) {
    final day = _dateFromKey(entry.dayKey);
    final end = DateTime(
      day.year,
      day.month,
      day.day,
      entry.endMinutes ~/ 60,
      entry.endMinutes % 60,
    );
    return end.isBefore(TimeFormat.nowIst());
  }

  Future<TimeOfDay?> _pickTimeCompact(TimeOfDay initial) async {
    int hour24 = initial.hour;
    int minute = initial.minute;
    String period = hour24 >= 12 ? "PM" : "AM";

    int toHour12(int h24) {
      final mod = h24 % 12;
      return mod == 0 ? 12 : mod;
    }

    int fromHour12(int h12, String p) {
      final base = h12 % 12;
      return p == "PM" ? base + 12 : base;
    }

    return showDialog<TimeOfDay>(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 70, vertical: 220),
          child: StatefulBuilder(
            builder: (context, setLocal) {
              return Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text("Select Time",
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            initialValue: toHour12(hour24),
                            decoration:
                                const InputDecoration(labelText: "Hour"),
                            items: List.generate(
                              12,
                              (h) {
                                final v = h + 1;
                                return DropdownMenuItem(
                                    value: v,
                                    child: Text(v.toString().padLeft(2, "0")));
                              },
                            ),
                            onChanged: (value) => setLocal(() {
                              final picked = value ?? toHour12(hour24);
                              hour24 = fromHour12(picked, period);
                            }),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            initialValue: minute,
                            decoration: const InputDecoration(labelText: "Min"),
                            items: List.generate(
                              12,
                              (m) {
                                final v = m * 5;
                                return DropdownMenuItem(
                                    value: v,
                                    child: Text(v.toString().padLeft(2, "0")));
                              },
                            ),
                            onChanged: (value) =>
                                setLocal(() => minute = value ?? minute),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: period,
                            decoration:
                                const InputDecoration(labelText: "AM/PM"),
                            items: const [
                              DropdownMenuItem(value: "AM", child: Text("AM")),
                              DropdownMenuItem(value: "PM", child: Text("PM")),
                            ],
                            onChanged: (value) => setLocal(() {
                              period = value ?? period;
                              hour24 = fromHour12(toHour12(hour24), period);
                            }),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text("Cancel"),
                          ),
                        ),
                        Expanded(
                          child: FilledButton(
                            onPressed: () => Navigator.of(context)
                                .pop(TimeOfDay(hour: hour24, minute: minute)),
                            child: const Text("OK"),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _showEntryEditor({_CalendarEntry? existing}) async {
    String title = existing?.title ?? "";
    String details = existing?.details ?? "";
    bool isEvent = (existing?.type ?? "EVENT") == "EVENT";
    DateTime selectedDate =
        existing == null ? _selectedDay : _dateFromKey(existing.dayKey);
    TimeOfDay start = TimeOfDay(
      hour: (existing?.startMinutes ?? 540) ~/ 60,
      minute: (existing?.startMinutes ?? 540) % 60,
    );
    TimeOfDay end = TimeOfDay(
      hour: (existing?.endMinutes ?? 600) ~/ 60,
      minute: (existing?.endMinutes ?? 600) % 60,
    );

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        return StatefulBuilder(
          builder: (context, setLocal) {
            Future<void> pickDate() async {
              final picked = await showDatePicker(
                context: context,
                initialDate: selectedDate,
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
              );
              if (picked != null) {
                setLocal(() => selectedDate = picked);
              }
            }

            Future<void> pickStart() async {
              final picked = await _pickTimeCompact(start);
              if (picked != null) {
                setLocal(() => start = picked);
              }
            }

            Future<void> pickEnd() async {
              final picked = await _pickTimeCompact(end);
              if (picked != null) {
                setLocal(() => end = picked);
              }
            }

            String fmt(TimeOfDay t) =>
                TimeFormat.formatMinutes12h((t.hour * 60) + t.minute);

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 12,
                bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    existing == null ? "Add Schedule" : "Edit Schedule",
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    decoration: const InputDecoration(labelText: "Title"),
                    onChanged: (value) => title = value,
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    decoration:
                        const InputDecoration(labelText: "Details (optional)"),
                    onChanged: (value) => details = value,
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<bool>(
                    initialValue: isEvent,
                    decoration: const InputDecoration(labelText: "Type"),
                    items: const [
                      DropdownMenuItem(value: true, child: Text("Event")),
                      DropdownMenuItem(value: false, child: Text("Timetable")),
                    ],
                    onChanged: (value) =>
                        setLocal(() => isEvent = value ?? true),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: pickDate,
                          icon: const Icon(Icons.calendar_today_rounded,
                              size: 16),
                          label: Text(TimeFormat.formatDate(selectedDate)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: pickStart,
                          child: Text("Start ${fmt(start)}"),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: pickEnd,
                          child: Text("End ${fmt(end)}"),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: () async {
                            if (title.trim().isEmpty) {
                              return;
                            }
                            final navigator = Navigator.of(context);
                            final startMins = (start.hour * 60) + start.minute;
                            final endMins = (end.hour * 60) + end.minute;
                            final entry = _CalendarEntry(
                              id: existing?.id ??
                                  DateTime.now()
                                      .microsecondsSinceEpoch
                                      .toString(),
                              dayKey: _dayKey(selectedDate),
                              title: title.trim(),
                              details: details.trim(),
                              type: isEvent ? "EVENT" : "TIMETABLE",
                              startMinutes: startMins,
                              endMinutes: endMins,
                            );
                            setState(() {
                              if (existing == null) {
                                _entries.add(entry);
                              } else {
                                final idx = _entries
                                    .indexWhere((e) => e.id == existing.id);
                                if (idx >= 0) {
                                  _entries[idx] = entry;
                                }
                              }
                              _selectedDay = DateTime(selectedDate.year,
                                  selectedDate.month, selectedDate.day);
                              _focusedMonth = DateTime(
                                  selectedDate.year, selectedDate.month);
                            });
                            await _saveEntries();
                            if (!mounted) {
                              return;
                            }
                            navigator.pop();
                          },
                          child: Text("Save",
                              style: TextStyle(color: scheme.onPrimary)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showAddEntrySheet() => _showEntryEditor();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final firstDay = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final daysInMonth =
        DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0).day;
    final leading = firstDay.weekday % 7;
    final totalCells = leading + daysInMonth;
    final rows = (totalCells / 7).ceil();
    final events = _eventsForSelectedDay();

    String monthLabel =
        "${_monthNames[_focusedMonth.month - 1]} ${_focusedMonth.year}";

    return DraggableScrollableSheet(
      initialChildSize: 0.86,
      minChildSize: 0.48,
      maxChildSize: 0.96,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color.alphaBlend(
                  scheme.primary.withValues(alpha: dark ? 0.12 : 0.08),
                  scheme.surface,
                ),
                scheme.surface,
              ],
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(
                color: scheme.onSurface.withValues(alpha: dark ? 0.18 : 0.10)),
          ),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 16),
                  children: [
                    Center(
                      child: Container(
                        width: 44,
                        height: 4,
                        decoration: BoxDecoration(
                          color: scheme.onSurface.withValues(alpha: 0.24),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        IconButton(
                          onPressed: () => setState(() {
                            _focusedMonth = DateTime(
                                _focusedMonth.year, _focusedMonth.month - 1);
                          }),
                          icon: const Icon(Icons.chevron_left_rounded),
                        ),
                        Expanded(
                          child: Text(
                            monthLabel,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w700),
                          ),
                        ),
                        IconButton(
                          onPressed: () => setState(() {
                            _focusedMonth = DateTime(
                                _focusedMonth.year, _focusedMonth.month + 1);
                          }),
                          icon: const Icon(Icons.chevron_right_rounded),
                        ),
                        if (widget.isProfessor)
                          IconButton(
                            onPressed: _showAddEntrySheet,
                            icon: const Icon(Icons.add_circle_rounded),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: _weekNames
                          .map(
                            (d) => Expanded(
                              child: Center(
                                child: Text(
                                  d,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: scheme.onSurface
                                        .withValues(alpha: 0.72),
                                  ),
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 8),
                    ...List.generate(rows, (row) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: List.generate(7, (col) {
                            final cell = (row * 7) + col;
                            final dayNum = cell - leading + 1;
                            if (dayNum < 1 || dayNum > daysInMonth) {
                              return const Expanded(
                                  child: SizedBox(height: 46));
                            }
                            final day = DateTime(_focusedMonth.year,
                                _focusedMonth.month, dayNum);
                            final selected =
                                _dayKey(day) == _dayKey(_selectedDay);
                            final count = _eventCount(day);
                            return Expanded(
                              child: InkWell(
                                borderRadius: BorderRadius.circular(10),
                                onTap: () => setState(() => _selectedDay = day),
                                child: Container(
                                  height: 46,
                                  margin:
                                      const EdgeInsets.symmetric(horizontal: 2),
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? scheme.primary.withValues(
                                            alpha: dark ? 0.28 : 0.16)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: selected
                                          ? scheme.primary.withValues(
                                              alpha: dark ? 0.70 : 0.40)
                                          : scheme.onSurface
                                              .withValues(alpha: 0.08),
                                    ),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        "$dayNum",
                                        style: TextStyle(
                                          fontWeight: selected
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                          color: selected
                                              ? scheme.primary
                                              : scheme.onSurface,
                                        ),
                                      ),
                                      if (count > 0)
                                        Container(
                                          margin: const EdgeInsets.only(top: 3),
                                          width: 16,
                                          height: 4,
                                          decoration: BoxDecoration(
                                            color: scheme.primary
                                                .withValues(alpha: 0.8),
                                            borderRadius:
                                                BorderRadius.circular(99),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                      );
                    }),
                    const SizedBox(height: 10),
                    Text(
                      "Schedule for ${TimeFormat.formatDate(_selectedDay)} IST",
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    if (events.isEmpty)
                      AppCard(
                        child: Text(
                          widget.isProfessor
                              ? "No items scheduled. Use + to add timetable or events."
                              : "No timetable/events for this day.",
                        ),
                      )
                    else
                      ...events.map((entry) {
                        final startLabel =
                            TimeFormat.formatMinutes12h(entry.startMinutes);
                        final endLabel =
                            TimeFormat.formatMinutes12h(entry.endMinutes);
                        final isEvent = entry.type == "EVENT";
                        final expired = _isExpired(entry);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: AppCard(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 4,
                                  height: 52,
                                  margin:
                                      const EdgeInsets.only(right: 10, top: 2),
                                  decoration: BoxDecoration(
                                    color: isEvent
                                        ? scheme.secondary
                                        : scheme.primary,
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              entry.title,
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w700),
                                            ),
                                          ),
                                          if (expired)
                                            Text(
                                              "Expired",
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: scheme.error,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          if (widget.isProfessor && !expired)
                                            IconButton(
                                              visualDensity:
                                                  VisualDensity.compact,
                                              icon: const Icon(
                                                  Icons.edit_rounded,
                                                  size: 18),
                                              onPressed: () => _showEntryEditor(
                                                  existing: entry),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        "$startLabel - $endLabel IST  •  ${isEvent ? "Event" : "Timetable"}",
                                        style: TextStyle(
                                            color: scheme.onSurface
                                                .withValues(alpha: 0.72)),
                                      ),
                                      if (entry.details.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(entry.details),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                  ],
                ),
        );
      },
    );
  }
}

class _CalendarEntry {
  _CalendarEntry({
    required this.id,
    required this.dayKey,
    required this.title,
    required this.details,
    required this.type,
    required this.startMinutes,
    required this.endMinutes,
  });

  factory _CalendarEntry.fromJson(Map<String, dynamic> json) {
    return _CalendarEntry(
      id: (json["id"] ?? "").toString(),
      dayKey: (json["day_key"] ?? "").toString(),
      title: (json["title"] ?? "").toString(),
      details: (json["details"] ?? "").toString(),
      type: (json["type"] ?? "EVENT").toString(),
      startMinutes: (json["start_minutes"] as num?)?.toInt() ?? 0,
      endMinutes: (json["end_minutes"] as num?)?.toInt() ?? 0,
    );
  }

  final String id;
  final String dayKey;
  final String title;
  final String details;
  final String type;
  final int startMinutes;
  final int endMinutes;

  Map<String, dynamic> toJson() {
    return {
      "id": id,
      "day_key": dayKey,
      "title": title,
      "details": details,
      "type": type,
      "start_minutes": startMinutes,
      "end_minutes": endMinutes,
    };
  }
}

const List<String> _monthNames = [
  "January",
  "February",
  "March",
  "April",
  "May",
  "June",
  "July",
  "August",
  "September",
  "October",
  "November",
  "December",
];

const List<String> _weekNames = [
  "Sun",
  "Mon",
  "Tue",
  "Wed",
  "Thu",
  "Fri",
  "Sat"
];

class _BottomTabSection extends StatefulWidget {
  const _BottomTabSection({
    required this.selectedIndex,
    required this.onTap,
  });

  final int selectedIndex;
  final ValueChanged<int> onTap;

  static const List<({IconData icon, String label})> _tabs = [
    (icon: Icons.home_rounded, label: "Home"),
    (icon: Icons.note_alt_rounded, label: "LearnEd"),
    (icon: Icons.school_rounded, label: "ConnectEd"),
    (icon: Icons.assessment_rounded, label: "AttendEd"),
  ];

  @override
  State<_BottomTabSection> createState() => _BottomTabSectionState();
}

class _BottomTabSectionState extends State<_BottomTabSection> {
  static const int _visibleTabs = 4;
  late final PageController _pageController;

  int _pageCount() {
    final count = _BottomTabSection._tabs.length - _visibleTabs + 1;
    return count > 0 ? count : 1;
  }

  int _pageForIndex(int index) {
    final maxPage = _pageCount() - 1;
    final page = index - (_visibleTabs - 1);
    if (page < 0) {
      return 0;
    }
    if (page > maxPage) {
      return maxPage;
    }
    return page;
  }

  @override
  void initState() {
    super.initState();
    _pageController =
        PageController(initialPage: _pageForIndex(widget.selectedIndex));
  }

  @override
  void didUpdateWidget(covariant _BottomTabSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldPage = _pageForIndex(oldWidget.selectedIndex);
    final newPage = _pageForIndex(widget.selectedIndex);
    if (oldPage != newPage && _pageController.hasClients) {
      _pageController.animateToPage(
        newPage,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final lowEnd = PerfConfig.lowEnd(context);
    final pageCount = _pageCount();
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: lowEnd
              ? Container(
                  height: 76,
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: Colors.black.withValues(alpha: dark ? 0.20 : 0.08),
                    ),
                  ),
                  child: LayoutBuilder(
                builder: (context, constraints) {
                  const itemGap = 4.0;
                  final itemWidth =
                      (constraints.maxWidth - (itemGap * (_visibleTabs - 1))) /
                          _visibleTabs;

                  return PageView.builder(
                    controller: _pageController,
                    padEnds: false,
                    itemCount: pageCount,
                    itemBuilder: (context, pageIndex) {
                      final start = pageIndex;
                      return Row(
                        children: List.generate(_visibleTabs, (slot) {
                          final tabIndex = start + slot;
                          final isLastSlot = slot == _visibleTabs - 1;
                          if (tabIndex >= _BottomTabSection._tabs.length) {
                            return Expanded(
                              child: Padding(
                                padding: EdgeInsets.only(
                                    right: isLastSlot ? 0 : itemGap),
                                child: const SizedBox(height: 60),
                              ),
                            );
                          }

                          final tab = _BottomTabSection._tabs[tabIndex];
                          final selected = tabIndex == widget.selectedIndex;

                          return Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(
                                  right: isLastSlot ? 0 : itemGap),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: () => widget.onTap(tabIndex),
                              child: AnimatedContainer(
                                  duration: lowEnd ? Duration.zero : const Duration(milliseconds: 220),
                                  curve: Curves.easeOutCubic,
                                  width: itemWidth,
                                  height: 60,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: selected
                                          ? [
                                              scheme.primary.withValues(
                                                  alpha: dark ? 0.34 : 0.24),
                                              scheme.primary.withValues(
                                                  alpha: dark ? 0.18 : 0.12),
                                            ]
                                          : [
                                              scheme.onSurface.withValues(
                                                  alpha: dark ? 0.10 : 0.05),
                                              scheme.onSurface.withValues(
                                                  alpha: dark ? 0.06 : 0.02),
                                            ],
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: selected
                                          ? scheme.primary.withValues(
                                              alpha: dark ? 0.78 : 0.52)
                                          : scheme.onSurface.withValues(
                                              alpha: dark ? 0.18 : 0.12),
                                    ),
                                    boxShadow: lowEnd
                                        ? null
                                        : [
                                            if (selected)
                                              BoxShadow(
                                                color: scheme.primary.withValues(
                                                    alpha: dark ? 0.36 : 0.24),
                                                blurRadius: 14,
                                                offset: const Offset(0, 4),
                                              ),
                                          ],
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        tab.icon,
                                        size: 18,
                                        color: selected
                                            ? scheme.primary
                                            : scheme.onSurface.withValues(
                                                alpha: dark ? 0.78 : 0.68),
                                      ),
                                      const SizedBox(height: 5),
                                      Text(
                                        tab.label,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: selected
                                              ? FontWeight.w700
                                              : FontWeight.w600,
                                          color: selected
                                              ? scheme.primary
                                              : scheme.onSurface.withValues(
                                                  alpha: dark ? 0.80 : 0.70),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                      );
                    },
                  );
                },
              ),
                )
              : BackdropFilter(
                  filter: ImageFilter.blur(
                      sigmaX: dark ? 2 : 0, sigmaY: dark ? 2 : 0),
                  child: Container(
                    height: 76,
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: Colors.black.withValues(alpha: dark ? 0.20 : 0.08),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: dark ? 0.22 : 0.08),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        const itemGap = 4.0;
                        final itemWidth =
                            (constraints.maxWidth - (itemGap * (_visibleTabs - 1))) /
                                _visibleTabs;

                        return PageView.builder(
                          controller: _pageController,
                          padEnds: false,
                          itemCount: pageCount,
                          itemBuilder: (context, pageIndex) {
                            final start = pageIndex;
                            return Row(
                              children: List.generate(_visibleTabs, (slot) {
                                final tabIndex = start + slot;
                                final isLastSlot = slot == _visibleTabs - 1;
                                if (tabIndex >= _BottomTabSection._tabs.length) {
                                  return Expanded(
                                    child: Padding(
                                      padding: EdgeInsets.only(
                                          right: isLastSlot ? 0 : itemGap),
                                      child: const SizedBox(height: 60),
                                    ),
                                  );
                                }

                                final tab = _BottomTabSection._tabs[tabIndex];
                                final selected = tabIndex == widget.selectedIndex;

                                return Expanded(
                                  child: Padding(
                                    padding: EdgeInsets.only(
                                        right: isLastSlot ? 0 : itemGap),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(14),
                                      onTap: () => widget.onTap(tabIndex),
                                      child: AnimatedContainer(
                                        duration: const Duration(milliseconds: 220),
                                        curve: Curves.easeOutCubic,
                                        width: itemWidth,
                                        height: 60,
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                            colors: selected
                                                ? [
                                                    scheme.primary.withValues(
                                                        alpha: dark ? 0.34 : 0.24),
                                                    scheme.primary.withValues(
                                                        alpha: dark ? 0.18 : 0.12),
                                                  ]
                                                : [
                                                    scheme.onSurface.withValues(
                                                        alpha: dark ? 0.10 : 0.05),
                                                    scheme.onSurface.withValues(
                                                        alpha: dark ? 0.06 : 0.02),
                                                  ],
                                          ),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: selected
                                                ? scheme.primary.withValues(
                                                    alpha: dark ? 0.78 : 0.52)
                                                : scheme.onSurface.withValues(
                                                    alpha: dark ? 0.18 : 0.12),
                                          ),
                                          boxShadow: [
                                            if (selected)
                                              BoxShadow(
                                                color: scheme.primary.withValues(
                                                    alpha: dark ? 0.36 : 0.24),
                                                blurRadius: 14,
                                                offset: const Offset(0, 4),
                                              ),
                                          ],
                                        ),
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              tab.icon,
                                              size: 18,
                                              color: selected
                                                  ? scheme.primary
                                                  : scheme.onSurface.withValues(
                                                      alpha: dark ? 0.78 : 0.68),
                                            ),
                                            const SizedBox(height: 5),
                                            Text(
                                              tab.label,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: selected
                                                    ? FontWeight.w700
                                                    : FontWeight.w600,
                                                color: selected
                                                    ? scheme.primary
                                                    : scheme.onSurface.withValues(
                                                        alpha: dark ? 0.80 : 0.70),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

class _HomeTab extends StatefulWidget {
  const _HomeTab({this.onOpenAttendance, this.onOpenConnected});

  final VoidCallback? onOpenAttendance;
  final VoidCallback? onOpenConnected;

  @override
  State<_HomeTab> createState() => _HomeTabState();
}

class _TimetableSlot {
  const _TimetableSlot({
    required this.startMinutes,
    required this.endMinutes,
    required this.title,
  });

  final int startMinutes;
  final int endMinutes;
  final String title;
}

const Map<String, String> _timetableSubjectDetails = {
  "CT": "Prof. Nirosha Uppul • Room 715",
  "DBMS": "Dr. Vaishali M. Shinde • Room 715",
  "OS": "Dr. Aamna H. Punse • Room 715",
  "MDM": "Dr. Archana Chaudhari • Room 715",
  "OE": "Prof. Swarmala Mahendran • Room 715",
  "BMD": "Dr. Sanjay Deshmukh • Room 715",
  "DT": "Dr. Manoj Kumar Yadav / Dr. Archana Chaudhari • Room 715",
  "NU": "Room 715",
  "MKY": "Room 715",
  "SD": "Room 715",
  "AC": "Room 715",
  "VMS": "Room 715",
  "Mini Project": "Mini Project",
};

const String _timetableLabDetails =
    "Practical Labs • L1: 601 • L2: 602(A) • L3: 602(B)";

const Map<int, List<_TimetableSlot>> _weeklyTimetable = {
  DateTime.monday: [
    _TimetableSlot(startMinutes: 570, endMinutes: 630, title: "CT"),
    _TimetableSlot(startMinutes: 630, endMinutes: 690, title: "DT / BMD / DBMS"),
    _TimetableSlot(startMinutes: 690, endMinutes: 750, title: "NU"),
    _TimetableSlot(startMinutes: 780, endMinutes: 840, title: "MDM"),
    _TimetableSlot(startMinutes: 840, endMinutes: 900, title: "BMD"),
    _TimetableSlot(startMinutes: 900, endMinutes: 960, title: "SD / AC / MDM"),
    _TimetableSlot(startMinutes: 960, endMinutes: 1020, title: "L1 / L2 / L3"),
  ],
  DateTime.tuesday: [
    _TimetableSlot(startMinutes: 570, endMinutes: 630, title: "OS"),
    _TimetableSlot(startMinutes: 630, endMinutes: 690, title: "MKY / SD / VMS"),
    _TimetableSlot(startMinutes: 690, endMinutes: 750, title: "OS / DT / BMD"),
    _TimetableSlot(startMinutes: 780, endMinutes: 840, title: "AC"),
    _TimetableSlot(startMinutes: 840, endMinutes: 900, title: "SD"),
    _TimetableSlot(startMinutes: 900, endMinutes: 960, title: "Mini Project"),
  ],
  DateTime.wednesday: [
    _TimetableSlot(startMinutes: 570, endMinutes: 630, title: "DT"),
    _TimetableSlot(startMinutes: 630, endMinutes: 690, title: "DBMS / OS / MDM"),
    _TimetableSlot(startMinutes: 690, endMinutes: 750, title: "L1 / L2 / L3"),
    _TimetableSlot(startMinutes: 780, endMinutes: 840, title: "OS"),
    _TimetableSlot(startMinutes: 840, endMinutes: 900, title: "VMS"),
    _TimetableSlot(startMinutes: 900, endMinutes: 960, title: "BMD"),
  ],
  DateTime.thursday: [
    _TimetableSlot(startMinutes: 570, endMinutes: 630, title: "OE"),
    _TimetableSlot(
        startMinutes: 630, endMinutes: 690, title: "Self Study / DBMS / DT"),
    _TimetableSlot(startMinutes: 690, endMinutes: 750, title: "L1 / L2 / L3"),
    _TimetableSlot(startMinutes: 780, endMinutes: 840, title: "MDM"),
    _TimetableSlot(startMinutes: 840, endMinutes: 900, title: "AC"),
    _TimetableSlot(startMinutes: 900, endMinutes: 960, title: "SD"),
  ],
  DateTime.friday: [
    _TimetableSlot(startMinutes: 570, endMinutes: 630, title: "Room 715"),
    _TimetableSlot(startMinutes: 630, endMinutes: 690, title: "DT"),
    _TimetableSlot(startMinutes: 690, endMinutes: 750, title: "CT"),
    _TimetableSlot(startMinutes: 780, endMinutes: 840, title: "OS"),
    _TimetableSlot(startMinutes: 840, endMinutes: 900, title: "DBMS"),
    _TimetableSlot(startMinutes: 900, endMinutes: 960, title: "MDM / Self Study"),
    _TimetableSlot(startMinutes: 960, endMinutes: 1020, title: "L1 / L2 / L3"),
  ],
};

String _timetableDetailsForTitle(String title) {
  final trimmed = title.trim();
  if (trimmed.isEmpty || trimmed == "—") {
    return "";
  }
  if (trimmed.contains("L1") && trimmed.contains("L2") && trimmed.contains("L3")) {
    return _timetableLabDetails;
  }
  final parts = trimmed.split("/").map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  if (parts.isEmpty) {
    return trimmed;
  }
  final details = parts.map((subject) => _timetableSubjectDetails[subject] ?? subject).toList();
  return details.join(" • ");
}

List<_CalendarEntry> _timetableEntriesForRange(DateTime start, DateTime end) {
  final entries = <_CalendarEntry>[];
  var cursor = DateTime(start.year, start.month, start.day);
  final last = DateTime(end.year, end.month, end.day);
  while (!cursor.isAfter(last)) {
    final slots = _weeklyTimetable[cursor.weekday] ?? const <_TimetableSlot>[];
    final dayKey =
        "${cursor.year}-${cursor.month.toString().padLeft(2, "0")}-${cursor.day.toString().padLeft(2, "0")}";
    for (final slot in slots) {
      if (slot.title.trim().isEmpty || slot.title.trim() == "—") {
        continue;
      }
      final details = _timetableDetailsForTitle(slot.title);
      entries.add(
        _CalendarEntry(
          id: "timetable-$dayKey-${slot.startMinutes}-${slot.title}",
          dayKey: dayKey,
          title: slot.title,
          details: details,
          type: "TIMETABLE",
          startMinutes: slot.startMinutes,
          endMinutes: slot.endMinutes,
        ),
      );
    }
    cursor = cursor.add(const Duration(days: 1));
  }
  return entries;
}

class _HomeTabState extends State<_HomeTab> {
  final ApiService _api = ApiService();
  bool _loading = false;
  bool _offline = false;
  List<dynamic> _active = [];
  List<dynamic> _history = [];
  List<dynamic> _scheduled = [];
  List<dynamic> _rooms = [];
  List<Map<String, dynamic>> _castAlerts = [];
  List<dynamic> _nearbyStudents = [];
  List<dynamic> _docEdAppointments = [];
  List<dynamic> _complaints = [];
  Map<int, _StudentAttendanceSummary> _studentSummary = {};
  Map<int, String> _studentNames = {};
  String _departmentName = "-";
  int _studentCount = 0;
  Timer? _demoSyncTimer;
  int? _demoActiveLectureId;
  Timer? _activeSyncTimer;
  Timer? _roomSyncTimer;
  Timer? _alertSyncTimer;
  Timer? _alertTickTimer;
  DateTime _alertNow = DateTime.now();


  Future<void> _handleLectureStarted(Map<String, dynamic> started) async {
    if (kUseDemoDataEverywhere) {
      final title = (started["title"] ?? "Lecture").toString();
      final selectedStudents =
          (started["selected_students"] as List<dynamic>?)
                  ?.whereType<Map<String, dynamic>>()
                  .toList() ??
              [];
      final classroomId =
          (started["classroom_id"] as num?)?.toInt() ??
              int.tryParse(started["room_no"]?.toString() ?? "") ??
              0;
      final nowUtc = DateTime.now().toUtc().toIso8601String();
      final prefs = await SharedPreferences.getInstance();

      setState(() {
        final nextScheduled = List<dynamic>.from(_scheduled);
        final removeAt = nextScheduled.indexWhere((row) {
          if (row is! Map<String, dynamic>) {
            return false;
          }
          return (row["title"] ?? "").toString().trim().toLowerCase() ==
              title.trim().toLowerCase();
        });
        if (removeAt >= 0) {
          nextScheduled.removeAt(removeAt);
        }

        final nextActive = List<dynamic>.from(_active);
        nextActive.insert(0, {
          "id": DateTime.now().millisecondsSinceEpoch % 100000,
          "title": title,
          "classroom_id": classroomId,
          "status": "ACTIVE",
          "start_time": nowUtc,
        });
        _active = nextActive;
        _scheduled = nextScheduled;
        if (selectedStudents.isNotEmpty) {
          var idx = 0;
          _nearbyStudents = selectedStudents.map((row) {
            final id = (row["id"] as num?)?.toInt() ?? 0;
            final inside = idx % 2 == 0;
            idx += 1;
            return {
              "student_id": id,
              "student_name": (row["name"] ?? "Student #$id").toString(),
              "lecture_id": nextActive.first["id"],
              "inside_geofence": inside,
            };
          }).toList();
        }
      });
      final activePayload = {
        "id": _active.first["id"],
        "title": title,
        "classroom_id": classroomId,
        "status": "ACTIVE",
        "start_time": nowUtc,
      };
      await prefs.setString("demo_active_lecture", jsonEncode(activePayload));
      return;
    }
    await _load();
  }

  Future<void> _handleLectureEnded(Map<String, dynamic> ended) async {
    if (kUseDemoDataEverywhere) {
      final endedId = (ended["id"] as num?)?.toInt();
      final nowUtc = DateTime.now().toUtc().toIso8601String();
      final endedRow = <String, dynamic>{
        ...ended,
        "status": "ENDED",
        "end_time": (ended["end_time"] ?? nowUtc).toString(),
      };
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        final nextActive = List<dynamic>.from(_active);
        if (endedId != null) {
          nextActive.removeWhere((row) {
            if (row is! Map<String, dynamic>) {
              return false;
            }
            final id = (row["id"] as num?)?.toInt();
            return id == endedId;
          });
        } else if (nextActive.isNotEmpty) {
          nextActive.removeAt(0);
        }
        _active = nextActive;
        _history = [endedRow, ..._history];
      });
      await prefs.remove("demo_active_lecture");
      return;
    }
    await _load();
  }

  static const List<Map<String, dynamic>> _demoActiveLectures = [];
  static const List<Map<String, dynamic>> _demoProfessorHistory = [
    {
      "id": 896,
      "classroom_id": 12,
      "status": "ENDED",
      "end_time": "2026-02-22T09:55:00Z"
    },
    {
      "id": 894,
      "classroom_id": 12,
      "status": "ENDED",
      "end_time": "2026-02-21T10:02:00Z"
    },
    {
      "id": 889,
      "classroom_id": 12,
      "status": "ENDED",
      "end_time": "2026-02-20T09:49:00Z"
    },
  ];
  static const List<Map<String, dynamic>> _demoStudentHistory = [
    {"lecture_id": 401, "presence_duration": 3150, "status": "PRESENT"},
    {"lecture_id": 402, "presence_duration": 2920, "status": "PRESENT"},
    {"lecture_id": 403, "presence_duration": 0, "status": "ABSENT"},
  ];
  static const List<Map<String, dynamic>> _demoScheduled = [
    {"id": 301, "title": "AI Fundamentals", "scheduled_at": "2026-02-24 10:00"},
    {"id": 302, "title": "Data Structures", "scheduled_at": "2026-02-24 12:00"},
  ];
  static const List<Map<String, dynamic>> _demoNearby = [
    {"student_id": 101, "student_name": "Aarav Patil", "lecture_id": 901},
    {"student_id": 102, "student_name": "Diya Shinde", "lecture_id": 901},
    {"student_id": 103, "student_name": "Rohan Kale", "lecture_id": 901},
  ];
  static const List<Map<String, dynamic>> _demoDocEdAppointments = [
    {
      "id": 1,
      "document_type": "Hall Ticket",
      "student_name": "Aarav Patil",
      "appointment_at": "2026-02-24T09:30:00Z",
      "status": "PENDING",
    },
    {
      "id": 2,
      "document_type": "ID Card",
      "student_name": "Diya Shinde",
      "appointment_at": "2026-02-24T11:15:00Z",
      "status": "COLLECTED",
    },
  ];
  static const List<Map<String, dynamic>> _demoComplaints = [
    {
      "id": 1,
      "subject": "ID card issue",
      "description": "Name mismatch in ID card",
      "status": "OPEN",
    },
    {
      "id": 2,
      "subject": "Portal access",
      "description": "Unable to access attendance report",
      "status": "IN_PROGRESS",
    },
    {
      "id": 3,
      "subject": "Bonafide delay",
      "description": "Document is not generated yet",
      "status": "RESOLVED",
    },
  ];

  @override
  void initState() {
    super.initState();
    _demoSyncTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (!mounted || !kUseDemoDataEverywhere) {
        return;
      }
      final role = context.read<AuthProvider>().role ?? "STUDENT";
      if (role != "STUDENT") {
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString("demo_active_lecture");
      if (raw == null || raw.isEmpty) {
        if (_demoActiveLectureId != null) {
          setState(() {
            _active = [];
            _demoActiveLectureId = null;
          });
        }
        return;
      }
      try {
        final payload = jsonDecode(raw) as Map<String, dynamic>;
        final id = (payload["id"] as num?)?.toInt();
        if (id != null && id != _demoActiveLectureId && mounted) {
          setState(() {
            _active = [payload];
            _demoActiveLectureId = id;
          });
        }
      } catch (_) {
        // Ignore malformed cache.
      }
    });
    _activeSyncTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      if (!mounted || kUseDemoDataEverywhere) {
        return;
      }
      final role = context.read<AuthProvider>().role ?? "STUDENT";
      if (role != "STUDENT") {
        return;
      }
      await _syncActiveLecturesFromApi();
    });
    _roomSyncTimer = Timer.periodic(const Duration(seconds: 4), (_) async {
      if (!mounted || kUseDemoDataEverywhere) {
        return;
      }
      final role = context.read<AuthProvider>().role ?? "STUDENT";
      if (role != "STUDENT") {
        return;
      }
      await _syncRoomsFromApi();
    });
    _alertSyncTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      if (!mounted || kUseDemoDataEverywhere) {
        return;
      }
      await _syncCastAlerts();
    });
    _alertTickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_castAlerts.isEmpty) return;
      setState(() => _alertNow = DateTime.now());
    });
    _load();
  }

  @override
  void dispose() {
    _demoSyncTimer?.cancel();
    _activeSyncTimer?.cancel();
    _roomSyncTimer?.cancel();
    _alertSyncTimer?.cancel();
    _alertTickTimer?.cancel();
    super.dispose();
  }

  Future<void> _syncActiveLecturesFromApi() async {
    if (!mounted) return;
    try {
      final res = await _api.listActiveLectures();
      if (!mounted || res.statusCode < 200 || res.statusCode >= 300) {
        return;
      }
      final rows = jsonDecode(res.body) as List<dynamic>;
      if (mounted) {
        setState(() => _active = rows);
      }
    } catch (_) {
      // Ignore transient failures.
    }
  }

  Future<void> _syncRoomsFromApi() async {
    if (!mounted) return;
    try {
      final res = await _api.listRooms();
      if (!mounted || res.statusCode < 200 || res.statusCode >= 300) {
        return;
      }
      final rows = jsonDecode(res.body) as List<dynamic>;
      await _api.saveCache("home_rooms", rows);
      if (mounted) {
        setState(() => _rooms = rows);
      }
    } catch (_) {
      // Ignore transient failures.
    }
  }

  List<Map<String, dynamic>> _parseMapList(dynamic raw) {
    if (raw is! List) {
      return const [];
    }
    return raw
        .whereType<Map>()
        .map((row) => row.map((key, value) => MapEntry(key.toString(), value)))
        .toList();
  }

  Future<void> _syncCastAlerts() async {
    if (!mounted) return;
    try {
      final res = await _api.listCastAlerts();
      if (!mounted || res.statusCode < 200 || res.statusCode >= 300) {
        return;
      }
      final rows = _parseMapList(jsonDecode(res.body));
      await _api.saveCache("home_cast_alerts", rows);
      if (mounted) {
        setState(() {
          _castAlerts = rows;
          _alertNow = DateTime.now();
        });
      }
    } catch (_) {
      // Ignore transient failures.
    }
  }

  String _normalizeRoomCode(String raw, {required String title}) {
    final input = raw.trim();
    String roomCode;
    if (input.isNotEmpty) {
      roomCode = input.toLowerCase().replaceAll(RegExp(r"[^a-z0-9_-]+"), "-");
    } else {
      roomCode =
          "connected-${title.toLowerCase().replaceAll(RegExp(r"[^a-z0-9]+"), "-")}";
    }
    roomCode = roomCode
        .replaceAll(RegExp(r"-+"), "-")
        .replaceAll(RegExp(r"^-|-$"), "");
    if (roomCode.isEmpty) {
      return "connected-room-${DateTime.now().millisecondsSinceEpoch}";
    }
    return roomCode;
  }

  String _roomCodeFromRaw(String raw, {required String title}) {
    final value = raw.trim();
    if (value.startsWith("http://") || value.startsWith("https://")) {
      final uri = Uri.tryParse(value);
      final segment =
          (uri?.pathSegments.isNotEmpty ?? false) ? uri!.pathSegments.last : "";
      return _normalizeRoomCode(segment, title: title);
    }
    return _normalizeRoomCode(value, title: title);
  }

  Future<void> _openRoomFromHome(Map<String, dynamic> room) async {
    if (!mounted) {
      return;
    }
    final title = (room["title"] ?? "Meeting").toString();
    final roomCode =
        _roomCodeFromRaw((room["meeting_url"] ?? "").toString(), title: title);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _InAppMeetingScreen(
          title: title,
          roomCode: roomCode,
          displayName: context.read<AuthProvider>().name ?? "Participant",
          role: context.read<AuthProvider>().role ?? "",
          isHost: false,
        ),
      ),
    );
  }

  Future<void> _openCasts() async {
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push(
      AppTransitions.fadeSlide(const HelloCastsScreen()),
    );
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final role = context.read<AuthProvider>().role ?? "STUDENT";
    if (kUseDemoDataEverywhere) {
      if (!mounted) {
        return;
      }
      Map<String, dynamic>? demoActive;
      if (role == "STUDENT") {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString("demo_active_lecture");
        if (raw != null && raw.isNotEmpty) {
          try {
            demoActive = jsonDecode(raw) as Map<String, dynamic>;
            _demoActiveLectureId = (demoActive["id"] as num?)?.toInt();
          } catch (_) {
            demoActive = null;
          }
        }
      }
      setState(() {
        _loading = false;
        _offline = false;
        _active = demoActive == null ? _demoActiveLectures : [demoActive];
        _scheduled = _demoScheduled;
        _rooms = const [];
        _castAlerts = [
          {
            "id": 9001,
            "title": "Project Review",
            "schedule_at":
                DateTime.now().add(const Duration(minutes: 18)).toIso8601String(),
            "active": true,
          },
          {
            "id": 9002,
            "title": "Lab Reminder",
            "schedule_at":
                DateTime.now().add(const Duration(hours: 2)).toIso8601String(),
            "active": true,
          },
        ];
        _history =
            role == "PROFESSOR" ? _demoProfessorHistory : _demoStudentHistory;
        _nearbyStudents = _demoNearby;
        _docEdAppointments = _demoDocEdAppointments;
        _complaints = _demoComplaints;
        _studentSummary = const {
          101: _StudentAttendanceSummary(
              totalLectures: 24, presentCount: 21, attendancePercentage: 87.5),
          102: _StudentAttendanceSummary(
              totalLectures: 24, presentCount: 19, attendancePercentage: 79.2),
          103: _StudentAttendanceSummary(
              totalLectures: 24, presentCount: 22, attendancePercentage: 91.7),
        };
        _studentNames = const {
          101: "Aarav Patil",
          102: "Diya Shinde",
          103: "Rohan Kale",
        };
        _departmentName = "AI & Data Science";
        _studentCount = 72;
      });
      return;
    }
    final activeRes = await _api.listActiveLectures();
    final histRes = role == "PROFESSOR"
        ? await _api.lectureHistory()
        : await _api.attendanceHistory();
    final schedRes = await _api.listScheduledLectures();
    final roomRes = await _api.listRooms();
    final alertsRes = await _api.listCastAlerts();
    final depRes = await _api.myDepartment();
    final countRes = await _api.studentCount();
    final summaryRes =
        role == "PROFESSOR" ? await _api.lectureStudentSummary() : null;
    final nearbyRes = role == "PROFESSOR" ? await _api.nearbyStudents() : null;
    final studentsRes = role == "PROFESSOR" ? await _api.studentsList() : null;
    final docEdRes = await _api.listShareItAppointments();
    final complaintsRes = await _api.myComplaints();
    final isOffline = !(await _api.isBackendOnlineCached());

    List<dynamic> nextActive = _active;
    List<dynamic> nextHistory = _history;
    List<dynamic> nextScheduled = _scheduled;
    List<dynamic> nextRooms = _rooms;
    List<Map<String, dynamic>> nextCastAlerts = _castAlerts;
    List<dynamic> nextNearby = _nearbyStudents;
    List<dynamic> nextDocEdAppointments = _docEdAppointments;
    List<dynamic> nextComplaints = _complaints;
    Map<int, _StudentAttendanceSummary> nextSummary = _studentSummary;
    Map<int, String> nextNames = _studentNames;
    String nextDepartmentName = _departmentName;
    int nextStudentCount = _studentCount;

    if (isOffline) {
      nextActive =
          (await _api.readCache("home_active") as List<dynamic>?) ?? nextActive;
      nextHistory = (await _api.readCache("home_history") as List<dynamic>?) ??
          nextHistory;
      nextScheduled =
          (await _api.readCache("home_scheduled") as List<dynamic>?) ??
              nextScheduled;
      nextRooms =
          (await _api.readCache("home_rooms") as List<dynamic>?) ?? nextRooms;
      nextCastAlerts = _parseMapList(await _api.readCache("home_cast_alerts"));
      nextNearby =
          (await _api.readCache("home_nearby") as List<dynamic>?) ?? nextNearby;
      final dep =
          await _api.readCache("home_department") as Map<String, dynamic>?;
      final count =
          await _api.readCache("home_student_count") as Map<String, dynamic>?;
      final rawSummary =
          await _api.readCache("home_student_summary") as List<dynamic>?;
      final rawNames =
          await _api.readCache("home_student_names") as List<dynamic>?;
      nextDocEdAppointments =
          (await _api.readCache("home_doced_appointments") as List<dynamic>?) ??
              nextDocEdAppointments;
      nextComplaints =
          (await _api.readCache("home_complaints") as List<dynamic>?) ??
              nextComplaints;
      nextDepartmentName = dep?["name"]?.toString() ?? nextDepartmentName;
      nextStudentCount = (count?["count"] as num?)?.toInt() ?? nextStudentCount;
      if (rawSummary != null) {
        nextSummary = _parseStudentSummary(rawSummary);
      }
      if (rawNames != null) {
        nextNames = _parseStudentNames(rawNames);
      }
    } else {
      if (activeRes.statusCode >= 200 && activeRes.statusCode < 300) {
        nextActive = jsonDecode(activeRes.body) as List<dynamic>;
        await _api.saveCache("home_active", nextActive);
      }
      if (histRes.statusCode >= 200 && histRes.statusCode < 300) {
        nextHistory = jsonDecode(histRes.body) as List<dynamic>;
        await _api.saveCache("home_history", nextHistory);
      }
      if (schedRes.statusCode >= 200 && schedRes.statusCode < 300) {
        nextScheduled = jsonDecode(schedRes.body) as List<dynamic>;
        await _api.saveCache("home_scheduled", nextScheduled);
      }
      if (roomRes.statusCode >= 200 && roomRes.statusCode < 300) {
        nextRooms = jsonDecode(roomRes.body) as List<dynamic>;
        await _api.saveCache("home_rooms", nextRooms);
      }
      if (alertsRes.statusCode >= 200 && alertsRes.statusCode < 300) {
        nextCastAlerts = _parseMapList(jsonDecode(alertsRes.body));
        await _api.saveCache("home_cast_alerts", nextCastAlerts);
      }
      if (nearbyRes != null &&
          nearbyRes.statusCode >= 200 &&
          nearbyRes.statusCode < 300) {
        final decoded = jsonDecode(nearbyRes.body);
        if (decoded is Map<String, dynamic>) {
          nextNearby = (decoded["students"] as List<dynamic>? ?? const []);
        } else if (decoded is List<dynamic>) {
          nextNearby = decoded;
        }
        await _api.saveCache("home_nearby", nextNearby);
      }
      if (summaryRes != null &&
          summaryRes.statusCode >= 200 &&
          summaryRes.statusCode < 300) {
        final rows = jsonDecode(summaryRes.body) as List<dynamic>;
        nextSummary = _parseStudentSummary(rows);
        await _api.saveCache("home_student_summary", rows);
      }
      if (studentsRes != null &&
          studentsRes.statusCode >= 200 &&
          studentsRes.statusCode < 300) {
        final rows = jsonDecode(studentsRes.body) as List<dynamic>;
        nextNames = _parseStudentNames(rows);
        await _api.saveCache("home_student_names", rows);
      }
      if (docEdRes.statusCode >= 200 && docEdRes.statusCode < 300) {
        nextDocEdAppointments = jsonDecode(docEdRes.body) as List<dynamic>;
        await _api.saveCache("home_doced_appointments", nextDocEdAppointments);
      }
      if (complaintsRes.statusCode >= 200 && complaintsRes.statusCode < 300) {
        nextComplaints = jsonDecode(complaintsRes.body) as List<dynamic>;
        await _api.saveCache("home_complaints", nextComplaints);
      }
      if (depRes.statusCode >= 200 && depRes.statusCode < 300) {
        final dep = (jsonDecode(depRes.body)
            as Map<String, dynamic>)["department"] as Map<String, dynamic>?;
        nextDepartmentName = dep?["name"]?.toString() ?? "-";
        await _api.saveCache("home_department", {"name": nextDepartmentName});
      }
      if (countRes.statusCode >= 200 && countRes.statusCode < 300) {
        nextStudentCount = (jsonDecode(countRes.body)
                as Map<String, dynamic>)["count"] as int? ??
            0;
        await _api.saveCache("home_student_count", {"count": nextStudentCount});
      }
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _loading = false;
      _offline = isOffline;
      _active = nextActive;
      _history = nextHistory;
      _scheduled = nextScheduled;
      _rooms = nextRooms;
      _castAlerts = nextCastAlerts;
      _nearbyStudents = nextNearby;
      _docEdAppointments = nextDocEdAppointments;
      _complaints = nextComplaints;
      _studentSummary = nextSummary;
      _studentNames = nextNames;
      _departmentName = nextDepartmentName;
      _studentCount = nextStudentCount;
      _alertNow = DateTime.now();
    });
    await _syncCalendarFromSources(
      scheduled: nextScheduled,
      docEdAppointments: nextDocEdAppointments,
      complaints: nextComplaints,
    );
  }

  Future<void> _syncCalendarFromSources({
    required List<dynamic> scheduled,
    required List<dynamic> docEdAppointments,
    required List<dynamic> complaints,
  }) async {
    final items = <_CalendarEntry>[];
    for (final row in scheduled) {
      if (row is! Map<String, dynamic>) {
        continue;
      }
      final when = TimeFormat.parseToIst(row["scheduled_at"]?.toString()) ??
          _CalendarSync.parseFlexibleDateTime(
              row["scheduled_at"]?.toString() ?? "");
      if (when == null) {
        continue;
      }
      final start = (when.hour * 60) + when.minute;
      final title = (row["title"] ?? "Lecture").toString();
      items.add(
        _CalendarEntry(
          id: "home-scheduled-$title-${row["scheduled_at"]}",
          dayKey:
              "${when.year}-${when.month.toString().padLeft(2, "0")}-${when.day.toString().padLeft(2, "0")}",
          title: "Lecture: $title",
          details: "Scheduled via ConnectEd",
          type: "TIMETABLE",
          startMinutes: start,
          endMinutes: (start + 60).clamp(0, 1439),
        ),
      );
    }
    for (final row in docEdAppointments) {
      if (row is! Map<String, dynamic>) {
        continue;
      }
      final when = TimeFormat.parseToIst(row["appointment_at"]?.toString()) ??
          _CalendarSync.parseFlexibleDateTime(
              row["appointment_at"]?.toString() ?? "");
      if (when == null) {
        continue;
      }
      final start = (when.hour * 60) + when.minute;
      final id = (row["id"] ?? "${row["document_type"]}-${row["student_name"]}")
          .toString();
      items.add(
        _CalendarEntry(
          id: "home-doced-$id",
          dayKey:
              "${when.year}-${when.month.toString().padLeft(2, "0")}-${when.day.toString().padLeft(2, "0")}",
          title: "DocEd: ${(row["document_type"] ?? "Document").toString()}",
          details:
              "${(row["student_name"] ?? "Student").toString()} • ${(row["status"] ?? "PENDING").toString()}",
          type: "EVENT",
          startMinutes: start,
          endMinutes: (start + 60).clamp(0, 1439),
        ),
      );
    }
    final now = TimeFormat.nowIst();
    final nowStart = (now.hour * 60) + now.minute;
    for (final row in complaints) {
      if (row is! Map<String, dynamic>) {
        continue;
      }
      final id = (row["id"] ?? row["subject"] ?? row["title"] ?? "complaint")
          .toString();
      final subject = (row["subject"] ?? row["title"] ?? "Complaint")
          .toString();
      final status = (row["status"] ?? "OPEN").toString();
      items.add(
        _CalendarEntry(
          id: "home-complaint-$id",
          dayKey:
              "${now.year}-${now.month.toString().padLeft(2, "0")}-${now.day.toString().padLeft(2, "0")}",
          title: "Complaint: $subject",
          details: "Status: $status",
          type: "EVENT",
          startMinutes: nowStart,
          endMinutes: (nowStart + 30).clamp(0, 1439),
        ),
      );
    }
    final rangeStart =
        DateTime(now.year, now.month, now.day).subtract(const Duration(days: 14));
    final rangeEnd =
        DateTime(now.year, now.month, now.day).add(const Duration(days: 112));
    items.addAll(_timetableEntriesForRange(rangeStart, rangeEnd));
    await _CalendarSync.upsertBatch(items);
  }

  Map<int, _StudentAttendanceSummary> _parseStudentSummary(List<dynamic> rows) {
    final map = <int, _StudentAttendanceSummary>{};
    for (final row in rows) {
      if (row is! Map<String, dynamic>) {
        continue;
      }
      final id = row["student_id"];
      if (id is! int) {
        continue;
      }
      map[id] = _StudentAttendanceSummary(
        totalLectures: (row["total_lectures"] as num?)?.toInt() ?? 0,
        presentCount: (row["present_count"] as num?)?.toInt() ?? 0,
        attendancePercentage:
            (row["attendance_percentage"] as num?)?.toDouble() ?? 0,
      );
    }
    return map;
  }

  Map<int, String> _parseStudentNames(List<dynamic> rows) {
    final map = <int, String>{};
    for (final row in rows) {
      if (row is! Map<String, dynamic>) {
        continue;
      }
      final id = row["id"];
      if (id is! int) {
        continue;
      }
      map[id] = (row["name"] ?? "Student #$id").toString();
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final role = auth.role ?? "STUDENT";
    return ListView(
      padding:
          const EdgeInsets.fromLTRB(14, 8, 14, 18 + kDockScrollBottomInset),
      children: [
        if (_offline && role != "PROFESSOR")
          const Card(
            child: ListTile(
              leading: Icon(Icons.wifi_off_rounded),
              title: Text("Offline mode"),
              subtitle: Text("Showing latest available data."),
            ),
          ),
        if (_offline && role != "PROFESSOR") const SizedBox(height: 10),
        _Header(
          name: auth.name ?? "User",
        ),
        const SizedBox(height: 14),
        if (role == "PROFESSOR")
          _ProfessorDashboard(
            loading: _loading,
            active: _active,
            scheduled: _scheduled,
            history: _history,
            nearbyStudents: _nearbyStudents,
            studentSummary: _studentSummary,
            studentNames: _studentNames,
            docEdAppointments: _docEdAppointments,
            complaints: _complaints,
            departmentName: _departmentName,
            studentCount: _studentCount,
            onOpenAttendance: widget.onOpenAttendance,
            onLectureStarted: _handleLectureStarted,
            onLectureEnded: _handleLectureEnded,
          )
        else
          _StudentDashboard(
            loading: _loading,
            active: _active,
            scheduled: _scheduled,
            rooms: _rooms,
            history: _history,
            castAlerts: _castAlerts,
            now: _alertNow,
            onJoinRoom: _openRoomFromHome,
            onOpenConnected: widget.onOpenConnected,
            onOpenCasts: _openCasts,
          ),
      ],
    );
  }
}

class _StudentDashboard extends StatelessWidget {
  const _StudentDashboard({
    required this.loading,
    required this.active,
    required this.scheduled,
    required this.rooms,
    required this.history,
    required this.castAlerts,
    required this.now,
    this.onJoinRoom,
    this.onOpenConnected,
    this.onOpenCasts,
  });

  final bool loading;
  final List<dynamic> active;
  final List<dynamic> scheduled;
  final List<dynamic> rooms;
  final List<dynamic> history;
  final List<Map<String, dynamic>> castAlerts;
  final DateTime now;
  final Future<void> Function(Map<String, dynamic> room)? onJoinRoom;
  final VoidCallback? onOpenConnected;
  final VoidCallback? onOpenCasts;
  static const List<Map<String, String>> _upcomingEvents = [
    {
      "title": "Blood Donation Drive",
      "date": "11 Sep 2025",
      "time": "09:00 AM - 04:00 PM",
      "venue": "Student Lounge",
      "poster": "https://images.unsplash.com/photo-1615461066841-6116e61058f4?w=1200",
    },
    {
      "title": "Hackathon 2026",
      "date": "05 Aug 2026",
      "time": "10:00 AM - 08:00 PM",
      "venue": "Main Auditorium",
      "poster": "https://images.unsplash.com/photo-1518770660439-4636190af475?w=1200",
    },
    {
      "title": "Campus Placement Talk",
      "date": "19 Mar 2026",
      "time": "02:00 PM - 05:00 PM",
      "venue": "Seminar Hall",
      "poster": "https://images.unsplash.com/photo-1521737711867-e3b97375f902?w=1200",
    },
  ];

  DateTime? _parseAlertAt(Map<String, dynamic> alert) {
    final raw = alert["schedule_at"]?.toString();
    if (raw == null || raw.isEmpty) return null;
    return TimeFormat.parseToIst(raw) ?? DateTime.tryParse(raw);
  }

  List<Map<String, dynamic>> _sortedAlerts() {
    final filtered = castAlerts
        .where((alert) => alert["active"] != false)
        .toList(growable: false);
    filtered.sort((a, b) {
      final at = _parseAlertAt(a);
      final bt = _parseAlertAt(b);
      if (at == null && bt == null) return 0;
      if (at == null) return 1;
      if (bt == null) return -1;
      return at.compareTo(bt);
    });
    return filtered;
  }

  String _formatCountdown(DateTime at) {
    final diff = at.difference(now);
    if (diff.inSeconds.abs() <= 60) return "Now";
    if (diff.isNegative) return "Overdue";
    final totalMinutes = diff.inMinutes;
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes.remainder(60);
    if (hours > 0 && minutes > 0) return "In ${hours}h ${minutes}m";
    if (hours > 0) return "In ${hours}h";
    return "In ${minutes}m";
  }

  String _formatClock(DateTime time) {
    final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final minute = time.minute.toString().padLeft(2, "0");
    final period = time.hour >= 12 ? "PM" : "AM";
    return "$hour:$minute $period";
  }

  @override
  Widget build(BuildContext context) {
    final hasActive = active.isNotEmpty;
    final liveRooms = _liveRooms(rooms);
    final todayMeetings = _todayMeetings(scheduled);
    final upcomingAlerts = _sortedAlerts();
    return Column(
      children: [
        AppCard(
          child: Row(
            children: [
              const Icon(Icons.announcement_rounded),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  "Announcement",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (hasActive) ...[
          AppCard(
            gradient: const LinearGradient(
              colors: [Color(0xFF0A84FF), Color(0xFF5AA9FF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Active Lecture",
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
                const SizedBox(height: 6),
                Text(
                  "Lecture #${active.first["id"]} is running now",
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 14),
                AppButton(
                  label: "Mark Presence",
                  icon: Icons.location_on_rounded,
                  onPressed: () {
                    Navigator.of(context).push(
                      AppTransitions.fadeSlide(const ActiveLectureScreen()),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        AppCard(
          gradient: LinearGradient(
            colors: [
              Theme.of(context).colorScheme.primary.withValues(alpha: 0.85),
              Theme.of(context).colorScheme.secondary.withValues(alpha: 0.75),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.alarm_rounded, color: Colors.white),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      "Alert Studio",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  if (onOpenCasts != null)
                    TextButton(
                      onPressed: onOpenCasts,
                      child: const Text(
                        "Open",
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (upcomingAlerts.isEmpty)
                const Text(
                  "No reminders yet. Schedule one from Casts.",
                  style: TextStyle(color: Colors.white70),
                )
              else
                Column(
                  children: upcomingAlerts.take(3).map((alert) {
                    final title = alert["title"]?.toString() ?? "Reminder";
                    final at = _parseAlertAt(alert);
                    final timeLabel =
                        at == null ? "-" : "${_formatCountdown(at)} â€¢ ${_formatClock(at)}";
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          const Icon(Icons.notifications_active_rounded,
                              size: 16, color: Colors.white),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  timeLabel,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const SectionTitle("Upcoming Events"),
        const SizedBox(height: 10),
        SizedBox(
          height: 228,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _upcomingEvents.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final event = _upcomingEvents[index];
              return SizedBox(
                width: 280,
                child: AppCard(
                  gradient: LinearGradient(
                    colors: [
                      Theme.of(context).colorScheme.primary.withValues(alpha: 0.85),
                      Theme.of(context).colorScheme.secondary.withValues(alpha: 0.75),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: SizedBox(
                          height: 76,
                          width: double.infinity,
                          child: Image.network(
                            event["poster"] ?? "",
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: Colors.black.withValues(alpha: 0.18),
                              alignment: Alignment.center,
                              child: const Icon(Icons.event_rounded, color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        event["title"] ?? "Event",
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _eventMeta(Icons.calendar_today_rounded, event["date"] ?? ""),
                      const SizedBox(height: 4),
                      _eventMeta(Icons.schedule_rounded, event["time"] ?? ""),
                      const SizedBox(height: 4),
                      _eventMeta(Icons.location_on_rounded, event["venue"] ?? ""),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 14),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(child: SectionTitle("Today's Meetings")),
                  if (onOpenConnected != null)
                    TextButton.icon(
                      onPressed: onOpenConnected,
                      icon: const Icon(Icons.open_in_new_rounded, size: 16),
                      label: const Text("ConnectEd"),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (liveRooms.isEmpty && todayMeetings.isEmpty)
                const Text("No meetings scheduled for today")
              else ...[
                if (liveRooms.isNotEmpty) ...[
                  Text(
                    "Live now",
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...liveRooms.take(3).map(
                        (room) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              const Icon(Icons.wifi_tethering_rounded,
                                  size: 16, color: Colors.green),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      room["title"]?.toString() ?? "Meeting",
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700),
                                    ),
                                    Text(
                                      room["subtitle"]?.toString() ?? "Just started",
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withValues(alpha: 0.72),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              TextButton(
                                onPressed: onJoinRoom == null
                                    ? null
                                    : () => onJoinRoom!(
                                        Map<String, dynamic>.from(room)),
                                child: const Text("Join"),
                              ),
                            ],
                          ),
                        ),
                      ),
                  if (todayMeetings.isNotEmpty) const Divider(height: 18),
                ],
                if (todayMeetings.isNotEmpty)
                  ...todayMeetings
                      .take(4)
                      .map((m) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              children: [
                                const Icon(Icons.video_call_rounded, size: 16),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    "${m["title"]} • ${m["time"]}",
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          )),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        _LectureStateSections(
          ongoing: active,
          upcoming: scheduled,
          completed: history,
        ),
        const SizedBox(height: 14),
        const SectionTitle("Recent Lectures"),
        const SizedBox(height: 10),
        if (loading)
          const LoadingSkeleton(height: 110)
        else if (history.isEmpty)
          const EmptyStateWidget(message: "No recent lecture records")
        else
          ...history.take(5).map(
                (r) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: AppCard(
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("Lecture #${r["lecture_id"]}",
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700)),
                              const SizedBox(height: 4),
                              Text(
                                "Duration ${r["presence_duration"]}s",
                                style: TextStyle(
                                  color: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.color
                                      ?.withValues(alpha: 0.72),
                                ),
                              ),
                            ],
                          ),
                        ),
                        StatusBadge.forAttendance(r["status"].toString()),
                      ],
                    ),
                  ),
                ),
              ),
      ],
    );
  }

  List<Map<String, String>> _todayMeetings(List<dynamic> rows) {
    final now = TimeFormat.nowIst();
    final today = DateTime(now.year, now.month, now.day);
    final list = <Map<String, String>>[];
    for (final row in rows) {
      if (row is! Map<String, dynamic>) {
        continue;
      }
      final parsed = TimeFormat.parseToIst(row["scheduled_at"]?.toString());
      if (parsed == null) {
        continue;
      }
      final day = DateTime(parsed.year, parsed.month, parsed.day);
      if (day != today) {
        continue;
      }
      list.add({
        "title": (row["title"] ?? "Meeting").toString(),
        "time": TimeFormat.formatMinutes12h((parsed.hour * 60) + parsed.minute),
      });
    }
    return list;
  }

  List<Map<String, dynamic>> _liveRooms(List<dynamic> rows) {
    final now = TimeFormat.nowIst();
    final cutoff = now.subtract(const Duration(hours: 6));
    final live = <Map<String, dynamic>>[];
    for (final row in rows) {
      if (row is! Map<String, dynamic>) {
        continue;
      }
      final title = (row["title"] ?? "Meeting").toString();
      final created = TimeFormat.parseToIst(row["created_at"]?.toString()) ??
          _CalendarSync.parseFlexibleDateTime(
              row["created_at"]?.toString() ?? "");
      if (created == null || created.isBefore(cutoff)) {
        continue;
      }
      final age = now.difference(created);
      final subtitle = age.inMinutes <= 1
          ? "Started just now"
          : age.inMinutes < 60
              ? "Started ${age.inMinutes} min ago"
              : "Started ${age.inHours} hr ago";
      live.add({
        ...row,
        "title": title,
        "subtitle": subtitle,
      });
    }
    live.sort((a, b) => (b["created_at"] ?? "")
        .toString()
        .compareTo((a["created_at"] ?? "").toString()));
    return live;
  }
}

Widget _eventMeta(IconData icon, String value) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 15, color: Colors.white.withValues(alpha: 0.95)),
      const SizedBox(width: 7),
      Expanded(
        child: Text(
          value,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.95)),
        ),
      ),
    ],
  );
}

class _ProfessorDashboard extends StatefulWidget {
  const _ProfessorDashboard({
    required this.loading,
    required this.active,
    required this.scheduled,
    required this.history,
    required this.nearbyStudents,
    required this.studentSummary,
    required this.studentNames,
    required this.docEdAppointments,
    required this.complaints,
    required this.departmentName,
    required this.studentCount,
    this.onOpenAttendance,
    this.onLectureStarted,
    this.onLectureEnded,
  });

  final bool loading;
  final List<dynamic> active;
  final List<dynamic> scheduled;
  final List<dynamic> history;
  final List<dynamic> nearbyStudents;
  final Map<int, _StudentAttendanceSummary> studentSummary;
  final Map<int, String> studentNames;
  final List<dynamic> docEdAppointments;
  final List<dynamic> complaints;
  final String departmentName;
  final int studentCount;
  final VoidCallback? onOpenAttendance;
  final Future<void> Function(Map<String, dynamic> started)? onLectureStarted;
  final Future<void> Function(Map<String, dynamic> ended)? onLectureEnded;

  @override
  State<_ProfessorDashboard> createState() => _ProfessorDashboardState();
}

class _ProfessorDashboardState extends State<_ProfessorDashboard> {
  final ApiService _api = ApiService();
  final SmartAttendanceService _smartAttendance = SmartAttendanceService();
  bool _endingLecture = false;
  Timer? _clockTimer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        return;
      }
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  List<_TimetableSlot> _todayTimetableSlots() {
    final now = TimeFormat.nowIst();
    return _weeklyTimetable[now.weekday] ?? const <_TimetableSlot>[];
  }

  _TimetableSlot? _currentTimetableSlot() {
    final now = TimeFormat.nowIst();
    final minutes = (now.hour * 60) + now.minute;
    for (final slot in _todayTimetableSlots()) {
      if (minutes >= slot.startMinutes && minutes < slot.endMinutes) {
        return slot;
      }
    }
    return null;
  }

  List<_TimetableSlot> _upcomingTimetableSlots({int limit = 2}) {
    final now = TimeFormat.nowIst();
    final minutes = (now.hour * 60) + now.minute;
    final list = _todayTimetableSlots()
        .where((slot) => slot.startMinutes > minutes)
        .toList()
      ..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
    if (list.length <= limit) {
      return list;
    }
    return list.take(limit).toList();
  }

  String _slotLabel(_TimetableSlot slot) {
    final start = TimeFormat.formatMinutes12h(slot.startMinutes);
    final end = TimeFormat.formatMinutes12h(slot.endMinutes);
    return "${slot.title} ($start - $end)";
  }

  String _activeLectureDurationLabel(dynamic lecture) {
    if (lecture is! Map<String, dynamic>) {
      return "--:--";
    }
    final startRaw = lecture["start_time"]?.toString();
    final start = TimeFormat.parseToIst(startRaw) ??
        DateTime.tryParse(startRaw ?? "");
    if (start == null) {
      return "--:--";
    }
    final diff = _now.difference(start).abs();
    final hours = diff.inHours;
    final minutes = diff.inMinutes.remainder(60).toString().padLeft(2, "0");
    final seconds = diff.inSeconds.remainder(60).toString().padLeft(2, "0");
    return hours > 0 ? "${hours}h ${minutes}m" : "$minutes:$seconds";
  }

  Future<void> _showQuickStartLectureSheet() async {
    final createdSpaces = <Map<String, dynamic>>[];
    try {
      final res = await _api.listClassrooms();
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final decoded = jsonDecode(res.body) as List<dynamic>;
        createdSpaces.addAll(decoded.whereType<Map<String, dynamic>>());
      }
    } catch (_) {
      // Ignore fetch failures here.
    }
    if (createdSpaces.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      final rawSpaces = prefs.getString("professor_created_spaces");
      if (rawSpaces != null && rawSpaces.isNotEmpty) {
        try {
          createdSpaces.addAll(
            (jsonDecode(rawSpaces) as List<dynamic>)
                .whereType<Map<String, dynamic>>(),
          );
        } catch (_) {}
      }
    }
    final selectedClasses = <int>{};
    final selectedStudents = <int>{};
    int? selectedSpaceId;
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(builder: (context, setSheetState) {
          List<Map<String, dynamic>> visibleStudents() {
            if (selectedClasses.isEmpty) {
              return const [];
            }
            final rows = <Map<String, dynamic>>[];
            for (final classId in selectedClasses) {
              final list = _demoClassStudents[classId] ?? const [];
              rows.addAll(list);
            }
            return rows;
          }

          void toggleClass(int id, bool selected) {
            setSheetState(() {
              if (selected) {
                selectedClasses.add(id);
              } else {
                selectedClasses.remove(id);
                final list = _demoClassStudents[id] ?? const [];
                for (final s in list) {
                  selectedStudents.remove(s["id"] as int);
                }
              }
            });
          }

          void toggleStudent(int id, bool selected) {
            setSheetState(() {
              if (selected) {
                selectedStudents.add(id);
              } else {
                selectedStudents.remove(id);
              }
            });
          }

          Future<void> startLecture() async {
            if (createdSpaces.isNotEmpty && selectedSpaceId == null) {
              GlassToast.show(context, "Select a space",
                  icon: Icons.info_outline);
              return;
            }
            if (selectedClasses.isEmpty) {
              GlassToast.show(context, "Select at least one class",
                  icon: Icons.info_outline);
              return;
            }
            if (selectedStudents.isEmpty) {
              GlassToast.show(context, "Select at least one student",
                  icon: Icons.info_outline);
              return;
            }
            String extractDetail(String body, String fallback) {
              try {
                final map = jsonDecode(body) as Map<String, dynamic>;
                return (map["detail"] ?? fallback).toString();
              } catch (_) {
                return fallback;
              }
            }
            final firstClass = _demoProfessorClasses
                .firstWhere((c) => selectedClasses.contains(c["id"] as int));
            final classroomId = selectedSpaceId ?? (firstClass["id"] as int);
            final title = "Lecture - ${firstClass["name"]}";
            final selected = _demoClassStudents.values
                .expand((e) => e)
                .where((s) => selectedStudents.contains(s["id"] as int))
                .toList();

            Map<String, dynamic> payload = {
              "title": title,
              "classroom_id": classroomId,
              "selected_students": selected,
            };
            final res = await _api.startLecture(classroomId);
            if (res.statusCode >= 200 && res.statusCode < 300) {
              try {
                payload = jsonDecode(res.body) as Map<String, dynamic>;
                final lectureId = (payload["id"] as num).toInt();
                final durationMs =
                    ((payload["scheduled_duration_ms"] as num?)?.toInt() ?? 60) *
                        60 *
                        1000;
                try {
                  await _smartAttendance.startProfessorSession(
                    lectureId: lectureId,
                    roomId: classroomId,
                    scheduledDurationMs: durationMs,
                    minAttendancePercent: 75,
                    scheduledStart: payload["scheduled_start"] as int?,
                  );
                } catch (_) {
                  if (!context.mounted) return;
                  GlassToast.show(
                    context,
                    "BLE beacon not started. Enable Bluetooth and allow Advertise permission, then retry.",
                    icon: Icons.error_outline,
                  );
                  return;
                }
              } catch (_) {}
            } else {
              if (!context.mounted) return;
              GlassToast.show(
                context,
                extractDetail(res.body, "Unable to start lecture."),
                  icon: Icons.error_outline);
              return;
            }
            if (widget.onLectureStarted != null) {
              await widget.onLectureStarted!(payload);
            }
            if (context.mounted) {
              Navigator.of(context).pop();
            }
          }

          final students = visibleStudents();
          final allClassesSelected =
              selectedClasses.length == _demoProfessorClasses.length;
          final allStudentsSelected =
              students.isNotEmpty && selectedStudents.length == students.length;
          return SafeArea(
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionTitle("Start Lecture"),
                    const SizedBox(height: 8),
                    const Text("Select space"),
                    const SizedBox(height: 6),
                    if (createdSpaces.isEmpty)
                      const Text("No spaces created yet.")
                    else
                      ...createdSpaces.map((space) {
                        final id = (space["id"] as num?)?.toInt();
                        final name =
                            (space["name"] ?? "Space #$id").toString();
                        final isSelected = id != null && selectedSpaceId == id;
                        return ListTile(
                          dense: true,
                          enabled: id != null,
                          contentPadding: EdgeInsets.zero,
                          onTap: id == null
                              ? null
                              : () => setSheetState(() => selectedSpaceId = id),
                          leading: Icon(
                            isSelected
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                          ),
                          title: Text(name),
                        );
                      }),
                    const SizedBox(height: 12),
                    const Text("Select classes"),
                    const SizedBox(height: 6),
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: allClassesSelected,
                      onChanged: (value) => setSheetState(() {
                        if (value == true) {
                          selectedClasses
                            ..clear()
                            ..addAll(
                              _demoProfessorClasses
                                  .map((c) => c["id"] as int),
                            );
                        } else {
                          selectedClasses.clear();
                        }
                      }),
                      title: const Text("Select all classes"),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _demoProfessorClasses.map((c) {
                        final id = c["id"] as int;
                        return FilterChip(
                          label: Text(c["name"].toString()),
                          selected: selectedClasses.contains(id),
                          onSelected: (value) => toggleClass(id, value),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                    const Text("Select students"),
                    const SizedBox(height: 6),
                    if (students.isEmpty)
                      const Text("Select a class to load students.")
                    else ...[
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: allStudentsSelected,
                        onChanged: (value) => setSheetState(() {
                          if (value == true) {
                            selectedStudents
                              ..clear()
                              ..addAll(students.map((s) => s["id"] as int));
                          } else {
                            selectedStudents.clear();
                          }
                        }),
                        title: const Text("Select all students"),
                      ),
                      ...students.map((s) {
                        final id = s["id"] as int;
                        final name = s["name"].toString();
                        return CheckboxListTile(
                          dense: true,
                          value: selectedStudents.contains(id),
                          onChanged: (value) =>
                              toggleStudent(id, value ?? false),
                          title: Text(name),
                        );
                      }),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: AppButton(
                            label: "Start lecture",
                            icon: Icons.play_circle_fill_rounded,
                            onPressed: startLecture,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        });
      },
    );
  }

  Future<void> _endActiveLecture() async {
    if (_endingLecture || widget.active.isEmpty) {
      return;
    }
    final active = widget.active.first;
    final lectureMap =
        active is Map<String, dynamic> ? active : <String, dynamic>{};
    final lectureId = _activeLectureId(active);
    if (!kUseDemoDataEverywhere && lectureId == null) {
      if (!mounted) {
        return;
      }
      GlassToast.show(context, "Unable to end lecture.", icon: Icons.error_outline);
      return;
    }

    setState(() => _endingLecture = true);
    var ok = false;
    String? errorDetail;
    if (kUseDemoDataEverywhere) {
      ok = true;
    } else {
      final res = await _api.endLecture(lectureId!);
      ok = res.statusCode >= 200 && res.statusCode < 300;
      if (!ok) {
        try {
          final map = jsonDecode(res.body) as Map<String, dynamic>;
          errorDetail = map["detail"]?.toString();
        } catch (_) {
          errorDetail = null;
        }
      }
    }

    if (!mounted) {
      return;
    }

    if (ok) {
      final endedPayload = <String, dynamic>{
        ...lectureMap,
        if (lectureId != null) "id": lectureId,
        "status": "ENDED",
        "end_time": DateTime.now().toUtc().toIso8601String(),
      };
      if (widget.onLectureEnded != null) {
        await widget.onLectureEnded!(endedPayload);
      }
      if (!mounted) {
        return;
      }
      GlassToast.show(context, "Lecture ended.", icon: Icons.check_circle_outline);
    } else {
      GlassToast.show(
        context,
        errorDetail ?? "Unable to end lecture.",
        icon: Icons.error_outline,
      );
    }
    if (mounted) {
      setState(() => _endingLecture = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayHistory = widget.history
        .whereType<Map<String, dynamic>>()
        .where(
            (row) => (row["status"]?.toString() ?? "").toUpperCase() == "ENDED")
        .toList();
    final todayUpcoming = _todayUpcomingLectures(widget.scheduled);
    final todayCompletedOverview = _todayCompletedLectures(displayHistory);
    final activeLectureId =
        _activeLectureId(widget.active.isEmpty ? null : widget.active.first);
    final presentStudents = _studentsPresentForActiveLecture(activeLectureId);
    final currentSlot = _currentTimetableSlot();
    final upcomingSlots = _upcomingTimetableSlots();
    final todayMeetings = _todayMeetings(widget.scheduled);
    final docEdStatus = _docEdStatus(widget.docEdAppointments);
    final complaintStatus = _complaintStatus(widget.complaints);
    return Column(
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionTitle("Today's Overview"),
              const SizedBox(height: 8),
              Text("Department: ${widget.departmentName}"),
              const SizedBox(height: 10),
              _LectureStrip(
                title: "Currently Active Lecture",
                dotColor: Colors.red,
                compact: true,
                children: [
                  if (widget.active.isEmpty) ...[
                    const Text("No active lecture"),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerRight,
                      child: AppButton(
                        label: "Start Lecture",
                        icon: Icons.play_circle_fill_rounded,
                        onPressed: _showQuickStartLectureSheet,
                      ),
                    ),
                  ] else ...[
                    Text(
                      widget.active.isNotEmpty
                          ? (widget.active.first is Map<String, dynamic>
                              ? _lectureSubjectRoom(
                                  widget.active.first as Map<String, dynamic>)
                              : _lectureLabel(widget.active.first))
                          : _slotLabel(currentSlot!),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Duration: ${_activeLectureDurationLabel(widget.active.first)}"
                      "${currentSlot == null ? "" : " / ${currentSlot.endMinutes - currentSlot.startMinutes}m"}",
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            "Student Present: ${presentStudents.length}",
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: presentStudents.isEmpty
                              ? null
                              : () => _showPresentStudentsSheet(
                                    context,
                                    students: presentStudents,
                                    lectureId: activeLectureId,
                                  ),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                          child: const Text("View"),
                        ),
                        const SizedBox(width: 4),
                        TextButton(
                          onPressed: _endingLecture ? null : _endActiveLecture,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                          child: Text(_endingLecture ? "Ending..." : "End Lecture"),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              _LectureStrip(
                title: "Upcoming Lecture",
                dotColor: Colors.blue,
                children: todayUpcoming.isEmpty
                    ? (upcomingSlots.isEmpty
                        ? const [Text("No upcoming lecture")]
                        : upcomingSlots
                            .map((slot) => Text(_slotLabel(slot)))
                            .toList())
                    : [
                        Text(_lectureLine(todayUpcoming.first)),
                        if (todayUpcoming.length > 1) ...[
                          const SizedBox(height: 4),
                          Text(_lectureLine(todayUpcoming[1])),
                        ],
                        const SizedBox(height: 4),
                        Align(
                          alignment: Alignment.centerRight,
                          child: AppButton(
                            label: "Start Lecture",
                            icon: Icons.play_circle_fill_rounded,
                            onPressed: () => _showStartLectureSheet(
                              todayUpcoming.first,
                              allUpcoming: todayUpcoming,
                            ),
                          ),
                        ),
                      ],
              ),
              const SizedBox(height: 10),
              _LectureStrip(
                title: "Completed Lecture",
                dotColor: Colors.green,
                children: todayCompletedOverview.isEmpty
                    ? const [Text("No completed lecture")]
                    : todayCompletedOverview
                        .take(3)
                        .map((e) => Text(_completedLine(e)))
                        .toList(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionTitle("Today's Meetings"),
              const SizedBox(height: 8),
              if (todayMeetings.isEmpty)
                const Text("No meetings scheduled for today")
              else
                ...todayMeetings
                    .take(4)
                    .map((m) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: [
                              const Icon(Icons.video_call_rounded, size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  "${m["title"]} • ${m["time"]}",
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        )),
            ],
          ),
        ),
        const SizedBox(height: 10),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionTitle("DocEd Status"),
              const SizedBox(height: 8),
              Text(
                "Today: ${docEdStatus.todayTotal} appointments • Pending: ${docEdStatus.pending} • Collected: ${docEdStatus.collected}",
              ),
              const SizedBox(height: 6),
              Text(
                docEdStatus.nextLabel,
                style: TextStyle(
                  color: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.color
                      ?.withValues(alpha: 0.85),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionTitle("Complaint Status"),
              const SizedBox(height: 8),
              Text(
                "Open: ${complaintStatus.open} • In Progress: ${complaintStatus.inProgress} • Resolved: ${complaintStatus.resolved}",
              ),
              const SizedBox(height: 8),
              if (complaintStatus.latestSubjects.isEmpty)
                const Text("No complaints yet")
              else
                ...complaintStatus.latestSubjects
                    .map((text) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text("• $text"),
                        )),
            ],
          ),
        ),
      ],
    );
  }

  List<Map<String, String>> _todayMeetings(List<dynamic> rows) {
    final now = TimeFormat.nowIst();
    final today = DateTime(now.year, now.month, now.day);
    final list = <Map<String, String>>[];
    for (final row in rows) {
      if (row is! Map<String, dynamic>) {
        continue;
      }
      final parsed = TimeFormat.parseToIst(row["scheduled_at"]?.toString());
      if (parsed == null) {
        continue;
      }
      final day = DateTime(parsed.year, parsed.month, parsed.day);
      if (day != today) {
        continue;
      }
      list.add({
        "title": (row["title"] ?? "Meeting").toString(),
        "time": TimeFormat.formatMinutes12h((parsed.hour * 60) + parsed.minute),
      });
    }
    return list;
  }

  _DocEdHomeStatus _docEdStatus(List<dynamic> rows) {
    final now = TimeFormat.nowIst();
    final today = DateTime(now.year, now.month, now.day);
    var total = 0;
    var pending = 0;
    var collected = 0;
    DateTime? nextTime;
    String nextText = "No upcoming DocEd appointment";
    for (final row in rows) {
      if (row is! Map<String, dynamic>) {
        continue;
      }
      final at = TimeFormat.parseToIst(row["appointment_at"]?.toString());
      if (at == null) {
        continue;
      }
      final day = DateTime(at.year, at.month, at.day);
      if (day == today) {
        total += 1;
      }
      final status = (row["status"] ?? "PENDING").toString().toUpperCase();
      if (status == "COLLECTED") {
        collected += 1;
      } else {
        pending += 1;
      }
      if (at.isAfter(now) && (nextTime == null || at.isBefore(nextTime))) {
        nextTime = at;
        final student = (row["student_name"] ?? "Student").toString();
        final doc = (row["document_type"] ?? "Document").toString();
        nextText =
            "Next: $doc for $student at ${TimeFormat.formatMinutes12h((at.hour * 60) + at.minute)}";
      }
    }
    return _DocEdHomeStatus(
      todayTotal: total,
      pending: pending,
      collected: collected,
      nextLabel: nextText,
    );
  }

  _ComplaintHomeStatus _complaintStatus(List<dynamic> rows) {
    var open = 0;
    var inProgress = 0;
    var resolved = 0;
    final latest = <String>[];
    for (final row in rows) {
      if (row is! Map<String, dynamic>) {
        continue;
      }
      final status = (row["status"] ?? "OPEN").toString().toUpperCase();
      if (status == "RESOLVED") {
        resolved += 1;
      } else if (status == "IN_PROGRESS") {
        inProgress += 1;
      } else {
        open += 1;
      }
      final subject = (row["subject"] ?? row["title"] ?? "").toString().trim();
      if (subject.isNotEmpty && latest.length < 3) {
        latest.add("$subject (${status.replaceAll("_", " ")})");
      }
    }
    return _ComplaintHomeStatus(
      open: open,
      inProgress: inProgress,
      resolved: resolved,
      latestSubjects: latest,
    );
  }

  List<Map<String, dynamic>> _todayUpcomingLectures(List<dynamic> rows) {
    final now = TimeFormat.nowIst();
    final today = DateTime(now.year, now.month, now.day);
    final list = <Map<String, dynamic>>[];
    for (final row in rows) {
      if (row is! Map<String, dynamic>) {
        continue;
      }
      final parsed = TimeFormat.parseToIst(row["scheduled_at"]?.toString());
      if (parsed == null) {
        continue;
      }
      final day = DateTime(parsed.year, parsed.month, parsed.day);
      if (day == today && parsed.isAfter(now)) {
        list.add(row);
      }
    }
    list.sort((a, b) {
      final ap = TimeFormat.parseToIst(a["scheduled_at"]?.toString()) ?? now;
      final bp = TimeFormat.parseToIst(b["scheduled_at"]?.toString()) ?? now;
      return ap.compareTo(bp);
    });
    return list;
  }

  String _classLabelFromLecture(Map<String, dynamic> row) {
    final candidates = [
      row["class_name"],
      row["classroom"],
      row["division"],
      row["section"],
      row["department_name"],
      row["department_id"] == null ? null : "Class ${row["department_id"]}",
    ];
    for (final c in candidates) {
      final text = (c ?? "").toString().trim();
      if (text.isNotEmpty) {
        return text;
      }
    }
    return "Class A";
  }

  String _subjectFromLecture(Map<String, dynamic> row) {
    final title = (row["title"] ?? "").toString().trim();
    if (title.isNotEmpty) {
      return title;
    }
    final id = row["id"] ?? row["lecture_id"] ?? "-";
    return "Lecture #$id";
  }

  String _roomFromLecture(Map<String, dynamic> row) {
    final candidates = [row["classroom_id"], row["room_no"], row["room"]];
    for (final c in candidates) {
      final text = (c ?? "").toString().trim();
      if (text.isNotEmpty && text != "null") {
        return text;
      }
    }
    return "";
  }

  Future<void> _showStartLectureSheet(
    Map<String, dynamic> source, {
    required List<Map<String, dynamic>> allUpcoming,
  }) async {
    final classMeta = <String, int?>{};
    for (final row in allUpcoming) {
      final label = _classLabelFromLecture(row);
      final roomIdRaw = row["classroom_id"];
      final roomId = roomIdRaw is int
          ? roomIdRaw
          : int.tryParse(roomIdRaw?.toString() ?? "");
      classMeta[label] = roomId;
    }
    if (classMeta.isEmpty) {
      classMeta["Class A"] = null;
    }
    final classOptions = classMeta.keys.toList()..sort();
    final selectedClasses = <String>{_classLabelFromLecture(source)};
    selectedClasses.removeWhere((c) => !classMeta.containsKey(c));
    if (selectedClasses.isEmpty && classOptions.isNotEmpty) {
      selectedClasses.add(classOptions.first);
    }
    var roomText = _roomFromLecture(source);
    var subjectText = _subjectFromLecture(source);
    Map<String, dynamic>? startedPayloadResult;

    final started = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            left: 12,
            right: 12,
            bottom: MediaQuery.of(context).viewInsets.bottom + 12,
          ),
          child: StatefulBuilder(
            builder: (context, setLocal) => AppCard(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Start Lecture",
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Text("Classes",
                            style: TextStyle(fontWeight: FontWeight.w700)),
                        const Spacer(),
                        TextButton(
                          onPressed: () {
                            setLocal(() {
                              if (selectedClasses.length == classOptions.length) {
                                selectedClasses.clear();
                              } else {
                                selectedClasses
                                  ..clear()
                                  ..addAll(classOptions);
                              }
                            });
                          },
                          child: Text(
                            selectedClasses.length == classOptions.length
                                ? "Unselect All"
                                : "Select All",
                          ),
                        ),
                      ],
                    ),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 170),
                      child: ListView(
                        shrinkWrap: true,
                        children: classOptions.map((className) {
                          final checked = selectedClasses.contains(className);
                          return CheckboxListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            value: checked,
                            onChanged: (_) {
                              setLocal(() {
                                if (checked) {
                                  selectedClasses.remove(className);
                                } else {
                                  selectedClasses.add(className);
                                }
                              });
                            },
                            title: Text(className),
                            controlAffinity: ListTileControlAffinity.leading,
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      initialValue: roomText,
                      onChanged: (value) => roomText = value,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: "Room No"),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      initialValue: subjectText,
                      onChanged: (value) => subjectText = value,
                      decoration: const InputDecoration(labelText: "Subject"),
                    ),
                    const SizedBox(height: 12),
                    AppButton(
                      label: "Start Now",
                      icon: Icons.play_arrow_rounded,
                      onPressed: () async {
                        if (selectedClasses.isEmpty) {
                          GlassToast.show(
                            context,
                            "Select at least one class.",
                            icon: Icons.error_outline,
                          );
                          return;
                        }
                        final roomNo = int.tryParse(roomText.trim());
                        if (roomNo == null) {
                          GlassToast.show(
                            context,
                            "Enter valid room number.",
                            icon: Icons.error_outline,
                          );
                          return;
                        }
                        var startedCount = 0;
                        int? firstLectureId;
                        int? firstRoomId;
                        int? firstDurationMs;
                        int? firstScheduledStart;
                        if (!kUseDemoDataEverywhere) {
                          for (final className in selectedClasses) {
                            final classRoomId = classMeta[className];
                            final res =
                                await _api.startLecture(classRoomId ?? roomNo);
                            if (res.statusCode >= 200 && res.statusCode < 300) {
                              startedCount += 1;
                              if (firstLectureId == null) {
                                try {
                                  final p =
                                      jsonDecode(res.body) as Map<String, dynamic>;
                                  firstLectureId =
                                      (p["id"] as num?)?.toInt();
                                  firstRoomId = classRoomId ?? roomNo;
                                  firstDurationMs =
                                      ((p["scheduled_duration_ms"] as num?)
                                                  ?.toInt() ??
                                              60) *
                                          60 *
                                          1000;
                                  firstScheduledStart =
                                      p["scheduled_start"] as int?;
                                } catch (_) {}
                              }
                            }
                          }
                        } else {
                          startedCount = selectedClasses.length;
                        }
                        if (!context.mounted) {
                          return;
                        }
                        if (startedCount > 0) {
                          if (firstLectureId != null && firstRoomId != null) {
                            try {
                              await _smartAttendance.startProfessorSession(
                                lectureId: firstLectureId,
                                roomId: firstRoomId,
                                scheduledDurationMs:
                                    firstDurationMs ?? 3600000,
                                minAttendancePercent: 75,
                                scheduledStart: firstScheduledStart,
                              );
                            } catch (_) {
                              if (!context.mounted) return;
                              GlassToast.show(
                                context,
                                "BLE beacon not started. Enable Bluetooth and allow Advertise permission, then retry.",
                                icon: Icons.error_outline,
                              );
                              return;
                            }
                          }
                          final firstClass = selectedClasses.isEmpty
                              ? "Class A"
                              : selectedClasses.first;
                          startedPayloadResult = <String, dynamic>{
                            "title": subjectText.trim().isEmpty
                                ? "Lecture"
                                : subjectText.trim(),
                            "classroom_id": classMeta[firstClass] ?? roomNo,
                            "room_no": roomText.trim(),
                            "classes": selectedClasses.toList(),
                            "started_count": startedCount,
                          };
                          if (!context.mounted) return;
                          Navigator.of(context).pop(true);
                          return;
                        }
                        if (!context.mounted) return;
                        GlassToast.show(
                          context,
                          "Unable to start selected lectures.",
                          icon: Icons.error_outline,
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    if (started == true && mounted && startedPayloadResult != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) {
          return;
        }
        if (widget.onLectureStarted != null) {
          await widget.onLectureStarted!(startedPayloadResult!);
        }
        final startedClasses =
            (startedPayloadResult!["classes"] as List<dynamic>? ?? const [])
                .map((e) => e.toString())
                .toList();
        await _CalendarSync.upsert(
          id: "home-start-lecture-${DateTime.now().microsecondsSinceEpoch}",
          when: TimeFormat.nowIst(),
          title:
              "Lecture Started: ${(startedPayloadResult!["title"] ?? "Lecture").toString()}",
          details:
              "${startedClasses.join(", ")} • Room ${(startedPayloadResult!["room_no"] ?? "-").toString()}",
          type: "TIMETABLE",
        );
        if (!mounted) {
          return;
        }
        final startedCount =
            (startedPayloadResult!["started_count"] as num?)?.toInt() ?? 1;
        GlassToast.show(
          context,
          "$startedCount lecture(s) started.",
          icon: Icons.check_circle_outline,
        );
      });
    }
  }

  List<Map<String, dynamic>> _todayCompletedLectures(
      List<Map<String, dynamic>> rows) {
    final now = TimeFormat.nowIst();
    final today = DateTime(now.year, now.month, now.day);
    return rows.where((row) {
      final parsed = TimeFormat.parseToIst(row["end_time"]?.toString());
      if (parsed == null) {
        return false;
      }
      final day = DateTime(parsed.year, parsed.month, parsed.day);
      return day == today;
    }).toList();
  }

  String _lectureSubjectRoom(Map<String, dynamic> lecture) {
    final subject = (lecture["title"]?.toString().trim().isNotEmpty ?? false)
        ? lecture["title"].toString()
        : "Lecture #${lecture["id"] ?? lecture["lecture_id"] ?? "-"}";
    final room = (lecture["classroom_id"] ?? "-").toString();
    return "$subject - Room $room";
  }

  Future<void> _showPresentStudentsSheet(
    BuildContext hostContext, {
    required List<_PresentStudent> students,
    required int? lectureId,
  }) async {
    await showModalBottomSheet<void>(
      context: hostContext,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Builder(
            builder: (context) {
              final scheme = Theme.of(context).colorScheme;
              final dark = Theme.of(context).brightness == Brightness.dark;
              return Container(
                decoration: BoxDecoration(
                  color: Color.alphaBlend(
                    scheme.primary.withValues(alpha: dark ? 0.12 : 0.08),
                    scheme.surface,
                  ),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(24)),
                  border: Border.all(
                    color:
                        scheme.onSurface.withValues(alpha: dark ? 0.16 : 0.10),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.groups_rounded, color: scheme.primary),
                          const SizedBox(width: 8),
                          const Text("Students Present",
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w700)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 360),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: students.length,
                          separatorBuilder: (_, __) => Divider(
                              height: 1,
                              color: scheme.onSurface.withValues(alpha: 0.10)),
                          itemBuilder: (context, index) {
                            final student = students[index];
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(student.name),
                              subtitle: Text("ID: ${student.id}"),
                              trailing: Icon(Icons.chevron_right_rounded,
                                  color: scheme.primary),
                              onTap: () async {
                                Navigator.of(sheetContext).pop();
                                await _showStudentAttendanceSheet(
                                  hostContext,
                                  student: student,
                                  lectureId: lectureId,
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  int? _activeLectureId(dynamic lecture) {
    if (lecture is! Map<String, dynamic>) {
      return null;
    }
    final id = lecture["id"] ?? lecture["lecture_id"];
    if (id is int) {
      return id;
    }
    return int.tryParse(id?.toString() ?? "");
  }

  String _lectureLabel(dynamic lecture) {
    if (lecture is! Map<String, dynamic>) {
      return "Lecture";
    }
    final id = lecture["id"] ?? lecture["lecture_id"] ?? "-";
    final classroom = lecture["classroom_id"];
    if (classroom != null) {
      return "Lecture #$id  •  Classroom $classroom";
    }
    return "Lecture #$id";
  }

  String _completedLine(dynamic row) {
    if (row is! Map<String, dynamic>) {
      return "Completed";
    }
    final endedRaw = row["end_time"]?.toString();
    final ended = TimeFormat.parseToIst(endedRaw);
    if (ended != null) {
      return "Ended ${TimeFormat.formatDateTime12hIst(ended)}";
    }
    final startRaw = row["start_time"]?.toString();
    final start = TimeFormat.parseToIst(startRaw);
    if (start != null) {
      return "Started ${TimeFormat.formatDateTime12hIst(start)}";
    }
    return "Completed";
  }

  String _lectureLine(dynamic e) {
    if (e is! Map<String, dynamic>) {
      return e.toString();
    }
    if (e.containsKey("title")) {
      final title = e["title"]?.toString() ?? "Lecture";
      final when = e["scheduled_at"]?.toString() ?? "";
      final parsed = TimeFormat.parseToIst(when);
      final whenLabel =
          parsed == null ? when : TimeFormat.formatDateTime12hIst(parsed);
      return whenLabel.isEmpty ? title : "$title ($whenLabel)";
    }
    return _lectureLabel(e);
  }

  List<_PresentStudent> _studentsPresentForActiveLecture(int? lectureId) {
    if (lectureId == null) {
      return const [];
    }
    final seen = <int>{};
    final list = <_PresentStudent>[];
    for (final row in widget.nearbyStudents) {
      if (row is! Map<String, dynamic>) {
        continue;
      }
      final rowLectureId = row["lecture_id"];
      final rowLectureParsed = rowLectureId is int
          ? rowLectureId
          : int.tryParse(rowLectureId?.toString() ?? "");
      if (rowLectureParsed != lectureId) {
        continue;
      }
      final studentIdRaw = row["student_id"];
      final studentId = studentIdRaw is int
          ? studentIdRaw
          : int.tryParse(studentIdRaw?.toString() ?? "");
      if (studentId == null || seen.contains(studentId)) {
        continue;
      }
      seen.add(studentId);
      final inside = row["inside_geofence"];
      if (inside is bool && inside == false) {
        continue;
      }
      final name = (row["student_name"] ??
              widget.studentNames[studentId] ??
              "Student #$studentId")
          .toString();
      list.add(
        _PresentStudent(
          id: studentId,
          name: name,
          summary: widget.studentSummary[studentId],
        ),
      );
    }
    return list;
  }

  Future<void> _showStudentAttendanceSheet(
    BuildContext context, {
    required _PresentStudent student,
    required int? lectureId,
  }) async {
    final summary = student.summary;
    int total = summary?.totalLectures ?? 0;
    int present = summary?.presentCount ?? 0;
    double percent = summary?.attendancePercentage ?? 0;
    bool subjectWise = false;

    if (kUseDemoDataEverywhere) {
      total = 24;
      present = student.id % 2 == 0 ? 19 : 22;
      percent = (present / total) * 100.0;
      subjectWise = true;
    } else if (lectureId != null) {
      final res = await ApiService().lectureStudentSubjectAttendance(
        lectureId: lectureId,
        studentId: student.id,
      );
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final decoded = jsonDecode(res.body);
        if (decoded is Map<String, dynamic>) {
          total = (decoded["total_lectures"] as num?)?.toInt() ?? total;
          present = (decoded["present_count"] as num?)?.toInt() ?? present;
          percent =
              (decoded["attendance_percentage"] as num?)?.toDouble() ?? percent;
          subjectWise = true;
        }
      }
    }

    if (!context.mounted) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(student.name,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text("Current Active Subject: Lecture #${lectureId ?? "-"}"),
              const SizedBox(height: 6),
              Text("Student ID: ${student.id}"),
              const SizedBox(height: 12),
              if (summary == null && !subjectWise)
                const Text("Attendance summary unavailable for this student.")
              else
                Text(
                  "Total Attendance in this subject: $present/$total (${percent.toStringAsFixed(1)}%)"
                  "${subjectWise ? "" : " (overall fallback)"}",
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

class _LectureStrip extends StatelessWidget {
  const _LectureStrip({
    required this.title,
    required this.dotColor,
    required this.children,
    this.compact = false,
  });

  final String title;
  final Color dotColor;
  final List<Widget> children;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: compact
          ? const EdgeInsets.fromLTRB(10, 6, 10, 6)
          : const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration:
                    BoxDecoration(color: dotColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700)),
            ],
          ),
          SizedBox(height: compact ? 2 : 8),
          ...children.map(
            (child) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

class _StudentAttendanceSummary {
  const _StudentAttendanceSummary({
    required this.totalLectures,
    required this.presentCount,
    required this.attendancePercentage,
  });

  final int totalLectures;
  final int presentCount;
  final double attendancePercentage;
}

class _PresentStudent {
  const _PresentStudent({
    required this.id,
    required this.name,
    required this.summary,
  });

  final int id;
  final String name;
  final _StudentAttendanceSummary? summary;
}

class _DocEdHomeStatus {
  const _DocEdHomeStatus({
    required this.todayTotal,
    required this.pending,
    required this.collected,
    required this.nextLabel,
  });

  final int todayTotal;
  final int pending;
  final int collected;
  final String nextLabel;
}

class _ComplaintHomeStatus {
  const _ComplaintHomeStatus({
    required this.open,
    required this.inProgress,
    required this.resolved,
    required this.latestSubjects,
  });

  final int open;
  final int inProgress;
  final int resolved;
  final List<String> latestSubjects;
}

class _LectureStateSections extends StatelessWidget {
  const _LectureStateSections({
    required this.ongoing,
    required this.upcoming,
    required this.completed,
  });

  final List<dynamic> ongoing;
  final List<dynamic> upcoming;
  final List<dynamic> completed;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _LectureStateCard(
          title: "On Going Lec",
          color: Colors.red,
          items: ongoing,
          emptyText: "No ongoing lecture",
        ),
        const SizedBox(height: 10),
        _LectureStateCard(
          title: "Will Be Conducted Lec",
          color: Colors.blue,
          items: upcoming,
          emptyText: "No upcoming lecture",
        ),
        const SizedBox(height: 10),
        _LectureStateCard(
          title: "Complete Lec",
          color: Colors.green,
          items: completed,
          emptyText: "No completed lecture",
        ),
      ],
    );
  }
}

class _LectureStateCard extends StatelessWidget {
  const _LectureStateCard({
    required this.title,
    required this.color,
    required this.items,
    required this.emptyText,
  });

  final String title;
  final Color color;
  final List<dynamic> items;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 8),
          if (items.isEmpty)
            Text(emptyText)
          else
            ...items.take(3).map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      _lectureLine(e),
                      style: TextStyle(
                          color: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.color
                              ?.withValues(alpha: 0.9)),
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  String _lectureLine(dynamic e) {
    if (e is! Map<String, dynamic>) {
      return e.toString();
    }
    if (e.containsKey("title")) {
      final title = e["title"]?.toString() ?? "Lecture";
      final when = e["scheduled_at"]?.toString() ?? "";
      final parsed = TimeFormat.parseToIst(when);
      final whenLabel =
          parsed == null ? when : TimeFormat.formatDateTime12hIst(parsed);
      return whenLabel.isEmpty ? title : "$title ($whenLabel)";
    }
    final id = e["id"] ?? e["lecture_id"] ?? "-";
    return "Lecture #$id";
  }
}

class _LecturesTab extends StatefulWidget {
  const _LecturesTab();

  @override
  State<_LecturesTab> createState() => _LecturesTabState();
}

class _NotesTab extends StatelessWidget {
  const _NotesTab();

  @override
  Widget build(BuildContext context) => const LearnEdScreen();
}

/*
class _NotesTabState extends State<_NotesTab> {
  final ApiService _api = ApiService();
  static const bool _forceCloudSyncForNotes = true;
  static const String _notesLocalKey = "notes_local_resources_v2";
  static const String _announcementsLocalKey = "notes_local_announcements_v2";
  static const String _assignmentsLocalKey = "notes_local_assignments_v1";
  static const String _submissionsLocalKey = "notes_local_submissions_v1";
  bool _loading = false;
  bool _offline = false;
  List<dynamic> _notes = [];
  List<Map<String, dynamic>> _announcements = [];
  List<Map<String, dynamic>> _assignments = [];
  List<Map<String, dynamic>> _submissions = [];
  final TextEditingController _resourceTitle = TextEditingController();
  final TextEditingController _resourceUrl = TextEditingController();
  final TextEditingController _announcement = TextEditingController();
  final TextEditingController _assignmentTitle = TextEditingController();
  final TextEditingController _assignmentTemplateText = TextEditingController();
  final TextEditingController _assignmentTemplateUrl = TextEditingController();
  String _selectedSubject = "CT";
  String _selectedType = "NOTES";
  String _activeTab = "STREAM";

  static const List<Map<String, dynamic>> _demoNotes = <Map<String, dynamic>>[
    {
      "title": "CT | NOTES | Problem Solving Basics",
      "url": "https://example.com/ct-notes",
      "created_by": 2,
      "created_at": "2026-02-24T03:20:00Z",
    },
    {
      "title": "DBMS | ASSIGNMENT | SQL Practice Set 1",
      "url": "https://example.com/dbms-assignment",
      "created_by": 2,
      "created_at": "2026-02-24T05:00:00Z",
    },
    {
      "title": "CT | PRACTICAL | Loop Tracing Worksheet",
      "url": "https://example.com/ct-practical-worksheet",
      "created_by": 2,
      "created_at": "2026-02-24T06:40:00Z",
    },
  ];

  static const List<Map<String, dynamic>> _demoAnnouncements =
      <Map<String, dynamic>>[
    {
      "subject": "CT",
      "message": "Bring rough notebooks for today`s in-class activity.",
      "author": "Prof. Nirosha Uppu",
      "created_at": "2026-02-24T04:30:00Z",
    },
    {
      "subject": "DBMS",
      "message": "Tomorrow there will be a short surprise quiz on SQL joins.",
      "author": "Dr. Vaishali M. Shinde",
      "created_at": "2026-02-24T06:00:00Z",
    },
  ];
  static const List<Map<String, dynamic>> _demoAssignments =
      <Map<String, dynamic>>[
    {
      "id": "asg-ct-001",
      "subject": "CT",
      "title": "Algorithm Design Worksheet",
      "template_text":
          "Use the template and write pseudocode for 3 sorting strategies.",
      "template_url": "https://example.com/templates/ct-algo-sheet",
      "due_at": "2026-02-26T12:30:00Z",
      "created_by": "Prof. Nirosha Uppu",
      "created_at": "2026-02-24T07:10:00Z",
    },
    {
      "id": "asg-dbms-001",
      "subject": "DBMS",
      "title": "SQL Query Lab",
      "template_text":
          "Fill query outputs and explain optimization for each query.",
      "template_url": "https://example.com/templates/dbms-query-lab",
      "due_at": "2026-02-27T11:30:00Z",
      "created_by": "Dr. Vaishali M. Shinde",
      "created_at": "2026-02-24T08:00:00Z",
    },
  ];

  static const List<Map<String, String>> _subjects = <Map<String, String>>[
    {
      "code": "CT",
      "name": "Computational Thinking",
      "faculty": "Prof. Nirosha Uppu"
    },
    {
      "code": "DBMS",
      "name": "Database Management Systems",
      "faculty": "Dr. Vaishali M. Shinde"
    },
    {
      "code": "DSM",
      "name": "Data Science & MDM",
      "faculty": "Prof. Manisha Punse"
    },
    {
      "code": "MDM",
      "name": "Marketing Data Management",
      "faculty": "Dr. Archana Chaudhari"
    },
    {
      "code": "BMD",
      "name": "Business Model Design",
      "faculty": "Dr. Sanjay Deshmukh"
    },
    {
      "code": "DT",
      "name": "Design Thinking",
      "faculty": "Dr. Manoj Kumar Yadav"
    },
    {
      "code": "OE",
      "name": "Open Elective (Fintech)",
      "faculty": "Prof. Swarmala Mahendran"
    },
  ];
  static const Map<String, List<String>> _syllabusBySubject =
      <String, List<String>>{
    "CT": <String>[
      "Unit 1: Problem Solving and Logic Building",
      "Unit 2: Algorithms and Flowcharts",
      "Unit 3: Arrays, Strings, and Searching",
      "Unit 4: Sorting and Complexity Basics",
      "Unit 5: Applied Computational Thinking",
    ],
    "DBMS": <String>[
      "Unit 1: ER Modelling and Relational Model",
      "Unit 2: SQL DDL, DML, DCL",
      "Unit 3: Joins, Subqueries, Set Operations",
      "Unit 4: Normalization and Transactions",
      "Unit 5: Indexing and Query Optimization",
    ],
    "DSM": <String>[
      "Unit 1: Data Science Workflow",
      "Unit 2: Data Cleaning and Feature Engineering",
      "Unit 3: Exploratory Data Analysis",
      "Unit 4: Supervised Learning Basics",
      "Unit 5: Model Evaluation and Reporting",
    ],
  };

  @override
  void initState() {
    super.initState();
    _loadLocalClassroomState();
    _load();
  }

  @override
  void dispose() {
    _resourceTitle.dispose();
    _resourceUrl.dispose();
    _announcement.dispose();
    _assignmentTitle.dispose();
    _assignmentTemplateText.dispose();
    _assignmentTemplateUrl.dispose();
    super.dispose();
  }

  Future<void> _loadLocalClassroomState() async {
    final prefs = await SharedPreferences.getInstance();
    List<dynamic> decodeList(String? raw) {
      if (raw == null || raw.isEmpty) {
        return const [];
      }
      try {
        final decoded = jsonDecode(raw);
        return decoded is List ? decoded : const [];
      } catch (_) {
        return const [];
      }
    }

    final localNotes = decodeList(prefs.getString(_notesLocalKey));
    final localAnnouncements =
        decodeList(prefs.getString(_announcementsLocalKey));
    final localAssignments = decodeList(prefs.getString(_assignmentsLocalKey));
    final localSubmissions = decodeList(prefs.getString(_submissionsLocalKey));

    if (!mounted) {
      return;
    }
    setState(() {
      if (localNotes.isNotEmpty) {
        _notes = localNotes;
      }
      if (localAnnouncements.isNotEmpty) {
        _announcements =
            localAnnouncements.whereType<Map<String, dynamic>>().toList();
      }
      if (localAssignments.isNotEmpty) {
        _assignments =
            localAssignments.whereType<Map<String, dynamic>>().toList();
      }
      if (localSubmissions.isNotEmpty) {
        _submissions =
            localSubmissions.whereType<Map<String, dynamic>>().toList();
      }
    });
  }

  Future<void> _persistLocalClassroomState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_notesLocalKey, jsonEncode(_notes));
    await prefs.setString(_announcementsLocalKey, jsonEncode(_announcements));
    await prefs.setString(_assignmentsLocalKey, jsonEncode(_assignments));
    await prefs.setString(_submissionsLocalKey, jsonEncode(_submissions));
    await _api.saveCache("notes_assignments", _assignments);
    await _api.saveCache("notes_submissions", _submissions);
  }

  Future<void> _load({bool silent = false}) async {
    if (kUseDemoDataEverywhere && !_forceCloudSyncForNotes) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _offline = false;
        _notes = _notes.isEmpty ? _demoNotes : _notes;
        if (_announcements.isEmpty) {
          _announcements = List<Map<String, dynamic>>.from(_demoAnnouncements);
        }
        if (_assignments.isEmpty) {
          _assignments = List<Map<String, dynamic>>.from(_demoAssignments);
        }
      });
      await _persistLocalClassroomState();
      return;
    }
    setState(() => _loading = true);
    final res = await _api.listNotes();
    final assignmentsRes = await _api.listAssignments();
    final submissionsRes = await _api.listAssignmentSubmissions();
    final isOffline = !(await _api.isBackendOnlineCached());
    List<dynamic> nextNotes = _notes;
    List<Map<String, dynamic>> nextAssignments = _assignments;
    List<Map<String, dynamic>> nextSubmissions = _submissions;
    if (isOffline) {
      nextNotes =
          (await _api.readCache("notes_list") as List<dynamic>?) ?? nextNotes;
      nextAssignments =
          (await _api.readCache("notes_assignments") as List<dynamic>?)
                  ?.whereType<Map<String, dynamic>>()
                  .toList() ??
              nextAssignments;
      nextSubmissions =
          (await _api.readCache("notes_submissions") as List<dynamic>?)
                  ?.whereType<Map<String, dynamic>>()
                  .toList() ??
              nextSubmissions;
    } else if (res.statusCode >= 200 && res.statusCode < 300) {
      nextNotes = jsonDecode(res.body) as List<dynamic>;
      await _api.saveCache("notes_list", nextNotes);
      if (assignmentsRes.statusCode >= 200 && assignmentsRes.statusCode < 300) {
        nextAssignments = (jsonDecode(assignmentsRes.body) as List<dynamic>)
            .whereType<Map<String, dynamic>>()
            .toList();
        await _api.saveCache("notes_assignments", nextAssignments);
      }
      if (submissionsRes.statusCode >= 200 && submissionsRes.statusCode < 300) {
        nextSubmissions = (jsonDecode(submissionsRes.body) as List<dynamic>)
            .whereType<Map<String, dynamic>>()
            .toList();
        await _api.saveCache("notes_submissions", nextSubmissions);
      }
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _loading = false;
      _offline = isOffline;
      _notes = nextNotes;
      _assignments = nextAssignments;
      _submissions = nextSubmissions;
    });
    await _persistLocalClassroomState();
  }

  Future<void> _create() async {
    if (_resourceTitle.text.trim().isEmpty ||
        _resourceUrl.text.trim().isEmpty) {
      return;
    }
    final title =
        "$_selectedSubject | $_selectedType | ${_resourceTitle.text.trim()}";
    final rawTitle = _resourceTitle.text.trim();
    final rawUrl = _resourceUrl.text.trim();
    if (kUseDemoDataEverywhere && !_forceCloudSyncForNotes) {
      if (!mounted) {
        return;
      }
      setState(() {
        _notes = [
          {
            "title": title,
            "url": _resourceUrl.text.trim(),
            "created_by": 2,
            "created_at": DateTime.now().toUtc().toIso8601String(),
          },
          ..._notes,
        ];
      });
      _resourceTitle.clear();
      _resourceUrl.clear();
      await _CalendarSync.upsert(
        id: "learned-resource-${DateTime.now().microsecondsSinceEpoch}",
        when: TimeFormat.nowIst(),
        title: "LearnEd: Resource Added",
        details: "$_selectedSubject • $_selectedType • $rawTitle",
      );
      await _persistLocalClassroomState();
      return;
    }
    final res = await _api.createNote(
      title: title,
      url: rawUrl,
      description: "subject=$_selectedSubject,type=$_selectedType",
    );
    if (res.statusCode >= 200 && res.statusCode < 300) {
      await _CalendarSync.upsert(
        id: "learned-resource-${DateTime.now().microsecondsSinceEpoch}",
        when: TimeFormat.nowIst(),
        title: "LearnEd: Resource Added",
        details: "$_selectedSubject • $_selectedType • $rawTitle",
      );
      _resourceTitle.clear();
      _resourceUrl.clear();
      await _load();
    }
    await _persistLocalClassroomState();
  }

  Future<void> _postAnnouncement() async {
    final message = _announcement.text.trim();
    if (message.isEmpty) {
      return;
    }
    final faculty = _subjectMeta(_selectedSubject)["faculty"] ?? "Professor";
    setState(() {
      _announcements = [
        {
          "subject": _selectedSubject,
          "message": message,
          "author": faculty,
          "created_at": DateTime.now().toUtc().toIso8601String(),
        },
        ..._announcements,
      ];
    });
    _announcement.clear();
    await _CalendarSync.upsert(
      id: "learned-announcement-${DateTime.now().microsecondsSinceEpoch}",
      when: TimeFormat.nowIst(),
      title: "LearnEd: Announcement Posted",
      details: "$_selectedSubject • $message",
    );
    await _persistLocalClassroomState();
  }

  Map<String, String> _subjectMeta(String code) {
    return _subjects.firstWhere(
      (s) => s["code"] == code,
      orElse: () => {"code": code, "name": code, "faculty": "Professor"},
    );
  }

  Map<String, String> _parseResourceTitle(String rawTitle) {
    final parts = rawTitle.split("|").map((e) => e.trim()).toList();
    if (parts.length >= 3) {
      return {
        "subject": parts[0],
        "type": parts[1],
        "title": parts.sublist(2).join(" | ")
      };
    }
    return {"subject": _selectedSubject, "type": "NOTES", "title": rawTitle};
  }

  DateTime _parseTimestamp(dynamic raw) {
    final parsed = TimeFormat.parseToIst(raw?.toString());
    return parsed ?? TimeFormat.nowIst();
  }

  String _formatTimestamp(dynamic raw) {
    return TimeFormat.formatDateTime12hIst(_parseTimestamp(raw));
  }

  List<Map<String, dynamic>> _subjectResources() {
    final rows = <Map<String, dynamic>>[];
    for (final item in _notes) {
      if (item is! Map<String, dynamic>) {
        continue;
      }
      final meta = _parseResourceTitle((item["title"] ?? "").toString());
      if (meta["subject"] != _selectedSubject) {
        continue;
      }
      rows.add({
        "subject": meta["subject"],
        "type": meta["type"],
        "title": meta["title"],
        "url": (item["url"] ?? "").toString(),
        "created_by": item["created_by"],
        "created_at": item["created_at"],
      });
    }
    rows.sort((a, b) => _parseTimestamp(b["created_at"])
        .compareTo(_parseTimestamp(a["created_at"])));
    return rows;
  }

  List<Map<String, dynamic>> _subjectAnnouncements() {
    final rows =
        _announcements.where((a) => a["subject"] == _selectedSubject).toList();
    rows.sort((a, b) => _parseTimestamp(b["created_at"])
        .compareTo(_parseTimestamp(a["created_at"])));
    return rows;
  }

  List<Map<String, dynamic>> _streamRows() {
    final resources = _subjectResources().map(
      (r) => {
        "kind": "RESOURCE",
        "title": r["title"],
        "type": r["type"],
        "subtitle": "Material posted in classwork",
        "url": r["url"],
        "created_at": r["created_at"],
      },
    );
    final announcements = _subjectAnnouncements().map(
      (a) => {
        "kind": "ANNOUNCEMENT",
        "title": (a["message"] ?? "").toString(),
        "type": "ANNOUNCEMENT",
        "subtitle": (a["author"] ?? "Professor").toString(),
        "url": "",
        "created_at": a["created_at"],
      },
    );
    final merged = [...announcements, ...resources];
    merged.sort((a, b) => _parseTimestamp(b["created_at"])
        .compareTo(_parseTimestamp(a["created_at"])));
    return merged;
  }

  Color _typeColor(BuildContext context, String type) {
    final scheme = Theme.of(context).colorScheme;
    switch (type) {
      case "ASSIGNMENT":
        return Colors.orange;
      case "PRACTICAL":
        return Colors.green;
      case "MINI_PROJECT":
        return Colors.purple;
      case "ANNOUNCEMENT":
        return scheme.primary;
      default:
        return Colors.blue;
    }
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case "ASSIGNMENT":
        return Icons.assignment_rounded;
      case "PRACTICAL":
        return Icons.science_rounded;
      case "MINI_PROJECT":
        return Icons.rocket_launch_rounded;
      case "ANNOUNCEMENT":
        return Icons.campaign_rounded;
      default:
        return Icons.note_alt_rounded;
    }
  }

  List<String> _demoStudentsForSubject(String code) {
    switch (code) {
      case "CT":
        return const [
          "Aarav Patil",
          "Diya Shinde",
          "Rohan Kale",
          "Sara Thomas"
        ];
      case "DBMS":
        return const ["Kabir Shah", "Aarohi Jain", "Mihir Roy", "Neha Shetty"];
      case "DSM":
        return const ["Priya Das", "Aditya Kulkarni", "Sakshi Nair"];
      default:
        return const ["Class Student 1", "Class Student 2", "Class Student 3"];
    }
  }

  Future<void> _showResourceDialog(Map<String, dynamic> item) async {
    if (!mounted) {
      return;
    }
    final theme = Theme.of(context);
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(item["title"]?.toString() ?? "Resource"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Type: ${item["type"]}"),
              const SizedBox(height: 8),
              Text("URL: ${(item["url"] ?? "-").toString()}"),
              const SizedBox(height: 8),
              Text(
                _formatTimestamp(item["created_at"]),
                style: TextStyle(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    fontSize: 12),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("Close"),
            ),
          ],
        );
      },
    );
  }

  List<Map<String, dynamic>> _subjectAssignments() {
    final rows =
        _assignments.where((a) => a["subject"] == _selectedSubject).toList();
    rows.sort((a, b) =>
        _parseTimestamp(a["due_at"]).compareTo(_parseTimestamp(b["due_at"])));
    return rows;
  }

  List<Map<String, dynamic>> _submissionsForAssignment(String assignmentId) {
    final rows = _submissions
        .where((s) => s["assignment_id"]?.toString() == assignmentId)
        .toList();
    rows.sort((a, b) => _parseTimestamp(b["submitted_at"])
        .compareTo(_parseTimestamp(a["submitted_at"])));
    return rows;
  }

  Future<String?> _pickAndUploadFile({required String purpose}) async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const [
        "pdf",
        "doc",
        "docx",
        "ppt",
        "pptx",
        "xls",
        "xlsx",
        "txt",
        "png",
        "jpg",
        "jpeg",
      ],
      withData: false,
    );
    if (picked == null || picked.files.isEmpty) {
      return null;
    }
    final filePath = picked.files.single.path;
    if (filePath == null || filePath.isEmpty) {
      return null;
    }
    final res =
        await _api.uploadAttachment(filePath: filePath, purpose: purpose);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final payload = jsonDecode(res.body) as Map<String, dynamic>;
      return (payload["url"] ?? payload["relative_url"])?.toString();
    }
    if (mounted) {
      GlassToast.show(
        context,
        _extractDetailLocal(res.body, fallback: "Upload failed"),
        icon: Icons.error_outline,
      );
    }
    return null;
  }

  String _extractDetailLocal(String body,
      {String fallback = "Request failed"}) {
    try {
      final map = jsonDecode(body) as Map<String, dynamic>;
      return (map["detail"] ?? fallback).toString();
    } catch (_) {
      return fallback;
    }
  }

  Map<String, dynamic>? _submissionForStudent({
    required String assignmentId,
    required String studentEmail,
  }) {
    for (final row in _submissions) {
      if (row["assignment_id"]?.toString() == assignmentId &&
          row["student_email"]?.toString().toLowerCase() ==
              studentEmail.toLowerCase()) {
        return row;
      }
    }
    return null;
  }

  Future<void> _createAssignment(AuthProvider auth) async {
    final title = _assignmentTitle.text.trim();
    final template = _assignmentTemplateText.text.trim();
    if (title.isEmpty || template.isEmpty) {
      return;
    }
    final subject = _subjectMeta(_selectedSubject);
    final createdAt = TimeFormat.nowIst();
    if (kUseDemoDataEverywhere && !_forceCloudSyncForNotes) {
      final assignment = <String, dynamic>{
        "id": "asg-${DateTime.now().microsecondsSinceEpoch}",
        "subject": _selectedSubject,
        "title": title,
        "template_text": template,
        "template_url": _assignmentTemplateUrl.text.trim(),
        "due_at": DateTime.now()
            .toUtc()
            .add(const Duration(days: 2))
            .toIso8601String(),
        "created_by_name": auth.name ?? subject["faculty"] ?? "Professor",
        "created_at": DateTime.now().toUtc().toIso8601String(),
      };
      setState(() {
        _assignments = [assignment, ..._assignments];
      });
    } else {
      final dueAt =
          DateTime.now().toUtc().add(const Duration(days: 2)).toIso8601String();
      final res = await _api.createAssignment(
        subject: _selectedSubject,
        title: title,
        templateText: template,
        templateUrl: _assignmentTemplateUrl.text.trim(),
        dueAt: dueAt,
      );
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final created = jsonDecode(res.body) as Map<String, dynamic>;
        setState(() {
          _assignments = [
            created,
            ..._assignments.where((a) => a["id"] != created["id"])
          ];
        });
      } else {
        final fallback = <String, dynamic>{
          "id": "local-asg-${DateTime.now().microsecondsSinceEpoch}",
          "subject": _selectedSubject,
          "title": title,
          "template_text": template,
          "template_url": _assignmentTemplateUrl.text.trim(),
          "due_at": dueAt,
          "created_by_name": auth.name ?? subject["faculty"] ?? "Professor",
          "created_at": DateTime.now().toUtc().toIso8601String(),
        };
        setState(() {
          _assignments = [fallback, ..._assignments];
        });
      }
    }

    _assignmentTitle.clear();
    _assignmentTemplateText.clear();
    _assignmentTemplateUrl.clear();
    await _CalendarSync.upsert(
      id: "learned-assignment-${DateTime.now().microsecondsSinceEpoch}",
      when: createdAt,
      title: "LearnEd: Assignment Created",
      details: "$_selectedSubject • $title",
    );
    await _persistLocalClassroomState();
  }

  Future<void> _openSubmitSheet({
    required Map<String, dynamic> assignment,
    required AuthProvider auth,
  }) async {
    final existing = _submissionForStudent(
      assignmentId: assignment["id"].toString(),
      studentEmail: (auth.email ?? "").toLowerCase(),
    );
    final answerController =
        TextEditingController(text: existing?["answer_text"]?.toString() ?? "");
    final fileController = TextEditingController(
        text: existing?["attachment_url"]?.toString() ?? "");

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.68,
          minChildSize: 0.50,
          maxChildSize: 0.90,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    assignment["title"]?.toString() ?? "Assignment",
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                      "Template: ${(assignment["template_text"] ?? "").toString()}"),
                  if ((assignment["template_url"] ?? "")
                      .toString()
                      .isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                        "Template Link: ${(assignment["template_url"] ?? "").toString()}"),
                  ],
                  const SizedBox(height: 10),
                  TextField(
                    controller: answerController,
                    minLines: 4,
                    maxLines: 7,
                    decoration: const InputDecoration(
                      labelText: "Your answer",
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: fileController,
                    decoration: const InputDecoration(
                      labelText: "Attachment URL (optional)",
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final url =
                            await _pickAndUploadFile(purpose: "submission");
                        if (url != null) {
                          fileController.text = url;
                        }
                      },
                      icon: const Icon(Icons.attach_file_rounded),
                      label: const Text("Upload Attachment"),
                    ),
                  ),
                  const SizedBox(height: 12),
                  AppButton(
                    label: existing == null
                        ? "Submit Assignment"
                        : "Update Submission",
                    onPressed: () => Navigator.of(context).pop(true),
                    icon: Icons.send_rounded,
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (ok != true) {
      return;
    }

    final submission = <String, dynamic>{
      "assignment_id": assignment["id"].toString(),
      "subject": assignment["subject"].toString(),
      "student_email": (auth.email ?? "student@edusys.edu").toLowerCase(),
      "student_name": auth.name ?? "Student",
      "answer_text": answerController.text.trim(),
      "attachment_url": fileController.text.trim(),
      "submitted_at": DateTime.now().toUtc().toIso8601String(),
    };

    if (kUseDemoDataEverywhere && !_forceCloudSyncForNotes) {
      setState(() {
        _submissions = _submissions
            .where((s) => !(s["assignment_id"]?.toString() ==
                    submission["assignment_id"] &&
                s["student_email"]?.toString().toLowerCase() ==
                    submission["student_email"]))
            .toList();
        _submissions = [submission, ..._submissions];
      });
    } else {
      final assignmentId = int.tryParse(assignment["id"]?.toString() ?? "");
      if (assignmentId == null) {
        setState(() {
          _submissions = _submissions
              .where((s) => !(s["assignment_id"]?.toString() ==
                      submission["assignment_id"] &&
                  s["student_email"]?.toString().toLowerCase() ==
                      submission["student_email"]))
              .toList();
          _submissions = [submission, ..._submissions];
        });
        await _persistLocalClassroomState();
        return;
      }
      final res = await _api.submitAssignment(
        assignmentId: assignmentId,
        answerText: answerController.text.trim(),
        attachmentUrl: fileController.text.trim(),
      );
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final created = jsonDecode(res.body) as Map<String, dynamic>;
        setState(() {
          _submissions = _submissions
              .where((s) => !(s["assignment_id"]?.toString() ==
                      created["assignment_id"]?.toString() &&
                  s["student_email"]?.toString().toLowerCase() ==
                      (created["student_email"]?.toString().toLowerCase() ??
                          "")))
              .toList();
          _submissions = [created, ..._submissions];
        });
      } else {
        setState(() {
          _submissions = _submissions
              .where((s) => !(s["assignment_id"]?.toString() ==
                      submission["assignment_id"] &&
                  s["student_email"]?.toString().toLowerCase() ==
                      submission["student_email"]))
              .toList();
          _submissions = [submission, ..._submissions];
        });
      }
    }
    await _CalendarSync.upsert(
      id: "learned-submission-${DateTime.now().microsecondsSinceEpoch}",
      when: TimeFormat.nowIst(),
      title: "LearnEd: Assignment Submitted",
      details: "${assignment["title"]?.toString() ?? "Assignment"} • ${(auth.email ?? "").toString()}",
    );
    await _persistLocalClassroomState();
  }

  Future<void> _showSubmissionsDialog(Map<String, dynamic> assignment) async {
    final rows = _submissionsForAssignment(assignment["id"].toString());
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text("Submissions - ${assignment["title"]}"),
          content: SizedBox(
            width: 420,
            child: rows.isEmpty
                ? const Text("No submissions yet.")
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const Divider(height: 12),
                    itemBuilder: (context, index) {
                      final s = rows[index];
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (s["student_name"] ?? "Student").toString(),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 2),
                          Text(
                              "Submitted: ${_formatTimestamp(s["submitted_at"])}"),
                          const SizedBox(height: 4),
                          Text(
                              "Answer: ${(s["answer_text"] ?? "-").toString()}"),
                          if ((s["attachment_url"] ?? "").toString().isNotEmpty)
                            Text(
                                "Attachment: ${(s["attachment_url"] ?? "").toString()}"),
                          const SizedBox(height: 4),
                          Text(
                            "Marks: ${(s["marks"] ?? "-").toString()}",
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          if ((s["feedback"] ?? "").toString().isNotEmpty)
                            Text(
                                "Feedback: ${(s["feedback"] ?? "").toString()}"),
                          const SizedBox(height: 4),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () async {
                                Navigator.of(context).pop();
                                await _openGradeDialog(s);
                              },
                              child: const Text("Grade"),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("Close"),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openGradeDialog(Map<String, dynamic> submission) async {
    final marksController =
        TextEditingController(text: (submission["marks"] ?? "").toString());
    final feedbackController =
        TextEditingController(text: (submission["feedback"] ?? "").toString());

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Grade Submission"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: marksController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: "Marks (0-100)"),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: feedbackController,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: "Feedback"),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text("Cancel"),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text("Save"),
            ),
          ],
        );
      },
    );

    if (ok != true) {
      return;
    }

    final marks = int.tryParse(marksController.text.trim());
    final feedback = feedbackController.text.trim();

    if (kUseDemoDataEverywhere && !_forceCloudSyncForNotes) {
      final id = submission["id"]?.toString();
      final assignmentId = submission["assignment_id"]?.toString();
      final studentEmail =
          (submission["student_email"] ?? "").toString().toLowerCase();
      setState(() {
        _submissions = _submissions.map((row) {
          final sameById = id != null && row["id"]?.toString() == id;
          final sameByComposite =
              row["assignment_id"]?.toString() == assignmentId &&
                  (row["student_email"] ?? "").toString().toLowerCase() ==
                      studentEmail;
          if (sameById || sameByComposite) {
            return {
              ...row,
              "marks": marks,
              "feedback": feedback,
              "graded_at": DateTime.now().toUtc().toIso8601String(),
            };
          }
          return row;
        }).toList();
      });
      await _persistLocalClassroomState();
      return;
    }

    final submissionId = int.tryParse(submission["id"]?.toString() ?? "");
    if (submissionId == null) {
      final assignmentId = submission["assignment_id"]?.toString();
      final studentEmail =
          (submission["student_email"] ?? "").toString().toLowerCase();
      setState(() {
        _submissions = _submissions.map((row) {
          final sameByComposite =
              row["assignment_id"]?.toString() == assignmentId &&
                  (row["student_email"] ?? "").toString().toLowerCase() ==
                      studentEmail;
          if (sameByComposite) {
            return {
              ...row,
              "marks": marks,
              "feedback": feedback,
              "graded_at": DateTime.now().toUtc().toIso8601String(),
            };
          }
          return row;
        }).toList();
      });
      await _persistLocalClassroomState();
      return;
    }
    final res = await _api.gradeAssignmentSubmission(
      submissionId: submissionId,
      marks: marks,
      feedback: feedback,
    );
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final updated = jsonDecode(res.body) as Map<String, dynamic>;
      setState(() {
        _submissions = _submissions
            .where((s) => s["id"]?.toString() != updated["id"]?.toString())
            .toList();
        _submissions = [updated, ..._submissions];
      });
      await _persistLocalClassroomState();
    } else {
      final assignmentId = submission["assignment_id"]?.toString();
      final studentEmail =
          (submission["student_email"] ?? "").toString().toLowerCase();
      setState(() {
        _submissions = _submissions.map((row) {
          final sameByComposite =
              row["assignment_id"]?.toString() == assignmentId &&
                  (row["student_email"] ?? "").toString().toLowerCase() ==
                      studentEmail;
          if (sameByComposite) {
            return {
              ...row,
              "marks": marks,
              "feedback": feedback,
              "graded_at": DateTime.now().toUtc().toIso8601String(),
            };
          }
          return row;
        }).toList();
      });
      await _persistLocalClassroomState();
    }
    await _CalendarSync.upsert(
      id: "learned-graded-${DateTime.now().microsecondsSinceEpoch}",
      when: TimeFormat.nowIst(),
      title: "LearnEd: Submission Graded",
      details: "Marks: ${marks?.toString() ?? "-"} • Feedback updated",
    );
  }

  Widget _buildClassroomHeader(BuildContext context) {
    final subject = _subjectMeta(_selectedSubject);
    return AppCard(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1F3B63), Color(0xFF275DA2)],
          ),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "${subject["code"]} - ${subject["name"]}",
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 19),
            ),
            const SizedBox(height: 4),
            const Text(
              "SE - AIDS 2025-26",
              style:
                  TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            Text(
              subject["faculty"] ?? "",
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubjectStrip() {
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _subjects.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final code = _subjects[index]["code"]!;
          final selected = code == _selectedSubject;
          return ChoiceChip(
            label: Text(code),
            selected: selected,
            onSelected: (_) => setState(() => _selectedSubject = code),
          );
        },
      ),
    );
  }

  Widget _buildTabStrip() {
    const tabs = ["STREAM", "CLASSWORK", "ASSIGNMENTS", "PEOPLE", "SYLLABUS"];
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: tabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final tab = tabs[index];
          return ChoiceChip(
            label: Text(tab),
            selected: _activeTab == tab,
            onSelected: (_) => setState(() => _activeTab = tab),
          );
        },
      ),
    );
  }

  Widget _buildStream(bool canUpload) {
    final rows = _streamRows();
    return Column(
      children: [
        if (canUpload)
          AppCard(
            child: Column(
              children: [
                TextField(
                  controller: _announcement,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: "Announce something to class",
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: AppButton(
                        label: "Post Announcement",
                        onPressed: _postAnnouncement,
                        icon: Icons.campaign_rounded,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        if (canUpload) const SizedBox(height: 10),
        if (_loading)
          const LoadingSkeleton(height: 120)
        else if (rows.isEmpty)
          const EmptyStateWidget(message: "No posts yet in this class stream")
        else
          ...rows.map(
            (row) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AppCard(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor:
                        _typeColor(context, row["type"]!.toString())
                            .withValues(alpha: 0.16),
                    child: Icon(_typeIcon(row["type"]!.toString()),
                        color: _typeColor(context, row["type"]!.toString())),
                  ),
                  title: Text(row["title"]!.toString(),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(
                      "${row["subtitle"]}\n${_formatTimestamp(row["created_at"])}"),
                  isThreeLine: true,
                  trailing: row["kind"] == "RESOURCE"
                      ? TextButton(
                          onPressed: () => _showResourceDialog(row),
                          child: const Text("Open"),
                        )
                      : null,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildAssignments({
    required bool canUpload,
    required AuthProvider auth,
  }) {
    final rows = _subjectAssignments();
    final studentEmail = (auth.email ?? "").toLowerCase();

    return Column(
      children: [
        if (canUpload)
          AppCard(
            child: Column(
              children: [
                TextField(
                  controller: _assignmentTitle,
                  decoration:
                      const InputDecoration(labelText: "Assignment Title"),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _assignmentTemplateText,
                  minLines: 3,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: "Template / Instructions",
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _assignmentTemplateUrl,
                  decoration: const InputDecoration(
                    labelText: "Template URL (optional)",
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final url = await _pickAndUploadFile(purpose: "template");
                      if (url != null && mounted) {
                        setState(() => _assignmentTemplateUrl.text = url);
                      }
                    },
                    icon: const Icon(Icons.upload_file_rounded),
                    label: const Text("Upload Template File"),
                  ),
                ),
                const SizedBox(height: 10),
                AppButton(
                  label: "Assign To Class",
                  onPressed: () => _createAssignment(auth),
                  icon: Icons.post_add_rounded,
                ),
              ],
            ),
          ),
        if (canUpload) const SizedBox(height: 10),
        if (rows.isEmpty)
          const EmptyStateWidget(message: "No assignments in this class yet")
        else
          ...rows.map((assignment) {
            final id = assignment["id"]?.toString() ?? "";
            final dueAt = _formatTimestamp(assignment["due_at"]);
            final submission = _submissionForStudent(
              assignmentId: id,
              studentEmail: studentEmail,
            );
            final submissionCount = _submissionsForAssignment(id).length;

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.assignment_rounded),
                      title: Text(
                        assignment["title"]?.toString() ?? "-",
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text("Due: $dueAt"),
                    ),
                    Text(
                      "Template: ${(assignment["template_text"] ?? "").toString()}",
                    ),
                    if ((assignment["template_url"] ?? "")
                        .toString()
                        .isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                          "Template Link: ${(assignment["template_url"] ?? "").toString()}"),
                    ],
                    const SizedBox(height: 10),
                    if (canUpload)
                      Row(
                        children: [
                          Expanded(
                            child: Text("Submissions: $submissionCount"),
                          ),
                          TextButton(
                            onPressed: () => _showSubmissionsDialog(assignment),
                            child: const Text("View"),
                          ),
                        ],
                      )
                    else
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  submission == null
                                      ? "Status: Not submitted"
                                      : "Status: Submitted (${_formatTimestamp(submission["submitted_at"])})",
                                  style: TextStyle(
                                    color: submission == null
                                        ? Colors.orange
                                        : Colors.green,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (submission != null &&
                                    submission["marks"] != null)
                                  Text(
                                    "Graded: ${submission["marks"]}/100",
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700),
                                  ),
                                if (submission != null &&
                                    (submission["feedback"] ?? "")
                                        .toString()
                                        .isNotEmpty)
                                  Text(
                                    "Feedback: ${(submission["feedback"] ?? "").toString()}",
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: () => _openSubmitSheet(
                              assignment: assignment,
                              auth: auth,
                            ),
                            child:
                                Text(submission == null ? "Submit" : "Update"),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildClasswork(bool canUpload) {
    final resources = _subjectResources();
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final row in resources) {
      final type = (row["type"] ?? "NOTES").toString();
      grouped.putIfAbsent(type, () => []).add(row);
    }

    return Column(
      children: [
        if (canUpload)
          AppCard(
            child: Column(
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _selectedType,
                  decoration: const InputDecoration(labelText: "Resource Type"),
                  items: const [
                    DropdownMenuItem(value: "NOTES", child: Text("Notes")),
                    DropdownMenuItem(
                        value: "ASSIGNMENT", child: Text("Assignment")),
                    DropdownMenuItem(
                        value: "PRACTICAL", child: Text("Practical")),
                    DropdownMenuItem(
                        value: "MINI_PROJECT", child: Text("Mini Project")),
                  ],
                  onChanged: (v) =>
                      setState(() => _selectedType = v ?? "NOTES"),
                ),
                const SizedBox(height: 10),
                TextField(
                    controller: _resourceTitle,
                    decoration: const InputDecoration(labelText: "Title")),
                const SizedBox(height: 10),
                TextField(
                    controller: _resourceUrl,
                    decoration:
                        const InputDecoration(labelText: "Resource URL")),
                const SizedBox(height: 10),
                AppButton(
                    label: "Post To Classwork",
                    onPressed: _create,
                    icon: Icons.add_task_rounded),
              ],
            ),
          ),
        if (canUpload) const SizedBox(height: 10),
        if (_loading)
          const LoadingSkeleton(height: 120)
        else if (resources.isEmpty)
          const EmptyStateWidget(
              message: "No classwork material for this subject")
        else
          ...grouped.entries.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.key,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: _typeColor(context, entry.key),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...entry.value.map(
                      (item) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(_typeIcon(entry.key),
                            color: _typeColor(context, entry.key)),
                        title: Text(item["title"]?.toString() ?? "-",
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(_formatTimestamp(item["created_at"])),
                        trailing: TextButton(
                          onPressed: () => _showResourceDialog(item),
                          child: const Text("Open"),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPeople() {
    final subject = _subjectMeta(_selectedSubject);
    final students = _demoStudentsForSubject(_selectedSubject);
    return Column(
      children: [
        AppCard(
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const CircleAvatar(child: Icon(Icons.person_rounded)),
            title: Text(subject["faculty"] ?? "",
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text("Teacher"),
          ),
        ),
        const SizedBox(height: 10),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Students (${students.length})",
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 8),
              ...students.map(
                (name) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.account_circle_rounded),
                  title: Text(name),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSyllabus() {
    final subject = _subjectMeta(_selectedSubject);
    final units = _syllabusBySubject[_selectedSubject] ??
        const <String>[
          "Unit 1: Introduction",
          "Unit 2: Core Concepts",
          "Unit 3: Practical Applications",
          "Unit 4: Advanced Topics",
          "Unit 5: Revision and Assessment",
        ];
    return Column(
      children: [
        AppCard(
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.menu_book_rounded),
            title: Text(
              "${subject["code"]} Syllabus",
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text((subject["name"] ?? "").toString()),
          ),
        ),
        const SizedBox(height: 10),
        ...units.asMap().entries.map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: AppCard(
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 14,
                        child: Text("${entry.key + 1}"),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          entry.value,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final role = auth.role ?? "STUDENT";
    final canUpload = role == "PROFESSOR";
    return ListView(
      padding:
          const EdgeInsets.fromLTRB(14, 10, 14, 18 + kDockScrollBottomInset),
      children: [
        if (_offline && role != "PROFESSOR")
          const Card(
            child: ListTile(
              leading: Icon(Icons.wifi_off_rounded),
              title: Text("Offline mode"),
              subtitle: Text("LearnEd update is unavailable right now."),
            ),
          ),
        if (_offline && role != "PROFESSOR") const SizedBox(height: 10),
        const Text("LearnEd",
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        _buildClassroomHeader(context),
        const SizedBox(height: 10),
        _buildSubjectStrip(),
        const SizedBox(height: 10),
        _buildTabStrip(),
        const SizedBox(height: 10),
        if (_activeTab == "STREAM")
          _buildStream(canUpload)
        else if (_activeTab == "CLASSWORK")
          _buildClasswork(canUpload)
        else if (_activeTab == "ASSIGNMENTS")
          _buildAssignments(canUpload: canUpload, auth: auth)
        else if (_activeTab == "SYLLABUS")
          _buildSyllabus()
        else
          _buildPeople(),
      ],
    );
  }
}
*/

class _LearningTab extends StatefulWidget {
  const _LearningTab();

  @override
  State<_LearningTab> createState() => _LearningTabState();
}

class _LearningTabState extends State<_LearningTab> {
  final ApiService _api = ApiService();
  static const String _recentMeetingsKey = "learning_recent_meetings";
  static const String _roomJoinCountKey = "learning_room_join_count";
  bool _loading = false;
  bool _offline = false;
  List<dynamic> _rooms = [];
  List<dynamic> _lectures = [];
  List<dynamic> _scheduled = [];
  List<Map<String, dynamic>> _recentMeetings = [];
  Map<String, int> _roomJoinCount = {};
  final TextEditingController _roomTitle = TextEditingController();
  final TextEditingController _roomUrl = TextEditingController();
  final TextEditingController _scheduleTitle = TextEditingController();
  final TextEditingController _scheduleWhen = TextEditingController();
  static const List<Map<String, dynamic>> _demoRooms = [
    {"title": "AI ConnectEd Room", "meeting_url": "connected-ai-live-room"},
    {
      "title": "DBMS ConnectEd Room",
      "meeting_url": "connected-dbms-doubt-session"
    },
  ];
  static const List<Map<String, dynamic>> _demoLectures = [
    {
      "title": "Intro to Neural Networks",
      "date": "2026-02-21",
      "status": "ENDED"
    },
    {
      "title": "ER Modelling Masterclass",
      "date": "2026-02-22",
      "status": "ENDED"
    },
    {"title": "API Design Workshop", "date": "2026-02-23", "status": "ACTIVE"},
  ];
  static const List<Map<String, dynamic>> _demoScheduled = [
    {"title": "AI - Regression", "scheduled_at": "2026-02-24 09:30"},
    {"title": "DBMS - Joins", "scheduled_at": "2026-02-24 11:00"},
  ];

  @override
  void initState() {
    super.initState();
    _loadMeetingMeta();
    _load();
  }

  @override
  void dispose() {
    _roomTitle.dispose();
    _roomUrl.dispose();
    _scheduleTitle.dispose();
    _scheduleWhen.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (kUseDemoDataEverywhere) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _offline = false;
        _rooms = _demoRooms;
        _lectures = _demoLectures;
        _scheduled = _demoScheduled;
      });
      return;
    }
    if (!silent) {
      setState(() => _loading = true);
    }
    final roomRes = await _api.listRooms();
    final lectureRes = await _api.sampleLectures();
    final schedRes = await _api.listScheduledLectures();
    final isOffline = !(await _api.isBackendOnlineCached());

    List<dynamic> nextRooms = _rooms;
    List<dynamic> nextLectures = _lectures;
    List<dynamic> nextScheduled = _scheduled;
    if (isOffline) {
      nextRooms = (await _api.readCache("learning_rooms") as List<dynamic>?) ??
          nextRooms;
      nextLectures =
          (await _api.readCache("learning_lectures") as List<dynamic>?) ??
              nextLectures;
      nextScheduled =
          (await _api.readCache("learning_scheduled") as List<dynamic>?) ??
              nextScheduled;
    } else {
      if (roomRes.statusCode >= 200 && roomRes.statusCode < 300) {
        nextRooms = jsonDecode(roomRes.body) as List<dynamic>;
        await _api.saveCache("learning_rooms", nextRooms);
      }
      if (lectureRes.statusCode >= 200 && lectureRes.statusCode < 300) {
        nextLectures = jsonDecode(lectureRes.body) as List<dynamic>;
        await _api.saveCache("learning_lectures", nextLectures);
      }
      if (schedRes.statusCode >= 200 && schedRes.statusCode < 300) {
        nextScheduled = jsonDecode(schedRes.body) as List<dynamic>;
        await _api.saveCache("learning_scheduled", nextScheduled);
      }
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _loading = false;
      _offline = isOffline;
      _rooms = nextRooms;
      _lectures = nextLectures;
      _scheduled = nextScheduled;
    });
    final calendarRows = <_CalendarEntry>[];
    for (final row in nextScheduled) {
      if (row is! Map<String, dynamic>) {
        continue;
      }
      final title = (row["title"] ?? "ConnectEd Lecture").toString();
      final when = TimeFormat.parseToIst(row["scheduled_at"]?.toString()) ??
          _CalendarSync.parseFlexibleDateTime(
              row["scheduled_at"]?.toString() ?? "");
      if (when == null) {
        continue;
      }
      final start = (when.hour * 60) + when.minute;
      calendarRows.add(
        _CalendarEntry(
          id: "connected-scheduled-$title-${row["scheduled_at"]}",
          dayKey:
              "${when.year}-${when.month.toString().padLeft(2, "0")}-${when.day.toString().padLeft(2, "0")}",
          title: "ConnectEd: $title",
          details: "Scheduled lecture",
          type: "TIMETABLE",
          startMinutes: start,
          endMinutes: (start + 60).clamp(0, 1439),
        ),
      );
    }
    await _CalendarSync.upsertBatch(calendarRows);
  }

  Future<void> _createRoom() async {
    final title = _roomTitle.text.trim();
    if (title.isEmpty) {
      return;
    }
    final roomCode = _normalizeRoomCode(_roomUrl.text.trim(), title: title);

    if (kUseDemoDataEverywhere) {
      final room = {"title": title, "meeting_url": roomCode};
      if (!mounted) {
        return;
      }
      setState(() {
        _rooms = [room, ..._rooms];
      });
      _roomTitle.clear();
      _roomUrl.clear();
      await _CalendarSync.upsert(
        id: "connected-room-created-${DateTime.now().microsecondsSinceEpoch}",
        when: TimeFormat.nowIst(),
        title: "ConnectEd Meeting Created",
        details: title,
      );
      await _openMeeting(room, explicitRoomCode: roomCode, isHost: true);
      return;
    }

    final res = await _api.createRoom(title: title, meetingUrl: roomCode);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final created = jsonDecode(res.body) as Map<String, dynamic>;
      _roomTitle.clear();
      _roomUrl.clear();
      await _CalendarSync.upsert(
        id: "connected-room-created-${DateTime.now().microsecondsSinceEpoch}",
        when: TimeFormat.nowIst(),
        title: "ConnectEd Meeting Created",
        details: title,
      );
      await _load();
      if (!mounted) {
        return;
      }
      await _openMeeting({
        "title": (created["title"] ?? title).toString(),
        "meeting_url": (created["meeting_url"] ?? roomCode).toString(),
      },
          explicitRoomCode: roomCodeFromRaw(
              (created["meeting_url"] ?? roomCode).toString(),
              title: title),
          isHost: true);
    } else if (mounted) {
      GlassToast.show(
        context,
        "Unable to create room right now.",
        icon: Icons.error_outline,
      );
    }
  }

  String _normalizeRoomCode(String raw, {required String title}) {
    final input = raw.trim();
    String roomCode;
    if (input.isNotEmpty) {
      roomCode = input.toLowerCase().replaceAll(RegExp(r"[^a-z0-9_-]+"), "-");
    } else {
      roomCode =
          "connected-${title.toLowerCase().replaceAll(RegExp(r"[^a-z0-9]+"), "-")}";
    }
    roomCode = roomCode
        .replaceAll(RegExp(r"-+"), "-")
        .replaceAll(RegExp(r"^-|-$"), "");
    if (roomCode.isEmpty) {
      return "connected-room-${DateTime.now().millisecondsSinceEpoch}";
    }
    return roomCode;
  }

  String roomCodeFromRaw(String raw, {required String title}) {
    final value = raw.trim();
    if (value.startsWith("http://") || value.startsWith("https://")) {
      final uri = Uri.tryParse(value);
      final segment =
          (uri?.pathSegments.isNotEmpty ?? false) ? uri!.pathSegments.last : "";
      return _normalizeRoomCode(segment, title: title);
    }
    return _normalizeRoomCode(value, title: title);
  }

  String _roomKey(Map<String, dynamic> room) {
    final title = (room["title"] ?? "meeting").toString();
    final raw = (room["meeting_url"] ?? "").toString().trim();
    return roomCodeFromRaw(raw, title: title);
  }

  int _estimatedParticipants(Map<String, dynamic> room) {
    final key = _roomKey(room);
    var hash = 0;
    for (final code in key.codeUnits) {
      hash = ((hash * 31) + code) & 0x7fffffff;
    }
    return 6 + (hash % 19);
  }

  Future<void> _loadMeetingMeta() async {
    final prefs = await SharedPreferences.getInstance();
    final recentRaw = prefs.getString(_recentMeetingsKey);
    final countRaw = prefs.getString(_roomJoinCountKey);

    final nextRecent = <Map<String, dynamic>>[];
    if (recentRaw != null && recentRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(recentRaw);
        if (decoded is List) {
          for (final row in decoded) {
            if (row is Map<String, dynamic>) {
              nextRecent.add({
                "title": (row["title"] ?? "Meeting").toString(),
                "meeting_url": (row["meeting_url"] ?? "").toString(),
                "last_joined_at": (row["last_joined_at"] ?? "").toString(),
              });
            }
          }
        }
      } catch (_) {}
    }

    final nextCounts = <String, int>{};
    if (countRaw != null && countRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(countRaw);
        if (decoded is Map<String, dynamic>) {
          decoded.forEach((k, v) {
            nextCounts[k] = (v as num?)?.toInt() ?? 0;
          });
        }
      } catch (_) {}
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _recentMeetings = nextRecent;
      _roomJoinCount = nextCounts;
    });
  }

  Future<void> _saveMeetingMeta() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_recentMeetingsKey, jsonEncode(_recentMeetings));
    await prefs.setString(_roomJoinCountKey, jsonEncode(_roomJoinCount));
  }

  Future<void> _openMeeting(Map<String, dynamic> room,
      {String? explicitRoomCode, bool isHost = false}) async {
    if (!mounted) {
      return;
    }
    final title = (room["title"] ?? "Meeting").toString();
    final roomCode = explicitRoomCode ??
        roomCodeFromRaw((room["meeting_url"] ?? "").toString(), title: title);

    final key = _roomKey({"title": title, "meeting_url": roomCode});
    final updatedRecent = <Map<String, dynamic>>[
      {
        "title": title,
        "meeting_url": roomCode,
        "last_joined_at": DateTime.now().toIso8601String(),
      },
      ..._recentMeetings.where((m) => _roomKey(m) != key),
    ].take(10).toList();
    final updatedCounts = Map<String, int>.from(_roomJoinCount);
    updatedCounts[key] = (updatedCounts[key] ?? 0) + 1;
    setState(() {
      _recentMeetings = updatedRecent;
      _roomJoinCount = updatedCounts;
    });
    await _saveMeetingMeta();
    await _CalendarSync.upsert(
      id: "connected-join-${DateTime.now().microsecondsSinceEpoch}",
      when: TimeFormat.nowIst(),
      title: "ConnectEd Meeting Joined",
      details: title,
    );
    if (!mounted) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _InAppMeetingScreen(
          title: title,
          roomCode: roomCode,
          displayName: context.read<AuthProvider>().name ?? "Participant",
          role: context.read<AuthProvider>().role ?? "",
          isHost: isHost,
        ),
      ),
    );
  }

  Future<void> _schedule() async {
    if (_scheduleTitle.text.trim().isEmpty ||
        _scheduleWhen.text.trim().isEmpty) {
      return;
    }
    final title = _scheduleTitle.text.trim();
    final rawWhen = _scheduleWhen.text.trim();
    final res = await _api.scheduleLecture(
      title: title,
      scheduledAt: rawWhen,
    );
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final when = TimeFormat.parseToIst(rawWhen) ??
          _CalendarSync.parseFlexibleDateTime(rawWhen) ??
          TimeFormat.nowIst();
      await _CalendarSync.upsert(
        id: "connected-scheduled-$title-$rawWhen",
        when: when,
        title: "ConnectEd: $title",
        details: "Scheduled lecture",
        type: "TIMETABLE",
      );
      _scheduleTitle.clear();
      _scheduleWhen.clear();
      await _load();
    }
  }

  String _formatApiTime(String? raw) {
    final parsed = TimeFormat.parseToIst(raw);
    if (parsed == null) {
      return raw ?? "-";
    }
    return TimeFormat.formatDateTime12hIst(parsed);
  }

  String _formatApiDate(String? raw) {
    final parsed = TimeFormat.parseToIst(raw);
    if (parsed == null) {
      return raw ?? "-";
    }
    return "${TimeFormat.formatDate(parsed)} IST";
  }

  @override
  Widget build(BuildContext context) {
    final role = context.watch<AuthProvider>().role ?? "STUDENT";
    return ListView(
      padding:
          const EdgeInsets.fromLTRB(14, 10, 14, 18 + kDockScrollBottomInset),
      children: [
        if (_offline && role != "PROFESSOR")
          const Card(
            child: ListTile(
              leading: Icon(Icons.wifi_off_rounded),
              title: Text("Offline mode"),
              subtitle: Text("ConnectEd resources may be incomplete."),
            ),
          ),
        if (_offline && role != "PROFESSOR") const SizedBox(height: 10),
        const Text("ConnectEd",
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        if (role == "PROFESSOR")
          AppCard(
            child: Column(
              children: [
                TextField(
                    controller: _scheduleTitle,
                    decoration:
                        const InputDecoration(labelText: "Lecture title")),
                const SizedBox(height: 10),
                TextField(
                    controller: _scheduleWhen,
                    decoration: const InputDecoration(
                        labelText: "Schedule (e.g., 2026-02-20 10:00)")),
                const SizedBox(height: 10),
                AppButton(
                    label: "Schedule Lecture",
                    onPressed: _schedule,
                    icon: Icons.schedule_rounded),
                const SizedBox(height: 14),
                TextField(
                    controller: _roomTitle,
                    decoration:
                        const InputDecoration(labelText: "Online room title")),
                const SizedBox(height: 10),
                TextField(
                  controller: _roomUrl,
                  decoration:
                      const InputDecoration(labelText: "Room Code (optional)"),
                ),
                const SizedBox(height: 10),
                AppButton(
                    label: "Create & Start ConnectEd Meeting",
                    onPressed: _createRoom,
                    icon: Icons.video_call_rounded),
              ],
            ),
          ),
        const SizedBox(height: 10),
        Text(
          role == "STUDENT"
              ? "ConnectEd Schedule by Teacher"
              : "Scheduled Lectures",
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        if (_scheduled.isEmpty)
          const EmptyStateWidget(message: "No scheduled lectures yet")
        else
          ..._scheduled.map(
            (s) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AppCard(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(s["title"].toString(),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(
                      "Scheduled: ${_formatApiTime(s["scheduled_at"]?.toString())}"),
                ),
              ),
            ),
          ),
        const SizedBox(height: 8),
        Text(
          role == "STUDENT" ? "ConnectEd Rooms" : "ConnectEd Classrooms",
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        if (_loading)
          const LoadingSkeleton(height: 100)
        else if (_rooms.isEmpty)
          const EmptyStateWidget(message: "No online rooms created yet")
        else
          ..._rooms.map(
            (r) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AppCard(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(r["title"].toString(),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(
                    "Room: ${roomCodeFromRaw((r["meeting_url"] ?? "").toString(), title: (r["title"] ?? "").toString())}\nParticipants: "
                    "${_roomJoinCount[_roomKey({
                              "title": (r["title"] ?? "").toString(),
                              "meeting_url": (r["meeting_url"] ?? "").toString()
                            })] ?? _estimatedParticipants({
                              "title": (r["title"] ?? "").toString(),
                              "meeting_url": (r["meeting_url"] ?? "").toString()
                            })}",
                  ),
                  isThreeLine: true,
                  trailing: TextButton(
                    onPressed: () => _openMeeting({
                      "title": (r["title"] ?? "Meeting").toString(),
                      "meeting_url": (r["meeting_url"] ?? "").toString(),
                    }),
                    child: const Text("Join"),
                  ),
                  onTap: () => _openMeeting({
                    "title": (r["title"] ?? "Meeting").toString(),
                    "meeting_url": (r["meeting_url"] ?? "").toString(),
                  }),
                ),
              ),
            ),
          ),
        if (_recentMeetings.isNotEmpty) ...[
          const SizedBox(height: 8),
          const SectionTitle("Recent ConnectEd Meetings"),
          const SizedBox(height: 8),
          ..._recentMeetings.map(
            (m) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AppCard(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.history_rounded),
                  title: Text((m["title"] ?? "Meeting").toString(),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle:
                      Text(_formatApiTime(m["last_joined_at"]?.toString())),
                  trailing: TextButton(
                    onPressed: () => _openMeeting({
                      "title": (m["title"] ?? "Meeting").toString(),
                      "meeting_url": (m["meeting_url"] ?? "").toString(),
                    }),
                    child: const Text("Rejoin"),
                  ),
                ),
              ),
            ),
          ),
        ],
        if (role != "STUDENT") ...[
          const SizedBox(height: 8),
          const SectionTitle("Sample Lectures (Preview)"),
          const SizedBox(height: 8),
          ..._lectures.map(
            (l) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AppCard(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l["title"].toString(),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(_formatApiDate(l["date"]?.toString())),
                  trailing: StatusBadge(
                      label: l["status"].toString(),
                      color: l["status"] == "ACTIVE"
                          ? Colors.green
                          : Colors.orange),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _InAppMeetingScreen extends StatefulWidget {
  const _InAppMeetingScreen({
    required this.title,
    required this.roomCode,
    required this.displayName,
    required this.role,
    this.isHost = false,
  });

  final String title;
  final String roomCode;
  final String displayName;
  final String role;
  final bool isHost;

  @override
  State<_InAppMeetingScreen> createState() => _InAppMeetingScreenState();
}

class _InAppMeetingScreenState extends State<_InAppMeetingScreen> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final Map<String, RTCVideoRenderer> _remoteRenderers = {};
  final Map<String, MediaStream> _remoteMediaStreams = {};
  final Map<String, RTCPeerConnection> _peerConnections = {};
  final Map<String, List<RTCIceCandidate>> _pendingCandidates = {};
  final Map<String, List<RTCIceCandidate>> _pendingRemoteCandidates = {};
  final Map<String, bool> _remoteDescriptionSet = {};
  final Map<String, _MeetingPeerDebugState> _peerDebug = {};
  final Map<String, int> _localCandidateCount = {};
  final Map<String, int> _remoteCandidateCount = {};
  List<Map<String, dynamic>> _iceServers = [
    {"urls": ["stun:stun.l.google.com:19302"]},
  ];
  MediaStream? _localStream;
  WebSocket? _socket;
  late String _peerId;
  bool _loading = true;
  String? _error;
  bool _audioMuted = false;
  bool _videoOff = false;
  late bool _isHost;
  String? _turnWarning;
  final Map<String, _MeetingParticipant> _participants = {};
  final Map<String, _MeetingParticipant> _waitingParticipants = {};
  bool _isInLobby = false;
  String? _lobbyMessage;
  // Chat
  bool _handRaised = false;
  final List<Map<String, dynamic>> _chatMessages = [];
  final TextEditingController _chatCtrl = TextEditingController();
  bool _chatOpen = false;
  int _unreadChat = 0;
  bool _showDebug = false;

  // Layout
  bool _tileView = true; // true = tile grid, false = spotlight
  String? _pinnedPeerId; // peerId of pinned participant (spotlight)

  // Meeting timer
  DateTime? _meetingStartTime;
  Timer? _timerTick;
  String _elapsedLabel = "0:00";

  // Reactions
  final List<_ReactionBubble> _reactions = [];

  // Speaking indicator (simple RSSI-based approximation)
  final Set<String> _speaking = {};

  @override
  void initState() {
    super.initState();
    _isHost = widget.isHost;
    _peerId = "p${DateTime.now().microsecondsSinceEpoch}";
    _participants[_peerId] = _MeetingParticipant(
      peerId: _peerId,
      name: widget.displayName,
      role: widget.role,
      isHost: _isHost,
      isLocal: true,
    );
    _startTimer();
    _boot();
  }

  Future<void> _boot() async {
    try {
      await _localRenderer.initialize();
      await [Permission.camera, Permission.microphone].request();
      _localStream = await navigator.mediaDevices.getUserMedia({
        "audio": true,
        "video": {
          "facingMode": "user",
        },
      });
      _localRenderer.srcObject = _localStream;
      _iceServers = await ApiService().getIceServers();
      if (!_hasTurnServers(_iceServers)) {
        _turnWarning =
            "TURN not configured. Calls may fail on different networks.";
      }
      await _connectSignaling();
      if (!mounted) {
        return;
      }
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = "Unable to start meeting: $e";
      });
    }
  }

  Future<void> _connectSignaling() async {
    final baseUrl = await ApiService().getBaseUrl();
    final token = await ApiService().getToken();
    if (token == null || token.isEmpty) {
      if (mounted) {
        setState(() => _error = "Login required to join the meeting.");
      }
      return;
    }
    Uri? baseUri = Uri.tryParse(baseUrl);
    if (baseUri == null || baseUri.host.isEmpty) {
      baseUri = Uri.tryParse("https://$baseUrl");
    }
    final isSecure = (baseUri?.scheme ?? "https") == "https";
    final wsScheme = isSecure ? "wss" : "ws";
    final host = baseUri?.host ?? baseUrl;
    final port = (baseUri?.hasPort ?? false) && baseUri!.port != 0
        ? baseUri.port
        : null;
    final uri = Uri(
      scheme: wsScheme,
      host: host,
      port: port,
      path: "/ws/meetings/${widget.roomCode}",
      queryParameters: {
        "peer_id": _peerId,
        "display_name": widget.displayName,
        "role": widget.role,
        "host": _isHost ? "1" : "0",
        "token": token,
      },
    );
    _socket = await WebSocket.connect(uri.toString());
    _socket!.listen(
      _handleSocketMessage,
      onDone: () {
        if (!mounted) {
          return;
        }
        setState(() => _error = _error ?? "Signaling disconnected.");
      },
      onError: (error) {
        if (!mounted) {
          return;
        }
        setState(() => _error = "Signaling error: $error");
      },
    );
    _socket!.add(jsonEncode({"type": "join", "peer_id": _peerId}));
  }

  void _upsertParticipant(_MeetingParticipant p) {
    _participants[p.peerId] = p;
    if (mounted) {
      setState(() {});
    }
  }

  Future<RTCPeerConnection> _ensurePeer(String remotePeerId) async {
    final existing = _peerConnections[remotePeerId];
    if (existing != null) {
      return existing;
    }
    _remoteDescriptionSet[remotePeerId] = false;
    _peerDebug[remotePeerId] ??= _MeetingPeerDebugState();

    final pc = await createPeerConnection(
      {
        "iceServers": _iceServers,
      },
      {
        "mandatory": {},
        "optional": [
          {"DtlsSrtpKeyAgreement": true},
        ],
      },
    );

    final stream = _localStream;
    if (stream != null) {
      for (final track in stream.getTracks()) {
        await pc.addTrack(track, stream);
      }
    }

    pc.onIceCandidate = (candidate) {
      if (candidate.candidate == null) return;
      _localCandidateCount[remotePeerId] =
          (_localCandidateCount[remotePeerId] ?? 0) + 1;
      final hasRemote = _remoteDescriptionSet[remotePeerId] ?? false;
      if (hasRemote) {
        _sendSignal(
          to: remotePeerId,
          data: {
            "candidate": {
              "candidate": candidate.candidate,
              "sdpMid": candidate.sdpMid,
              "sdpMLineIndex": candidate.sdpMLineIndex,
            },
          },
        );
        return;
      }
      _pendingCandidates.putIfAbsent(remotePeerId, () => []).add(candidate);
    };

    pc.onTrack = (event) async {
      final stream = await _resolveRemoteStream(remotePeerId, event);
      if (stream == null) {
        return;
      }
      await _attachRemoteStream(remotePeerId, stream);
    };

    pc.onAddStream = (stream) async {
      await _attachRemoteStream(remotePeerId, stream);
    };

    pc.onIceConnectionState = (state) {
      _peerDebug[remotePeerId]?.iceConnection = state.toString();
      if (mounted) setState(() {});
    };
    pc.onConnectionState = (state) {
      _peerDebug[remotePeerId]?.connection = state.toString();
      if (mounted) setState(() {});
    };
    pc.onSignalingState = (state) {
      _peerDebug[remotePeerId]?.signaling = state.toString();
      if (mounted) setState(() {});
    };
    pc.onIceGatheringState = (state) {
      _peerDebug[remotePeerId]?.gathering = state.toString();
      if (mounted) setState(() {});
    };

    _peerConnections[remotePeerId] = pc;
    return pc;
  }

  Future<void> _createOffer(String remotePeerId) async {
    final pc = await _ensurePeer(remotePeerId);
    final offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    _sendSignal(
      to: remotePeerId,
      data: {
        "sdp": {
          "type": offer.type,
          "sdp": offer.sdp,
        },
      },
    );
  }

  Future<void> _handleSignal(
      String fromPeerId, Map<String, dynamic> data) async {
    final pc = await _ensurePeer(fromPeerId);

    final sdpData = data["sdp"];
    if (sdpData is Map<String, dynamic>) {
      final type = (sdpData["type"] ?? "").toString();
      final sdp = (sdpData["sdp"] ?? "").toString();
      if (type.isNotEmpty && sdp.isNotEmpty) {
        try {
          await pc.setRemoteDescription(RTCSessionDescription(sdp, type));
          _remoteDescriptionSet[fromPeerId] = true;
          _flushCandidates(fromPeerId);
          await _flushRemoteCandidates(fromPeerId, pc);
          if (type == "offer") {
            final answer = await pc.createAnswer();
            await pc.setLocalDescription(answer);
            _sendSignal(
              to: fromPeerId,
              data: {
                "sdp": {
                  "type": answer.type,
                  "sdp": answer.sdp,
                },
              },
            );
          }
        } catch (e) {
          // Glare or invalid state — the other peer's negotiation will succeed.
        }
      }
    }

    final candidateData = data["candidate"];
    if (candidateData is Map<String, dynamic>) {
      final candidate = (candidateData["candidate"] ?? "").toString();
      final sdpMid = candidateData["sdpMid"]?.toString();
      final sdpMLineIndex = (candidateData["sdpMLineIndex"] as num?)?.toInt();
      if (candidate.isNotEmpty) {
        final ice = RTCIceCandidate(candidate, sdpMid, sdpMLineIndex);
        _remoteCandidateCount[fromPeerId] =
            (_remoteCandidateCount[fromPeerId] ?? 0) + 1;
        final hasRemote = _remoteDescriptionSet[fromPeerId] ?? false;
        if (!hasRemote) {
          _pendingRemoteCandidates.putIfAbsent(fromPeerId, () => []).add(ice);
          return;
        }
        await pc.addCandidate(ice);
      }
    }
  }

  void _sendSignal({required String to, required Map<String, dynamic> data}) {
    _socket?.add(
      jsonEncode({
        "type": "signal",
        "from": _peerId,
        "to": to,
        "data": data,
      }),
    );
  }

  void _flushCandidates(String remotePeerId) {
    final candidates = _pendingCandidates.remove(remotePeerId);
    if (candidates == null || candidates.isEmpty) return;
    for (final candidate in candidates) {
      if (candidate.candidate == null) continue;
      _sendSignal(
        to: remotePeerId,
        data: {
          "candidate": {
            "candidate": candidate.candidate,
            "sdpMid": candidate.sdpMid,
            "sdpMLineIndex": candidate.sdpMLineIndex,
          },
        },
      );
    }
  }

  Future<void> _flushRemoteCandidates(
      String remotePeerId, RTCPeerConnection pc) async {
    final candidates = _pendingRemoteCandidates.remove(remotePeerId);
    if (candidates == null || candidates.isEmpty) return;
    for (final candidate in candidates) {
      if (candidate.candidate == null) continue;
      await pc.addCandidate(candidate);
    }
  }

  Future<void> _removePeer(String peerId) async {
    _pendingCandidates.remove(peerId);
    _pendingRemoteCandidates.remove(peerId);
    _remoteDescriptionSet.remove(peerId);
    _peerDebug.remove(peerId);
    _localCandidateCount.remove(peerId);
    _remoteCandidateCount.remove(peerId);
    final pc = _peerConnections.remove(peerId);
    await pc?.close();
    final renderer = _remoteRenderers[peerId];
    final stream = _remoteMediaStreams.remove(peerId);
    if (mounted) {
      setState(() {
        _remoteRenderers.remove(peerId);
      });
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await renderer?.dispose();
        await stream?.dispose();
      });
    } else {
      await renderer?.dispose();
      await stream?.dispose();
      _remoteRenderers.remove(peerId);
    }
  }

  Future<void> _attachRemoteStream(
      String remotePeerId, MediaStream stream) async {
    RTCVideoRenderer renderer =
        _remoteRenderers[remotePeerId] ?? RTCVideoRenderer();
    if (!_remoteRenderers.containsKey(remotePeerId)) {
      await renderer.initialize();
      _remoteRenderers[remotePeerId] = renderer;
    }
    _remoteMediaStreams[remotePeerId] = stream;
    renderer.srcObject = stream;
    if (mounted) {
      setState(() {});
    }
  }

  Future<MediaStream?> _resolveRemoteStream(
      String remotePeerId, RTCTrackEvent event) async {
    if (event.streams.isNotEmpty) {
      return event.streams.first;
    }
    final track = event.track;
    final existing = _remoteMediaStreams[remotePeerId];
    if (existing != null) {
      existing.addTrack(track);
      return existing;
    }
    final stream = await createLocalMediaStream("remote-$remotePeerId");
    stream.addTrack(track);
    _remoteMediaStreams[remotePeerId] = stream;
    return stream;
  }

  void _handleSocketMessage(dynamic raw) {
    try {
      final decoded = jsonDecode(raw.toString());
      if (decoded is! Map<String, dynamic>) {
        return;
      }
      final type = (decoded["type"] ?? "").toString();
      if (type == "lobby_status") {
        final status = (decoded["status"] ?? "").toString();
        final message = (decoded["message"] ?? "").toString();
        if (status == "denied") {
          if (mounted) {
            GlassToast.show(
              context,
              message.isEmpty ? "Professor did not admit you." : message,
              icon: Icons.error_outline,
            );
          }
          Future.delayed(const Duration(milliseconds: 300), () {
            if (mounted) {
              Navigator.of(context).maybePop();
            }
          });
          return;
        }
        if (mounted) {
          setState(() {
            _isInLobby = true;
            _lobbyMessage = message.isEmpty
                ? "Waiting for the professor to admit you."
                : message;
          });
        }
        return;
      }
      if (type == "admitted") {
        if (mounted) {
          setState(() {
            _isInLobby = false;
            _lobbyMessage = null;
          });
          final message = (decoded["message"] ?? "").toString();
          if (message.isNotEmpty) {
            GlassToast.show(context, message, icon: Icons.verified_rounded);
          }
        }
        return;
      }
      if (type == "lobby_snapshot") {
        final peers = (decoded["peers"] as List<dynamic>? ?? const []);
        final nextWaiting = <String, _MeetingParticipant>{};
        for (final peer in peers) {
          if (peer is! Map<String, dynamic>) {
            continue;
          }
          final peerId = (peer["peer_id"] ?? "").toString();
          if (peerId.isEmpty) {
            continue;
          }
          nextWaiting[peerId] = _MeetingParticipant(
            peerId: peerId,
            name: (peer["display_name"] ?? peerId).toString(),
            role: (peer["role"] ?? "").toString(),
            isHost: (peer["is_host"] ?? false) == true,
          );
        }
        if (mounted) {
          setState(() {
            _waitingParticipants
              ..clear()
              ..addAll(nextWaiting);
          });
        }
        return;
      }
      if (type == "peers") {
        final peers = (decoded["peers"] as List<dynamic>? ?? const []);
        if (mounted) {
          setState(() {
            _isInLobby = false;
            _lobbyMessage = null;
          });
        }
        for (final peer in peers) {
          if (peer is Map<String, dynamic>) {
            final peerId = (peer["peer_id"] ?? "").toString();
            if (peerId.isEmpty || peerId == _peerId) {
              continue;
            }
            _upsertParticipant(
              _MeetingParticipant(
                peerId: peerId,
                name: (peer["display_name"] ?? peerId).toString(),
                role: (peer["role"] ?? "").toString(),
                isHost: (peer["is_host"] ?? false) == true,
              ),
            );
            if (_shouldCreateOffer(peerId)) {
              _createOffer(peerId);
            }
          } else {
            final peerId = peer.toString();
            if (peerId.isNotEmpty) {
              _upsertParticipant(
                _MeetingParticipant(
                    peerId: peerId, name: peerId, role: "", isHost: false),
              );
              if (_shouldCreateOffer(peerId)) {
                _createOffer(peerId);
              }
            }
          }
        }
        return;
      }
      if (type == "peer_joined") {
        String peerId = "";
        String name = "";
        String role = "";
        bool isHost = false;
        final peer = decoded["peer"];
        if (peer is Map<String, dynamic>) {
          peerId = (peer["peer_id"] ?? "").toString();
          name = (peer["display_name"] ?? "").toString();
          role = (peer["role"] ?? "").toString();
          isHost = (peer["is_host"] ?? false) == true;
        } else {
          peerId = (decoded["peer_id"] ?? "").toString();
          name = peerId;
        }
        if (peerId.isNotEmpty) {
          _upsertParticipant(
            _MeetingParticipant(
              peerId: peerId,
              name: name.isEmpty ? peerId : name,
              role: role,
              isHost: isHost,
            ),
          );
          _waitingParticipants.remove(peerId);
          // Do NOT create offer here — the newcomer will offer us.
          // Both sides calling _createOffer simultaneously causes glare.
        }
        return;
      }
      if (type == "peer_left") {
        final peerId = (decoded["peer_id"] ?? "").toString();
        if (peerId.isNotEmpty) {
          _participants.remove(peerId);
          _waitingParticipants.remove(peerId);
          _removePeer(peerId);
        }
        return;
      }
      if (type == "control") {
        final action = (decoded["action"] ?? "").toString();
        if (action == "mute_all") {
          _applyRemoteMuteAll();
        } else if (action == "remove_self") {
          _applyRemoteRemove();
        }
        return;
      }
      if (type == "chat") {
        final text = (decoded["text"] ?? "").toString();
        final senderName = (decoded["sender_name"] ?? "").toString();
        final isOwn = decoded["is_own"] == true;
        if (text.isNotEmpty && mounted) {
          setState(() {
            _chatMessages.add({
              "text": text,
              "sender": senderName,
              "is_own": isOwn,
              "ts": (decoded["ts"] ?? "").toString(),
            });
            if (!_chatOpen) _unreadChat += 1;
          });
        }
        return;
      }
      if (type == "hand_raise") {
        final name =
            (decoded["display_name"] ?? decoded["from"] ?? "Someone")
                .toString();
        final raised = decoded["raised"] == true;
        if (raised && mounted) {
          GlassToast.show(context, "$name raised their hand ✋",
              icon: Icons.back_hand_rounded);
        }
        return;
      }
      if (type == "reaction") {
        final emoji = (decoded["emoji"] ?? "").toString();
        final name = (decoded["display_name"] ?? "").toString();
        if (emoji.isNotEmpty && mounted) {
          setState(() {
            _reactions.add(_ReactionBubble(
                emoji: emoji,
                name: name,
                id: DateTime.now().microsecondsSinceEpoch.toString()));
          });
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted) {
              setState(
                  () => _reactions.removeWhere((r) => r.id == _reactions.last.id));
            }
          });
        }
        return;
      }
      if (type == "signal") {
        final from = (decoded["from"] ?? "").toString();
        final data = decoded["data"];
        if (from.isEmpty || data is! Map<String, dynamic>) {
          return;
        }
        _handleSignal(from, data);
      }
    } catch (_) {}
  }

  Future<void> _applyRemoteMuteAll() async {
    final stream = _localStream;
    if (stream == null) {
      return;
    }
    for (final track in stream.getAudioTracks()) {
      track.enabled = false;
    }
    if (!mounted) {
      return;
    }
    setState(() => _audioMuted = true);
    GlassToast.show(context, "Host muted all participants.", icon: Icons.info_outline);
  }

  Future<void> _applyRemoteRemove() async {
    if (!mounted) {
      return;
    }
    GlassToast.show(context, "Removed by host.", icon: Icons.info_outline);
    await Future.delayed(const Duration(milliseconds: 350));
    if (mounted) {
      Navigator.of(context).maybePop();
    }
  }

  bool _shouldCreateOffer(String remotePeerId) {
    // Always let the joining peer create the offer toward existing peers.
    // The server sends existing peers in the 'peers' list and new arrivals
    // in 'peer_joined'. Both paths call _createOffer, so we must not block
    // based on lexicographic order — both sides need negotiation to succeed.
    if (remotePeerId.isEmpty || remotePeerId == _peerId) {
      return false;
    }
    return true;
  }

  void _startTimer() {
    _meetingStartTime = DateTime.now();
    _timerTick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        return;
      }
      final diff = DateTime.now().difference(_meetingStartTime!);
      final h = diff.inHours;
      final m = diff.inMinutes.remainder(60).toString().padLeft(2, "0");
      final s = diff.inSeconds.remainder(60).toString().padLeft(2, "0");
      setState(() => _elapsedLabel = h > 0 ? "$h:$m:$s" : "$m:$s");
    });
  }

  Future<void> _toggleHandRaise() async {
    final next = !_handRaised;
    setState(() => _handRaised = next);
    _socket?.add(jsonEncode({"type": "hand_raise", "raised": next}));
  }

  void _sendChat() {
    final text = _chatCtrl.text.trim();
    if (text.isEmpty) {
      return;
    }
    _socket?.add(jsonEncode(
        {"type": "chat", "text": text, "sender_name": widget.displayName}));
    _chatCtrl.clear();
  }

  void _sendReaction(String emoji) {
    _socket?.add(jsonEncode(
        {"type": "reaction", "emoji": emoji, "display_name": widget.displayName}));
    setState(() {
      _reactions.add(_ReactionBubble(
        emoji: emoji,
        name: "You",
        id: DateTime.now().microsecondsSinceEpoch.toString(),
      ));
    });
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _reactions
            .removeWhere((r) => r.name == "You" && r.emoji == emoji));
      }
    });
  }

  void _pinParticipant(String peerId) {
    setState(() {
      _pinnedPeerId = _pinnedPeerId == peerId ? null : peerId;
      _tileView = _pinnedPeerId == null;
    });
  }

  void _showReactionPicker() {
    const emojis = ["👍", "❤️", "😂", "😮", "👏", "🎉"];
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: emojis
                .map(
                  (e) => GestureDetector(
                    onTap: () {
                      Navigator.pop(ctx);
                      _sendReaction(e);
                    },
                    child: Text(e, style: const TextStyle(fontSize: 36)),
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final remoteList = _remoteRenderers.entries.toList();
    final hasOthers = _participants.values.any((p) => !p.isLocal);

    // Determine which renderers to show in the main grid
    final mainRenderers = _pinnedPeerId != null
        ? remoteList.where((e) => e.key == _pinnedPeerId).toList()
        : remoteList;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // ── Main video area ──────────────────────────────────────────
            Positioned.fill(
              bottom: 80,
              child: _error != null
                  ? Center(
                      child: Text(_error!,
                          style: const TextStyle(color: Colors.white)))
                  : _loading
                      ? const Center(
                          child: CircularProgressIndicator(color: Colors.white))
                      : _isInLobby
                          ? _WaitingView(
                              displayName: widget.displayName,
                              localRenderer: _localRenderer,
                              message: "Waiting for professor approval...",
                              detail: _lobbyMessage ??
                                  "You are in the meeting waiting room.",
                            )
                          : (!hasOthers && mainRenderers.isEmpty && !_isHost)
                          ? _WaitingView(
                              displayName: widget.displayName,
                              localRenderer: _localRenderer,
                              message: "Waiting for others to join...",
                            )
                          : _tileView
                              ? _TileGrid(
                                  renderers: mainRenderers,
                                  participants: _participants,
                                  speaking: _speaking,
                                  onPin: _pinParticipant,
                                  localRenderer: _localRenderer,
                                  localPeerId: _peerId,
                                  localName: widget.displayName,
                                  videoOff: _videoOff,
                                )
                              : _SpotlightView(
                                  pinnedEntry: mainRenderers.isNotEmpty
                                      ? mainRenderers.first
                                      : null,
                                  participants: _participants,
                                  speaking: _speaking,
                                  localRenderer: _localRenderer,
                                  localPeerId: _peerId,
                                  localName: widget.displayName,
                                  videoOff: _videoOff,
                                  onUnpin: () => setState(() {
                                    _pinnedPeerId = null;
                                    _tileView = true;
                                  }),
                                ),
            ),
            if (_turnWarning != null)
              Positioned(
                left: 12,
                right: 12,
                top: 54,
                child: _WarningBanner(text: _turnWarning!),
              ),

            // ── Top bar ──────────────────────────────────────────────────
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.7),
                      Colors.transparent
                    ],
                  ),
                ),
                child: Row(
                  children: [
                    // Meeting title + timer
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 15),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            _elapsedLabel,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        if (!mounted) return;
                        setState(() => _showDebug = !_showDebug);
                      },
                      icon: const Icon(Icons.bug_report_outlined,
                          color: Colors.white),
                      tooltip: "Debug",
                    ),
                    // Layout toggle
                    IconButton(
                      onPressed: () => setState(() {
                        _tileView = !_tileView;
                        _pinnedPeerId = null;
                      }),
                      icon: Icon(
                          _tileView
                              ? Icons.view_agenda_rounded
                              : Icons.grid_view_rounded,
                          color: Colors.white),
                      tooltip: _tileView ? "Spotlight" : "Tile view",
                    ),
                    // Participants
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        IconButton(
                          onPressed: _showParticipantsSheet,
                          icon: const Icon(Icons.people_alt_rounded,
                              color: Colors.white),
                          tooltip: "Participants",
                        ),
                        if (_isHost && _waitingParticipants.isNotEmpty)
                          Positioned(
                            left: -2,
                            top: 2,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.amber.shade700,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _waitingParticipants.length.toString(),
                                style: const TextStyle(
                                    fontSize: 9,
                                    color: Colors.black,
                                    fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                        Positioned(
                          right: 4,
                          top: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: scheme.primary,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _participants.length.toString(),
                              style: const TextStyle(
                                  fontSize: 9,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ],
                    ),
                    // Chat
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        IconButton(
                          onPressed: () => setState(() {
                            _chatOpen = !_chatOpen;
                            if (_chatOpen) _unreadChat = 0;
                          }),
                          icon: const Icon(Icons.chat_bubble_outline_rounded,
                              color: Colors.white),
                          tooltip: "Chat",
                        ),
                        if (_unreadChat > 0)
                          Positioned(
                            right: 4,
                            top: 4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                  color: Colors.red,
                                  borderRadius: BorderRadius.circular(8)),
                              child: Text("$_unreadChat",
                                  style: const TextStyle(
                                      fontSize: 9,
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700)),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (_showDebug)
              _MeetingDebugPanel(
                peerId: _peerId,
                iceServers: _iceServers,
                peerStates: _peerDebug,
                localCandidates: _localCandidateCount,
                remoteCandidates: _remoteCandidateCount,
              ),

            // ── Reaction bubbles ─────────────────────────────────────────
            if (_reactions.isNotEmpty)
              Positioned(
                left: 16,
                bottom: 100,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _reactions
                      .take(5)
                      .map((r) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(r.emoji,
                                      style: const TextStyle(fontSize: 20)),
                                  const SizedBox(width: 6),
                                  Text(r.name,
                                      style: const TextStyle(
                                          color: Colors.white, fontSize: 12)),
                                ],
                              ),
                            ),
                          ))
                      .toList(),
                ),
              ),

            // ── Bottom control bar ───────────────────────────────────────
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.80),
                      Colors.transparent
                    ],
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Mic
                    _ControlButton(
                      icon: _audioMuted
                          ? Icons.mic_off_rounded
                          : Icons.mic_rounded,
                      label: _audioMuted ? "Unmute" : "Mute",
                      active: !_audioMuted,
                      onTap: _error != null ? null : _toggleAudio,
                    ),
                    // Camera
                    _ControlButton(
                      icon: _videoOff
                          ? Icons.videocam_off_rounded
                          : Icons.videocam_rounded,
                      label: _videoOff ? "Start video" : "Stop video",
                      active: !_videoOff,
                      onTap: _error != null ? null : _toggleVideo,
                    ),
                    // Hand raise
                    _ControlButton(
                      icon: Icons.back_hand_rounded,
                      label: _handRaised ? "Lower hand" : "Raise hand",
                      active: _handRaised,
                      activeColor: Colors.amber,
                      onTap: _error != null ? null : _toggleHandRaise,
                    ),
                    // Reactions
                    _ControlButton(
                      icon: Icons.emoji_emotions_rounded,
                      label: "React",
                      active: false,
                      onTap: _showReactionPicker,
                    ),
                    // Leave (red)
                    _ControlButton(
                      icon: Icons.call_end_rounded,
                      label: "Leave",
                      active: true,
                      activeColor: Colors.red,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
            ),

            // ── Chat panel (slides in from right) ────────────────────────
            if (_chatOpen)
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: 300,
                child: Container(
                  color: dark
                      ? Colors.black.withValues(alpha: 0.92)
                      : Colors.white.withValues(alpha: 0.96),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                        child: Row(
                          children: [
                            const Text("In-call messages",
                                style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15)),
                            const Spacer(),
                            IconButton(
                              onPressed: () =>
                                  setState(() => _chatOpen = false),
                              icon: const Icon(Icons.close_rounded),
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: _chatMessages.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.chat_bubble_outline_rounded,
                                        size: 40,
                                        color: scheme.onSurface
                                            .withValues(alpha: 0.3)),
                                    const SizedBox(height: 8),
                                    Text(
                                      "Messages are visible to everyone\nin this call",
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          color: scheme.onSurface
                                              .withValues(alpha: 0.5),
                                          fontSize: 13),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.all(12),
                                reverse: true,
                                itemCount: _chatMessages.length,
                                itemBuilder: (_, i) {
                                  final msg = _chatMessages[
                                      _chatMessages.length - 1 - i];
                                  final isOwn = msg["is_own"] == true;
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: Column(
                                      crossAxisAlignment: isOwn
                                          ? CrossAxisAlignment.end
                                          : CrossAxisAlignment.start,
                                      children: [
                                        if (!isOwn)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                                bottom: 2, left: 4),
                                            child: Text(
                                              msg["sender"]?.toString() ?? "",
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                  color: scheme.primary),
                                            ),
                                          ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 8),
                                          constraints: const BoxConstraints(
                                              maxWidth: 220),
                                          decoration: BoxDecoration(
                                            color: isOwn
                                                ? scheme.primary
                                                : scheme
                                                    .surfaceContainerHighest,
                                            borderRadius: BorderRadius.only(
                                              topLeft: const Radius.circular(16),
                                              topRight:
                                                  const Radius.circular(16),
                                              bottomLeft: Radius.circular(
                                                  isOwn ? 16 : 4),
                                              bottomRight: Radius.circular(
                                                  isOwn ? 4 : 16),
                                            ),
                                          ),
                                          child: Text(
                                            msg["text"]?.toString() ?? "",
                                            style: TextStyle(
                                                fontSize: 14,
                                                color: isOwn
                                                    ? Colors.white
                                                    : null),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                      ),
                      const Divider(height: 1),
                      Padding(
                        padding: EdgeInsets.only(
                          left: 12,
                          right: 8,
                          top: 10,
                          bottom: MediaQuery.of(context).viewInsets.bottom + 10,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _chatCtrl,
                                style: TextStyle(
                                    fontSize: 14, color: scheme.onSurface),
                                decoration: InputDecoration(
                                  hintText: "Send a message...",
                                  hintStyle: TextStyle(
                                      color: scheme.onSurface
                                          .withValues(alpha: 0.4)),
                                  isDense: true,
                                  filled: true,
                                  fillColor: scheme.surfaceContainerHighest
                                      .withValues(alpha: 0.6),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(24),
                                    borderSide: BorderSide.none,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 10),
                                ),
                                onSubmitted: (_) => _sendChat(),
                              ),
                            ),
                            const SizedBox(width: 6),
                            IconButton(
                              onPressed: _sendChat,
                              icon: Icon(Icons.send_rounded,
                                  color: scheme.primary),
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleAudio() async {
    final stream = _localStream;
    if (stream == null) {
      return;
    }
    final nextMuted = !_audioMuted;
    for (final track in stream.getAudioTracks()) {
      track.enabled = !nextMuted;
    }
    if (!mounted) {
      return;
    }
    setState(() => _audioMuted = nextMuted);
  }

  Future<void> _toggleVideo() async {
    final stream = _localStream;
    if (stream == null) {
      return;
    }
    final nextVideoOff = !_videoOff;
    for (final track in stream.getVideoTracks()) {
      track.enabled = !nextVideoOff;
    }
    if (!mounted) {
      return;
    }
    setState(() => _videoOff = nextVideoOff);
  }

  Future<void> _hostMuteAll() async {
    _socket?.add(
      jsonEncode({
        "type": "host_action",
        "action": "mute_all",
      }),
    );
    GlassToast.show(context, "Mute all sent.", icon: Icons.info_outline);
  }

  Future<void> _hostAdmitParticipant(String peerId) async {
    _socket?.add(
      jsonEncode({
        "type": "host_action",
        "action": "admit_peer",
        "target_peer_id": peerId,
      }),
    );
    if (mounted) {
      final name = _waitingParticipants[peerId]?.name ?? "Participant";
      GlassToast.show(context, "Admitting $name...", icon: Icons.verified_rounded);
    }
  }

  Future<void> _hostDenyParticipant(String peerId) async {
    _socket?.add(
      jsonEncode({
        "type": "host_action",
        "action": "deny_peer",
        "target_peer_id": peerId,
      }),
    );
    if (mounted) {
      final name = _waitingParticipants[peerId]?.name ?? "Participant";
      GlassToast.show(context, "Declined $name.", icon: Icons.person_remove_rounded);
    }
  }

  Future<void> _hostRemoveParticipant(String peerId) async {
    _socket?.add(
      jsonEncode({
        "type": "host_action",
        "action": "remove_peer",
        "target_peer_id": peerId,
      }),
    );
    await _removePeer(peerId);
    _participants.remove(peerId);
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _showParticipantsSheet() async {
    final participants = _participants.values.toList()
      ..sort((a, b) {
        if (a.isHost == b.isHost) {
          if (a.isLocal == b.isLocal) {
            return a.name.compareTo(b.name);
          }
          return a.isLocal ? -1 : 1;
        }
        return a.isHost ? -1 : 1;
      });
    final waiting = _waitingParticipants.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final scheme = Theme.of(sheetContext).colorScheme;
        final dark = Theme.of(sheetContext).brightness == Brightness.dark;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Container(
              decoration: BoxDecoration(
                color: Color.alphaBlend(
                  scheme.primary.withValues(alpha: dark ? 0.12 : 0.08),
                  scheme.surface,
                ),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
                border:
                    Border.all(color: scheme.onSurface.withValues(alpha: 0.12)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.people_alt_rounded),
                        const SizedBox(width: 8),
                        Text("Participants (${participants.length})",
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        const Spacer(),
                        if (_isHost)
                          TextButton.icon(
                            onPressed: _hostMuteAll,
                            icon: const Icon(Icons.volume_off_rounded),
                            label: const Text("Mute All"),
                        ),
                      ],
                    ),
                    if (_isHost && waiting.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: scheme.primary.withValues(alpha: 0.16)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Waiting room (${waiting.length})",
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 8),
                            ...waiting.map(
                              (p) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            p.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w600),
                                          ),
                                          if (p.role.isNotEmpty)
                                            Text(
                                              p.role,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: scheme.onSurface
                                                    .withValues(alpha: 0.68),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: () =>
                                          _hostDenyParticipant(p.peerId),
                                      child: const Text("Deny"),
                                    ),
                                    FilledButton.tonal(
                                      onPressed: () =>
                                          _hostAdmitParticipant(p.peerId),
                                      child: const Text("Admit"),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 420),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: participants.length,
                        separatorBuilder: (_, __) => Divider(
                            height: 1,
                            color: scheme.onSurface.withValues(alpha: 0.10)),
                        itemBuilder: (context, index) {
                          final p = participants[index];
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              radius: 15,
                              backgroundColor:
                                  scheme.primary.withValues(alpha: 0.15),
                              child: Icon(Icons.person_rounded,
                                  size: 16, color: scheme.primary),
                            ),
                            title: Text(p.name),
                            subtitle: Text(
                              [
                                if (p.role.isNotEmpty) p.role,
                                if (p.isHost) "Host",
                                if (p.isLocal) "You",
                              ].join(" • "),
                            ),
                            trailing: _isHost && !p.isLocal
                                ? IconButton(
                                    tooltip: "Remove",
                                    onPressed: () =>
                                        _hostRemoveParticipant(p.peerId),
                                    icon: const Icon(
                                        Icons.person_remove_rounded,
                                        color: Colors.redAccent),
                                  )
                                : null,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    for (final pc in _peerConnections.values) {
      pc.close();
    }
    for (final renderer in _remoteRenderers.values) {
      renderer.dispose();
    }
    _remoteRenderers.clear();
    _peerConnections.clear();
    _localStream?.dispose();
    _localRenderer.dispose();
    _socket?.close();
    _chatCtrl.dispose();
    _timerTick?.cancel();
    super.dispose();
  }
}

class _MeetingParticipant {
  const _MeetingParticipant({
    required this.peerId,
    required this.name,
    required this.role,
    required this.isHost,
    this.isLocal = false,
  });

  final String peerId;
  final String name;
  final String role;
  final bool isHost;
  final bool isLocal;
}

// Reaction bubble data
class _ReactionBubble {
  const _ReactionBubble({
    required this.emoji,
    required this.name,
    required this.id,
  });

  final String emoji;
  final String name;
  final String id;
}

// Google Meet style round control button
class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.activeColor,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;
  final Color? activeColor;

  @override
  Widget build(BuildContext context) {
    final bg = activeColor != null && active
        ? activeColor!
        : active
            ? Colors.white.withValues(alpha: 0.18)
            : Colors.white.withValues(alpha: 0.08);
    final fg = activeColor != null && active
        ? Colors.white
        : active
            ? Colors.white
            : Colors.white.withValues(alpha: 0.55);
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
            child: Icon(icon, color: fg, size: 22),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.75), fontSize: 10),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _MeetingPeerDebugState {
  String iceConnection = "unknown";
  String connection = "unknown";
  String signaling = "unknown";
  String gathering = "unknown";
}

class _MeetingDebugPanel extends StatelessWidget {
  const _MeetingDebugPanel({
    required this.peerId,
    required this.iceServers,
    required this.peerStates,
    required this.localCandidates,
    required this.remoteCandidates,
  });

  final String peerId;
  final List<Map<String, dynamic>> iceServers;
  final Map<String, _MeetingPeerDebugState> peerStates;
  final Map<String, int> localCandidates;
  final Map<String, int> remoteCandidates;

  @override
  Widget build(BuildContext context) {
    final entries = peerStates.entries.toList();
    return Positioned(
      left: 12,
      right: 12,
      top: 70,
      child: Card(
        color: Colors.black.withValues(alpha: 0.85),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: DefaultTextStyle(
            style: const TextStyle(color: Colors.white70, fontSize: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("WebRTC Debug",
                    style: TextStyle(
                        fontWeight: FontWeight.w700, color: Colors.white)),
                const SizedBox(height: 6),
                Text("Peer: $peerId"),
                const SizedBox(height: 6),
                Text("ICE Servers: ${iceServers.length}"),
                const SizedBox(height: 6),
                if (entries.isEmpty) const Text("No peers connected"),
                for (final entry in entries) ...[
                  const Divider(color: Colors.white24, height: 12),
                  Text("Peer: ${entry.key}"),
                  Text("ICE: ${entry.value.iceConnection}"),
                  Text("Conn: ${entry.value.connection}"),
                  Text("Signal: ${entry.value.signaling}"),
                  Text("Gather: ${entry.value.gathering}"),
                  Text(
                      "Candidates L/R: ${localCandidates[entry.key] ?? 0}/${remoteCandidates[entry.key] ?? 0}"),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

bool _hasTurnServers(List<Map<String, dynamic>> servers) {
  for (final entry in servers) {
    final urls = entry["urls"];
    if (urls is String) {
      if (urls.startsWith("turn:") || urls.startsWith("turns:")) return true;
    } else if (urls is List) {
      for (final item in urls) {
        final value = item.toString();
        if (value.startsWith("turn:") || value.startsWith("turns:")) {
          return true;
        }
      }
    }
  }
  return false;
}

class _WarningBanner extends StatelessWidget {
  const _WarningBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFE4A200),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 10,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.black),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Waiting screen when no remote peers yet
class _WaitingView extends StatelessWidget {
  const _WaitingView({
    required this.displayName,
    required this.localRenderer,
    required this.message,
    this.detail,
  });

  final String displayName;
  final RTCVideoRenderer localRenderer;
  final String message;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: ClipRRect(
            child: RTCVideoView(
              localRenderer,
              mirror: true,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            ),
          ),
        ),
        Positioned.fill(
          child: Container(color: Colors.black.withValues(alpha: 0.4)),
        ),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 40,
                backgroundColor: Theme.of(context).colorScheme.primary,
                child: Text(
                  displayName.isNotEmpty ? displayName[0].toUpperCase() : "?",
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.w700),
                ),
               ),
               const SizedBox(height: 16),
               Text(
                 message,
                 style: TextStyle(color: Colors.white, fontSize: 16),
               ),
               if (detail != null && detail!.trim().isNotEmpty) ...[
                 const SizedBox(height: 8),
                 SizedBox(
                   width: 240,
                   child: Text(
                     detail!,
                     textAlign: TextAlign.center,
                     style: const TextStyle(
                       color: Colors.white70,
                       fontSize: 13,
                       fontWeight: FontWeight.w500,
                     ),
                   ),
                 ),
               ],
             ],
           ),
         ),
      ],
    );
  }
}

// Tile grid view (Google Meet tiled layout)
class _TileGrid extends StatelessWidget {
  const _TileGrid({
    required this.renderers,
    required this.participants,
    required this.speaking,
    required this.onPin,
    required this.localRenderer,
    required this.localPeerId,
    required this.localName,
    required this.videoOff,
  });

  final List<MapEntry<String, RTCVideoRenderer>> renderers;
  final Map<String, _MeetingParticipant> participants;
  final Set<String> speaking;
  final void Function(String peerId) onPin;
  final RTCVideoRenderer localRenderer;
  final String localPeerId;
  final String localName;
  final bool videoOff;

  @override
  Widget build(BuildContext context) {
    final allTiles = <Widget>[
      // Local tile always first
      _VideoTile(
        renderer: localRenderer,
        name: "$localName (You)",
        isMirrored: true,
        isSpeaking: false,
        videoOff: videoOff,
        onPin: null,
      ),
      // Remote tiles
      ...renderers.map((e) {
        final p = participants[e.key];
        return _VideoTile(
          renderer: e.value,
          name: p?.name ?? e.key,
          isMirrored: false,
          isSpeaking: speaking.contains(e.key),
          videoOff: false,
          onPin: () => onPin(e.key),
          isHost: p?.isHost ?? false,
        );
      }),
    ];

    final count = allTiles.length;
    final crossAxisCount = count <= 1 ? 1 : count <= 4 ? 2 : 3;

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(8, 56, 8, 8),
      itemCount: allTiles.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        childAspectRatio: count == 1 ? 3 / 4 : 4 / 3,
      ),
      itemBuilder: (_, i) => allTiles[i],
    );
  }
}

// Spotlight view — one large + strip of thumbnails
class _SpotlightView extends StatelessWidget {
  const _SpotlightView({
    required this.pinnedEntry,
    required this.participants,
    required this.speaking,
    required this.localRenderer,
    required this.localPeerId,
    required this.localName,
    required this.videoOff,
    required this.onUnpin,
  });

  final MapEntry<String, RTCVideoRenderer>? pinnedEntry;
  final Map<String, _MeetingParticipant> participants;
  final Set<String> speaking;
  final RTCVideoRenderer localRenderer;
  final String localPeerId;
  final String localName;
  final bool videoOff;
  final VoidCallback onUnpin;

  @override
  Widget build(BuildContext context) {
    if (pinnedEntry == null) {
      return const Center(
          child: Text("No participant pinned",
              style: TextStyle(color: Colors.white)));
    }
    final p = participants[pinnedEntry!.key];
    return Column(
      children: [
        Expanded(
          child: _VideoTile(
            renderer: pinnedEntry!.value,
            name: p?.name ?? pinnedEntry!.key,
            isMirrored: false,
            isSpeaking: speaking.contains(pinnedEntry!.key),
            videoOff: false,
            onPin: onUnpin,
            isPinned: true,
            isHost: p?.isHost ?? false,
          ),
        ),
        // Local pip thumbnail
        Container(
          height: 90,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: _VideoTile(
            renderer: localRenderer,
            name: "$localName (You)",
            isMirrored: true,
            isSpeaking: false,
            videoOff: videoOff,
            onPin: null,
          ),
        ),
      ],
    );
  }
}

// Individual video tile with name overlay and speaking ring
class _VideoTile extends StatelessWidget {
  const _VideoTile({
    required this.renderer,
    required this.name,
    required this.isMirrored,
    required this.isSpeaking,
    required this.videoOff,
    required this.onPin,
    this.isHost = false,
    this.isPinned = false,
  });

  final RTCVideoRenderer renderer;
  final String name;
  final bool isMirrored;
  final bool isSpeaking;
  final bool videoOff;
  final VoidCallback? onPin;
  final bool isHost;
  final bool isPinned;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onDoubleTap: onPin,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            // Video or avatar
            Positioned.fill(
              child: videoOff
                  ? Container(
                      color: const Color(0xFF1E1E2A),
                      child: Center(
                        child: CircleAvatar(
                          radius: 28,
                          backgroundColor:
                              scheme.primary.withValues(alpha: 0.3),
                          child: Text(
                            name.isNotEmpty ? name[0].toUpperCase() : "?",
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    )
                  : RTCVideoView(
                      renderer,
                      mirror: isMirrored,
                      objectFit:
                          RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    ),
            ),
            // Speaking ring
            if (isSpeaking)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green, width: 3),
                  ),
                ),
              ),
            // Name overlay bottom
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(8, 16, 8, 6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.7),
                      Colors.transparent
                    ],
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isHost)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text("Host",
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w700)),
                      ),
                    if (isPinned)
                      const Padding(
                        padding: EdgeInsets.only(left: 4),
                        child: Icon(Icons.push_pin_rounded,
                            color: Colors.white, size: 12),
                      ),
                  ],
                ),
              ),
            ),
            // Pin hint on double tap (small icon top right)
            if (onPin != null && !isPinned)
              Positioned(
                top: 6,
                right: 6,
                child: GestureDetector(
                  onTap: onPin,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.push_pin_outlined,
                        color: Colors.white70, size: 14),
                  ),
                ),
              ),
            if (isPinned)
              Positioned(
                top: 6,
                right: 6,
                child: GestureDetector(
                  onTap: onPin,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.push_pin_rounded,
                        color: Colors.amber, size: 14),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LecturesTabState extends State<_LecturesTab> {
  final ApiService _api = ApiService();
  final SmartAttendanceService _smartAttendance = SmartAttendanceService();
  final TextEditingController _classroomController = TextEditingController();
  final TextEditingController _lectureIdController = TextEditingController();

  bool _loading = false;
  bool _offline = false;
  List<dynamic> _active = [];
  Timer? _syncTimer;
  static const List<Map<String, dynamic>> _demoActive = [
    {"id": 901, "classroom_id": 12},
    {"id": 902, "classroom_id": 14},
  ];

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
    _classroomController.dispose();
    _lectureIdController.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (kUseDemoDataEverywhere) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _offline = false;
        _active = _demoActive;
      });
      return;
    }
    if (!silent) {
      setState(() => _loading = true);
    }
    final activeRes = await _api.listActiveLectures();
    final isOffline = !(await _api.isBackendOnlineCached());
    List<dynamic> nextActive = _active;
    if (isOffline) {
      nextActive =
          (await _api.readCache("lectures_active") as List<dynamic>?) ??
              nextActive;
    } else if (activeRes.statusCode >= 200 && activeRes.statusCode < 300) {
      nextActive = jsonDecode(activeRes.body) as List<dynamic>;
      await _api.saveCache("lectures_active", nextActive);
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _loading = false;
      _offline = isOffline;
      _active = nextActive;
    });
  }

  Future<void> _startLecture() async {
    final id = int.tryParse(_classroomController.text.trim());
    if (id == null) return;
    final res = await _api.startLecture(id);
    _show(_detail(res.body, "Lecture start request sent"));
    if (res.statusCode >= 200 && res.statusCode < 300) {
      try {
        final payload = jsonDecode(res.body) as Map<String, dynamic>;
        final lectureId = (payload["id"] as num).toInt();
        final durationMs =
            ((payload["scheduled_duration_ms"] as num?)?.toInt() ?? 60) *
                60 *
                1000;
        try {
          await _smartAttendance.startProfessorSession(
            lectureId: lectureId,
            roomId: id,
            scheduledDurationMs: durationMs,
            minAttendancePercent: 75,
            scheduledStart: payload["scheduled_start"] as int?,
          );
        } catch (_) {
          if (mounted) {
            _show(
              "BLE beacon not started. Enable Bluetooth and allow Advertise permission, then retry.",
            );
          }
          return;
        }
      } catch (_) {
        // Keep lecture start flow alive even if parsing fails.
      }
    }
    await _load();
  }

  Future<void> _endLecture() async {
    final id = int.tryParse(_lectureIdController.text.trim());
    if (id == null) return;
    final res = await _api.endLecture(id);
    _show(_detail(res.body, "Lecture end request sent"));
    if (res.statusCode >= 200 && res.statusCode < 300) {
      await _smartAttendance.endProfessorSession(lectureId: id);
    }
    await _load();
  }

  Future<void> _markPresence(int lectureId) async {
    try {
      final res = await _api.submitCheckpoint(lectureId: lectureId);
      if (!mounted) return;
      _show(_detail(res.body, "Checkpoint submitted"));
    } catch (e) {
      if (!mounted) return;
      _show("Unable to mark presence. Please retry.");
    }
  }

  String _detail(String body, String fallback) {
    try {
      final map = jsonDecode(body) as Map<String, dynamic>;
      return (map["detail"] ?? fallback).toString();
    } catch (_) {
      return fallback;
    }
  }

  void _show(String message) {
    GlassToast.show(context, message, icon: Icons.info_outline);
  }

  @override
  Widget build(BuildContext context) {
    final role = context.watch<AuthProvider>().role ?? "STUDENT";
    return ListView(
      padding:
          const EdgeInsets.fromLTRB(14, 10, 14, 18 + kDockScrollBottomInset),
      children: [
        if (_offline && role != "PROFESSOR")
          const Card(
            child: ListTile(
              leading: Icon(Icons.wifi_off_rounded),
              title: Text("Offline mode"),
              subtitle:
                  Text("Lecture actions may not sync until network returns."),
            ),
          ),
        if (_offline && role != "PROFESSOR") const SizedBox(height: 10),
        const Text("Lectures",
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        if (role == "PROFESSOR")
          AppCard(
            child: Column(
              children: [
                TextField(
                  controller: _classroomController,
                  decoration:
                      const InputDecoration(labelText: "Classroom ID"),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 10),
                AppButton(
                    label: "Start Lecture",
                    onPressed: _startLecture,
                    icon: Icons.play_arrow_rounded),
                const SizedBox(height: 10),
                TextField(
                  controller: _lectureIdController,
                  decoration: const InputDecoration(labelText: "Lecture ID"),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 10),
                AppButton(
                    label: "End Lecture",
                    onPressed: _endLecture,
                    isPrimary: false,
                    icon: Icons.stop_rounded),
              ],
            ),
          ),
        const SizedBox(height: 12),
        if (_loading)
          const LoadingSkeleton(height: 90)
        else if (_active.isEmpty)
          const EmptyStateWidget(message: "No active lectures")
        else
          ..._active.map(
            (lecture) {
              final id = (lecture["id"] as num).toInt();
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: AppCard(
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Lecture #$id",
                                style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            Text("Classroom ${lecture["classroom_id"]}"),
                          ],
                        ),
                      ),
                      if (role == "STUDENT")
                        SizedBox(
                          width: 130,
                          child: AppButton(
                            label: "Mark",
                            onPressed: () => _markPresence(id),
                            icon: Icons.my_location_rounded,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

class _AttendanceTab extends StatefulWidget {
  const _AttendanceTab();

  @override
  State<_AttendanceTab> createState() => _AttendanceTabState();
}

class _AttendanceTabState extends State<_AttendanceTab> {
  final ApiService _api = ApiService();
  bool _loading = false;
  bool _offline = false;
  List<dynamic> _records = [];
  List<dynamic> _lectureHistory = [];
  bool _geofenceEnabled = true;
  List<dynamic> _students = [];
  List<dynamic> _nearbyStudents = [];
  List<dynamic> _manualMarks = [];
  Map<int, _StudentAttendanceSummary> _studentSummary = {};
  Map<int, String> _studentNames = {};
  List<Map<String, dynamic>> _classwiseStudents = [];
  final Map<int, double> _editableAttendancePercent = {};
  String _historyFilter = "Daily";
  String _classFilter = "All Classes";
  int _monthlyPresent = 0;
  int _monthlyAbsent = 0;
  double _monthlyPercentage = 0;
  int? _selectedStudentId;
  final TextEditingController _ceilingHeightController = TextEditingController();
  final TextEditingController _bleRssiController = TextEditingController();
  bool _bleRssiAuto = true;
  List<Map<String, dynamic>> _createdSpaces = [];
  final TextEditingController _spaceNameController = TextEditingController();
  final TextEditingController _spaceThresholdController =
      TextEditingController(text: "75");
  final TextEditingController _thresholdLectureIdController =
      TextEditingController();
  final TextEditingController _manualLectureId =
      TextEditingController(text: "1");
  Timer? _syncTimer;
  static const List<Map<String, dynamic>> _exampleAttendanceRecords = [
    {"lecture_id": 401, "presence_duration": 3150, "status": "PRESENT"},
    {"lecture_id": 402, "presence_duration": 2920, "status": "PRESENT"},
    {"lecture_id": 403, "presence_duration": 0, "status": "ABSENT"},
    {"lecture_id": 404, "presence_duration": 3010, "status": "PRESENT"},
    {"lecture_id": 405, "presence_duration": 0, "status": "ABSENT"},
    {"lecture_id": 406, "presence_duration": 2880, "status": "PRESENT"},
  ];

  static const List<Map<String, dynamic>> _exampleManualMarks = [
    {"student_name": "Aarav Patil", "lecture_id": 401, "status": "PRESENT"},
    {"student_name": "Diya Shinde", "lecture_id": 401, "status": "ABSENT"},
    {"student_name": "Rohan Kale", "lecture_id": 402, "status": "PRESENT"},
  ];
  static const List<Map<String, dynamic>> _exampleLectureHistory = [
    {
      "id": 901,
      "title": "CT",
      "classroom_id": 12,
      "status": "ENDED",
      "end_time": "2026-02-24T09:10:00Z",
    },
    {
      "id": 894,
      "title": "DBMS",
      "classroom_id": 12,
      "status": "ENDED",
      "end_time": "2026-02-23T11:02:00Z",
    },
    {
      "id": 889,
      "title": "DSM",
      "classroom_id": 16,
      "status": "ENDED",
      "end_time": "2026-02-20T13:49:00Z",
    },
  ];
  static const List<Map<String, dynamic>> _demoStudents = [
    {"id": 101, "name": "Aarav Patil", "class_name": "AIDS-A"},
    {"id": 102, "name": "Diya Shinde", "class_name": "AIDS-A"},
    {"id": 103, "name": "Rohan Kale", "class_name": "AIDS-B"},
    {"id": 104, "name": "Meera Joshi", "class_name": "AIDS-B"},
  ];
  static const List<Map<String, dynamic>> _demoNearby = [
    {
      "student_name": "Aarav Patil",
      "student_id": 101,
      "device_id": "DEV-A1",
      "sim_serial": "SIM-A1",
      "lecture_id": 401,
    },
    {
      "student_name": "Diya Shinde",
      "student_id": 102,
      "device_id": "DEV-D2",
      "sim_serial": "SIM-D2",
      "lecture_id": 401,
    },
  ];
  static const List<Map<String, dynamic>> _demoClasswiseAttendance = [
    {
      "id": 101,
      "name": "Aarav Patil",
      "class_name": "AIDS-A",
      "attendance": 87.5
    },
    {
      "id": 102,
      "name": "Diya Shinde",
      "class_name": "AIDS-A",
      "attendance": 74.0
    },
    {
      "id": 103,
      "name": "Rohan Kale",
      "class_name": "AIDS-B",
      "attendance": 92.0
    },
    {
      "id": 104,
      "name": "Meera Joshi",
      "class_name": "AIDS-B",
      "attendance": 69.5
    },
  ];

  @override
  void dispose() {
    _syncTimer?.cancel();
    _spaceNameController.dispose();
    _ceilingHeightController.dispose();
    _bleRssiController.dispose();
    _spaceThresholdController.dispose();
    _thresholdLectureIdController.dispose();
    _manualLectureId.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadCreatedSpaces();
    _load();
    _syncTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _load(silent: true);
    });
  }

  Future<void> _loadCreatedSpaces() async {
    try {
      final res = await _api.listClassrooms();
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final decoded = jsonDecode(res.body) as List<dynamic>;
        final list = decoded.whereType<Map<String, dynamic>>().toList();
        if (!mounted) return;
        setState(() => _createdSpaces = list);
        return;
      }
    } catch (_) {
      // Fall through to cached data.
    }

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString("professor_created_spaces");
    if (raw == null || raw.isEmpty) {
      return;
    }
    try {
      final list = (jsonDecode(raw) as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .toList();
      if (!mounted) return;
      setState(() => _createdSpaces = list);
    } catch (_) {
      // Ignore malformed cache.
    }
  }

  Future<void> _persistCreatedSpaces() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("professor_created_spaces", jsonEncode(_createdSpaces));
  }

  Future<void> _load({bool silent = false}) async {
    if (kUseDemoDataEverywhere) {
      if (!mounted) {
        return;
      }
      final demoSummary = <int, _StudentAttendanceSummary>{
        101: const _StudentAttendanceSummary(
            totalLectures: 24, presentCount: 21, attendancePercentage: 87.5),
        102: const _StudentAttendanceSummary(
            totalLectures: 24, presentCount: 18, attendancePercentage: 75.0),
        103: const _StudentAttendanceSummary(
            totalLectures: 24, presentCount: 22, attendancePercentage: 91.7),
        104: const _StudentAttendanceSummary(
            totalLectures: 24, presentCount: 17, attendancePercentage: 70.8),
      };
      final demoNames = <int, String>{
        for (final s in _demoStudents)
          (s["id"] as int): (s["name"] ?? "Student").toString(),
      };
      setState(() {
        _loading = false;
        _offline = false;
        _records = _exampleAttendanceRecords;
        _lectureHistory = _exampleLectureHistory;
        _geofenceEnabled = true;
        _students = _demoStudents;
        _selectedStudentId = 101;
        _nearbyStudents = _demoNearby;
        _manualMarks = _exampleManualMarks;
        _studentSummary = demoSummary;
        _studentNames = demoNames;
        _classwiseStudents = _demoClasswiseAttendance
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _editableAttendancePercent
          ..clear()
          ..addEntries(_demoClasswiseAttendance.map((e) {
            final id = e["id"] as int;
            final pct = (e["attendance"] as num).toDouble();
            return MapEntry(id, pct);
          }));
        _monthlyPresent = 21;
        _monthlyAbsent = 5;
        _monthlyPercentage = 80.8;
      });
      return;
    }
    if (!silent) {
      setState(() => _loading = true);
    }
    final role = context.read<AuthProvider>().role ?? "STUDENT";
    final res = await _api.attendanceHistory();
    final geoRes = role == "PROFESSOR" ? await _api.geofenceStatus() : null;
    final studentRes = role == "PROFESSOR" ? await _api.studentsList() : null;
    final nearbyRes = role == "PROFESSOR" ? await _api.nearbyStudents() : null;
    final manualRes =
        role == "PROFESSOR" ? await _api.manualAttendanceList() : null;
    final historyRes = role == "PROFESSOR" ? await _api.lectureHistory() : null;
    final summaryRes =
        role == "PROFESSOR" ? await _api.lectureStudentSummary() : null;
    final monthlyRes = await _api.attendanceMonthlySummary();
    final isOffline = !(await _api.isBackendOnlineCached());

    List<dynamic> nextRecords = _records;
    bool nextGeofenceEnabled = _geofenceEnabled;
    List<dynamic> nextStudents = _students;
    List<dynamic> nextNearbyStudents = _nearbyStudents;
    List<dynamic> nextManualMarks = _manualMarks;
    List<dynamic> nextLectureHistory = _lectureHistory;
    Map<int, _StudentAttendanceSummary> nextSummary = _studentSummary;
    Map<int, String> nextStudentNames = _studentNames;
    List<Map<String, dynamic>> nextClasswiseStudents = _classwiseStudents;
    int nextMonthlyPresent = _monthlyPresent;
    int nextMonthlyAbsent = _monthlyAbsent;
    double nextMonthlyPercentage = _monthlyPercentage;

    if (isOffline) {
      nextRecords =
          (await _api.readCache("attendance_records") as List<dynamic>?) ??
              nextRecords;
      if (role == "PROFESSOR") {
        final geoCache = await _api.readCache("attendance_geofence")
            as Map<String, dynamic>?;
        nextGeofenceEnabled =
            geoCache?["enabled"] as bool? ?? nextGeofenceEnabled;
        nextStudents =
            (await _api.readCache("attendance_students") as List<dynamic>?) ??
                nextStudents;
        nextNearbyStudents =
            (await _api.readCache("attendance_nearby") as List<dynamic>?) ??
                nextNearbyStudents;
        nextManualMarks = (await _api.readCache("attendance_manual_marks")
                as List<dynamic>?) ??
            nextManualMarks;
        nextLectureHistory = (await _api.readCache("attendance_lecture_history")
                as List<dynamic>?) ??
            nextLectureHistory;
        final rawSummary = await _api.readCache("attendance_student_summary")
            as List<dynamic>?;
        final rawNames =
            await _api.readCache("attendance_student_names") as List<dynamic>?;
        if (rawSummary != null) {
          nextSummary = _parseStudentSummary(rawSummary);
        }
        if (rawNames != null) {
          nextStudentNames = _parseStudentNames(rawNames);
        }
      }
      final monthlyCache =
          await _api.readCache("Attendance_monthly") as Map<String, dynamic>?;
      if (monthlyCache != null) {
        nextMonthlyPresent =
            (monthlyCache["present"] as num?)?.toInt() ?? nextMonthlyPresent;
        nextMonthlyAbsent =
            (monthlyCache["absent"] as num?)?.toInt() ?? nextMonthlyAbsent;
        nextMonthlyPercentage =
            (monthlyCache["percentage"] as num?)?.toDouble() ??
                nextMonthlyPercentage;
      }
    } else {
      if (res.statusCode >= 200 && res.statusCode < 300) {
        nextRecords = jsonDecode(res.body) as List<dynamic>;
        await _api.saveCache("attendance_records", nextRecords);
      }
      if (geoRes != null &&
          geoRes.statusCode >= 200 &&
          geoRes.statusCode < 300) {
        nextGeofenceEnabled = (jsonDecode(geoRes.body)
                as Map<String, dynamic>)["enabled"] as bool? ??
            true;
        await _api
            .saveCache("attendance_geofence", {"enabled": nextGeofenceEnabled});
      }
      if (studentRes != null &&
          studentRes.statusCode >= 200 &&
          studentRes.statusCode < 300) {
        nextStudents = jsonDecode(studentRes.body) as List<dynamic>;
        await _api.saveCache("attendance_students", nextStudents);
      }
      if (nearbyRes != null &&
          nearbyRes.statusCode >= 200 &&
          nearbyRes.statusCode < 300) {
        final data = jsonDecode(nearbyRes.body) as Map<String, dynamic>;
        nextNearbyStudents = (data["students"] as List<dynamic>? ?? []);
        await _api.saveCache("attendance_nearby", nextNearbyStudents);
      }
      if (manualRes != null &&
          manualRes.statusCode >= 200 &&
          manualRes.statusCode < 300) {
        nextManualMarks = jsonDecode(manualRes.body) as List<dynamic>;
        await _api.saveCache("attendance_manual_marks", nextManualMarks);
      }
      if (historyRes != null &&
          historyRes.statusCode >= 200 &&
          historyRes.statusCode < 300) {
        nextLectureHistory = jsonDecode(historyRes.body) as List<dynamic>;
        await _api.saveCache("attendance_lecture_history", nextLectureHistory);
      }
      if (summaryRes != null &&
          summaryRes.statusCode >= 200 &&
          summaryRes.statusCode < 300) {
        final rows = jsonDecode(summaryRes.body) as List<dynamic>;
        nextSummary = _parseStudentSummary(rows);
        await _api.saveCache("attendance_student_summary", rows);
      }
      if (studentRes != null &&
          studentRes.statusCode >= 200 &&
          studentRes.statusCode < 300) {
        final rows = jsonDecode(studentRes.body) as List<dynamic>;
        nextStudentNames = _parseStudentNames(rows);
        await _api.saveCache("attendance_student_names", rows);
        nextClasswiseStudents = _buildClasswiseAttendance(
          rows,
          summaries: nextSummary,
        );
      }
      if (monthlyRes.statusCode >= 200 && monthlyRes.statusCode < 300) {
        final monthly = jsonDecode(monthlyRes.body) as Map<String, dynamic>;
        nextMonthlyPresent = (monthly["present"] as num?)?.toInt() ?? 0;
        nextMonthlyAbsent = (monthly["absent"] as num?)?.toInt() ?? 0;
        nextMonthlyPercentage =
            (monthly["percentage"] as num?)?.toDouble() ?? 0.0;
        await _api.saveCache("Attendance_monthly", {
          "present": nextMonthlyPresent,
          "absent": nextMonthlyAbsent,
          "percentage": nextMonthlyPercentage,
        });
      }
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _loading = false;
      _offline = isOffline;
      _records = nextRecords;
      _geofenceEnabled = nextGeofenceEnabled;
      _students = nextStudents;
      _selectedStudentId ??=
          _students.isNotEmpty ? _students.first["id"] as int : null;
      _nearbyStudents = nextNearbyStudents;
      _manualMarks = nextManualMarks;
      _lectureHistory = nextLectureHistory;
      _studentSummary = nextSummary;
      _studentNames = nextStudentNames;
      _classwiseStudents = nextClasswiseStudents;
      for (final row in _classwiseStudents) {
        final id = row["id"];
        if (id is! int) {
          continue;
        }
        _editableAttendancePercent[id] =
            _editableAttendancePercent[id] ?? _baseAttendancePercent(row);
      }
      _monthlyPresent = nextMonthlyPresent;
      _monthlyAbsent = nextMonthlyAbsent;
      _monthlyPercentage = nextMonthlyPercentage;
    });
  }

  Future<void> _openCreateSpaceDialog() async {
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setDialogState) {
          final height = double.tryParse(_ceilingHeightController.text.trim());
          final hasValidHeight = height != null && height >= 2.0 && height <= 10.0;
          final hasRssi = _bleRssiController.text.trim().isNotEmpty;
          final canSave =
              _spaceNameController.text.trim().isNotEmpty && hasValidHeight && hasRssi;
          return AlertDialog(
            title: const Text("Create Space"),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _spaceNameController,
                    decoration: const InputDecoration(
                      labelText: "Space name",
                      prefixIcon: Icon(Icons.meeting_room_rounded),
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _ceilingHeightController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: "Ceiling height (metres)",
                      hintText: "e.g. 3.0, 3.5, 4.0",
                      prefixIcon: Icon(Icons.height_rounded),
                    ),
                    onChanged: (value) {
                      final parsed = double.tryParse(value.trim());
                      if (parsed == null || parsed < 2.0 || parsed > 10.0) {
                        setDialogState(() {
                          _bleRssiController.text = "";
                          _bleRssiAuto = true;
                        });
                        return;
                      }
                      final rssi = _computeRssiThreshold(parsed);
                      if (rssi == null) {
                        setDialogState(() {
                          _bleRssiController.text = "";
                          _bleRssiAuto = true;
                        });
                        return;
                      }
                      if (_bleRssiAuto) {
                        setDialogState(() {
                          _bleRssiController.text = rssi.round().toString();
                        });
                      }
                      setDialogState(() {});
                    },
                  ),
                  const SizedBox(height: 6),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "Standard classroom ≈ 3.0–3.5m. Lecture hall ≈ 4.5–5.0m.",
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _bleRssiController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: "BLE RSSI Threshold (dBm)",
                      hintText: "Auto-computed — edit only after real-world testing",
                      prefixIcon: Icon(Icons.bluetooth_searching_rounded),
                    ),
                    onChanged: (_) {
                      if (_bleRssiAuto) {
                        setDialogState(() => _bleRssiAuto = false);
                      }
                      setDialogState(() {});
                    },
                  ),
                  const SizedBox(height: 12),
                  AppButton(
                    label: "Create space",
                    icon: Icons.add_location_alt_rounded,
                    onPressed: canSave ? _createSpace : null,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text("Close"),
              ),
            ],
          );
        });
      },
    );
  }

  Map<int, _StudentAttendanceSummary> _parseStudentSummary(List<dynamic> rows) {
    final map = <int, _StudentAttendanceSummary>{};
    for (final row in rows) {
      if (row is! Map<String, dynamic>) {
        continue;
      }
      final id = row["student_id"];
      if (id is! int) {
        continue;
      }
      map[id] = _StudentAttendanceSummary(
        totalLectures: (row["total_lectures"] as num?)?.toInt() ?? 0,
        presentCount: (row["present_count"] as num?)?.toInt() ?? 0,
        attendancePercentage:
            (row["attendance_percentage"] as num?)?.toDouble() ?? 0,
      );
    }
    return map;
  }

  Map<int, String> _parseStudentNames(List<dynamic> rows) {
    final map = <int, String>{};
    for (final row in rows) {
      if (row is! Map<String, dynamic>) {
        continue;
      }
      final id = row["id"];
      if (id is! int) {
        continue;
      }
      map[id] = (row["name"] ?? "Student #$id").toString();
    }
    return map;
  }

  List<Map<String, dynamic>> _buildClasswiseAttendance(
    List<dynamic> rows, {
    required Map<int, _StudentAttendanceSummary> summaries,
  }) {
    final list = <Map<String, dynamic>>[];
    for (final row in rows) {
      if (row is! Map<String, dynamic>) {
        continue;
      }
      final id = row["id"];
      if (id is! int) {
        continue;
      }
      final summary = summaries[id];
      list.add({
        "id": id,
        "name": (row["name"] ?? "Student #$id").toString(),
        "class_name": (row["class_name"] ??
                row["classroom"] ??
                row["division"] ??
                "Class A")
            .toString(),
        "attendance": summary?.attendancePercentage ?? 0.0,
      });
    }
    return list;
  }

  double _baseAttendancePercent(Map<String, dynamic> row) {
    final raw = row["attendance"];
    if (raw is num) {
      return raw.toDouble().clamp(0.0, 100.0);
    }
    final id = row["id"];
    if (id is int) {
      return _studentSummary[id]?.attendancePercentage ?? 0.0;
    }
    return 0.0;
  }

  double _percentForStudent(Map<String, dynamic> row) {
    final id = row["id"];
    if (id is! int) {
      return _baseAttendancePercent(row);
    }
    return _editableAttendancePercent[id] ?? _baseAttendancePercent(row);
  }

  bool _isDefaulter(double percent) => percent < 75.0;

  List<Map<String, dynamic>> _visibleClasswiseStudents() {
    final source = _classwiseStudents.isEmpty
        ? _demoClasswiseAttendance
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : _classwiseStudents;
    if (_classFilter == "All Classes") {
      return source;
    }
    return source
        .where((e) => (e["class_name"] ?? "").toString() == _classFilter)
        .toList();
  }

  List<String> _classOptions() {
    final source = _classwiseStudents.isEmpty
        ? _demoClasswiseAttendance
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : _classwiseStudents;
    final names = source
        .map((e) => (e["class_name"] ?? "").toString())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return ["All Classes", ...names];
  }

  double _avgAttendanceTillDate() {
    final list = _visibleClasswiseStudents();
    if (list.isEmpty) {
      return 0;
    }
    final sum =
        list.fold<double>(0, (acc, row) => acc + _percentForStudent(row));
    return sum / list.length;
  }

  List<dynamic> _filterLectureHistory() {
    final source =
        _lectureHistory.isNotEmpty ? _lectureHistory : _exampleLectureHistory;
    final now = TimeFormat.nowIst();
    return source.where((row) {
      if (row is! Map<String, dynamic>) {
        return false;
      }
      final ended = TimeFormat.parseToIst(row["end_time"]?.toString());
      if (ended == null) {
        return true;
      }
      switch (_historyFilter) {
        case "Daily":
          return ended.year == now.year &&
              ended.month == now.month &&
              ended.day == now.day;
        case "Monthly":
          return ended.year == now.year && ended.month == now.month;
        case "Yearly":
          return ended.year == now.year;
        default:
          return true;
      }
    }).toList();
  }

  int? _lectureId(dynamic lecture) {
    if (lecture is! Map<String, dynamic>) {
      return null;
    }
    final raw = lecture["id"] ?? lecture["lecture_id"];
    if (raw is int) {
      return raw;
    }
    return int.tryParse(raw?.toString() ?? "");
  }

  String _lectureSubjectRoom(Map<String, dynamic> lecture) {
    final subject = (lecture["title"]?.toString().trim().isNotEmpty ?? false)
        ? lecture["title"].toString()
        : "Lecture #${lecture["id"] ?? lecture["lecture_id"] ?? "-"}";
    final room = (lecture["classroom_id"] ?? "-").toString();
    return "$subject - Room $room";
  }

  String _completedDateTimeNoIst(Map<String, dynamic> row) {
    final ended = TimeFormat.parseToIst(row["end_time"]?.toString());
    if (ended == null) {
      return "Ended -";
    }
    const months = [
      "Jan",
      "Feb",
      "Mar",
      "Apr",
      "May",
      "Jun",
      "Jul",
      "Aug",
      "Sep",
      "Oct",
      "Nov",
      "Dec"
    ];
    final day = ended.day.toString().padLeft(2, "0");
    final month = months[ended.month - 1];
    final year = ended.year;
    final mins = (ended.hour * 60) + ended.minute;
    return "Ended $day $month $year ${TimeFormat.formatMinutes12h(mins)}";
  }

  double _historyPercent(Map<String, dynamic> row) {
    final raw =
        row["attendance_percentage"] ?? row["total_Attendance_percentage"];
    if (raw is num) {
      return raw.toDouble().clamp(0.0, 100.0);
    }
    final id = _lectureId(row) ?? 0;
    final seed = 68 + (id % 25);
    return seed.toDouble().clamp(0.0, 100.0);
  }

  List<_PresentStudent> _studentsForLecture(int? lectureId) {
    if (lectureId == null) {
      return const [];
    }
    final seen = <int>{};
    final list = <_PresentStudent>[];
    for (final row in _nearbyStudents) {
      if (row is! Map<String, dynamic>) {
        continue;
      }
      final rowLecture = row["lecture_id"];
      final rowLectureId = rowLecture is int
          ? rowLecture
          : int.tryParse(rowLecture?.toString() ?? "");
      if (rowLectureId != lectureId) {
        continue;
      }
      final sidRaw = row["student_id"];
      final sid =
          sidRaw is int ? sidRaw : int.tryParse(sidRaw?.toString() ?? "");
      if (sid == null || seen.contains(sid)) {
        continue;
      }
      seen.add(sid);
      list.add(
        _PresentStudent(
          id: sid,
          name: (row["student_name"] ?? _studentNames[sid] ?? "Student #$sid")
              .toString(),
          summary: _studentSummary[sid],
        ),
      );
    }
    if (list.isNotEmpty) {
      return list;
    }
    for (final row in _visibleClasswiseStudents().take(8)) {
      final sid = row["id"];
      if (sid is! int || seen.contains(sid)) {
        continue;
      }
      seen.add(sid);
      list.add(
        _PresentStudent(
          id: sid,
          name:
              (row["name"] ?? _studentNames[sid] ?? "Student #$sid").toString(),
          summary: _studentSummary[sid],
        ),
      );
    }
    return list;
  }

  void _toast(String message) {
    GlassToast.show(context, message, icon: Icons.info_outline);
  }

  double? _computeRssiThreshold(double ceilingHeightM) {
    if (ceilingHeightM <= 1.0) return null;
    const txPower = -59.0;
    const n = 3.2;
    const floorSlabPenalty = -25.0;
    final verticalDistance = ceilingHeightM - 1.0;
    final rssiAtCeiling =
        txPower - (10.0 * n * (math.log(verticalDistance) / math.ln10));
    final rssiAboveSlab = rssiAtCeiling + floorSlabPenalty;
    return rssiAboveSlab + 5.0;
  }

  String _extractDetail(String body, String fallback) {
    try {
      final map = jsonDecode(body) as Map<String, dynamic>;
      return (map["detail"] ?? fallback).toString();
    } catch (_) {
      return fallback;
    }
  }

  Future<void> _createSpace() async {
    final name = _spaceNameController.text.trim();
    if (name.isEmpty) {
      _toast("Enter a space name");
      return;
    }
    final ceilingHeight = double.tryParse(_ceilingHeightController.text.trim());
    if (ceilingHeight == null || ceilingHeight < 2.0 || ceilingHeight > 10.0) {
      _toast("Enter ceiling height between 2.0 and 10.0");
      return;
    }
    final rssi = int.tryParse(_bleRssiController.text.trim());
    if (rssi == null) {
      _toast("Enter a BLE RSSI threshold");
      return;
    }
    setState(() => _loading = true);
    final res = await _api.createClassroom(
      name: name,
      latitudeMin: 0,
      latitudeMax: 0,
      longitudeMin: 0,
      longitudeMax: 0,
    );
    if (!mounted) return;
    setState(() => _loading = false);
    final isOk = res.statusCode >= 200 && res.statusCode < 300;
    var feedback = _extractDetail(res.body, isOk ? "Space created" : "Failed to create space");
    int? roomId;
    if (isOk) {
      try {
        final payload = jsonDecode(res.body) as Map<String, dynamic>;
        final id = payload["id"];
        if (id is num) {
          roomId = id.toInt();
        }
      } catch (_) {}
    }
    _toast(feedback);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      setState(() {
        _spaceNameController.clear();
        _ceilingHeightController.clear();
        _bleRssiController.clear();
        _bleRssiAuto = true;
        try {
          final payload = jsonDecode(res.body) as Map<String, dynamic>;
          _createdSpaces = [
            payload,
            ..._createdSpaces,
          ];
        } catch (_) {
          // Ignore parse errors.
        }
      });
      await _persistCreatedSpaces();
      if (roomId != null) {
        final calibrationPayload = {
          "room_id": roomId,
          "name": name,
          "ceiling_height_m": ceilingHeight,
          "ble_rssi_threshold": rssi,
          "ble_rssi_threshold_auto": _bleRssiAuto,
        };
        await _api.setRoomCalibration(
          roomId: roomId,
          payload: calibrationPayload,
        );
      }
    }
  }

  Future<void> _updateLectureThreshold() async {
    final lectureId = int.tryParse(_thresholdLectureIdController.text.trim());
    if (lectureId == null) {
      _toast("Enter a valid lecture ID");
      return;
    }
    final percent = double.tryParse(_spaceThresholdController.text.trim());
    if (percent == null || percent < 0 || percent > 100) {
      _toast("Enter a threshold between 0 and 100");
      return;
    }
    setState(() => _loading = true);
    final res = await _api.updateLectureThreshold(
      lectureId: lectureId,
      requiredPresencePercent: percent,
    );
    if (!mounted) return;
    setState(() => _loading = false);
    _toast(_extractDetail(res.body, res.statusCode >= 200 && res.statusCode < 300
        ? "Threshold updated"
        : "Failed to update threshold"));
  }

  Future<void> _showPresentStudentsSheet(
    BuildContext hostContext, {
    required List<_PresentStudent> students,
    required int? lectureId,
  }) async {
    await showModalBottomSheet<void>(
      context: hostContext,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Builder(
            builder: (context) {
              final scheme = Theme.of(context).colorScheme;
              final dark = Theme.of(context).brightness == Brightness.dark;
              return Container(
                decoration: BoxDecoration(
                  color: Color.alphaBlend(
                    scheme.primary.withValues(alpha: dark ? 0.12 : 0.08),
                    scheme.surface,
                  ),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(24)),
                  border: Border.all(
                    color:
                        scheme.onSurface.withValues(alpha: dark ? 0.16 : 0.10),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.groups_rounded, color: scheme.primary),
                          const SizedBox(width: 8),
                          const Text(
                            "Students Present",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 360),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: students.length,
                          separatorBuilder: (_, __) => Divider(
                            height: 1,
                            color: scheme.onSurface.withValues(alpha: 0.10),
                          ),
                          itemBuilder: (_, index) {
                            final student = students[index];
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(student.name),
                              subtitle: Text("ID: ${student.id}"),
                              trailing: Icon(Icons.chevron_right_rounded,
                                  color: scheme.primary),
                              onTap: () async {
                                Navigator.of(sheetContext).pop();
                                await _showStudentAttendanceSheet(
                                  hostContext,
                                  student: student,
                                  lectureId: lectureId,
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _showStudentAttendanceSheet(
    BuildContext context, {
    required _PresentStudent student,
    required int? lectureId,
  }) async {
    final summary = student.summary;
    int total = summary?.totalLectures ?? 0;
    int present = summary?.presentCount ?? 0;
    double percent = summary?.attendancePercentage ?? 0;
    bool subjectWise = false;

    if (kUseDemoDataEverywhere) {
      total = 24;
      present = student.id % 2 == 0 ? 19 : 22;
      percent = (present / total) * 100.0;
      subjectWise = true;
    } else if (lectureId != null) {
      final res = await _api.lectureStudentSubjectAttendance(
        lectureId: lectureId,
        studentId: student.id,
      );
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final decoded = jsonDecode(res.body);
        if (decoded is Map<String, dynamic>) {
          total = (decoded["total_lectures"] as num?)?.toInt() ?? total;
          present = (decoded["present_count"] as num?)?.toInt() ?? present;
          percent =
              (decoded["attendance_percentage"] as num?)?.toDouble() ?? percent;
          subjectWise = true;
        }
      }
    }

    if (!context.mounted) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(student.name,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text("Subject Context: Lecture #${lectureId ?? "-"}"),
              const SizedBox(height: 6),
              Text("Student ID: ${student.id}"),
              const SizedBox(height: 12),
              if (summary == null && !subjectWise)
                const Text("Attendance summary unavailable for this student.")
              else
                Text(
                  "Total Attendance in this subject: $present/$total (${percent.toStringAsFixed(1)}%)"
                  "${subjectWise ? "" : " (overall fallback)"}",
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final role = context.watch<AuthProvider>().role ?? "STUDENT";
    return ListView(
      padding:
          const EdgeInsets.fromLTRB(14, 10, 14, 18 + kDockScrollBottomInset),
      children: [
          if (_offline && role != "PROFESSOR")
            const Card(
              child: ListTile(
                leading: Icon(Icons.wifi_off_rounded),
                title: Text("Offline mode"),
                subtitle: Text("Showing local Attendance data."),
              ),
            ),
          if (_offline && role != "PROFESSOR") const SizedBox(height: 10),
          const Text("AttendEd",
              style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          if (role == "PROFESSOR") ...[
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(child: SectionTitle("Create Space")),
                      IconButton(
                        onPressed: _openCreateSpaceDialog,
                        icon: const Icon(Icons.add_circle_rounded),
                        tooltip: "Create space",
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text("Enter ceiling height and a BLE RSSI threshold to create a space."),
                  // Space points recording removed — BLE+ceiling height only.
                  if (_createdSpaces.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    const SectionTitle("Created Spaces"),
                    const SizedBox(height: 6),
                    ..._createdSpaces.take(6).map((space) {
                      final id = space["id"]?.toString() ?? "-";
                      final name = space["name"]?.toString() ?? "Unnamed space";
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text("- $name (ID: $id)"),
                      );
                    }),
                  ],
                  const SizedBox(height: 12),
                  const Divider(),
                  const SizedBox(height: 8),
                  const SectionTitle("Update Attendance Threshold"),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _thresholdLectureIdController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: "Lecture ID",
                      prefixIcon: Icon(Icons.numbers_rounded),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _spaceThresholdController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: "Required presence (%)",
                      prefixIcon: Icon(Icons.percent_rounded),
                    ),
                  ),
                  const SizedBox(height: 10),
                  AppButton(
                    label: "Update threshold",
                    icon: Icons.tune_rounded,
                    onPressed: _updateLectureThreshold,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Builder(builder: (context) {
              final classes = _classOptions();
              if (!classes.contains(_classFilter)) {
                _classFilter = "All Classes";
              }
              final visibleStudents = _visibleClasswiseStudents();
              final avg = _avgAttendanceTillDate();
              final history = _filterLectureHistory();
              return Column(
                children: [
                  AppCard(
                    child: Row(
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Theme.of(context)
                                .colorScheme
                                .primary
                                .withValues(alpha: 0.12),
                          ),
                          child: Icon(Icons.analytics_rounded,
                              color: Theme.of(context).colorScheme.primary),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "Avg Attendance till date",
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "${avg.toStringAsFixed(1)}% across ${visibleStudents.length} students",
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SectionTitle("Student List (Classwise)"),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          initialValue: _classFilter,
                          decoration: const InputDecoration(labelText: "Class"),
                          items: classes
                              .map(
                                (c) => DropdownMenuItem<String>(
                                  value: c,
                                  child: Text(c),
                                ),
                              )
                              .toList(),
                          onChanged: (value) => setState(
                              () => _classFilter = value ?? "All Classes"),
                        ),
                        const SizedBox(height: 10),
                        if (visibleStudents.isEmpty)
                          const EmptyStateWidget(
                              message: "No students available")
                        else
                          ...visibleStudents.map((row) {
                            final percent = _percentForStudent(row);
                            final isDefaulter = _isDefaulter(percent);
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest
                                      .withValues(alpha: 0.35),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            "${row["name"]} • ${row["class_name"]}",
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                        Text(
                                          "${percent.toStringAsFixed(1)}%",
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        StatusBadge(
                                          label: isDefaulter
                                              ? "Defaulter"
                                              : "Regular",
                                          color: isDefaulter
                                              ? Colors.red
                                              : Colors.green,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    LinearProgressIndicator(
                                      value: (percent / 100).clamp(0.0, 1.0),
                                      minHeight: 7,
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Expanded(
                                child: SectionTitle("Lecture History")),
                            SizedBox(
                              width: 130,
                              child: DropdownButtonFormField<String>(
                                initialValue: _historyFilter,
                                decoration: const InputDecoration(
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 8),
                                ),
                                items: const ["Daily", "Monthly", "Yearly"]
                                    .map(
                                      (label) => DropdownMenuItem<String>(
                                        value: label,
                                        child: Text(label),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (value) => setState(
                                  () => _historyFilter = value ?? "Daily",
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (_loading)
                          const LoadingSkeleton(height: 110)
                        else if (history.isEmpty)
                          const EmptyStateWidget(
                              message: "No completed lectures")
                        else
                          ...history.map((row) {
                            if (row is! Map<String, dynamic>) {
                              return const SizedBox.shrink();
                            }
                            final percent = _historyPercent(row);
                            final lectureId = _lectureId(row);
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest
                                      .withValues(alpha: 0.35),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            _lectureSubjectRoom(row),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                        Text(
                                          "${percent.toStringAsFixed(1)}%",
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                              _completedDateTimeNoIst(row)),
                                        ),
                                        TextButton(
                                          onPressed: () =>
                                              _showPresentStudentsSheet(
                                            context,
                                            students:
                                                _studentsForLecture(lectureId),
                                            lectureId: lectureId,
                                          ),
                                          child: const Text("View"),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              );
            }),
          ],
          if (role != "PROFESSOR") ...[
            AppCard(
              child: Row(
                children: [
                  SizedBox(
                    width: 86,
                    height: 86,
                    child: _AttendancePieChart(
                      presentFraction: (_monthlyPresent + _monthlyAbsent) == 0
                          ? 0.0
                          : _monthlyPresent / (_monthlyPresent + _monthlyAbsent),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Monthly Attendance",
                            style: TextStyle(
                                fontSize: 17, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text(
                          "${_monthlyPercentage.toStringAsFixed(1)}%  (P: $_monthlyPresent  A: $_monthlyAbsent)",
                          style: TextStyle(
                              color: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.color
                                  ?.withValues(alpha: 0.9)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _LegendDot(color: Colors.green, label: "Present"),
                SizedBox(width: 14),
                _LegendDot(color: Colors.red, label: "Absent"),
              ],
            ),
            const SizedBox(height: 14),
            const SectionTitle("History"),
            const SizedBox(height: 8),
            if (_loading)
              const LoadingSkeleton(height: 110)
            else if (_records.isEmpty)
              const EmptyStateWidget(message: "No records found")
            else
              ..._records.map(
                (record) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: AppCard(
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("Lecture #${record["lecture_id"]}",
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700)),
                              const SizedBox(height: 4),
                              Text("Presence ${record["presence_duration"]}s"),
                            ],
                          ),
                        ),
                        StatusBadge.forAttendance(record["status"].toString()),
                      ],
                    ),
                  ),
                ),
              ),
          ],
      ],
    );
  }
}

class _SettingsTab extends StatefulWidget {
  const _SettingsTab();

  @override
  State<_SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<_SettingsTab> {
  final DeviceBindingService _bindingService = DeviceBindingService();
  final SmartAttendanceService _smartAttendance = SmartAttendanceService();
  String _deviceId = "Loading...";
  String _sim = "Loading...";
  bool _backgroundTracking = false;
  bool _updatingBackgroundTracking = false;
  static const String _bgTrackingPrefKey = "attendance_background_enabled";
  final List<Map<String, dynamic>> _complaints = [
    {
      "id": 1,
      "title": "ID card issue",
      "details": "Name spelling mismatch on card",
      "status": "OPEN",
      "assigned": true,
    },
    {
      "id": 2,
      "title": "Library access",
      "details": "Access not enabled in portal",
      "status": "IN_PROGRESS",
      "assigned": true,
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadDevice();
    _loadAttendancePrefs();
  }

  Future<void> _loadDevice() async {
    final device = await _bindingService.getDeviceId();
    final sim = await _bindingService.getSimSerial();
    if (!mounted) return;
    setState(() {
      _deviceId = device;
      _sim = sim;
    });
  }

  Future<void> _loadAttendancePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_bgTrackingPrefKey) ?? false;
    if (!mounted) return;
    setState(() {
      _backgroundTracking = enabled;
    });
  }

  Future<void> _toggleBackgroundTracking(bool enabled) async {
    setState(() => _updatingBackgroundTracking = true);
    final actualEnabled =
        await _smartAttendance.setBackgroundTrackingEnabled(enabled);
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_bgTrackingPrefKey, actualEnabled);
    setState(() {
      _backgroundTracking = actualEnabled;
      _updatingBackgroundTracking = false;
    });
  }

  Future<void> _raiseComplaint() async {
    final titleController = TextEditingController();
    final detailsController = TextEditingController();
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Raise Complaint",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: titleController,
              decoration: const InputDecoration(labelText: "Title"),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: detailsController,
              maxLines: 3,
              decoration: const InputDecoration(labelText: "Details"),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: AppButton(
                label: "Submit",
                icon: Icons.send_rounded,
                onPressed: () => Navigator.of(context).pop(true),
              ),
            ),
          ],
        ),
      ),
    );
    if (created != true || !mounted) {
      return;
    }
    final title = titleController.text.trim();
    final details = detailsController.text.trim();
    if (title.isEmpty) {
      return;
    }
    final detailsText = details.isEmpty ? "No details" : details;
    setState(() {
      _complaints.insert(0, {
        "id": DateTime.now().millisecondsSinceEpoch,
        "title": title,
        "details": detailsText,
        "status": "OPEN",
        "assigned": false,
      });
    });
    await _CalendarSync.upsert(
      id: "complaint-raised-${DateTime.now().microsecondsSinceEpoch}",
      when: TimeFormat.nowIst(),
      title: "Complaint Raised",
      details: title,
    );
  }

  Future<void> _resolveComplaint(int id) async {
    String title = "Complaint";
    setState(() {
      final index = _complaints.indexWhere((row) => row["id"] == id);
      if (index == -1) {
        return;
      }
      title = (_complaints[index]["title"] ?? "Complaint").toString();
      _complaints[index] = {
        ..._complaints[index],
        "status": "RESOLVED",
      };
    });
    await _CalendarSync.upsert(
      id: "complaint-resolved-$id",
      when: TimeFormat.nowIst(),
      title: "Complaint Resolved",
      details: title,
    );
  }

  Future<void> _copyToken() async {
    final token = await ApiService().getToken();
    if (!mounted) return;
    if (token == null || token.isEmpty) {
      GlassToast.show(context, "No token found", icon: Icons.error_outline);
      return;
    }
    await Clipboard.setData(ClipboardData(text: token));
    if (!mounted) return;
    GlassToast.show(context, "Token copied", icon: Icons.check_circle_outline);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.read<ThemeProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListView(
      padding:
          const EdgeInsets.fromLTRB(16, 10, 16, 20 + kDockScrollBottomInset),
      children: [
        Row(
          children: [
            const Icon(Icons.person_rounded, size: 26),
            const SizedBox(width: 8),
            const Text("Profile",
                style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 12),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _IconSectionTitle(
                icon: Icons.palette_rounded,
                title: "Appearance",
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      isDark ? "Dark Mode" : "Light Mode",
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Switch.adaptive(
                    value: isDark,
                    onChanged: (_) {
                      theme.setMode(
                          isDark ? AppThemeMode.light : AppThemeMode.dark);
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _IconSectionTitle(
                icon: Icons.bluetooth_connected_rounded,
                title: "Attendance",
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      "Background tracking",
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Switch.adaptive(
                    value: _backgroundTracking,
                    onChanged: _updatingBackgroundTracking
                        ? null
                        : (value) => _toggleBackgroundTracking(value),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                _backgroundTracking
                    ? "Keeps scanning while the app is not open (shows a notification)."
                    : "Scans automatically while the app is open.",
                style: TextStyle(
                  color: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.color
                      ?.withValues(alpha: 0.72),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _IconSectionTitle(
                  icon: Icons.person_outline_rounded, title: "Profile"),
              const SizedBox(height: 8),
              Text("Device Binding Status: $_deviceId"),
              const SizedBox(height: 4),
              Text("SIM Status: $_sim"),
              const SizedBox(height: 10),
              AppButton(
                label: "Account Settings",
                onPressed: () {
                  Navigator.of(context)
                      .push(AppTransitions.fadeSlide(const ProfileScreen()));
                },
                icon: Icons.manage_accounts_rounded,
              ),
              const SizedBox(height: 10),
              AppButton(
                label: "Logout",
                isPrimary: false,
                icon: Icons.logout_rounded,
                onPressed: () async {
                  final authProvider = context.read<AuthProvider>();
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text("Logout"),
                      content: const Text("Are you sure you want to logout?"),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text("Cancel")),
                        FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text("Logout")),
                      ],
                    ),
                  );
                  if (confirmed == true) {
                    if (!mounted) {
                      return;
                    }
                    await authProvider.logout();
                  }
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: _IconSectionTitle(
                      icon: Icons.report_gmailerrorred_rounded,
                      title: "Complaints",
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _raiseComplaint,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text("New"),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_complaints.isEmpty)
                const Text("No complaints yet")
              else
                ..._complaints.take(6).map((row) {
                  final status = (row["status"] ?? "OPEN").toString();
                  final isResolved = status == "RESOLVED";
                  final assigned = row["assigned"] == true;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withValues(alpha: 0.35),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  (row["title"] ?? "Complaint").toString(),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700),
                                ),
                              ),
                              StatusBadge(
                                label: status,
                                color: isResolved ? Colors.green : Colors.orange,
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text((row["details"] ?? "").toString()),
                          if (assigned && !isResolved) ...[
                            const SizedBox(height: 6),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: () =>
                                    _resolveComplaint((row["id"] as num).toInt()),
                                child: const Text("Resolve"),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _IconSectionTitle(
                  icon: Icons.info_outline_rounded, title: "System"),
              const SizedBox(height: 8),
              const Text("App Version: 1.0.0+1"),
              const SizedBox(height: 10),
              AppButton(
                label: "Copy Token",
                isPrimary: false,
                icon: Icons.copy_rounded,
                onPressed: _copyToken,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AdminHomeTab extends StatelessWidget {
  const _AdminHomeTab();

  @override
  Widget build(BuildContext context) {
    final tiles = [
      ("Manage Users", Icons.group_rounded),
      ("Classrooms", Icons.apartment_rounded),
      ("Reports", Icons.bar_chart_rounded),
      ("Logs", Icons.description_outlined),
      ("Reset Bindings", Icons.restart_alt_rounded),
    ];
    return ListView(
      padding:
          const EdgeInsets.fromLTRB(16, 10, 16, 20 + kDockScrollBottomInset),
      children: [
        const Text("Admin Dashboard",
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        TextField(
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search_rounded),
            hintText: "Search",
            filled: true,
            fillColor: Theme.of(context).cardColor,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: const [
            Chip(label: Text("All")),
            Chip(label: Text("Users")),
            Chip(label: Text("Logs")),
          ],
        ),
        const SizedBox(height: 10),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: tiles.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.5,
          ),
          itemBuilder: (context, index) {
            final (label, icon) = tiles[index];
            return InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () {
                Navigator.of(context).push(
                    AppTransitions.fadeSlide(const AdminDashboardScreen()));
              },
              child: AppCard(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 26, color: AppColors.lightPrimary),
                    const SizedBox(height: 8),
                    Text(label,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.name,
  });

  final String name;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text.rich(
            TextSpan(
              text: "Good Morning,\n",
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.color
                    ?.withValues(alpha: 0.72),
              ),
              children: [
                TextSpan(
                  text: name,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _IconSectionTitle extends StatelessWidget {
  const _IconSectionTitle({
    required this.icon,
    required this.title,
  });

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
              fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: -0.2),
        ),
      ],
    );
  }
}

class _AttendancePieChart extends StatelessWidget {
  const _AttendancePieChart({
    required this.presentFraction,
  });

  final double presentFraction;

  @override
  Widget build(BuildContext context) {
    final clamped = presentFraction.clamp(0.0, 1.0);
    return CustomPaint(
      painter: _AttendancePiePainter(presentFraction: clamped),
      child: Center(
        child: Text(
          "${(clamped * 100).round()}%",
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _AttendancePiePainter extends CustomPainter {
  _AttendancePiePainter({required this.presentFraction});

  final double presentFraction;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    const start = -math.pi / 2;
    final presentSweep = 2 * math.pi * presentFraction;

    final absentPaint = Paint()..color = Colors.red.withValues(alpha: 0.85);
    final presentPaint = Paint()..color = Colors.green.withValues(alpha: 0.85);

    canvas.drawArc(rect, start, 2 * math.pi, true, absentPaint);
    if (presentSweep > 0) {
      canvas.drawArc(rect, start, presentSweep, true, presentPaint);
    }

    final holePaint = Paint()..color = ThemeData.dark().scaffoldBackgroundColor;
    canvas.drawCircle(center, radius * 0.58, holePaint);
  }

  @override
  bool shouldRepaint(covariant _AttendancePiePainter oldDelegate) {
    return oldDelegate.presentFraction != presentFraction;
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({
    required this.color,
    required this.label,
  });

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label),
      ],
    );
  }
}



