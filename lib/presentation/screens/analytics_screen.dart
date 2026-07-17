import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<Map<String, dynamic>> _periods = [];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.bgDark : AppColors.bgLight,
      appBar: AppBar(
        title: const Text('Attendance Analytics', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: isDark ? Colors.white : AppColors.textPrimaryLight,
      ),
      body: _periods.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.analytics_outlined, size: 64,
                      color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.15)),
                  const SizedBox(height: 16),
                  Text('No analytics data yet',
                      style: TextStyle(fontSize: 16,
                          color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.4))),
                  const SizedBox(height: 8),
                  Text('Analytics will appear once attendance sessions are completed.',
                      style: TextStyle(fontSize: 13,
                          color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.25))),
                ],
              ),
            )
          : Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Stats Row
            Row(
              children: (_periods[_currentPage]['stats'] as List).map<Widget>((stat) {
                return _buildStatCard(
                  stat['label'],
                  stat['value'],
                  stat['icon'],
                  stat['color'],
                  isDark,
                );
              }).toList().expand((widget) => [widget, const SizedBox(width: 24)]).toList()..removeLast(),
            ),
            const SizedBox(height: 48),

            // Dynamic Heading
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _periods[_currentPage]['title'],
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                ),
                Row(
                  children: List.generate(_periods.length, (index) => Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(left: 8),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _currentPage == index
                        ? AppColors.primaryTeal
                        : (isDark ? Colors.white10 : Colors.black12),
                    ),
                  )),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Swipeable Chart Card
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (index) => setState(() => _currentPage = index),
                itemCount: _periods.length,
                itemBuilder: (context, index) {
                  final data = _periods[index];
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Attendance Distribution',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : AppColors.textPrimaryLight,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppColors.primaryTeal.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                'Real-time',
                                style: TextStyle(
                                  color: AppColors.primaryTeal,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 40),
                        Expanded(
                          child: _buildDemograph(
                            data['chartData'] as List<double>,
                            data['chartLabels'] as List<String>,
                            isDark,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
            Center(
              child: Text(
                'Swipe left or right to switch periods',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white24 : Colors.black.withValues(alpha: 0.24),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDemograph(List<double> data, List<String> labels, bool isDark) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(data.length, (index) {
        return Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                '${(data[index] * 100).toInt()}%',
                style: TextStyle(
                  fontSize: 10,
                  color: isDark ? Colors.white38 : Colors.black38,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        AppColors.primaryTeal,
                        AppColors.primaryTeal.withValues(alpha: 0.3),
                      ],
                    ),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                  ),
                  height: double.infinity,
                  child: FractionallySizedBox(
                    heightFactor: data[index],
                    alignment: Alignment.bottomCenter,
                    child: Container(),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                labels[index],
                style: TextStyle(
                  fontSize: 10,
                  color: isDark ? Colors.white38 : Colors.black38,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color, bool isDark) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 24),
            Text(value, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
            Text(label, style: const TextStyle(color: Colors.grey, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}
