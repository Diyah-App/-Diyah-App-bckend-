import 'dart:async';
import 'package:flutter/material.dart';
import '../models/member_model.dart';
import '../services/api_service.dart';
import '../widgets/custom_app_bar.dart';
import '../theme/app_theme.dart';
import '../widgets/member_tile.dart';
import '../widgets/smart_search_bar.dart';
import 'member_details_screen.dart';
import '../utils/number_utility.dart';

import '../services/notification_service.dart';
import '../services/auth_service.dart';

class MembersScreen extends StatefulWidget {
  const MembersScreen({super.key});

  @override
  State<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends State<MembersScreen> {
  List<Member> _allMembers = [];
  List<Member> _filteredMembers = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _filterType = 'الكل'; // 'الكل', 'وجهاء', 'أعضاء'

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _isWajeeh = false;
  int? _selectedWajeehId;

  late StreamSubscription _refreshSubscription;

  @override
  void initState() {
    super.initState();
    _fetchMembers();
    _refreshSubscription = NotificationService().onRefreshRequired.listen((_) {
      if (mounted) _fetchMembers();
    });
  }

  @override
  void dispose() {
    _refreshSubscription.cancel();
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _fetchMembers() async {
    setState(() => _isLoading = true);
    try {
      final members = await ApiService.getMembers();
      setState(() {
        _allMembers = members;
        _applyFilters();
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في جلب البيانات: $e')),
        );
      }
      setState(() => _isLoading = false);
    }
  }

  void _applyFilters() {
    setState(() {
      _filteredMembers = _allMembers.where((m) {
        // Using Global Smart Match Logic
        final matchesName = SmartSearchBar.matches(m.fullName, _searchQuery);
        final matchesPhone = SmartSearchBar.matches(m.phone, _searchQuery);
        
        bool categoryMatch = true;
        if (_filterType == 'وجهاء') categoryMatch = m.isWajeeh;
        if (_filterType == 'أعضاء') categoryMatch = !m.isWajeeh;

        return (matchesName || matchesPhone) && categoryMatch;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: const CustomAppBar(
          title: 'إدارة الوجهاء والأعضاء',
        ),
        body: Column(
          children: [
            _buildSearchAndFilters(),

            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredMembers.isEmpty
                      ? const Center(child: Text('لا يوجد نتائج تطابق البحث.'))
                      : _filterType == 'الكل' && _searchQuery.isEmpty
                          ? _buildGroupedMembersList()
                          : _buildMembersList(),
            ),
          ],
        ),
        floatingActionButton: ['owner', 'sheikh', 'admin', 'wajeeh'].contains(AuthService.role) ? FloatingActionButton(
          heroTag: 'members_fab',
          onPressed: () => _showMemberDialog(),
          backgroundColor: AppColors.primary,
          child: const Icon(Icons.add, color: Colors.white),
        ) : null,
      ),
    );
  }

  Widget _buildSearchAndFilters() {
    // Fixed counts always from full list, not filtered
    final totalAll = _allMembers.length;
    final totalWajeehs = _allMembers.where((m) => m.isWajeeh).length;
    final totalMembers = totalAll - totalWajeehs;

    final counts = {
      'الكل': totalAll,
      'وجهاء': totalWajeehs,
      'أعضاء': totalMembers,
    };
    final colors = {
      'الكل': Colors.blue,
      'وجهاء': Colors.amber.shade700,
      'أعضاء': Colors.green,
    };

    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Column(
        children: [
          SmartSearchBar(
            hintText: 'ابحث عن اسم أو رقم هاتف...',
            onChanged: (value) {
              _searchQuery = value;
              _applyFilters();
            },
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: ['الكل', 'وجهاء', 'أعضاء'].map((type) {
              final isSelected = _filterType == type;
              final count = counts[type]!;
              final color = colors[type]!;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: GestureDetector(
                  onTap: () => setState(() {
                    _filterType = type;
                    _applyFilters();
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? color.withAlpha(30) : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected ? color : Colors.grey.shade300,
                        width: isSelected ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isSelected)
                          Icon(Icons.check, size: 14, color: color),
                        if (isSelected) const SizedBox(width: 4),
                        Text(
                          type,
                          style: TextStyle(
                            color: isSelected ? color : Colors.grey.shade700,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: isSelected ? color : Colors.grey.shade400,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            count.toString(),
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildMembersList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _filteredMembers.length,
      itemBuilder: (context, index) {
        final member = _filteredMembers[index];
        return _buildMemberTile(member);
      },
    );
  }

  Widget _buildGroupedMembersList() {
    // Only Wajeehs at the top level
    final wajeehs = _filteredMembers.where((m) => m.isWajeeh).toList();
    // Members who don't have a wajeeh and aren't wajeehs themselves (rare if data is clean)
    final orphans = _filteredMembers.where((m) => !m.isWajeeh && m.wajeehId == null).toList();

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        ...wajeehs.map((wajeeh) {
          final followers = _allMembers.where((m) => m.wajeehId == wajeeh.id).toList();
          if (followers.isEmpty) return _buildMemberTile(wajeeh);

          return Card(
            elevation: 0,
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            child: ExpansionTile(
              shape: const RoundedRectangleBorder(side: BorderSide.none),
              collapsedShape: const RoundedRectangleBorder(side: BorderSide.none),
              leading: CircleAvatar(
                backgroundColor: AppColors.primary.withAlpha(30),
                child: Text(wajeeh.fullName[0], style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
              ),
              title: Row(
                children: [
                  Expanded(child: Text(wajeeh.fullName, style: const TextStyle(fontWeight: FontWeight.bold))),
                  if (wajeeh.role == 'sheikh') 
                    _buildInPlaceBadge("شيخ", Colors.orange.shade800)
                  else if (wajeeh.role == 'admin')
                    _buildInPlaceBadge("مشرف", Colors.red.shade700),
                ],
              ),
              subtitle: Text('وجيه | ${wajeeh.phone} | ${followers.length} تابعين', style: const TextStyle(fontSize: 12, color: Colors.amber)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                   IconButton(
                     icon: const Icon(Icons.info_outline, color: AppColors.primary, size: 22),
                     tooltip: 'تفاصيل الوجيه',
                     onPressed: () => Navigator.push(
                       context,
                       MaterialPageRoute(builder: (ctx) => MemberDetailsScreen(member: wajeeh)),
                     ),
                   ),
                   _buildMemberActions(wajeeh),
                   const Icon(Icons.expand_more),
                ],
              ),
              children: followers.map((m) => Padding(
                padding: const EdgeInsets.only(right: 16.0),
                child: _buildMemberTile(m),
              )).toList(),
            ),
          );
        }),
        ...orphans.map((m) => _buildMemberTile(m)),
      ],
    );
  }

  Widget _buildMemberTile(Member member) {
    return MemberTile(
      member: member,
      onRefresh: _fetchMembers,
      trailing: _buildMemberActions(member),
    );
  }

  Widget _buildMemberActions(Member member) {
    final role = AuthService.role;
    final currentId = AuthService.currentUserId;
    
    bool canEdit = false;
    bool canDelete = false;
    bool canAddFollower = false;
    bool canChangePassword = false;

    if (role == 'owner' || role == 'sheikh' || role == 'admin') {
      canEdit = true;
      canDelete = true;
      canAddFollower = member.isWajeeh;
    } else if (role == 'wajeeh') {
      if (member.id == currentId || member.wajeehId == currentId) {
        canEdit = true;
        canDelete = member.id != currentId;
      }
      if (member.id == currentId) {
        canAddFollower = true;
      }
    }

    if (member.id != currentId && member.role != 'member') {
      if (role == 'owner') canChangePassword = true;
      else if (role == 'sheikh' && member.role != 'owner' && member.role != 'sheikh') canChangePassword = true;
      else if (role == 'admin' && member.role != 'owner' && member.role != 'sheikh' && member.role != 'admin') canChangePassword = true;
    }

    if (!canEdit && !canDelete && !canAddFollower && !canChangePassword) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (canAddFollower)
          IconButton(
            icon: const Icon(Icons.person_add_alt_1, color: Colors.blue, size: 20),
            tooltip: 'إضافة تابع',
            onPressed: () => _showMemberDialog(wajeehId: member.id),
          ),
        if (canEdit || canDelete)
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 20),
            onSelected: (val) {
              if (val == 'edit') _showMemberDialog(member: member);
              if (val == 'delete') _deleteMember(member);
              if (val == 'change_password') _changeUserPassword(member);
            },
            itemBuilder: (ctx) => [
              if (canEdit) const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit, size: 18), SizedBox(width: 8), Text('تعديل')])),
              if (canDelete) const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, size: 18, color: Colors.red), SizedBox(width: 8), Text('حذف', style: TextStyle(color: Colors.red))])),
              if (canChangePassword) const PopupMenuItem(value: 'change_password', child: Row(children: [Icon(Icons.lock_reset, size: 18, color: Colors.blue), SizedBox(width: 8), Text('تغيير رمز المرور', style: TextStyle(color: Colors.blue))])),
            ],
          ),
      ],
    );
  }

  void _changeUserPassword(Member member) async {
    String? newPassword = await showDialog<String>(
      context: context,
      builder: (ctx) {
        String p = '';
        return AlertDialog(
          title: Text('تغيير كلمة المرور لـ ${member.fullName}'),
          content: TextField(
            onChanged: (v) => p = v,
            decoration: const InputDecoration(hintText: 'كلمة المرور الجديدة'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('إلغاء')),
            TextButton(onPressed: () => Navigator.pop(ctx, p), child: const Text('حفظ')),
          ],
        );
      }
    );
    
    if (newPassword != null && newPassword.isNotEmpty) {
      try {
        await ApiService.updateMember(member, password: newPassword);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تغيير رمز المرور بنجاح')));
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e')));
      }
    }
  }

  void _promote(Member member, String role) async {
    String? password;
    if (role == 'admin' && !member.isWajeeh && member.id != AuthService.currentUserId) {
      // Need password for new admin who was a regular member
      password = await _askForPassword();
      if (password == null || password.isEmpty) return;
    }
    
    try {
      await ApiService.changeUserRole(member.id!, role, password: password);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تمت العملية بنجاح')));
      _fetchMembers();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e')));
    }
  }

  Future<String?> _askForPassword() {
    String p = '';
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تعيين كلمة مرور للأدمن الجديد'),
        content: TextField(
          onChanged: (v) => p = v,
          decoration: const InputDecoration(hintText: 'كلمة المرور'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(ctx, p), child: const Text('تعيين')),
        ],
      )
    );
  }

  void _showMemberDialog({Member? member, int? wajeehId}) async {
    final isEditing = member != null;
    _nameController.text = member?.fullName ?? '';
    _phoneController.text = member?.phone ?? '';
    _isWajeeh = member?.isWajeeh ?? false;
    _selectedWajeehId = wajeehId ?? member?.wajeehId;

    if (AuthService.role == 'wajeeh') {
      _selectedWajeehId = AuthService.currentUserId;
    }

    List<Member> wajeehs = await ApiService.getWajeehs();
    if (member != null) {
      wajeehs.removeWhere((w) => w.id == member.id);
    }
    
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(isEditing ? 'تعديل بيانات العضو' : 'إضافة عضو جديد'),
              content: SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(labelText: 'الاسم الكامل'),
                        validator: (value) => value == null || value.isEmpty ? 'يرجى إدخال الاسم' : null,
                      ),
                      TextFormField(
                        controller: _phoneController,
                        decoration: const InputDecoration(labelText: 'رقم الهاتف'),
                        keyboardType: TextInputType.phone,
                        validator: (value) => value == null || value.isEmpty ? 'يرجى إدخال الرقم' : null,
                      ),
                      const SizedBox(height: 16),
                      if (AuthService.role != 'wajeeh')
                        SwitchListTile(
                          title: const Text('هل هو وجيه؟'),
                          value: _isWajeeh,
                          onChanged: (bool value) {
                            setDialogState(() => _isWajeeh = value);
                          },
                        ),
                      if (!_isWajeeh && wajeehs.isNotEmpty)
                        ListTile(
                          title: Text(_selectedWajeehId == null ? 'اختر الوجيه' : 'الوجيه: ${wajeehs.firstWhere((w) => w.id == _selectedWajeehId).fullName}'),
                          subtitle: _selectedWajeehId != null ? Text(wajeehs.firstWhere((w) => w.id == _selectedWajeehId).phone) : null,
                          trailing: const Icon(Icons.search),
                          onTap: () async {
                            final picked = await showDialog<Member>(
                              context: context,
                              builder: (ctx) => _SearchableMemberPicker(members: wajeehs),
                            );
                            if (picked != null) setDialogState(() => _selectedWajeehId = picked.id);
                          },
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
                ElevatedButton(
                  onPressed: () async {
                    if (_formKey.currentState!.validate()) {
                      if (!_isWajeeh && AuthService.role != 'wajeeh' && _selectedWajeehId == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('يرجى اختيار الوجيه التابع له هذا العضو أولاً'),
                            backgroundColor: Colors.red,
                          )
                        );
                        return;
                      }
                      
                      int? transferWajeehId;
                      
                      if (isEditing && member!.isWajeeh && !_isWajeeh) {
                        final followers = _allMembers.where((m) => m.wajeehId == member.id).toList();
                        if (followers.isNotEmpty) {
                          transferWajeehId = await showDialog<int>(
                            context: context,
                            barrierDismissible: false,
                            builder: (ctx) => AlertDialog(
                              title: const Text('نقل التابعين'),
                              content: Text('هذا الوجيه لديه ${followers.length} أعضاء تابعين له. يرجى اختيار وجيه جديد لينتقلوا إليه:'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('إلغاء الحفظ')),
                                TextButton(
                                  onPressed: () async {
                                    final picked = await showDialog<Member>(
                                      context: ctx,
                                      builder: (innerCtx) => _SearchableMemberPicker(members: wajeehs),
                                    );
                                    if (picked != null) {
                                      Navigator.pop(ctx, picked.id);
                                    }
                                  },
                                  child: const Text('اختيار الوجيه الجديد'),
                                ),
                              ],
                            ),
                          );
                          if (transferWajeehId == null) return;
                        }
                      }

                      final updatedMember = Member(
                        id: member?.id,
                        fullName: _nameController.text,
                        phone: NumberUtility.cleanNumberString(_phoneController.text),
                        isWajeeh: AuthService.role == 'wajeeh' ? false : _isWajeeh, // Wajeeh cannot add another Wajeeh
                        wajeehId: AuthService.role == 'wajeeh' ? AuthService.currentUserId : (_isWajeeh ? null : _selectedWajeehId),
                      );
                      try {
                        String? newPassword;
                        if (!isEditing && updatedMember.isWajeeh) {
                           newPassword = await _askForPassword();
                           if (newPassword == null) return;
                        }
                        if (isEditing) {
                          await ApiService.updateMember(updatedMember, transferWajeehId: transferWajeehId);
                          NotificationService().addNotification(
                            title: 'تعديل عضو',
                            message: 'تم تحديث بيانات العضو ${updatedMember.fullName} بنجاح.',
                            type: NotificationType.member,
                            entityId: updatedMember.id,
                          );
                        } else {
                          final newMember = await ApiService.addMember(updatedMember, password: newPassword);
                          NotificationService().addNotification(
                            title: 'عضو جديد',
                            message: 'تم إضافة العضو ${newMember.fullName} إلى النظام.',
                            type: NotificationType.member,
                            entityId: newMember.id,
                          );
                        }
                        if (!context.mounted) return;
                        Navigator.pop(context);
                        _fetchMembers();
                      } catch (e) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشلت العملية: $e')));
                      }
                    }
                  },
                  child: Text(isEditing ? 'تعديل' : 'إضافة'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _deleteMember(Member member) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('هل أنت متأكد من حذف العضو "${member.fullName}"؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm == true && member.id != null) {
      try {
        await ApiService.deleteMember(member.id!);
        NotificationService().addNotification(
          title: 'حذف عضو',
          message: 'تم حذف العضو ${member.fullName} من النظام.',
        );
        _fetchMembers();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ في الحذف: $e')));
      }
    }
  }

  Widget _buildInPlaceBadge(String label, Color color) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(50)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _SearchableMemberPicker extends StatefulWidget {
  final List<Member> members;
  const _SearchableMemberPicker({required this.members});

  @override
  State<_SearchableMemberPicker> createState() => _SearchableMemberPickerState();
}

class _SearchableMemberPickerState extends State<_SearchableMemberPicker> {
  String _query = "";

  @override
  Widget build(BuildContext context) {
    final filtered = widget.members.where((m) => 
      SmartSearchBar.matches(m.fullName, _query) || 
      SmartSearchBar.matches(m.phone, _query)).toList();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('اختر من القائمة'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SmartSearchBar(
                hintText: 'بحث بالاسم أو الهاتف...',
                onChanged: (val) => setState(() => _query = val),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: filtered.length,
                  itemBuilder: (ctx, index) {
                    final m = filtered[index];
                    return ListTile(
                      title: Text(m.fullName),
                      subtitle: Text(m.phone),
                      leading: CircleAvatar(child: Text(m.fullName[0])),
                      onTap: () => Navigator.pop(context, m),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        ],
      ),
    );
  }
}
