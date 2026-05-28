import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import '../models/member_model.dart';
import '../models/wallet_transaction_model.dart';
import '../services/api_service.dart';
import '../widgets/custom_app_bar.dart';
import '../widgets/smart_search_bar.dart';
import '../widgets/member_tile.dart';
import 'member_details_screen.dart';
import '../theme/app_theme.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  // Wallet Status Stats
  double _totalBalance = 0.0;
  int _totalMembersCount = 0;
  double _totalPositiveFunds = 0.0;
  double _totalDeficit = 0.0;

  // Data lists
  List<WalletTransaction> _transactions = [];
  List<Member> _allMembers = [];
  List<Member> _owingMembers = [];
  List<Member> _settledMembers = [];

  // Filtered lists for search
  List<WalletTransaction> _filteredTransactions = [];
  List<Member> _filteredOwingMembers = [];
  List<Member> _filteredSettledMembers = [];

  // Loading & Search Queries
  bool _isLoadingStatus = true;
  bool _isLoadingTransactions = true;
  bool _isLoadingMembers = true;
  
  String _txSearchQuery = "";
  String _owingSearchQuery = "";
  String _settledSearchQuery = "";

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  Future<void> _loadAllData() async {
    await Future.wait([
      _loadWalletStatus(),
      _loadTransactions(),
      _loadMembers(),
    ]);
  }

  Future<void> _loadWalletStatus() async {
    if (!mounted) return;
    setState(() => _isLoadingStatus = true);
    try {
      final status = await ApiService.getWalletStatus();
      if (mounted) {
        setState(() {
          _totalBalance = (status['total_balance'] as num?)?.toDouble() ?? 0.0;
          _totalMembersCount = (status['total_members'] as num?)?.toInt() ?? 0;
          _totalPositiveFunds = (status['total_positive_funds'] as num?)?.toDouble() ?? 0.0;
          _totalDeficit = (status['total_deficit'] as num?)?.toDouble() ?? 0.0;
          _isLoadingStatus = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingStatus = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في تحميل إحصائيات الصندوق: $e')),
        );
      }
    }
  }

  Future<void> _loadTransactions() async {
    if (!mounted) return;
    setState(() => _isLoadingTransactions = true);
    try {
      final txs = await ApiService.getWalletTransactions(query: _txSearchQuery);
      if (mounted) {
        setState(() {
          _transactions = txs;
          _filteredTransactions = txs;
          _isLoadingTransactions = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingTransactions = false);
      }
    }
  }

  Future<void> _loadMembers() async {
    if (!mounted) return;
    setState(() => _isLoadingMembers = true);
    try {
      final members = await ApiService.getMembers();
      if (mounted) {
        setState(() {
          _allMembers = members;
          _owingMembers = members.where((m) => m.balance < 0).toList();
          _settledMembers = members.where((m) => m.balance >= 0).toList();
          
          // Apply initial search
          _applyOwingFilter();
          _applySettledFilter();
          
          _isLoadingMembers = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingMembers = false);
      }
    }
  }

  void _applyOwingFilter() {
    setState(() {
      _filteredOwingMembers = _owingMembers.where((m) {
        return SmartSearchBar.matches(m.fullName, _owingSearchQuery) ||
               SmartSearchBar.matches(m.phone, _owingSearchQuery);
      }).toList();
    });
  }

  void _applySettledFilter() {
    setState(() {
      _filteredSettledMembers = _settledMembers.where((m) {
        return SmartSearchBar.matches(m.fullName, _settledSearchQuery) ||
               SmartSearchBar.matches(m.phone, _settledSearchQuery);
      }).toList();
    });
  }

  String _getTransactionTypeArabic(String type) {
    switch (type) {
      case 'diyah_share':
        return 'حصة ديّة (مستحق)';
      case 'cash_payment':
        return 'تسديد نقدي';
      case 'admin_adjustment':
        return 'تعديل إداري';
      default:
        return type;
    }
  }

  Color _getTransactionColor(double amount) {
    if (amount > 0) return Colors.green.shade700;
    if (amount < 0) return Colors.red.shade700;
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    final currencyFmt = intl.NumberFormat('#,##0.##');

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: const CustomAppBar(
          title: 'محفظة العشيرة والصندوق',
          showBackButton: true,
        ),
        body: RefreshIndicator(
          onRefresh: _loadAllData,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Total Balance Statistics Card
                _buildStatsCard(currencyFmt),
                const SizedBox(height: 20),

                // 1. Dropdown for Transactions Ledger
                _buildTransactionsDropdown(currencyFmt),
                const SizedBox(height: 14),

                // 2. Dropdown for Settled (Not Owing) Members
                _buildSettledMembersDropdown(currencyFmt),
                const SizedBox(height: 14),

                // 3. Dropdown for Owing Members
                _buildOwingMembersDropdown(currencyFmt),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTransactionsDropdown(intl.NumberFormat currencyFmt) {
    return Card(
      elevation: 2,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        title: const Text(
          'سجل حركة المعاملات والعمليات المالية',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        leading: const Icon(Icons.receipt_long, color: AppColors.primary),
        childrenPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        initiallyExpanded: false,
        children: [
          SmartSearchBar(
            hintText: 'ابحث في السجل عن عضو أو بيان...',
            onChanged: (val) {
              _txSearchQuery = val;
              _loadTransactions();
            },
          ),
          const SizedBox(height: 12),
          _isLoadingTransactions
              ? const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
              : _filteredTransactions.isEmpty
                  ? const Center(child: Padding(padding: EdgeInsets.all(20), child: Text('لا توجد عمليات مسجلة تطابق البحث.')))
                  : Column(
                      children: _filteredTransactions.map((tx) {
                        final isPositive = tx.amount > 0;
                        return Column(
                          children: [
                            ListTile(
                              contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 0),
                              leading: CircleAvatar(
                                radius: 18,
                                backgroundColor: isPositive ? Colors.green.shade50 : Colors.red.shade50,
                                child: Icon(
                                  isPositive ? Icons.add_circle_outline : Icons.remove_circle_outline,
                                  color: isPositive ? Colors.green : Colors.red,
                                  size: 18,
                                ),
                              ),
                              title: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      tx.memberName ?? 'مجهول',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Text(
                                    '${isPositive ? "+" : ""}${currencyFmt.format(tx.amount)} د.ع',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: _getTransactionColor(tx.amount),
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 4),
                                  if (tx.diyahTitle != null)
                                    Text(
                                      'الديّة: ${tx.diyahTitle}',
                                      style: const TextStyle(color: Colors.black87, fontSize: 12),
                                    ),
                                  Text(
                                    'النوع: ${_getTransactionTypeArabic(tx.transactionType)}',
                                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                  ),
                                  if (tx.description != null && tx.description!.isNotEmpty)
                                    Text(
                                      tx.description!,
                                      style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: Colors.grey.shade500),
                                    ),
                                  const SizedBox(height: 2),
                                  Text(
                                    intl.DateFormat('yyyy-MM-dd HH:mm').format(tx.createdAt.toLocal()),
                                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                                  ),
                                ],
                              ),
                            ),
                            const Divider(height: 1, thickness: 0.5),
                          ],
                        );
                      }).toList(),
                    ),
        ],
      ),
    );
  }

  Widget _buildSettledMembersDropdown(intl.NumberFormat currencyFmt) {
    return Card(
      elevation: 2,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        title: Text(
          'الأعضاء غير المطلوبين (${_filteredSettledMembers.length})',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        leading: const Icon(Icons.check_circle_outline, color: Colors.green),
        childrenPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          SmartSearchBar(
            hintText: 'بحث في الأعضاء غير المطلوبين...',
            onChanged: (val) {
              _settledSearchQuery = val;
              _applySettledFilter();
            },
          ),
          const SizedBox(height: 12),
          _isLoadingMembers
              ? const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
              : _filteredSettledMembers.isEmpty
                  ? const Center(child: Padding(padding: EdgeInsets.all(20), child: Text('لا يوجد أعضاء تطابق البحث.')))
                  : Column(
                      children: _filteredSettledMembers.map((member) {
                        final hasSurplus = member.balance > 0;
                        return MemberTile(
                          member: member,
                          subtitleOverride: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(member.phone, style: const TextStyle(color: Colors.grey, fontSize: 13)),
                              Text(
                                hasSurplus
                                    ? 'رصيده الفائض: +${currencyFmt.format(member.balance)} د.ع'
                                    : 'الرصيد: صفر (مسدد بالكامل)',
                                style: TextStyle(
                                  color: hasSurplus ? Colors.green : Colors.grey.shade700,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => MemberDetailsScreen(member: member),
                              ),
                            ).then((_) => _loadAllData());
                          },
                        );
                      }).toList(),
                    ),
        ],
      ),
    );
  }

  Widget _buildOwingMembersDropdown(intl.NumberFormat currencyFmt) {
    return Card(
      elevation: 2,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        title: Text(
          'الأعضاء المطلوبين (${_filteredOwingMembers.length})',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        leading: const Icon(Icons.warning_amber_rounded, color: Colors.red),
        childrenPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          SmartSearchBar(
            hintText: 'بحث في الأعضاء المطلوبين...',
            onChanged: (val) {
              _owingSearchQuery = val;
              _applyOwingFilter();
            },
          ),
          const SizedBox(height: 12),
          _isLoadingMembers
              ? const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
              : _filteredOwingMembers.isEmpty
                  ? const Center(child: Padding(padding: EdgeInsets.all(20), child: Text('لا يوجد أعضاء مطلوبين تطابق البحث.')))
                  : Column(
                      children: _filteredOwingMembers.map((member) {
                        return MemberTile(
                          member: member,
                          subtitleOverride: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(member.phone, style: const TextStyle(color: Colors.grey, fontSize: 13)),
                              Text(
                                'المتبقي بذمته: ${currencyFmt.format(member.balance.abs())} د.ع',
                                style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => MemberDetailsScreen(member: member),
                              ),
                            ).then((_) => _loadAllData());
                          },
                        );
                      }).toList(),
                    ),
        ],
      ),
    );
  }

  Widget _buildStatsCard(intl.NumberFormat currencyFmt) {
    if (_isLoadingStatus) {
      return Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: const Padding(
          padding: EdgeInsets.all(40.0),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final isPositive = _totalBalance >= 0;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [
              AppColors.primary.withAlpha(240),
              AppColors.primaryLight.withAlpha(240),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            const Text(
              'الرصيد الإجمالي للصندوق',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '${isPositive ? "" : "-"}${currencyFmt.format(_totalBalance.abs())} د.ع',
                style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 16),
            const Divider(color: Colors.white24),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      const Text(
                        'الأموال الفائضة المتوفرة',
                        style: TextStyle(color: Colors.white70, fontSize: 11),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${currencyFmt.format(_totalPositiveFunds)} د.ع',
                        style: const TextStyle(color: Colors.greenAccent, fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                Container(width: 1, height: 40, color: Colors.white24),
                Expanded(
                  child: Column(
                    children: [
                      const Text(
                        'إجمالي المديونية المطلوبة',
                        style: TextStyle(color: Colors.white70, fontSize: 11),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${currencyFmt.format(_totalDeficit)} د.ع',
                        style: const TextStyle(color: Colors.orangeAccent, fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(color: Colors.white24),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.people_outline, color: Colors.white70, size: 16),
                const SizedBox(width: 6),
                Text(
                  'عدد المساهمين: $_totalMembersCount شخص',
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
