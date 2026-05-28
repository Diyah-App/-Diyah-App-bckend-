import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/notification_service.dart';
import '../services/auth_service.dart';
import '../widgets/custom_app_bar.dart';
import 'members_screen.dart';
import 'diyahs_screen.dart';
import 'about_screen.dart';
import 'settings_screen.dart';
import 'login_screen.dart';
import '../data/covenant_data.dart';
class HomeScreen extends StatefulWidget {
  final bool needsUpdate;
  final String updateUrl;
  
  const HomeScreen({
    super.key, 
    this.needsUpdate = false, 
    this.updateUrl = ""
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  // Use lazy initialization to strictly avoid 'undefined' issues in JS/Web runtimes
  List<GlobalKey<NavigatorState>>? _keys;
  List<GlobalKey<NavigatorState>> get _navigatorKeys {
    _keys ??= List.generate(5, (_) => GlobalKey<NavigatorState>());
    return _keys!;
  }

  void _onTap(int index) {
    if (_currentIndex == index) {
      _navigatorKeys[index].currentState?.popUntil((route) => route.isFirst);
    } else {
      setState(() {
        _currentIndex = index;
      });
    }
  }

  Widget _buildNavigator(int index) {
    return Navigator(
      key: _navigatorKeys[index],
      onGenerateRoute: (settings) {
        return MaterialPageRoute(
          builder: (context) {
            switch (index) {
              case 0: return _EmptyHome(needsUpdate: widget.needsUpdate, updateUrl: widget.updateUrl);
              case 1: return const MembersScreen();
              case 2: return const DiyahsScreen();
              case 3: return const AboutScreen();
              case 4: return const SettingsScreen();
              default: return _EmptyHome(needsUpdate: widget.needsUpdate, updateUrl: widget.updateUrl);
            }
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) return;
          
          final NavigatorState? currentNavigator = _navigatorKeys[_currentIndex].currentState;
          if (currentNavigator != null && currentNavigator.canPop()) {
            currentNavigator.pop();
          } else {
            if (_currentIndex != 0) {
              setState(() {
                _currentIndex = 0;
              });
            }
          }
        },
        child: Scaffold(
          body: IndexedStack(
            index: _currentIndex,
            children: [
              _buildNavigator(0),
              _buildNavigator(1),
              _buildNavigator(2),
              _buildNavigator(3),
              _buildNavigator(4),
            ],
          ),
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: _currentIndex,
            type: BottomNavigationBarType.fixed,
            selectedItemColor: Colors.blue,
            unselectedItemColor: Colors.grey,
            onTap: _onTap,
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.home), label: 'الرئيسية'),
              BottomNavigationBarItem(icon: Icon(Icons.people), label: 'الوجهاء والأعضاء'),
              BottomNavigationBarItem(icon: Icon(Icons.history_edu), label: 'سجل الديات'),
              BottomNavigationBarItem(icon: Icon(Icons.info), label: 'حول'),
              BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'الإعدادات'),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyHome extends StatefulWidget {
  final bool needsUpdate;
  final String updateUrl;
  
  const _EmptyHome({required this.needsUpdate, required this.updateUrl});

  @override
  State<_EmptyHome> createState() => _EmptyHomeState();
}

class _EmptyHomeState extends State<_EmptyHome> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(
        title: 'ميثاق الدية العشائرية',
        showBackButton: false,
        bottom: widget.needsUpdate ? PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: Container(
            color: Colors.orange.shade800,
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: InkWell(
              onTap: () {
                launchUrl(Uri.parse(widget.updateUrl), mode: LaunchMode.externalApplication);
              },
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.system_update, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'يتوفر تحديث جديد للميثاق، اضغط هنا للتحميل',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
        ) : null,
      ),
      body: SelectionArea(
        child: Container(
          color: Colors.grey.shade50,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
            children: [
              _buildHeaderSection(),
              const SizedBox(height: 16),
              ...covenantSections.asMap().entries.map((entry) {
                final index = entry.key;
                final section = entry.value;
                return Card(
                  elevation: 2,
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: ExpansionTile(
                    iconColor: Theme.of(context).primaryColor,
                    collapsedIconColor: Colors.grey.shade700,
                    title: Text(
                      section.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    leading: Icon(
                      _getIconForSection(index),
                      color: Theme.of(context).primaryColor,
                    ),
                    childrenPadding: const EdgeInsets.all(16),
                    expandedCrossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Divider(height: 1),
                      const SizedBox(height: 12),
                      Text(
                        section.content,
                        style: const TextStyle(
                          fontSize: 15,
                          height: 1.8,
                          color: Colors.black87,
                        ),
                        textAlign: TextAlign.justify,
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderSection() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final bismFont  = w < 360 ? 18.0 : w < 420 ? 21.0 : 24.0;
        final ayahFont  = w < 360 ? 14.0 : w < 420 ? 17.0 : 20.0;
        final titleFont = w < 360 ? 14.0 : w < 420 ? 16.0 : 20.0;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 10),
            Text(
              'بِسْمِ اللَّهِ الرَّحْمَنِ الرَّحِيمِ',
              style: TextStyle(fontSize: bismFont, fontWeight: FontWeight.bold, color: Colors.black87),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              'قال تعالى: {وَتَعَاوَنُوا عَلَى الْبِرِّ وَالتَّقْوَى وَلَا تَعَاوَنُوا عَلَى الْإِثْمِ وَالْعُدْوَانِ}',
              style: TextStyle(fontSize: ayahFont, height: 1.8, color: Colors.green.shade900, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            // Single centered title line — no dividers, FittedBox keeps it on ONE line always
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'ميثاق الدية العشائرية لعشائر البو حمدان',
                style: TextStyle(
                  fontSize: titleFont,
                  fontWeight: FontWeight.bold,
                  color: Colors.brown.shade900,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
              ),
            ),
            const SizedBox(height: 10),
          ],
        );
      },
    );
  }

  IconData _getIconForSection(int index) {
    switch (index) {
      case 0: return Icons.menu_book; // المقدمة
      case 1: return Icons.info_outline; // تعريف الدية
      case 2: return Icons.gavel; // مهام مجلس الشورى
      case 3: return Icons.account_balance_wallet; // مسؤولية الدية
      case 4: return Icons.payments; // أبواب دفع الدية
      case 5: return Icons.block; // الحالات التي لا تدفع فيها
      case 6: return Icons.verified; // الخاتمة
      default: return Icons.article;
    }
  }
}
