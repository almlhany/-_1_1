import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const AlarmApp());

const dayNames = ['الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];

String fmt(TimeOfDay t) {
  final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
  final m = t.minute.toString().padLeft(2, '0');
  return '$h:$m ${t.period == DayPeriod.am ? 'ص' : 'م'}';
}

class AlarmApp extends StatelessWidget {
  const AlarmApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'المنبّه',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFFF2B84B),
        brightness: Brightness.dark,
      ),
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      home: const HomePage(),
    );
  }
}

class Alarm {
  Alarm({required this.time, this.label = '', Set<int>? days, this.on = true})
      : days = days ?? <int>{};
  TimeOfDay time;
  String label;
  Set<int> days; // 1 = الاثنين ... 7 = الأحد
  bool on;
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final List<Alarm> alarms = [];
  late final Timer timer;
  Timer? beepTimer;
  DateTime now = DateTime.now();
  DateTime? snoozeAt;
  String lastKey = '';
  bool ringing = false;

  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }

  @override
  void dispose() {
    timer.cancel();
    beepTimer?.cancel();
    super.dispose();
  }

  void tick() {
    now = DateTime.now();
    if (!ringing) {
      final key = '${now.year}-${now.month}-${now.day}-${now.hour}:${now.minute}';
      if (snoozeAt != null && !now.isBefore(snoozeAt!)) {
        snoozeAt = null;
        startRing('غفوة');
      } else if (key != lastKey) {
        for (final a in alarms) {
          if (a.on &&
              a.time.hour == now.hour &&
              a.time.minute == now.minute &&
              (a.days.isEmpty || a.days.contains(now.weekday))) {
            lastKey = key;
            if (a.days.isEmpty) a.on = false;
            startRing(a.label.isEmpty ? 'حان الوقت' : a.label);
            break;
          }
        }
      }
    }
    if (mounted) setState(() {});
  }

  void beep() {
    SystemSound.play(SystemSoundType.alert);
    HapticFeedback.vibrate();
  }

  void stopRing() {
    beepTimer?.cancel();
    ringing = false;
  }

  void startRing(String label) {
    ringing = true;
    beep();
    beepTimer = Timer.periodic(const Duration(seconds: 1), (_) => beep());
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(label, textAlign: TextAlign.center),
        content: Text(
          fmt(TimeOfDay.now()),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold),
        ),
        actions: [
          TextButton(
            onPressed: () {
              snoozeAt = DateTime.now().add(const Duration(minutes: 5));
              Navigator.pop(ctx);
            },
            child: const Text('غفوة 5 دقائق'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إيقاف'),
          ),
        ],
      ),
    ).then((_) => stopRing());
  }

  String nextText() {
    DateTime? best;
    for (final a in alarms.where((a) => a.on)) {
      for (var d = 0; d < 8; d++) {
        final base = now.add(Duration(days: d));
        final t = DateTime(base.year, base.month, base.day, a.time.hour, a.time.minute);
        if (!t.isAfter(now)) continue;
        if (a.days.isNotEmpty && !a.days.contains(t.weekday)) continue;
        if (best == null || t.isBefore(best)) best = t;
        break;
      }
    }
    if (best == null) return 'لا يوجد منبّه مفعّل';
    final mins = (best.difference(now).inSeconds / 60).ceil();
    final h = mins ~/ 60;
    final m = mins % 60;
    final parts = <String>[];
    if (h > 0) parts.add('$h ساعة');
    if (m > 0 || h == 0) parts.add('$m دقيقة');
    return 'أقرب منبّه بعد ${parts.join(' و ')}';
  }

  Future<void> edit([Alarm? a]) async {
    var time = a?.time ?? TimeOfDay.now();
    final label = TextEditingController(text: a?.label ?? '');
    final days = <int>{...?a?.days};
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.fromLTRB(
              20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextButton(
                onPressed: () async {
                  final t = await showTimePicker(context: ctx, initialTime: time);
                  if (t != null) setS(() => time = t);
                },
                child: Text(fmt(time),
                    style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold)),
              ),
              TextField(
                controller: label,
                maxLength: 30,
                decoration: const InputDecoration(
                    labelText: 'الاسم', hintText: 'مثال: صلاة الفجر'),
              ),
              const Text('التكرار (بدون اختيار = مرة واحدة)'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (var i = 1; i <= 7; i++)
                    FilterChip(
                      label: Text(dayNames[i - 1]),
                      selected: days.contains(i),
                      onSelected: (v) => setS(() {
                        if (v) {
                          days.add(i);
                        } else {
                          days.remove(i);
                        }
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('حفظ المنبّه'),
              ),
            ],
          ),
        ),
      ),
    );
    if (saved == true) {
      setState(() {
        if (a != null) {
          a.time = time;
          a.label = label.text.trim();
          a.days = days;
          a.on = true;
        } else {
          alarms.add(Alarm(time: time, label: label.text.trim(), days: days));
        }
        alarms.sort((x, y) =>
            (x.time.hour * 60 + x.time.minute) - (y.time.hour * 60 + y.time.minute));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hh = (now.hour % 12 == 0 ? 12 : now.hour % 12).toString();
    final mm = now.minute.toString().padLeft(2, '0');
    final ss = now.second.toString().padLeft(2, '0');
    return Scaffold(
      appBar: AppBar(title: const Text('المنبّه')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => edit(),
        icon: const Icon(Icons.add_alarm),
        label: const Text('إضافة منبّه'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          const SizedBox(height: 16),
          Center(
            child: Text(
              '$hh:$mm:$ss ${now.hour < 12 ? 'ص' : 'م'}',
              textDirection: TextDirection.ltr,
              style: const TextStyle(fontSize: 54, fontWeight: FontWeight.w800),
            ),
          ),
          Center(
            child: Text(dayNames[now.weekday - 1],
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 16)),
          ),
          const SizedBox(height: 12),
          Center(child: Chip(label: Text(nextText()))),
          const SizedBox(height: 16),
          if (alarms.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'ما عندك منبّهات بعد. اضغط «إضافة منبّه» لتبدأ.',
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            ),
          for (final a in alarms)
            Card(
              child: ListTile(
                onTap: () => edit(a),
                title: Text(fmt(a.time),
                    style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: a.on ? null : cs.onSurfaceVariant)),
                subtitle: Text(
                  '${a.label.isEmpty ? '' : '${a.label} • '}'
                  '${a.days.isEmpty ? 'مرة واحدة' : a.days.length == 7 ? 'كل يوم' : (a.days.toList()..sort()).map((d) => dayNames[d - 1]).join('، ')}',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Switch(value: a.on, onChanged: (v) => setState(() => a.on = v)),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() => alarms.remove(a)),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}