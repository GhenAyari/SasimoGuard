import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'analytics_view.dart';
import 'all_earthquakes_screen.dart';
import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math' as math;
import 'login_screen.dart'; // Sesuaikan path ini dengan folder lu

// --- THEME COLORS ---
class SeismicColors {
  static const Color navyDark = Color(0xFF0F172A);
  static const Color navyAccent = Color(0xFF1E293B);
  static const Color redAlert = Color(0xFFE11D48);
  static const Color orangeAlert = Color(0xFFF97316);
  static const Color greenAlert = Color(0xFF22C55E);
  static const Color blueLight = Color(0xFF38BDF8);
  static const Color textLight = Color(0xFFF8FAFC);
  static const Color textMuted = Color(0xFF94A3B8);
  static const Color bgLight = Color(0xFFF1F5F9);
}

// --- MODEL DATA ---
class GempaModel {
  final String source;
  final String magnitude;
  final String wilayah;
  final String waktu;
  final String kedalaman;
  final String koordinat;

  GempaModel({
    required this.source,
    required this.magnitude,
    required this.wilayah,
    required this.waktu,
    required this.kedalaman,
    required this.koordinat,
  });
}

// --- NOTIFIKASI PLUGIN (GLOBAL) ---
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

// =============================================================================
// PUBLIC SCREEN — Root + EWS Radar
// =============================================================================
class PublicScreen extends StatefulWidget {
  const PublicScreen({super.key});

  @override
  State<PublicScreen> createState() => _PublicScreenState();
}

class _PublicScreenState extends State<PublicScreen> {
  int _selectedIndex = 0;
  late final RealtimeChannel _ewsChannel;
  Position? _userPosition;
  final Set<String> _gempaSudahDinotif = {}; // <-- TAMBAHAN BARU

  final List<Widget> _pages = [
    const DashboardView(),
    const LiveMapView(),
    const AnalyticsView(),
  ];

  @override
  void initState() {
    super.initState();
    _initEWS();
  }

  @override
  void dispose() {
    Supabase.instance.client.removeChannel(_ewsChannel);
    super.dispose();
  }

  Future<void> _initEWS() async {
    // 1. Setup plugin notifikasi
    const AndroidInitializationSettings androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    await flutterLocalNotificationsPlugin.initialize(
      const InitializationSettings(android: androidInit),
    );

// Minta izin notifikasi Android 13+
    final AndroidFlutterLocalNotificationsPlugin? androidPlugin =
        flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation< 
                AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      await androidPlugin.requestNotificationsPermission();
    }

    // 2. Ambil lokasi user
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always) {
      _userPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
    }

    // 3. Hidupkan radar realtime Supabase
    _ewsChannel = Supabase.instance.client
        .channel('public:gempa_live')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'gempa_live',
          callback: (payload) => _processEWSAlert(payload.newRecord),
        )
        .subscribe();
  }

  // --- TIMPA FUNGSI INI SAJA ---
  Future<void> _processEWSAlert(Map<String, dynamic> data) async {
    // 1. Panggil memori jangka panjang (SharedPreferences)
    final prefs = await SharedPreferences.getInstance();
    List<String> notifiedList = prefs.getStringList('history_notif_gempa') ?? [];

    String idUnikGempa = "${data['waktu']}_${data['wilayah']}";

    // 2. Kalau gempa ini udah pernah dinotif, hentikan proses (Biar gak spam!)
    if (notifiedList.contains(idUnikGempa)) {
      return; 
    }

    // Masukkan ke ingatan permanen (Dibatasi 50 gempa biar memori HP gak penuh)
    notifiedList.add(idUnikGempa);
    if (notifiedList.length > 50) notifiedList.removeAt(0);
    await prefs.setStringList('history_notif_gempa', notifiedList);

    // 3. Ekstrak data
    double mag = double.tryParse(data['magnitude'].toString()) ?? 0;
    String wilayah = data['wilayah'] ?? 'Lokasi tidak diketahui';
    String koordinat = data['koordinat'] ?? '';
    double distanceKm = 9999.0;

    if (_userPosition != null && koordinat.isNotEmpty) {
      List<String> coords = koordinat.split(',');
      if (coords.length == 2) {
        double quakeLat = double.tryParse(coords[0]) ?? 0;
        double quakeLng = double.tryParse(coords[1]) ?? 0;
        distanceKm = Geolocator.distanceBetween(
              _userPosition!.latitude,
              _userPosition!.longitude,
              quakeLat,
              quakeLng,
            ) / 1000; // meter -> km
      }
    }

    // 4. Aturan EWS (Jarak sudah dikembalikan ke 300km yang logis)
    bool isNear = distanceKm <= 300.0; 
    bool isDangerous = mag >= 5.0;

    // Bikin ID Notifikasi unik per gempa biar muncul semua dan gak saling timpa
    int notifId = idUnikGempa.hashCode;

    if (isNear && isDangerous) {
      await _showNotification(
        id: notifId, 
        title: '⚠️ AWAS! GEMPA KUAT DEKAT ANDA',
        body: 'M $mag terdeteksi ${distanceKm.toStringAsFixed(0)} km dari Anda. BERLINDUNG!',
        isUrgent: true,
      );
    } else if (isNear && !isDangerous) {
      await _showNotification(
        id: notifId,
        title: 'ℹ️ Info: Gempa Terasa',
        body: 'Gempa M $mag berjarak ${distanceKm.toStringAsFixed(0)} km dari anda di $wilayah.',
        isUrgent: false,
      );
    } else if (!isNear && isDangerous) {
      await _showNotification(
        id: notifId,
        title: 'Peringatan Gempa Jauh',
        body: 'Gempa kuat M $mag terjadi di $wilayah.',
        isUrgent: false,
      );
    } else {
      // --- TAMBAHIN BLOK ELSE INI BUAT TESTING ---
      await _showNotification(
        id: notifId,
        title: 'Info Minor',
        body: 'Gempa kecil M $mag jarak ${distanceKm.toStringAsFixed(0)} km dari anda di $wilayah.',
        isUrgent: false,
      );
    }
  }

Future<void> _showNotification({
    required int id,
    required String title,
    required String body,
    required bool isUrgent,
  }) async {
    // INI KUNCI RAHASIANYA: FLAG_INSISTENT (Angka 4)
    // Bikin notifikasi bunyi dan getar terus-terusan kayak alarm beneran!
    final Int32List insistentFlag = Int32List.fromList(<int>[4]);

    final AndroidNotificationDetails urgentChannel = AndroidNotificationDetails(
      'ews_urgent_channel_v3', // Ganti ID lagi biar Android ngereset settingan
      'Peringatan Darurat',
      channelDescription: 'Alarm gempa jarak dekat & kuat',
      importance: Importance.max,
      priority: Priority.max,
      color: Colors.red,
      enableVibration: true,
      playSound: true,
      fullScreenIntent: true,
      category: AndroidNotificationCategory.alarm,
      audioAttributesUsage: AudioAttributesUsage.alarm,
      additionalFlags: insistentFlag, // <-- PASANG DI SINI
    );

    const AndroidNotificationDetails normalChannel = AndroidNotificationDetails(
      'ews_info_channel',
      'Info Gempa',
      channelDescription: 'Pemberitahuan gempa jarak jauh atau lemah',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      color: Colors.blue,
      playSound: false,
    );

    await flutterLocalNotificationsPlugin.show(
      id,
      title,
      body,
      NotificationDetails(android: isUrgent ? urgentChannel : normalChannel),
    );
  }

  // Modal test skenario EWS
  void _showTestModal() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Test Skenario EWS',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: SeismicColors.navyDark,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Pilih skenario untuk melihat notifikasi sistem muncul.',
                textAlign: TextAlign.center,
                style: TextStyle(color: SeismicColors.textMuted),
              ),
              const SizedBox(height: 24),

              // Skenario 1: Dekat + Kuat = Alarm merah
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: SeismicColors.redAlert,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.warning_rounded, color: Colors.white),
                label: const Text(
                  'Simulasi: Dekat & Kuat (ALARM)',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                onPressed: () {
                  Navigator.pop(context);
                  _showNotification(
                    id: 991,
                    title: '⚠️ AWAS! GEMPA KUAT DEKAT ANDA',
                    body:
                        'M 6.8 terdeteksi sejauh 45 km. BERLINDUNG SEKARANG!',
                    isUrgent: true,
                  );
                },
              ),
              const SizedBox(height: 12),

              // Skenario 2: Dekat + Lemah = Info orange
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: SeismicColors.orangeAlert,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.info_rounded, color: Colors.white),
                label: const Text(
                  'Simulasi: Dekat & Lemah (INFO)',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                onPressed: () {
                  Navigator.pop(context);
                  _showNotification(
                    id: 992,
                    title: 'ℹ️ Info: Gempa Terasa',
                    body: 'Gempa M 3.2 berjarak 12 km dari lokasi Anda.',
                    isUrgent: false,
                  );
                },
              ),
              const SizedBox(height: 12),

              // Skenario 3: Jauh + Kuat = Info biru
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: SeismicColors.blueLight,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.public_rounded, color: Colors.white),
                label: const Text(
                  'Simulasi: Jauh & Kuat (INFO)',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                onPressed: () {
                  Navigator.pop(context);
                  _showNotification(
                    id: 993,
                    title: 'Peringatan Gempa Jauh',
                    body: 'Gempa kuat M 7.5 terjadi di Jepang.',
                    isUrgent: false,
                  );
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SeismicColors.bgLight,
      body: _pages[_selectedIndex],
      floatingActionButton: FloatingActionButton(
        onPressed: _showTestModal,
        backgroundColor: SeismicColors.navyDark,
        elevation: 4,
        child: const Icon(Icons.bug_report_rounded, color: Colors.white),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        backgroundColor: Colors.white,
        selectedItemColor: Colors.blueAccent,
        unselectedItemColor: SeismicColors.textMuted,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_rounded),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.map_outlined),
            label: 'Live Map',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.analytics_outlined),
            label: 'Analytics',
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// DASHBOARD VIEW — SAMA PERSIS DENGAN VERSI LU, TIDAK DIUBAH
// =============================================================================
class DashboardView extends StatefulWidget {
  const DashboardView({super.key});

  @override
  State<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<DashboardView> {
  late Future<Map<String, dynamic>?> _bmkgFuture;
  late Future<List<GempaModel>> _recentFuture;

  @override
  void initState() {
    super.initState();
    _refreshData();
  }

  Future<void> _refreshData() async {
    setState(() {
      _bmkgFuture = _fetchBMKGLatest();
      _recentFuture = _fetchAllSeismicData();
    });
    await Future.wait([
      _bmkgFuture,
      _recentFuture.catchError((_) => <GempaModel>[]),
    ]);
  }

  Future<Map<String, dynamic>?> _fetchBMKGLatest() async {
    try {
      final response = await http.get(
        Uri.parse('https://data.bmkg.go.id/DataMKG/TEWS/autogempa.json'),
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['Infogempa']['gempa'];
      }
    } catch (e) {
      debugPrint('Error BMKG Latest: $e');
    }
    return null;
  }

  Future<List<GempaModel>> _fetchAllSeismicData() async {
    try {
      final response = await Supabase.instance.client
          .from('gempa_live')
          .select('*')
          .order('waktu', ascending: false)
          .limit(20);

      List<GempaModel> combinedData = [];
      for (var item in response) {
        combinedData.add(GempaModel(
          source: item['source'] ?? 'Unknown',
          magnitude: item['magnitude'].toString(),
          wilayah: item['wilayah'] ?? '-',
          waktu: item['waktu'] ?? '-',
          kedalaman: item['kedalaman']?.toString() ?? '-',
          koordinat: item['koordinat']?.toString() ?? '-',
        ));
      }
      return combinedData;
    } catch (e) {
      debugPrint("Supabase Fetch Error: $e");
      return [];
    }
  }

  void _showDetailModal(GempaModel item, Color magColor) {
    String lat = '-';
    String lng = '-';
    if (item.koordinat != '-' && item.koordinat.isNotEmpty) {
      List<String> coords = item.koordinat.split(',');
      if (coords.length == 2) {
        lat = coords[0].trim();
        lng = coords[1].trim();
      }
    }

    double mag = double.tryParse(item.magnitude) ?? 0;
    String kategori = 'Minor';
    if (mag >= 6.0) kategori = 'Gempa Kuat/Besar';
    else if (mag >= 5.0) kategori = 'Gempa Sedang';
    else if (mag >= 4.0) kategori = 'Gempa Terasa';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      color: magColor,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      item.magnitude,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 24,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.waktu,
                          style: const TextStyle(
                            color: SeismicColors.textMuted,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.wilayah,
                          style: const TextStyle(
                            color: SeismicColors.navyDark,
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                          ),
                          maxLines: 3,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),
              Row(
                children: [
                  _buildDetailItem(Icons.waves_rounded, 'Kedalaman', '${item.kedalaman} km'),
                  _buildDetailItem(Icons.warning_rounded, 'Kategori', kategori),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _buildDetailItem(Icons.my_location_rounded, 'Koordinat', '$lat, $lng'),
                  _buildDetailItem(Icons.source_rounded, 'Sumber', item.source),
                ],
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: SeismicColors.navyDark,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Tutup Detail',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDetailItem(IconData icon, String label, String value) {
    return Expanded(
      child: Row(
        children: [
          Icon(icon, color: SeismicColors.blueLight, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        color: SeismicColors.textMuted, fontSize: 12)),
                Text(value,
                    style: const TextStyle(
                        color: SeismicColors.navyDark,
                        fontWeight: FontWeight.w700,
                        fontSize: 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refreshData,
      color: SeismicColors.navyDark,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverAppBar(
            floating: true,
            backgroundColor: Colors.white,
            elevation: 0,
           leading: IconButton( // <-- Ganti jadi IconButton
              icon: const Icon(Icons.door_back_door_sharp, color: SeismicColors.navyDark),
              onPressed: () {
                // Arahkan ke halaman Login
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const LoginScreen()),
                );
              },
            ),
            title: const Text(
              'SASIMOK GUARD',
              style: TextStyle(
                color: SeismicColors.navyDark,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
              ),
            ),
            centerTitle: true,
            actions: [
              IconButton(
                icon: const Icon(Icons.notifications_none_rounded,
                    color: SeismicColors.navyDark),
                onPressed: () {},
              ),
            ],
          ),
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // ALERT BANNER
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: SeismicColors.redAlert,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          color: Colors.white, size: 28),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('EWS Aktif',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16)),
                            Text(
                                'Sistem notifikasi gempa wilayah aktif bekerja.',
                                style: TextStyle(
                                    color: Colors.white70, fontSize: 13)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),
                const Text(
                  'INFO GEMPA TERBARU (BMKG)',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: SeismicColors.textMuted,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 12),

                FutureBuilder<Map<String, dynamic>?>(
                  future: _bmkgFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const SizedBox(
                        height: 200,
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (!snapshot.hasData || snapshot.data == null) {
                      return const Card(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('Gagal memuat data BMKG'),
                        ),
                      );
                    }

                    final bmkg = snapshot.data!;
                    double mag =
                        double.tryParse(bmkg['Magnitude'] ?? '0') ?? 0;
                    Color badgeColor = mag >= 5.0
                        ? SeismicColors.redAlert
                        : SeismicColors.orangeAlert;
                    String badgeText = mag >= 5.0 ? 'STRONG' : 'MODERATE';

                    return Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          Stack(
                            children: [
                              Image.network(
                                'https://data.bmkg.go.id/DataMKG/TEWS/${bmkg['Shakemap']}',
                                height: 200,
                                width: double.infinity,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stack) =>
                                    Container(
                                  height: 200,
                                  color: SeismicColors.navyDark,
                                  child: const Center(
                                    child: Text(
                                      'Peta tidak tersedia',
                                      style: TextStyle(color: Colors.white),
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 12,
                                left: 12,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: badgeColor,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    badgeText,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Container(
                                  width: 60,
                                  height: 60,
                                  decoration: BoxDecoration(
                                    color: badgeColor,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    bmkg['Magnitude'],
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        bmkg['Wilayah'],
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: SeismicColors.navyDark,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        'Kedalaman: ${bmkg['Kedalaman']} • ${bmkg['Jam']}',
                                        style: const TextStyle(
                                          color: SeismicColors.textMuted,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),

                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'AKTIVITAS GEMPA GLOBAL',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: SeismicColors.textMuted,
                        letterSpacing: 1,
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const AllEarthquakesScreen(),
                        ),
                      ),
                      child: const Text(
                        'View All',
                        style: TextStyle(
                            color: Colors.blue, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),

                FutureBuilder<List<GempaModel>>(
                  future: _recentFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return const Center(
                          child: Text('Gagal sinkronisasi API.'));
                    }

                    return Column(
                      children: snapshot.data!.map((gempa) {
                        Color color = SeismicColors.greenAlert;
                        double magVal =
                            double.tryParse(gempa.magnitude) ?? 0;
                        if (magVal >= 5.0) {
                          color = SeismicColors.redAlert;
                        } else if (magVal >= 4.0) {
                          color = SeismicColors.orangeAlert;
                        }

                        Widget sourceBadge = Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: gempa.source == 'BMKG'
                                ? Colors.blue
                                : (gempa.source == 'USGS'
                                    ? Colors.purple
                                    : Colors.teal),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            gempa.source,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        );

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => _showDetailModal(gempa, color),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  Container(
                                    width: 50,
                                    height: 50,
                                    decoration: BoxDecoration(
                                      color: color,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      gempa.magnitude,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          gempa.wilayah,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: SeismicColors.navyDark,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            sourceBadge,
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                '${gempa.waktu} • Kedalaman: ${gempa.kedalaman} km',
                                                style: const TextStyle(
                                                  color:
                                                      SeismicColors.textMuted,
                                                  fontSize: 12,
                                                ),
                                                overflow:
                                                    TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.chevron_right_rounded,
                                      color: SeismicColors.textMuted),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
                const SizedBox(height: 30),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

/// =============================================================================
// LIVE MAP VIEW (DENGAN MARKER POSKO + MODAL DETAIL)
// =============================================================================
class LiveMapView extends StatefulWidget {
  const LiveMapView({super.key});

  @override
  State<LiveMapView> createState() => _LiveMapViewState();
}

class _LiveMapViewState extends State<LiveMapView> {
  List<Marker> _gempaMarkers = [];
  List<Marker> _poskoMarkers = []; 
  List<CircleMarker> _circles = [];
  bool _isLoading = true;
  bool _isRefreshing = false;
  Map<String, dynamic>? _selectedQuake;

  @override
  void initState() {
    super.initState();
    _loadMapData();
  }

  Future<void> _loadMapData({bool isRefresh = false}) async {
    if (_isRefreshing) return;

    setState(() {
      if (isRefresh) {
        _isRefreshing = true;
      } else {
        _isLoading = true;
      }
      _selectedQuake = null;
    });

    try {
      // 1. Tarik Data Gempa
      final gempaResponse =
          await Supabase.instance.client.from('gempa_live').select('*');

      // 2. Tarik Data Posko
      final poskoResponse = 
          await Supabase.instance.client.from('posko_evakuasi').select('*');

      List<Marker> newGempaMarkers = [];
      List<Marker> newPoskoMarkers = [];
      List<CircleMarker> newCircles = [];

      // Proses Data Gempa
      for (var item in gempaResponse) {
        if (item['koordinat'] != null) {
          List<String> coords = item['koordinat'].toString().split(',');
          if (coords.length == 2) {
            double lat = double.tryParse(coords[0]) ?? 0;
            double lng = double.tryParse(coords[1]) ?? 0;
            double mag = item['magnitude'] != null
                ? double.tryParse(item['magnitude'].toString()) ?? 0
                : 0;

            Color markerColor = SeismicColors.greenAlert;
            if (mag >= 5.0) markerColor = SeismicColors.redAlert;
            else if (mag >= 4.0) markerColor = SeismicColors.orangeAlert;

            final Map<String, dynamic> itemCopy =
                Map<String, dynamic>.from(item);

            newCircles.add(
              CircleMarker(
                point: LatLng(lat, lng),
                color: markerColor.withValues(alpha: 0.25), 
                borderColor: markerColor, 
                borderStrokeWidth: 2,
                useRadiusInMeter: true, 
                radius: math.pow(mag, 1.5) * 2500, 
              ),
            );

            newGempaMarkers.add(
              Marker(
                point: LatLng(lat, lng),
                width: 40,
                height: 40,
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      if (_selectedQuake != null &&
                          _selectedQuake!['koordinat'] ==
                              itemCopy['koordinat']) {
                        _selectedQuake = null;
                      } else {
                        _selectedQuake = {
                          ...itemCopy,
                          '_markerColor': markerColor,
                          '_mag': mag,
                        };
                      }
                    });
                  },
                  child:
                      Icon(Icons.location_on, color: markerColor, size: 35),
                ),
              ),
            );
          }
        }
      }

      // Proses Data Posko Evakuasi
      for (var posko in poskoResponse) {
        if (posko['koordinat'] != null) {
          List<String> coords = posko['koordinat'].toString().split(',');
          if (coords.length == 2) {
            double lat = double.tryParse(coords[0]) ?? 0;
            double lng = double.tryParse(coords[1]) ?? 0;
            final poskoCopy = Map<String, dynamic>.from(posko);

            newPoskoMarkers.add(
              Marker(
                point: LatLng(lat, lng),
                width: 60,
                height: 60,
                child: GestureDetector(
                  onTap: () => _showPoskoDetail(poskoCopy), 
                  child: Column(
                    children: [
                      const Icon(Icons.health_and_safety,
                          color: Colors.blue, size: 28), 
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 2),
                        decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4),
                            boxShadow: const [
                              BoxShadow(
                                  color: Colors.black26, blurRadius: 4)
                            ]),
                        child: Text(
                          (posko['nama_posko'] ?? '').toString().length > 10
                              ? (posko['nama_posko'] ?? '')
                                      .toString()
                                      .substring(0, 10) +
                                  '...'
                              : (posko['nama_posko'] ?? '').toString(),
                          style: const TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                              color: SeismicColors.navyDark),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }
        }
      }

      setState(() {
        _gempaMarkers = newGempaMarkers;
        _poskoMarkers = newPoskoMarkers; 
        _circles = newCircles; 
        _isLoading = false;
        _isRefreshing = false;
      });
    } catch (e) {
      debugPrint("Error Map: $e");
      setState(() {
        _isLoading = false;
        _isRefreshing = false;
      });
    }
  }

  void _showPoskoDetail(Map<String, dynamic> posko) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                const Icon(Icons.health_and_safety, color: Colors.blue, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    posko['nama_posko'] ?? 'Posko Evakuasi',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: SeismicColors.navyDark),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),
            if (posko['keterangan'] != null &&
                posko['keterangan'].toString().isNotEmpty) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_rounded, size: 18, color: SeismicColors.textMuted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      posko['keterangan'],
                      style: const TextStyle(color: SeismicColors.navyDark, fontSize: 14),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                const Icon(Icons.my_location_rounded, size: 18, color: SeismicColors.textMuted),
                const SizedBox(width: 8),
                Text(posko['koordinat'] ?? '-', style: const TextStyle(color: SeismicColors.textMuted, fontSize: 13)),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  backgroundColor: SeismicColors.bgLight,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Tutup', style: TextStyle(color: SeismicColors.navyDark, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    return Stack(
      children: [
        GestureDetector(
          onTap: () => setState(() => _selectedQuake = null),
          child: FlutterMap(
            options: const MapOptions(
              initialCenter: LatLng(-2.5489, 118.0149),
              initialZoom: 4.5,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.sasimokguard.app',
              ),
              CircleLayer(circles: _circles),
              MarkerLayer(markers: _gempaMarkers), 
              MarkerLayer(markers: _poskoMarkers), 
            ],
          ),
        ),

        Positioned(
          top: 60,
          left: 20,
          right: 20,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.95),
              borderRadius: BorderRadius.circular(30),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 10,
                  offset: Offset(0, 5),
                ),
              ],
            ),
            child: Row(
              children: [
                const Icon(Icons.satellite_alt_rounded, color: SeismicColors.navyDark),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${_gempaMarkers.length} Titik Gempa • ${_poskoMarkers.length} Posko',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: SeismicColors.navyDark,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => _loadMapData(isRefresh: true),
                  child: AnimatedRotation(
                    turns: _isRefreshing ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 600),
                    child: Icon(
                      Icons.refresh_rounded,
                      color: _isRefreshing ? SeismicColors.textMuted : SeismicColors.navyDark,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        AnimatedPositioned(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          bottom: _selectedQuake != null ? 24 : -220,
          left: 16,
          right: 16,
          child: _selectedQuake == null
              ? const SizedBox.shrink()
              : _buildInfoPanel(_selectedQuake!),
        ),
      ],
    );
  }

  Widget _buildInfoPanel(Map<String, dynamic> quake) {
    final Color color = quake['_markerColor'] as Color;
    final double mag = quake['_mag'] as double;
    final String source = quake['source'] ?? 'Unknown';
    final String wilayah = quake['wilayah'] ?? '-';
    final String waktu = quake['waktu'] ?? '-';
    final String kedalaman = quake['kedalaman'] ?? '-';

    Color sourceBadgeColor = Colors.blue;
    if (source == 'USGS') sourceBadgeColor = Colors.purple;
    else if (source == 'EMSC') sourceBadgeColor = Colors.teal;

    return Material(
      elevation: 12,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border(left: BorderSide(color: color, width: 5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    mag.toStringAsFixed(1),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        wilayah,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: SeismicColors.navyDark,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: sourceBadgeColor,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          source,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() => _selectedQuake = null),
                  child: const Icon(Icons.close_rounded,
                      color: SeismicColors.textMuted),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Row(
              children: [
                _infoChip(Icons.access_time_rounded, waktu),
                const SizedBox(width: 16),
                _infoChip(Icons.layers_rounded, kedalaman),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoChip(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: SeismicColors.textMuted),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(
                color: SeismicColors.textMuted, fontSize: 12)),
      ],
    );
  }
}