part of 'hw_factory_binding.dart';

InputDecoration _hwDec(String? hint, {String? label}) => InputDecoration(
  labelText: label,
  hintText: hint,
  labelStyle: Sa.body(size: 12, color: Sa.textDim),
  hintStyle: Sa.body(size: 12, color: Sa.muted),
  filled: true,
  fillColor: Sa.bgRaised.withValues(alpha: 0.6),
  isDense: true,
  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(9),
    borderSide: BorderSide(color: Sa.border),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(9),
    borderSide: BorderSide(color: Sa.cyan),
  ),
);

Widget _hwFieldLabel(String s) => Padding(
  padding: const EdgeInsets.only(bottom: 6),
  child: Text(s, style: Sa.mono(size: 9, color: Sa.muted)),
);

// ───────────────────────── Binding editor ─────────────────────────
