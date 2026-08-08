import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final raw = await rootBundle.loadString('assets/songs.json');
  final decoded = jsonDecode(raw) as List<dynamic>;
  final songs = decoded
      .map((item) => Song.fromJson(item as Map<String, dynamic>))
      .toList(growable: false);
  runApp(HallerschipperApp(songs: songs));
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
        text.toLowerCase().contains(value);
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

  List<String> get _categories {
    final categories =
    widget.songs
        .map((song) => song.category)
        .where((category) => category.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return ['Alle', ...categories];
  }

  List<Song> get _filteredSongs => widget.songs
      .where((song) {
    final categoryMatches =
        _selectedCategory == 'Alle' || song.category == _selectedCategory;
    return categoryMatches && song.matches(_searchController.text);
  })
      .toList(growable: false);

  @override
  void dispose() {
    _searchController.dispose();
    _programController.dispose();
    super.dispose();
  }

  Song? _findSongByNumber(String number) {
    final normalized = number.trim().toLowerCase();
    for (final song in widget.songs) {
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

  Future<void> _openProgramDialog() async {
    _programController.clear();

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.library_music_rounded),
            SizedBox(width: 10),
            Text('Programm erstellen'),
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
                decoration: const InputDecoration(
                  labelText: 'Liednummern',
                  hintText: 'z. B. 12, 45, 188, 189',
                  prefixIcon: Icon(Icons.format_list_numbered_rounded),
                ),
                onSubmitted: (_) =>
                    Navigator.of(dialogContext).pop(_programController.text),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Abbrechen'),
          ),
          FilledButton.icon(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_programController.text),
            icon: const Icon(Icons.playlist_add_check_rounded),
            label: const Text('Programm anzeigen'),
          ),
        ],
      ),
    );

    if (!mounted || result == null || result.trim().isEmpty) return;

    final numbers = _parseProgramNumbers(result);
    final programSongs = <Song>[];
    final missingNumbers = <String>[];

    for (final number in numbers) {
      final song = _findSongByNumber(number);
      if (song != null) {
        programSongs.add(song);
      } else {
        missingNumbers.add(number);
      }
    }

    if (programSongs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Zu den eingegebenen Nummern wurden keine Lieder gefunden.',
          ),
        ),
      );
      return;
    }

    if (missingNumbers.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Nicht gefunden: ${missingNumbers.join(', ')}'),
          duration: const Duration(seconds: 5),
        ),
      );
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProgramPage(songs: programSongs),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final songs = _filteredSongs;
    return Scaffold(
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
                            onPressed: _openProgramDialog,
                            icon: const Icon(Icons.queue_music_rounded),
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

class ProgramPage extends StatelessWidget {
  const ProgramPage({super.key, required this.songs});

  final List<Song> songs;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Programm'),
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
                        const Row(
                          children: [
                            Icon(
                              Icons.queue_music_rounded,
                              color: Color(0xFF0F76C5),
                            ),
                            SizedBox(width: 10),
                            Text(
                              'Liederprogramm',
                              style: TextStyle(
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
                            SelectableText(
                              song.text.isEmpty
                                  ? 'Kein Text gefunden.'
                                  : song.text,
                              style: const TextStyle(
                                fontSize: 20,
                                height: 1.65,
                                color: Color(0xFF112233),
                              ),
                            ),
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
                    SelectableText(
                      song.text.isEmpty ? 'Kein Text gefunden.' : song.text,
                      style: const TextStyle(
                        fontSize: 20,
                        height: 1.65,
                        color: Color(0xFF112233),
                      ),
                    ),
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
