import 'package:flutter/material.dart';
import '../models/member_model.dart';
import '../theme/app_theme.dart';
import '../screens/member_details_screen.dart';

class MemberTile extends StatelessWidget {
  final Member member;
  final VoidCallback? onRefresh;
  final Widget? trailing;
  final Widget? subtitleOverride;
  final VoidCallback? onTap;

  const MemberTile({
    super.key,
    required this.member,
    this.onRefresh,
    this.trailing,
    this.subtitleOverride,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        onTap: onTap ?? () async {
          final updated = await Navigator.push(
            context,
            MaterialPageRoute(builder: (ctx) => MemberDetailsScreen(member: member)),
          );
          if (updated == true && onRefresh != null) {
            onRefresh!();
          }
        },
        leading: CircleAvatar(
          backgroundColor: member.isWajeeh ? AppColors.primary.withAlpha(20) : Colors.blue.withAlpha(10),
          child: Icon(
            member.isWajeeh ? Icons.star : Icons.person,
            color: member.isWajeeh ? AppColors.primary : Colors.blue,
            size: 20,
          ),
        ),
        title: Row(
          children: [
            Expanded(child: Text(member.fullName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
            _buildRoleBadge(),
          ],
        ),
        subtitle: subtitleOverride ?? Text(member.phone, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
        trailing: trailing,
      ),
    );
  }

  Widget _buildRoleBadge() {
    String adminRoleName = "";
    Color adminRoleColor = Colors.transparent;
    
    if (member.role == 'owner') {
      adminRoleName = "المالك";
      adminRoleColor = Colors.purple;
    } else if (member.role == 'sheikh') {
      adminRoleName = "شيخ";
      adminRoleColor = Colors.orange.shade800;
    } else if (member.role == 'admin') {
      adminRoleName = "مشرف";
      adminRoleColor = Colors.red.shade700;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (adminRoleName.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(left: 4),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: adminRoleColor.withAlpha(30),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: adminRoleColor.withAlpha(50)),
            ),
            child: Text(
              adminRoleName,
              style: TextStyle(
                fontSize: 10,
                color: adminRoleColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: member.isWajeeh ? AppColors.primary.withAlpha(30) : Colors.blueGrey.withAlpha(30),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            member.isWajeeh ? 'وجيه' : 'عضو',
            style: TextStyle(
              fontSize: 10,
              color: member.isWajeeh ? AppColors.primary : Colors.blueGrey,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}
