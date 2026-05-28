import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import '../models/diyah_model.dart';
import '../models/member_model.dart';
import '../services/api_service.dart';
import '../widgets/custom_app_bar.dart';
import '../widgets/smart_search_bar.dart';
import 'diyah_details_screen.dart';
import 'payment_management_screen.dart';
import '../utils/number_utility.dart';

import '../services/notification_service.dart';
import '../services/auth_service.dart';

class DiyahsScreen extends StatefulWidget {
  const DiyahsScreen({super.key});

  @override
  State<DiyahsScreen> createState() => _DiyahsScreenState();
}

class _DiyahsScreenState extends State<DiyahsScreen> {
  List<Diyah> _allDiyahs = [];
  List<Diyah> _filteredDiyahs = [];
  bool _isLoading = true;
  String _searchQuery = "";
  String _statusFilter = 'نشطة'; // 'الكل', 'نشطة', 'منتهية'

  late StreamSubscription _refreshSubscription;

  @override
  void initState() {
    super.initState();
    _loadDiyahs();
    _refreshSubscription = NotificationService().onRefreshRequired.listen((_) {
      if (mounted) _loadDiyahs();
    });
  }

  @override
  void dispose() {
    _refreshSubscription.cancel();
    super.dispose();
  }

  Future<void> _loadDiyahs() async {
    try {
      final diyahs = await ApiService.getDiyahs();
      if (!mounted) return;
      setState(() {
        _allDiyahs = diyahs;
        _applyFilters();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ في تحميل الديات: $e')));
      setState(() => _isLoading = false);
    }
  }

  void _applyFilters() {
    setState(() {
      _filteredDiyahs = _allDiyahs.where((d) {
        final matchesTitle = SmartSearchBar.matches(d.title, _searchQuery);
        final matchesDesc = SmartSearchBar.matches(d.description ?? '', _searchQuery);
        
        bool matchesStatus = true;
        if (_statusFilter == 'نشطة') matchesStatus = !d.isFinished;
        if (_statusFilter == 'منتهية') matchesStatus = d.isFinished;

        return (matchesTitle || matchesDesc) && matchesStatus;
      }).toList();
    });
  }

  Future<void> _showAddEditDialog([Diyah? diyah]) async {
    final titleController = TextEditingController(text: diyah?.title);
    final amountController = TextEditingController(text: diyah?.amount.toString() == '0.0' ? '' : diyah?.amount.toString());
    final descController = TextEditingController(text: diyah?.description);
    final percentController = TextEditingController(text: diyah?.ownerPercentage?.toString() ?? '35');
    final ownerAmountController = TextEditingController();
    
    DateTime? selectedDate = diyah?.manualDate;
    int? selectedCausedById = diyah?.causedById;
    bool useCustomPercentage = diyah?.ownerPercentage != null;

    if (useCustomPercentage && diyah != null) {
      final initialOwnerAmount = diyah.amount * (diyah.ownerPercentage! / 100.0);
      ownerAmountController.text = initialOwnerAmount % 1 == 0 
          ? initialOwnerAmount.toInt().toString() 
          : initialOwnerAmount.toStringAsFixed(2);
    }

    List<Member> allMembers = await ApiService.getMembers();

    if (!mounted) return;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Text(diyah == null ? 'إضافة دية جديدة' : 'تعديل الدية'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: titleController, decoration: const InputDecoration(labelText: 'العنوان *')),
                  TextField(
                    controller: amountController, 
                    decoration: const InputDecoration(labelText: 'المبلغ الإجمالي *'), 
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                    inputFormatters: [AmountInputFormatter()],
                    onChanged: (val) {
                      if (useCustomPercentage) {
                        final totalAmount = NumberUtility.tryParseDouble(val) ?? 0.0;
                        final percent = NumberUtility.tryParseDouble(percentController.text) ?? 0.0;
                        final ownerAmount = totalAmount * (percent / 100.0);
                        ownerAmountController.text = ownerAmount % 1 == 0 
                            ? ownerAmount.toInt().toString() 
                            : ownerAmount.toStringAsFixed(2);
                      }
                    },
                  ),
                  TextField(controller: descController, decoration: const InputDecoration(labelText: 'الوصف (اختياري)')),
                  const SizedBox(height: 16),
                  ListTile(
                    title: Text(selectedCausedById == null ? 'اختر صاحب الدية *' : 'صاحب الدية: ${allMembers.firstWhere((m) => m.id == selectedCausedById, orElse: () => allMembers[0]).fullName}'),
                    subtitle: selectedCausedById != null ? Text(allMembers.firstWhere((m) => m.id == selectedCausedById, orElse: () => allMembers[0]).phone) : null,
                    trailing: const Icon(Icons.search),
                    onTap: () async {
                      final picked = await showDialog<Member>(
                        context: context,
                        builder: (ctx) => _SearchableMemberPicker(members: allMembers),
                      );
                      if (picked != null) setDialogState(() => selectedCausedById = picked.id);
                    },
                  ),
                  const Divider(),
                  SwitchListTile(
                    title: const Text('تحديد حصة صاحب الدية (%)'),
                    subtitle: const Text('إذا لم يتم التفعيل، سيتم التقسيم بالتساوي على الجميع'),
                    value: useCustomPercentage,
                    onChanged: (val) {
                      setDialogState(() {
                        useCustomPercentage = val;
                        if (val) {
                          if (percentController.text.isEmpty) {
                            percentController.text = '35';
                          }
                          final totalAmount = NumberUtility.tryParseDouble(amountController.text) ?? 0.0;
                          final percent = NumberUtility.tryParseDouble(percentController.text) ?? 35.0;
                          final ownerAmount = totalAmount * (percent / 100.0);
                          ownerAmountController.text = ownerAmount % 1 == 0 
                              ? ownerAmount.toInt().toString() 
                              : ownerAmount.toStringAsFixed(2);
                        }
                      });
                    },
                  ),
                  if (useCustomPercentage)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: percentController,
                              decoration: const InputDecoration(
                                labelText: 'النسبة (%)',
                                border: OutlineInputBorder(),
                              ),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                              inputFormatters: [AmountInputFormatter()],
                              onChanged: (val) {
                                final totalAmount = NumberUtility.tryParseDouble(amountController.text) ?? 0.0;
                                final percent = NumberUtility.tryParseDouble(val) ?? 0.0;
                                if (totalAmount > 0) {
                                  final ownerAmount = totalAmount * (percent / 100.0);
                                  ownerAmountController.text = ownerAmount % 1 == 0 
                                      ? ownerAmount.toInt().toString() 
                                      : ownerAmount.toStringAsFixed(2);
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: ownerAmountController,
                              decoration: const InputDecoration(
                                labelText: 'مبلغ صاحب الدية (د.ع)',
                                border: OutlineInputBorder(),
                              ),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                              inputFormatters: [AmountInputFormatter()],
                              onChanged: (val) {
                                final totalAmount = NumberUtility.tryParseDouble(amountController.text) ?? 0.0;
                                final ownerAmount = NumberUtility.tryParseDouble(val) ?? 0.0;
                                if (totalAmount > 0) {
                                  final percent = (ownerAmount / totalAmount) * 100.0;
                                  percentController.text = percent % 1 == 0 
                                      ? percent.toInt().toString() 
                                      : percent.toStringAsFixed(2);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  const Divider(),
                  ListTile(
                    title: Text(selectedDate == null ? 'تاريخ الواقعة (اختياري)' : 'تاريخ الواقعة: ${intl.DateFormat('yyyy-MM-dd').format(selectedDate!)}'),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate ?? DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) setDialogState(() => selectedDate = picked);
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
              ElevatedButton(
                onPressed: () async {
                  if (titleController.text.isEmpty || amountController.text.isEmpty || selectedCausedById == null) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('يرجى ملء الحقول الإجبارية (*)'), backgroundColor: Colors.red));
                    return;
                  }
                  
                  double? percentage;
                  if (useCustomPercentage) {
                    percentage = NumberUtility.tryParseDouble(percentController.text) ?? 35.0;
                  }

                  final diyahData = Diyah(
                    id: diyah?.id,
                    title: titleController.text,
                    amount: NumberUtility.tryParseDouble(amountController.text) ?? 0.0,
                    description: descController.text,
                    manualDate: selectedDate,
                    createdAt: diyah?.createdAt ?? DateTime.now(),
                    causedById: selectedCausedById,
                    isFinished: diyah?.isFinished ?? false,
                    ownerPercentage: percentage,
                  );
                  try {
                    if (diyah == null) {
                      final newDiyah = await ApiService.addDiyah(diyahData);
                      NotificationService().addNotification(
                        title: 'دية جديدة',
                        message: 'تم تسجيل دية جديدة: ${newDiyah.title}',
                        type: NotificationType.diyah,
                        entityId: newDiyah.id,
                      );
                    } else {
                      await ApiService.updateDiyah(diyahData);
                      NotificationService().addNotification(
                        title: 'تعديل دية',
                        message: 'تم تحديث بيانات الدية: ${diyahData.title}',
                        type: NotificationType.diyah,
                        entityId: diyahData.id,
                      );
                    }
                    if (!context.mounted) return;
                    Navigator.pop(ctx, true);
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e')));
                  }
                },
                child: const Text('حفظ'),
              ),
            ],
          ),
        ),
      ),
    );

    if (result == true) _loadDiyahs();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(
        title: 'سجل الديات',
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(105),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: SmartSearchBar(
                  hintText: 'بحث في الديات...',
                  onChanged: (val) {
                    _searchQuery = val;
                    _applyFilters();
                  },
                ),
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 10, top: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildFilterBtn('الكل',       _allDiyahs.length,                             Colors.blue),
                    _buildFilterBtn('نشطة',   _allDiyahs.where((d) => !d.isFinished).length, Colors.green),
                    _buildFilterBtn('منتهية',  _allDiyahs.where((d) => d.isFinished).length,  Colors.orange),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  itemCount: _filteredDiyahs.length,
                  itemBuilder: (ctx, index) => _buildDiyahCard(_filteredDiyahs[index]),
                ),
          ),
        ],
      ),
      floatingActionButton: ['owner', 'sheikh', 'admin'].contains(AuthService.role) ? FloatingActionButton(
        heroTag: 'diyahs_fab',
        onPressed: () => _showAddEditDialog(),
        child: const Icon(Icons.add),
      ) : null,
    );
  }

  Widget _buildFilterBtn(String label, int count, Color color) {
    final isSelected = _statusFilter == label;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: GestureDetector(
        onTap: () => setState(() {
          _statusFilter = label;
          _applyFilters();
        }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: isSelected ? color.withAlpha(40) : Colors.white.withAlpha(30),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? color : Colors.white.withAlpha(100),
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isSelected)
                Icon(Icons.check, size: 13, color: isSelected ? color : Colors.white70),
              if (isSelected) const SizedBox(width: 3),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? color : Colors.white,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: isSelected ? color : Colors.white.withAlpha(80),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  count.toString(),
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDiyahCard(Diyah diyah) {
    return Card(
      margin: const EdgeInsets.all(8),
      child: ListTile(
        title: Row(
          children: [
            Expanded(child: Text(diyah.title, style: const TextStyle(fontWeight: FontWeight.bold))),
            if (diyah.isFullyPaid)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: diyah.isFinished ? Colors.green.shade100 : Colors.blue.shade100,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: diyah.isFinished ? Colors.green : Colors.blue),
                ),
                child: Text(
                  diyah.isFinished ? 'مغلقة ومسددة' : 'مسددة بالكامل',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: diyah.isFinished ? Colors.green.shade900 : Colors.blue.shade900,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('المبلغ الإجمالي: ${intl.NumberFormat('#,##0.##').format(diyah.amount)} د.ع'),
            Text('حصة الفرد: ${intl.NumberFormat('#,##0.##').format(diyah.sharePerMember)} د.ع', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
            Text('صاحب الدية: ${diyah.causedByName ?? "غير محدد"}', style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.add_circle_outline, size: 12, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text('تاريخ الإضافة: ${intl.DateFormat('yyyy-MM-dd').format(diyah.createdAt)}', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
              ],
            ),
            Row(
              children: [
                Icon(Icons.event_note, size: 12, color: Colors.blueGrey[600]),
                const SizedBox(width: 4),
                Text('تاريخ الواقعة: ${intl.DateFormat('yyyy-MM-dd').format(diyah.manualDate ?? diyah.createdAt)}', style: TextStyle(fontSize: 11, color: Colors.blueGrey[600])),
              ],
            ),
          ],
        ),
        trailing: ['owner', 'sheikh', 'admin'].contains(AuthService.role) ? Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.payments, color: Colors.green),
              tooltip: 'إدارة التحصيل',
              onPressed: () => Navigator.push(
                context, 
                MaterialPageRoute(builder: (ctx) => PaymentManagementScreen(diyah: diyah))
              ),
            ),
            IconButton(
              icon: Icon(diyah.isFinished ? Icons.check_circle : Icons.circle_outlined, color: diyah.isFinished ? Colors.blue : Colors.grey),
              tooltip: diyah.isFinished ? 'إعادة فتح' : 'إنهاء الدية',
              onPressed: () async {
                final updated = Diyah(
                  id: diyah.id,
                  title: diyah.title,
                  amount: diyah.amount,
                  description: diyah.description,
                  manualDate: diyah.manualDate,
                  createdAt: diyah.createdAt,
                  causedById: diyah.causedById,
                  isFinished: !diyah.isFinished,
                  totalMembersCount: diyah.totalMembersCount,
                  sharePerMember: diyah.sharePerMember,
                );
                await ApiService.updateDiyah(updated);
                NotificationService().addNotification(
                  title: updated.isFinished ? 'إغلاق دية' : 'إعادة فتح دية',
                  message: 'تم تغيير حالة الدية: ${updated.title}',
                  type: NotificationType.diyah,
                  entityId: updated.id,
                );
                _loadDiyahs();
              },
            ),
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => _showAddEditDialog(diyah),
            ),
          ],
        ) : null,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (ctx) => DiyahDetailsScreen(diyah: diyah))
        ).then((_) => _loadDiyahs()),
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
