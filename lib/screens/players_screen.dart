import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/database_helper.dart';
import '../services/auth_service.dart';
import '../services/sync_service.dart';
import '../theme.dart';

// Bowling type colours are role-specific — not theme-dependent.
const Color _colorFast = Color(0xFFFF6B35);
const Color _colorSpin = Color(0xFF7C4DFF);

const List<String> _roleOptions = ['batter', 'bowler', 'all-rounder', 'wicket-keeper'];
const List<String> _bowlingTypes = ['Fast', 'Spin'];

bool _roleHasBowlingType(String? role) =>
    role == 'bowler' || role == 'all-rounder';

/// Screen for browsing and managing the global players registry.
class PlayersScreen extends StatefulWidget {
  const PlayersScreen({super.key});

  @override
  State<PlayersScreen> createState() => _PlayersScreenState();
}

class _PlayersScreenState extends State<PlayersScreen> {
  List<Map<String, dynamic>> _players = [];
  bool _loading = true;
  bool _syncing = false;
  StreamSubscription<SyncState>? _syncSub;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _searchDebounce;

  List<Map<String, dynamic>> get _filteredPlayers {
    if (_searchQuery.isEmpty) return _players;
    final query = _searchQuery.toLowerCase();
    return _players.where((p) {
      final name = (p[DatabaseHelper.colName] as String).toLowerCase();
      return name.contains(query);
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      _searchDebounce?.cancel();
      _searchDebounce = Timer(const Duration(milliseconds: 200), () {
        if (mounted) setState(() => _searchQuery = _searchController.text);
      });
    });
    _syncSub = SyncService.instance.syncStatusStream.listen((state) {
      if (state == SyncState.synced || state == SyncState.error) {
        _loadPlayers();
      }
    });
    _syncAndLoad();
  }

  @override
  void dispose() {
    _syncSub?.cancel();
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _syncAndLoad() async {
    if (mounted) setState(() => _syncing = true);
    try {
      await SyncService.instance.syncDownInitialData(force: true);
    } finally {
      if (mounted) setState(() => _syncing = false);
      await _loadPlayers();
    }
  }

  Future<void> _loadPlayers() async {
    if (mounted) setState(() => _loading = true);
    try {
      final userId = AuthService.instance.userId;
      final players = await DatabaseHelper.instance.fetchPlayersForUser(userId);
      if (mounted) {
        setState(() {
          _players = players;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deletePlayer(int id) async {
    await DatabaseHelper.instance.deletePlayer(id);
    await _loadPlayers();
  }

  void _showConfirmDelete(Map<String, dynamic> player) {
    final name = player[DatabaseHelper.colName] as String;
    final c = Theme.of(context).appColors;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Delete Player',
          style: GoogleFonts.rajdhani(fontWeight: FontWeight.w700, color: c.textPrimary),
        ),
        content: Text(
          'Remove "$name" from the global roster?',
          style: GoogleFonts.rajdhani(color: c.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: GoogleFonts.rajdhani(fontWeight: FontWeight.w600, color: c.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _deletePlayer(player[DatabaseHelper.colId] as int);
            },
            child: Text(
              'Delete',
              style: GoogleFonts.rajdhani(fontWeight: FontWeight.w700, color: c.liveRed),
            ),
          ),
        ],
      ),
    );
  }

  void _showAddPlayerDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PlayerFormSheet(
        onSave: (name, team, role, bowlingType, localAvatarPath) async {
          final createdBy = AuthService.instance.currentUser?.id;
          await DatabaseHelper.instance.insertPlayer(
            name: name,
            team: team,
            role: role,
            bowlingType: bowlingType,
            localAvatarPath: localAvatarPath,
            createdBy: createdBy,
          );
          await _loadPlayers();
        },
      ),
    );
  }

  void _showEditPlayerDialog(Map<String, dynamic> player) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PlayerFormSheet(
        initialName:        player[DatabaseHelper.colName]            as String,
        initialTeam:        player[DatabaseHelper.colTeam]            as String,
        initialRole:        player[DatabaseHelper.colRole]            as String?,
        initialBowlingType: player[DatabaseHelper.colBowlingType]     as String?,
        initialAvatarPath:  player[DatabaseHelper.colLocalAvatarPath] as String?,
        onSave: (name, team, role, bowlingType, localAvatarPath) async {
          await DatabaseHelper.instance.updatePlayer(
            player[DatabaseHelper.colId] as int,
            name: name,
            team: team,
            role: role,
            bowlingType: bowlingType,
            localAvatarPath: localAvatarPath,
          );
          await _loadPlayers();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).appColors;
    return Scaffold(
      backgroundColor: c.surface,
      body: RefreshIndicator(
        color: c.accent,
        backgroundColor: c.card,
        onRefresh: _syncAndLoad,
        child: CustomScrollView(
          slivers: [
            _buildAppBar(c),
            if (_syncing)
              SliverToBoxAdapter(
                child: LinearProgressIndicator(
                  color: c.accent,
                  backgroundColor: c.accent.withAlpha(30),
                  minHeight: 2,
                ),
              ),
            SliverToBoxAdapter(child: _buildSearchBar(c)),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              sliver: _loading
                  ? SliverFillRemaining(
                      child: Center(
                        child: CircularProgressIndicator(color: c.accent),
                      ),
                    )
                  : (_players.isEmpty && _searchQuery.isEmpty)
                      ? _buildEmptyState(c)
                      : _buildPlayerList(c),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddPlayerDialog,
        tooltip: 'Add Player',
        child: const Icon(Icons.person_add),
      ),
    );
  }

  Widget _buildSearchBar(AppColors c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: TextField(
        controller: _searchController,
        style: GoogleFonts.rajdhani(fontSize: 16, color: c.textPrimary),
        decoration: InputDecoration(
          hintText: 'Search players...',
          hintStyle: GoogleFonts.rajdhani(fontSize: 16, color: c.textSecondary),
          prefixIcon: Icon(Icons.search, color: c.accent),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.clear, color: c.textSecondary, size: 20),
                  onPressed: () => _searchController.clear(),
                )
              : null,
          filled: true,
          fillColor: c.glassBg,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: c.glassBorder, width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: c.accent, width: 1.5),
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar(AppColors c) {
    final subtitle = _syncing
        ? 'SYNCING...'
        : _players.isEmpty
            ? 'GLOBAL ROSTER'
            : '${_players.length} PLAYERS';
    return SliverAppBar(
      expandedHeight: 120,
      floating: false,
      pinned: true,
      backgroundColor: c.accentDark,
      automaticallyImplyLeading: false,
      flexibleSpace: FlexibleSpaceBar(
        centerTitle: true,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Players',
              style: GoogleFonts.rajdhani(
                fontSize: 22, fontWeight: FontWeight.w900,
                color: Colors.white, letterSpacing: 2,
              ),
            ),
            Text(
              subtitle,
              style: GoogleFonts.rajdhani(
                fontSize: 10, fontWeight: FontWeight.w600,
                color: kAccentNeon, letterSpacing: 3,
              ),
            ),
          ],
        ),
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [kAccentDark, Color(0xFF0D3318)],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(AppColors c) {
    if (_searchQuery.isNotEmpty) {
      return SliverFillRemaining(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.search_off, size: 80, color: c.accent.withAlpha(120)),
              const SizedBox(height: 24),
              Text(
                'No Results Found',
                style: GoogleFonts.rajdhani(
                    fontSize: 24, fontWeight: FontWeight.w700, color: c.textSecondary),
              ),
              const SizedBox(height: 8),
              Text(
                'No players match "$_searchQuery".',
                style: GoogleFonts.rajdhani(fontSize: 16, color: c.textSecondary),
              ),
              const SizedBox(height: 100),
            ],
          ),
        ),
      );
    }
    return SliverFillRemaining(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 80, color: c.accent.withAlpha(120)),
            const SizedBox(height: 24),
            Text(
              _syncing ? 'Loading Players...' : 'No Players Yet',
              style: GoogleFonts.rajdhani(
                  fontSize: 24, fontWeight: FontWeight.w700, color: c.textSecondary),
            ),
            const SizedBox(height: 8),
            Text(
              _syncing
                  ? 'Downloading community roster from cloud.'
                  : 'Tap + to add your first player.',
              style: GoogleFonts.rajdhani(fontSize: 16, color: c.textSecondary),
            ),
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayerList(AppColors c) {
    final players = _filteredPlayers;
    if (players.isEmpty) return _buildEmptyState(c);
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          if (index == players.length) return const SizedBox(height: 100);
          return _buildPlayerCard(players[index], c);
        },
        childCount: players.length + 1,
      ),
    );
  }

  Widget _buildPlayerCard(Map<String, dynamic> player, AppColors c) {
    final name        = player[DatabaseHelper.colName]            as String;
    final team        = player[DatabaseHelper.colTeam]            as String;
    final role        = player[DatabaseHelper.colRole]            as String?;
    final bowlingType = player[DatabaseHelper.colBowlingType]     as String?;
    final avatarPath  = player[DatabaseHelper.colLocalAvatarPath] as String?;

    final Widget avatarWidget = CircleAvatar(
      radius: 24,
      backgroundColor: c.accent.withAlpha(40),
      backgroundImage: (avatarPath != null && avatarPath.isNotEmpty)
          ? (avatarPath.startsWith('http://') || avatarPath.startsWith('https://'))
              ? CachedNetworkImageProvider(avatarPath) as ImageProvider
              : FileImage(File(avatarPath))
          : null,
      child: (avatarPath == null || avatarPath.isEmpty)
          ? Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: GoogleFonts.rajdhani(
                  fontWeight: FontWeight.w800, color: c.accent, fontSize: 18),
            )
          : null,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            decoration: BoxDecoration(
              color: c.glassBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: c.glassBorder, width: 1),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: avatarWidget,
              title: Text(
                name,
                style: GoogleFonts.rajdhani(
                    fontSize: 17, fontWeight: FontWeight.w700, color: c.textPrimary),
              ),
              subtitle: Row(
                children: [
                  Text(
                    team,
                    style: GoogleFonts.rajdhani(fontSize: 13, color: c.textSecondary),
                  ),
                  if (role != null && role.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    _buildRoleBadge(role, c),
                  ],
                  if (bowlingType != null && bowlingType.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    _buildBowlingTypeBadge(bowlingType),
                  ],
                ],
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(Icons.edit_outlined, color: c.accent, size: 20),
                    onPressed: () => _showEditPlayerDialog(player),
                    tooltip: 'Edit',
                  ),
                  IconButton(
                    icon: Icon(Icons.delete_outline, color: c.liveRed, size: 20),
                    onPressed: () => _showConfirmDelete(player),
                    tooltip: 'Delete',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRoleBadge(String role, AppColors c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: c.accent.withAlpha(30),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.accent.withAlpha(80), width: 1),
      ),
      child: Text(
        role,
        style: GoogleFonts.rajdhani(
            fontSize: 11, fontWeight: FontWeight.w700,
            color: c.accent, letterSpacing: 0.5),
      ),
    );
  }

  Widget _buildBowlingTypeBadge(String type) {
    final isFast = type.toLowerCase() == 'fast';
    final color  = isFast ? _colorFast : _colorSpin;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(100), width: 1),
      ),
      child: Text(
        type,
        style: GoogleFonts.rajdhani(
            fontSize: 11, fontWeight: FontWeight.w700,
            color: color, letterSpacing: 0.5),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// PLAYER FORM BOTTOM SHEET
// ══════════════════════════════════════════════════════════════════════════════

class _PlayerFormSheet extends StatefulWidget {
  final String? initialName;
  final String? initialTeam;
  final String? initialRole;
  final String? initialBowlingType;
  final String? initialAvatarPath;
  final Future<void> Function(
    String name,
    String team,
    String? role,
    String? bowlingType,
    String? localAvatarPath,
  ) onSave;

  const _PlayerFormSheet({
    this.initialName,
    this.initialTeam,
    this.initialRole,
    this.initialBowlingType,
    this.initialAvatarPath,
    required this.onSave,
  });

  @override
  State<_PlayerFormSheet> createState() => _PlayerFormSheetState();
}

class _PlayerFormSheetState extends State<_PlayerFormSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _teamCtrl;
  String? _selectedRole;
  String? _selectedBowlingType;
  String? _avatarPath;
  bool _saving = false;
  List<String> _teamSuggestions = [];

  bool get _showBowlingType => _roleHasBowlingType(_selectedRole);

  @override
  void initState() {
    super.initState();
    _nameCtrl            = TextEditingController(text: widget.initialName ?? '');
    _teamCtrl            = TextEditingController(text: widget.initialTeam ?? '');
    _selectedRole        = widget.initialRole;
    _selectedBowlingType = widget.initialBowlingType;
    _avatarPath          = widget.initialAvatarPath;
    _loadTeamSuggestions();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _teamCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTeamSuggestions() async {
    final names = await DatabaseHelper.instance.fetchDistinctTeamNames();
    if (mounted) setState(() => _teamSuggestions = names);
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 500,
      maxHeight: 500,
      imageQuality: 50,
    );
    if (picked != null && mounted) {
      setState(() => _avatarPath = picked.path);
    }
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    final team = _teamCtrl.text.trim();
    if (name.isEmpty || team.isEmpty) return;

    setState(() => _saving = true);

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final c = Theme.of(context).appColors;

    String? resolvedAvatarPath = _avatarPath;
    final isNewLocalFile = _avatarPath != null &&
        _avatarPath != widget.initialAvatarPath &&
        !(_avatarPath!.startsWith('http://') ||
          _avatarPath!.startsWith('https://'));

    if (isNewLocalFile) {
      try {
        final supabase = Supabase.instance.client;
        final userId   = AuthService.instance.userId ?? 'anon';
        final fileName = '${userId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final fileBytes = await File(_avatarPath!).readAsBytes();

        await supabase.storage.from('avatars').uploadBinary(
          fileName,
          fileBytes,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: true,
          ),
        );

        final publicUrl = supabase.storage
            .from('avatars')
            .getPublicUrl(fileName);

        resolvedAvatarPath = publicUrl;
      } catch (e) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Image upload failed — player saved without avatar.',
              style: GoogleFonts.rajdhani(fontSize: 14),
            ),
            backgroundColor: c.liveRed,
          ),
        );
      }
    }

    navigator.pop();

    await Future.delayed(const Duration(milliseconds: 100), () async {
      await widget.onSave(
        name,
        team,
        _selectedRole,
        _showBowlingType ? _selectedBowlingType : null,
        resolvedAvatarPath,
      );
    });
  }

  // ── Shared InputDecoration ─────────────────────────────────────────────────

  InputDecoration _inputDec(AppColors c, String label, {String? hint, IconData? icon}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: GoogleFonts.rajdhani(
          color: c.textSecondary, fontWeight: FontWeight.w600, fontSize: 14),
      hintStyle: GoogleFonts.rajdhani(color: c.textSecondary, fontSize: 15),
      prefixIcon: icon != null
          ? Icon(icon, color: c.textSecondary, size: 20)
          : null,
      filled: true,
      fillColor: c.card2,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: c.border, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: c.neon, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: c.liveRed, width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: c.liveRed, width: 2),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).appColors;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: c.textSecondary.withAlpha(80),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Title
          Text(
            widget.initialName == null ? 'Add Player' : 'Edit Player',
            style: GoogleFonts.rajdhani(
                fontSize: 24, fontWeight: FontWeight.w900, color: c.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            widget.initialName == null
                ? 'Fill in the details below to register a new player.'
                : 'Update the player details below.',
            style: GoogleFonts.rajdhani(fontSize: 13, color: c.textSecondary),
          ),
          const SizedBox(height: 24),

          // Avatar picker
          Center(child: _buildAvatarPicker(c)),
          const SizedBox(height: 24),

          // ── Name ────────────────────────────────────────────────────────────
          TextField(
            controller: _nameCtrl,
            textCapitalization: TextCapitalization.words,
            style: GoogleFonts.rajdhani(
                color: c.textPrimary, fontSize: 16, fontWeight: FontWeight.w600),
            decoration: _inputDec(c, 'Player Name',
                hint: 'e.g. Babar Azam', icon: Icons.person_outline),
          ),
          const SizedBox(height: 14),

          // ── Team (with autocomplete) ────────────────────────────────────────
          _buildTeamAutocomplete(c),
          const SizedBox(height: 14),

          // ── Role ────────────────────────────────────────────────────────────
          _buildRoleDropdown(c),
          const SizedBox(height: 14),

          // ── Bowling Type (conditional) ──────────────────────────────────────
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 220),
            crossFadeState: _showBowlingType
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildBowlingTypeSelector(c),
                const SizedBox(height: 14),
              ],
            ),
            secondChild: const SizedBox.shrink(),
          ),

          // ── Save button ──────────────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: _saving ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: c.accent,
                foregroundColor: Colors.white,
                disabledBackgroundColor: c.accent.withAlpha(80),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 4,
                shadowColor: c.accent.withAlpha(80),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 22, height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      widget.initialName == null ? 'Add Player' : 'Save Changes',
                      style: GoogleFonts.rajdhani(
                          fontSize: 18, fontWeight: FontWeight.w800,
                          letterSpacing: 0.5),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Avatar ────────────────────────────────────────────────────────────────

  Widget _buildAvatarPicker(AppColors c) {
    return GestureDetector(
      onTap: _pickImage,
      child: Stack(
        alignment: Alignment.bottomRight,
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: c.accent.withAlpha(80), width: 2),
            ),
            child: CircleAvatar(
              radius: 46,
              backgroundColor: c.card2,
              backgroundImage: (_avatarPath != null && _avatarPath!.isNotEmpty)
                  ? (_avatarPath!.startsWith('http://') || _avatarPath!.startsWith('https://'))
                      ? CachedNetworkImageProvider(_avatarPath!) as ImageProvider
                      : FileImage(File(_avatarPath!))
                  : null,
              child: (_avatarPath == null || _avatarPath!.isEmpty)
                  ? Icon(Icons.person, size: 46, color: c.accent)
                  : null,
            ),
          ),
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: c.accent,
              shape: BoxShape.circle,
              border: Border.all(color: c.card, width: 2),
            ),
            child: const Icon(Icons.camera_alt, size: 14, color: Colors.white),
          ),
        ],
      ),
    );
  }

  // ── Team autocomplete ─────────────────────────────────────────────────────

  Widget _buildTeamAutocomplete(AppColors c) {
    return Autocomplete<String>(
      initialValue: TextEditingValue(text: widget.initialTeam ?? ''),
      optionsBuilder: (TextEditingValue value) {
        if (value.text.isEmpty) return const [];
        final query = value.text.toLowerCase();
        return _teamSuggestions
            .where((t) => t.toLowerCase().contains(query))
            .take(5);
      },
      onSelected: (String selection) {
        _teamCtrl.text = selection;
      },
      fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
        controller.addListener(() {
          if (_teamCtrl.text != controller.text) {
            _teamCtrl.text = controller.text;
          }
        });
        return TextField(
          controller: controller,
          focusNode: focusNode,
          textCapitalization: TextCapitalization.words,
          style: GoogleFonts.rajdhani(
              color: c.textPrimary, fontSize: 16, fontWeight: FontWeight.w600),
          decoration: _inputDec(c, 'Team',
              hint: 'e.g. Karachi Kings', icon: Icons.shield_outlined),
          onSubmitted: (_) => onSubmitted(),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            color: c.card2,
            borderRadius: BorderRadius.circular(12),
            elevation: 10,
            shadowColor: Colors.black54,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (_, i) {
                  final opt = options.elementAt(i);
                  return InkWell(
                    onTap: () => onSelected(opt),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 13),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: c.border,
                            width: i < options.length - 1 ? 1 : 0,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.shield_outlined,
                              size: 15, color: c.accent),
                          const SizedBox(width: 10),
                          Text(
                            opt,
                            style: GoogleFonts.rajdhani(
                                fontSize: 15, fontWeight: FontWeight.w600,
                                color: c.textPrimary),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Role dropdown ─────────────────────────────────────────────────────────

  Widget _buildRoleDropdown(AppColors c) {
    return Container(
      decoration: BoxDecoration(
        color: c.card2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: _selectedRole,
          hint: Row(
            children: [
              Icon(Icons.sports_cricket_outlined,
                  color: c.textSecondary, size: 20),
              const SizedBox(width: 12),
              Text(
                'Role (optional)',
                style: GoogleFonts.rajdhani(
                    color: c.textSecondary, fontSize: 15,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
          dropdownColor: c.card2,
          isExpanded: true,
          icon: Icon(Icons.keyboard_arrow_down, color: c.textSecondary),
          style: GoogleFonts.rajdhani(
              color: c.textPrimary, fontSize: 15, fontWeight: FontWeight.w600),
          items: [
            DropdownMenuItem<String?>(
              value: null,
              child: Row(
                children: [
                  Icon(Icons.remove_circle_outline,
                      color: c.textSecondary, size: 18),
                  const SizedBox(width: 12),
                  Text('No role',
                      style: GoogleFonts.rajdhani(color: c.textSecondary)),
                ],
              ),
            ),
            ..._roleOptions.map(
              (r) => DropdownMenuItem<String?>(
                value: r,
                child: Row(
                  children: [
                    Icon(_roleIcon(r), color: c.accent, size: 18),
                    const SizedBox(width: 12),
                    Text(r),
                  ],
                ),
              ),
            ),
          ],
          onChanged: (val) => setState(() {
            _selectedRole = val;
            if (!_roleHasBowlingType(val)) _selectedBowlingType = null;
          }),
        ),
      ),
    );
  }

  // ── Bowling Type segmented selector ──────────────────────────────────────

  Widget _buildBowlingTypeSelector(AppColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            'BOWLING TYPE',
            style: GoogleFonts.rajdhani(
                fontSize: 11, fontWeight: FontWeight.w700,
                color: c.textSecondary, letterSpacing: 2.5),
          ),
        ),
        Row(
          children: _bowlingTypes.map((type) {
            final isFast     = type == 'Fast';
            final isSelected = _selectedBowlingType == type;
            final activeColor = isFast ? _colorFast : _colorSpin;
            return Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _selectedBowlingType = type),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: EdgeInsets.only(right: isFast ? 8 : 0),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? activeColor.withAlpha(35)
                        : c.card2,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected ? activeColor : c.border,
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        isFast ? Icons.bolt : Icons.rotate_90_degrees_cw,
                        size: 22,
                        color: isSelected ? activeColor : c.textSecondary,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        type,
                        style: GoogleFonts.rajdhani(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: isSelected ? activeColor : c.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isFast ? 'Pace bowler' : 'Spin bowler',
                        style: GoogleFonts.rajdhani(
                            fontSize: 11, color: c.textSecondary),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  IconData _roleIcon(String role) {
    switch (role) {
      case 'bowler':          return Icons.sports_cricket;
      case 'all-rounder':     return Icons.swap_horiz;
      case 'wicket-keeper':   return Icons.back_hand_outlined;
      default:                return Icons.sports_baseball;
    }
  }
}
