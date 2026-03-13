import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/database_helper.dart';
import '../services/auth_service.dart';
import 'scoring_screen.dart';

// ── Brand Palette ────────────────────────────────────────────────────────────
const Color _primaryGreen  = Color(0xFF1B5E20);
const Color _accentGreen   = Color(0xFF4CAF50);
const Color _surfaceDark   = Color(0xFF0A0A0A);
const Color _surfaceCard   = Color(0xFF1A1A1A);
const Color _inputFill     = Color(0xFF1E1E1E);
const Color _glassBg       = Color(0x1A4CAF50);
const Color _glassBorder   = Color(0x334CAF50);
const Color _hintColor     = Color(0xFF757575);
const Color _textPrimary   = Colors.white;

class NewMatchScreen extends StatefulWidget {
  /// If [tournamentId] is provided the match is linked to that tournament.
  ///
  /// [tournamentFormat] should be one of `'league'`, `'knockout'`, or
  /// `'mixed'`.  When it is `'knockout'` the match-stage dropdown is hidden
  /// and the stage is computed automatically from the number of active
  /// (non-eliminated) teams remaining in the tournament.
  const NewMatchScreen({
    super.key,
    this.tournamentId,
    this.tournamentFormat,
  });

  final int?    tournamentId;
  final String? tournamentFormat;

  @override
  State<NewMatchScreen> createState() => _NewMatchScreenState();
}

class _NewMatchScreenState extends State<NewMatchScreen> {
  final _formKey = GlobalKey<FormState>();
  final _teamACtrl = TextEditingController();
  final _teamBCtrl = TextEditingController();
  final _oversCtrl = TextEditingController(text: '20');

  String? _tossWinner;  // 'team_a' or 'team_b'
  String? _optTo;       // 'bat' or 'bowl'
  String? _matchStage;  // 'Group Stage' | 'Quarter-Final' | 'Semi-Final' | 'Final'
  bool _saving = false;

  // ── Tournament-team dropdown state ─────────────────────────────────────────
  /// Teams registered to the selected tournament (empty until loaded).
  List<String> _tournamentTeams = [];
  bool _teamsLoading = false;

  /// Selected values for the dropdowns (only used when tournamentId != null).
  String? _selectedTeamA;
  String? _selectedTeamB;

  static const _stageOptions = [
    'Group Stage',
    'Quarter-Final',
    'Semi-Final',
    'Final',
  ];

  // ── Derived helpers ────────────────────────────────────────────────────────

  /// The effective Team A name regardless of input mode.
  String get _effectiveTeamA =>
      widget.tournamentId != null ? (_selectedTeamA ?? '') : _teamACtrl.text.trim();

  /// The effective Team B name regardless of input mode.
  String get _effectiveTeamB =>
      widget.tournamentId != null ? (_selectedTeamB ?? '') : _teamBCtrl.text.trim();

  @override
  void initState() {
    super.initState();
    // Load registered teams if we are in tournament mode
    if (widget.tournamentId != null) {
      _loadTournamentTeams();
    }
  }

  @override
  void dispose() {
    _teamACtrl.dispose();
    _teamBCtrl.dispose();
    _oversCtrl.dispose();
    super.dispose();
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  bool get _isKnockout =>
      widget.tournamentFormat?.toLowerCase() == 'knockout';

  /// Derive the stage label from the number of active teams still in the
  /// knockout tournament.
  static String _stageForTeamCount(int activeCount) {
    if (activeCount <= 2) return 'Final';
    if (activeCount <= 4) return 'Semi-Final';
    if (activeCount <= 8) return 'Quarter-Final';
    return 'Group Stage';
  }

  // ── Load tournament teams ──────────────────────────────────────────────────

  Future<void> _loadTournamentTeams() async {
    if (widget.tournamentId == null) return;
    setState(() => _teamsLoading = true);
    try {
      final db = DatabaseHelper.instance;
      final teams = await db.fetchActiveTeams(widget.tournamentId!);
      if (mounted) {
        setState(() {
          _tournamentTeams = teams;
          // Auto-set stage for knockout tournaments based on remaining teams
          if (_isKnockout) {
            _matchStage = _stageForTeamCount(teams.length);
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not load tournament teams: $e',
              style: GoogleFonts.rajdhani(fontWeight: FontWeight.w600),
            ),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _teamsLoading = false);
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  InputDecoration _inputDecoration(String label, {String? hint, IconData? icon}) {
    return InputDecoration(
      labelText: label,
      hintText:  hint,
      prefixIcon: icon != null ? Icon(icon, color: _hintColor, size: 20) : null,
      labelStyle: GoogleFonts.rajdhani(color: _hintColor, fontWeight: FontWeight.w600),
      hintStyle:  GoogleFonts.rajdhani(color: _hintColor),
      filled:     true,
      fillColor:  _inputFill,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF2A2A2A)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _accentGreen, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.redAccent, width: 2),
      ),
    );
  }

  // ── Submit ─────────────────────────────────────────────────────────────────

  Future<void> _startMatch() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    try {
      final db = DatabaseHelper.instance;
      final userId = AuthService.instance.currentUser?.id;
      
      // Determine actual toss winner name
      String? tossWinnerName;
      if (_tossWinner == 'team_a') {
        tossWinnerName = _effectiveTeamA;
      } else if (_tossWinner == 'team_b') {
        tossWinnerName = _effectiveTeamB;
      }

      // For quick matches, ensure both team names exist in the teams table
      // (find-or-create) so we can store proper FK references on the match row.
      int? teamAId;
      int? teamBId;
      if (widget.tournamentId == null) {
        teamAId = await db.ensureTeamExists(
          _effectiveTeamA,
          createdBy: userId,
        );
        teamBId = await db.ensureTeamExists(
          _effectiveTeamB,
          createdBy: userId,
        );
      }

      // Create match - NO players pre-selected, enter as you go
      final matchId = await db.insertMatch(
        teamA:        _effectiveTeamA,
        teamB:        _effectiveTeamB,
        totalOvers:   int.parse(_oversCtrl.text.trim()),
        tossWinner:   tossWinnerName,
        optTo:        _optTo,
        createdBy:    userId,
        tournamentId: widget.tournamentId,
        matchStage:   widget.tournamentId != null ? _matchStage : null,
        teamAId:      teamAId,
        teamBId:      teamBId,
      );

      if (!mounted) return;

      // Navigate to scoring screen — ScoringScreen.initState() calls loadMatch()
      // exclusively.  Do NOT call loadMatch() here first; doing so causes a
      // double-load race condition that doubles the score on resume.
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ScoringScreen(matchId: matchId),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to save match: $e',
            style: GoogleFonts.rajdhani(fontWeight: FontWeight.w600),
          ),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surfaceDark,
      appBar: AppBar(
        backgroundColor: _primaryGreen,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: Text(
          'New Match',
          style: GoogleFonts.rajdhani(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            letterSpacing: 1.2,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ── Optional: Tournament Name ─────────────────────────────
                      // ── Match Stage (only for tournament matches) ─────────
                      if (widget.tournamentId != null) ...[
                        _buildSectionHeader('MATCH STAGE'),
                        const SizedBox(height: 12),
                        if (_isKnockout)
                          // Knockout: auto-computed stage badge (read-only)
                          _buildKnockoutStageBadge()
                        else
                          DropdownButtonFormField<String>(
                            initialValue: _matchStage,
                            dropdownColor: _surfaceCard,
                            style: GoogleFonts.rajdhani(
                              color: _textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                            decoration: _inputDecoration(
                              'Stage',
                              icon: Icons.outlined_flag,
                            ),
                            hint: Text(
                              'Select stage',
                              style: GoogleFonts.rajdhani(
                                color: _hintColor,
                                fontSize: 16,
                              ),
                            ),
                            items: _stageOptions.map((s) => DropdownMenuItem(
                              value: s,
                              child: Text(s),
                            )).toList(),
                            onChanged: (v) => setState(() => _matchStage = v),
                          ),
                      ],

                      const SizedBox(height: 24),

                      // ── Section: Teams ──────────────────────────────────────────
                      _buildSectionHeader('TEAMS'),
                      const SizedBox(height: 12),

                      // Team A — dropdown when tournament is active, text otherwise
                      _buildTeamInput(slot: 'A'),
                      const SizedBox(height: 16),

                      // VS Divider
                      Row(
                        children: [
                          Expanded(child: Container(height: 1, color: const Color(0xFF2A2A2A))),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Text(
                              'VS',
                              style: GoogleFonts.rajdhani(
                                color: _accentGreen,
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                                letterSpacing: 3,
                              ),
                            ),
                          ),
                          Expanded(child: Container(height: 1, color: const Color(0xFF2A2A2A))),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Team B — dropdown when tournament is active, text otherwise
                      _buildTeamInput(slot: 'B'),
                      const SizedBox(height: 28),

                      // ── Section: Match Settings ─────────────────────────────────
                      _buildSectionHeader('MATCH SETTINGS'),
                      const SizedBox(height: 12),
                      
                      TextFormField(
                        controller:  _oversCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        style: GoogleFonts.rajdhani(
                          color: _textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: _inputDecoration(
                          'Total Overs',
                          hint: '1 - 50',
                          icon: Icons.sports_cricket,
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Required';
                          final n = int.tryParse(v.trim());
                          if (n == null) return 'Must be a number';
                          if (n < 1) return 'Minimum 1';
                          if (n > 50) return 'Maximum 50';
                          return null;
                        },
                      ),
                      const SizedBox(height: 28),

                      // ── Section: Toss ───────────────────────────────────────────
                      _buildSectionHeader('TOSS (OPTIONAL)'),
                      const SizedBox(height: 12),
                      
                      _buildTossSection(),
                      const SizedBox(height: 32),

                      // ── Preview Card ────────────────────────────────────────────
                      _buildPreviewCard(),
                      
                      // ── Info Note ───────────────────────────────────────────────
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: _accentGreen.withAlpha(20),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _accentGreen.withAlpha(60)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, color: _accentGreen, size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Players will be entered as the match progresses. No need to add the full squad upfront!',
                                style: GoogleFonts.rajdhani(
                                  fontSize: 13,
                                  color: _accentGreen,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
            
            // ── Start Button ────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _surfaceDark,
                border: Border(
                  top: BorderSide(color: _glassBorder, width: 1),
                ),
              ),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _saving ? null : _startMatch,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accentGreen,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: _accentGreen.withAlpha(120),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 4,
                    shadowColor: _accentGreen.withAlpha(100),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.play_arrow, size: 24),
                            const SizedBox(width: 8),
                            Text(
                              'Start Match',
                              style: GoogleFonts.rajdhani(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: GoogleFonts.rajdhani(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: _hintColor,
        letterSpacing: 2.5,
      ),
    );
  }

  /// Read-only stage badge shown for knockout tournaments.
  Widget _buildKnockoutStageBadge() {
    final stage = _matchStage ?? (_teamsLoading ? '...' : '—');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _inputFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _accentGreen.withAlpha(120), width: 1.5),
      ),
      child: Row(
        children: [
          const Icon(Icons.outlined_flag, color: _accentGreen, size: 20),
          const SizedBox(width: 12),
          Text(
            stage,
            style: GoogleFonts.rajdhani(
              color: _accentGreen,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          Text(
            'AUTO',
            style: GoogleFonts.rajdhani(
              color: _hintColor,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            ),
          ),
        ],
      ),
    );
  }

  // ── Team Input Builder ─────────────────────────────────────────────────────
  /// Builds either a [DropdownButtonFormField] (tournament mode) or a
  /// [TextFormField] (quick-match mode) for the given [slot] ('A' or 'B').
  Widget _buildTeamInput({required String slot}) {
    final isA = slot == 'A';
    final label = 'Team $slot Name';
    final hint = isA ? 'e.g. Karachi Kings' : 'e.g. Lahore Qalandars';
    final icon = isA ? Icons.shield : Icons.shield_outlined;

    // ── Tournament mode → Dropdown ─────────────────────────────────────────
    if (widget.tournamentId != null) {
      if (_teamsLoading) {
        return Container(
          height: 56,
          decoration: BoxDecoration(
            color: _inputFill,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF2A2A2A)),
          ),
          child: const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: _accentGreen,
              ),
            ),
          ),
        );
      }

      final selectedValue = isA ? _selectedTeamA : _selectedTeamB;
      final otherSelected = isA ? _selectedTeamB : _selectedTeamA;

      // Filter out the team already chosen for the other slot
      final availableTeams = _tournamentTeams
          .where((t) => t != otherSelected)
          .toList();

      // If the current selection was removed (e.g. other slot took it), reset
      final effectiveValue =
          (selectedValue != null && availableTeams.contains(selectedValue))
              ? selectedValue
              : null;

      return DropdownButtonFormField<String>(
        initialValue: effectiveValue,
        dropdownColor: _surfaceCard,
        isExpanded: true,
        style: GoogleFonts.rajdhani(
          color: _textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        decoration: _inputDecoration(label, icon: icon),
        hint: Text(
          _tournamentTeams.isEmpty ? 'No teams registered' : 'Select $label',
          style: GoogleFonts.rajdhani(color: _hintColor, fontSize: 16),
        ),
        items: availableTeams
            .map((t) => DropdownMenuItem(
                  value: t,
                  child: Text(
                    t,
                    style: GoogleFonts.rajdhani(
                      color: _textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ))
            .toList(),
        onChanged: _tournamentTeams.isEmpty
            ? null
            : (v) => setState(() {
                  if (isA) {
                    _selectedTeamA = v;
                  } else {
                    _selectedTeamB = v;
                  }
                  // Reset toss when teams change
                  _tossWinner = null;
                  _optTo = null;
                }),
        validator: (v) {
          if (v == null || v.isEmpty) return 'Required';
          return null;
        },
      );
    }

    // ── Quick-match mode → Autocomplete TextField ──────────────────────────
    final ctrl = isA ? _teamACtrl : _teamBCtrl;

    return Autocomplete<String>(
      initialValue: TextEditingValue(text: ctrl.text),
      optionsBuilder: (TextEditingValue textEditingValue) async {
        // Always fetch so the list updates as the user types
        final suggestions = await DatabaseHelper.instance.getDistinctTeamNames(
          prefix: textEditingValue.text,
          limit: 5,
        );
        // Filter out exact match to avoid a suggestion that duplicates the field
        return suggestions.where((s) =>
            s.toLowerCase() != textEditingValue.text.trim().toLowerCase());
      },
      displayStringForOption: (s) => s,
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            color: Colors.transparent,
            child: Container(
              constraints: const BoxConstraints(maxHeight: 200),
              margin: const EdgeInsets.only(top: 4),
              decoration: BoxDecoration(
                color: _surfaceCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF2A2A2A)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(120),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ListView.separated(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                separatorBuilder: (context, index) =>
                    const Divider(height: 1, color: Color(0xFF2A2A2A)),
                itemBuilder: (context, index) {
                  final option = options.elementAt(index);
                  return InkWell(
                    onTap: () => onSelected(option),
                    borderRadius: index == 0
                        ? const BorderRadius.vertical(top: Radius.circular(12))
                        : (index == options.length - 1
                            ? const BorderRadius.vertical(
                                bottom: Radius.circular(12))
                            : BorderRadius.zero),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          Icon(Icons.history, size: 16, color: _hintColor),
                          const SizedBox(width: 10),
                          Text(
                            option,
                            style: GoogleFonts.rajdhani(
                              color: _textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
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
      fieldViewBuilder:
          (context, textController, focusNode, onFieldSubmitted) {
        // Keep the external controller in sync with the Autocomplete internal one
        textController.text = ctrl.text;
        textController.addListener(() {
          if (ctrl.text != textController.text) {
            ctrl.text = textController.text;
            ctrl.selection = textController.selection;
            setState(() {}); // Rebuild for toss & preview
          }
        });
        return TextFormField(
          controller: textController,
          focusNode: focusNode,
          textCapitalization: TextCapitalization.words,
          style: GoogleFonts.rajdhani(
            color: _textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
          decoration: _inputDecoration(label, hint: hint, icon: icon),
          validator: (v) {
            if (v == null || v.trim().isEmpty) return 'Required';
            if (v.trim().length < 2) return 'Min 2 characters';
            if (!isA) {
              final a = _teamACtrl.text.trim().toLowerCase();
              final b = v.trim().toLowerCase();
              if (a.isNotEmpty && a == b) return 'Must be different';
            }
            return null;
          },
          onFieldSubmitted: (_) => onFieldSubmitted(),
        );
      },
      onSelected: (String selection) {
        ctrl.text = selection;
        setState(() {}); // Rebuild for toss & preview
      },
    );
  }

  Widget _buildTossSection() {
    final teamA = _effectiveTeamA;
    final teamB = _effectiveTeamB;
    final hasTeams = teamA.isNotEmpty && teamB.isNotEmpty;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _glassBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _glassBorder, width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Toss Winner
              Text(
                'Who won the toss?',
                style: GoogleFonts.rajdhani(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _buildChoiceChip(
                      label: teamA.isEmpty ? 'Team A' : teamA,
                      selected: _tossWinner == 'team_a',
                      enabled: hasTeams,
                      onTap: () => setState(() => _tossWinner = 'team_a'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildChoiceChip(
                      label: teamB.isEmpty ? 'Team B' : teamB,
                      selected: _tossWinner == 'team_b',
                      enabled: hasTeams,
                      onTap: () => setState(() => _tossWinner = 'team_b'),
                    ),
                  ),
                ],
              ),
              
              if (_tossWinner != null) ...[
                const SizedBox(height: 20),
                Text(
                  'Elected to?',
                  style: GoogleFonts.rajdhani(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _buildChoiceChip(
                        label: 'BAT',
                        selected: _optTo == 'bat',
                        onTap: () => setState(() => _optTo = 'bat'),
                        icon: Icons.sports_cricket,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildChoiceChip(
                        label: 'BOWL',
                        selected: _optTo == 'bowl',
                        onTap: () => setState(() => _optTo = 'bowl'),
                        icon: Icons.sports_baseball,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChoiceChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    bool enabled = true,
    IconData? icon,
  }) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? _accentGreen : _surfaceCard,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? _accentGreen : const Color(0xFF2A2A2A),
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 18,
                color: selected ? Colors.white : _hintColor,
              ),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(
                label,
                style: GoogleFonts.rajdhani(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? Colors.white
                      : (enabled ? _textPrimary : _hintColor),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewCard() {
    final a = _effectiveTeamA;
    final b = _effectiveTeamB;
    final overs = _oversCtrl.text.trim();
    final isTournamentMatch = widget.tournamentId != null;

    final teamA = a.isEmpty ? 'Team A' : a;
    final teamB = b.isEmpty ? 'Team B' : b;
    final ovsLabel = (overs.isEmpty || int.tryParse(overs) == null)
        ? '? overs'
        : '${int.parse(overs)} overs';

    String? tossInfo;
    if (_tossWinner != null && _optTo != null) {
      final winner = _tossWinner == 'team_a' ? teamA : teamB;
      tossInfo = '$winner won toss, elected to ${_optTo == 'bat' ? 'bat' : 'bowl'}';
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _glassBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _glassBorder, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(40),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            children: [
              // Show "TOURNAMENT MATCH" badge or generic "MATCH PREVIEW" label
              if (isTournamentMatch) ...[
                Text(
                  'TOURNAMENT MATCH',
                  style: GoogleFonts.rajdhani(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _accentGreen,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 8),
              ] else
                Text(
                  'MATCH PREVIEW',
                  style: GoogleFonts.rajdhani(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: _hintColor,
                    letterSpacing: 3,
                  ),
                ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      teamA,
                      textAlign: TextAlign.right,
                      style: GoogleFonts.rajdhani(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: _textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      'VS',
                      style: GoogleFonts.rajdhani(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: _accentGreen,
                        letterSpacing: 3,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      teamB,
                      textAlign: TextAlign.left,
                      style: GoogleFonts.rajdhani(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: _textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                ovsLabel,
                style: GoogleFonts.rajdhani(
                  fontSize: 14,
                  color: _accentGreen,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
              if (tossInfo != null) ...[
                const SizedBox(height: 10),
                Text(
                  tossInfo,
                  style: GoogleFonts.rajdhani(
                    fontSize: 12,
                    color: _hintColor,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
