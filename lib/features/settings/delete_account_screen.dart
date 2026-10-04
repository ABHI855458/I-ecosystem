import 'package:flutter/material.dart';

import '../../services/account_service.dart';
import '../profile_v2/profile_v2_tokens.dart';
import 'settings_scaffold.dart';

// ---------------------------------------------------------------------------
// DeleteAccountScreen — two-step confirmation before anything irreversible
// happens: the commit button stays disabled until the user types DELETE,
// and pressing it opens a final AlertDialog before AccountService actually
// runs. See account_service.dart / supabase/functions/delete-account for
// what deletion actually does (soft-delete + permanent ban, not a hard
// delete — auth.users can't be hard-deleted without violating FKs, see
// that function's own header).
// ---------------------------------------------------------------------------

class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  final _confirmController = TextEditingController();
  bool _confirmed = false;
  bool _deleting = false;
  String? _error;

  @override
  void dispose() {
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _onCommit() async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: PV2.raised,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Delete account?', style: PV2.body(size: 16, weight: FontWeight.w700)),
        content: Text(
          'This cannot be undone. Your posts, moments, group posts, comments, '
          'and reactions will be removed, and you will not be able to sign '
          'back in.',
          style: PV2.body(size: 13.5, color: PV2.inkBio, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('Cancel', style: PV2.body(size: 14, color: PV2.inkStamp)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Delete', style: PV2.body(size: 14, weight: FontWeight.w800, color: PV2.danger)),
          ),
        ],
      ),
    );
    if (proceed != true || !mounted) return;

    setState(() {
      _deleting = true;
      _error = null;
    });
    try {
      await AccountService.instance.deleteAccount();
      // AuthGate's own auth-state listener swaps to AuthScreen once the
      // session clears — this pop is only needed because that swap happens
      // invisibly underneath this still-pushed screen, same fix
      // settings_screen.dart's _LogoutSection already uses.
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e, st) {
      debugPrint('[DeleteAccountScreen._onCommit] failed: $e\n$st');
      if (mounted) {
        setState(() {
          _deleting = false;
          _error = "Couldn't delete your account — try again.";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsScaffold(
      title: 'Delete Account',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Deleting your account removes your posts, moments, group posts, '
            'comments, and reactions, removes your circles and group '
            'memberships, and permanently blocks you from signing back in. '
            'This cannot be undone.',
            style: PV2.body(size: 13.5, color: PV2.inkBio, height: 1.5),
          ),
          const SizedBox(height: 20),
          SettingsInputCard(
            label: 'Type DELETE to confirm',
            field: TextField(
              controller: _confirmController,
              textCapitalization: TextCapitalization.characters,
              cursorColor: PV2.danger,
              style: PV2.body(size: 15, weight: FontWeight.w700),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                hintText: 'DELETE',
                hintStyle: PV2.body(size: 15, color: PV2.inkStamp),
              ),
              onChanged: (v) => setState(() => _confirmed = v.trim() == 'DELETE'),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: PV2.body(size: 12.5, color: PV2.danger)),
          ],
          const SizedBox(height: 18),
          SettingsCommitButton(
            label: 'Delete account',
            enabled: _confirmed,
            destructive: true,
            loading: _deleting,
            onTap: _onCommit,
          ),
        ],
      ),
    );
  }
}
