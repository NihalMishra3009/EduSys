# EduSys Tab Navigation Document

## Objective
Create a clear tab section for primary app navigation so users can quickly move between core areas.

## Current Layout
- Tab section location: bottom section of the home shell screen.
- Tabs available:
  - `Home`
  - `Lectures`
  - `Attendance`
  - `Profile`

## Behavior
- Tapping a tab switches the active page immediately.
- Active tab is highlighted with:
  - Blue icon/text color (`#0A84FF`)
  - Light blue background tint (`#1A0A84FF`)
- Inactive tabs use muted gray (`#6B7280`).
- Transition between tabs uses `AnimatedSwitcher` for smooth screen change.

## Role-Based Page Mapping
- For `ADMIN`:
  - Tab 1 opens `AdminDashboardScreen`
  - Tab 2 opens `Lectures`
  - Tab 3 opens `Attendance`
  - Tab 4 opens `Profile`
- For non-admin roles:
  - Tab 1 opens `Home`
  - Tab 2 opens `Lectures`
  - Tab 3 opens `Attendance`
  - Tab 4 opens `Profile`

## Implementation Reference
- Main file:
  - `mobile/lib/screens/common/home_screen.dart`
- Main classes:
  - `AppShell`
  - `_BottomTabSection` (used as top tab section)

## Notes
- This is a custom tab section (not Flutter `TabBar` + `TabBarView`).
- Navigation is controlled by `_index` state in `AppShell`.
