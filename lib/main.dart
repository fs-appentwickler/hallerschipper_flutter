import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final raw = await rootBundle.loadString('assets/songs.json');
  final decoded = jsonDecode(raw) as List<dynamic>;
  final songs = decoded
      .map((item) => Song.fromJson(item as Map<String, dynamic>))
      .toList(growable: false);
  try {
    await LyricsStore.instance.load();
  } catch (_) {
    // Auch bei nicht verfügbarem lokalen Speicher bleiben die Originallieder lesbar.
  }
  final available = await SongUpdates.loadCache(songs);
  runApp(HallerschipperApp(songs: available));
}

class Song {
  const Song({
    required this.number,
    required this.title,
    required this.category,
    required this.text,
  });

  factory Song.fromJson(Map<String, dynamic> json) => Song(
    number: (json['nr'] as String? ?? '').trim(),
    title: (json['title'] as String? ?? '').trim(),
    category: (json['category'] as String? ?? '').trim(),
    text: (json['text'] as String? ?? '').trim(),
  );

  final String number;
  final String title;
  final String category;
  final String text;

  String get displayTitle => number.isEmpty ? title : 'Nr. $number – $title';

  bool matches(String query) {
    final value = query.trim().toLowerCase();
    if (value.isEmpty) return true;
    return number.toLowerCase().contains(value) ||
        title.toLowerCase().contains(value) ||
        LyricsStore.instance.textFor(this).toLowerCase().contains(value);
  }
}

class HallerschipperApp extends StatelessWidget {
  const HallerschipperApp({super.key, required this.songs});

  final List<Song> songs;

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF0F76C5);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Hallerschipper',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: blue,
          primary: blue,
          surface: Colors.white,
        ),
        scaffoldBackgroundColor: const Color(0xFFEDF5FB),
        useMaterial3: true,
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFD9E3EE), width: 2),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFD9E3EE), width: 2),
          ),
        ),
      ),
      home: SongListPage(songs: songs),
    );
  }
}

class SongListPage extends StatefulWidget {
  const SongListPage({super.key, required this.songs});

  final List<Song> songs;

  @override
  State<SongListPage> createState() => _SongListPageState();
}

class _SongListPageState extends State<SongListPage> {
  final _searchController = TextEditingController();
  final _programController = TextEditingController();
  String _selectedCategory = 'Alle';
  late List<Song> _songs;
  List<Song>? _pendingSongs;
  bool _updateBusy = false;
  String _updateStatus = '';

  Future<void> _checkUpdates() async {
    if (_updateBusy) return;
    setState(() {
      _updateBusy = true;
      _updateStatus = 'Lieddaten werden geprüft …';
    });
    try {
      final downloaded = await SongUpdates.download();
      final merged = SongUpdates.preservePersonal(_songs, downloaded);
      final changed = SongUpdates.encode(merged) != SongUpdates.encode(_songs);
      if (mounted)
        setState(() {
          _pendingSongs = changed ? merged : null;
          _updateStatus = changed
              ? 'Neue oder geänderte Lieddaten verfügbar.'
              : 'Deine Lieddaten sind aktuell.';
        });
    } catch (_) {
      if (mounted)
        setState(
              () => _updateStatus =
          'Prüfung nicht möglich. Deine gespeicherten Lieder bleiben verfügbar.',
        );
    } finally {
      if (mounted) setState(() => _updateBusy = false);
    }
  }

  Future<void> _installUpdate() async {
    final pending = _pendingSongs;
    if (_updateBusy || pending == null) return;
    setState(() => _updateBusy = true);
    try {
      await LyricsStore.instance.load();
      final installed = SongUpdates.preservePersonal(_songs, pending);
      await SongUpdates.saveCache(installed);
      if (mounted)
        setState(() {
          _songs = installed;
          _pendingSongs = null;
          _selectedCategory = 'Alle';
          _updateStatus =
          'Lieddaten gespeichert und offline verfügbar. Persönliche Versionen bleiben erhalten.';
        });
    } catch (_) {
      if (mounted)
        setState(
              () => _updateStatus =
          'Speichern fehlgeschlagen. Die bisherige Sammlung bleibt aktiv.',
        );
    } finally {
      if (mounted) setState(() => _updateBusy = false);
    }
  }

  bool _programMenuOpen = false;
  List<String> _program1Numbers = [];
  List<String> _program2Numbers = [];

  static const _program1Key = 'hallerschipper_programm_1';
  static const _program2Key = 'hallerschipper_programm_2';

  @override
  void initState() {
    super.initState();
    _songs = widget.songs;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _checkUpdates();
    });
    _loadSavedPrograms();
    LyricsStore.instance.addListener(_lyricsChanged);
    LyricsStore.instance.load().catchError((Object _) {});
  }

  void _lyricsChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadSavedPrograms() async {
    final prefs = await SharedPreferences.getInstance();
    final p1 = prefs.getStringList(_program1Key) ?? <String>[];
    final p2 = prefs.getStringList(_program2Key) ?? <String>[];

    if (!mounted) return;
    setState(() {
      _program1Numbers = p1;
      _program2Numbers = p2;
    });
  }

  Future<void> _saveProgramNumbers(int slot, List<String> numbers) async {
    final prefs = await SharedPreferences.getInstance();
    if (slot == 1) {
      await prefs.setStringList(_program1Key, numbers);
      if (!mounted) return;
      setState(() => _program1Numbers = List<String>.from(numbers));
    } else {
      await prefs.setStringList(_program2Key, numbers);
      if (!mounted) return;
      setState(() => _program2Numbers = List<String>.from(numbers));
    }
  }

  Future<void> _clearSavedProgram(int slot) async {
    final prefs = await SharedPreferences.getInstance();
    if (slot == 1) {
      await prefs.remove(_program1Key);
      if (!mounted) return;
      setState(() => _program1Numbers = []);
    } else {
      await prefs.remove(_program2Key);
      if (!mounted) return;
      setState(() => _program2Numbers = []);
    }
  }

  List<String> get _categories {
    final categories =
    _songs
        .map((song) => song.category)
        .where((category) => category.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return ['Alle', ...categories];
  }

  List<Song> get _filteredSongs => _songs
      .where((song) {
    final categoryMatches =
        _selectedCategory == 'Alle' || song.category == _selectedCategory;
    return categoryMatches && song.matches(_searchController.text);
  })
      .toList(growable: false);

  @override
  void dispose() {
    LyricsStore.instance.removeListener(_lyricsChanged);
    _searchController.dispose();
    _programController.dispose();
    super.dispose();
  }

  Song? _findSongByNumber(String number) {
    final normalized = number.trim().toLowerCase();
    for (final song in _songs) {
      if (song.number.trim().toLowerCase() == normalized) {
        return song;
      }
    }
    return null;
  }

  List<String> _parseProgramNumbers(String input) {
    return input
        .split(RegExp(r'[,;\s]+'))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
  }

  List<Song> _songsForNumbers(
      List<String> numbers, {
        List<String>? missingNumbers,
      }) {
    final result = <Song>[];
    for (final number in numbers) {
      final song = _findSongByNumber(number);
      if (song != null) {
        result.add(song);
      } else {
        missingNumbers?.add(number);
      }
    }
    return result;
  }

  Future<void> _showSavedProgram(int slot) async {
    final numbers = slot == 1 ? _program1Numbers : _program2Numbers;

    if (numbers.isEmpty) {
      await _editSavedProgram(slot);
      return;
    }

    final missingNumbers = <String>[];
    final programSongs = _songsForNumbers(
      numbers,
      missingNumbers: missingNumbers,
    );

    if (programSongs.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Programm $slot enthält keine vorhandenen Liednummern.',
          ),
        ),
      );
      return;
    }

    if (missingNumbers.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Nicht gefunden: ${missingNumbers.join(', ')}'),
          duration: const Duration(seconds: 5),
        ),
      );
    }

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ProgramPage(songs: programSongs, programTitle: 'Programm $slot'),
      ),
    );
  }

  Future<void> _editSavedProgram(int slot) async {
    final savedNumbers = slot == 1 ? _program1Numbers : _program2Numbers;
    _programController.text = savedNumbers.join(', ');

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.library_music_rounded),
            const SizedBox(width: 10),
            Text('Programm $slot speichern'),
          ],
        ),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Gib die Liednummern in der gewünschten Reihenfolge ein.',
              ),
              const SizedBox(height: 8),
              const Text(
                'Beispiel: 12, 45, 188, 189',
                style: TextStyle(color: Color(0xFF607585)),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _programController,
                autofocus: true,
                minLines: 2,
                maxLines: 5,
                decoration: InputDecoration(
                  labelText: 'Liednummern für Programm $slot',
                  hintText: 'z. B. 12, 45, 188, 189',
                  prefixIcon: const Icon(Icons.format_list_numbered_rounded),
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (savedNumbers.isNotEmpty)
            TextButton.icon(
              onPressed: () => Navigator.of(dialogContext).pop('__DELETE__'),
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text('Löschen'),
            ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Abbrechen'),
          ),
          FilledButton.icon(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_programController.text),
            icon: const Icon(Icons.save_rounded),
            label: const Text('Speichern'),
          ),
        ],
      ),
    );

    if (!mounted || result == null) return;

    if (result == '__DELETE__') {
      await _clearSavedProgram(slot);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Programm $slot wurde gelöscht.')));
      return;
    }

    final numbers = _parseProgramNumbers(result);
    if (numbers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bitte mindestens eine Liednummer eingeben.'),
        ),
      );
      return;
    }

    await _saveProgramNumbers(slot, numbers);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Programm $slot wurde gespeichert: ${numbers.join(', ')}',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final songs = _filteredSongs;
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        tooltip: 'Kurzanleitung',
        onPressed: () {
          Navigator.of(
            context,
          ).push(MaterialPageRoute<void>(builder: (_) => const HelpPage()));
        },
        shape: const CircleBorder(),
        child: const Text(
          'i',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
        ),
      ),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 182,
            foregroundColor: Colors.white,
            backgroundColor: const Color(0xFF0A5B9D),
            flexibleSpace: FlexibleSpaceBar(
              background: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF0A5B9D), Color(0xFF0F76C5)],
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black26,
                                blurRadius: 12,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ClipOval(
                            child: Image.asset(
                              'assets/logo.png',
                              width: 72,
                              height: 72,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        const SizedBox(width: 18),
                        const Flexible(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Hallerschipper',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 30,
                                ),
                              ),
                              Text(
                                'Digitale Liedersammlung',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(14, 18, 14, 30),
            sliver: SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 940),
                  child: Card(
                    elevation: 2,
                    margin: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              OutlinedButton.icon(
                                onPressed: _updateBusy ? null : _checkUpdates,
                                icon: const Icon(Icons.refresh),
                                label: const Text('Lieddaten prüfen'),
                              ),
                              if (_pendingSongs != null)
                                FilledButton.icon(
                                  onPressed: _updateBusy
                                      ? null
                                      : _installUpdate,
                                  icon: const Icon(Icons.download),
                                  label: const Text('Lieddaten übernehmen'),
                                ),
                            ],
                          ),
                          if (_updateBusy) const LinearProgressIndicator(),
                          if (_updateStatus.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(_updateStatus),
                            ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _searchController,
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(
                              hintText: 'Lied, Nummer oder Text suchen …',
                              prefixIcon: Icon(Icons.search),
                            ),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            initialValue: _selectedCategory,
                            decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.filter_list),
                              labelText: 'Kategorie',
                            ),
                            items: _categories
                                .map(
                                  (category) => DropdownMenuItem(
                                value: category,
                                child: Text(
                                  category == 'Alle'
                                      ? 'Alle Kategorien'
                                      : category,
                                ),
                              ),
                            )
                                .toList(growable: false),
                            onChanged: (category) {
                              if (category != null) {
                                setState(() => _selectedCategory = category);
                              }
                            },
                          ),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: () {
                              setState(
                                    () => _programMenuOpen = !_programMenuOpen,
                              );
                            },
                            icon: Icon(
                              _programMenuOpen
                                  ? Icons.expand_less_rounded
                                  : Icons.queue_music_rounded,
                            ),
                            label: const Text('Programm'),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 16,
                              ),
                              textStyle: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          AnimatedCrossFade(
                            firstChild: const SizedBox.shrink(),
                            secondChild: Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: Column(
                                children: [
                                  _ProgramSlotButton(
                                    title: 'Programm 1',
                                    numbers: _program1Numbers,
                                    onOpen: () => _showSavedProgram(1),
                                    onEdit: () => _editSavedProgram(1),
                                  ),
                                  const SizedBox(height: 8),
                                  _ProgramSlotButton(
                                    title: 'Programm 2',
                                    numbers: _program2Numbers,
                                    onOpen: () => _showSavedProgram(2),
                                    onEdit: () => _editSavedProgram(2),
                                  ),
                                ],
                              ),
                            ),
                            crossFadeState: _programMenuOpen
                                ? CrossFadeState.showSecond
                                : CrossFadeState.showFirst,
                            duration: const Duration(milliseconds: 220),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
                            child: Text(
                              '${songs.length} Lieder',
                              style: Theme.of(context).textTheme.bodyLarge
                                  ?.copyWith(color: const Color(0xFF496170)),
                            ),
                          ),
                          if (songs.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(28),
                              child: Center(
                                child: Text('Keine passenden Lieder gefunden.'),
                              ),
                            )
                          else
                            ...songs.map(
                                  (song) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Material(
                                  color: const Color(0xFFF7FBFF),
                                  borderRadius: BorderRadius.circular(14),
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 18,
                                      vertical: 8,
                                    ),
                                    title: Text(
                                      song.displayTitle,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    subtitle: song.category.isEmpty
                                        ? null
                                        : Padding(
                                      padding: const EdgeInsets.only(
                                        top: 4,
                                      ),
                                      child: Text(song.category),
                                    ),
                                    trailing: const Icon(
                                      Icons.chevron_right_rounded,
                                    ),
                                    onTap: () => Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) =>
                                            SongDetailPage(song: song),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgramSlotButton extends StatelessWidget {
  const _ProgramSlotButton({
    required this.title,
    required this.numbers,
    required this.onOpen,
    required this.onEdit,
  });

  final String title;
  final List<String> numbers;
  final VoidCallback onOpen;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final isEmpty = numbers.isEmpty;

    return Material(
      color: const Color(0xFFF5FAFE),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          child: Row(
            children: [
              Icon(
                isEmpty
                    ? Icons.playlist_add_rounded
                    : Icons.playlist_play_rounded,
                color: const Color(0xFF0F76C5),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isEmpty
                          ? 'Noch kein Programm gespeichert'
                          : 'Lieder: ${numbers.join(', ')}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF607585),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: isEmpty ? 'Programm speichern' : 'Programm ändern',
                onPressed: onEdit,
                icon: Icon(
                  isEmpty ? Icons.add_circle_outline : Icons.edit_rounded,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ProgramPage extends StatelessWidget {
  const ProgramPage({
    super.key,
    required this.songs,
    this.programTitle = 'Programm',
  });

  final List<Song> songs;
  final String programTitle;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(programTitle),
        backgroundColor: const Color(0xFF0F76C5),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(14, 18, 14, 36),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 940),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  elevation: 2,
                  margin: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.queue_music_rounded,
                              color: Color(0xFF0F76C5),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              programTitle,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF0B4F88),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${songs.length} Lieder • Reihenfolge: '
                              '${songs.map((song) => song.number).join(' – ')}',
                          style: const TextStyle(
                            color: Color(0xFF566E7D),
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                ...songs.asMap().entries.map((entry) {
                  final index = entry.key;
                  final song = entry.value;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Card(
                      elevation: 2,
                      margin: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CircleAvatar(
                                  backgroundColor: const Color(0xFFE8F3FC),
                                  foregroundColor: const Color(0xFF0B4F88),
                                  child: Text(
                                    '${index + 1}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        song.displayTitle,
                                        style: const TextStyle(
                                          fontSize: 23,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFF0B4F88),
                                        ),
                                      ),
                                      if (song.category.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          song.category,
                                          style: const TextStyle(
                                            color: Color(0xFF607585),
                                            fontSize: 15,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 28),
                            LyricsPanel(song: song),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF0F76C5);
    const darkBlue = Color(0xFF0B4F88);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kurzanleitung'),
        backgroundColor: blue,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(14, 18, 14, 36),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 940),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  elevation: 2,
                  margin: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: Color(0xFFE8F3FC),
                              foregroundColor: darkBlue,
                              child: Text(
                                'i',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Hallerschipper-App',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  color: darkBlue,
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Kurzanleitung für Sängerinnen und Sänger',
                          style: TextStyle(
                            fontSize: 16,
                            color: Color(0xFF566E7D),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const _HelpSection(
                  icon: Icons.download_rounded,
                  title: '1. App installieren',
                  text:
                  'QR-Code bzw. Downloadlink öffnen, die Datei app-release.apk '
                      'herunterladen und auf dem Android-Smartphone oder Tablet '
                      'installieren. Falls Android nachfragt, die Installation aus '
                      'dieser Quelle erlauben.',
                ),
                const _HelpSection(
                  icon: Icons.search_rounded,
                  title: '2. Lied suchen',
                  text:
                  'In der Suchleiste nach Liednummer, Titel oder einem Begriff '
                      'aus dem Liedtext suchen. Das gewünschte Lied antippen, um den '
                      'vollständigen Liedtext anzuzeigen.',
                ),
                const _HelpSection(
                  icon: Icons.filter_list_rounded,
                  title: '3. Kategorien verwenden',
                  text:
                  'Mit dem Kategorie-Filter lässt sich die Liedauswahl eingrenzen. '
                      'So findest du bestimmte Liedgruppen schneller.',
                ),
                const _HelpSection(
                  icon: Icons.queue_music_rounded,
                  title: '4. Programm verwenden',
                  text:
                  'Den Button Programm öffnen. Dort stehen Programm 1 und '
                      'Programm 2 zur Verfügung. Für jedes Programm können '
                      'Liednummern in der gewünschten Reihenfolge eingetragen werden.',
                ),
                const _HelpSection(
                  icon: Icons.save_rounded,
                  title: '5. Programme speichern',
                  text:
                  'Programm 1 und Programm 2 werden auf dem Gerät gespeichert. '
                      'Die Liedfolgen bleiben deshalb auch nach dem Schließen der App '
                      'erhalten und können später wieder geöffnet werden.',
                ),
                const _HelpSection(
                  icon: Icons.system_update_alt_rounded,
                  title: '6. Neue App-Version',
                  text:
                  'Wenn eine neue Version bereitsteht, die aktuelle APK über '
                      'denselben Downloadweg installieren. Die vorhandene App wird '
                      'dabei normalerweise aktualisiert.',
                ),
                const SizedBox(height: 8),
                Card(
                  color: const Color(0xFFEAF5FB),
                  elevation: 0,
                  margin: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(18),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.lightbulb_rounded, color: darkBlue),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Tipp für den Auftritt: Programme vorher zusammenstellen '
                                'und kurz prüfen. Dann stehen die Liedtexte beim Auftritt '
                                'direkt in der richtigen Reihenfolge bereit.',
                            style: TextStyle(
                              fontSize: 16,
                              height: 1.45,
                              color: Color(0xFF17384A),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HelpSection extends StatelessWidget {
  const _HelpSection({
    required this.icon,
    required this.title,
    required this.text,
  });

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: Color(0xFFE8F3FC),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: const Color(0xFF0F76C5)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0B4F88),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    text,
                    style: const TextStyle(
                      fontSize: 16,
                      height: 1.5,
                      color: Color(0xFF223844),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SongDetailPage extends StatelessWidget {
  const SongDetailPage({super.key, required this.song});

  final Song song;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Liedtext'),
        backgroundColor: const Color(0xFF0F76C5),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(14, 18, 14, 36),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 940),
            child: Card(
              elevation: 2,
              margin: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (song.category.isNotEmpty)
                      Chip(
                        label: Text(song.category),
                        backgroundColor: const Color(0xFFE8F3FC),
                        side: BorderSide.none,
                        labelStyle: const TextStyle(color: Color(0xFF0B4F88)),
                      ),
                    const SizedBox(height: 8),
                    Text(
                      song.displayTitle,
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                        color: const Color(0xFF0B4F88),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 18),
                    LyricsPanel(song: song),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Persönliche Liedtexte und Markierungen; die gebündelten Lieddaten bleiben unverändert.
class LyricsStore extends ChangeNotifier {
  static final instance = LyricsStore();
  static const preferencesKey = 'hallerschipper_lyrics_v1';
  Map<String, dynamic> _saved = {};
  Future<void>? _loading;

  String songKey(Song song) =>
      jsonEncode([song.number, song.title, song.category]);

  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final raw = prefs.getString(preferencesKey);
      if (raw != null) {
        _saved = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      }
    } on FormatException {
      _saved = {};
    } on TypeError {
      _saved = {};
    }
    notifyListeners();
  }

  String textFor(Song song) {
    final saved = _saved[songKey(song)];
    return saved is Map && saved['text'] is String
        ? saved['text'] as String
        : song.text;
  }

  List<TextRange> marksFor(Song song) {
    final saved = _saved[songKey(song)];
    if (saved is! Map || saved['marks'] is! List) return [];
    final length = textFor(song).length;
    return mergeMarks(
      (saved['marks'] as List)
          .where(
            (r) =>
        r is List &&
            r.length == 2 &&
            r[0] is int &&
            r[1] is int &&
            r[0] >= 0 &&
            r[1] <= length &&
            r[0] < r[1],
      )
          .map((r) => TextRange(start: r[0] as int, end: r[1] as int))
          .toList(),
    );
  }

  static List<TextRange> mergeMarks(List<TextRange> ranges) {
    final sorted = [...ranges]..sort((a, b) => a.start.compareTo(b.start));
    final merged = <TextRange>[];
    for (final range in sorted) {
      if (merged.isNotEmpty && range.start <= merged.last.end) {
        final previous = merged.removeLast();
        merged.add(
          TextRange(
            start: previous.start,
            end: previous.end > range.end ? previous.end : range.end,
          ),
        );
      } else {
        merged.add(range);
      }
    }
    return merged;
  }

  Future<void> save(Song song, String text, List<TextRange> marks) async {
    await load();
    final updated = Map<String, dynamic>.from(_saved);
    updated[songKey(song)] = {
      'text': text,
      'marks': mergeMarks(marks).map((r) => [r.start, r.end]).toList(),
    };
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(preferencesKey, jsonEncode(updated))) {
      throw StateError('Liedtext konnte nicht gespeichert werden.');
    }
    _saved = updated;
    notifyListeners();
  }
}

class LyricsPanel extends StatefulWidget {
  const LyricsPanel({super.key, required this.song});
  final Song song;
  @override
  State<LyricsPanel> createState() => _LyricsPanelState();
}

class _LyricsPanelState extends State<LyricsPanel> {
  final _controller = TextEditingController();
  final _store = LyricsStore.instance;
  bool _editing = false;
  bool _saving = false;
  bool _ready = false;
  String _status = '';
  TextSelection? _selection;

  @override
  void initState() {
    super.initState();
    _store.addListener(_refresh);
    _prepare();
  }

  Future<void> _prepare() async {
    try {
      await _store.load();
      if (mounted) setState(() => _ready = true);
    } catch (_) {
      if (mounted) {
        setState(
              () => _status =
          'Lokaler Speicher konnte nicht geladen werden. Bitte öffne das Lied erneut.',
        );
      }
    }
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _store.removeListener(_refresh);
    _controller.dispose();
    super.dispose();
  }

  void _startEditing() {
    _controller.text = _store.textFor(widget.song);
    setState(() {
      _editing = true;
      _selection = null;
      _status = '';
    });
  }

  Future<void> _saveText() async {
    final text = _controller.text;
    final changed = text != _store.textFor(widget.song);
    final hadMarks = _store.marksFor(widget.song).isNotEmpty;
    setState(() => _saving = true);
    try {
      await _store.save(
        widget.song,
        text,
        changed ? [] : _store.marksFor(widget.song),
      );
      if (!mounted) return;
      setState(() {
        _editing = false;
        _selection = null;
        _status =
        'Liedtext auf diesem Gerät gespeichert.${changed && hadMarks ? ' Bitte markiere den geänderten Text erneut.' : ''}';
      });
    } catch (_) {
      if (mounted) {
        setState(
              () => _status =
          'Speichern nicht möglich. Dein Entwurf bleibt im Textfeld.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _changeMarks(String action, [TextSelection? selection]) async {
    if (_saving) return;
    final text = _store.textFor(widget.song);
    final selected = selection ?? _selection;
    if (action != 'clear' &&
        (selected == null ||
            !selected.isValid ||
            selected.isCollapsed ||
            selected.end > text.length)) {
      setState(() => _status = 'Bitte zuerst Wörter im Liedtext auswählen.');
      return;
    }
    var marks = _store.marksFor(widget.song);
    if (action == 'clear') {
      marks = [];
    } else if (action == 'mark') {
      marks = LyricsStore.mergeMarks([
        ...marks,
        TextRange(start: selected!.start, end: selected.end),
      ]);
    } else {
      final start = selected!.start;
      final end = selected.end;
      marks = marks.expand((r) {
        if (r.end <= start || r.start >= end) return [r];
        return [
          if (r.start < start) TextRange(start: r.start, end: start),
          if (r.end > end) TextRange(start: end, end: r.end),
        ];
      }).toList();
    }
    setState(() => _saving = true);
    try {
      await _store.save(widget.song, text, marks);
      if (mounted) {
        setState(() {
          _selection = null;
          _status = 'Markierungen auf diesem Gerät gespeichert.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
              () => _status =
          'Markierungen konnten nicht gespeichert werden. Bitte versuche es erneut.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  TextSpan _markedText() {
    final text = _store.textFor(widget.song);
    final spans = <TextSpan>[];
    var offset = 0;
    for (final range in _store.marksFor(widget.song)) {
      spans.add(TextSpan(text: text.substring(offset, range.start)));
      spans.add(
        TextSpan(
          text: text.substring(range.start, range.end),
          style: const TextStyle(backgroundColor: Color(0xFFFFEB79)),
        ),
      );
      offset = range.end;
    }
    spans.add(TextSpan(text: text.substring(offset)));
    return TextSpan(children: spans);
  }

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontSize: 20,
      height: 1.65,
      color: Color(0xFF112233),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!_ready)
          const LinearProgressIndicator()
        else if (_editing) ...[
          TextField(
            controller: _controller,
            minLines: 8,
            maxLines: null,
            readOnly: _saving,
            style: style,
            decoration: const InputDecoration(
              labelText: 'Liedtext bearbeiten',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: _saving ? null : _saveText,
                child: const Text('💾 Speichern'),
              ),
              OutlinedButton(
                onPressed: _saving
                    ? null
                    : () => setState(() {
                  _editing = false;
                  _controller.clear();
                  _status = '';
                  _selection = null;
                }),
                child: const Text('❌ Abbrechen'),
              ),
            ],
          ),
        ] else ...[
          const Text(
            'Wörter länger berühren und auswählen. Dann „Markieren“ drücken.',
            style: TextStyle(color: Color(0xFF496170)),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: _saving ? null : () => _changeMarks('mark'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFFFEB79),
                  foregroundColor: const Color(0xFF112233),
                ),
                child: const Text('🖍️ Markieren'),
              ),
              OutlinedButton(
                onPressed: _saving ? null : () => _changeMarks('remove'),
                child: const Text('Markierung entfernen'),
              ),
              if (_store.marksFor(widget.song).isNotEmpty)
                TextButton(
                  onPressed: _saving ? null : () => _changeMarks('clear'),
                  child: const Text('Alle Markierungen entfernen'),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (_store.textFor(widget.song).isEmpty)
            const Text('Kein Text vorhanden.', style: style)
          else
            SelectableText.rich(
              _markedText(),
              style: style,
              onSelectionChanged: (selection, cause) {
                if (!selection.isCollapsed) {
                  _selection = selection;
                } else if (cause == SelectionChangedCause.tap) {
                  _selection = null;
                }
              },
              contextMenuBuilder: (context, state) {
                final selection = state.textEditingValue.selection;
                return AdaptiveTextSelectionToolbar.buttonItems(
                  anchors: state.contextMenuAnchors,
                  buttonItems: [
                    ...state.contextMenuButtonItems,
                    if (!selection.isCollapsed) ...[
                      ContextMenuButtonItem(
                        label: '🖍️ Markieren',
                        onPressed: () {
                          state.hideToolbar();
                          _changeMarks('mark', selection);
                        },
                      ),
                      ContextMenuButtonItem(
                        label: 'Markierung entfernen',
                        onPressed: () {
                          state.hideToolbar();
                          _changeMarks('remove', selection);
                        },
                      ),
                    ],
                  ],
                );
              },
            ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _saving ? null : _startEditing,
            child: const Text('✏️ Liedtext bearbeiten'),
          ),
        ],
        if (_status.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              _status,
              style: const TextStyle(color: Color(0xFF496170)),
            ),
          ),
      ],
    );
  }
}

// Only data from this fixed public HTTPS endpoint is accepted. Never eval JS.
class SongUpdates {
  static final source = Uri.parse(
    'https://raw.githubusercontent.com/fs-appentwickler/hallerschipper-app/main/songs.js',
  );
  static const cacheKey = 'hallerschipper_song_catalog_v1';
  static const maxBytes = 5 * 1024 * 1024;

  static String encode(List<Song> songs) => jsonEncode(
    songs
        .map(
          (s) => {
        'nr': s.number,
        'title': s.title,
        'category': s.category,
        'text': s.text,
      },
    )
        .toList(),
  );

  static List<Song> parseJson(String raw) {
    final data = jsonDecode(raw);
    if (data is! List || data.isEmpty || data.length > 10000) {
      throw const FormatException('Ungültige Liedliste');
    }
    final keys = <String>{};
    return data
        .map((row) {
      if (row is! Map<String, dynamic> ||
          [
            'nr',
            'title',
            'category',
            'text',
          ].any((k) => row[k] is! String)) {
        throw const FormatException('Ungültige Liedfelder');
      }
      final song = Song.fromJson(row);
      if (song.title.isEmpty ||
          song.text.isEmpty ||
          !keys.add(LyricsStore.instance.songKey(song))) {
        throw const FormatException(
          'Leeres oder doppelt zugeordnetes Lied',
        );
      }
      return song;
    })
        .toList(growable: false);
  }

  static List<Song> parseJavaScript(String raw) {
    // Confirmed repository format: const SONGS = <strict JSON array>;
    // No scripts, comments, functions or alternative assignments are accepted.
    final match = RegExp(
      r'^\s*const\s+SONGS\s*=\s*(\[[\s\S]*\])\s*;\s*$',
    ).firstMatch(raw);
    if (match == null)
      throw const FormatException('Unerwartetes songs.js-Format');
    return parseJson(match.group(1)!);
  }

  static Future<List<Song>> download() async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      return await (() async {
        final request = await client.getUrl(source);
        request.followRedirects = false;
        request.headers.set(HttpHeaders.acceptHeader, 'text/plain');
        request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
        final response = await request.close();
        if (response.statusCode != 200 || response.contentLength > maxBytes) {
          throw const FormatException('Download abgelehnt');
        }
        final bytes = <int>[];
        await for (final chunk in response) {
          if (bytes.length + chunk.length > maxBytes) {
            throw const FormatException('Datei zu groß');
          }
          bytes.addAll(chunk);
        }
        return parseJavaScript(utf8.decode(bytes, allowMalformed: false));
      })().timeout(const Duration(seconds: 25));
    } finally {
      client.close(force: true);
    }
  }

  static Future<List<Song>> loadCache(List<Song> bundled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(cacheKey);
      if (raw != null && utf8.encode(raw).length <= maxBytes) {
        return parseJson(raw);
      }
    } catch (_) {
      // Invalid cache or unavailable storage: use bundled offline data.
    }
    return bundled;
  }

  static List<Song> preservePersonal(List<Song> old, List<Song> incoming) {
    final result = [...incoming];
    final keys = incoming.map(LyricsStore.instance.songKey).toSet();
    for (final song in old) {
      final key = LyricsStore.instance.songKey(song);
      // Never guess identity from numbers: the repository repeats "00".
      // Keep removed/renamed personal versions under their original exact key.
      if (LyricsStore.instance._saved.containsKey(key) && keys.add(key)) {
        result.add(song);
      }
    }
    return result;
  }

  static Future<void> saveCache(List<Song> songs) async {
    final raw = encode(songs);
    if (utf8.encode(raw).length > maxBytes) {
      throw const FormatException('Sammlung zu groß');
    }
    parseJson(raw);
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(cacheKey, raw)) {
      throw StateError('Cache konnte nicht gespeichert werden');
    }
  }
}
