import 'package:billiardtm/app_theme.dart';
import 'package:billiardtm/bloc/blocs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../widgets/widgets.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});
  @override State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  String _range = 'today';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: const Text('Stats & Reports'),
        actions: [
          PopupMenuButton<String>(
            color: AppTheme.surface2,
            initialValue: _range,
            onSelected: (r) {
              setState(() => _range = r);
              _reload(context, r);
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'today', child: Text('Today')),
              const PopupMenuItem(value: 'week', child: Text('This Week')),
              const PopupMenuItem(value: 'month', child: Text('This Month')),
            ],
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(color: AppTheme.border),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_rangeLabel, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
                  const SizedBox(width: 4),
                  const Icon(Icons.keyboard_arrow_down, size: 16, color: AppTheme.textMuted),
                ],
              ),
            ),
          ),
        ],
      ),
      body: BlocBuilder<StatsBloc, StatsState>(
        builder: (context, state) {
          if (state is StatsLoading) {
            return const Center(child: CircularProgressIndicator(color: AppTheme.green));
          }
          if (state is StatsLoaded) {
            return _StatsContent(data: state.data);
          }
          if (state is StatsError) {
            return Center(child: Text(state.message, style: const TextStyle(color: AppTheme.red)));
          }
          return const Center(child: Text('Loading...', style: TextStyle(color: AppTheme.textMuted)));
        },
      ),
    );
  }

  void _reload(BuildContext context, String range) {
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      context.read<StatsBloc>().add(StatsLoadRequested(authState.user.venueId, range: range));
    }
  }

  String get _rangeLabel {
    switch (_range) {
      case 'week': return 'This Week';
      case 'month': return 'This Month';
      default: return 'Today';
    }
  }
}

class _StatsContent extends StatelessWidget {
  final StatsData data;
  const _StatsContent({required this.data});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // KPI grid
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 2.0,
          children: [
            StatCard(
              label: 'TOTAL REVENUE',
              value: '\$${data.totalRevenue.toStringAsFixed(2)}',
              valueColor: AppTheme.green,
              icon: Icons.attach_money,
            ),
            StatCard(
              label: 'SESSIONS',
              value: '${data.totalSessions}',
              icon: Icons.sports_bar_outlined,
            ),
            StatCard(
              label: 'AVG SESSION VALUE',
              value: '\$${data.avgSessionValue.toStringAsFixed(2)}',
              icon: Icons.trending_up,
            ),
            StatCard(
              label: 'AVG DURATION',
              value: '${data.avgSessionMinutes.toStringAsFixed(0)}min',
              icon: Icons.access_time,
            ),
          ],
        ),

        const SizedBox(height: 20),
        SectionHeader('Revenue Breakdown'),
        Row(
          children: [
            Expanded(child: _RevenueBreakdownBar(timeRevenue: data.timeRevenue, fbRevenue: data.fbRevenue, total: data.totalRevenue)),
          ],
        ),

        // Revenue by day chart
        if (data.revenueByDay.isNotEmpty) ...[
          const SizedBox(height: 20),
          SectionHeader('Revenue by Day'),
          Container(
            height: 200,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              border: Border.all(color: AppTheme.border),
              borderRadius: BorderRadius.circular(4),
            ),
            child: _RevenueChart(data: data.revenueByDay),
          ),
        ],

        // Sessions by hour
        if (data.sessionsByHour.isNotEmpty) ...[
          const SizedBox(height: 20),
          SectionHeader('Busy Hours'),
          Container(
            height: 160,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              border: Border.all(color: AppTheme.border),
              borderRadius: BorderRadius.circular(4),
            ),
            child: _HourChart(data: data.sessionsByHour),
          ),
        ],

        // Top tables
        if (data.revenueByTable.isNotEmpty) ...[
          const SizedBox(height: 20),
          SectionHeader('Top Tables'),
          ...(_sortedByValue(data.revenueByTable).take(5).map((entry) => _RankRow(
            label: entry.key,
            value: '\$${entry.value.toStringAsFixed(2)}',
            maxValue: data.revenueByTable.values.reduce((a, b) => a > b ? a : b),
            currentValue: entry.value,
          ))),
        ],

        // Top menu items
        if (data.topMenuItems.isNotEmpty) ...[
          const SizedBox(height: 20),
          SectionHeader('Top Menu Items'),
          ...(_sortedByValueInt(data.topMenuItems).take(5).map((entry) => _RankRow(
            label: entry.key,
            value: '×${entry.value}',
            maxValue: data.topMenuItems.values.reduce((a, b) => a > b ? a : b).toDouble(),
            currentValue: entry.value.toDouble(),
            color: AppTheme.blue,
          ))),
        ],

        // Recent sessions
        if (data.sessions.isNotEmpty) ...[
          const SizedBox(height: 20),
          SectionHeader('Recent Sessions'),
          ...data.sessions.take(10).map((s) => _SessionHistoryRow(session: s)),
        ],

        const SizedBox(height: 40),
      ],
    );
  }

  List<MapEntry<String, double>> _sortedByValue(Map<String, double> map) {
    final entries = map.entries.toList();
    entries.sort((a, b) => b.value.compareTo(a.value));
    return entries;
  }

  List<MapEntry<String, int>> _sortedByValueInt(Map<String, int> map) {
    final entries = map.entries.toList();
    entries.sort((a, b) => b.value.compareTo(a.value));
    return entries;
  }
}

class _RevenueBreakdownBar extends StatelessWidget {
  final double timeRevenue, fbRevenue, total;
  const _RevenueBreakdownBar({required this.timeRevenue, required this.fbRevenue, required this.total});

  @override
  Widget build(BuildContext context) {
    if (total == 0) return const SizedBox();
    final timePct = timeRevenue / total;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppTheme.surface, border: Border.all(color: AppTheme.border), borderRadius: BorderRadius.circular(4)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: Row(
              children: [
                Expanded(flex: (timePct * 100).toInt(), child: Container(height: 8, color: AppTheme.green)),
                Expanded(flex: ((1 - timePct) * 100).toInt().clamp(0, 100), child: Container(height: 8, color: AppTheme.blue)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _Legend(color: AppTheme.green, label: 'Time', value: '\$${timeRevenue.toStringAsFixed(2)}'),
              const SizedBox(width: 24),
              _Legend(color: AppTheme.blue, label: 'F&B', value: '\$${fbRevenue.toStringAsFixed(2)}'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label, value;
  const _Legend({required this.color, required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 6),
      Text('$label  ', style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
      Text(value, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12, fontWeight: FontWeight.w700)),
    ],
  );
}

class _RevenueChart extends StatelessWidget {
  final Map<String, double> data;
  const _RevenueChart({required this.data});

  @override
  Widget build(BuildContext context) {
    final entries = data.entries.toList();
    return BarChart(
      BarChartData(
        barGroups: entries.asMap().entries.map((e) => BarChartGroupData(
          x: e.key,
          barRods: [BarChartRodData(
            toY: e.value.value,
            color: AppTheme.green,
            width: 16,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
          )],
        )).toList(),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: null,
          getDrawingHorizontalLine: (_) => const FlLine(color: AppTheme.border, strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40, getTitlesWidget: (v, _) => Text('\$${v.toInt()}', style: const TextStyle(color: AppTheme.textMuted, fontSize: 9)))),
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (v, _) {
            final idx = v.toInt();
            if (idx < 0 || idx >= entries.length) return const SizedBox();
            return Text(entries[idx].key, style: const TextStyle(color: AppTheme.textMuted, fontSize: 9));
          })),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
      ),
    );
  }
}

class _HourChart extends StatelessWidget {
  final Map<int, int> data;
  const _HourChart({required this.data});

  @override
  Widget build(BuildContext context) {
    final hours = List.generate(24, (i) => i);
    return BarChart(
      BarChartData(
        barGroups: hours.map((h) => BarChartGroupData(
          x: h,
          barRods: [BarChartRodData(
            toY: (data[h] ?? 0).toDouble(),
            color: (data[h] ?? 0) > 0 ? AppTheme.green.withOpacity(0.7) : AppTheme.border,
            width: 8,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(1)),
          )],
        )).toList(),
        gridData: const FlGridData(show: false),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, interval: 6, getTitlesWidget: (v, _) {
            final h = v.toInt();
            if (h == 0) return const Text('12a', style: TextStyle(color: AppTheme.textMuted, fontSize: 9));
            if (h == 6) return const Text('6a', style: TextStyle(color: AppTheme.textMuted, fontSize: 9));
            if (h == 12) return const Text('12p', style: TextStyle(color: AppTheme.textMuted, fontSize: 9));
            if (h == 18) return const Text('6p', style: TextStyle(color: AppTheme.textMuted, fontSize: 9));
            return const SizedBox();
          })),
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
      ),
    );
  }
}

class _RankRow extends StatelessWidget {
  final String label, value;
  final double maxValue, currentValue;
  final Color color;
  const _RankRow({required this.label, required this.value, required this.maxValue, required this.currentValue, this.color = AppTheme.green});

  @override
  Widget build(BuildContext context) {
    final pct = maxValue > 0 ? currentValue / maxValue : 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    Text(value, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: pct.toDouble(),
                    backgroundColor: AppTheme.border,
                    valueColor: AlwaysStoppedAnimation(color),
                    minHeight: 4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionHistoryRow extends StatelessWidget {
  final dynamic session;
  const _SessionHistoryRow({required this.session});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(session.tableName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              Text(formatDate(session.startedAt), style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
            ],
          )),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('\$${session.total.toStringAsFixed(2)}', style: const TextStyle(color: AppTheme.green, fontWeight: FontWeight.w800, fontSize: 15)),
              Text(formatTime(session.elapsedSeconds.toInt()), style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }
}