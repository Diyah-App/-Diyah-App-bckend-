import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/foundation.dart'; // Add kIsWeb and defaultTargetPlatform
import 'package:firebase_remote_config/firebase_remote_config.dart';
import '../utils/constants.dart';
import '../widgets/custom_app_bar.dart';
import 'legal_screen.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  Future<void> _launchInstagram(BuildContext context) async {
    final Uri url = Uri.parse('https://www.instagram.com/q.e_lith_j.s/'); 
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر فتح الرابط')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(
        title: 'حول التطبيق',
      ),
      body: SelectionArea(
        child: SingleChildScrollView(
          child: Column(
          children: [
            const SizedBox(height: 40),
            // App Logo / Icon (Circular)
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Theme.of(context).colorScheme.primary, width: 2),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 10, spreadRadius: 2)
                ],
              ),
              child: ClipOval(
                child: Image.asset(
                  'assets/images/logo.png',
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Icon(Icons.shield, size: 60, color: Theme.of(context).colorScheme.primary),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'ميثاق الدية العشائرية',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
            ),
            const Text(
              'الإصدار 1.0.0',
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
            const SizedBox(height: 32),

            // Concept & Idea
            _buildSectionCard(
              context,
              title: 'فكرة التطبيق',
              icon: Icons.menu_book_rounded,
              content: 'انطلاقاً من الشعور بالمسؤولية واستجابة لمقتضيات المصلحة العامة لعشائر بني حمدان والمناشدات المستمرة من قبل الأعمام، فقد اجتمعت نخبة خيرة من الرجال المخلصين والصادقين في مجلس الشورى بمضيف الشيخ عبيد السهر.\n\n'
                  'وتمت صياغة فكرة هذا النظام ليكون بمثابة قانون عشائري وتطبيق رقمي متكامل يوفر الحماية لكل من ينتمي إليه، لضبط وتنظيم حسابات الديات وتوزيعها بشفافية عالية وعدالة تامة، ليكون سنداً وعوناً في أوقات الشدائد والملمات.\n\n'
                  'تم إعداد وتوجيه فكرة هذا النظام بناءً على مخرجات مجلس الشورى واجتماع رجالات العشيرة، وبمتابعة وإشراف مباشر من قبل:\nالشيخ حميد عبيد السهر.',
            ),

            // Developer / Contact
            _buildSectionCard(
              context,
              title: 'الإعداد والتطوير والبرمجة',
              icon: Icons.code,
              content: 'تم تصميم وتطوير وبرمجة هذا النظام بأحدث التقنيات البرمجية وأعلى معايير الأمن السيبراني لضمان سرية وسلامة بيانات العشيرة، بواسطة المبرمج:\nليث جاسم محمد الحمداني',
              child: Padding(
                padding: const EdgeInsets.only(top: 16.0),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _launchInstagram(context),
                    icon: const FaIcon(FontAwesomeIcons.instagram, color: Colors.white),
                    label: const Text('تواصل مع المبرمج على إنستغرام', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE1306C), // Instagram Official Color
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 3,
                    ),
                  ),
                ),
              ),
            ),

            if (kIsWeb) ...[
              const SizedBox(height: 30),
              _buildWebDownloadSection(context),
            ],

            const SizedBox(height: 10),
            
            // Legal Button
            TextButton.icon(
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => const LegalScreen()));
              },
              icon: const Icon(Icons.gavel, color: Colors.blueGrey),
              label: const Text(
                'سياسة الخصوصية وشروط الاستخدام',
                style: TextStyle(color: Colors.blueGrey, decoration: TextDecoration.underline, fontSize: 14),
              ),
            ),

            const SizedBox(height: 20),
            const Text(
              '© 2026 جميع الحقوق محفوظة',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 40),
          ],
        ),
      )),
    );
  }

  Widget _buildSectionCard(BuildContext context, {required String title, required IconData icon, required String content, Widget? child}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
      child: Card(
        elevation: 3,
        shadowColor: Colors.black.withOpacity(0.3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.red.withOpacity(0.3), width: 1)),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), shape: BoxShape.circle),
                    child: Icon(icon, color: Colors.red, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const Divider(height: 30),
              Text(
                content,
                style: const TextStyle(fontSize: 15, height: 1.8),
              ),
              if (child != null) child,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWebDownloadSection(BuildContext context) {
    String selectedPlatform = 'android';
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      selectedPlatform = 'ios';
    } else if (defaultTargetPlatform == TargetPlatform.macOS) {
      selectedPlatform = 'macos';
    } else if (defaultTargetPlatform == TargetPlatform.windows) {
      selectedPlatform = 'windows';
    } else if (defaultTargetPlatform == TargetPlatform.linux) {
      selectedPlatform = 'linux';
    }

    return StatefulBuilder(
      builder: (context, setState) {
        return _buildSectionCard(
          context,
          title: 'تحميل التطبيق',
          icon: Icons.download_rounded,
          content: 'قم بتحميل التطبيق ليعمل بكفاءة أعلى على جهازك:',
          child: Padding(
            padding: const EdgeInsets.only(top: 16.0),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: selectedPlatform,
                        isExpanded: true,
                        items: const [
                          DropdownMenuItem(value: 'android', child: Text('Android')),
                          DropdownMenuItem(value: 'ios', child: Text('iOS (iPhone)')),
                          DropdownMenuItem(value: 'windows', child: Text('Windows')),
                          DropdownMenuItem(value: 'macos', child: Text('MacBook')),
                          DropdownMenuItem(value: 'linux', child: Text('Linux')),
                        ],
                        onChanged: (val) {
                          if (val != null) setState(() => selectedPlatform = val);
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 3,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      // Construct download link using the smart backend endpoint!
                      String baseUrl = AppConstants.baseUrl;
                      String downloadLink = '';
                      if (selectedPlatform == 'android') downloadLink = '$baseUrl/download/android';
                      else if (selectedPlatform == 'ios') downloadLink = '$baseUrl/download/ios';
                      else if (selectedPlatform == 'windows') downloadLink = '$baseUrl/download/windows';
                      else if (selectedPlatform == 'macos') downloadLink = '$baseUrl/download/macos';
                      else if (selectedPlatform == 'linux') downloadLink = '$baseUrl/download/linux';
                      
                      launchUrl(Uri.parse(downloadLink), mode: LaunchMode.externalApplication);
                    },
                    icon: const Icon(Icons.download),
                    label: const Text('تحميل'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    );
  }
}
