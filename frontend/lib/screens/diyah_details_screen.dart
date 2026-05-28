import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import '../models/diyah_model.dart';
import '../models/member_model.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../services/auth_service.dart';
import '../widgets/member_tile.dart';
import '../widgets/smart_search_bar.dart';
import '../widgets/custom_app_bar.dart';
import '../utils/number_utility.dart';
import '../theme/app_theme.dart';
import 'member_details_screen.dart';

class DiyahDetailsScreen extends StatefulWidget {
  final Diyah diyah;

  const DiyahDetailsScreen({super.key, required this.diyah});

  @override
  State<DiyahDetailsScreen> createState() => _DiyahDetailsScreenState();
}

class _DiyahDetailsScreenState extends State<DiyahDetailsScreen> {
  late Diyah _diyah;
  List<Member> _allMembers = [];
  List<Member> _filteredMembers = [];
  Map<int, double?> _payments = {}; // Map of memberId to amount paid
  Set<int> _eligibleMemberIds = {};
  bool _isLoading = true;
  String _searchQuery = "";
  String _roleFilter = 'الكل'; // 'الكل', 'وجهاء', 'أعضاء'
  String _paymentFilter = 'الكل'; // 'الكل', 'دافعين', 'غير دافعين'

  @override
  void initState() {
    super.initState();
    _diyah = widget.diyah;
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final members = await ApiService.getMembers();
      final status = await ApiService.getDiyahPaymentStatus(_diyah.id!);
      
      if (!mounted) return;
      setState(() {
        _allMembers = members;
        _payments = status['payments'] as Map<int, double?>;
        _eligibleMemberIds = status['eligible']!.toSet();
        _applyFilters();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  void _applyFilters() {
    setState(() {
      final eligibleMembers = _allMembers.where((m) => _eligibleMemberIds.contains(m.id)).toList();

      _filteredMembers = eligibleMembers.where((m) {
        final matchesSearch = SmartSearchBar.matches(m.fullName, _searchQuery) || 
                             SmartSearchBar.matches(m.phone, _searchQuery);
        
        bool roleMatch = true;
        if (_roleFilter == 'وجهاء') roleMatch = m.isWajeeh;
        if (_roleFilter == 'أعضاء') roleMatch = !m.isWajeeh;

        bool paymentMatch = true;
        if (_paymentFilter == 'دافعين') {
          paymentMatch = _payments.containsKey(m.id);
        } else if (_paymentFilter == 'غير دافعين') {
          paymentMatch = !_payments.containsKey(m.id);
        }

        return matchesSearch && roleMatch && paymentMatch;
      }).toList();
    });
  }

  Future<void> _togglePayment(int memberId) async {
    final wasPaid = _payments.containsKey(memberId);
    final member = _allMembers.firstWhere((m) => m.id == memberId);

    if (wasPaid) {
      // Confirm un-payment
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('إلغاء السداد'),
          content: Text('هل أنت متأكد من إلغاء حالة السداد للعضو ${member.fullName}؟'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('تراجع')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('نعم، إلغاء')),
          ],
        )
      );
      if (confirm != true) return;

      setState(() {
        _payments.remove(memberId);
        _applyFilters();
      });
    } else {
      // Show payment dialog
      double defaultAmount = _diyah.sharePerMember;
      if (memberId == _diyah.causedById && _diyah.ownerPercentage != null) {
        defaultAmount = _diyah.amount * (_diyah.ownerPercentage! / 100);
      }

      final amountController = TextEditingController(text: intl.NumberFormat('#,##0.##').format(defaultAmount));
      final resultAmount = await showDialog<double>(
        context: context,
        builder: (ctx) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Text('تسديد الدية لـ ${member.fullName}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('الحصة المطلوبة: ${intl.NumberFormat('#,##0.##').format(defaultAmount)} د.ع', 
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                const SizedBox(height: 16),
                TextField(
                  controller: amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  inputFormatters: [AmountInputFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'المبلغ المدفوع فعلياً (د.ع)',
                    border: OutlineInputBorder(),
                  ),
                  autofocus: true,
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('إلغاء')),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, NumberUtility.tryParseDouble(amountController.text)),
                child: const Text('تأكيد الدفع'),
              ),
            ],
          ),
        )
      );

      if (resultAmount == null) return;

      setState(() {
        _payments[memberId] = resultAmount;
        _applyFilters();
      });
    }

    try {
      if (!mounted) return;
      await ApiService.updateDiyahPayments(_diyah.id!, _payments);
      if (!mounted) return;
      NotificationService().addNotification(
        title: 'تعديل سداد',
        message: 'تم تحديث حالة دفع ${member.fullName} لدية ${_diyah.title}',
        type: NotificationType.diyah,
        entityId: _diyah.id,
      );
      _checkAndPromptDiyahCompletion();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ في المزامنة: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: CustomAppBar(
          title: 'تفاصيل الدية',
          extraActions: [
            IconButton(
              icon: Icon(_diyah.isFinished ? Icons.check_circle : Icons.circle_outlined, color: Colors.white),
              tooltip: _diyah.isFinished ? 'إعادة فتح' : 'إنهاء الدية',
              onPressed: () async {
                final updated = Diyah(
                  id: _diyah.id,
                  title: _diyah.title,
                  amount: _diyah.amount,
                  description: _diyah.description,
                  manualDate: _diyah.manualDate,
                  createdAt: _diyah.createdAt,
                  causedById: _diyah.causedById,
                  isFinished: !_diyah.isFinished,
                  totalMembersCount: _diyah.totalMembersCount,
                  sharePerMember: _diyah.sharePerMember,
                );
                await ApiService.updateDiyah(updated);
                NotificationService().addNotification(
                  title: updated.isFinished ? 'إغلاق دية' : 'إعادة فتح دية',
                  message: 'تم تغيير حالة الدية: ${updated.title}',
                  type: NotificationType.diyah,
                  entityId: updated.id,
                );
                setState(() => _diyah = updated);
              },
            ),
          ],
        ),
        body: _isLoading ? const Center(child: CircularProgressIndicator()) : Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeaderCard(),
                    const SizedBox(height: 16),
                    _buildDiyahStats(),
                    if (_diyah.description != null && _diyah.description!.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _buildDescriptionCard(),
                    ],
                    const SizedBox(height: 16),
                    _buildResponsibleCard(),
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),
                    const Text('إدارة سداد الأعضاء', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 12),
                    SmartSearchBar(
                      hintText: 'بحث في الأعضاء...',
                      onChanged: (val) {
                        _searchQuery = val;
                        _applyFilters();
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildFilterRow(),
                    const SizedBox(height: 16),
                    _roleFilter == 'الكل' && _searchQuery.isEmpty
                        ? _buildGroupedMembersList()
                        : ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _filteredMembers.length,
                            itemBuilder: (ctx, index) {
                              return _buildMemberListItem(_filteredMembers[index]);
                            },
                          ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterRow() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: ['الكل', 'وجهاء', 'أعضاء'].map((type) {
            final isSelected = _roleFilter == type;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: FilterChip(
                label: Text(type, style: const TextStyle(fontSize: 12)),
                selected: isSelected,
                onSelected: (val) {
                  setState(() {
                    _roleFilter = type;
                    _applyFilters();
                  });
                },
              ),
            );
          }).toList(),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: ['الكل', 'دافعين', 'غير دافعين'].map((type) {
            final isSelected = _paymentFilter == type;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: FilterChip(
                label: Text(type, style: const TextStyle(fontSize: 12)),
                selected: isSelected,
                selectedColor: Colors.green.withAlpha(50),
                checkmarkColor: Colors.green,
                onSelected: (val) {
                  setState(() {
                    _paymentFilter = type;
                    _applyFilters();
                  });
                },
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildHeaderCard() {
    final color = _diyah.isFinished 
        ? Colors.green.shade700 
        : (_diyah.isFullyPaid ? Colors.teal.shade700 : Colors.red.shade700);
    final fmt = intl.NumberFormat('#,##0.##');
    final dateFmt = intl.DateFormat('yyyy-MM-dd');

    return Card(
      margin: EdgeInsets.zero,   // full width — padding comes from the parent
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      color: color,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Row 1: Title ──────────────────────────────────
            Row(
              children: [
                if (_diyah.isFullyPaid)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Icon(
                      _diyah.isFinished ? Icons.check_circle : Icons.payment_outlined,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                Expanded(
                  child: Text(
                    _diyah.title + (_diyah.isFullyPaid ? (_diyah.isFinished ? " (مغلقة ومسددة)" : " (مسددة بالكامل)") : ""),
                    style: const TextStyle(
                      fontSize: 20,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Divider(color: Colors.white24, height: 1),
            const SizedBox(height: 10),

            // ── Row 2: Total amount  |  Share per member ─────
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Text('المبلغ الإجمالي', style: TextStyle(fontSize: 11, color: Colors.white60)),
                      const SizedBox(height: 2),
                      Text(
                        '${fmt.format(_diyah.amount)} د.ع',
                        style: const TextStyle(fontSize: 15, color: Colors.white70, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                Container(width: 1, height: 36, color: Colors.white24),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Text('حصة الفرد', style: TextStyle(fontSize: 11, color: Colors.white60)),
                      const SizedBox(height: 2),
                      Text(
                        '${fmt.format(_diyah.sharePerMember)} د.ع',
                        style: const TextStyle(fontSize: 15, color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Divider(color: Colors.white24, height: 1),
            const SizedBox(height: 8),

            // ── Row 3: Creation date  |  Event date ──────────
            Row(
              children: [
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.add_circle_outline, size: 13, color: Colors.white54),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          'تاريخ الإضافة: ${dateFmt.format(_diyah.createdAt)}',
                          style: const TextStyle(fontSize: 11, color: Colors.white70),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(width: 1, height: 28, color: Colors.white24),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.event_note, size: 13, color: Colors.white54),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          'تاريخ الواقعة: ${dateFmt.format(_diyah.manualDate ?? _diyah.createdAt)}',
                          style: const TextStyle(fontSize: 11, color: Colors.white70),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResponsibleCard() {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.warning, color: Colors.red),
        title: const Text('صاحب الدية'),
        subtitle: Text(_diyah.causedByName ?? "غير محدد"),
        trailing: _diyah.ownerPercentage != null 
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(10)),
              child: Text(
                'يتحمل ${_diyah.ownerPercentage}% (${intl.NumberFormat('#,##0.##').format(_diyah.amount * (_diyah.ownerPercentage! / 100))} د.ع)', 
                style: TextStyle(color: Colors.red.shade900, fontWeight: FontWeight.bold, fontSize: 12),
              ),
            )
          : null,
      ),
    );
  }

  Widget _buildDescriptionCard() {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(12), topRight: Radius.circular(12)),
            ),
            child: const Text('وصف الدية', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(_diyah.description ?? '', style: const TextStyle(fontSize: 14, height: 1.5)),
          ),
        ],
      ),
    );
  }

  Widget _buildDiyahStats() {
    final _paidMemberIds = _payments.keys.toSet();
    final totalEligible = _eligibleMemberIds.length;
    final paidCount = _paidMemberIds.length;
    final remainingCount = totalEligible - _paidMemberIds.intersection(_eligibleMemberIds).length;

    final filteredTotal = _filteredMembers.length;
    final filteredWajeehs = _filteredMembers.where((m) => m.isWajeeh).length;
    final filteredMembersCount = filteredTotal - filteredWajeehs;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatColumn('المشمولين', totalEligible, Colors.blue),
                _buildStatColumn('المسددين', paidCount, Colors.green),
                _buildStatColumn('المتبقي', remainingCount, Colors.red),
              ],
            ),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('نتائج الفلترة:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                Text('وجهاء: $filteredWajeehs | أعضاء: $filteredMembersCount', style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatColumn(String label, int value, Color color) {
    return Column(
      children: [
        Text(value.toString(), style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
      ],
    );
  }

  Widget _buildMemberListItem(Member member) {
    final isPaid = _payments.containsKey(member.id);
    final paidAmount = _payments[member.id];
    
    double memberShare = _diyah.sharePerMember;
    if (member.id == _diyah.causedById && _diyah.ownerPercentage != null) {
      memberShare = _diyah.amount * (_diyah.ownerPercentage! / 100);
    }

    // Calculate group share if wajeeh
    double totalGroupShare = 0.0;
    int followersCount = 0;
    if (member.isWajeeh) {
      final followers = _allMembers.where((m) => m.wajeehId == member.id).toList();
      followersCount = followers.length;
      
      // 1. Add Wajeeh's share
      totalGroupShare += memberShare;
      
      // 2. Add each follower's share (checking if they are the diyah owner)
      for (var f in followers) {
        double followerShare = _diyah.sharePerMember;
        if (f.id == _diyah.causedById && _diyah.ownerPercentage != null) {
          followerShare = _diyah.amount * (_diyah.ownerPercentage! / 100.0);
        }
        totalGroupShare += followerShare;
      }
    }

    // Calculate detailed breakdown
    final cashPaid = paidAmount ?? 0.0;
    final balanceBefore = member.balance - cashPaid + memberShare;

    double coveredFromBalance = 0.0;
    double remainingClaim = memberShare - cashPaid;

    if (remainingClaim > 0 && balanceBefore > 0) {
      coveredFromBalance = balanceBefore >= remainingClaim ? remainingClaim : balanceBefore;
      remainingClaim = remainingClaim - coveredFromBalance;
    }
    if (remainingClaim < 0) remainingClaim = 0.0;

    return MemberTile(
      member: member,
      subtitleOverride: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (member.isWajeeh) ...[
            Text('حصة الوجيه الفردية: ${intl.NumberFormat('#,##0.##').format(memberShare)} د.ع', style: const TextStyle(fontSize: 12, color: Colors.black87)),
            Text('حصة المجموعة كاملة (${followersCount + 1}): ${intl.NumberFormat('#,##0.##').format(totalGroupShare)} د.ع', 
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blue)),
          ] else ...[
            Text('حصة العضو: ${intl.NumberFormat('#,##0.##').format(memberShare)} د.ع', 
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.brown)),
            Text('الهاتف: ${member.phone}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300, width: 0.5),
            ),
            child: _buildPaymentBreakdownWidget(member, memberShare, cashPaid, coveredFromBalance, remainingClaim),
          ),
        ],
      ),
      trailing: Switch(
        value: isPaid,
        activeTrackColor: Colors.green.shade400,
        activeColor: Colors.green.shade900,
        onChanged: (_) => _togglePayment(member.id!),
      ),
    );
  }

  Widget _buildGroupedMembersList() {
    final eligibleMembers = _allMembers.where((m) => _eligibleMemberIds.contains(m.id)).toList();
    final allWajeehs = eligibleMembers.where((m) => m.isWajeeh).toList();

    // Get ALL eligible followers for each wajeeh (from full list, not filtered)
    // so we can show unpaid followers under a paid wajeeh
    final wajeehsToShow = allWajeehs.where((wajeeh) {
      final wajeehMatches = _filteredMembers.any((m) => m.id == wajeeh.id);
      // Use ALL eligible followers, not just filteredMembers, to catch paid-wajeeh/unpaid-follower case
      final allFollowersEligible = eligibleMembers.where((m) => m.wajeehId == wajeeh.id).toList();
      final anyFollowerMatches = allFollowersEligible.any((f) => _filteredMembers.any((m) => m.id == f.id));
      return wajeehMatches || anyFollowerMatches;
    }).toList();

    final orphansToShow = _filteredMembers.where((m) => !m.isWajeeh && m.wajeehId == null).toList();

    return ListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        ...wajeehsToShow.map((wajeeh) {
          // Show only followers that match the current filter
          final matchingFollowers = _filteredMembers.where((m) => m.wajeehId == wajeeh.id).toList();
          final wajeehMatches = _filteredMembers.any((m) => m.id == wajeeh.id);

          if (matchingFollowers.isEmpty && !wajeehMatches) {
            return const SizedBox.shrink();
          }

          // If only the wajeeh himself matches and no followers, show as simple tile
          if (matchingFollowers.isEmpty && wajeehMatches) {
            // Check if this wajeeh has any eligible followers at all
            final hasAnyFollowers = eligibleMembers.any((m) => m.wajeehId == wajeeh.id);
            if (!hasAnyFollowers) {
              return _buildMemberListItem(wajeeh);
            }
          }

          // Count of matching followers for subtitle
          final subtitleFollowersCount = matchingFollowers.length;

          return Card(
            elevation: 0,
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            child: ExpansionTile(
              initiallyExpanded: true,
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
              subtitle: Text(
                'وجيه | ${wajeeh.phone}${subtitleFollowersCount > 0 ? " | $subtitleFollowersCount تابع مطابق" : ""}',
                style: const TextStyle(fontSize: 12, color: Colors.amber),
              ),
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
                  Switch(
                    value: _payments.containsKey(wajeeh.id),
                    activeTrackColor: Colors.green.shade400,
                    activeColor: Colors.green.shade900,
                    onChanged: (_) => _togglePayment(wajeeh.id!),
                  ),
                ],
              ),
              children: [
                // Show wajeeh's own payment breakdown only if he matches the filter
                if (wajeehMatches) ...[
                  _buildWajeehBreakdownChild(wajeeh),
                  const Divider(height: 1, thickness: 0.5),
                ],
                // Show matching followers
                ...matchingFollowers.map((m) => Padding(
                  padding: const EdgeInsets.only(right: 16.0),
                  child: _buildMemberListItem(m),
                )),
              ],
            ),
          );
        }),
        ...orphansToShow.map((m) => _buildMemberListItem(m)),
      ],
    );
  }

  Widget _buildWajeehBreakdownChild(Member wajeeh) {
    final paidAmount = _payments[wajeeh.id];
    double memberShare = _diyah.sharePerMember;
    if (wajeeh.id == _diyah.causedById && _diyah.ownerPercentage != null) {
      memberShare = _diyah.amount * (_diyah.ownerPercentage! / 100);
    }
    final cashPaid = paidAmount ?? 0.0;
    final balanceBefore = wajeeh.balance - cashPaid + memberShare;

    double coveredFromBalance = 0.0;
    double remainingClaim = memberShare - cashPaid;

    if (remainingClaim > 0 && balanceBefore > 0) {
      coveredFromBalance = balanceBefore >= remainingClaim ? remainingClaim : balanceBefore;
      remainingClaim = remainingClaim - coveredFromBalance;
    }
    if (remainingClaim < 0) remainingClaim = 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('تفاصيل تسديد الوجيه نفسه:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber.shade900, fontSize: 13)),
          const SizedBox(height: 4),
          _buildPaymentBreakdownWidget(wajeeh, memberShare, cashPaid, coveredFromBalance, remainingClaim),
        ],
      ),
    );
  }

  Widget _buildInPlaceBadge(String label, Color color) {
    return Container(
      margin: const EdgeInsets.only(left: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(50)),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildPaymentBreakdownWidget(Member member, double memberShare, double cashPaid, double coveredFromBalance, double remainingClaim) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('• المدفوع نقداً: ${intl.NumberFormat('#,##0.##').format(cashPaid)} د.ع', 
          style: TextStyle(fontSize: 12, color: cashPaid > 0 ? Colors.green.shade800 : Colors.black87)),
        if (coveredFromBalance > 0)
          Text('• خصم من الرصيد المتوفر: ${intl.NumberFormat('#,##0.##').format(coveredFromBalance)} د.ع', 
            style: TextStyle(fontSize: 12, color: Colors.blue.shade800)),
        if (remainingClaim > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text('• المتبقي كطلب بالذمة (سالب): ${intl.NumberFormat('#,##0.##').format(remainingClaim)} د.ع', 
                    style: TextStyle(fontSize: 12, color: Colors.red.shade800, fontWeight: FontWeight.w600)),
                ),
                ElevatedButton.icon(
                  onPressed: () => _payRemaining(member.id!, remainingClaim, cashPaid),
                  icon: const Icon(Icons.payment, size: 12, color: Colors.red),
                  label: const Text('دفع الباقي', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    backgroundColor: Colors.red.shade50,
                    foregroundColor: Colors.red.shade900,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                ),
              ],
            ),
          ),
        if (cashPaid >= memberShare)
          Text(
            cashPaid > memberShare 
              ? '• تم التسديد بالكامل وفائض +${intl.NumberFormat('#,##0.##').format(cashPaid - memberShare)} د.ع للرصيد' 
              : '• تم التسديد بالكامل نقداً',
            style: TextStyle(fontSize: 12, color: Colors.green.shade900, fontWeight: FontWeight.bold),
          ),
        if (cashPaid < memberShare && remainingClaim == 0)
          Text('• تم تغطية باقي الحصة بالكامل من الرصيد السابق', 
            style: TextStyle(fontSize: 12, color: Colors.green.shade900, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Future<void> _payRemaining(int memberId, double remainingAmount, double currentPaid) async {
    final member = _allMembers.firstWhere((m) => m.id == memberId);
    final amountController = TextEditingController(text: intl.NumberFormat('#,##0.##').format(remainingAmount));
    
    final resultAmount = await showDialog<double>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text('دفع المتبقي لـ ${member.fullName}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('المبلغ المتبقي بالذمة: ${intl.NumberFormat('#,##0.##').format(remainingAmount)} د.ع', 
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
              const SizedBox(height: 16),
              TextField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                inputFormatters: [AmountInputFormatter()],
                decoration: const InputDecoration(
                  labelText: 'المبلغ المدفوع الآن (د.ع)',
                  border: OutlineInputBorder(),
                ),
                autofocus: true,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, NumberUtility.tryParseDouble(amountController.text)),
              child: const Text('تأكيد الدفع'),
            ),
          ],
        ),
      )
    );

    if (resultAmount == null || resultAmount <= 0) return;

    final double newTotalPayment = currentPaid + resultAmount;

    setState(() {
      _payments[memberId] = newTotalPayment;
      _applyFilters();
    });

    try {
      if (!mounted) return;
      await ApiService.updateDiyahPayments(_diyah.id!, _payments);
      if (!mounted) return;
      NotificationService().addNotification(
        title: 'تعديل سداد',
        message: 'تم تحديث حالة دفع ${member.fullName} لدية ${_diyah.title}',
        type: NotificationType.diyah,
        entityId: _diyah.id,
      );
      
      // Check if all members paid now and offer closing
      _checkAndPromptDiyahCompletion();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ في المزامنة: $e')));
    }
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
}
