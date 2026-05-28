import 'package:flutter/services.dart';

class NumberUtility {
  /// Converts Arabic/Eastern digits to Western digits, removes spaces and commas.
  static String cleanNumberString(String input) {
    var text = input;
    // Replace Eastern Arabic digits with Western digits
    final arabicDigits = {
      '٠': '0',
      '١': '1',
      '٢': '2',
      '٣': '3',
      '٤': '4',
      '٥': '5',
      '٦': '6',
      '٧': '7',
      '٨': '8',
      '٩': '9'
    };
    arabicDigits.forEach((key, value) {
      text = text.replaceAll(key, value);
    });

    // Remove spaces
    text = text.replaceAll(RegExp(r'\s+'), '');

    // Remove commas (thousand separators)
    text = text.replaceAll(',', '');

    return text;
  }

  /// Parses the cleaned number string to double safely.
  static double? tryParseDouble(String input) {
    final cleaned = cleanNumberString(input);
    return double.tryParse(cleaned);
  }
}

/// A TextInputFormatter that permits only numbers (English & Arabic),
/// plus, minus, commas, dots, and spaces.
class AmountInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    // Only allow: 0-9, Eastern Arabic digits, +, -, commas, dots, and spaces
    final regExp = RegExp(r'^[0-9٠-٩\+\-\,\.\s]*$');
    if (regExp.hasMatch(newValue.text)) {
      return newValue;
    }
    return oldValue;
  }
}
