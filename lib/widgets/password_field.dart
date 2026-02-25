import 'package:flutter/material.dart';

class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    this.hintText = 'Password',
    this.errorText,
    this.enabled = true,
    this.textInputAction,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String hintText;
  final String? errorText;
  final bool enabled;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TextField(
      controller: widget.controller,
      enabled: widget.enabled,
      obscureText: _obscure,
      decoration: InputDecoration(
        prefixIcon: Icon(Icons.lock_outline, color: cs.onSurfaceVariant),
        hintText: widget.hintText,
        errorText: widget.errorText,
        suffixIcon: IconButton(
          icon: Icon(
            _obscure
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            color: cs.onSurfaceVariant,
          ),
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
      ),
      textInputAction: widget.textInputAction,
      onSubmitted: widget.onSubmitted,
    );
  }
}
