import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/auth_service.dart';
import '../services/database_helper.dart';
import '../theme.dart';
import 'scorecard_screen.dart';
import 'player_profile_screen.dart';

// ── Fixed-role colour (not in AppColors) ──────────────────────────────────────
const Color _tdLossRed = Color(0xFFD32F2F);
// ─────────────────────────────────────────────────────────────────────────────

/// Detailed view of a single team: squad list + match history.
/// Allows adding a new player to the team inline.
class TeamDetailScreen extends StatefulWidget {
  const TeamDetailScreen({super.key, required this.teamName});

  final String teamName;

  @override
  State<TeamDetailScreen> createState() => _TeamDetailScreenState();
}

class _TeamDetailScreenState extends State<TeamDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<Map<String, dynamic>> _players = [];
  List<Map<String, dynamic>> _matches  = [];
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final db = DatabaseHelper.instance;
      final players = await db.fetchPlayersByTeam(widget.teamName);
      final matches  = await db.fetchMatchesByTeam(widget.teamName);
      if (mounted) {
        setState(() {
          _players = players;
          _matches  = matches;
          _loading  = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Add Player ────────────────────────────────────────────────────────────

  void _showAddPlayerSheet() {
    final nameCtrl = TextEditingController();
    String selectedRole = 'Batsman';
    String? selectedBowlingType;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(

        builder: (ctx, setLocal) {
          final c = Theme.of(ctx).appColors;
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              decoration: BoxDecoration(
                color: c.card,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
                border: Border(
                  top: BorderSide(color: c.glassBorder, width: 1),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle bar
                  Center(
                    child: Container(
                      width: 40, height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: c.glassBorder,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Text(
                    'Add Player to ${widget.teamName}',
                    style: GoogleFonts.rajdhani(
                      fontSize: 18, fontWeight: FontWeight.w800,
                      color: c.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Name field
                  TextField(
                    controller: nameCtrl,
                    style: GoogleFonts.rajdhani(
                      fontSize: 15, color: c.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Player name',
                      hintStyle: GoogleFonts.rajdhani(
                        fontSize: 15, color: c.textSecondary,
                      ),
                      prefixIcon: Icon(Icons.person_outline,
                          color: c.accentGreen, size: 20),
                      filled: true,
                      fillColor: c.glassBg,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                            color: c.glassBorder, width: 1),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                            color: c.glassBorder, width: 1),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                            color: c.neon, width: 1.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Role selector
                  Text(
                    'Role',
                    style: GoogleFonts.rajdhani(
                      fontSize: 13, fontWeight: FontWeight.w700,
                      color: c.textSecondary, letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final role in [
                          'Batsman', 'Bowler', 'All-rounder', 'Wicketkeeper'
                        ]) ...[
                          _RoleChip(
                            label: role,
                            selected: selectedRole == role,
                            accent: c.neon,
                            glassBorder: c.glassBorder,
                            textSecondary: c.textSecondary,
                            onTap: () => setLocal(() => selectedRole = role),
                          ),
                          const SizedBox(width: 8),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Bowling type (show if bowler / all-rounder)
                  if (selectedRole == 'Bowler' ||
                      selectedRole == 'All-rounder') ...[
                    Text(
                      'Bowling Type',
                      style: GoogleFonts.rajdhani(
                        fontSize: 13, fontWeight: FontWeight.w700,
                        color: c.textSecondary, letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final bt in [
                            'Fast', 'Medium-Fast', 'Medium', 'Off-spin',
                            'Leg-spin'
                          ]) ...[
                            _RoleChip(
                              label: bt,
                              selected: selectedBowlingType == bt,
                              accent: c.accentGreen,
                              glassBorder: c.glassBorder,
                              textSecondary: c.textSecondary,
                              onTap: () =>
                                  setLocal(() => selectedBowlingType = bt),
                            ),
                            const SizedBox(width: 8),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Submit
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final name = nameCtrl.text.trim();
                        if (name.isEmpty) return;
                        await DatabaseHelper.instance.insertPlayer(
                          name: name,
                          team: widget.teamName,
                          role: selectedRole,
                          bowlingType: selectedBowlingType,
                          createdBy: AuthService.instance.userId,
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                        _load();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: c.neon,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.person_add_outlined, size: 20),
                      label: Text(
                        'Add Player',
                        style: GoogleFonts.rajdhani(
                          fontSize: 16, fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ).then((_) => nameCtrl.dispose());
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).appColors;
    return Scaffold(
      backgroundColor: c.surface,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddPlayerSheet,
        backgroundColor: c.neon,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.person_add_outlined),
        label: Text(
          'Add Player',
          style: GoogleFonts.rajdhani(
            fontSize: 14, fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: NestedScrollView(
        headerSliverBuilder: (ctx, inner) => [_buildAppBar(ctx)],
        body: _loading
            ? Center(
                child: CircularProgressIndicator(color: c.neon),
              )
            : TabBarView(
                controller: _tabController,
                children: [
                  _buildSquadTab(c),
                  _buildMatchesTab(c),
                ],
              ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext ctx) {
    final c = Theme.of(ctx).appColors;
    return SliverAppBar(
      expandedHeight: 160,
      floating: false,
      pinned: true,
      backgroundColor: c.surface,
      leading: IconButton(
        icon: Icon(Icons.arrow_back_ios_new,
            color: c.textPrimary, size: 18),
        onPressed: () => Navigator.pop(context),
      ),
      flexibleSpace: FlexibleSpaceBar(
        centerTitle: false,
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0F1F0F), Color(0xFF0A0A0A)],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 56),
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.teamName,
                    style: GoogleFonts.rajdhani(
                      fontSize: 26, fontWeight: FontWeight.w900,
                      color: c.textPrimary, letterSpacing: 1,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _MiniStat(label: 'W',  value: _wins.toString(),
                          color: c.accentGreen),
                      const SizedBox(width: 8),
                      _MiniStat(label: 'L',  value: _losses.toString(),
                          color: _tdLossRed),
                      const SizedBox(width: 8),
                      _MiniStat(
                        label: 'P',
                        value: _players.length.toString(),
                        color: c.accentGreen,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(48),
        child: Container(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: c.glassBorder, width: 1)),
          ),
          child: TabBar(
            controller: _tabController,
            indicatorColor: c.neon,
            indicatorWeight: 3,
            labelColor: c.neon,
            unselectedLabelColor: c.textSecondary,
            labelStyle: GoogleFonts.rajdhani(
              fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 1,
            ),
            unselectedLabelStyle: GoogleFonts.rajdhani(
              fontSize: 14, fontWeight: FontWeight.w500,
            ),
            tabs: const [
              Tab(text: 'SQUAD'),
              Tab(text: 'MATCHES'),
            ],
          ),
        ),
      ),
    );
  }

  // ── Squad Tab ─────────────────────────────────────────────────────────────

  Widget _buildSquadTab(AppColors c) {
    if (_players.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_search, size: 64,
                color: c.neon.withAlpha(50)),
            const SizedBox(height: 16),
            Text(
              'No Players Yet',
              style: GoogleFonts.rajdhani(
                fontSize: 20, fontWeight: FontWeight.w700,
                color: c.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap "Add Player" to build your squad.',
              style: GoogleFonts.rajdhani(
                  fontSize: 14, color: c.textSecondary),
            ),
            const SizedBox(height: 80),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      itemCount: _players.length,
      itemBuilder: (ctx, i) => _playerTile(c, _players[i]),
    );
  }

  Widget _playerTile(AppColors c, Map<String, dynamic> player) {
    final id   = player[DatabaseHelper.colId]   as int;
    final name = player[DatabaseHelper.colName] as String;
    final role = player[DatabaseHelper.colRole] as String? ?? '';
    final bt   = player[DatabaseHelper.colBowlingType] as String? ?? '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PlayerProfileScreen(playerId: id, playerName: name),
          ),
        ).then((_) => _load()),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.glassBorder, width: 1),
          ),
          child: Row(
            children: [
              Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                  color: c.neon.withAlpha(20),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: GoogleFonts.rajdhani(
                      fontSize: 18, fontWeight: FontWeight.w800,
                      color: c.neon,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: GoogleFonts.rajdhani(
                        fontSize: 16, fontWeight: FontWeight.w700,
                        color: c.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (role.isNotEmpty || bt.isNotEmpty)
                      Text(
                        [role, bt].where((s) => s.isNotEmpty).join(' · '),
                        style: GoogleFonts.rajdhani(
                          fontSize: 12, color: c.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  color: c.textSecondary, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  // ── Matches Tab ───────────────────────────────────────────────────────────

  Widget _buildMatchesTab(AppColors c) {
    if (_matches.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.sports_cricket, size: 64,
                color: c.neon.withAlpha(50)),
            const SizedBox(height: 16),
            Text(
              'No Matches Yet',
              style: GoogleFonts.rajdhani(
                fontSize: 20, fontWeight: FontWeight.w700,
                color: c.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Matches involving this team will appear here.',
              style: GoogleFonts.rajdhani(
                  fontSize: 14, color: c.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      itemCount: _matches.length,
      itemBuilder: (ctx, i) => _matchTile(c, _matches[i]),
    );
  }

  Widget _matchTile(AppColors c, Map<String, dynamic> match) {
    final id     = match[DatabaseHelper.colId]         as int;
    final teamA  = match[DatabaseHelper.colTeamA]      as String;
    final teamB  = match[DatabaseHelper.colTeamB]      as String;
    final status = match[DatabaseHelper.colStatus]     as String;
    final winner = match[DatabaseHelper.colWinner]     as String? ?? '';

    // Determine result relative to this team
    String? resultLabel;
    Color resultColor = c.textSecondary;
    if (status == 'completed' && winner.isNotEmpty) {
      if (winner.toLowerCase().contains(widget.teamName.toLowerCase())) {
        resultLabel = 'WON';
        resultColor = c.accentGreen;
      } else {
        resultLabel = 'LOST';
        resultColor = _tdLossRed;
      }
    }

    Color statusColor;
    String statusLabel;
    switch (status) {
      case 'live':
      case 'ongoing':
        statusColor = c.liveRed;        statusLabel = 'LIVE';      break;
      case 'completed':
        statusColor = c.completedBlue;  statusLabel = 'DONE';      break;
      default:
        statusColor = c.accentGreen;    statusLabel = 'PENDING';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: status == 'completed'
            ? () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ScorecardScreen(
                      matchId: id, teamA: teamA, teamB: teamB,
                    ),
                  ),
                )
            : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.glassBorder, width: 1),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$teamA vs $teamB',
                      style: GoogleFonts.rajdhani(
                        fontSize: 15, fontWeight: FontWeight.w700,
                        color: c.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: statusColor.withAlpha(25),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                                color: statusColor.withAlpha(70)),
                          ),
                          child: Text(
                            statusLabel,
                            style: GoogleFonts.rajdhani(
                              fontSize: 10, fontWeight: FontWeight.w700,
                              color: statusColor, letterSpacing: 1.2,
                            ),
                          ),
                        ),
                        if (resultLabel != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            resultLabel,
                            style: GoogleFonts.rajdhani(
                              fontSize: 12, fontWeight: FontWeight.w800,
                              color: resultColor,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (status == 'completed')
                Icon(Icons.chevron_right,
                    color: c.textSecondary, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Helper widgets ────────────────────────────────────────────────────────────

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(70), width: 1),
      ),
      child: Text(
        '$label: $value',
        style: GoogleFonts.rajdhani(
          fontSize: 12, fontWeight: FontWeight.w700, color: color,
        ),
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.accent = const Color(0xFF39FF14),
    this.glassBorder = const Color(0x3239FF14),
    this.textSecondary = const Color(0xFF8A8A8A),
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color accent;
  final Color glassBorder;
  final Color textSecondary;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? accent.withAlpha(30) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? accent : glassBorder,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.rajdhani(
            fontSize: 13, fontWeight: FontWeight.w700,
            color: selected ? accent : textSecondary,
          ),
        ),
      ),
    );
  }
}
