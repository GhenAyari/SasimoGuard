import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:math' as math;
import 'login_screen.dart';

class AdminColors {
  static const Color navyDark = Color(0xFF0F172A);
  static const Color navyAccent = Color(0xFF1E293B);
  static const Color redAlert = Color(0xFFE11D48);
  static const Color orangeAlert = Color(0xFFF97316);
  static const Color greenAlert = Color(0xFF22C55E);
  static const Color blueLight = Color(0xFF38BDF8);
  static const Color textMuted = Color(0xFF94A3B8);
  static const Color bgLight = Color(0xFFF1F5F9);
  static const Color poskoBlue = Color(0xFF3B82F6);
}

// =============================================================================
// ADMIN SCREEN — ROOT
// =============================================================================
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  int _selectedIndex = 0;

  final List<Widget> _pages = [
    const AdminDashboardView(),
    const AdminLiveMapView(),
    const AdminAnalyticsView(),
  ];

  Future<void> _logout() async {
    await Supabase.instance.client.auth.signOut();
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'SASIMOK COMMAND CENTER',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
        ),
        backgroundColor: AdminColors.navyDark,
        foregroundColor: Colors.white,
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
            tooltip: 'Logout',
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Keluar dari Command Center?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Batal'),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red),
                      onPressed: _logout,
                      child: const Text('Logout',
                          style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: _pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        selectedItemColor: AdminColors.poskoBlue,
        unselectedItemColor: AdminColors.textMuted,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.dashboard_rounded), label: 'Dashboard'),
          BottomNavigationBarItem(
              icon: Icon(Icons.map_outlined), label: 'Admin Map'),
          BottomNavigationBarItem(
              icon: Icon(Icons.analytics_outlined), label: 'Analytics'),
        ],
      ),
    );
  }
}

// =============================================================================
// ADMIN DASHBOARD — LIST GEMPA + EDIT/HAPUS (WITH INFINITE SCROLL & DWH GOLD)
// =============================================================================
class AdminDashboardView extends StatefulWidget {
  const AdminDashboardView({super.key});

  @override
  State<AdminDashboardView> createState() => _AdminDashboardViewState();
}

class _AdminDashboardViewState extends State<AdminDashboardView> {
  List<dynamic> _earthquakes = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMoreData = true;
  int _totalDataTersedia = 0;

  // Variabel Pagination & Search
  final int _limit = 15;
  int _offset = 0;
  String _searchQuery = "";

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchData(isRefresh: true);

    // Listener buat Infinite Scroll (Load more pas di-scroll ke bawah)
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 200) {
        if (!_isLoadingMore && _hasMoreData) {
          _fetchData(isRefresh: false);
        }
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearch(String value) {
    setState(() {
      _searchQuery = value;
    });
    _fetchData(isRefresh: true);
  }

  Future<void> _fetchData({required bool isRefresh}) async {
    if (isRefresh) {
      _offset = 0;
      _hasMoreData = true;
      setState(() => _isLoading = true);
    } else {
      setState(() => _isLoadingMore = true);
    }

    try {
      // 1. CARI TOTAL DATA (NATIVE COUNT) DI DWH GOLD
      var countBuilder = Supabase.instance.client
          .schema('gold')
          .from('gold_gempa_analytics')
          .count(CountOption.exact);

      if (_searchQuery.isNotEmpty) {
        countBuilder = countBuilder.ilike('wilayah', '%$_searchQuery%');
      }
      final int totalCount = await countBuilder;

      // 2. TARIK DATA ASLI PAKE LIMIT 15
      var dataQuery = Supabase.instance.client
          .schema('gold')
          .from('gold_gempa_analytics')
          .select('*');

      if (_searchQuery.isNotEmpty) {
        dataQuery = dataQuery.ilike('wilayah', '%$_searchQuery%');
      }

      final data = await dataQuery
          .order('id_fakta', ascending: false)
          .range(_offset, _offset + _limit - 1);

      setState(() {
        _totalDataTersedia = totalCount;
        if (isRefresh) {
          _earthquakes = data;
        } else {
          _earthquakes.addAll(data);
        }

        _offset += data.length;
        if (data.length < _limit) {
          _hasMoreData = false;
        }

        _isLoading = false;
        _isLoadingMore = false;
      });
    } catch (e) {
      debugPrint('Error fetch admin: $e');
      setState(() {
        _isLoading = false;
        _isLoadingMore = false;
      });
    }
  }

  Color _magColor(double mag) {
    if (mag >= 5.0) return AdminColors.redAlert;
    if (mag >= 4.0) return AdminColors.orangeAlert;
    return AdminColors.greenAlert;
  }

  void _showEditModal(Map<String, dynamic> item) {
    final magCtrl = TextEditingController(text: item['magnitude']?.toString() ?? '');
    final wilayahCtrl = TextEditingController(text: item['wilayah']?.toString() ?? '');
    final kedalamanCtrl = TextEditingController(text: item['kedalaman']?.toString() ?? '');
    final waktuCtrl = TextEditingController(text: item['waktu']?.toString() ?? '');
    
    // Gabung Lat & Lng jadi satu string koordinat buat di-edit
    final String latLng = '${item['latitude'] ?? ''}, ${item['longitude'] ?? ''}';
    final koordinatCtrl = TextEditingController(text: latLng);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          left: 24, right: 24, top: 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(Icons.edit_rounded, color: AdminColors.poskoBlue),
                  const SizedBox(width: 8),
                  const Text('Edit Data Gempa', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AdminColors.navyDark)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.delete_rounded, color: AdminColors.redAlert),
                    // Menggunakan id_fakta sebagai referensi id aslinya
                    onPressed: () => _confirmDelete(context, item['id_fakta']),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _inputField(magCtrl, 'Magnitude', Icons.waves_rounded),
              const SizedBox(height: 12),
              _inputField(wilayahCtrl, 'Wilayah', Icons.location_on_rounded),
              const SizedBox(height: 12),
              _inputField(kedalamanCtrl, 'Kedalaman', Icons.layers_rounded),
              const SizedBox(height: 12),
              _inputField(koordinatCtrl, 'Koordinat (Lat, Lng)', Icons.my_location_rounded),
              const SizedBox(height: 12),
              _inputField(waktuCtrl, 'Waktu', Icons.access_time_rounded),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AdminColors.navyDark,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () async {
                    try {
                      // KUNCI CRUD: Update ke tabel SUMBER (gempa_live), jangan ke tabel VIEW!
                      await Supabase.instance.client
                          .from('gempa_live')
                          .update({
                            'magnitude': magCtrl.text,
                            'wilayah': wilayahCtrl.text,
                            'kedalaman': kedalamanCtrl.text,
                            'koordinat': koordinatCtrl.text,
                            'waktu': waktuCtrl.text,
                          })
                          .eq('id', item['id_fakta']); 
                          
                      if (mounted) {
                        Navigator.pop(context);
                        _fetchData(isRefresh: true);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Data diupdate di gempa_live!'), backgroundColor: Colors.green),
                        );
                      }
                    } catch (e) {
                      debugPrint('Update error: $e');
                    }
                  },
                  child: const Text('Simpan Perubahan', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _inputField(TextEditingController ctrl, String label, IconData icon) {
    return TextField(
      controller: ctrl,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AdminColors.poskoBlue, size: 20),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }

  void _confirmDelete(BuildContext ctx, dynamic idFakta) {
    showDialog(
      context: ctx,
      builder: (context) => AlertDialog(
        title: const Text('Hapus Data Gempa?'),
        content: const Text('Data ini akan dihapus permanen dari database sumber (gempa_live).'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AdminColors.redAlert),
            onPressed: () async {
              // Delete juga dilakukan di gempa_live
              await Supabase.instance.client.from('gempa_live').delete().eq('id', idFakta);
              if (mounted) {
                Navigator.pop(context); // Tutup dialog
                Navigator.pop(context); // Tutup modal edit
                _fetchData(isRefresh: true);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Data berhasil dihapus.'), backgroundColor: Colors.red),
                );
              }
            },
            child: const Text('Hapus', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // --- SUMMARY BAR ---
        Container(
          color: AdminColors.navyDark,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Total Data Warehouse', style: TextStyle(color: AdminColors.textMuted, fontSize: 12)),
                    Text('$_totalDataTersedia Kejadian', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                onPressed: () => _fetchData(isRefresh: true),
              ),
            ],
          ),
        ),

        // --- SEARCH BAR (SERVER SIDE) ---
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _searchCtrl,
            textInputAction: TextInputAction.search,
            onSubmitted: _onSearch,
            decoration: InputDecoration(
              hintText: 'Cari wilayah...',
              prefixIcon: const Icon(Icons.search_rounded, color: AdminColors.textMuted),
              suffixIcon: _searchQuery.isNotEmpty
                  ? GestureDetector(
                      onTap: () {
                        _searchCtrl.clear();
                        _onSearch('');
                      },
                      child: const Icon(Icons.close_rounded, color: AdminColors.textMuted),
                    )
                  : null,
              filled: true,
              fillColor: AdminColors.bgLight,
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
        ),

        // --- LIST VIEW (INFINITE SCROLL) ---
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _earthquakes.isEmpty
                  ? const Center(child: Text('Tidak ada data gempa'))
                  : RefreshIndicator(
                      onRefresh: () => _fetchData(isRefresh: true),
                      child: ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(12),
                        itemCount: _earthquakes.length + (_hasMoreData ? 1 : 0),
                        itemBuilder: (context, index) {
                          // Tampilkan loading spinner di urutan paling bawah
                          if (index == _earthquakes.length) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 20),
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }

                          final item = _earthquakes[index];
                          final double mag = double.tryParse(item['magnitude'].toString()) ?? 0;
                          final Color color = _magColor(mag);
                          final String source = item['sumber_data'] ?? 'DATA';

                          Color srcColor = Colors.blue;
                          if (source == 'USGS') srcColor = Colors.purple;
                          if (source == 'EMSC') srcColor = Colors.teal;

                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: Colors.grey.shade200),
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => _showEditModal(Map<String, dynamic>.from(item)),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 52, height: 52,
                                      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
                                      alignment: Alignment.center,
                                      child: Text(mag.toStringAsFixed(1), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(item['wilayah'] ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AdminColors.navyDark), maxLines: 1, overflow: TextOverflow.ellipsis),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(color: srcColor, borderRadius: BorderRadius.circular(4)),
                                                child: Text(source, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text('${item['waktu']} • ${item['kedalaman']}', style: const TextStyle(color: AdminColors.textMuted, fontSize: 11), overflow: TextOverflow.ellipsis),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Icon(Icons.edit_rounded, color: AdminColors.textMuted, size: 18),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
        ),
      ],
    );
  }
}
// =============================================================================
// ADMIN LIVE MAP VIEW — GEMPA + POSKO
// =============================================================================
class AdminLiveMapView extends StatefulWidget {
  const AdminLiveMapView({super.key});

  @override
  State<AdminLiveMapView> createState() => _AdminLiveMapViewState();
}

class _AdminLiveMapViewState extends State<AdminLiveMapView> {
  List<Marker> _gempaMarkers = [];
  List<Marker> _poskoMarkers = [];
  List<CircleMarker> _circles = [];
  List<dynamic> _poskoList = [];
  bool _isLoading = true;
  Map<String, dynamic>? _selectedQuake;

  @override
  void initState() {
    super.initState();
    _loadAllMapData();
  }

  Future<void> _loadAllMapData() async {
    setState(() {
      _isLoading = true;
      _selectedQuake = null;
    });
    try {
      final gempaData = await Supabase.instance.client
          .from('gempa_live')
          .select('*');
      final poskoData = await Supabase.instance.client
          .from('posko_evakuasi')
          .select('*');

      List<Marker> tempGempaM = [];
      List<CircleMarker> tempCircles = [];

      for (var item in gempaData) {
        if (item['koordinat'] != null) {
          List<String> coords = item['koordinat'].toString().split(',');
          if (coords.length == 2) {
            double lat = double.tryParse(coords[0]) ?? 0;
            double lng = double.tryParse(coords[1]) ?? 0;
            double mag = double.tryParse(
                    item['magnitude']?.toString() ?? '0') ??
                0;

            Color markerColor = AdminColors.greenAlert;
            if (mag >= 5.0) markerColor = AdminColors.redAlert;
            else if (mag >= 4.0) markerColor = AdminColors.orangeAlert;

            final itemCopy = Map<String, dynamic>.from(item);

            tempCircles.add(CircleMarker(
              point: LatLng(lat, lng),
              color: markerColor.withOpacity(0.2),
              borderColor: markerColor,
              borderStrokeWidth: 1.5,
              useRadiusInMeter: true,
              radius: math.pow(mag, 1.5) * 2500,
            ));

            tempGempaM.add(Marker(
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
                child: Icon(Icons.location_on,
                    color: markerColor, size: 30),
              ),
            ));
          }
        }
      }

      List<Marker> tempPoskoM = [];
      for (var posko in poskoData) {
        if (posko['koordinat'] != null) {
          List<String> coords = posko['koordinat'].toString().split(',');
          if (coords.length == 2) {
            double lat = double.tryParse(coords[0]) ?? 0;
            double lng = double.tryParse(coords[1]) ?? 0;
            final poskoCopy = Map<String, dynamic>.from(posko);

            tempPoskoM.add(Marker(
              point: LatLng(lat, lng),
              width: 60,
              height: 60,
              child: GestureDetector(
                onTap: () => _showPoskoDetail(poskoCopy),
                child: Column(
                  children: [
                    const Icon(Icons.health_and_safety,
                        color: AdminColors.poskoBlue, size: 28),
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
                            color: AdminColors.navyDark),
                      ),
                    ),
                  ],
                ),
              ),
            ));
          }
        }
      }

      setState(() {
        _gempaMarkers = tempGempaM;
        _poskoMarkers = tempPoskoM;
        _poskoList = poskoData;
        _circles = tempCircles;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Error Load Admin Map: $e");
      setState(() => _isLoading = false);
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
            Row(
              children: [
                const Icon(Icons.health_and_safety,
                    color: AdminColors.poskoBlue, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    posko['nama_posko'] ?? 'Posko',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: AdminColors.navyDark),
                  ),
                ),
                // Tombol edit posko
                IconButton(
                  icon: const Icon(Icons.edit_rounded,
                      color: AdminColors.poskoBlue),
                  onPressed: () {
                    Navigator.pop(context);
                    _showEditPoskoModal(posko);
                  },
                ),
                // Tombol hapus posko
                IconButton(
                  icon:
                      const Icon(Icons.delete_rounded, color: Colors.red),
                  onPressed: () async {
                    await Supabase.instance.client
                        .from('posko_evakuasi')
                        .delete()
                        .eq('id', posko['id']);
                    if (mounted) {
                      Navigator.pop(context);
                      _loadAllMapData();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Posko dihapus'),
                            backgroundColor: Colors.red),
                      );
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 12),
            if (posko['keterangan'] != null &&
                posko['keterangan'].toString().isNotEmpty) ...[
              Row(
                children: [
                  const Icon(Icons.info_rounded,
                      size: 16, color: AdminColors.textMuted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(posko['keterangan'],
                        style: const TextStyle(
                            color: AdminColors.navyDark)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            Row(
              children: [
                const Icon(Icons.my_location_rounded,
                    size: 16, color: AdminColors.textMuted),
                const SizedBox(width: 8),
                Text(posko['koordinat'] ?? '-',
                    style:
                        const TextStyle(color: AdminColors.textMuted)),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  backgroundColor: AdminColors.bgLight,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Tutup',
                    style: TextStyle(color: AdminColors.navyDark)),
              ),
            ),
          ],
        ),
      ),
    );
  }


  void _showEditPoskoModal(Map<String, dynamic> posko) {
    final namaCtrl =
        TextEditingController(text: posko['nama_posko']?.toString() ?? '');
    final ketCtrl =
        TextEditingController(text: posko['keterangan']?.toString() ?? '');
    final koordCtrl =
        TextEditingController(text: posko['koordinat']?.toString() ?? '');
    bool isFetchingGPS = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                left: 24,
                right: 24,
                top: 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40, height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text('Edit Posko Evakuasi',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AdminColors.navyDark)),
                    const SizedBox(height: 16),
                    TextField(
                      controller: namaCtrl,
                      decoration: InputDecoration(
                        labelText: 'Nama Posko',
                        prefixIcon: const Icon(Icons.health_and_safety_rounded,
                            color: AdminColors.poskoBlue),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: ketCtrl,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: 'Keterangan',
                        prefixIcon: const Icon(Icons.notes_rounded,
                            color: AdminColors.poskoBlue),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: koordCtrl,
                            decoration: InputDecoration(
                              labelText: 'Koordinat (Lat, Lng)',
                              prefixIcon: const Icon(Icons.my_location_rounded,
                                  color: AdminColors.poskoBlue),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          height: 56,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AdminColors.poskoBlue,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () async {
                              setModalState(() => isFetchingGPS = true);
                              try {
                                Position pos =
                                    await Geolocator.getCurrentPosition(
                                        desiredAccuracy: LocationAccuracy.high);
                                koordCtrl.text =
                                    "${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}";
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text(
                                              'Gagal ambil GPS!')));
                                }
                              }
                              setModalState(() => isFetchingGPS = false);
                            },
                            child: isFetchingGPS
                                ? const SizedBox(
                                    width: 20, height: 20,
                                    child: CircularProgressIndicator(
                                        color: Colors.white, strokeWidth: 2))
                                : const Icon(Icons.gps_fixed,
                                    color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AdminColors.poskoBlue,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () async {
                          if (namaCtrl.text.isEmpty || koordCtrl.text.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Nama dan Koordinat wajib!')),
                            );
                            return;
                          }
                          try {
                            await Supabase.instance.client
                                .from('posko_evakuasi')
                                .update({
                                  'nama_posko': namaCtrl.text,
                                  'keterangan': ketCtrl.text,
                                  'koordinat': koordCtrl.text,
                                })
                                .eq('id', posko['id']);
                            if (mounted) {
                              Navigator.pop(context);
                              _loadAllMapData();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Posko berhasil diupdate!'),
                                    backgroundColor: Colors.green),
                              );
                            }
                          } catch (e) {
                            debugPrint('Update posko error: $e');
                          }
                        },
                        child: const Text('Simpan Perubahan',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold)),
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

  void _showAddPoskoModal() {
    final namaCtrl = TextEditingController();
    final ketCtrl = TextEditingController();
    final koordCtrl = TextEditingController();
    bool isFetchingGPS = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                left: 24,
                right: 24,
                top: 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text('Tambah Posko Evakuasi',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AdminColors.navyDark)),
                    const SizedBox(height: 16),
                    TextField(
                      controller: namaCtrl,
                      decoration: InputDecoration(
                        labelText: 'Nama Posko / RS / Shelter',
                        prefixIcon: const Icon(
                            Icons.health_and_safety_rounded,
                            color: AdminColors.poskoBlue),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: ketCtrl,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: 'Keterangan (Kapasitas, Kebutuhan, dll)',
                        prefixIcon: const Icon(Icons.notes_rounded,
                            color: AdminColors.poskoBlue),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: koordCtrl,
                            decoration: InputDecoration(
                              labelText: 'Koordinat (Lat, Lng)',
                              prefixIcon: const Icon(
                                  Icons.my_location_rounded,
                                  color: AdminColors.poskoBlue),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Tombol GPS
                        SizedBox(
                          height: 56,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AdminColors.poskoBlue,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () async {
                              setModalState(() => isFetchingGPS = true);
                              try {
                                Position pos =
                                    await Geolocator.getCurrentPosition(
                                        desiredAccuracy:
                                            LocationAccuracy.high);
                                koordCtrl.text =
                                    "${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}";
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(const SnackBar(
                                    content: Text(
                                        'Gagal ambil GPS! Cek izin lokasi.'),
                                  ));
                                }
                              }
                              setModalState(() => isFetchingGPS = false);
                            },
                            child: isFetchingGPS
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2),
                                  )
                                : const Icon(Icons.gps_fixed,
                                    color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AdminColors.navyDark,
                          padding:
                              const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () async {
                          if (namaCtrl.text.isEmpty ||
                              koordCtrl.text.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text(
                                      'Nama dan Koordinat wajib diisi!')),
                            );
                            return;
                          }
                          try {
                            await Supabase.instance.client
                                .from('posko_evakuasi')
                                .insert({
                              'nama_posko': namaCtrl.text,
                              'keterangan': ketCtrl.text,
                              'koordinat': koordCtrl.text,
                            });
                            if (mounted) {
                              Navigator.pop(context);
                              _loadAllMapData();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content:
                                        Text('Posko berhasil ditambahkan!'),
                                    backgroundColor: Colors.green),
                              );
                            }
                          } catch (e) {
                            debugPrint('Insert Posko Error: $e');
                          }
                        },
                        child: const Text('Simpan Titik Posko',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold)),
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
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.sasimokguard.app',
              ),
              CircleLayer(circles: _circles),
              MarkerLayer(markers: _gempaMarkers),
              MarkerLayer(markers: _poskoMarkers),
            ],
          ),
        ),

        // Banner atas
        Positioned(
          top: 16,
          left: 16,
          right: 16,
          child: Container(
            padding:
                const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.95),
              borderRadius: BorderRadius.circular(30),
              boxShadow: const [
                BoxShadow(
                    color: Colors.black26, blurRadius: 8, offset: Offset(0, 4))
              ],
            ),
            child: Row(
              children: [
                const Icon(Icons.admin_panel_settings_rounded,
                    color: AdminColors.navyDark, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${_gempaMarkers.length} Gempa • ${_poskoMarkers.length} Posko',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AdminColors.navyDark,
                        fontSize: 13),
                  ),
                ),
                GestureDetector(
                  onTap: _loadAllMapData,
                  child: const Icon(Icons.refresh_rounded,
                      color: AdminColors.navyDark),
                ),
              ],
            ),
          ),
        ),

        // Info panel gempa saat diklik
        AnimatedPositioned(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          bottom: _selectedQuake != null ? 100 : -220,
          left: 16,
          right: 16,
          child: _selectedQuake == null
              ? const SizedBox.shrink()
              : _buildQuakePanel(_selectedQuake!),
        ),

        // FAB tambah posko
        Positioned(
          bottom: 24,
          right: 16,
          child: FloatingActionButton.extended(
            backgroundColor: AdminColors.poskoBlue,
            icon: const Icon(Icons.add_location_alt_rounded,
                color: Colors.white),
            label: const Text('Posko Baru',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
            onPressed: _showAddPoskoModal,
          ),
        ),
      ],
    );
  }

  Widget _buildQuakePanel(Map<String, dynamic> quake) {
    final Color color = quake['_markerColor'] as Color;
    final double mag = quake['_mag'] as double;
    final String source = quake['source'] ?? 'Unknown';
    final String wilayah = quake['wilayah'] ?? '-';
    final String waktu = quake['waktu'] ?? '-';
    final String kedalaman = quake['kedalaman'] ?? '-';

    Color srcColor = Colors.blue;
    if (source == 'USGS') srcColor = Colors.purple;
    if (source == 'EMSC') srcColor = Colors.teal;

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
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(10)),
                  alignment: Alignment.center,
                  child: Text(mag.toStringAsFixed(1),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(wilayah,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: AdminColors.navyDark),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                            color: srcColor,
                            borderRadius: BorderRadius.circular(4)),
                        child: Text(source,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () =>
                      setState(() => _selectedQuake = null),
                  child: const Icon(Icons.close_rounded,
                      color: AdminColors.textMuted),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.access_time_rounded,
                    size: 14, color: AdminColors.textMuted),
                const SizedBox(width: 4),
                Expanded(
                    child: Text(waktu,
                        style: const TextStyle(
                            color: AdminColors.textMuted, fontSize: 12))),
                const Icon(Icons.layers_rounded,
                    size: 14, color: AdminColors.textMuted),
                const SizedBox(width: 4),
                Text(kedalaman,
                    style: const TextStyle(
                        color: AdminColors.textMuted, fontSize: 12)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// ADMIN ANALYTICS VIEW — ADVANCE STATS
// =============================================================================
class AdminAnalyticsView extends StatefulWidget {
  const AdminAnalyticsView({super.key});

  @override
  State<AdminAnalyticsView> createState() => _AdminAnalyticsViewState();
}

class _AdminAnalyticsViewState extends State<AdminAnalyticsView> {
  bool _isLoading = true;
  int _total = 0;
  int _m5plus = 0;
  int _m4to5 = 0;
  int _m3to4 = 0;
  int _minor = 0;
  int _totalPosko = 0;
  double _avgMag = 0;
  double _maxMag = 0;
  Map<String, int> _bySource = {};
  List<dynamic> _topQuakes = [];

  @override
  void initState() {
    super.initState();
    _fetchStats();
  }

  Future<void> _fetchStats() async {
  setState(() => _isLoading = true);
  try {
    final now = DateTime.now();
    final start = now.subtract(const Duration(days: 30));
    String fmtDate(DateTime d) =>
        "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";

    final gempa = await Supabase.instance.client
        .schema('gold')
        .from('gold_gempa_analytics')
        .select('magnitude, kedalaman, status_gempa, waktu, wilayah')
        .gte('waktu', fmtDate(start))
        .lte('waktu', fmtDate(now));

    final posko = await Supabase.instance.client
        .from('posko_evakuasi')
        .select('id');

    int m5 = 0, m4 = 0, m3 = 0, minor = 0;
    double sumMag = 0, maxM = 0;

    for (var item in gempa) {
      double mag = double.tryParse(item['magnitude']?.toString() ?? '0') ?? 0;
      sumMag += mag;
      if (mag > maxM) maxM = mag;
      if (mag >= 5.0) m5++;
      else if (mag >= 4.0) m4++;
      else if (mag >= 3.0) m3++;
      else minor++;
    }

    List<dynamic> sorted = List.from(gempa);
    sorted.sort((a, b) {
      double ma = double.tryParse(a['magnitude']?.toString() ?? '0') ?? 0;
      double mb = double.tryParse(b['magnitude']?.toString() ?? '0') ?? 0;
      return mb.compareTo(ma);
    });

    setState(() {
      _total = gempa.length;
      _m5plus = m5;
      _m4to5 = m4;
      _m3to4 = m3;
      _minor = minor;
      _totalPosko = posko.length;
      _avgMag = _total > 0 ? sumMag / _total : 0;
      _maxMag = maxM;
      _topQuakes = sorted.take(5).toList();
      _isLoading = false;
    });
  } catch (e) {
    debugPrint('Analytics error: $e');
    setState(() => _isLoading = false);
  }
}

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    return RefreshIndicator(
      onRefresh: _fetchStats,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Summary cards
            Row(
              children: [
                _summaryCard('Total Gempa', _total.toString(),
                    Icons.public_rounded, AdminColors.poskoBlue),
                const SizedBox(width: 12),
                _summaryCard('Total Posko', _totalPosko.toString(),
                    Icons.health_and_safety_rounded, AdminColors.greenAlert),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _summaryCard('Avg Magnitude',
                    _avgMag.toStringAsFixed(2),
                    Icons.analytics_rounded, AdminColors.orangeAlert),
                const SizedBox(width: 12),
                _summaryCard('Max Magnitude', _maxMag.toStringAsFixed(1),
                    Icons.warning_rounded, AdminColors.redAlert),
              ],
            ),

            const SizedBox(height: 24),
            const Text('DISTRIBUSI MAGNITUDE',
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AdminColors.textMuted,
                    letterSpacing: 1,
                    fontSize: 12)),
            const SizedBox(height: 12),

            // Magnitude bars
            _magBar('M5+', _m5plus, _total, AdminColors.redAlert),
            const SizedBox(height: 8),
            _magBar('M4-5', _m4to5, _total, AdminColors.orangeAlert),
            const SizedBox(height: 8),
            _magBar('M3-4', _m3to4, _total, AdminColors.blueLight),
            const SizedBox(height: 8),
            _magBar('< M3', _minor, _total, AdminColors.greenAlert),

            const SizedBox(height: 24),
            const SizedBox(height: 24),
            const Text('TOP 5 GEMPA TERBESAR',
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AdminColors.textMuted,
                    letterSpacing: 1,
                    fontSize: 12)),
            const SizedBox(height: 12),

            ..._topQuakes.map((item) {
              double mag =
                  double.tryParse(item['magnitude']?.toString() ?? '0') ??
                      0;
              Color color = AdminColors.greenAlert;
              if (mag >= 5.0) color = AdminColors.redAlert;
              else if (mag >= 4.0) color = AdminColors.orangeAlert;

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border(left: BorderSide(color: color, width: 4)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(8)),
                      alignment: Alignment.center,
                      child: Text(mag.toStringAsFixed(1),
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 17)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item['wilayah'] ?? '-',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AdminColors.navyDark,
                                  fontSize: 13),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          Text(
                              '${item['waktu'] ?? '-'} • ${item['kedalaman'] ?? '-'}',
                              style: const TextStyle(
                                  color: AdminColors.textMuted,
                                  fontSize: 11)),
                        ],
                      ),
                    ),
                    Text(
  item['status_gempa'] ?? '-',
  style: TextStyle(
    color: _statusColor(item['status_gempa'] ?? ''),
    fontSize: 10,
    fontWeight: FontWeight.bold,
  ),
),
                  ],
                ),
              );
            }),

            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
Color _statusColor(String status) {
  switch (status.toLowerCase()) {
    case 'gempa kuat':
      return AdminColors.redAlert;
    case 'gempa sedang':
    case 'gempa terasa':
      return AdminColors.orangeAlert;
    default:
      return AdminColors.textMuted;
  }
}
  Widget _summaryCard(
      String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 10),
            Text(value,
                style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w900,
                    fontSize: 20)),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(
                    color: AdminColors.textMuted, fontSize: 10),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  Widget _magBar(String label, int count, int total, Color color) {
    double pct = total > 0 ? count / total : 0;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AdminColors.navyDark,
                      fontSize: 13)),
              Text('$count (${(pct * 100).toStringAsFixed(1)}%)',
                  style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                      fontSize: 13)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct,
              backgroundColor: color.withOpacity(0.15),
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 8,
            ),
          ),
        ],
      ),
    );
  }
}