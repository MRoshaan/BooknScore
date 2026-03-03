import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../services/database_helper.dart';
import '../services/auth_service.dart';

// ── Brand Palette ─────────────────────────────────────────────────────────────
const Color _primaryGreen  = Color(0xFF1B5E20);
const Color _accentGreen   = Color(0xFF4CAF50);
const Color _surfaceDark   = Color(0xFF0A0A0A);
const Color _glassBg       = Color(0x1A4CAF50);
const Color _glassBorder   = Color(0x334CAF50);
const Color _textPrimary   = Colors.white;
const Color _textSecondary = Color(0xFFB0B0B0);

const List<String> _roleOptions = ['batter', 'bowler', 'all-rounder', 'wicket-keeper'];

/// Screen for browsing and managing the global players registry.
class PlayersScreen extends StatefulWidget {
  const PlayersScreen({super.key});

  @override
  State<PlayersScreen> createState() => _PlayersScreenState();
}

class _PlayersScreenState extends State<PlayersScreen> {
  List<Map<String, dynamic>> _players = [];
  bool _loading = true;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

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
    _loadPlayers();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadPlayers() async {
    setState(() => _loading = true);
    try {
      final players = await DatabaseHelper.instance.fetchAllPlayers();
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
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Delete Player',
          style: GoogleFonts.rajdhani(
            fontWeight: FontWeight.w700,
            color: _textPrimary,
          ),
        ),
        content: Text(
          'Remove "$name" from the global roster?',
          style: GoogleFonts.rajdhani(color: _textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: GoogleFonts.rajdhani(
                fontWeight: FontWeight.w600,
                color: _textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _deletePlayer(player[DatabaseHelper.colId] as int);
            },
            child: Text(
              'Delete',
              style: GoogleFonts.rajdhani(
                fontWeight: FontWeight.w700,
                color: Colors.redAccent,
              ),
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
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _PlayerFormSheet(
        onSave: (name, team, role, localAvatarPath) async {
          final createdBy = AuthService.instance.currentUser?.id;
          await DatabaseHelper.instance.insertPlayer(
            name: name,
            team: team,
            role: role,
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
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _PlayerFormSheet(
        initialName: player[DatabaseHelper.colName] as String,
        initialTeam: player[DatabaseHelper.colTeam] as String,
        initialRole: player[DatabaseHelper.colRole] as String?,
        initialAvatarPath: player[DatabaseHelper.colLocalAvatarPath] as String?,
        onSave: (name, team, role, localAvatarPath) async {
          await DatabaseHelper.instance.updatePlayer(
            player[DatabaseHelper.colId] as int,
            name: name,
            team: team,
            role: role,
            localAvatarPath: localAvatarPath,
          );
          await _loadPlayers();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surfaceDark,
      body: CustomScrollView(
        slivers: [
          _buildAppBar(),
          SliverToBoxAdapter(child: _buildSearchBar()),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            sliver: _loading
                ? const SliverFillRemaining(
                    child: Center(
                      child: CircularProgressIndicator(color: _accentGreen),
                    ),
                  )
                : (_players.isEmpty && _searchQuery.isEmpty)
                    ? _buildEmptyState()
                    : _buildPlayerList(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddPlayerDialog,
        backgroundColor: _accentGreen,
        foregroundColor: Colors.white,
        tooltip: 'Add Player',
        child: const Icon(Icons.person_add),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: TextField(
        controller: _searchController,
        style: GoogleFonts.rajdhani(
          fontSize: 16,
          color: _textPrimary,
        ),
        decoration: InputDecoration(
          hintText: 'Search players...',
          hintStyle: GoogleFonts.rajdhani(
            fontSize: 16,
            color: _textSecondary,
          ),
          prefixIcon: const Icon(Icons.search, color: _accentGreen),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, color: _textSecondary, size: 20),
                  onPressed: () {
                    _searchController.clear();
                  },
                )
              : null,
          filled: true,
          fillColor: _glassBg,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _glassBorder, width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _accentGreen, width: 1.5),
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return SliverAppBar(
      expandedHeight: 120,
      floating: false,
      pinned: true,
      backgroundColor: _primaryGreen,
      automaticallyImplyLeading: false,
      flexibleSpace: FlexibleSpaceBar(
        centerTitle: true,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Players',
              style: GoogleFonts.rajdhani(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: _textPrimary,
                letterSpacing: 2,
              ),
            ),
            Text(
              'GLOBAL ROSTER',
              style: GoogleFonts.rajdhani(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: _accentGreen,
                letterSpacing: 3,
              ),
            ),
          ],
        ),
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_primaryGreen, Color(0xFF0D3318)],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    if (_searchQuery.isNotEmpty) {
      return SliverFillRemaining(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.search_off, size: 80, color: _accentGreen.withAlpha(120)),
              const SizedBox(height: 24),
              Text(
                'No Results Found',
                style: GoogleFonts.rajdhani(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: _textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'No players match "$_searchQuery".',
                style: GoogleFonts.rajdhani(fontSize: 16, color: _textSecondary),
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
            Icon(Icons.people_outline, size: 80, color: _accentGreen.withAlpha(120)),
            const SizedBox(height: 24),
            Text(
              'No Players Yet',
              style: GoogleFonts.rajdhani(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: _textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap + to add your first player.',
              style: GoogleFonts.rajdhani(fontSize: 16, color: _textSecondary),
            ),
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayerList() {
    final players = _filteredPlayers;
    if (players.isEmpty) {
      return _buildEmptyState();
    }
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          if (index == players.length) return const SizedBox(height: 100);
          return _buildPlayerCard(players[index]);
        },
        childCount: players.length + 1,
      ),
    );
  }

  Widget _buildPlayerCard(Map<String, dynamic> player) {
    final name = player[DatabaseHelper.colName] as String;
    final team = player[DatabaseHelper.colTeam] as String;
    final role = player[DatabaseHelper.colRole] as String?;
    final avatarPath = player[DatabaseHelper.colLocalAvatarPath] as String?;

    // Build the leading avatar widget
    final Widget avatarWidget = CircleAvatar(
      radius: 24,
      backgroundColor: _accentGreen.withAlpha(40),
      backgroundImage: (avatarPath != null && avatarPath.isNotEmpty)
          ? FileImage(File(avatarPath))
          : null,
      child: (avatarPath == null || avatarPath.isEmpty)
          ? Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: GoogleFonts.rajdhani(
                fontWeight: FontWeight.w800,
                color: _accentGreen,
                fontSize: 18,
              ),
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
              color: _glassBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _glassBorder, width: 1),
            ),
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: avatarWidget,
              title: Text(
                name,
                style: GoogleFonts.rajdhani(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: _textPrimary,
                ),
              ),
              subtitle: Row(
                children: [
                  Text(
                    team,
                    style: GoogleFonts.rajdhani(
                      fontSize: 13,
                      color: _textSecondary,
                    ),
                  ),
                  if (role != null && role.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    _buildRoleBadge(role),
                  ],
                ],
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined,
                        color: _accentGreen, size: 20),
                    onPressed: () => _showEditPlayerDialog(player),
                    tooltip: 'Edit',
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline,
                        color: Colors.redAccent, size: 20),
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

  Widget _buildRoleBadge(String role) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: _accentGreen.withAlpha(30),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _accentGreen.withAlpha(80), width: 1),
      ),
      child: Text(
        role,
        style: GoogleFonts.rajdhani(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: _accentGreen,
          letterSpacing: 0.5,
        ),
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
  final String? initialAvatarPath;
  final Future<void> Function(
    String name,
    String team,
    String? role,
    String? localAvatarPath,
  ) onSave;

  const _PlayerFormSheet({
    this.initialName,
    this.initialTeam,
    this.initialRole,
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
  String? _avatarPath;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl     = TextEditingController(text: widget.initialName ?? '');
    _teamCtrl     = TextEditingController(text: widget.initialTeam ?? '');
    _selectedRole = widget.initialRole;
    _avatarPath   = widget.initialAvatarPath;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _teamCtrl.dispose();
    super.dispose();
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

    if (context.mounted) Navigator.pop(context);

    await Future.delayed(const Duration(milliseconds: 100), () async {
      await widget.onSave(name, team, _selectedRole, _avatarPath);
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: _textSecondary.withAlpha(80),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          Text(
            widget.initialName == null ? 'Add Player' : 'Edit Player',
            style: GoogleFonts.rajdhani(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: _textPrimary,
            ),
          ),
          const SizedBox(height: 20),

          // Avatar picker
          Center(child: _buildAvatarPicker()),
          const SizedBox(height: 20),

          // Name field
          _buildTextField(_nameCtrl, 'Player Name', Icons.person_outline),
          const SizedBox(height: 14),

          // Team field
          _buildTextField(_teamCtrl, 'Team', Icons.group_outlined),
          const SizedBox(height: 14),

          // Role dropdown
          _buildRoleDropdown(),
          const SizedBox(height: 24),

          // Save button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _saving ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: _accentGreen,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                widget.initialName == null ? 'Add Player' : 'Save Changes',
                style: GoogleFonts.rajdhani(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatarPicker() {
    return GestureDetector(
      onTap: _pickImage,
      child: Stack(
        alignment: Alignment.bottomRight,
        children: [
          CircleAvatar(
            radius: 44,
            backgroundColor: _accentGreen.withAlpha(40),
            backgroundImage: (_avatarPath != null && _avatarPath!.isNotEmpty)
                ? FileImage(File(_avatarPath!))
                : null,
            child: (_avatarPath == null || _avatarPath!.isEmpty)
                ? const Icon(Icons.person, size: 44, color: _accentGreen)
                : null,
          ),
          Container(
            padding: const EdgeInsets.all(6),
            decoration: const BoxDecoration(
              color: _accentGreen,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.camera_alt, size: 16, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(
      TextEditingController ctrl, String hint, IconData icon) {
    return TextField(
      controller: ctrl,
      style: GoogleFonts.rajdhani(color: _textPrimary, fontSize: 16),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.rajdhani(color: _textSecondary),
        prefixIcon: Icon(icon, color: _textSecondary, size: 20),
        filled: true,
        fillColor: const Color(0xFF242424),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _accentGreen, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      ),
    );
  }

  Widget _buildRoleDropdown() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF242424),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: _selectedRole,
          hint: Row(
            children: [
              const Icon(Icons.sports_cricket_outlined,
                  color: _textSecondary, size: 20),
              const SizedBox(width: 12),
              Text(
                'Role (optional)',
                style: GoogleFonts.rajdhani(color: _textSecondary, fontSize: 16),
              ),
            ],
          ),
          dropdownColor: const Color(0xFF242424),
          isExpanded: true,
          icon: const Icon(Icons.arrow_drop_down, color: _textSecondary),
          style: GoogleFonts.rajdhani(color: _textPrimary, fontSize: 16),
          items: [
            DropdownMenuItem<String?>(
              value: null,
              child: Text(
                'No role',
                style: GoogleFonts.rajdhani(color: _textSecondary),
              ),
            ),
            ..._roleOptions.map(
              (r) => DropdownMenuItem<String?>(
                value: r,
                child: Text(r),
              ),
            ),
          ],
          onChanged: (val) => setState(() => _selectedRole = val),
        ),
      ),
    );
  }
}
