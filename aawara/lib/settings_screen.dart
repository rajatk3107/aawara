import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'privacy_policy_screen.dart';
import 'services/notification_service.dart';
import 'services/step_tracking_service.dart';
import 'workout/database/workout_database.dart';
import 'workout/models/workout_plan_day.dart';
import 'workout/screens/export_screen.dart';
import 'workout/screens/import_screen.dart';
import 'workout/screens/monthly_summary_screen.dart';
import 'workout/screens/step_goal_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _appVersion = '1.0.0';

  String? _photoPath;
  int _photoTs = 0;
  final _nameController = TextEditingController();
  bool _savingName = false;
  bool _savingPhoto = false;

  // Reminders
  List<WorkoutPlanDay> _workoutDays = [];
  Map<int, bool> _reminderEnabled = {};
  Map<int, TimeOfDay> _reminderTimes = {};

  // Step tracking
  bool _stepEnabled = false;
  int _stepGoal = 8000;
  bool _stepNotify = true;
  bool _stepShowHome = true;
  bool _batteryTipShown = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final allDays = await WorkoutDatabase.instance.getWorkoutPlan();
    final workoutDays = allDays.where((d) => !d.isRestDay).toList()
      ..sort((a, b) => a.dayOfWeek.compareTo(b.dayOfWeek));

    final enabled = <int, bool>{};
    final times = <int, TimeOfDay>{};
    for (final d in workoutDays) {
      enabled[d.dayOfWeek] =
          prefs.getBool('reminder_enabled_${d.dayOfWeek}') ?? false;
      times[d.dayOfWeek] = TimeOfDay(
        hour: prefs.getInt('reminder_hour_${d.dayOfWeek}') ?? 8,
        minute: prefs.getInt('reminder_min_${d.dayOfWeek}') ?? 0,
      );
    }

    if (!mounted) return;
    setState(() {
      _photoPath = prefs.getString('profile_photo_path');
      _photoTs = prefs.getInt('profile_photo_ts') ?? 0;
      _nameController.text = prefs.getString('user_name') ?? '';
      _workoutDays = workoutDays;
      _reminderEnabled = enabled;
      _reminderTimes = times;
      _stepEnabled = prefs.getBool('step_tracking_enabled') ?? false;
      _stepGoal = prefs.getInt('step_goal') ?? 8000;
      _stepNotify = prefs.getBool('step_notify_goal') ?? true;
      _stepShowHome = prefs.getBool('step_show_home') ?? true;
      _batteryTipShown = prefs.getBool('battery_tip_shown') ?? false;
    });
  }

  Future<void> _saveName() async {
    final name = _nameController.text.trim();
    setState(() => _savingName = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_name', name);
    if (!mounted) return;
    setState(() => _savingName = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(_snack('Name saved', icon: Icons.check_circle_rounded));
  }

  Future<void> _pickPhoto() async {
    final source = await _photoSourceSheet();
    if (source == null) return;
    setState(() => _savingPhoto = true);
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: source, imageQuality: 90);
      if (picked == null) {
        setState(() => _savingPhoto = false);
        return;
      }
      final cropped = await _cropPhoto(picked.path);
      if (cropped == null) {
        setState(() => _savingPhoto = false);
        return;
      }
      await _savePhoto(cropped);
    } catch (_) {
      setState(() => _savingPhoto = false);
    }
  }

  Future<ImageSource?> _photoSourceSheet() async {
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: const Color(0xFF444466),
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded,
                  color: Color(0xFFFFD700)),
              title: const Text('Take a Photo',
                  style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded,
                  color: Color(0xFFFFD700)),
              title: const Text('Choose from Gallery',
                  style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<String?> _cropPhoto(String sourcePath) async {
    final croppedFile = await ImageCropper().cropImage(
      sourcePath: sourcePath,
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: 90,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Adjust Photo',
          toolbarColor: const Color(0xFF0D0D1A),
          toolbarWidgetColor: const Color(0xFFFFD700),
          backgroundColor: Colors.black,
          activeControlsWidgetColor: const Color(0xFFFFD700),
          cropStyle: CropStyle.circle,
          lockAspectRatio: true,
          hideBottomControls: false,
          showCropGrid: false,
        ),
        IOSUiSettings(
          title: 'Adjust Photo',
          cropStyle: CropStyle.circle,
          aspectRatioLockEnabled: true,
          resetAspectRatioEnabled: false,
        ),
      ],
    );
    return croppedFile?.path;
  }

  Future<void> _savePhoto(String sourcePath) async {
    final dir = await getApplicationDocumentsDirectory();
    final dest = '${dir.path}/profile_photo.jpg';
    final existing = File(dest);
    if (existing.existsSync()) await existing.delete();
    await File(sourcePath).copy(dest);

    final ts = DateTime.now().millisecondsSinceEpoch;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('profile_photo_path', dest);
    await prefs.setInt('profile_photo_ts', ts);

    if (!mounted) return;
    setState(() {
      _photoPath = dest;
      _photoTs = ts;
      _savingPhoto = false;
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(_snack('Photo updated', icon: Icons.check_circle_rounded));
  }

  Future<void> _toggleReminder(WorkoutPlanDay day, bool value) async {
    if (value) {
      final granted = await NotificationService.instance.requestPermission();
      if (!granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(_snack(
            'Notification permission denied',
            icon: Icons.notifications_off_rounded,
          ));
        }
        return;
      }
      final time =
          _reminderTimes[day.dayOfWeek] ?? const TimeOfDay(hour: 8, minute: 0);
      await NotificationService.instance.scheduleWorkoutReminder(
          day.dayOfWeek, time, day.workoutName);
    } else {
      await NotificationService.instance.cancelReminder(day.dayOfWeek);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('reminder_enabled_${day.dayOfWeek}', value);
    if (mounted) setState(() => _reminderEnabled[day.dayOfWeek] = value);
  }

  Future<void> _pickReminderTime(WorkoutPlanDay day) async {
    final current =
        _reminderTimes[day.dayOfWeek] ?? const TimeOfDay(hour: 8, minute: 0);
    final picked =
        await showTimePicker(context: context, initialTime: current);
    if (picked == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('reminder_hour_${day.dayOfWeek}', picked.hour);
    await prefs.setInt('reminder_min_${day.dayOfWeek}', picked.minute);
    if (mounted) setState(() => _reminderTimes[day.dayOfWeek] = picked);
    if (_reminderEnabled[day.dayOfWeek] == true) {
      await NotificationService.instance.scheduleWorkoutReminder(
          day.dayOfWeek, picked, day.workoutName);
    }
  }

  Future<void> _sendFeedback() async {
    await Clipboard.setData(
        const ClipboardData(text: 'rajatky3107@gmail.com'));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        _snack('Email copied — rajatky3107@gmail.com',
            icon: Icons.mail_outline_rounded));
  }

  SnackBar _snack(String msg, {IconData? icon}) {
    return SnackBar(
      content: Row(children: [
        if (icon != null) ...[
          Icon(icon, color: const Color(0xFFFFD700), size: 18),
          const SizedBox(width: 8),
        ],
        Text(msg, style: const TextStyle(color: Colors.white)),
      ]),
      backgroundColor: const Color(0xFF1A1A2E),
      behavior: SnackBarBehavior.floating,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      duration: const Duration(seconds: 2),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D1A),
        foregroundColor: Colors.white,
        title: const Text(
          'Settings',
          style: TextStyle(
              color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        children: [
          // ── Profile ──────────────────────────────────────────────────
          _sectionHeader('Profile'),
          _buildProfileCard(),
          const SizedBox(height: 24),

          // ── Data ─────────────────────────────────────────────────────
          _sectionHeader('Data'),
          _buildCard([
            _tile(
              icon: Icons.upload_rounded,
              iconColor: const Color(0xFF3498DB),
              title: 'Export Data',
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const ExportScreen())),
            ),
            _divider(),
            _tile(
              icon: Icons.download_rounded,
              iconColor: const Color(0xFF2ECC71),
              title: 'Import Data',
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const ImportScreen())),
            ),
            _divider(),
            _tile(
              icon: Icons.calendar_month_rounded,
              iconColor: const Color(0xFFFFD700),
              title: 'Monthly Summary',
              onTap: _viewMonthlySummary,
            ),
          ]),
          const SizedBox(height: 24),

          // ── Reminders ────────────────────────────────────────────────
          _sectionHeader('Reminders'),
          _buildRemindersCard(),
          const SizedBox(height: 24),

          // ── Step Tracking ─────────────────────────────────────────────
          _sectionHeader('Step Tracking'),
          _buildStepTrackingCard(),
          const SizedBox(height: 24),

          // ── App ───────────────────────────────────────────────────────
          _sectionHeader('App'),
          _buildCard([
            _tile(
              icon: Icons.privacy_tip_outlined,
              iconColor: const Color(0xFF9B59B6),
              title: 'Privacy Policy',
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const PrivacyPolicyScreen())),
            ),
            _divider(),
            _tile(
              icon: Icons.info_outline_rounded,
              iconColor: const Color(0xFF555577),
              title: 'App Version',
              trailing: const Text(_appVersion,
                  style: TextStyle(color: Color(0xFF888899), fontSize: 14)),
            ),
            _divider(),
            _tile(
              icon: Icons.mail_outline_rounded,
              iconColor: const Color(0xFFFF6B35),
              title: 'Send Feedback',
              onTap: _sendFeedback,
            ),
          ]),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildStepTrackingCard() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1E1E35)),
      ),
      child: Column(
        children: [
          // Enable toggle
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFD700).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.directions_walk_rounded,
                      color: Color(0xFFFFD700), size: 18),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text('Track steps automatically',
                      style: TextStyle(color: Colors.white, fontSize: 15)),
                ),
                Switch(
                  value: _stepEnabled,
                  onChanged: _toggleStepTracking,
                  activeThumbColor: const Color(0xFFFFD700),
                  activeTrackColor:
                      const Color(0xFFFFD700).withValues(alpha: 0.25),
                  inactiveThumbColor: const Color(0xFF444466),
                  inactiveTrackColor: const Color(0xFF1E1E35),
                ),
              ],
            ),
          ),
          if (_stepEnabled) ...[
            _divider(),
            // Goal row
            ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              leading: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: const Color(0xFF3498DB).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.flag_rounded,
                    color: Color(0xFF3498DB), size: 18),
              ),
              title: const Text('Daily goal',
                  style: TextStyle(color: Colors.white, fontSize: 15)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_fmtSteps(_stepGoal),
                      style: const TextStyle(
                          color: Color(0xFF888899), fontSize: 13)),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _editStepGoal,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFD700).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: const Color(0xFFFFD700).withValues(alpha: 0.3)),
                      ),
                      child: const Text('Edit',
                          style: TextStyle(
                              color: Color(0xFFFFD700),
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ),
            _divider(),
            // Notify toggle
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2ECC71).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.notifications_rounded,
                        color: Color(0xFF2ECC71), size: 18),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text('Notify at goal',
                        style: TextStyle(color: Colors.white, fontSize: 15)),
                  ),
                  Switch(
                    value: _stepNotify,
                    onChanged: (v) async {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool('step_notify_goal', v);
                      if (mounted) setState(() => _stepNotify = v);
                    },
                    activeThumbColor: const Color(0xFFFFD700),
                    activeTrackColor:
                        const Color(0xFFFFD700).withValues(alpha: 0.25),
                    inactiveThumbColor: const Color(0xFF444466),
                    inactiveTrackColor: const Color(0xFF1E1E35),
                  ),
                ],
              ),
            ),
            _divider(),
            // Show on home toggle
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: const Color(0xFF9B59B6).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.home_rounded,
                        color: Color(0xFF9B59B6), size: 18),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text('Show on home screen',
                        style: TextStyle(color: Colors.white, fontSize: 15)),
                  ),
                  Switch(
                    value: _stepShowHome,
                    onChanged: (v) async {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool('step_show_home', v);
                      if (mounted) setState(() => _stepShowHome = v);
                    },
                    activeThumbColor: const Color(0xFFFFD700),
                    activeTrackColor:
                        const Color(0xFFFFD700).withValues(alpha: 0.25),
                    inactiveThumbColor: const Color(0xFF444466),
                    inactiveTrackColor: const Color(0xFF1E1E35),
                  ),
                ],
              ),
            ),
            // Platform-specific rows
            if (Platform.isAndroid) ...[
              _divider(),
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded,
                        color: Color(0xFF555577), size: 16),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'For accurate tracking, exclude Aawara from battery optimization.',
                        style: TextStyle(
                            color: Color(0xFF555577), fontSize: 12),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _openBatterySettings,
                      child: const Text('Open Settings',
                          style: TextStyle(
                              color: Color(0xFFFFD700), fontSize: 12)),
                    ),
                  ],
                ),
              ),
            ],
            if (Platform.isIOS) ...[
              _divider(),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_rounded,
                        color: Color(0xFF2ECC71), size: 16),
                    SizedBox(width: 8),
                    Text('Reading steps from Apple Health',
                        style: TextStyle(
                            color: Color(0xFF555577), fontSize: 12)),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Future<void> _toggleStepTracking(bool value) async {
    if (value) {
      // Navigate to goal setup first, then enable via StepGoalScreen
      final result = await Navigator.push<int>(
        context,
        MaterialPageRoute(
            builder: (_) => const StepGoalScreen(isFirstSetup: true)),
      );
      if (result != null) {
        if (mounted) {
          setState(() {
            _stepEnabled = true;
            _stepGoal = result;
          });
        }
        // Show battery tip on Android (once)
        if (Platform.isAndroid && !_batteryTipShown && mounted) {
          _showBatteryTipDialog();
        }
      }
    } else {
      await StepTrackingService.disable();
      if (mounted) setState(() => _stepEnabled = false);
    }
  }

  Future<void> _editStepGoal() async {
    final result = await Navigator.push<int>(
      context,
      MaterialPageRoute(
          builder: (_) => const StepGoalScreen(isFirstSetup: false)),
    );
    if (result != null && mounted) {
      setState(() => _stepGoal = result);
    }
  }

  Future<void> _openBatterySettings() async {
    await openAppSettings();
  }

  void _showBatteryTipDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('One more step',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        content: const Text(
          'To count steps even when Aawara isn\'t open, please disable battery optimization for Aawara. This keeps the step counter running all day.',
          style: TextStyle(color: Color(0xFF888899), height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Maybe Later',
                style: TextStyle(color: Color(0xFF555577))),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _openBatterySettings();
            },
            child: const Text('Open Settings',
                style: TextStyle(color: Color(0xFFFFD700))),
          ),
        ],
      ),
    );
    // Mark as shown
    SharedPreferences.getInstance()
        .then((p) => p.setBool('battery_tip_shown', true));
    setState(() => _batteryTipShown = true);
  }

  String _fmtSteps(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  Widget _buildProfileCard() {
    final hasPhoto = _photoPath != null && File(_photoPath!).existsSync();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1E1E35)),
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: _savingPhoto ? null : _pickPhoto,
            child: Stack(
              children: [
                _savingPhoto
                    ? Container(
                        width: 80,
                        height: 80,
                        decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFF0D0D1A)),
                        child: const Center(
                          child: CircularProgressIndicator(
                              color: Color(0xFFFFD700), strokeWidth: 2),
                        ),
                      )
                    : hasPhoto
                        ? CircleAvatar(
                            radius: 40,
                            backgroundImage: FileImage(
                                File(_photoPath!),
                                scale: 1.0) as ImageProvider,
                            key: ValueKey(_photoTs),
                          )
                        : Container(
                            width: 80,
                            height: 80,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: [Color(0xFFFFD700), Color(0xFFB8860B)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                            child: const Center(
                              child: Text('A',
                                  style: TextStyle(
                                      color: Colors.black,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 28)),
                            ),
                          ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFD700),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: const Color(0xFF1A1A2E), width: 2),
                    ),
                    child: const Icon(Icons.edit_rounded,
                        color: Colors.black, size: 13),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _nameController,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                  decoration: InputDecoration(
                    hintText: 'Your name',
                    hintStyle: const TextStyle(color: Color(0xFF555577)),
                    filled: true,
                    fillColor: const Color(0xFF0D0D1A),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFF1E1E35)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFF1E1E35)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                          color: Color(0xFFFFD700), width: 1.5),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                  ),
                  onSubmitted: (_) => _saveName(),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: _savingName ? null : _saveName,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFD700),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 13),
                  elevation: 0,
                ),
                child: _savingName
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            color: Colors.black, strokeWidth: 2))
                    : const Text('Save',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRemindersCard() {
    if (_workoutDays.isEmpty) {
      return Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF1E1E35)),
        ),
        child: const Text(
          'Set up a workout plan first to enable reminders.',
          style: TextStyle(color: Color(0xFF888899), fontSize: 14),
        ),
      );
    }

    const dayNames = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final tiles = <Widget>[];
    for (int i = 0; i < _workoutDays.length; i++) {
      final day = _workoutDays[i];
      final enabled = _reminderEnabled[day.dayOfWeek] ?? false;
      final time =
          _reminderTimes[day.dayOfWeek] ?? const TimeOfDay(hour: 8, minute: 0);
      if (i > 0) tiles.add(_divider());
      tiles.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD700).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    dayNames[day.dayOfWeek],
                    style: const TextStyle(
                        color: Color(0xFFFFD700),
                        fontSize: 11,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(day.workoutName,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 14)),
                    if (enabled)
                      GestureDetector(
                        onTap: () => _pickReminderTime(day),
                        child: Text(
                          time.format(context),
                          style: const TextStyle(
                              color: Color(0xFFFFD700), fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),
              Switch(
                value: enabled,
                onChanged: (v) => _toggleReminder(day, v),
                activeThumbColor: const Color(0xFFFFD700),
                activeTrackColor:
                    const Color(0xFFFFD700).withValues(alpha: 0.25),
                inactiveThumbColor: const Color(0xFF444466),
                inactiveTrackColor: const Color(0xFF1E1E35),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1E1E35)),
      ),
      child: Column(children: tiles),
    );
  }

  void _viewMonthlySummary() {
    final now = DateTime.now();
    // Show previous month's summary
    final month = now.month == 1 ? 12 : now.month - 1;
    final year = now.month == 1 ? now.year - 1 : now.year;
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) =>
              MonthlySummaryScreen(year: year, month: month)),
    );
  }

  Widget _sectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          color: Color(0xFF555577),
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1E1E35)),
      ),
      child: Column(children: children),
    );
  }

  Widget _tile({
    required IconData icon,
    required Color iconColor,
    required String title,
    VoidCallback? onTap,
    Widget? trailing,
  }) {
    return ListTile(
      onTap: onTap,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: iconColor, size: 18),
      ),
      title: Text(title,
          style: const TextStyle(color: Colors.white, fontSize: 15)),
      trailing: trailing ??
          (onTap != null
              ? const Icon(Icons.chevron_right_rounded,
                  color: Color(0xFF555577), size: 20)
              : null),
    );
  }

  Widget _divider() => const Divider(
      height: 1, thickness: 1, color: Color(0xFF1E1E35), indent: 66);
}
