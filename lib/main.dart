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
    super.dispose();
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
