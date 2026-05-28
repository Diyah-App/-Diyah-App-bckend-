import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart' as intl;
import '../models/member_model.dart';
import '../models/diyah_model.dart';
import '../services/api_service.dart';
import '../widgets/smart_search_bar.dart';
import '../widgets/member_tile.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import 'diyah_details_screen.dart';
import '../widgets/custom_app_bar.dart';

class MemberDetailsScreen extends StatefulWidget {
  final Member member;

  const MemberDetailsScreen({super.key, required this.member});

  @override
  State<MemberDetailsScreen> createState() => _MemberDetailsScreenState();
}

class _MemberDetailsScreenState extends State<MemberDetailsScreen> {
  late Member _member;
  List<Diyah> _caused = [];
  List<Diyah> _paid = [];
  List<Diyah> _partiallyPaid = [];
  List<Diyah> _pending = [];
  List<Diyah> _notLiable = [];
  List<Member> _followers = [];
  bool _isLoading = true;
  String _causedSearch = "";
  String _paidSearch = "";
  String _partiallyPaidSearch = "";
  String _pendingSearch = "";
  String _notLiableSearch = "";
  String _followersSearch = "";

  @override
  void initState() {
    super.initState();
    _member = widget.member;
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      final history = await ApiService.getMemberHistory(_member.id!);
      final allMembers = await ApiService.getMembers();
      if (!mounted) return;

      // Followers = members whose wajeehId matches this member's id
      // Exclude the wajeeh himself and ensure wajeehId is not null
      final followers = allMembers.where((m) {
        return m.wajeehId != null && 
               m.wajeehId == _member.id && 
               m.id != _member.id;
      }).toList();

      setState(() {
        _caused = history['caused'] ?? [];
        _paid = history['paid'] ?? [];
        _partiallyPaid = history['partially_paid'] ?? [];
        _pending = history['not_paid'] ?? [];
        _notLiable = history['not_liable'] ?? [];
        _followers = followers;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _makeCall() async {
    final Uri launchUri = Uri(scheme: 'tel', path: _member.phone);
    if (await canLaunchUrl(launchUri)) await launchUrl(launchUri);
  }

  @override
  Widget build(BuildContext context) {
    final currencyFmt = intl.NumberFormat('#,##0.##');

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: const CustomAppBar(title: 'ملف العضو'),
        body: _isLoading 
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  _buildHeader(),
                  const SizedBox(height: 12),
                  _buildBalanceCard(currencyFmt),
                  const SizedBox(height: 16),
                  _buildManagementSection(),
                  const SizedBox(height: 24),
                  _buildStatsSection(),
                  const SizedBox(height: 24),
                  if (_member.isWajeeh) ...[
                    _buildFollowersSection(),
                    const SizedBox(height: 24),
                  ],
                  _buildDiyahHistorySection('ديات هو صاحبها', _caused, Colors.red, _causedSearch, (val) => setState(() => _causedSearch = val)),
                  _buildDiyahHistorySection('ديات تم تسديدها بالكامل', _paid, Colors.green, _paidSearch, (val) => setState(() => _paidSearch = val)),
                  _buildDiyahHistorySection('الديات قيد التسديد (مدفوعة جزئياً)', _partiallyPaid, Colors.amber.shade800, _partiallyPaidSearch, (val) => setState(() => _partiallyPaidSearch = val)),
                  _buildDiyahHistorySection('ديات قيد التحصيل (غير مدفوعة)', _pending, Colors.orange, _pendingSearch, (val) => setState(() => _pendingSearch = val)),
                  _buildDiyahHistorySection('ديات قديمة (غير مشمول)', _notLiable, Colors.blueGrey, _notLiableSearch, (val) => setState(() => _notLiableSearch = val)),
                ],
              ),
            ),
      ),
    );
  }

  Widget _buildBalanceCard(intl.NumberFormat currencyFmt) {
    final isNegative = _member.balance < 0;
    final isPositive = _member.balance > 0;
    final balanceColor = isNegative 
        ? Colors.red.shade700 
        : isPositive 
            ? Colors.green.shade700 
            : Colors.grey.shade700;
    final balanceBg = isNegative 
        ? Colors.red.shade50 
        : isPositive 
            ? Colors.green.shade50 
            : Colors.grey.shade100;
    final balanceText = isNegative 
        ? 'مطلوب ذمة مالية: ${currencyFmt.format(_member.balance.abs())} د.ع'
        : isPositive
            ? 'له رصيد فائض: +${currencyFmt.format(_member.balance)} د.ع'
            : 'الرصيد: مسدد بالكامل (صفر د.ع)';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: balanceBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: balanceColor.withAlpha(80), width: 1.5),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isNegative 
                ? Icons.warning_amber_rounded 
                : isPositive 
                    ? Icons.account_balance_wallet 
                    : Icons.check_circle_outline,
            color: balanceColor,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              balanceText,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: balanceColor,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        CircleAvatar(
          radius: 40, 
          backgroundColor: _member.isWajeeh ? Colors.amber.shade100 : Colors.blue.shade100, 
          child: Icon(
            _member.isWajeeh ? Icons.star : Icons.person, 
            size: 40, 
            color: _member.isWajeeh ? Colors.amber : Colors.blue
          )
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_member.fullName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            _buildRoleBadge(),
          ],
        ),
        Text(_member.phone, style: const TextStyle(color: Colors.grey)),
        IconButton(icon: const Icon(Icons.call, color: Colors.green), onPressed: _makeCall),
      ],
    );
  }

  Widget _buildRoleBadge() {
    String adminRoleName = "";
    Color adminRoleColor = Colors.transparent;

    if (_member.role == 'sheikh') {
      adminRoleName = "شيخ";
      adminRoleColor = Colors.orange.shade800;
    } else if (_member.role == 'admin') {
      adminRoleName = "مشرف";
      adminRoleColor = Colors.red.shade700;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (adminRoleName.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(left: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: adminRoleColor.withAlpha(40),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: adminRoleColor.withAlpha(60)),
            ),
            child: Text(
              adminRoleName,
              style: TextStyle(
                fontSize: 12,
                color: adminRoleColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: _member.isWajeeh ? Colors.amber.withAlpha(50) : Colors.blue.withAlpha(50),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Text(
            _member.isWajeeh ? 'وجيه' : 'عضو',
            style: TextStyle(
              fontSize: 12,
              color: _member.isWajeeh ? Colors.amber.shade900 : Colors.blue.shade900,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatsSection() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildStatCard('صاحب الدية', _caused.length.toString(), Colors.red),
        _buildStatCard('المدفوعة', _paid.length.toString(), Colors.green),
        _buildStatCard('المتبقية', _pending.length.toString(), Colors.orange),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _buildDiyahHistorySection(String title, List<Diyah> diyahs, Color color, String currentSearch, Function(String) onSearchChanged) {
    final filtered = diyahs.where((d) => 
      SmartSearchBar.matches(d.title, currentSearch)
    ).toList();

    return ExpansionTile(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            decoration: BoxDecoration(color: color.withAlpha(30), borderRadius: BorderRadius.circular(10)),
            child: Text(diyahs.length.toString(), style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
          ),
        ],
      ),
      children: [
        if (diyahs.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SmartSearchBar(
              hintText: 'بحث في هذه القائمة...',
              onChanged: onSearchChanged,
            ),
          ),
        if (filtered.isEmpty && diyahs.isNotEmpty)
          const ListTile(title: Text('لا توجد نتائج تطابق بحثك', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey))),
        if (diyahs.isEmpty)
          const ListTile(title: Text('لا يوجد سجل حالياً'))
        else
          ...filtered.map((d) {
            final double share = d.memberShare ?? d.sharePerMember;
            final double payment = d.memberPayment ?? 0.0;
            final double remaining = share - payment;
            final fmt = intl.NumberFormat('#,##0.##');
            return ListTile(
              title: Text(d.title, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('إجمالي الدية: ${fmt.format(d.amount)} د.ع'),
                  Row(
                    children: [
                      Text('المطلوب: ${fmt.format(share)} د.ع', 
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey, fontSize: 13)),
                      const SizedBox(width: 16),
                      Text('المسدد: ${fmt.format(payment)} د.ع', 
                        style: TextStyle(fontWeight: FontWeight.bold, color: payment > 0 ? Colors.green.shade700 : Colors.red, fontSize: 13)),
                      const SizedBox(width: 16),
                      Text(
                        remaining > 0 
                            ? 'المتبقي: ${fmt.format(remaining)} د.ع' 
                            : (remaining < 0 ? 'الفائض: ${fmt.format(remaining.abs())} د.ع' : 'المتبقي: صفر (مسدد)'),
                        style: TextStyle(
                          fontWeight: FontWeight.bold, 
                          color: remaining > 0 
                              ? Colors.orange.shade800 
                              : (remaining < 0 ? Colors.green.shade700 : Colors.green.shade800), 
                          fontSize: 13
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              trailing: const Icon(Icons.chevron_left),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (ctx) => DiyahDetailsScreen(diyah: d)),
                ).then((_) => _loadHistory());
              },
            );
          }),
      ],
    );
  }

  Widget _buildFollowersSection() {
    final filtered = _followers.where((m) => 
      SmartSearchBar.matches(m.fullName, _followersSearch) || 
      SmartSearchBar.matches(m.phone, _followersSearch)
    ).toList();

    return ExpansionTile(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('الأعضاء التابعين', style: TextStyle(color: Colors.blueGrey, fontWeight: FontWeight.bold)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            decoration: BoxDecoration(color: Colors.blueGrey.withAlpha(30), borderRadius: BorderRadius.circular(10)),
            child: Text(_followers.length.toString(), style: const TextStyle(color: Colors.blueGrey, fontWeight: FontWeight.bold, fontSize: 12)),
          ),
        ],
      ),
      children: [
        if (_followers.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SmartSearchBar(
              hintText: 'بحث في التابعين...',
              onChanged: (val) => setState(() => _followersSearch = val),
            ),
          ),
        if (filtered.isEmpty && _followers.isNotEmpty)
          const ListTile(title: Text('لا توجد نتائج تطابق بحثك', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey))),
        if (_followers.isEmpty)
          const ListTile(title: Text('لا يوجد تابعين حالياً'))
        else
          ...filtered.map((m) => MemberTile(
            member: m,
            onRefresh: _loadHistory,
          )),
      ],
    );
  }

  Widget _buildManagementSection() {
    final myRole = AuthService.role;
    if (myRole != 'owner' && myRole != 'sheikh') return const SizedBox.shrink();
    if (_member.role == 'owner') return const SizedBox.shrink();

    bool isSheikh = _member.role == 'sheikh';
    bool isAdmin = _member.role == 'admin';

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.admin_panel_settings, size: 20, color: Colors.blueGrey),
                SizedBox(width: 8),
                Text('إدارة الرتب والصلاحيات', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
              ],
            ),
            const Divider(),
            SwitchListTile(
              title: const Text('ترقية إلى شيخ'),
              subtitle: const Text('صلاحيات كاملة للمالك والشيخ فقط'),
              value: isSheikh,
              secondary: const Icon(Icons.star, color: Colors.amber),
              onChanged: myRole == 'owner' ? (val) => _handleRoleSwitch('sheikh', val) : null,
            ),
            SwitchListTile(
              title: const Text('ترقية إلى مشرف (أدمن)'),
              subtitle: const Text('صلاحيات إدارة الأعضاء والديات'),
              value: isAdmin,
              secondary: const Icon(Icons.security, color: Colors.red),
              onChanged: (val) => _handleRoleSwitch('admin', val)
            ),
            if (!isSheikh && !isAdmin)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Text(
                  _member.isWajeeh ? 'الحالة الحالية: وجيه (مستخدم عادي)' : 'الحالة الحالية: عضو (مستخدم عادي)',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _handleRoleSwitch(String roleToToggle, bool value) async {
    String newRole;
    if (value) {
      newRole = roleToToggle;
    } else {
      // If we turn off a role, they revert to their base type
      newRole = _member.isWajeeh ? 'wajeeh' : 'member';
    }

    String? password;
    if (newRole == 'admin' && !_member.isWajeeh && _member.id != AuthService.currentUserId) {
      password = await _askForPassword();
      if (password == null || password.isEmpty) return;
    }

    try {
      final response = await ApiService.changeUserRole(_member.id!, newRole, password: password);
      setState(() {
        _member = Member.fromJson(response['member']);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تحديث الرتبة بنجاح')));
        NotificationService().addRefreshRequest();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e')));
    }
  }

  Future<String?> _askForPassword() {
    String p = '';
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تعيين كلمة مرور للمشرف الجديد'),
        content: TextField(
          onChanged: (v) => p = v,
          obscureText: true,
          decoration: const InputDecoration(hintText: 'كلمة المرور'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(ctx, p), child: const Text('تعيين')),
        ],
      )
    );
  }
}
