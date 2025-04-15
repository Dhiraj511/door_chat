import 'package:english_words/english_words.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print('🔙 Background message received: ${message.messageId}');
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool isDarkMode = false;

  @override
  void initState() {
    super.initState();
    _initNotifications();
  }

  void _initNotifications() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;

    NotificationSettings settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    print('🔐 Permission: ${settings.authorizationStatus}');

    String? token = await messaging.getToken();
    print('📲 FCM Token: $token');

    await messaging.subscribeToTopic("alerts");

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('📩 Foreground notification: ${message.notification?.title}');
      print('📝 Message data: ${message.data}');
    });

    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) {
        print("🚀 Opened from terminated state with: ${message.notification?.title}");
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print("📲 Notification clicked while in background: ${message.notification?.title}");
    });
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => MyAppState(),
      child: MaterialApp(
        title: 'Detection App',
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.light,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.light,
          ),
        ),
        darkTheme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.dark,
          ),
        ),
        themeMode: isDarkMode ? ThemeMode.dark : ThemeMode.light,
        home: MyHomePage(
          onToggleTheme: () {
            setState(() {
              isDarkMode = !isDarkMode;
            });
          },
        ),
      ),
    );
  }
}

class MyAppState extends ChangeNotifier {
  var current = WordPair.random();
}

class MyHomePage extends StatelessWidget {
  final VoidCallback onToggleTheme;
  const MyHomePage({super.key, required this.onToggleTheme});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Smart Surveillance'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.dashboard), text: "Dashboard"),
              Tab(icon: Icon(Icons.history), text: "History"),
            ],
          ),
          actions: [
            IconButton(
              icon: Icon(Icons.brightness_6),
              onPressed: onToggleTheme,
            ),
          ],
        ),
        body: TabBarView(
          children: [
            DashboardScreen(),
            HistoryScreen(),
          ],
        ),
      ),
    );
  }
}

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  Future<Map<String, int>> _getDailyStats() async {
    final snapshot = await FirebaseFirestore.instance.collection('detections').get();
    Map<String, int> counts = {};

    for (var doc in snapshot.docs) {
      final data = doc.data();
      if (data.containsKey('time')) {
        DateTime dt = DateTime.parse(data['time']).toLocal();
        String day = DateFormat('MMM d').format(dt);
        counts[day] = (counts[day] ?? 0) + 1;
      }
    }

    return counts;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildDashboardButton(context, Icons.remove_red_eye, "Live Feed", () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => LiveFeedScreen()));
              }),
              _buildDashboardButton(context, Icons.tune, "Controls", () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => ControlsScreen()));
              }),
            ],
          ),
          const SizedBox(height: 30),
          Text("Last 7 Days Activity", style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          FutureBuilder<Map<String, int>>(
            future: _getDailyStats(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) return CircularProgressIndicator();
              if (!snapshot.hasData || snapshot.data!.isEmpty) return Text("No data");
              final data = snapshot.data!;

              final List<BarChartGroupData> barGroups = [];
              int x = 0;
              data.entries.toList().asMap().forEach((index, entry) {
                barGroups.add(
                  BarChartGroupData(x: x++, barRods: [BarChartRodData(toY: entry.value.toDouble(), color: Colors.blue)]),
                );
              });

              return SizedBox(
                height: 200,
                child: BarChart(
                  BarChartData(
                    barGroups: barGroups,
                    titlesData: FlTitlesData(
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (value, _) => Text(data.keys.elementAt(value.toInt()), style: TextStyle(fontSize: 10)),
                        ),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(showTitles: true, reservedSize: 30),
                      ),
                    ),
                  ),
                ),
              );
            },
          )
        ],
      ),
    );
  }

  Widget _buildDashboardButton(BuildContext context, IconData icon, String label, VoidCallback onTap) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 32),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 36),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontSize: 16))
        ],
      ),
    );
  }
}

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  String formatDateTime(String isoTime) {
    try {
      final dt = DateTime.parse(isoTime).toLocal();
      return DateFormat("MMM d, h:mm a").format(dt);
    } catch (e) {
      return "Invalid date";
    }
  }

  void _clearAllDetections(BuildContext context) async {
    final snapshots = await FirebaseFirestore.instance.collection('detections').get();
    for (var doc in snapshots.docs) {
      await doc.reference.delete();
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("🧹 All detections cleared")),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: ElevatedButton.icon(
            icon: Icon(Icons.delete_forever),
            label: Text("Clear History"),
            onPressed: () => _clearAllDetections(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('detections').orderBy('time', descending: true).snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) return Center(child: Text('❌ Error loading data'));
              if (snapshot.connectionState == ConnectionState.waiting) return Center(child: CircularProgressIndicator());

              final detections = snapshot.data!.docs;
              if (detections.isEmpty) return Center(child: Text("No detections yet 👀"));

              return ListView.builder(
                padding: EdgeInsets.all(16),
                itemCount: detections.length,
                itemBuilder: (context, index) {
                  final data = detections[index].data() as Map<String, dynamic>;
                  final isoTime = data['time'] ?? '';

                  return Container(
                    margin: EdgeInsets.only(bottom: 12),
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.light
                          ? Colors.orange.shade100
                          : Colors.deepOrange.shade900.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 6,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                    child: ListTile(
                      leading: Icon(Icons.person, color: Colors.deepOrange),
                      title: Text("🧍 Person Detected", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                      subtitle: Text("⏱️ ${formatDateTime(isoTime)}",
                          style: TextStyle(fontSize: 14, fontStyle: FontStyle.italic)),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class LiveFeedScreen extends StatelessWidget {
  const LiveFeedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Live Feed")),
      body: Center(
        child: Image.network(
          'http://your-pi-ip:8080', // Replace with your Pi MJPEG stream
          errorBuilder: (context, error, stackTrace) => Text("🔌 Unable to load feed"),
        ),
      ),
    );
  }
}

class ControlsScreen extends StatelessWidget {
  const ControlsScreen({super.key});

  void _sendCommand(String action, BuildContext context) async {
    await FirebaseFirestore.instance.collection('control').doc('detection').set({
      'status': action,
      'timestamp': DateTime.now().toIso8601String()
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("📡 Sent command: $action")),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Controls")),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            ElevatedButton.icon(
              onPressed: () => _sendCommand("start", context),
              icon: Icon(Icons.play_arrow),
              label: Text("Start Detection"),
            ),
            SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => _sendCommand("stop", context),
              icon: Icon(Icons.stop),
              label: Text("Stop Detection"),
            ),
          ],
        ),
      ),
    );
  }
}
