import 'package:flutter/material.dart';
import '../widgets/custom_app_bar.dart';

class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(
        title: 'الشؤون القانونية',
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'سياسة الخصوصية',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.red),
            ),
            const SizedBox(height: 10),
            const Text(
              '''نحن نولي أهمية قصوى لخصوصية وسرية بيانات أفراد العشيرة. يقوم هذا التطبيق بجمع بيانات أساسية (مثل الأسماء وأرقام الهواتف) لغرض تنظيم وإدارة شؤون الديات والتواصل الفعال فقط. 
- لا يتم مشاركة أي من هذه البيانات مع أطراف خارجية أو جهات ثالثة بأي شكل من الأشكال.
- يتم تخزين كلمات المرور بطريقة مشفرة (Hashed) بحيث لا يمكن لأي شخص، حتى الإدارة، الاطلاع عليها.
- يحق للوجهاء والمشرفين إدارة بيانات الأفراد التابعين لهم لضمان دقة وتحديث سجلات العشيرة.''',
              style: TextStyle(fontSize: 16, height: 1.6),
            ),
            const SizedBox(height: 30),
            const Divider(),
            const SizedBox(height: 30),
            const Text(
              'شروط الاستخدام',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.red),
            ),
            const SizedBox(height: 10),
            const Text(
              '''باستخدامك لتطبيق ميثاق الدية العشائرية، فإنك توافق على الشروط التالية:
1. يمنع منعاً باتاً استخدام التطبيق في أغراض خارج نطاق تنظيم العشيرة وحسابات الدية.
2. تقع مسؤولية الحفاظ على سرية كلمات المرور على عاتق المستخدم وصاحب الصلاحية (الوجيه أو الإدارة).
3. يُعد هذا النظام بمثابة أداة رقمية مساعدة لقانون الميثاق العشائري، والالتزامات المادية المترتبة داخله هي التزامات أخلاقية وعشائرية يتكفل بها الأفراد حسب الاتفاق.
4. يحق لإدارة التطبيق (المالك والشيخ) تعديل الصلاحيات وإنزال الرتب أو حذف الأعضاء إذا دعت الحاجة لضمان استقرار النظام.''',
              style: TextStyle(fontSize: 16, height: 1.6),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
