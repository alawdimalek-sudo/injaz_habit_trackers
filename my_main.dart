import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.instance.init();
  runApp(const InjazHabitTrackerApp());
}

// ==========================================
// خدمة الإشعارات المحلية (Notification Service)
// ==========================================
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    // تهيئة بيانات المناطق الزمنية
    tz.initializeTimeZones();

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
    );

    await _plugin.initialize(initSettings);

    // طلب صلاحيات الإشعارات والمنبه الدقيق في أندرويد 13+
    final androidImplementation =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidImplementation?.requestNotificationsPermission();
    await androidImplementation?.requestExactAlarmsPermission();
  }

  // إرسال إشعار فوري للتجربة
  Future<void> showInstantTestNotification() async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'injaz_instant_channel',
      'إشعارات إنجاز الفورية',
      channelDescription: 'قناة اختبار الإشعارات الفورية لتطبيق إنجاز',
      importance: Importance.max,
      priority: Priority.high,
    );

    const NotificationDetails details =
        NotificationDetails(android: androidDetails);

    await _plugin.show(
      999999,
      'إنجاز | تنبيه تجريبي 🔔',
      'الإشعارات المحلية تعمل بنجاح على جهازك! استمر في تحقيق أهدافك اليومية.',
      details,
    );
  }

  // جدولة إشعار يومي متكرر لعادة محددة
  Future<void> scheduleDailyHabitReminder(Habit habit) async {
    if (habit.reminderHour == null || habit.reminderMinute == null) return;

    final int notificationId = habit.notificationId;
    final now = DateTime.now();
    var scheduledDate = DateTime(
      now.year,
      now.month,
      now.day,
      habit.reminderHour!,
      habit.reminderMinute!,
    );

    // إذا كان الوقت المحدد قد مضى اليوم، نجدوله لليوم التالي
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    // تحويل الفرق الزمني إلى التوقيت المعتمد في timezone لتفادي مشاكل المنطقة الزمنية
    final Duration offset = scheduledDate.difference(now);
    final tz.TZDateTime tzScheduled = tz.TZDateTime.now(tz.local).add(offset);

    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'injaz_daily_habits_channel',
      'تذكيرات العادات اليومية',
      channelDescription: 'تنبيهات يومية بمواعيد إنجاز العادات والأهداف',
      importance: Importance.max,
      priority: Priority.high,
    );

    const NotificationDetails details =
        NotificationDetails(android: androidDetails);

    await _plugin.zonedSchedule(
      notificationId,
      'حان موعد هدفك اليومي 🎯',
      'تذكير بإنجاز: ${habit.title} (${habit.category})',
      tzScheduled,
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time, // تكرار يومي في نفس الوقت
    );
  }

  // إلغاء تذكير عادة محددة
  Future<void> cancelHabitReminder(int notificationId) async {
    await _plugin.cancel(notificationId);
  }
}

// ==========================================
// نموذج البيانات (Habit Model)
// ==========================================
class Habit {
  String id;
  String title;
  String category;
  int iconCode;
  List<bool> days; // 7 أيام: الأحد (0) إلى السبت (6)
  int? reminderHour;
  int? reminderMinute;

  Habit({
    required this.id,
    required this.title,
    required this.category,
    required this.iconCode,
    required this.days,
    this.reminderHour,
    this.reminderMinute,
  });

  // رقم تعريفي فريد للإشعار مشتق من معرف العادة
  int get notificationId => id.hashCode & 0x7FFFFFFF;

  bool get hasReminder => reminderHour != null && reminderMinute != null;

  int get maxStreak {
    int maxS = 0;
    int currentS = 0;
    for (bool done in days) {
      if (done) {
        currentS++;
        if (currentS > maxS) maxS = currentS;
      } else {
        currentS = 0;
      }
    }
    return maxS;
  }

  int get completedCount => days.where((d) => d).length;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'category': category,
        'iconCode': iconCode,
        'days': days,
        'reminderHour': reminderHour,
        'reminderMinute': reminderMinute,
      };

  factory Habit.fromJson(Map<String, dynamic> json) => Habit(
        id: json['id'],
        title: json['title'],
        category: json['category'],
        iconCode: json['iconCode'],
        days: List<bool>.from(json['days']),
        reminderHour: json['reminderHour'],
        reminderMinute: json['reminderMinute'],
      );
}

// ==========================================
// التطبيق الرئيسي وإدارة الثيم
// ==========================================
class InjazHabitTrackerApp extends StatefulWidget {
  const InjazHabitTrackerApp({super.key});

  @override
  State<InjazHabitTrackerApp> createState() => _InjazHabitTrackerAppState();
}

class _InjazHabitTrackerAppState extends State<InjazHabitTrackerApp> {
  bool _isDarkMode = true;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isDarkMode = prefs.getBool('injaz_dark_mode') ?? true;
    });
  }

  Future<void> _toggleTheme() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isDarkMode = !_isDarkMode;
      prefs.setBool('injaz_dark_mode', _isDarkMode);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'إنجاز - متتبع العادات',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar', 'AE'),
      supportedLocales: const [Locale('ar', 'AE')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      themeMode: _isDarkMode ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorSchemeSeed: const Color(0xFF10B981),
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF10B981),
        scaffoldBackgroundColor: const Color(0xFF0F172A),
      ),
      home: HabitDashboardScreen(
        isDarkMode: _isDarkMode,
        onToggleTheme: _toggleTheme,
      ),
    );
  }
}

// ==========================================
// شاشة لوحة البيانات الرئيسية
// ==========================================
class HabitDashboardScreen extends StatefulWidget {
  final bool isDarkMode;
  final VoidCallback onToggleTheme;

  const HabitDashboardScreen({
    super.key,
    required this.isDarkMode,
    required this.onToggleTheme,
  });

  @override
  State<HabitDashboardScreen> createState() => _HabitDashboardScreenState();
}

class _HabitDashboardScreenState extends State<HabitDashboardScreen> {
  static const String _storageKey = 'injaz_habits_data_v2';
  final List<String> _weekDays = [
    'الأحد',
    'الإثنين',
    'الثلاثاء',
    'الأربعاء',
    'الخميس',
    'الجمعة',
    'السبت'
  ];

  List<Habit> _habits = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHabits();
  }

  List<Habit> _getDefaultHabits() {
    return [
      Habit(
        id: '101',
        title: 'قراءة 20 صفحة علمية',
        category: 'تعلم',
        iconCode: Icons.menu_book_rounded.codePoint,
        days: [true, true, true, false, true, true, false],
        reminderHour: 20,
        reminderMinute: 0,
      ),
      Habit(
        id: '102',
        title: 'ممارسة الرياضة 30 دقيقة',
        category: 'صحة',
        iconCode: Icons.fitness_center_rounded.codePoint,
        days: [true, true, true, true, false, true, true],
        reminderHour: 17,
        reminderMinute: 30,
      ),
      Habit(
        id: '103',
        title: 'ساعة برمجة / بحث علمي',
        category: 'إنتاجية',
        iconCode: Icons.code_rounded.codePoint,
        days: [true, true, true, true, true, false, true],
        reminderHour: 21,
        reminderMinute: 0,
      ),
      Habit(
        id: '104',
        title: 'أذكار الصباح والمساء',
        category: 'روحانيات',
        iconCode: Icons.mosque_rounded.codePoint,
        days: [true, true, true, true, true, true, true],
        reminderHour: 7,
        reminderMinute: 0,
      ),
    ];
  }

  Future<void> _loadHabits() async {
    final prefs = await SharedPreferences.getInstance();
    final String? stored = prefs.getString(_storageKey);
    if (stored != null) {
      final List<dynamic> decoded = jsonDecode(stored);
      setState(() {
        _habits = decoded.map((item) => Habit.fromJson(item)).toList();
        _isLoading = false;
      });
    } else {
      final defaults = _getDefaultHabits();
      setState(() {
        _habits = defaults;
        _isLoading = false;
      });
      await _saveHabits();
      // جدولة التذكيرات الافتراضية
      for (final h in defaults) {
        if (h.hasReminder) {
          await NotificationService.instance.scheduleDailyHabitReminder(h);
        }
      }
    }
  }

  Future<void> _saveHabits() async {
    final prefs = await SharedPreferences.getInstance();
    final String encoded =
        jsonEncode(_habits.map((h) => h.toJson()).toList());
    await prefs.setString(_storageKey, encoded);
  }

  void _toggleDay(int habitIndex, int dayIndex) {
    setState(() {
      _habits[habitIndex].days[dayIndex] = !_habits[habitIndex].days[dayIndex];
    });
    _saveHabits();
  }

  Future<void> _deleteHabit(int index) async {
    final habit = _habits[index];
    await NotificationService.instance
        .cancelHabitReminder(habit.notificationId);
    setState(() {
      _habits.removeAt(index);
    });
    _saveHabits();
  }

  // تعديل أو إيقاف وقت التذكير لعادة موجودة
  Future<void> _configureHabitReminder(int index) async {
    final habit = _habits[index];
    final initialTime = habit.hasReminder
        ? TimeOfDay(hour: habit.reminderHour!, minute: habit.reminderMinute!)
        : const TimeOfDay(hour: 20, minute: 0);

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'إعدادات التذكير: ${habit.title}',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.access_time_filled_rounded,
                  color: Color(0xFF10B981)),
              title: const Text('تحديد أو تغيير وقت التذكير اليومي'),
              subtitle: habit.hasReminder
                  ? Text('الوقت الحالي: ${_formatTime(habit.reminderHour!, habit.reminderMinute!)}')
                  : const Text('غير مفعل حالياً'),
              onTap: () async {
                Navigator.pop(ctx);
                final picked = await showTimePicker(
                  context: context,
                  initialTime: initialTime,
                );
                if (picked != null) {
                  setState(() {
                    habit.reminderHour = picked.hour;
                    habit.reminderMinute = picked.minute;
                  });
                  await _saveHabits();
                  await NotificationService.instance
                      .scheduleDailyHabitReminder(habit);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'تم ضبط التذكير اليومي الساعة ${_formatTime(picked.hour, picked.minute)}',
                        ),
                      ),
                    );
                  }
                }
              },
            ),
            if (habit.hasReminder)
              ListTile(
                leading: const Icon(Icons.notifications_off_rounded,
                    color: Colors.redAccent),
                title: const Text('إيقاف التذكير اليومي لهذه العادة'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await NotificationService.instance
                      .cancelHabitReminder(habit.notificationId);
                  setState(() {
                    habit.reminderHour = null;
                    habit.reminderMinute = null;
                  });
                  await _saveHabits();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('تم إيقاف التذكير اليومي')),
                    );
                  }
                },
              ),
          ],
        ),
      ),
    );
  }

  String _formatTime(int hour, int minute) {
    final tod = TimeOfDay(hour: hour, minute: minute);
    final period = tod.period == DayPeriod.am ? 'صباحاً' : 'مساءً';
    final h = tod.hourOfPeriod == 0 ? 12 : tod.hourOfPeriod;
    final m = minute.toString().padLeft(2, '0');
    return '$h:$m $period';
  }

  void _resetWeek() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تصفير الأسبوع'),
        content: const Text(
            'هل أنت متأكد من تصفير جميع إنجازات الأسبوع الحالي للبدء من جديد؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              setState(() {
                for (var h in _habits) {
                  h.days = List.filled(7, false);
                }
              });
              _saveHabits();
              Navigator.pop(ctx);
            },
            child: const Text('تصفير الآن'),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // الحسابات الإحصائية
  // ==========================================
  double get _overallCompletionRate {
    if (_habits.isEmpty) return 0.0;
    int totalPossible = _habits.length * 7;
    int totalCompleted =
        _habits.fold(0, (sum, h) => sum + h.completedCount);
    return (totalCompleted / totalPossible) * 100;
  }

  int get _bestOverallStreak {
    if (_habits.isEmpty) return 0;
    return _habits
        .map((h) => h.maxStreak)
        .reduce((a, b) => a > b ? a : b);
  }

  int get _perfectDaysCount {
    if (_habits.isEmpty) return 0;
    int count = 0;
    for (int d = 0; d < 7; d++) {
      if (_habits.every((h) => h.days[d])) count++;
    }
    return count;
  }

  int _completedOnDay(int dayIndex) =>
      _habits.where((h) => h.days[dayIndex]).length;

  bool _isPartOfStreak(Habit habit, int dayIndex) {
    if (!habit.days[dayIndex]) return false;
    bool prevDone = dayIndex > 0 && habit.days[dayIndex - 1];
    bool nextDone = dayIndex < 6 && habit.days[dayIndex + 1];
    return prevDone || nextDone;
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'صحة':
        return const Color(0xFF10B981);
      case 'تعلم':
        return const Color(0xFF3B82F6);
      case 'إنتاجية':
        return const Color(0xFF8B5CF6);
      case 'روحانيات':
        return const Color(0xFFF59E0B);
      case 'مالي':
        return const Color(0xFFEC4899);
      default:
        return const Color(0xFF10B981);
    }
  }

  // ==========================================
  // نافذة إضافة عادة جديدة مع وقت التذكير
  // ==========================================
  void _showAddHabitModal() {
    final titleController = TextEditingController();
    String selectedCategory = 'إنتاجية';
    int selectedIconCode = Icons.check_circle_outline_rounded.codePoint;
    bool enableReminder = true;
    TimeOfDay reminderTime = const TimeOfDay(hour: 20, minute: 0);

    final List<String> categories = [
      'إنتاجية',
      'صحة',
      'تعلم',
      'روحانيات',
      'مالي'
    ];
    final List<IconData> availableIcons = [
      Icons.check_circle_outline_rounded,
      Icons.menu_book_rounded,
      Icons.fitness_center_rounded,
      Icons.code_rounded,
      Icons.mosque_rounded,
      Icons.water_drop_rounded,
      Icons.savings_rounded,
      Icons.self_improvement_rounded,
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                top: 24,
                right: 20,
                left: 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'إضافة هدف يومي جديد',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: titleController,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: 'اسم العادة أو الهدف',
                        hintText: 'مثال: قراءة 15 صفحة، مشي نصف ساعة...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'التصنيف:',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: categories.map((cat) {
                        final isSelected = selectedCategory == cat;
                        return ChoiceChip(
                          label: Text(cat),
                          selected: isSelected,
                          selectedColor:
                              _getCategoryColor(cat).withOpacity(0.25),
                          onSelected: (_) {
                            setModalState(() => selectedCategory = cat);
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'الأيقونة:',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      children: availableIcons.map((iconData) {
                        final isSelected =
                            selectedIconCode == iconData.codePoint;
                        return InkWell(
                          onTap: () {
                            setModalState(
                                () => selectedIconCode = iconData.codePoint);
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFF10B981).withOpacity(0.2)
                                  : Colors.transparent,
                              border: Border.all(
                                color: isSelected
                                    ? const Color(0xFF10B981)
                                    : Colors.grey.withOpacity(0.3),
                                width: 2,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              iconData,
                              color: isSelected
                                  ? const Color(0xFF10B981)
                                  : Colors.grey,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'تفعيل التذكير اليومي 🔔',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        enableReminder
                            ? 'سيصلك إشعار الساعة ${_formatTime(reminderTime.hour, reminderTime.minute)}'
                            : 'بدون إشعار تذكير',
                      ),
                      value: enableReminder,
                      activeColor: const Color(0xFF10B981),
                      onChanged: (val) {
                        setModalState(() => enableReminder = val);
                      },
                    ),
                    if (enableReminder)
                      OutlinedButton.icon(
                        icon: const Icon(Icons.access_time_rounded),
                        label: Text(
                          'تغيير وقت التنبيه (${_formatTime(reminderTime.hour, reminderTime.minute)})',
                        ),
                        onPressed: () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime: reminderTime,
                          );
                          if (picked != null) {
                            setModalState(() => reminderTime = picked);
                          }
                        },
                      ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: FilledButton.icon(
                        icon: const Icon(Icons.add_task_rounded),
                        label: const Text(
                          'حفظ العادة وجدولة التنبيه',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        onPressed: () async {
                          final text = titleController.text.trim();
                          if (text.isEmpty) return;

                          final newHabit = Habit(
                            id: DateTime.now()
                                .millisecondsSinceEpoch
                                .toString(),
                            title: text,
                            category: selectedCategory,
                            iconCode: selectedIconCode,
                            days: List.filled(7, false),
                            reminderHour:
                                enableReminder ? reminderTime.hour : null,
                            reminderMinute:
                                enableReminder ? reminderTime.minute : null,
                          );

                          setState(() {
                            _habits.add(newHabit);
                          });
                          await _saveHabits();

                          if (newHabit.hasReminder) {
                            await NotificationService.instance
                                .scheduleDailyHabitReminder(newHabit);
                          }

                          if (mounted) Navigator.pop(ctx);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ==========================================
  // بناء واجهة المستخدم
  // ==========================================
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.auto_graph_rounded, color: Color(0xFF10B981)),
            SizedBox(width: 10),
            Text(
              'إنجاز | متتبع العادات',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'اختبار الإشعارات الفوري',
            onPressed: () {
              NotificationService.instance.showInstantTestNotification();
            },
            icon: const Icon(Icons.notifications_active_outlined,
                color: Color(0xFF10B981)),
          ),
          IconButton(
            tooltip: 'تصفير الأسبوع',
            onPressed: _resetWeek,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'تبديل المظهر',
            onPressed: widget.onToggleTheme,
            icon: Icon(
              widget.isDarkMode
                  ? Icons.light_mode_rounded
                  : Icons.dark_mode_rounded,
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddHabitModal,
        backgroundColor: const Color(0xFF10B981),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          'هدف جديد',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildKpiRow(),
            const SizedBox(height: 24),
            _buildChartsSection(),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'سجل العادات الأسبوعي',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  '${_habits.length} عادات نشطة',
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_habits.isEmpty)
              _buildEmptyState()
            else
              ...List.generate(
                  _habits.length, (index) => _buildHabitCard(index)),
          ],
        ),
      ),
    );
  }

  Widget _buildKpiRow() {
    return Row(
      children: [
        Expanded(
          child: _kpiCard(
            title: 'نسبة الإنجاز',
            value: '${_overallCompletionRate.toStringAsFixed(0)}%',
            subtitle: 'هذا الأسبوع',
            icon: Icons.pie_chart_rounded,
            color: const Color(0xFF10B981),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _kpiCard(
            title: 'أطول سلسلة',
            value: '$_bestOverallStreak أيام',
            subtitle: 'أفضل التزام متتالٍ',
            icon: Icons.local_fire_department_rounded,
            color: const Color(0xFFF59E0B),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _kpiCard(
            title: 'أيام مثالية',
            value: '$_perfectDaysCount / 7',
            subtitle: 'إنجاز 100%',
            icon: Icons.emoji_events_rounded,
            color: const Color(0xFF3B82F6),
          ),
        ),
      ],
    );
  }

  Widget _kpiCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 10, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildChartsSection() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final maxHabits = _habits.isEmpty ? 1.0 : _habits.length.toDouble();

    return DefaultTabController(
      length: 2,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey.withOpacity(0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const TabBar(
              indicatorColor: Color(0xFF10B981),
              labelColor: Color(0xFF10B981),
              tabs: [
                Tab(text: 'الإنجاز اليومي'),
                Tab(text: 'مقارنة السلاسل (Streak)'),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 200,
              child: TabBarView(
                children: [
                  BarChart(
                    BarChartData(
                      maxY: maxHabits,
                      gridData: const FlGridData(show: false),
                      borderData: FlBorderData(show: false),
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 28,
                            interval: 1,
                            getTitlesWidget: (val, meta) => Text(
                              val.toInt().toString(),
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.grey),
                            ),
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (value, meta) {
                              int idx = value.toInt();
                              if (idx < 0 || idx >= 7) return const SizedBox();
                              return Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  _weekDays[idx],
                                  style: const TextStyle(fontSize: 10),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      barGroups: List.generate(7, (dayIdx) {
                        final count = _completedOnDay(dayIdx).toDouble();
                        final isPerfect =
                            _habits.isNotEmpty && count == _habits.length;
                        return BarChartGroupData(
                          x: dayIdx,
                          barRods: [
                            BarChartRodData(
                              toY: count,
                              width: 18,
                              borderRadius: BorderRadius.circular(6),
                              color: isPerfect
                                  ? const Color(0xFFF59E0B)
                                  : const Color(0xFF10B981),
                              backDrawRodData: BackgroundBarChartRodData(
                                show: true,
                                toY: maxHabits,
                                color: Colors.grey.withOpacity(0.12),
                              ),
                            ),
                          ],
                        );
                      }),
                    ),
                  ),
                  _habits.isEmpty
                      ? const Center(child: Text('أضف عادات لعرض المقارنة'))
                      : BarChart(
                          BarChartData(
                            maxY: 7,
                            gridData: const FlGridData(show: false),
                            borderData: FlBorderData(show: false),
                            titlesData: FlTitlesData(
                              topTitles: const AxisTitles(
                                  sideTitles: SideTitles(showTitles: false)),
                              rightTitles: const AxisTitles(
                                  sideTitles: SideTitles(showTitles: false)),
                              leftTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 28,
                                  interval: 1,
                                  getTitlesWidget: (val, meta) => Text(
                                    val.toInt().toString(),
                                    style: const TextStyle(
                                        fontSize: 11, color: Colors.grey),
                                  ),
                                ),
                              ),
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  getTitlesWidget: (value, meta) {
                                    int idx = value.toInt();
                                    if (idx < 0 || idx >= _habits.length) {
                                      return const SizedBox();
                                    }
                                    String shortTitle = _habits[idx].title;
                                    if (shortTitle.length > 8) {
                                      shortTitle =
                                          '${shortTitle.substring(0, 8)}..';
                                    }
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: Text(
                                        shortTitle,
                                        style: const TextStyle(fontSize: 10),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                            barGroups:
                                List.generate(_habits.length, (habitIdx) {
                              final h = _habits[habitIdx];
                              return BarChartGroupData(
                                x: habitIdx,
                                barRods: [
                                  BarChartRodData(
                                    toY: h.maxStreak.toDouble(),
                                    width: 20,
                                    borderRadius: BorderRadius.circular(6),
                                    color: _getCategoryColor(h.category),
                                    backDrawRodData: BackgroundBarChartRodData(
                                      show: true,
                                      toY: 7,
                                      color: Colors.grey.withOpacity(0.12),
                                    ),
                                  ),
                                ],
                              );
                            }),
                          ),
                        ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHabitCard(int index) {
    final habit = _habits[index];
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final catColor = _getCategoryColor(habit.category);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: catColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  IconData(habit.iconCode, fontFamily: 'MaterialIcons'),
                  color: catColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      habit.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: catColor.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            habit.category,
                            style: TextStyle(
                              fontSize: 11,
                              color: catColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.local_fire_department_rounded,
                              size: 15,
                              color: habit.maxStreak >= 3
                                  ? const Color(0xFFF59E0B)
                                  : Colors.grey,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              'سلسلة: ${habit.maxStreak} أيام',
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.grey),
                            ),
                          ],
                        ),
                        // شارة وقت التذكير قابلة للنقر للتعديل
                        InkWell(
                          onTap: () => _configureHabitReminder(index),
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: habit.hasReminder
                                  ? const Color(0xFF10B981).withOpacity(0.15)
                                  : Colors.grey.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  habit.hasReminder
                                      ? Icons.alarm_on_rounded
                                      : Icons.alarm_off_rounded,
                                  size: 13,
                                  color: habit.hasReminder
                                      ? const Color(0xFF10B981)
                                      : Colors.grey,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  habit.hasReminder
                                      ? _formatTime(habit.reminderHour!,
                                          habit.reminderMinute!)
                                      : 'ضبط منبه',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: habit.hasReminder
                                        ? const Color(0xFF10B981)
                                        : Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => _deleteHabit(index),
                icon: const Icon(Icons.delete_outline_rounded,
                    color: Colors.redAccent, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(7, (dayIdx) {
              final isDone = habit.days[dayIdx];
              final inStreak = _isPartOfStreak(habit, dayIdx);

              return GestureDetector(
                onTap: () => _toggleDay(index, dayIdx),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 42,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: isDone
                        ? (inStreak
                            ? const Color(0xFF10B981)
                            : const Color(0xFF10B981).withOpacity(0.75))
                        : (isDark
                            ? const Color(0xFF0F172A)
                            : const Color(0xFFF1F5F9)),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: inStreak
                          ? const Color(0xFFF59E0B)
                          : Colors.transparent,
                      width: inStreak ? 1.8 : 1,
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        _weekDays[dayIdx],
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: isDone ? Colors.white : Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Icon(
                        isDone
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        size: 18,
                        color: isDone
                            ? Colors.white
                            : Colors.grey.withOpacity(0.5),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withOpacity(0.2)),
      ),
      child: const Column(
        children: [
          Icon(Icons.track_changes_rounded, size: 48, color: Colors.grey),
          SizedBox(height: 12),
          Text(
            'لا توجد عادات مسجلة حالياً',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          SizedBox(height: 4),
          Text(
            'اضغط على زر "هدف جديد" بالأسفل لإضافة عادتك الأولى وضبط منبهها اليومي',
            style: TextStyle(color: Colors.grey, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
