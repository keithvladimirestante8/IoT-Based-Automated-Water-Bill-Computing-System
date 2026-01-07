import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shimmer/shimmer.dart';

import 'profile.dart';

class ChartData {
  ChartData(this.x, this.y);

  final String x;
  final double y;
}

class ChartDataBar {
  ChartDataBar(this.x, this.y);

  final String x;
  final double y;
}

Map<String, dynamic> _processLogsForCharts(Map<String, dynamic> args) {
  final logsRootForMonthly = Map<String, dynamic>.from(
    args['logsRootForMonthly'] ?? {},
  );
  final aggregatedRoot = Map<String, dynamic>.from(
    args['aggregatedRoot'] ?? {},
  );
  final rawLogsRoot = Map<String, dynamic>.from(args['rawLogsRoot'] ?? {});
  final now = DateTime.fromMillisecondsSinceEpoch(
    args['nowMillis'] as int? ?? DateTime.now().millisecondsSinceEpoch,
  );
  final summary = Map<String, dynamic>.from(args['summary'] ?? {});
  final initialLogLimit = args['initialLogLimit'] as int? ?? 50;

  const List<String> englishMonths = [
    "",
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

  final currentYear = now.year.toString();
  final currentMonthName = englishMonths[now.month];

  final List<Map<String, dynamic>> monthlyUsageData = [];
  final List<Map<String, dynamic>> monthlyBillData = [];

  for (int i = 11; i >= 0; i--) {
    final targetDate = DateTime(now.year, now.month - i, 1);
    final yearStr = targetDate.year.toString();
    final monthStr = englishMonths[targetDate.month];

    double totalUsageForMonth = 0.0;
    double totalBillForMonth = 0.0;

    if (yearStr == currentYear && monthStr == currentMonthName) {
      totalUsageForMonth = (summary['Water_Usage'] ?? 0).toDouble();
      final billString = summary['Display_Total_Bill']?.toString() ?? '0.00';
      final cleaned = billString.replaceAll(RegExp(r'[^0-9\.\-]'), '');
      totalBillForMonth = double.tryParse(cleaned) ?? 0.0;
    } else {
      final targetMonthLogsDynamic =
          logsRootForMonthly[yearStr]?[monthStr] as Map?;
      if (targetMonthLogsDynamic != null) {
        final targetMonthLogs = Map<String, dynamic>.from(
          targetMonthLogsDynamic,
        );
        targetMonthLogs.forEach((logKey, logValue) {
          try {
            final data = Map<String, dynamic>.from(logValue as Map);
            if (data.containsKey('TotalUsage')) {
              totalUsageForMonth += (data['TotalUsage'] ?? 0).toDouble();
            } else {
              totalUsageForMonth += (data['Water_Usage'] ?? 0).toDouble();
            }
            final billString =
                (data['Display_Bill'] as String?) ??
                (data['Bill']?.toString()) ??
                '0.00';
            final cleaned = billString.toString().replaceAll(
              RegExp(r'[^0-9\.\-]'),
              '',
            );
            totalBillForMonth += double.tryParse(cleaned) ?? 0.0;
          } catch (_) {}
        });
      }
    }
    monthlyUsageData.add({
      'label': monthStr.substring(0, 3),
      'value': totalUsageForMonth,
    });
    monthlyBillData.add({
      'label': monthStr.substring(0, 3),
      'value': totalBillForMonth,
    });
  }

  final List<Map<String, dynamic>> weeklyUsageData = [];
  final Map<String, dynamic> logsForProcessing =
      (aggregatedRoot.isNotEmpty) ? aggregatedRoot : rawLogsRoot;
  final Map<String, dynamic> currentYearMap = Map<String, dynamic>.from(
    logsForProcessing[currentYear] ?? {},
  );
  final Map<String, dynamic> currentMonthFlat = {};

  currentYearMap.forEach((monthName, monthMap) {
    try {
      final mm = Map<String, dynamic>.from(monthMap as Map);
      mm.forEach((k, v) {
        currentMonthFlat[k] = v;
      });
    } catch (_) {}
  });

  for (int i = 6; i >= 0; i--) {
    final targetDate = now.subtract(Duration(days: i));
    final dayLabel = DateFormat('E').format(targetDate);
    double totalUsageForDay = 0.0;

    currentMonthFlat.forEach((logKey, logValue) {
      try {
        final keyParts = logKey.split('_');
        final datePart = keyParts[0];
        final logDate = DateTime.tryParse(datePart);

        if (logDate != null) {
          if (logDate.year == targetDate.year &&
              logDate.month == targetDate.month &&
              logDate.day == targetDate.day) {
            final data = Map<String, dynamic>.from(logValue as Map);
            if (data.containsKey('TotalUsage')) {
              totalUsageForDay += (data['TotalUsage'] ?? 0).toDouble();
            } else {
              totalUsageForDay += (data['Water_Usage'] ?? 0).toDouble();
            }
          }
        }
      } catch (_) {}
    });
    weeklyUsageData.add({'label': dayLabel, 'value': totalUsageForDay});
  }

  final List<Map<String, dynamic>> hourlyUsageData = [];
  final Map<int, double> hourlyTotals = {for (var i = 0; i < 24; i++) i: 0.0};

  currentMonthFlat.forEach((logKey, logValue) {
    try {
      final keyParts = logKey.split('_');
      final datePart = keyParts[0];
      final logDate = DateTime.tryParse(datePart);

      if (logDate != null &&
          logDate.year == now.year &&
          logDate.month == now.month &&
          logDate.day == now.day) {
        final data = Map<String, dynamic>.from(logValue as Map);
        int hourIdx = 0;
        if (data.containsKey('TotalUsage')) {
          if (keyParts.length > 1) hourIdx = int.tryParse(keyParts[1]) ?? 0;
          hourlyTotals[hourIdx] =
              (hourlyTotals[hourIdx] ?? 0.0) +
              (data['TotalUsage'] ?? 0).toDouble();
        } else {
          if (keyParts.length > 1) {
            final timePart = keyParts[1];
            hourIdx = int.tryParse(timePart.split('-')[0]) ?? 0;
          }
          hourlyTotals[hourIdx] =
              (hourlyTotals[hourIdx] ?? 0.0) +
              (data['Water_Usage'] ?? 0).toDouble();
        }
      }
    } catch (_) {}
  });

  hourlyTotals.forEach((hour, val) {
    final label =
        (hour == now.hour)
            ? 'Now'
            : DateFormat(
              'h a',
            ).format(DateTime(now.year, now.month, now.day, hour));
    hourlyUsageData.add({'label': label, 'value': val});
  });

  final entries = <Map<String, dynamic>>[];
  final targetMonthData = currentYearMap[currentMonthName];
  if (targetMonthData != null) {
    try {
      final specificMonthLogs = Map<String, dynamic>.from(
        targetMonthData as Map,
      );
      specificMonthLogs.forEach((k, v) {
        entries.add({'key': k, 'value': v});
      });
    } catch (_) {}
  }
  entries.sort((a, b) => (b['key'] as String).compareTo(a['key'] as String));

  final int showCount = entries.length.clamp(0, initialLogLimit);
  final bool hasMore = entries.length > initialLogLimit;
  final List<Map<String, dynamic>> initialEntries = entries.sublist(
    0,
    showCount,
  );

  final double totalUsageFromSummary =
      (summary['Water_Usage'] ?? 0.0).toDouble();
  final String totalBillDisplay =
      (summary['Display_Total_Bill'] ?? '₱0.00').toString();

  return {
    'monthlyUsageData': monthlyUsageData,
    'monthlyBillData': monthlyBillData,
    'weeklyUsageData': weeklyUsageData,
    'hourlyUsageData': hourlyUsageData,
    'uiEntries': initialEntries,
    'hasMore': hasMore,
    'totalUsage': totalUsageFromSummary,
    'totalBill': totalBillDisplay,
  };
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fadeIn;
  final DatabaseReference _databaseRef = FirebaseDatabase.instance.ref();

  Map<String, dynamic>? _processedCache;
  Future<Map<String, dynamic>>? _chartsFuture;
  bool _isProcessingCharts = false;
  int _lastEnsureCallMillis = 0;
  final Duration _ensureDebounce = const Duration(milliseconds: 300);

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    _fadeIn = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _ctrl.forward();
    _chartsFuture = Future.value(<String, dynamic>{});
    _checkAndResetData();

    Future.microtask(() async {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        try {
          final persisted = await _loadProcessedCacheFromPrefs(uid);
          if (persisted != null && persisted['processed'] != null) {
            final processed = Map<String, dynamic>.from(persisted['processed']);
            if (mounted) {
              setState(() {
                _processedCache = processed;
                _chartsFuture = Future.value(_processedCache);
              });
            }
          }
        } catch (_) {}
      }
    });

    Future.delayed(
      const Duration(milliseconds: 500),
      () => _startAggregationForCurrentMonth(),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _editWaterLimit(double currentLimit) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final TextEditingController _limitController = TextEditingController(
      text: currentLimit.toInt().toString(),
    );

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Set Water Limit'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("When this limit is reached, the buzzer will sound."),
              const SizedBox(height: 10),
              TextField(
                controller: _limitController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: "Limit (Liters)",
                  border: OutlineInputBorder(),
                  suffixText: "L",
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final input = double.tryParse(_limitController.text);
                if (input != null && input > 0) {
                  await _databaseRef.child('Users/$uid/Settings').update({
                    'Water_Limit': input,
                  });
                  if (mounted) Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Limit updated. Syncing...')),
                  );
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _editPricing(Map<String, dynamic> currentPrices) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final t1 = TextEditingController(
      text: (currentPrices['Tier1'] ?? 0.06562).toString(),
    );
    final t2 = TextEditingController(
      text: (currentPrices['Tier2'] ?? 0.07000).toString(),
    );
    final t3 = TextEditingController(
      text: (currentPrices['Tier3'] ?? 0.07500).toString(),
    );

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Set Water Rates'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("Set price per liter based on your bill."),
                const SizedBox(height: 15),
                TextField(
                  controller: t1,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: "Tier 1 (0-100L)",
                    prefixText: "₱ ",
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: t2,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: "Tier 2 (101-200L)",
                    prefixText: "₱ ",
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: t3,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: "Tier 3 (201L+)",
                    prefixText: "₱ ",
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final d1 = double.tryParse(t1.text);
                final d2 = double.tryParse(t2.text);
                final d3 = double.tryParse(t3.text);
                if (d1 != null && d2 != null && d3 != null) {
                  await _databaseRef.child('Users/$uid/Settings/Prices').update(
                    {'Tier1': d1, 'Tier2': d2, 'Tier3': d3},
                  );
                  if (mounted) Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Rates updated. Arduino will sync shortly.',
                      ),
                    ),
                  );
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _checkAndResetData() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final now = DateTime.now();
    final currentYear = now.year.toString();
    final snapshot = await _databaseRef.child('Users/$uid').once();
    final val = snapshot.snapshot.value as Map? ?? {};
    final logsRoot = val['Water_Logs'] as Map? ?? {};
    final currentYearLogs = logsRoot[currentYear] as Map? ?? {};
    final previousMonthDate = now.subtract(const Duration(days: 1));
    final previousYear = previousMonthDate.year.toString();

    if (now.month == 1 && logsRoot[previousYear] != null) {
      if (currentYearLogs.isEmpty) {
        final previousYearFullLogs = logsRoot[previousYear] as Map? ?? {};
        if (previousYearFullLogs.isNotEmpty) {
          final archivePath = 'Users/$uid/Water_Logs/Archives/$previousYear';
          final archiveSnapshot = await _databaseRef.child(archivePath).once();
          if (archiveSnapshot.snapshot.value == null) {
            await _databaseRef.child(archivePath).set(previousYearFullLogs);
          }
          await _databaseRef.child('Users/$uid/Summary').update({
            'Water_Usage': 0.0,
            'Total_Bill': 0.0,
            'Display_Total_Bill': '₱0.00',
          });
          await _databaseRef
              .child('Users/$uid/Water_Logs/$previousYear')
              .remove();
        }
      }
    }
  }

  Future<void> _startAggregationForCurrentMonth() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final now = DateTime.now();
    final currentYear = now.year.toString();
    final currentMonthName = DateFormat.MMMM().format(now);
    final rawPath = 'Users/$uid/Water_Logs/$currentYear/$currentMonthName';

    _databaseRef.child(rawPath).onChildAdded.listen((event) {
      if (event.snapshot.key != null && event.snapshot.value != null) {
        _aggregateRawLog(
          uid,
          event.snapshot.key!,
          Map<String, dynamic>.from(event.snapshot.value as Map),
        );
      }
    });
    _cleanupOldRawLogs(uid);
  }

  Future<void> _aggregateRawLog(
    String uid,
    String rawKey,
    Map<String, dynamic> rawData,
  ) async {
    try {
      final parts = rawKey.split('_');
      if (parts.isEmpty) return;
      final datePart = parts[0];
      final timePart = parts.length > 1 ? parts[1] : '00-00-00';
      final hour = timePart.split('-')[0].padLeft(2, '0');
      final hourKey = '${datePart}_$hour';
      final dt = DateTime.tryParse(datePart) ?? DateTime.now();
      final year = dt.year.toString();
      final monthName = DateFormat.MMMM().format(dt);
      final hourlyPath =
          'Users/$uid/Water_Logs_Hourly/$year/$monthName/$hourKey';
      final usageToAdd = (rawData['Water_Usage'] ?? 0).toDouble();

      final hourlyRef = _databaseRef.child(hourlyPath);
      final hourlySnapshot = await hourlyRef.once();
      double existingTotal = 0.0;
      int existingCount = 0;
      if (hourlySnapshot.snapshot.value != null) {
        final hourlyVal = Map<String, dynamic>.from(
          hourlySnapshot.snapshot.value as Map,
        );
        existingTotal = (hourlyVal['TotalUsage'] ?? 0).toDouble();
        existingCount =
            (hourlyVal['Entries'] ?? 0) is int
                ? (hourlyVal['Entries'] ?? 0) as int
                : 0;
      }
      await hourlyRef.set({
        'TotalUsage': existingTotal + usageToAdd,
        'Entries': existingCount + 1,
        'UpdatedAt': ServerValue.timestamp,
      });
      await _databaseRef
          .child('Users/$uid/Water_Logs/$year/$monthName/$rawKey')
          .remove();
    } catch (_) {}
  }

  Future<void> _cleanupOldRawLogs(String uid) async {
    try {
      final now = DateTime.now();
      final twoDaysAgo = now.subtract(const Duration(days: 2));
      final rootRef = _databaseRef.child('Users/$uid/Water_Logs');
      final snapshot = await rootRef.once();
      final rootVal = snapshot.snapshot.value as Map? ?? {};
      for (final yearKey in rootVal.keys) {
        final yearMap = rootVal[yearKey] as Map? ?? {};
        for (final monthName in yearMap.keys) {
          final monthMap = yearMap[monthName] as Map? ?? {};
          for (final rawKey in monthMap.keys) {
            try {
              final dateStr = rawKey.split('_').first;
              final dt = DateTime.tryParse(dateStr);
              if (dt == null) continue;
              if (dt.isBefore(twoDaysAgo)) {
                final rawPath =
                    'Users/$uid/Water_Logs/$yearKey/$monthName/$rawKey';
                await _databaseRef.child(rawPath).remove();
              }
            } catch (e) {}
          }
        }
      }
    } catch (e) {
      debugPrint('Error cleanup: $e');
    }
  }

  Future<void> _saveProcessedCacheToPrefs(
    String uid,
    String hash,
    Map<String, dynamic> processed,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'dashboard_cache_$uid',
      jsonEncode({'hash': hash, 'processed': processed}),
    );
  }

  Future<Map<String, dynamic>?> _loadProcessedCacheFromPrefs(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('dashboard_cache_$uid');
    return raw == null ? null : jsonDecode(raw);
  }

  String _computeLightSnapshotHash(
    Map<String, dynamic> logs,
    Map<String, dynamic> summary,
  ) {
    try {
      return '${jsonEncode(logs).hashCode}|${jsonEncode(summary).hashCode}';
    } catch (e) {
      return '0';
    }
  }

  Future<void> _ensureChartsUpToDate({
    required Map<String, dynamic> logsRootForMonthly,
    required Map<String, dynamic> aggregatedRoot,
    required Map<String, dynamic> rawLogsRoot,
    required String currentYear,
    required String currentMonthName,
    required Map<String, dynamic> summary,
    required DateTime now,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final snapshotHash = _computeLightSnapshotHash(logsRootForMonthly, summary);

    if (_processedCache != null) {
      _chartsFuture = Future.value(_processedCache);
    }

    final persisted = await _loadProcessedCacheFromPrefs(uid);
    if (persisted != null &&
        persisted['hash'] == snapshotHash &&
        persisted['processed'] != null) {
      try {
        _processedCache = Map<String, dynamic>.from(persisted['processed']);
        _chartsFuture = Future.value(_processedCache);
      } catch (_) {}
      _backgroundRefreshCompute(
        logsRootForMonthly: logsRootForMonthly,
        aggregatedRoot: aggregatedRoot,
        rawLogsRoot: rawLogsRoot,
        currentYear: currentYear,
        currentMonthName: currentMonthName,
        summary: summary,
        now: now,
        snapshotHash: snapshotHash,
        uid: uid,
      );
      return;
    }

    if (_isProcessingCharts) return;
    _isProcessingCharts = true;
    _chartsFuture = compute(_processLogsForCharts, {
          'logsRootForMonthly': logsRootForMonthly,
          'aggregatedRoot': aggregatedRoot,
          'rawLogsRoot': rawLogsRoot,
          'currentYear': currentYear,
          'currentMonthName': currentMonthName,
          'nowMillis': now.millisecondsSinceEpoch,
          'initialLogLimit': 50,
          'summary': summary,
        })
        .then((processed) {
          _processedCache = Map<String, dynamic>.from(processed);
          _saveProcessedCacheToPrefs(uid, snapshotHash, processed);
          _isProcessingCharts = false;
          return processed;
        })
        .catchError((e) {
          _isProcessingCharts = false;
          return <String, dynamic>{};
        });
  }

  void _backgroundRefreshCompute({
    required Map<String, dynamic> logsRootForMonthly,
    required Map<String, dynamic> aggregatedRoot,
    required Map<String, dynamic> rawLogsRoot,
    required String currentYear,
    required String currentMonthName,
    required Map<String, dynamic> summary,
    required DateTime now,
    required String snapshotHash,
    required String uid,
  }) {
    if (_isProcessingCharts) return;
    _isProcessingCharts = true;
    compute(_processLogsForCharts, {
          'logsRootForMonthly': logsRootForMonthly,
          'aggregatedRoot': aggregatedRoot,
          'rawLogsRoot': rawLogsRoot,
          'currentYear': currentYear,
          'currentMonthName': currentMonthName,
          'nowMillis': now.millisecondsSinceEpoch,
          'initialLogLimit': 50,
          'summary': summary,
        })
        .then((processed) async {
          final processedJson = jsonEncode(processed);
          final existingJson =
              _processedCache == null ? null : jsonEncode(_processedCache);
          if (existingJson != processedJson) {
            _processedCache = Map<String, dynamic>.from(processed);
            await _saveProcessedCacheToPrefs(uid, snapshotHash, processed);
            if (mounted)
              setState(() {
                _chartsFuture = Future.value(_processedCache);
              });
          }
          _isProcessingCharts = false;
        })
        .catchError((e) {
          _isProcessingCharts = false;
        });
  }

  Future<void> _downloadSummary(
    double waterUsage,
    String totalBill,
    String currentMonthName,
  ) async {
    try {
      final pdf = pw.Document();
      final userEmail = FirebaseAuth.instance.currentUser?.email ?? "User";

      pw.MemoryImage? waterBillIcon;
      try {
        final ByteData imageData = await rootBundle.load(
          'assets/water_bill_tracker_app_icon.png',
        );
        final Uint8List imageBytes = imageData.buffer.asUint8List();
        waterBillIcon = pw.MemoryImage(imageBytes);
      } catch (_) {}

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.roll80,
          margin: const pw.EdgeInsets.all(10),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (waterBillIcon != null)
                  pw.Center(
                    child: pw.Image(waterBillIcon, width: 40, height: 40),
                  ),
                pw.SizedBox(height: 5),
                pw.Center(
                  child: pw.Text(
                    'WATER BILL TRACKER',
                    style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                pw.Center(
                  child: pw.Text(
                    'Official Statement',
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                ),
                pw.SizedBox(height: 10),
                pw.Divider(thickness: 1),

                pw.SizedBox(height: 5),
                _buildPdfRow('Billed To:', userEmail, isSmall: true),
                _buildPdfRow('Month:', currentMonthName),
                _buildPdfRow(
                  'Date:',
                  DateFormat('yyyy-MM-dd').format(DateTime.now()),
                ),
                _buildPdfRow(
                  'Time:',
                  DateFormat('HH:mm:ss').format(DateTime.now()),
                ),
                pw.SizedBox(height: 5),

                pw.Divider(borderStyle: pw.BorderStyle.dashed),

                pw.SizedBox(height: 5),
                pw.Text(
                  'Consumption Details',
                  style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 10,
                  ),
                ),
                pw.SizedBox(height: 5),

                _buildPdfRow(
                  'Total Usage:',
                  '${waterUsage.toStringAsFixed(2)} Liters',
                ),

                pw.SizedBox(height: 10),
                pw.Divider(thickness: 1),

                pw.SizedBox(height: 5),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'TOTAL DUE',
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    pw.Text(
                      totalBill,
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 5),
                pw.Divider(thickness: 1),

                pw.SizedBox(height: 10),
                pw.Center(
                  child: pw.Text(
                    'Thank you for conserving water!',
                    style: pw.TextStyle(
                      fontStyle: pw.FontStyle.italic,
                      fontSize: 8,
                    ),
                    textAlign: pw.TextAlign.center,
                  ),
                ),
                pw.SizedBox(height: 5),
                pw.Center(
                  child: pw.Text(
                    'This is a system generated receipt.',
                    style: const pw.TextStyle(
                      fontSize: 6,
                      color: PdfColors.grey,
                    ),
                    textAlign: pw.TextAlign.center,
                  ),
                ),
              ],
            );
          },
        ),
      );

      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/Water_Bill_$currentMonthName.pdf');
      await file.writeAsBytes(await pdf.save());

      await Share.shareXFiles([
        XFile(file.path, mimeType: 'application/pdf'),
      ], text: 'Water Bill Summary for $currentMonthName');
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to generate PDF summary.')),
        );
    }
  }

  pw.Widget _buildPdfRow(String label, String value, {bool isSmall = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: pw.TextStyle(fontSize: isSmall ? 8 : 10)),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              fontSize: isSmall ? 8 : 10,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null)
      return const Scaffold(body: Center(child: Text('No user logged in.')));

    final now = DateTime.now();
    final currentYear = now.year.toString();
    final currentMonthName = DateFormat.MMMM().format(now);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.blue.shade100, Colors.white],
          ),
        ),
        child: Column(
          children: [
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Dashboard',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                    Row(
                      children: [
                        DeviceStatusWidget(uid: uid),
                        const SizedBox(width: 10),
                        StreamBuilder<DatabaseEvent>(
                          stream:
                              _databaseRef
                                  .child('Users/$uid/Settings/Prices')
                                  .onValue,
                          builder: (ctx, snap) {
                            return IconButton(
                              icon: const Icon(
                                Icons.settings,
                                color: Colors.blue,
                              ),
                              onPressed: () {
                                final data =
                                    snap.data?.snapshot.value as Map? ?? {};
                                _editPricing(Map<String, dynamic>.from(data));
                              },
                            );
                          },
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.account_circle,
                            size: 30,
                            color: Colors.blue,
                          ),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const ProfileScreen(),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            Expanded(
              child: FadeTransition(
                opacity: _fadeIn,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  child: StreamBuilder<DatabaseEvent>(
                    stream: _databaseRef.child('Users/$uid').onValue,
                    builder: (ctx, snap) {
                      if (snap.connectionState == ConnectionState.waiting)
                        return const Center(child: CircularProgressIndicator());
                      if (snap.hasError)
                        return const Text('Error loading data');

                      final val = snap.data?.snapshot.value as Map? ?? {};
                      final summary = val['Summary'] as Map? ?? {};
                      final waterUsage =
                          (summary['Water_Usage'] ?? 0).toDouble();
                      final totalBill =
                          summary['Display_Total_Bill'] ?? '₱0.00';
                      final settings = val['Settings'] as Map? ?? {};
                      final double maxWaterUsage =
                          (settings['Water_Limit'] ?? 30000.0).toDouble();

                      final logsRoot = val['Water_Logs'] as Map? ?? {};
                      final aggRoot = val['Water_Logs_Hourly'] as Map? ?? {};
                      SchedulerBinding.instance.addPostFrameCallback((_) {
                        final nowMillis = DateTime.now().millisecondsSinceEpoch;
                        if (nowMillis - _lastEnsureCallMillis >
                            _ensureDebounce.inMilliseconds) {
                          _lastEnsureCallMillis = nowMillis;
                          _ensureChartsUpToDate(
                            logsRootForMonthly:
                                logsRoot.isNotEmpty
                                    ? Map<String, dynamic>.from(logsRoot)
                                    : {},
                            aggregatedRoot:
                                aggRoot.isNotEmpty
                                    ? Map<String, dynamic>.from(aggRoot)
                                    : {},
                            rawLogsRoot:
                                logsRoot.isNotEmpty
                                    ? Map<String, dynamic>.from(logsRoot)
                                    : {},
                            currentYear: currentYear,
                            currentMonthName: currentMonthName,
                            summary: Map<String, dynamic>.from(summary),
                            now: now,
                          );
                        }
                      });

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 12),
                          const Hero(
                            tag: 'logo',
                            child: CircleAvatar(
                              radius: 40,
                              backgroundColor: Colors.white,
                              child: Icon(
                                Icons.water_drop,
                                size: 50,
                                color: Colors.blue,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Water Bill Tracker',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                            ),
                          ),
                          Text(
                            'User: ${FirebaseAuth.instance.currentUser?.email ?? ""}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 16),

                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.9),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.blue.withOpacity(0.1),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'TOTAL USAGE',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.grey,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    TweenAnimationBuilder<double>(
                                      tween: Tween<double>(
                                        begin: 0,
                                        end: waterUsage,
                                      ),
                                      duration: const Duration(seconds: 2),
                                      builder: (context, value, child) {
                                        return Text(
                                          '${value.toStringAsFixed(2)} L',
                                          style: const TextStyle(
                                            fontSize: 24,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.blue,
                                          ),
                                        );
                                      },
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Bill: $totalBill',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.download_rounded,
                                    color: Colors.blue,
                                    size: 30,
                                  ),
                                  onPressed:
                                      () => _downloadSummary(
                                        waterUsage,
                                        totalBill,
                                        currentMonthName,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),

                          FutureBuilder<Map<String, dynamic>>(
                            future: _chartsFuture,
                            builder: (context, snapshotCharts) {
                              if (!snapshotCharts.hasData)
                                return _buildShimmerLoading();
                              final processed = snapshotCharts.data!;
                              final double monthlyUsed =
                                  (processed['totalUsage'] ?? 0.0).toDouble();
                              double percentage = (monthlyUsed / maxWaterUsage)
                                  .clamp(0.0, 1.0);

                              final List<double> historyValues =
                                  (processed['monthlyUsageData'] as List? ?? [])
                                      .map(
                                        (e) => (e['value'] as num).toDouble(),
                                      )
                                      .toList()
                                      .reversed
                                      .toList();

                              final hourlyList =
                                  (processed['hourlyUsageData'] as List? ?? [])
                                      .map<ChartDataBar>(
                                        (e) => ChartDataBar(
                                          e['label'],
                                          (e['value'] ?? 0.0).toDouble(),
                                        ),
                                      )
                                      .toList();

                              double currentHourlyUsage = 0.0;
                              try {
                                final nowData = hourlyList.firstWhere(
                                  (element) => element.x == "Now",
                                );
                                currentHourlyUsage = nowData.y;
                              } catch (e) {
                                currentHourlyUsage = 0.0;
                              }

                              return Column(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(20),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.9),
                                      borderRadius: BorderRadius.circular(20),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.blue.withOpacity(0.1),
                                          blurRadius: 10,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: Column(
                                      children: [
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            const Text(
                                              'Monthly Goal',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                              ),
                                            ),
                                            IconButton(
                                              icon: const Icon(
                                                Icons.edit,
                                                size: 18,
                                                color: Colors.grey,
                                              ),
                                              onPressed:
                                                  () => _editWaterLimit(
                                                    maxWaterUsage,
                                                  ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 15),
                                        SizedBox(
                                          height: 200,
                                          width: 200,
                                          child: CustomLiquidWidget(
                                            percentage: percentage,
                                            valueText:
                                                "${(percentage * 100).toStringAsFixed(1)}%",
                                            subText:
                                                "${monthlyUsed.toInt()} / ${maxWaterUsage.toInt()} L",
                                            color:
                                                percentage > 0.8
                                                    ? Colors.orange
                                                    : Colors.blueAccent,
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        if (percentage >= 1.0)
                                          const Text(
                                            "⚠️ Limit Reached!",
                                            style: TextStyle(
                                              color: Colors.red,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          )
                                        else
                                          Text(
                                            "${(maxWaterUsage - monthlyUsed).toStringAsFixed(0)} L Remaining",
                                            style: const TextStyle(
                                              color: Colors.grey,
                                              fontSize: 12,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),

                                  SmartInsightsCard(
                                    currentUsage: waterUsage,
                                    currentBill:
                                        double.tryParse(
                                          totalBill.replaceAll(
                                            RegExp(r'[^0-9\.]'),
                                            '',
                                          ),
                                        ) ??
                                        0.0,
                                    hourlyUsage: currentHourlyUsage,
                                    monthlyUsageHistory: historyValues,
                                  ),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 20),

                          FutureBuilder<Map<String, dynamic>>(
                            future: _chartsFuture,
                            builder: (context, snapshotCharts) {
                              if (!snapshotCharts.hasData)
                                return _buildShimmerLoading();
                              final processed = snapshotCharts.data!;
                              final monthlyUsage =
                                  (processed['monthlyUsageData'] as List? ?? [])
                                      .map<ChartDataBar>(
                                        (e) => ChartDataBar(
                                          e['label'],
                                          (e['value'] ?? 0.0).toDouble(),
                                        ),
                                      )
                                      .toList();
                              final monthlyBill =
                                  (processed['monthlyBillData'] as List? ?? [])
                                      .map<ChartDataBar>(
                                        (e) => ChartDataBar(
                                          e['label'],
                                          (e['value'] ?? 0.0).toDouble(),
                                        ),
                                      )
                                      .toList();

                              return _buildBarChart(
                                'Monthly History (Last 12 Months)',
                                monthlyUsage,
                                monthlyBill,
                                isDual: true,
                                xAxisTitle: 'Month',
                                yAxisTitle: 'Usage / Bill',
                              );
                            },
                          ),
                          const SizedBox(height: 20),

                          FutureBuilder<Map<String, dynamic>>(
                            future: _chartsFuture,
                            builder: (context, snapshotCharts) {
                              if (!snapshotCharts.hasData)
                                return const SizedBox();
                              final processed = snapshotCharts.data!;
                              final weeklyList =
                                  (processed['weeklyUsageData'] as List? ?? [])
                                      .map<ChartDataBar>(
                                        (e) => ChartDataBar(
                                          e['label'],
                                          (e['value'] ?? 0.0).toDouble(),
                                        ),
                                      )
                                      .toList();
                              return _buildBarChart(
                                'Weekly Usage',
                                weeklyList,
                                null,
                                isDual: false,
                                xAxisTitle: 'Day',
                                yAxisTitle: 'Liters',
                              );
                            },
                          ),
                          const SizedBox(height: 20),

                          FutureBuilder<Map<String, dynamic>>(
                            future: _chartsFuture,
                            builder: (context, snapshotCharts) {
                              if (!snapshotCharts.hasData)
                                return const SizedBox();
                              final processed = snapshotCharts.data!;
                              final hourlyList =
                                  (processed['hourlyUsageData'] as List? ?? [])
                                      .map<ChartDataBar>(
                                        (e) => ChartDataBar(
                                          e['label'],
                                          (e['value'] ?? 0.0).toDouble(),
                                        ),
                                      )
                                      .toList();
                              return _buildBarChart(
                                'Hourly Usage',
                                hourlyList,
                                null,
                                isDual: false,
                                xAxisTitle: 'Hour',
                                yAxisTitle: 'Liters',
                                highlightLabel: 'Now',
                              );
                            },
                          ),
                          const SizedBox(height: 20),

                          FutureBuilder<Map<String, dynamic>>(
                            future: _chartsFuture,
                            builder: (context, snapshotCharts) {
                              if (!snapshotCharts.hasData)
                                return _skeletonListContainer();
                              final processed = snapshotCharts.data!;
                              final List uiEntriesRaw =
                                  processed['uiEntries'] as List? ?? [];
                              final bool hasMore =
                                  processed['hasMore'] as bool? ?? false;
                              final uiEntries =
                                  uiEntriesRaw
                                      .map<MapEntry<String, dynamic>>(
                                        (e) => MapEntry<String, dynamic>(
                                          e['key'].toString(),
                                          e['value'],
                                        ),
                                      )
                                      .toList();

                              return Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.9),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'History ($currentMonthName)',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    if (uiEntries.isEmpty)
                                      const Text('No logs yet.')
                                    else
                                      ListView.separated(
                                        shrinkWrap: true,
                                        physics:
                                            const NeverScrollableScrollPhysics(),
                                        itemCount: uiEntries.length,
                                        separatorBuilder:
                                            (_, __) => const Divider(height: 1),
                                        itemBuilder: (context, index) {
                                          final e = uiEntries[index];
                                          final data =
                                              Map<String, dynamic>.from(
                                                e.value as Map,
                                              );
                                          String usageText =
                                              data.containsKey('TotalUsage')
                                                  ? '${(data['TotalUsage'] ?? 0).toDouble().toStringAsFixed(2)} L'
                                                  : '${(data['Water_Usage'] ?? 0).toString()} L';
                                          return ListTile(
                                            contentPadding: EdgeInsets.zero,
                                            title: Text(
                                              usageText,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                              ),
                                            ),
                                            subtitle: Text(
                                              _formatLogKeyForUI(e.key),
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey,
                                              ),
                                            ),
                                            trailing: Text(
                                              data['Display_Bill']
                                                      ?.toString() ??
                                                  '₱0.00',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: Colors.blue,
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    if (hasMore)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 10),
                                        child: Center(
                                          child: Text(
                                            "Show more...",
                                            style: TextStyle(
                                              color: Colors.blue.shade700,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 30),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShimmerLoading() {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade300,
      highlightColor: Colors.grey.shade100,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(width: 150, height: 20, color: Colors.white),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            height: 200,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _skeletonChartContainer({double height = 200}) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.5),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Center(child: CircularProgressIndicator()),
    );
  }

  Widget _skeletonListContainer() {
    return Container(
      height: 100,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.5),
        borderRadius: BorderRadius.circular(20),
      ),
    );
  }

  String _formatLogKeyForUI(String key) {
    try {
      return DateFormat('MMM dd, hh:mm a').format(
        DateTime.parse(
          key.split('_')[0] + ' ' + key.split('_')[1].replaceAll('-', ':'),
        ),
      );
    } catch (e) {
      return key;
    }
  }

  Widget _buildBarChart(
    String title,
    List<ChartDataBar> usageData,
    List<ChartDataBar>? billData, {
    required bool isDual,
    required String xAxisTitle,
    required String yAxisTitle,
    String? highlightLabel,
  }) {
    final List<CartesianSeries<ChartDataBar, String>> seriesList = [
      ColumnSeries<ChartDataBar, String>(
        dataSource: usageData,

        animationDuration: 2000,
        xValueMapper: (ChartDataBar data, _) => data.x,
        yValueMapper: (ChartDataBar data, _) => data.y,
        name: 'Usage',
        color: Colors.blueAccent,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
      ),
    ];
    if (isDual && billData != null) {
      seriesList.add(
        ColumnSeries<ChartDataBar, String>(
          dataSource: billData,
          animationDuration: 2000,
          xValueMapper: (ChartDataBar data, _) => data.x,
          yValueMapper: (ChartDataBar data, _) => data.y,
          name: 'Bill',
          color: Colors.green,
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 200,
            child: SfCartesianChart(
              zoomPanBehavior: ZoomPanBehavior(
                enablePanning: true,
                zoomMode: ZoomMode.x,
              ),
              primaryXAxis: CategoryAxis(
                majorGridLines: const MajorGridLines(width: 0),
                labelStyle: const TextStyle(fontSize: 10),
                autoScrollingDelta: 5,
                autoScrollingMode: AutoScrollingMode.end,
              ),
              primaryYAxis: NumericAxis(
                majorGridLines: const MajorGridLines(
                  width: 0.5,
                  dashArray: [5, 5],
                ),
                axisLine: const AxisLine(width: 0),
              ),
              plotAreaBorderWidth: 0,
              series: seriesList,
              tooltipBehavior: TooltipBehavior(enable: true),
            ),
          ),
        ],
      ),
    );
  }
}

class DeviceStatusWidget extends StatelessWidget {
  final String uid;

  const DeviceStatusWidget({super.key, required this.uid});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DatabaseEvent>(
      stream:
          FirebaseDatabase.instance
              .ref('Users/$uid/Device_Status/last_seen')
              .onValue,
      builder: (context, snapshot) {
        bool isOnline = false;
        String statusText = "Connecting...";

        if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
          try {
            final val = snapshot.data!.snapshot.value;
            int lastSeenMillis = 0;
            if (val is int) lastSeenMillis = val;
            if (val is double) lastSeenMillis = val.toInt();

            final lastSeen = DateTime.fromMillisecondsSinceEpoch(
              lastSeenMillis,
            );
            final now = DateTime.now();
            final difference = now.difference(lastSeen).inSeconds;

            if (difference.abs() < 60) {
              isOnline = true;
              statusText = "Online";
            } else {
              isOnline = false;
              statusText = "Offline";
            }
          } catch (_) {
            statusText = "Error";
          }
        } else {
          statusText = "Offline";
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color:
                isOnline
                    ? Colors.green.withOpacity(0.15)
                    : Colors.red.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isOnline ? Colors.green : Colors.red,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.circle,
                size: 10,
                color: isOnline ? Colors.green : Colors.red,
              ),
              const SizedBox(width: 5),
              Text(
                statusText,
                style: TextStyle(
                  color: isOnline ? Colors.green.shade700 : Colors.red.shade700,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class SmartInsightsCard extends StatelessWidget {
  final double currentUsage;
  final double currentBill;
  final double hourlyUsage;
  final List<double> monthlyUsageHistory;

  const SmartInsightsCard({
    Key? key,
    required this.currentUsage,
    required this.currentBill,
    required this.hourlyUsage,
    required this.monthlyUsageHistory,
  }) : super(key: key);

  double _predictNextMonthUsage() {
    if (monthlyUsageHistory.isEmpty) return currentUsage;

    int n = monthlyUsageHistory.length;
    double sumX = 0;
    double sumY = 0;
    double sumXY = 0;
    double sumXX = 0;

    for (int i = 0; i < n; i++) {
      sumX += i;
      sumY += monthlyUsageHistory[i];
      sumXY += i * monthlyUsageHistory[i];
      sumXX += i * i;
    }

    double slope = (n * sumXY - sumX * sumY) / (n * sumXX - sumX * sumX);
    double intercept = (sumY - slope * sumX) / n;
    double prediction = slope * n + intercept;

    return prediction < 0 ? 0 : prediction;
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final dailyAverage = currentBill / (now.day == 0 ? 1 : now.day);
    final projectedBillCurrent = dailyAverage * daysInMonth;

    final double predictedUsage =
        monthlyUsageHistory.length >= 2
            ? _predictNextMonthUsage()
            : currentUsage;
    final double predictedBillNextMonth = predictedUsage * 0.07;

    final bool potentialLeak = hourlyUsage > 100.0;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors:
              potentialLeak
                  ? [Colors.red.shade50, Colors.red.shade100]
                  : [Colors.indigo.shade50, Colors.blue.shade100],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: potentialLeak ? Colors.red : Colors.indigo.shade200,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            blurRadius: 5,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                potentialLeak ? Icons.warning_amber_rounded : Icons.auto_graph,
                color: potentialLeak ? Colors.red : Colors.indigo[800],
              ),
              const SizedBox(width: 10),
              Text(
                potentialLeak ? "High Usage Alert!" : "Smart Forecast (AI)",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: potentialLeak ? Colors.red[900] : Colors.indigo[900],
                ),
              ),
            ],
          ),
          const Divider(),
          if (potentialLeak) ...[
            Text(
              "⚠️ Abnormal usage detected (${hourlyUsage.toStringAsFixed(1)} L/hr). Check for leaks.",
              style: TextStyle(color: Colors.red[800], fontSize: 13),
            ),
          ] else ...[
            _buildRow(
              "This Month's Forecast:",
              "₱ ${projectedBillCurrent.toStringAsFixed(2)}",
            ),
            const SizedBox(height: 5),
            _buildRow(
              "Next Month Prediction:",
              "₱ ${predictedBillNextMonth.toStringAsFixed(2)}",
              isHighlight: true,
            ),
            const SizedBox(height: 5),
            Text(
              monthlyUsageHistory.length < 2
                  ? "Collecting data for better predictions..."
                  : "Based on your usage trend analysis.",
              style: TextStyle(
                fontSize: 10,
                fontStyle: FontStyle.italic,
                color: Colors.grey[600],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRow(String label, String value, {bool isHighlight = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 13)),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 15,
            color: isHighlight ? Colors.indigo : Colors.black87,
          ),
        ),
      ],
    );
  }
}

class CustomLiquidWidget extends StatefulWidget {
  final double percentage;
  final String valueText;
  final String subText;
  final Color color;

  const CustomLiquidWidget({
    super.key,
    required this.percentage,
    required this.valueText,
    required this.subText,
    required this.color,
  });

  @override
  State<CustomLiquidWidget> createState() => _CustomLiquidWidgetState();
}

class _CustomLiquidWidgetState extends State<CustomLiquidWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );
    _animationController.repeat();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            ClipOval(
              child: CustomPaint(
                painter: WavePainter(
                  animationValue: _animationController.value,
                  percentage: widget.percentage,
                  color: widget.color,
                ),
                size: const Size(200, 200),
              ),
            ),
            Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.blue.withOpacity(0.1),
                  width: 4,
                ),
              ),
            ),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  widget.valueText,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color:
                        widget.percentage > 0.5 ? Colors.white : widget.color,
                  ),
                ),
                Text(
                  widget.subText,
                  style: TextStyle(
                    fontSize: 12,
                    color:
                        widget.percentage > 0.5 ? Colors.white70 : Colors.grey,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class WavePainter extends CustomPainter {
  final double animationValue;
  final double percentage;
  final Color color;

  WavePainter({
    required this.animationValue,
    required this.percentage,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = color
          ..style = PaintingStyle.fill;
    final path = Path();

    final waveHeight = size.height * 0.05;
    final baseHeight = size.height * (1 - percentage);

    path.moveTo(0, baseHeight);
    for (double i = 0; i <= size.width; i++) {
      path.lineTo(
        i,
        baseHeight +
            math.sin(
                  (i / size.width * 2 * math.pi) +
                      (animationValue * 2 * math.pi),
                ) *
                waveHeight,
      );
    }
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant WavePainter oldDelegate) => true;
}
