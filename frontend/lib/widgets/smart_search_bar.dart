import 'package:flutter/material.dart';

class SmartSearchBar extends StatelessWidget {
  final String hintText;
  final Function(String) onChanged;
  final TextEditingController? controller;

  const SmartSearchBar({
    super.key, 
    required this.hintText, 
    required this.onChanged,
    this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(10),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        textDirection: TextDirection.rtl,
        decoration: InputDecoration(
          hintText: hintText,
          prefixIcon: const Icon(Icons.search, color: Colors.blueGrey),
          border: InputBorder.none,
          hintStyle: const TextStyle(color: Colors.grey),
        ),
        onChanged: (value) {
          // Normalizing: Trim, lowercase (for non-Arabic if any), and collapse multiple spaces
          final normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ');
          onChanged(normalized);
        },
      ),
    );
  }

  // Static helper for smart fuzzy-like matching
  static bool matches(String text, String query) {
    if (query.isEmpty) return true;
    final cleanText = text.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
    final cleanQuery = query.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
    
    // Basic contains first
    if (cleanText.contains(cleanQuery)) return true;
    
    // Split query by spaces and check if all parts exist in text
    final parts = cleanQuery.split(' ');
    return parts.every((part) => cleanText.contains(part));
  }
}
