import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_config.dart';
import '../../services/current_user_service.dart';
import 'profile_v2_tokens.dart';
import 'profile_v2_widgets.dart';

// ---------------------------------------------------------------------------
// AnonIdentityEditSheet — the pencil next to the profile's anon-name card
// opens this. A single anon name lives here (required). The second-name /
// Shuffle feature (two switchable anon names) was removed on request — this
// sheet only ever edits the one active `anon_name` now.
//
// Returns `true` via Navigator.pop on a successful save so the caller
// (MyProfileScreen._editAnonIdentity) knows to reload from the DB, `null`/
// `false` otherwise.
// ---------------------------------------------------------------------------

Future<bool?> showAnonIdentityEditSheet(
  BuildContext context, {
  required String anonName1,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _AnonIdentityEditSheet(initialAnonName1: anonName1),
  );
}

class _AnonIdentityEditSheet extends StatefulWidget {
  const _AnonIdentityEditSheet({required this.initialAnonName1});

  final String initialAnonName1;

  @override
  State<_AnonIdentityEditSheet> createState() => _AnonIdentityEditSheetState();
}

class _AnonIdentityEditSheetState extends State<_AnonIdentityEditSheet> {
  late final _name1Controller = TextEditingController(text: widget.initialAnonName1);
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name1Controller.dispose();
    super.dispose();
  }

  String? _validate(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 'Required.';
    if (trimmed.length > 40) return 'Keep it under 40 characters.';
    return null;
  }

  Future<void> _save() async {
    final name1 = _name1Controller.text.trim();
    final firstError = _validate(name1);
    if (firstError != null) {
      setState(() => _error = firstError);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final id = await CurrentUserService.instance.resolveId();
      await supabase.from('users').update({'anon_name': name1}).eq('id', id);
      if (mounted) Navigator.of(context).pop(true);
    } on PostgrestException catch (e, st) {
      debugPrint('[AnonIdentityEditSheet._save] failed: ${e.code} ${e.message}\n$st');
      if (mounted) {
        setState(
          () => _error = e.code == '23505'
              ? "That anon name's taken — try another."
              : "Couldn't save — try again.",
        );
      }
    } catch (e, st) {
      debugPrint('[AnonIdentityEditSheet._save] failed: $e\n$st');
      if (mounted) setState(() => _error = "Couldn't save — try again.");
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          decoration: BoxDecoration(
            color: PV2.raised,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: PV2.hairlineBright),
            boxShadow: PV2.raisedLg,
          ),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: PV2.hairlineActive,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text('Anon identity', style: PV2.display(size: 18)),
              const SizedBox(height: 4),
              Text(
                'Never linked to your real name or photo.',
                style: PV2.body(size: 12.5, color: PV2.inkByline),
              ),
              const SizedBox(height: 18),
              _label('Anon name'),
              const SizedBox(height: 6),
              _field(_name1Controller, hint: 'A name for the Anonymous feed'),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: PV2.body(size: 12.5, color: PV2.danger)),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: GestureDetector(
                  onTap: _saving ? null : _save,
                  child: Container(
                    height: 46,
                    decoration: BoxDecoration(
                      gradient: PV2.accentButton,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    alignment: Alignment.center,
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: PV2.onAccent),
                          )
                        : Text(
                            'Save',
                            style: PV2.body(
                              size: 14.5,
                              weight: FontWeight.w700,
                              color: PV2.onAccent,
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Text(
        text,
        style: PV2.caps(size: 10.5, tracking: 0.08, color: PV2.inkLabel),
      );

  Widget _field(TextEditingController controller, {required String hint}) {
    return NeuWell(
      radius: 14,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: TextField(
        controller: controller,
        maxLength: 40,
        style: PV2.body(size: 15, color: PV2.ink),
        decoration: InputDecoration(
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          focusedErrorBorder: InputBorder.none,
          isDense: true,
          counterText: '',
          hintText: hint,
          hintStyle: PV2.body(size: 15, color: PV2.inkHandle),
        ),
      ),
    );
  }
}
