import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SeismicColors {
  static const Color navyDark = Color(0xFF1E293B);
  static const Color navyAccent = Color(0xFF334155);
  static const Color redAlert = Color(0xFFE11D48);
  static const Color orangeAlert = Color(0xFFF97316);
  static const Color blueLight = Color(0xFF38BDF8);
  static const Color textMuted = Color(0xFF94A3B8);
  static const Color bgLight = Color(0xFFF8FAFC);
  static const Color greenAlert = Color(0xFF22C55E);
}

class AnalyticsView extends StatefulWidget {
  const AnalyticsView({super.key});

  @override
  State<AnalyticsView> createState() => _AnalyticsViewState();
}

class _AnalyticsViewState extends State<AnalyticsView> {
  bool _isLoading = true;
  double _avgMagnitude = 0;
  int _totalEvents = 0;
  Map<String, int> _distribution = {
    'Minor': 0,
    'Light': 0,
    'Moderate': 0,
    'Major': 0
  };
  List<double> _monthlyCounts = [0, 0, 0, 0, 0, 0];
  double _maxBarValue = 10;

  // Variabel DSS (Decision Support System) Lanjutan
  String _topRegion = "-";
  double _maxMagnitudeInPeriod = 0.0;
  String _mostActiveDay = "-";
  int _mostActiveDayCount = 0;
  double _shallowQuakePercentage = 0.0;

  // Filter UI State
  String _activePreset = '30 Hari';
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _endDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _calcStats();
  }

  String _fmtDate(DateTime d) =>
      "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";

  String _fmtLabel(DateTime d) =>
      "${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}";

  Future<void> _calcStats() async {
    setState(() => _isLoading = true);
    try {
      // Tambahkan 'kedalaman' di query untuk analisis risiko
      final data = await Supabase.instance.client
          .schema("gold")
          .from('gold_gempa_analytics')
          .select('magnitude, waktu, wilayah, kedalaman')
          .gte('waktu', _fmtDate(_startDate))
          .lte('waktu', '${_fmtDate(_endDate)} 23:59:59');

      double totalMag = 0;
      double highestMagFound = 0.0;
      int shallowQuakesCount = 0;

      Map<String, int> regionFreq = {};
      Map<String, int> dateFreq = {};
      Map<String, int> dist = {'Minor': 0, 'Light': 0, 'Moderate': 0, 'Major': 0};
      List<double> counts = [0, 0, 0, 0, 0, 0];

      for (var item in data) {
        // Parsing Numerik
        double mag = double.tryParse(item['magnitude'].toString()) ?? 0;
        double depth = double.tryParse(item['kedalaman'].toString()) ?? 0;
        totalMag += mag;

        // DSS 1: Magnitudo Terbesar
        if (mag > highestMagFound) highestMagFound = mag;

        // DSS 2: Hitung Gempa Dangkal (< 60 km berisiko tinggi)
        if (depth > 0 && depth <= 60) shallowQuakesCount++;

        // DSS 3: Frekuensi Wilayah
        String region = item['wilayah']?.toString() ?? 'Unknown';
        regionFreq[region] = (regionFreq[region] ?? 0) + 1;

        // DSS 4: Frekuensi Tanggal Puncak (Anomali)
        String rawTime = item['waktu'].toString();
        String dateOnly = rawTime.contains(' ') ? rawTime.split(' ')[0] : rawTime;
        dateFreq[dateOnly] = (dateFreq[dateOnly] ?? 0) + 1;

        // Distribusi Magnitudo
        if (mag < 4.0) dist['Minor'] = dist['Minor']! + 1;
        else if (mag < 5.0) dist['Light'] = dist['Light']! + 1;
        else if (mag < 6.0) dist['Moderate'] = dist['Moderate']! + 1;
        else dist['Major'] = dist['Major']! + 1;

        // Bulanan Bar Chart
        if (rawTime.contains('-')) {
          List<String> parts = rawTime.split('-');
          if (parts.length >= 2) {
            int month = int.tryParse(parts[1]) ?? 0;
            if (month >= 1 && month <= 6) counts[month - 1]++;
          }
        }
      }

      // Kalkulasi Akhir DSS
      String mostAffectedRegion = "-";
      if (regionFreq.isNotEmpty) {
        var sortedRegions = regionFreq.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
        mostAffectedRegion = sortedRegions.first.key;
      }

      String peakDay = "-";
      int peakCount = 0;
      if (dateFreq.isNotEmpty) {
        var sortedDates = dateFreq.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
        peakDay = sortedDates.first.key;
        peakCount = sortedDates.first.value;
      }

      double shallowPct = data.isEmpty ? 0 : (shallowQuakesCount / data.length) * 100;

      double highest = counts.reduce((curr, next) => curr > next ? curr : next);
      double calcMax = highest + (highest * 0.2);
      if (calcMax < 10) calcMax = 10;

      setState(() {
        _totalEvents = data.length;
        _avgMagnitude = _totalEvents > 0 ? totalMag / _totalEvents : 0;
        _distribution = dist;
        _monthlyCounts = counts;
        _maxBarValue = calcMax;
        
        _maxMagnitudeInPeriod = highestMagFound;
        _topRegion = mostAffectedRegion;
        _mostActiveDay = peakDay;
        _mostActiveDayCount = peakCount;
        _shallowQuakePercentage = shallowPct;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Error Analytics: $e");
      setState(() => _isLoading = false);
    }
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: SeismicColors.navyDark,
              onPrimary: Colors.white,
              secondary: SeismicColors.blueLight,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
        _activePreset = 'Kustom';
      });
      _calcStats();
    }
  }

  void _applyPreset(String preset) {
    if (_activePreset == preset) return; 
    
    final now = DateTime.now();
    DateTime start;
    DateTime end = now;

    switch (preset) {
      case '7 Hari':
        start = now.subtract(const Duration(days: 7));
        break;
      case '30 Hari':
        start = now.subtract(const Duration(days: 30));
        break;
      case 'Bulan Ini':
        start = DateTime(now.year, now.month, 1);
        break;
      case 'Tahun Ini':
        start = DateTime(now.year, 1, 1);
        break;
      default:
        start = now.subtract(const Duration(days: 30));
    }

    setState(() {
      _activePreset = preset;
      _startDate = start;
      _endDate = end;
    });
    _calcStats();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SeismicColors.bgLight,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('SASIMOK GUARD', style: TextStyle(color: SeismicColors.navyDark, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
        centerTitle: true,
      ),
      body: RefreshIndicator(
        onRefresh: _calcStats,
        color: SeismicColors.blueLight,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFilterSection(),
                    const SizedBox(height: 24),

                    // ── INSIGHTS (DSS) SECTION ──
                    const Text('Analisis Ancaman Bencana', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: SeismicColors.navyDark)),
                    const SizedBox(height: 12),
                    _buildDSSGrid(),
                    const SizedBox(height: 24),

                    // ── STATS CARDS ──
                    _buildStatsSummary(),
                    const SizedBox(height: 32),

                    // ── BAR CHART ──
                    const Text('Tren Aktivitas Gempa', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: SeismicColors.navyDark)),
                    const SizedBox(height: 4),
                    Text('${_fmtLabel(_startDate)} – ${_fmtLabel(_endDate)}', style: const TextStyle(color: SeismicColors.textMuted, fontSize: 13)),
                    const SizedBox(height: 16),
                    _buildBarChartContainer(),
                    const SizedBox(height: 32),

                    // ── DONUT CHART ──
                    const Text('Sebaran Kekuatan Gempa', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: SeismicColors.navyDark)),
                    const SizedBox(height: 16),
                    _buildDonutChartContainer(),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildFilterSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.withOpacity(0.2))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Rentang Analisis', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: SeismicColors.textMuted)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: ['7 Hari', '30 Hari', 'Bulan Ini', 'Tahun Ini'].map((label) {
                  bool isActive = _activePreset == label;
                  return GestureDetector(
                    onTap: () => _applyPreset(label),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: isActive ? SeismicColors.blueLight : Colors.transparent,
                        border: Border.all(color: isActive ? SeismicColors.blueLight : Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(label, style: TextStyle(color: isActive ? Colors.white : SeismicColors.navyAccent, fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                  );
                }).toList(),
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: _pickDateRange,
            child: Row(
              children: [
                Icon(Icons.calendar_today_rounded, size: 16, color: _activePreset == 'Kustom' ? SeismicColors.blueLight : SeismicColors.navyDark),
                const SizedBox(width: 10),
                Expanded(child: Text('${_fmtLabel(_startDate)}  →  ${_fmtLabel(_endDate)}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _activePreset == 'Kustom' ? SeismicColors.blueLight : SeismicColors.navyDark))),
                const Icon(Icons.edit_calendar_rounded, size: 16, color: SeismicColors.textMuted),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── GRID DSS 2x2 YANG LEBIH PRO ────────────────────────────────────────
  Widget _buildDSSGrid() {
    bool isHighRisk = _shallowQuakePercentage >= 50.0;
    
    return Column(
      children: [
        Row(
          children: [
            _buildDSSCard(
              title: "Gempa Terkuat",
              value: "M ${_maxMagnitudeInPeriod.toStringAsFixed(1)}",
              subtitle: "Puncak magnitudo",
              icon: Icons.warning_amber_rounded,
              color: SeismicColors.orangeAlert,
            ),
            const SizedBox(width: 12),
            _buildDSSCard(
              title: "Puncak Anomali",
              value: _mostActiveDay,
              subtitle: "$_mostActiveDayCount gempa/hari",
              icon: Icons.show_chart_rounded,
              color: SeismicColors.blueLight,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _buildDSSCard(
              title: "Tingkat Risiko",
              value: "${_shallowQuakePercentage.toStringAsFixed(0)}% Dangkal",
              subtitle: isHighRisk ? "Potensi rusak tinggi" : "Aktivitas dalam normal",
              icon: Icons.waves_rounded,
              color: isHighRisk ? SeismicColors.redAlert : SeismicColors.navyAccent,
            ),
            const SizedBox(width: 12),
            _buildDSSCard(
              title: "Pusat Rawan",
              value: _topRegion.length > 15 ? "${_topRegion.substring(0, 15)}..." : _topRegion,
              subtitle: "Frekuensi terbanyak",
              icon: Icons.location_on_rounded,
              color: SeismicColors.navyDark,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDSSCard({required String title, required String value, required String subtitle, required IconData icon, required Color color}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: color.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Colors.white70, size: 16),
                const SizedBox(width: 6),
                Expanded(child: Text(title, style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis)),
              ],
            ),
            const SizedBox(height: 10),
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 10)),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsSummary() {
    return Row(
      children: [
        _buildMiniCard('AVG MAGNITUDE', _avgMagnitude.toStringAsFixed(2), 'Berdasarkan filter'),
        const SizedBox(width: 12),
        _buildMiniCard('TOTAL EVENTS', '$_totalEvents', 'Gempa tercatat'),
      ],
    );
  }

  Widget _buildMiniCard(String title, String val, String sub) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.withOpacity(0.2))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: SeismicColors.textMuted)),
            const SizedBox(height: 8),
            Text(val, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: SeismicColors.navyDark)),
            const SizedBox(height: 4),
            Text(sub, style: const TextStyle(fontSize: 11, color: SeismicColors.textMuted)),
          ],
        ),
      ),
    );
  }

  Widget _buildBarChartContainer() {
    return Container(
      height: 220,
      padding: const EdgeInsets.only(top: 10, right: 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.withOpacity(0.2))),
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: _maxBarValue,
          barTouchData: BarTouchData(
            enabled: true,
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                return BarTooltipItem('${rod.toY.toInt()} Kejadian', const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12));
              },
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (double value, TitleMeta meta) {
                  const style = TextStyle(color: SeismicColors.textMuted, fontWeight: FontWeight.bold, fontSize: 10);
                  const months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN'];
                  return SideTitleWidget(meta: meta, child: Text(months[value.toInt()], style: style));
                },
              ),
            ),
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (val) => FlLine(color: Colors.grey.withOpacity(0.1), strokeWidth: 1)),
          borderData: FlBorderData(show: false),
          barGroups: List.generate(6, (i) => BarChartGroupData(x: i, barRods: [BarChartRodData(toY: _monthlyCounts[i], color: i % 2 == 0 ? SeismicColors.navyDark : SeismicColors.redAlert, width: 22, borderRadius: BorderRadius.circular(2))])),
        ),
      ),
    );
  }

  Widget _buildDonutChartContainer() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.withOpacity(0.2))),
      child: Row(
        children: [
          SizedBox(
            width: 130, height: 130,
            child: Stack(
              children: [
                PieChart(PieChartData(sectionsSpace: 4, centerSpaceRadius: 45, sections: _buildPieSections())),
                Center(
                    child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('$_totalEvents', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 24, color: SeismicColors.navyDark)),
                    const Text('TOTAL', style: TextStyle(fontSize: 10, color: SeismicColors.textMuted, fontWeight: FontWeight.bold)),
                  ],
                )),
              ],
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildLegendItem('Minor (< 4.0)', SeismicColors.greenAlert, _distribution['Minor']!),
              _buildLegendItem('Terasa (4.0 - 4.9)', SeismicColors.blueLight, _distribution['Light']!),
              _buildLegendItem('Sedang (5.0 - 5.9)', SeismicColors.orangeAlert, _distribution['Moderate']!),
              _buildLegendItem('Kuat (≥ 6.0)', SeismicColors.redAlert, _distribution['Major']!),
            ],
          )),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color, int count) {
    double pct = _totalEvents == 0 ? 0 : (count / _totalEvents) * 100;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 10, color: SeismicColors.navyDark, fontWeight: FontWeight.w600))),
          Text('${pct.toStringAsFixed(0)}%', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: SeismicColors.navyDark)),
        ],
      ),
    );
  }

  List<PieChartSectionData> _buildPieSections() {
    return [
      PieChartSectionData(color: SeismicColors.greenAlert, value: _distribution['Minor']!.toDouble(), radius: 18, showTitle: false),
      PieChartSectionData(color: SeismicColors.blueLight, value: _distribution['Light']!.toDouble(), radius: 18, showTitle: false),
      PieChartSectionData(color: SeismicColors.orangeAlert, value: _distribution['Moderate']!.toDouble(), radius: 18, showTitle: false),
      PieChartSectionData(color: SeismicColors.redAlert, value: _distribution['Major']!.toDouble(), radius: 18, showTitle: false),
    ];
  }
}