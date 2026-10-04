import 'package:flutter/material.dart';

import '../../services/block_service.dart';
import '../profile_v2/profile_v2_tokens.dart';
import 'settings_scaffold.dart';

// ---------------------------------------------------------------------------
// BlockedUsersScreen — real list of everyone the current user has blocked,
// via BlockService (see that file's own doc on the blocks table's auth-UID
// key space). Unblock issues a real delete and surfaces failure with a
// SnackBar, matching settings_screen.dart's _BlockedUsersSection this was
// modeled on.
// ---------------------------------------------------------------------------

class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  List<BlockedUser>? _blocked;
  // Blocks made from anonymous posts: shown as "Anonymous poster", never a
  // name (the app can't read who they are; see BlockService.fetchAnonBlocks).
  List<({String id, DateTime createdAt})> _anon = const [];
  String? _error;
  final Set<String> _unblocking = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final blocked = await BlockService.instance.fetchBlocked();
      final anon = await BlockService.instance
          .fetchAnonBlocks()
          .catchError((_) => <({String id, DateTime createdAt})>[]);
      if (mounted) {
        setState(() {
          _blocked = blocked;
          _anon = anon;
        });
      }
    } catch (e, st) {
      debugPrint('[BlockedUsersScreen._load] failed: $e\n$st');
      if (mounted) setState(() => _error = "Couldn't load blocked users.");
    }
  }

  Future<void> _unblock(BlockedUser b) async {
    setState(() => _unblocking.add(b.authId));
    try {
      await BlockService.instance.unblock(b.authId);
      if (mounted) {
        setState(() => _blocked?.removeWhere((x) => x.authId == b.authId));
      }
    } catch (e, st) {
      debugPrint('[BlockedUsersScreen._unblock] failed: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't unblock — try again.")),
        );
      }
    } finally {
      if (mounted) setState(() => _unblocking.remove(b.authId));
    }
  }

  Future<void> _unblockAnon(String id) async {
    setState(() => _unblocking.add(id));
    try {
      await BlockService.instance.unblockAnon(id);
      if (mounted) setState(() => _anon = _anon.where((a) => a.id != id).toList());
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't unblock — try again.")),
        );
      }
    } finally {
      if (mounted) setState(() => _unblocking.remove(id));
    }
  }

  Widget _anonRow(({String id, DateTime createdAt}) a) {
    final busy = _unblocking.contains(a.id);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: PV2.raised,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: PV2.recessed,
            child: Icon(Icons.theater_comedy_rounded, size: 18, color: PV2.inkStamp),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Anonymous poster', style: PV2.body(size: 14, weight: FontWeight.w600)),
                Text(
                  'Blocked from an anonymous post',
                  style: PV2.body(size: 11.5, color: PV2.inkStamp),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: busy ? null : () => _unblockAnon(a.id),
            child: busy
                ? SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: PV2.inkStamp),
                  )
                : Text('Unblock', style: PV2.body(size: 13, color: PV2.accent)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SettingsScaffold(
      title: 'Blocked Users',
      child: _error != null
          ? Text(_error!, style: PV2.body(size: 13, color: PV2.danger))
          : _blocked == null
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2, color: PV2.inkStamp),
                    ),
                  ),
                )
              : _blocked!.isEmpty && _anon.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        "You haven't blocked anyone.",
                        style: PV2.body(size: 13.5, color: PV2.inkStamp),
                      ),
                    )
                  : Column(
                      children: [
                        for (final a in _anon) _anonRow(a),
                        for (final b in _blocked!)
                          Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: PV2.raised,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 18,
                                  backgroundColor: PV2.recessed,
                                  backgroundImage:
                                      b.photoUrl != null ? NetworkImage(b.photoUrl!) : null,
                                  child: b.photoUrl == null
                                      ? Icon(Icons.person, size: 18, color: PV2.inkStamp)
                                      : null,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    b.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: PV2.body(size: 14, weight: FontWeight.w600),
                                  ),
                                ),
                                TextButton(
                                  onPressed: _unblocking.contains(b.authId) ? null : () => _unblock(b),
                                  child: _unblocking.contains(b.authId)
                                      ? SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: PV2.inkStamp,
                                          ),
                                        )
                                      : Text('Unblock', style: PV2.body(size: 13, color: PV2.accent)),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
    );
  }
}
