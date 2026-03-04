import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:ui';

import '../services/database_helper.dart';
import 'match_summary_screen.dart';
import 'scorecard_screen.dart';

// ── Brand Palette ─────────────────────────────────────────────────────────────
const Color _thSurfaceDark   = Color(0xFF0A0A0A);
const Color _thSurfaceCard   = Color(0xFF141414);
const Color _thAccentGreen   = Color(0xFF39FF14);
const Color _thAccentMid     = Color(0xFF4CAF50);
const Color _thGlassBg       = Color(0x1A39FF14);
const Color _thGlassBorder   = Color(0x3239FF14);
const Color _thTextPrimary   = Colors.white;
const Color _thTextSecondary = Color(0xFF8A8A8A);
const Color _thLiveRed       = Color(0xFFFF3D3D);
const Color _thCompletedBlue = Color(0xFF2196F3);
const Color _thWinGreen      = Color(0xFF4CAF50);
const Color _thLossRed       = Color(0xFFD32F2F);
const Color _thTieAmber      = Color(0xFFFFA000);
// ─────────────────────────────────────────────────────────────────────────────

class TeamHistoryScreen extends StatefulWidget {
  const TeamHistoryScreen({super.key, required this.teamName});

  final String teamName;

  @override
  State<TeamHistoryScreen> createState() => _TeamHistoryScreenState();
}

class _TeamHistoryScreenState extends State<TeamHistoryScreen> {
  List<Map<String, dynamic>> _matches = [];
  bool _loading = true;

  int get _wins => _matches.where((m) {
    if (m[DatabaseHelper.colStatus] != 'completed') return false;
    final winner = (m[DatabaseHelper.colWinner] as String? ?? '').toLowerCase();
    return winner.contains(widget.teamName.toLowerCase());
  }).length;

  int get _losses {
    int count = 0;
    for (final m in _matches) {
      if (m[DatabaseHelper.colStatus] != 'completed') continue;
      final winner = (m[DatabaseHelper.colWinner] as String? ?? '').toLowerCase();
      if (winner.isEmpty) continue;
      if (!winner.contains(widget.teamName.toLowerCase())) count++;
    }
    return count;
  }

  int get _ties => _matches.where((m) {
    if (m[DatabaseHelper.colStatus] != 'completed') return false;
    final winner = (m[DatabaseHelper.colWinner] as String? ?? '').toLowerCase();
    return winner.contains('tied') || winner.contains('tie') || winner.contains('no result');
  }).length;

  @override
  void initState() {
    super.initState();
    _loadMatches();
  }

  Future<void> _loadMatches() async {
    setState(() => _loading = true);
    try {
      final matches = await DatabaseHelper.instance.fetchMatchesByTeam(widget.teamName);
      if (mounted) setState(() { _matches = matches; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final live = _matches.where((m) =>
      m[DatabaseHelper.colStatus] == 'live' ||
      m[DatabaseHelper.colStatus] == 'pending'
    ).toList();
    final done = _matches.where((m) =>
      m[DatabaseHelper.colStatus] == 'completed'
    ).toList();

    return Scaffold(
      backgroundColor: _thSurfaceDark,
      appBar: _buildAppBar(),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _thAccentGreen))
          : _matches.isEmpty
              ? _buildEmptyState()
              : _buildBody(live, done),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: _thSurfaceDark,
      foregroundColor: _thTextPrimary,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new, color: _thAccentGreen, size: 20),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.teamName,
            style: GoogleFonts.rajdhani(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: _thTextPrimary,
              letterSpacing: 0.5,
            ),
          ),
          Text(
            'MATCH HISTORY',
            style: GoogleFonts.rajdhani(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: _thAccentGreen,
              letterSpacing: 3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(
    List<Map<String, dynamic>> live,
    List<Map<String, dynamic>> done,
  ) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        // W/L/T record header
        if (_matches.any((m) => m[DatabaseHelper.colStatus] == 'completed'))
          _buildRecordCard(),
        const SizedBox(height: 16),

        if (live.isNotEmpty) ...[
          _sectionHeader('LIVE / ACTIVE', _thLiveRed),
          const SizedBox(height: 8),
          ...live.map(_buildMatchCard),
          const SizedBox(height: 20),
        ],
        if (done.isNotEmpty) ...[
          _sectionHeader('COMPLETED', _thCompletedBlue),
          const SizedBox(height: 8),
          ...done.map(_buildMatchCard),
        ],
      ],
    );
  }

  Widget _buildRecordCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: _thGlassBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _thGlassBorder, width: 1),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _recordStat('W', '$_wins', _thWinGreen),
              _vDivider(),
              _recordStat('L', '$_losses', _thLossRed),
              _vDivider(),
              _recordStat('T', '$_ties', _thTieAmber),
              _vDivider(),
              _recordStat('Total', '${_matches.where((m) => m[DatabaseHelper.colStatus] == 'completed').length}', _thTextSecondary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _recordStat(String label, String value, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: GoogleFonts.rajdhani(
            fontSize: 28,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
        Text(
          label,
          style: GoogleFonts.rajdhani(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: _thTextSecondary,
            letterSpacing: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _vDivider() => Container(
    width: 1,
    height: 36,
    color: _thGlassBorder,
  );

  Widget _sectionHeader(String title, Color accent) {
    return Row(
      children: [
        Container(
          width: 3, height: 18,
          decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: GoogleFonts.rajdhani(
            fontSize: 11, fontWeight: FontWeight.w700,
            color: _thTextSecondary, letterSpacing: 2.5,
          ),
        ),
      ],
    );
  }

  Widget _buildMatchCard(Map<String, dynamic> match) {
    final id       = match[DatabaseHelper.colId]         as int;
    final teamA    = match[DatabaseHelper.colTeamA]      as String;
    final teamB    = match[DatabaseHelper.colTeamB]      as String;
    final status   = match[DatabaseHelper.colStatus]     as String;
    final overs    = match[DatabaseHelper.colTotalOvers] as int;
    final created  = match[DatabaseHelper.colCreatedAt]  as String?;
    final winner   = match[DatabaseHelper.colWinner]     as String?;
    final opponent = teamA == widget.teamName ? teamB : teamA;

    // Determine result from this team's perspective
    String? resultLabel;
    Color resultColor = _thTextSecondary;
    if (status == 'completed' && winner != null && winner.isNotEmpty) {
      final lower = winner.toLowerCase();
      if (lower.contains('tied') || lower.contains('tie') || lower.contains('no result')) {
        resultLabel = 'TIE';
        resultColor = _thTieAmber;
      } else if (lower.contains(widget.teamName.toLowerCase())) {
        resultLabel = 'WIN';
        resultColor = _thWinGreen;
      } else {
        resultLabel = 'LOSS';
        resultColor = _thLossRed;
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () {
          if (status == 'completed') {
            Navigator.push(context, MaterialPageRoute(
              builder: (_) => ScorecardScreen(matchId: id, teamA: teamA, teamB: teamB),
            ));
          }
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _thSurfaceCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: status == 'live'
                      ? _thLiveRed.withAlpha(80)
                      : const Color(0xFF1E1E1E),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Status badge
                      _StatusChip(status),
                      const Spacer(),
                      // Result badge
                      if (resultLabel != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: resultColor.withAlpha(25),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: resultColor.withAlpha(80)),
                          ),
                          child: Text(
                            resultLabel,
                            style: GoogleFonts.rajdhani(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: resultColor,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ),
                      if (created != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          _relDate(created),
                          style: GoogleFonts.rajdhani(fontSize: 11, color: _thTextSecondary),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Opponent row
                  Row(
                    children: [
                      Text(
                        'vs  ',
                        style: GoogleFonts.rajdhani(
                          fontSize: 13, color: _thTextSecondary, fontWeight: FontWeight.w600,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          opponent,
                          style: GoogleFonts.rajdhani(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: _thTextPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (winner != null && winner.isNotEmpty && status == 'completed') ...[
                    const SizedBox(height: 4),
                    Text(
                      winner,
                      style: GoogleFonts.rajdhani(
                        fontSize: 12, color: _thTextSecondary, fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.timer_outlined, size: 13, color: _thTextSecondary),
                      const SizedBox(width: 4),
                      Text(
                        '$overs overs',
                        style: GoogleFonts.rajdhani(
                          fontSize: 12, color: _thTextSecondary, fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      if (status == 'completed')
                        GestureDetector(
                          onTap: () => Navigator.push(context, MaterialPageRoute(
                            builder: (_) => MatchSummaryScreen(matchId: id, teamA: teamA, teamB: teamB),
                          )),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: _thCompletedBlue.withAlpha(25),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: _thCompletedBlue.withAlpha(70)),
                            ),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              const Icon(Icons.bar_chart, size: 13, color: _thCompletedBlue),
                              const SizedBox(width: 4),
                              Text('Summary',
                                  style: GoogleFonts.rajdhani(
                                      fontSize: 11, fontWeight: FontWeight.w700, color: _thCompletedBlue)),
                            ]),
                          ),
                        ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.arrow_forward_ios,
                        size: 13,
                        color: status == 'completed' ? _thAccentMid : _thTextSecondary.withAlpha(80),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.sports_cricket, size: 72, color: _thAccentGreen.withAlpha(60)),
            const SizedBox(height: 20),
            Text(
              'No Matches Found',
              style: GoogleFonts.rajdhani(
                fontSize: 22, fontWeight: FontWeight.w700, color: _thTextSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${widget.teamName} has not played any matches yet.',
              style: GoogleFonts.rajdhani(fontSize: 14, color: _thTextSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  String _relDate(String iso) {
    try {
      final d = DateTime.parse(iso);
      final diff = DateTime.now().difference(d);
      if (diff.inDays == 0) return 'Today';
      if (diff.inDays == 1) return 'Yesterday';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return '${d.day}/${d.month}/${d.year}';
    } catch (_) { return ''; }
  }
}

// ── Status Chip ───────────────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  const _StatusChip(this.status);
  final String status;

  @override
  Widget build(BuildContext context) {
    late Color color;
    late String label;
    late IconData icon;
    switch (status) {
      case 'live':
        color = _thLiveRed; label = 'LIVE'; icon = Icons.circle;
        break;
      case 'pending':
        color = _thTieAmber; label = 'PENDING'; icon = Icons.hourglass_empty;
        break;
      default:
        color = _thCompletedBlue; label = 'DONE'; icon = Icons.check_circle_outline;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.rajdhani(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}
