import "package:flutter/material.dart";

import "hello_casts_chat_screen.dart";
import "hello_casts_widgets.dart";
import "hello_casts_bottom_sheets.dart";

class HelloCastsScreen extends StatefulWidget {
  const HelloCastsScreen({super.key});

  @override
  State<HelloCastsScreen> createState() => _HelloCastsScreenState();
}

class _HelloCastsScreenState extends State<HelloCastsScreen> {
  int _tabIndex = 0;
  String _chatFilter = "All";

  static const _tabs = ["Chats", "Communities", "Calls", "Alerts"];
  static const _filters = ["All", "Community", "Group", "Individual"];

  final List<Map<String, dynamic>> _chats = [
    {
      "name": "CSE Community Board",
      "type": "Community",
      "subtitle": "3 new posts • Exam cell notice",
      "time": "09:18",
      "unread": 4,
      "badge": "CAST",
    },
    {
      "name": "DBMS Group Cast",
      "type": "Group",
      "subtitle": "Reminder: Lab at 2:00 PM",
      "time": "08:41",
      "unread": 2,
      "badge": "ALERT",
    },
    {
      "name": "Shreya Kapoor",
      "type": "Individual",
      "subtitle": "I shared the notes deck.",
      "time": "08:20",
      "unread": 0,
    },
    {
      "name": "Hackathon Squad",
      "type": "Group",
      "subtitle": "Voice call scheduled at 6:30 PM",
      "time": "Yesterday",
      "unread": 1,
      "badge": "CALL",
    },
    {
      "name": "Placement Desk",
      "type": "Community",
      "subtitle": "New role: Data Analyst • 4 posts",
      "time": "Yesterday",
      "unread": 0,
    },
    {
      "name": "Rohan Mehta",
      "type": "Individual",
      "subtitle": "Reminder set for tomorrow 9 AM.",
      "time": "Mon",
      "unread": 0,
      "badge": "REMIND",
    },
  ];

  final List<Map<String, dynamic>> _communities = [
    {
      "name": "CSE Community",
      "members": "1.2k members",
      "groups": 6,
      "highlight": "Exam circular shared",
      "tone": "Academic",
    },
    {
      "name": "Innovation Cell",
      "members": "780 members",
      "groups": 4,
      "highlight": "Prototype sprint in 2 days",
      "tone": "Projects",
    },
    {
      "name": "Placement Hub",
      "members": "2.4k members",
      "groups": 8,
      "highlight": "Resume clinic live",
      "tone": "Career",
    },
  ];

  final List<Map<String, dynamic>> _calls = [
    {
      "name": "Hackathon Squad",
      "time": "Today, 6:30 PM",
      "type": "Group Call",
      "status": "Scheduled",
    },
    {
      "name": "Rohan Mehta",
      "time": "Today, 11:20 AM",
      "type": "Voice Call",
      "status": "Missed",
    },
    {
      "name": "DBMS Group Cast",
      "time": "Yesterday, 4:05 PM",
      "type": "Voice Call",
      "status": "Completed",
    },
  ];

  final List<Map<String, dynamic>> _alerts = [
    {
      "title": "Assignment submission",
      "audience": "DBMS Group Cast",
      "mode": "Every 4 hours",
      "next": "Next at 12:00 PM",
      "active": true,
    },
    {
      "title": "Morning attendance",
      "audience": "CSE Community",
      "mode": "At 9:15 AM",
      "next": "Tomorrow",
      "active": true,
    },
    {
      "title": "Team sync",
      "audience": "Hackathon Squad",
      "mode": "Every Monday 6:30 PM",
      "next": "Next Mon",
      "active": false,
    },
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    scheme.brightness == Brightness.dark
                        ? const Color(0xFF0E1524)
                        : const Color(0xFFF0F6FF),
                    scheme.brightness == Brightness.dark
                        ? const Color(0xFF0B1B2E)
                        : const Color(0xFFFDF6EC),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
          ),
          Positioned(
            right: -60,
            top: -40,
            child: HelloCastsGlowOrb(
              size: 200,
              color: scheme.brightness == Brightness.dark
                  ? const Color(0xFF1B6EF3)
                  : const Color(0xFF6BB6FF),
            ),
          ),
          Positioned(
            left: -50,
            bottom: 120,
            child: HelloCastsGlowOrb(
              size: 180,
              color: scheme.brightness == Brightness.dark
                  ? const Color(0xFF23C6B8)
                  : const Color(0xFF9EE7DA),
            ),
          ),
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 20 + 96),
            children: [
              const HelloCastsHeader(
                title: "Hello Casts",
                subtitle: "Community, group, and personal channels in one space.",
              ),
              const SizedBox(height: 12),
              HelloCastsQuickActions(
                onCreateCast: () => _openCreateCast(context),
                onScheduleAlert: () => _openAlertStudio(context),
                onStartCall: () => _openCallStudio(context),
              ),
              const SizedBox(height: 16),
              HelloCastsSegmentedTabs(
                tabs: _tabs,
                index: _tabIndex,
                onChanged: (value) => setState(() => _tabIndex = value),
              ),
              const SizedBox(height: 12),
              if (_tabIndex == 0) ...[
                HelloCastsFilterRow(
                  value: _chatFilter,
                  options: _filters,
                  onChanged: (value) => setState(() => _chatFilter = value),
                ),
                const SizedBox(height: 12),
                ..._filteredChats().map((chat) => HelloCastsChatTile(
                      data: chat,
                      onTap: () => _openChat(context, chat),
                    )),
              ] else if (_tabIndex == 1) ...[
                HelloCastsCommunityHeroCard(
                  onTap: () => _openCreateCommunity(context),
                ),
                const SizedBox(height: 12),
                ..._communities.map(
                  (community) => HelloCastsCommunityTile(data: community),
                ),
              ] else if (_tabIndex == 2) ...[
                HelloCastsCallStudioCard(onTap: () => _openCallStudio(context)),
                const SizedBox(height: 12),
                ..._calls.map((call) => HelloCastsCallTile(data: call)),
              ] else ...[
                HelloCastsAlertStudioCard(onTap: () => _openAlertStudio(context)),
                const SizedBox(height: 12),
                ..._alerts.map((alert) => HelloCastsAlertTile(data: alert)),
              ],
            ],
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _filteredChats() {
    if (_chatFilter == "All") {
      return _chats;
    }
    return _chats.where((row) => row["type"] == _chatFilter).toList();
  }

  void _openChat(BuildContext context, Map<String, dynamic> chat) {
    Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 260),
        reverseTransitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (context, animation, secondaryAnimation) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            ),
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.06, 0.02),
                end: Offset.zero,
              ).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              ),
              child: HelloCastsChatScreen(
                title: chat["name"].toString(),
                castType: chat["type"].toString(),
              ),
            ),
          );
        },
      ),
    );
  }

  void _openCreateCast(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const HelloCastsCreateCastSheet(),
    );
  }

  void _openCreateCommunity(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const HelloCastsCreateCommunitySheet(),
    );
  }

  void _openCallStudio(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const HelloCastsCallStudioSheet(),
    );
  }

  void _openAlertStudio(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const HelloCastsAlertStudioSheet(),
    );
  }
}
