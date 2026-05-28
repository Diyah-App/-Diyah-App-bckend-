import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../screens/login_screen.dart';
import '../screens/wallet_screen.dart';
import '../screens/home_screen.dart';

class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? extraActions;
  final bool showBackButton;
  final PreferredSizeWidget? bottom;

  const CustomAppBar({
    super.key,
    required this.title,
    this.extraActions,
    this.showBackButton = true,
    this.bottom,
  });

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();

    return AppBar(
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
        overflow: TextOverflow.ellipsis,
      ),
      centerTitle: true,
      leading: (showBackButton && canPop)
          ? IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.of(context).pop(),
            )
          : null,
      actions: [
        if (extraActions != null) ...extraActions!,
        // Wallet Icon (Visible to all, as the balance is public)
        IconButton(
          icon: const Icon(Icons.account_balance_wallet_outlined),
          tooltip: 'المحفظة والصندوق',
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const WalletScreen()),
            );
          },
        ),
        // Notification Badge Icon
        const NotificationBadgeIcon(),
        // Login / Logout Icon
        IconButton(
          icon: Icon(AuthService.isLoggedIn ? Icons.logout : Icons.login),
          tooltip: AuthService.isLoggedIn ? 'تسجيل الخروج' : 'تسجيل الدخول',
          onPressed: () async {
            if (AuthService.isLoggedIn) {
              await AuthService.logout();
              if (!context.mounted) return;
              Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const HomeScreen()),
                (route) => false,
              );
            } else {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
            }
          },
        ),
      ],
      bottom: bottom,
    );
  }

  @override
  Size get preferredSize => Size.fromHeight(56.0 + (bottom?.preferredSize.height ?? 0.0));
}
