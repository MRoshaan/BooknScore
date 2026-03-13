import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../providers/tournament_provider.dart';
import '../services/auth_service.dart';
import '../services/database_helper.dart';

// ── Palette (mirrors dashboard) ───────────────────────────────────────────────
const Color _accentGreen  = Color(0xFF39FF14);
const Color _surfaceDark  = Color(0xFF0A0A0A);
const Color _surfaceCard  = Color(0xFF141414);
const Color _surfaceCard2 = Color(0xFF1C1C1C);
const Color _glassBg      = Color(0x1239FF14);
const Color _glassBorder  = Color(0x3239FF14);
const Color _hintColor    = Color(0xFF6A6A6A);
const Color _textPrimary  = Colors.white;
const Color _textSec      = Color(0xFF8A8A8A);
const Color _trophyGold   = Color(0xFFFFC107);
const Color _liveRed      = Color(0xFFFF3D3D);

// ─────────────────────────────────────────────────────────────────────────────

class CreateTournamentScreen extends StatefulWidget {
  const CreateTournamentScreen({super.key});
  @override
  State<CreateTournamentScreen> createState() => _CreateTournamentScreenState();
}

class _CreateTournamentScreenState extends State<CreateTournamentScreen> {
  final _formKey   = GlobalKey<FormState>();
  final _nameCtrl  = TextEditingController();
  final _oversCtrl = TextEditingController(text: '20');
  final _teamCtrl  = TextEditingController();

  String _format = 'league';  // 'league' | 'knockout' | 'mixed'
  final List<String> _teams = [];
  bool _saving = false;
  List<String> _teamSuggestions = [];
  // Incrementing this key resets the Autocomplete widget (clears its field).
  int _autocompleteKey = 0;

  @override
  void initState() {
    super.initState();
    _loadTeamSuggestions();
  }

  Future<void> _loadTeamSuggestions() async {
    final names = await DatabaseHelper.instance.fetchDistinctTeamNames();
    if (mounted) setState(() => _teamSuggestions = names);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _oversCtrl.dispose();
    _teamCtrl.dispose();
    super.dispose();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  InputDecoration _input(String label, {String? hint, IconData? icon}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: icon != null ? Icon(icon, color: _hintColor, size: 18) : null,
      labelStyle: GoogleFonts.rajdhani(color: _hintColor, fontWeight: FontWeight.w600),
      hintStyle: GoogleFonts.rajdhani(color: _hintColor),
      filled: true,
      fillColor: _surfaceCard2,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
        borderSide: const BorderSide(color: _liveRed),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _liveRed, width: 2),
      ),
    );
  }

  void _addTeam() {
    final name = _teamCtrl.text.trim();
    if (name.isEmpty) return;
    if (_teams.any((t) => t.toLowerCase() == name.toLowerCase())) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Team "$name" already added.',
            style: GoogleFonts.rajdhani(fontWeight: FontWeight.w600)),
        backgroundColor: _liveRed,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
      return;
    }
    setState(() {
      _teams.add(name);
      _teamCtrl.clear();
      _autocompleteKey++; // reset Autocomplete field
    });
  }

  void _removeTeam(int index) => setState(() => _teams.removeAt(index));

  Future<void> _create() async {
    if (!_formKey.currentState!.validate()) return;
    if (_teams.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Add at least 2 teams.',
            style: GoogleFonts.rajdhani(fontWeight: FontWeight.w600)),
        backgroundColor: _liveRed,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
      return;
    }

    setState(() => _saving = true);
    try {
      final userId = AuthService.instance.currentUser?.id;
      await context.read<TournamentProvider>().createTournament(
        name: _nameCtrl.text.trim(),
        format: _format,
        oversPerMatch: int.parse(_oversCtrl.text.trim()),
        teams: List<String>.from(_teams),
        createdBy: userId,
      );
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Failed to create tournament: $e',
            style: GoogleFonts.rajdhani(fontWeight: FontWeight.w600)),
        backgroundColor: _liveRed,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surfaceDark,
      appBar: AppBar(
        backgroundColor: _surfaceDark,
        foregroundColor: _textPrimary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Create Tournament',
          style: GoogleFonts.rajdhani(
              fontSize: 22, fontWeight: FontWeight.w800, color: _textPrimary),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: _glassBorder),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _sectionLabel('TOURNAMENT DETAILS'),
                      const SizedBox(height: 12),

                      // Name
                      TextFormField(
                        controller: _nameCtrl,
                        textCapitalization: TextCapitalization.words,
                        style: GoogleFonts.rajdhani(
                            fontSize: 16, fontWeight: FontWeight.w600, color: _textPrimary),
                        decoration: _input(
                          'Tournament Name',
                          hint: 'e.g. Gully Premier League 2025',
                          icon: Icons.emoji_events,
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Required';
                          if (v.trim().length < 3) return 'Min 3 characters';
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Overs per match
                      TextFormField(
                        controller: _oversCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        style: GoogleFonts.rajdhani(
                            fontSize: 16, fontWeight: FontWeight.w600, color: _textPrimary),
                        decoration: _input(
                          'Overs per Match',
                          hint: '1 – 50',
                          icon: Icons.sports_cricket,
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Required';
                          final n = int.tryParse(v.trim());
                          if (n == null || n < 1 || n > 50) return 'Must be 1–50';
                          return null;
                        },
                      ),
                      const SizedBox(height: 24),

                      // Format selector
                      _sectionLabel('FORMAT'),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: _formatChip('league',   'League',   Icons.table_rows)),
                          const SizedBox(width: 8),
                          Expanded(child: _formatChip('knockout', 'Knockout', Icons.account_tree_outlined)),
                          const SizedBox(width: 8),
                          Expanded(child: _formatChip('mixed',    'Mixed',    Icons.shuffle)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _formatDescription(_format),
                        style: GoogleFonts.rajdhani(fontSize: 12, color: _textSec),
                      ),
                      const SizedBox(height: 28),

                      // Teams
                      _sectionLabel('TEAMS  (${_teams.length} added)'),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Autocomplete<String>(
                              key: ValueKey(_autocompleteKey),
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
                                // Keep _teamCtrl in sync with the autocomplete's
                                // internal controller so _addTeam() can read it.
                                controller.addListener(() {
                                  if (_teamCtrl.text != controller.text) {
                                    _teamCtrl.text = controller.text;
                                  }
                                });
                                return TextFormField(
                                  controller: controller,
                                  focusNode: focusNode,
                                  textCapitalization: TextCapitalization.words,
                                  style: GoogleFonts.rajdhani(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: _textPrimary),
                                  decoration: _input(
                                    'Team Name',
                                    hint: 'e.g. Karachi Kings',
                                    icon: Icons.shield_outlined,
                                  ),
                                  onFieldSubmitted: (_) {
                                    onSubmitted();
                                    _addTeam();
                                  },
                                );
                              },
                              optionsViewBuilder: (context, onSelected, options) {
                                return Align(
                                  alignment: Alignment.topLeft,
                                  child: Material(
                                    color: _surfaceCard2,
                                    borderRadius: BorderRadius.circular(10),
                                    elevation: 8,
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(maxHeight: 200),
                                      child: ListView.builder(
                                        padding: EdgeInsets.zero,
                                        shrinkWrap: true,
                                        itemCount: options.length,
                                        itemBuilder: (_, i) {
                                          final opt = options.elementAt(i);
                                          return InkWell(
                                            onTap: () => onSelected(opt),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(
                                                  horizontal: 16, vertical: 12),
                                              decoration: BoxDecoration(
                                                border: Border(
                                                  bottom: BorderSide(
                                                    color: const Color(0xFF2A2A2A),
                                                    width: i < options.length - 1 ? 1 : 0,
                                                  ),
                                                ),
                                              ),
                                              child: Row(
                                                children: [
                                                  const Icon(Icons.shield_outlined,
                                                      size: 14, color: _accentGreen),
                                                  const SizedBox(width: 10),
                                                  Text(
                                                    opt,
                                                    style: GoogleFonts.rajdhani(
                                                        fontSize: 14,
                                                        fontWeight: FontWeight.w600,
                                                        color: _textPrimary),
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
                            ),
                          ),
                          const SizedBox(width: 10),
                          GestureDetector(
                            onTap: _addTeam,
                            child: Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                color: _accentGreen,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.add, color: Colors.black, size: 26),
                            ),
                          ),
                        ],
                      ),
                      if (_teams.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Container(
                          decoration: BoxDecoration(
                            color: _surfaceCard2,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFF2A2A2A)),
                          ),
                          child: ReorderableListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _teams.length,
                            onReorder: (o, n) {
                              setState(() {
                                if (n > o) n--;
                                final item = _teams.removeAt(o);
                                _teams.insert(n, item);
                              });
                            },
                            itemBuilder: (_, i) => ListTile(
                              key: ValueKey(_teams[i]),
                              dense: true,
                              leading: Text(
                                '${i + 1}',
                                style: GoogleFonts.rajdhani(
                                    fontSize: 14, fontWeight: FontWeight.w700, color: _textSec),
                              ),
                              title: Text(
                                _teams[i],
                                style: GoogleFonts.rajdhani(
                                    fontSize: 15, fontWeight: FontWeight.w700, color: _textPrimary),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.drag_handle, color: Color(0xFF3A3A3A), size: 20),
                                  const SizedBox(width: 4),
                                  GestureDetector(
                                    onTap: () => _removeTeam(i),
                                    child: const Icon(Icons.remove_circle_outline,
                                        color: _liveRed, size: 20),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 28),

                      // Preview
                      _buildPreview(),
                      const SizedBox(height: 28),
                    ],
                  ),
                ),
              ),
            ),

            // Create button
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: _surfaceDark,
                border: Border(top: BorderSide(color: _glassBorder)),
              ),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: _saving ? null : _create,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _trophyGold,
                    foregroundColor: Colors.black,
                    disabledBackgroundColor: _trophyGold.withAlpha(100),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 6,
                    shadowColor: _trophyGold.withAlpha(80),
                  ),
                  icon: _saving
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                        )
                      : const Icon(Icons.emoji_events, size: 22),
                  label: Text(
                    _saving ? 'Creating...' : 'Create Tournament',
                    style: GoogleFonts.rajdhani(
                        fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: 0.8),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: GoogleFonts.rajdhani(
        fontSize: 11, fontWeight: FontWeight.w700,
        color: _hintColor, letterSpacing: 2.5,
      ),
    );
  }

  Widget _formatChip(String value, String label, IconData icon) {
    final selected = _format == value;
    return GestureDetector(
      onTap: () => setState(() => _format = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? _trophyGold.withAlpha(30) : _surfaceCard2,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? _trophyGold : const Color(0xFF2A2A2A),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: selected ? _trophyGold : _hintColor),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.rajdhani(
                fontSize: 12, fontWeight: FontWeight.w700,
                color: selected ? _trophyGold : _hintColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDescription(String fmt) {
    switch (fmt) {
      case 'knockout': return 'Single elimination — lose once and you\'re out.';
      case 'mixed':    return 'Group stage (league) followed by knockout rounds.';
      default:         return 'Every team plays every other team. Points table decides ranking.';
    }
  }

  Widget _buildPreview() {
    final name  = _nameCtrl.text.trim().isEmpty ? 'Tournament Name' : _nameCtrl.text.trim();
    final overs = _oversCtrl.text.trim().isEmpty ? '?' : _oversCtrl.text.trim();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _glassBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.emoji_events, size: 16, color: _trophyGold),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  name.toUpperCase(),
                  style: GoogleFonts.rajdhani(
                    fontSize: 14, fontWeight: FontWeight.w900,
                    color: _trophyGold, letterSpacing: 1.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '$_format  ·  $overs overs  ·  ${_teams.length} teams',
            style: GoogleFonts.rajdhani(fontSize: 12, color: _textSec, fontWeight: FontWeight.w600),
          ),
          if (_teams.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6, runSpacing: 4,
              children: _teams.map((t) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _surfaceCard,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF2A2A2A)),
                ),
                child: Text(t, style: GoogleFonts.rajdhani(fontSize: 11, color: _textSec)),
              )).toList(),
            ),
          ],
        ],
      ),
    );
  }
}
