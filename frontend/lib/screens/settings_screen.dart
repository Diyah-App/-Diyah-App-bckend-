import 'package:flutter/material.dart';
import '../utils/constants.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../widgets/custom_app_bar.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../models/member_model.dart';
import '../utils/constants.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(
        title: 'الإعدادات',
      ),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.language),
            title: const Text('اللغة'),
            subtitle: const Text('العربية'),
            onTap: () {},
          ),
          ListTile(
            leading: const Icon(Icons.dark_mode),
            title: const Text('الوضع الليلي'),
            trailing: Switch(value: false, onChanged: (val) {}),
          ),
          ListTile(
            leading: const Icon(Icons.notifications),
            title: const Text('التنبيهات'),
            onTap: () {},
          ),
          if (AuthService.isLoggedIn) ...[
            const Divider(),
            ListTile(
              leading: const Icon(Icons.lock),
              title: const Text('تغيير كلمة المرور'),
              onTap: () => _changePassword(context),
            ),
            if (AuthService.role == 'owner') ...[
              ListTile(
                leading: const Icon(Icons.person),
                title: const Text('تغيير اسم المستخدم'),
                onTap: () => _changeUsername(context),
              ),
              ListTile(
                leading: const Icon(Icons.cloud_sync, color: Colors.blue),
                title: const Text('تحديث رابط السيرفر (API URL)', style: TextStyle(color: Colors.blue)),
                subtitle: const Text('تحديث الرابط في Firebase لجميع الأجهزة'),
                onTap: () => _manageRemoteApiUrl(context),
              ),
            ]
          ]
        ],
      ),
    );
  }

  void _changePassword(BuildContext context) {
    String newPassword = '';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تغيير كلمة المرور'),
        content: TextField(
          obscureText: true,
          decoration: const InputDecoration(hintText: 'كلمة المرور الجديدة'),
          onChanged: (val) => newPassword = val,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          TextButton(
            onPressed: () async {
              if (newPassword.isNotEmpty) {
                try {
                  final member = Member(id: AuthService.currentUserId, fullName: '', phone: '', isWajeeh: false); // Mock object to pass ID
                  await ApiService.updateMember(member, password: newPassword);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم التغيير بنجاح')));
                  Navigator.pop(ctx);
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل: $e')));
                }
              }
            },
            child: const Text('تغيير'),
          ),
        ],
      ),
    );
  }

  void _changeUsername(BuildContext context) {
    String newUsername = '';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تغيير اسم المستخدم (المالك فقط)'),
        content: TextField(
          decoration: const InputDecoration(hintText: 'اسم المستخدم الجديد'),
          onChanged: (val) => newUsername = val,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          TextButton(
            onPressed: () async {
              if (newUsername.isNotEmpty) {
                try {
                   // This API expects full_name, phone. We might need a dedicated API or adjust updateMember
                   // Since update_member route sets username if provided in data, let's use it.
                  final member = Member(id: AuthService.currentUserId, fullName: '', phone: '', isWajeeh: false);
                  // We need to pass username in json. Let's make an ad-hoc call for simplicity here, or just tweak ApiService later.
                  // Wait, updateMember in ApiService only sends what's in member.toJson(). It doesn't send username.
                  // I will send a direct http request here since it's an edge case.
                  final response = await http.put(
                    Uri.parse('${ApiService.baseUrl}/members/${AuthService.currentUserId}'),
                    headers: {
                      'Content-Type': 'application/json', 
                      'X-User-Id': AuthService.currentUserId.toString(),
                      'X-App-Token': AppConstants.appToken
                    },
                    body: '{"username": "$newUsername"}'
                  );
                  if (response.statusCode == 200) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم التغيير بنجاح')));
                    Navigator.pop(ctx);
                  } else {
                    throw Exception('Server error');
                  }
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل: $e')));
                }
              }
            },
            child: const Text('تغيير'),
          ),
        ],
      ),
    );
  }

  void _changeApiUrl(BuildContext context) {
    String newUrl = AppConstants.baseUrl;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تغيير رابط السيرفر'),
        content: TextField(
          controller: TextEditingController(text: newUrl),
          decoration: const InputDecoration(hintText: 'https://your-api.com/api'),
          onChanged: (val) => newUrl = val,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          TextButton(
            onPressed: () async {
              if (newUrl.isNotEmpty) {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('custom_api_url', newUrl);
                AppConstants.baseUrl = newUrl;
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تغيير الرابط بنجاح! سيتم تطبيقه فوراً.')));
                  Navigator.pop(ctx);
                }
              }
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  void _manageRemoteApiUrl(BuildContext context) {
    String apiUrl = AppConstants.baseUrl;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تحديث رابط السيرفر'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'أدخل الرابط الجديد. سيتم إرساله إلى السيرفر الحالي لكي يرفعه إلى Firebase، ومن ثم ستقوم جميع الأجهزة (بما فيها جهازك) بتحديث وجهتها إلى الرابط الجديد فوراً.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 15),
            TextField(
              decoration: const InputDecoration(labelText: 'API URL', hintText: 'http://127.0.0.1:5000/api'), 
              onChanged: (val) => apiUrl = val, 
              controller: TextEditingController(text: apiUrl)
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () async {
              try {
                // Update remote config via the current working backend
                await ApiService.updateRemoteConfig({'api_url': apiUrl});
                
                // Also update local for immediate effect
                if (apiUrl.isNotEmpty) {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString('custom_api_url', apiUrl);
                  AppConstants.baseUrl = apiUrl;
                }
                
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم رفع الرابط لـ Firebase بنجاح!')));
                  Navigator.pop(ctx);
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e')));
                }
              }
            },
            child: const Text('تحديث لجميع الأجهزة'),
          ),
        ],
      ),
    );
  }
}
