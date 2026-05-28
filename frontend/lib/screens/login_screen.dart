import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../utils/constants.dart';
import '../services/auth_service.dart';
import '../widgets/custom_app_bar.dart';
import '../utils/number_utility.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  Future<void> _login() async {
    setState(() => _isLoading = true);
    final errorMsg = await AuthService.login(
      NumberUtility.cleanNumberString(_usernameController.text),
      _passwordController.text.trim(),
    );
    setState(() => _isLoading = false);

    if (errorMsg == null) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (route) => false,
      );
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ في تسجيل الدخول: $errorMsg'),
          duration: const Duration(seconds: 10),
          action: SnackBarAction(
            label: 'موافق',
            onPressed: () {},
          ),
        ),
      );
    }
  }

  void _showForgotPasswordDialog() {
    String phoneNumber = "";
    String verificationId = "";
    String smsCode = "";
    String newPassword = "";
    bool codeSent = false;
    bool isVerifying = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                title: const Text('نسيت كلمة المرور'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!codeSent) ...[
                        const Text('أدخل رقم هاتفك المسجل في النظام لإرسال رمز التحقق:'),
                        const SizedBox(height: 16),
                        TextField(
                          onChanged: (v) => phoneNumber = v,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'رقم الهاتف (مثال: +96478...)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ] else ...[
                        const Text('أدخل رمز التحقق المرسل لهاتفك وكلمة المرور الجديدة:'),
                        const SizedBox(height: 16),
                        TextField(
                          onChanged: (v) => smsCode = v,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'رمز التحقق (OTP)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          onChanged: (v) => newPassword = v,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'كلمة المرور الجديدة',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      if (isVerifying)
                        const CircularProgressIndicator()
                      else if (!codeSent)
                        ElevatedButton(
                          onPressed: () async {
                            if (phoneNumber.isEmpty) return;
                            setDialogState(() => isVerifying = true);
                            try {
                              await FirebaseAuth.instance.verifyPhoneNumber(
                                phoneNumber: phoneNumber.trim(),
                                verificationCompleted: (PhoneAuthCredential credential) {},
                                verificationFailed: (FirebaseAuthException e) {
                                  setDialogState(() => isVerifying = false);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('فشل الإرسال: ${e.message}')),
                                  );
                                },
                                codeSent: (String vid, int? forceResendingToken) {
                                  setDialogState(() {
                                    verificationId = vid;
                                    codeSent = true;
                                    isVerifying = false;
                                  });
                                },
                                codeAutoRetrievalTimeout: (String vid) {},
                              );
                            } catch (e) {
                              setDialogState(() => isVerifying = false);
                            }
                          },
                          child: const Text('إرسال الرمز'),
                        )
                      else
                        ElevatedButton(
                          onPressed: isVerifying ? null : () async {
                            if (smsCode.isEmpty || newPassword.isEmpty) return;
                            setDialogState(() => isVerifying = true);
                            try {
                              // 1. Verify OTP with Firebase
                              PhoneAuthCredential credential = PhoneAuthProvider.credential(
                                verificationId: verificationId,
                                smsCode: smsCode,
                              );
                              await FirebaseAuth.instance.signInWithCredential(credential);
                              
                              // 2. Update password in our backend
                              final response = await http.post(
                                Uri.parse('${AppConstants.baseUrl}/reset-password'),
                                headers: {
                                  'Content-Type': 'application/json',
                                  'X-App-Token': AppConstants.appToken,
                                },
                                body: jsonEncode({
                                  'phone': NumberUtility.cleanNumberString(phoneNumber).replaceAll('+', ''),
                                  'new_password': newPassword,
                                }),
                              );

                              if (response.statusCode == 200) {
                                if (!context.mounted) return;
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('تم تغيير كلمة المرور بنجاح!')),
                                );
                              } else {
                                throw "فشل التحديث في السيرفر";
                              }
                            } catch (e) {
                              setDialogState(() => isVerifying = false);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('خطأ: $e')),
                              );
                            }
                          },
                          child: const Text('تأكيد التغيير'),
                        ),
                    ],
                  ),
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
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: const CustomAppBar(title: 'تسجيل الدخول'),
        body: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: 'اسم المستخدم (أو رقم الهاتف)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: 'كلمة المرور',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                    onPressed: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                  ),
                ),
              ),
              const SizedBox(height: 24),
              _isLoading
                  ? const CircularProgressIndicator()
                  : ElevatedButton(
                      onPressed: _login,
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 50),
                      ),
                      child: const Text('دخول'),
                    ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _showForgotPasswordDialog,
                child: const Text('نسيت كلمة المرور؟', style: TextStyle(color: Colors.blue)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
