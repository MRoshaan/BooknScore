import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/auth_service.dart';
import '../services/database_helper.dart';
import '../services/sync_service.dart';

// ── Brand Palette ─────────────────────────────────────────────────────────────
const Color _ctSurface       = Color(0xFF0A0A0A);
const Color _ctCard          = Color(0xFF141414);
const Color _ctAccent        = Color(0xFF39FF14);
const Color _ctAccentMid     = Color(0xFF4CAF50);
const Color _ctGlassBorder   = Color(0x3239FF14);
const Color _ctTextPrimary   = Colors.white;
const Color _ctTextSecondary = Color(0xFF8A8A8A);
// ─────────────────────────────────────────────────────────────────────────────

/// Two-step screen for creating a new team:
///
///   Step 1 – Team name input.
///   Step 2 – Roster builder: multi-select players from a searchable list,
///             display them as dismissible chips, and optionally add new players
///             inline.
///
/// On save:
///   1. Inserts a new row into the `teams` table.
///   2. Updates each selected player's `team` column to the new team name.
///   3. Schedules a debounced sync.
class CreateTeamScreen extends StatefulWidget {
  const CreateTeamScreen({super.key});

  @override
  State<CreateTeamScreen> createState() => _CreateTeamScreenState();
}

class _CreateTeamScreenState extends State<CreateTeamScreen> {
  final _formKey        = GlobalKey<FormState>();
  final _nameCtrl       = TextEditingController();
  final _searchCtrl     = TextEditingController();
  final _searchFocus    = FocusNode();

  int _step = 1; // 1 = name, 2 = roster

  List<Map<String, dynamic>> _allPlayers    = [];
  List<Map<String, dynamic>> _selectedPlayers = [];
  List<Map<String, dynamic>> _suggestions   = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadPlayers();
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // ── Data loading ──────────────────────────────────────────────────────────

  Future<void> _loadPlayers() async {
    final userId  = AuthService.instance.userId;
    final players = await DatabaseHelper.instance.fetchPlayersForUser(userId);
    if (mounted) setState(() => _allPlayers = players);
  }

  void _onSearchChanged() {
    final query = _searchCtrl.text.trim().toLowerCase();
    if (query.isEmpty) {
      setState(() => _suggestions = []);
      return;
    }
    final selectedIds =
        _selectedPlayers.map((p) => p[DatabaseHelper.colId]).toSet();
    setState(() {
      _suggestions = _allPlayers
          .where((p) =>
              !selectedIds.contains(p[DatabaseHelper.colId]) &&
              (p[DatabaseHelper.colName] as String)
                  .toLowerCase()
                  .contains(query))
          .toList();
    });
  }

  // ── Player selection helpers ──────────────────────────────────────────────

  void _selectPlayer(Map<String, dynamic> player) {
    setState(() {
      _selectedPlayers.add(player);
      _searchCtrl.clear();
      _suggestions = [];
    });
    _searchFocus.unfocus();
  }

  void _removePlayer(Map<String, dynamic> player) {
    setState(() => _selectedPlayers.remove(player));
  }

  // ── New-player inline dialog ──────────────────────────────────────────────

  Future<void> _showAddPlayerDialog() async {
    final nameCtrl = TextEditingController();
    final formKey  = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text(
          'New Player',
          style: GoogleFonts.rajdhani(
            color: _ctTextPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: nameCtrl,
            autofocus: true,
            style: GoogleFonts.rajdhani(color: _ctTextPrimary),
            decoration: InputDecoration(
              hintText: 'Player name',
              hintStyle: GoogleFonts.rajdhani(color: _ctTextSecondary),
              enabledBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: _ctGlassBorder),
              ),
              focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: _ctAccent),
              ),
            ),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: GoogleFonts.rajdhani(color: _ctTextSecondary)),
          ),
          TextButton(
            onPressed: () {
              if (formKey.currentState?.validate() == true) {
                Navigator.pop(ctx, true);
              }
            },
            child: Text('Add',
                style: GoogleFonts.rajdhani(
                    color: _ctAccent, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirmed == true && nameCtrl.text.trim().isNotEmpty) {
      final teamName = _nameCtrl.text.trim();
      final userId   = AuthService.instance.userId;
      final newId    = await DatabaseHelper.instance.insertPlayer(
        name:      nameCtrl.text.trim(),
        team:      teamName.isNotEmpty ? teamName : 'Unassigned',
        createdBy: userId,
      );
      final newPlayer = await DatabaseHelper.instance.fetchPlayer(newId);
      if (newPlayer != null && mounted) {
        setState(() => _selectedPlayers.add(newPlayer));
        // Re-load master list so the new player appears in future searches.
        await _loadPlayers();
      }
    }
  }

  // ── Save ──────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    // Step A: validate name directly from the controller — the Form widget
    // from Step 1 is no longer in the tree at this point so _formKey.currentState
    // is null and cannot be used here.
    final teamName = _nameCtrl.text.trim();
    if (teamName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please enter a team name first.',
            style: GoogleFonts.rajdhani(fontWeight: FontWeight.w600),
          ),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      // Step B/C: create team row and capture the new SQLite id.
      final userId = AuthService.instance.userId;
      final teamId = await DatabaseHelper.instance.insertTeam(
        name:      teamName,
        createdBy: userId,
      );

      // Step D: update each selected player's team_id FK and legacy team TEXT.
      for (final player in _selectedPlayers) {
        final id = player[DatabaseHelper.colId] as int;
        await DatabaseHelper.instance.updatePlayerTeamId(id, teamId, teamName);
      }

      // Trigger background sync.
      SyncService.instance.scheduleDebouncedSync();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Team Saved!',
            style: GoogleFonts.rajdhani(fontWeight: FontWeight.w600),
          ),
          backgroundColor: const Color(0xFF1B5E20),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          duration: const Duration(seconds: 2),
        ),
      );
      Navigator.pop(context, true);
    } catch (e, st) {
      print('CreateTeamScreen._save error: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to save team: $e',
              style: GoogleFonts.rajdhani(fontWeight: FontWeight.w600),
            ),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _ctSurface,
      body: CustomScrollView(
        slivers: [
          _buildAppBar(),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
            sliver: SliverToBoxAdapter(
              child: _step == 1 ? _buildStep1() : _buildStep2(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar() {
    return SliverAppBar(
      expandedHeight: 120,
      floating: false,
      pinned: true,
      backgroundColor: _ctSurface,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new,
            color: _ctTextPrimary, size: 18),
        onPressed: () {
          if (_step == 2) {
            setState(() => _step = 1);
          } else {
            Navigator.pop(context);
          }
        },
      ),
      flexibleSpace: FlexibleSpaceBar(
        centerTitle: true,
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0F1F0F), Color(0xFF0A0A0A)],
            ),
          ),
        ),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Create Team',
              style: GoogleFonts.rajdhani(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: _ctTextPrimary,
                letterSpacing: 1.5,
              ),
            ),
            Text(
              'STEP $_step OF 2',
              style: GoogleFonts.rajdhani(
                fontSize: 8,
                fontWeight: FontWeight.w700,
                color: _ctAccent,
                letterSpacing: 3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Step 1: Team name ─────────────────────────────────────────────────────

  Widget _buildStep1() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionLabel('TEAM NAME'),
          const SizedBox(height: 12),
          _glassCard(
            child: TextFormField(
              controller: _nameCtrl,
              autofocus: true,
              style: GoogleFonts.rajdhani(
                  color: _ctTextPrimary, fontSize: 18),
              decoration: InputDecoration(
                hintText: 'e.g. Karachi Kings',
                hintStyle:
                    GoogleFonts.rajdhani(color: _ctTextSecondary),
                border: InputBorder.none,
                prefixIcon: const Icon(Icons.shield_outlined,
                    color: _ctAccentMid, size: 20),
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Team name cannot be empty'
                  : null,
              onFieldSubmitted: (_) => _goToStep2(),
            ),
          ),
          const SizedBox(height: 32),
          _primaryButton(
            label: 'Next: Build Roster',
            icon: Icons.arrow_forward,
            onPressed: () async => _goToStep2(),
          ),
        ],
      ),
    );
  }

  void _goToStep2() {
    if (_formKey.currentState?.validate() == true) {
      setState(() => _step = 2);
    }
  }

  // ── Step 2: Roster builder ────────────────────────────────────────────────

  Widget _buildStep2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Team name banner
        _glassCard(
          child: Row(
            children: [
              const Icon(Icons.shield_outlined,
                  color: _ctAccentMid, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _nameCtrl.text.trim(),
                  style: GoogleFonts.rajdhani(
                    color: _ctTextPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Search row
        _sectionLabel('ADD PLAYERS'),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _glassCard(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: TextField(
                  controller: _searchCtrl,
                  focusNode: _searchFocus,
                  style: GoogleFonts.rajdhani(
                      color: _ctTextPrimary, fontSize: 15),
                  decoration: InputDecoration(
                    hintText: 'Search players…',
                    hintStyle:
                        GoogleFonts.rajdhani(color: _ctTextSecondary),
                    border: InputBorder.none,
                    prefixIcon: const Icon(Icons.search,
                        color: _ctTextSecondary, size: 18),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // + New Player button
            GestureDetector(
              onTap: _showAddPlayerDialog,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                  child: Container(
                    width: 48,
                    height: 52,
                    decoration: BoxDecoration(
                      color: _ctAccent.withAlpha(20),
                      borderRadius: BorderRadius.circular(12),
                      border:
                          Border.all(color: _ctAccent.withAlpha(80), width: 1),
                    ),
                    child: const Icon(Icons.person_add_outlined,
                        color: _ctAccent, size: 22),
                  ),
                ),
              ),
            ),
          ],
        ),

        // Suggestions dropdown
        if (_suggestions.isNotEmpty) ...[
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1C1C1C).withAlpha(230),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _ctGlassBorder, width: 1),
                ),
                child: Column(
                  children: _suggestions.map((p) {
                    final name =
                        p[DatabaseHelper.colName] as String? ?? '';
                    final team =
                        p[DatabaseHelper.colTeam] as String? ?? '';
                    return ListTile(
                      dense: true,
                      title: Text(
                        name,
                        style: GoogleFonts.rajdhani(
                            color: _ctTextPrimary,
                            fontWeight: FontWeight.w600),
                      ),
                      subtitle: team.isNotEmpty
                          ? Text(
                              team,
                              style: GoogleFonts.rajdhani(
                                  color: _ctTextSecondary,
                                  fontSize: 11),
                            )
                          : null,
                      trailing: const Icon(Icons.add_circle_outline,
                          color: _ctAccentMid, size: 18),
                      onTap: () => _selectPlayer(p),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        ],

        const SizedBox(height: 20),

        // Selected players chips
        if (_selectedPlayers.isNotEmpty) ...[
          _sectionLabel('SELECTED (${_selectedPlayers.length})'),
          const SizedBox(height: 10),
          _glassCard(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _selectedPlayers.map((p) {
                final name =
                    p[DatabaseHelper.colName] as String? ?? '';
                return Chip(
                  label: Text(
                    name,
                    style: GoogleFonts.rajdhani(
                      color: _ctTextPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  backgroundColor: _ctAccent.withAlpha(18),
                  side: BorderSide(
                      color: _ctAccent.withAlpha(80), width: 1),
                  deleteIcon: const Icon(Icons.close,
                      size: 14, color: _ctTextSecondary),
                  onDeleted: () => _removePlayer(p),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 32),
        ] else ...[
          const SizedBox(height: 16),
          Center(
            child: Text(
              'No players selected yet',
              style: GoogleFonts.rajdhani(
                  color: _ctTextSecondary, fontSize: 13),
            ),
          ),
          const SizedBox(height: 32),
        ],

        // Save button
        _saving
            ? const Center(
                child: CircularProgressIndicator(color: _ctAccent))
            : _primaryButton(
                label: 'Save Team',
                icon: Icons.check,
                onPressed: _save,
              ),
      ],
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: GoogleFonts.rajdhani(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: _ctAccent,
        letterSpacing: 2.5,
      ),
    );
  }

  Widget _glassCard({
    required Widget child,
    EdgeInsets padding =
        const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: _ctCard.withAlpha(220),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _ctGlassBorder, width: 1),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _primaryButton({
    required String label,
    required IconData icon,
    required Future<void> Function() onPressed,
  }) {
    return GestureDetector(
      onTap: () async => onPressed(),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF39FF14), Color(0xFF4CAF50)],
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: _ctAccent.withAlpha(60),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.black, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.rajdhani(
                color: Colors.black,
                fontWeight: FontWeight.w900,
                fontSize: 16,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
