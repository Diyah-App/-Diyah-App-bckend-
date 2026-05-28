import 'package:flutter/material.dart';
import '../models/member_model.dart';
import '../models/diyah_model.dart';
import '../services/api_service.dart';
import '../widgets/smart_search_bar.dart';

import '../widgets/custom_app_bar.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';

class PaymentManagementScreen extends StatefulWidget {
  final Diyah diyah;

  const PaymentManagementScreen({super.key, required this.diyah});

  @override
  State<PaymentManagementScreen> createState() => _PaymentManagementScreenState();
}

class _PaymentManagementScreenState extends State<PaymentManagementScreen> {
  late Diyah _diyah;
  List<Member> _allMembers = [];
  Map<int, double?> _payments = {}; // Map of memberId to amount paid
  Set<int> _paidMemberIds = {};
  Set<int> _eligibleMemberIds = {};
  bool _isLoading = true;
  bool _isSaving = false;
  String _searchQuery = "";

  @override
  void initState() {
    super.initState();
    _diyah = widget.diyah;
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      var members = await ApiService.getMembers();
      final status = await ApiService.getDiyahPaymentStatus(_diyah.id!);
      if (!mounted) return;
      setState(() {
        _allMembers = members;
        _payments = Map<int, double?>.from(status['payments'] ?? {});
        _paidMemberIds = _payments.keys.toSet();
        _eligibleMemberIds = status['eligible']!.toSet();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ في التحميل: $e')));
      setState(() => _isLoading = false);
    }
  }

  Future<void> _syncPayments() async {
    setState(() => _isSaving = true);
    try {
      await ApiService.updateDiyahPayments(_diyah.id!, _payments);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ في المزامنة: $e')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _togglePayment(int memberId) async {
    final member = _allMembers.firstWhere((m) => m.id == memberId);
    
    // Check permissions
    if (AuthService.role == 'wajeeh') {
      if (member.id != AuthService.currentUserId && member.wajeehId != AuthService.currentUserId) {
        return; // Wajeeh can only toggle their own members
      }
    }

    bool wasPaid = _payments.containsKey(memberId);
    setState(() {
      if (wasPaid) {
        _payments.remove(memberId);
      } else {
        double defaultAmount = _diyah.sharePerMember;
        if (memberId == _diyah.causedById && _diyah.ownerPercentage != null) {
          defaultAmount = _diyah.amount * (_diyah.ownerPercentage! / 100);
        }
        _payments[memberId] = defaultAmount;
      }
      _paidMemberIds = _payments.keys.toSet();
    });
    
    NotificationService().addNotification(
      title: 'تحديث دفع',
      message: '${wasPaid ? "إلغاء دفع" : "تأكيد دفع"} حصة العضو: ${member.fullName}',
    );
    
    await _syncPayments();
    await _checkAndPromptDiyahCompletion();
  }

  Future<void> _selectAll() async {
    setState(() {
      for (var m in _allMembers) {
        if (!_eligibleMemberIds.contains(m.id)) continue;
        if (AuthService.role == 'wajeeh') {
          if (m.id != AuthService.currentUserId && m.wajeehId != AuthService.currentUserId) continue;
        }
        double defaultAmount = _diyah.sharePerMember;
        if (m.id == _diyah.causedById && _diyah.ownerPercentage != null) {
          defaultAmount = _diyah.amount * (_diyah.ownerPercentage! / 100);
        }
        _payments[m.id!] = defaultAmount;
      }
      _paidMemberIds = _payments.keys.toSet();
    });
    NotificationService().addNotification(
      title: 'تحصيل جماعي',
      message: 'تم تحديد الأعضاء كدافعين لدية ${_diyah.title}',
      type: NotificationType.diyah,
      entityId: _diyah.id,
    );
    await _syncPayments();
    await _checkAndPromptDiyahCompletion();
  }

  Future<void> _deselectAll() async {
    setState(() {
      for (var m in _allMembers) {
        if (AuthService.role == 'wajeeh') {
          if (m.id != AuthService.currentUserId && m.wajeehId != AuthService.currentUserId) continue;
        }
        _payments.remove(m.id!);
      }
      _paidMemberIds = _payments.keys.toSet();
    });
    NotificationService().addNotification(
      title: 'إلغاء تسديد جماعي',
      message: 'تم إلغاء تسديد الدية لجميع الأعضاء في ${_diyah.title}',
      type: NotificationType.diyah,
      entityId: _diyah.id,
    );
    await _syncPayments();
    await _checkAndPromptDiyahCompletion();
  }

  bool _checkIfAllMembersPaid() {
    final eligibleMembers = _allMembers.where((m) => _eligibleMemberIds.contains(m.id)).toList();
    if (eligibleMembers.isEmpty) return false;
    for (var member in eligibleMembers) {
      final paidAmount = _payments[member.id];
      double memberShare = _diyah.sharePerMember;
      if (member.id == _diyah.causedById && _diyah.ownerPercentage != null) {
        memberShare = _diyah.amount * (_diyah.ownerPercentage! / 100);
      }
      final cashPaid = paidAmount ?? 0.0;
      final balanceBefore = member.balance - cashPaid + memberShare;
      double remainingClaim = memberShare - cashPaid;
      double coveredFromBalance = 0.0;
      if (remainingClaim > 0 && balanceBefore > 0) {
        coveredFromBalance = balanceBefore >= remainingClaim ? remainingClaim : balanceBefore;
        remainingClaim = remainingClaim - coveredFromBalance;
      }
      if (remainingClaim > 0) {
        return false;
      }
    }
    return true;
  }

  Future<void> _checkAndPromptDiyahCompletion() async {
    final isNowFullyPaid = _checkIfAllMembersPaid();
    if (!_diyah.isFullyPaid && isNowFullyPaid) {
      if (!mounted) return;
      final bool? closeDiyah = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('اكتمل سداد الدية'),
            content: const Text('تم دفع حساب الدية بالكامل من قبل جميع الأعضاء المشمولين! هل تريد إغلاق هذه الدية الآن؟\n\n(إذا اخترت نعم، سيتم إغلاق الدية وتحديدها كمسددة ومغلقة. وإذا اخترت لا، ستظل مفتوحة ولكن مع تحديدها كدية مسددة بالكامل).'),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                child: const Text('نعم، إغلاق الدية', style: TextStyle(color: Colors.white)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('لا، إبقاء مفتوحة'),
              ),
            ],
          ),
        ),
      );

      if (closeDiyah == null) return;

      final updated = Diyah(
        id: _diyah.id,
        title: _diyah.title,
        amount: _diyah.amount,
        description: _diyah.description,
        manualDate: _diyah.manualDate,
        createdAt: _diyah.createdAt,
        causedById: _diyah.causedById,
        isFinished: closeDiyah,
        isFullyPaid: true,
        totalMembersCount: _diyah.totalMembersCount,
        sharePerMember: _diyah.sharePerMember,
        ownerPercentage: _diyah.ownerPercentage,
      );

      try {
        await ApiService.updateDiyah(updated);
        setState(() {
          _diyah = updated;
        });
        NotificationService().addNotification(
          title: closeDiyah ? 'إغلاق دية مكتملة' : 'دية مسددة بالكامل',
          message: closeDiyah ? 'تم إغلاق الدية المسددة: ${_diyah.title}' : 'تم تحديد الدية كمسددة بالكامل: ${_diyah.title}',
          type: NotificationType.diyah,
          entityId: _diyah.id,
        );
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ في تحديث حالة الدية: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    List<Member> filteredMembers = _allMembers.where((m) {
      final matchesName = SmartSearchBar.matches(m.fullName, _searchQuery);
      final matchesPhone = SmartSearchBar.matches(m.phone, _searchQuery);
      return matchesName || matchesPhone;
    }).toList();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: CustomAppBar(
          title: 'تحصيل: ${_diyah.title}',
          extraActions: [
            if (_isSaving) 
              const Center(child: Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)))),
            TextButton(
              onPressed: _allMembers.where((m) {
                 if (AuthService.role == 'wajeeh') {
                    return m.id == AuthService.currentUserId || m.wajeehId == AuthService.currentUserId;
                 }
                 return true;
              }).every((m) => _paidMemberIds.contains(m.id)) ? _deselectAll : _selectAll,
              child: Text(
                _allMembers.where((m) {
                 if (AuthService.role == 'wajeeh') {
                    return m.id == AuthService.currentUserId || m.wajeehId == AuthService.currentUserId;
                 }
                 return true;
              }).every((m) => _paidMemberIds.contains(m.id)) ? 'إلغاء الكل' : 'تحديد الكل',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        body: _isLoading 
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: SmartSearchBar(
                    hintText: 'بحث بالاسم أو رقم الهاتف...',
                    onChanged: (val) => setState(() => _searchQuery = val),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('تم التحصيل من: ${_paidMemberIds.intersection(_eligibleMemberIds).length} / ${_eligibleMemberIds.length}', 
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                      if (_isSaving) const Text('جاري الحفظ...', style: TextStyle(color: Colors.blue, fontSize: 12)),
                    ],
                  ),
                ),
                if (_allMembers.length > _eligibleMemberIds.length)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4),
                    child: Text('* يوجد ${_allMembers.length - _eligibleMemberIds.length} أعضاء جدد غير مشمولين بهذه الدية.', 
                      style: TextStyle(fontSize: 10, color: Colors.grey.shade600, fontStyle: FontStyle.italic)),
                  ),
                Expanded(
                  child: ListView.builder(
                    itemCount: filteredMembers.length,
                    itemBuilder: (ctx, index) {
                      final member = filteredMembers[index];
                      final isPaid = _paidMemberIds.contains(member.id);
                      final canEdit = (AuthService.role == 'owner' || AuthService.role == 'sheikh' || AuthService.role == 'admin') ||
                                      (AuthService.role == 'wajeeh' && (member.id == AuthService.currentUserId || member.wajeehId == AuthService.currentUserId));

                      return CheckboxListTile(
                        title: Text(member.fullName, style: TextStyle(fontWeight: FontWeight.bold, color: canEdit ? Colors.black : Colors.grey[600])),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('رقم الهاتف: ${member.phone}', style: const TextStyle(fontSize: 13)),
                            Text(member.isWajeeh ? 'الحالة: وجيه' : 'الحالة: عضو (تابع لـ: ${member.wajeehName ?? "لا يوجد"})', 
                              style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                          ],
                        ),
                        secondary: CircleAvatar(
                          backgroundColor: member.isWajeeh ? Colors.amber.shade100 : Colors.blue.shade50,
                          child: Icon(member.isWajeeh ? Icons.star : Icons.person, color: member.isWajeeh ? Colors.amber : Colors.blue),
                        ),
                        value: isPaid,
                        activeColor: Colors.green,
                        onChanged: canEdit ? (_) => _togglePayment(member.id!) : null,
                      );
                    },
                  ),
                ),
              ],
            ),
      ),
    );
  }
}
