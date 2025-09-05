import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

void main() {
  runApp(const FilmTrackerApp());
}

class FilmTrackerApp extends StatelessWidget {
  const FilmTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BJ Binging Journey',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF121212),
        primaryColor: Colors.deepPurple,
        colorScheme: const ColorScheme.dark(
          primary: Colors.deepPurple,
          secondary: Colors.deepPurpleAccent,
        ),
      ),
      home: const HomePage(),
    );
  }
}

enum MediaKind { movie, series, anime }

class MediaItem {
  final String title;
  final String? year;
  final String? posterUrl;
  final MediaKind kind;

  MediaItem({
    required this.title,
    this.year,
    this.posterUrl,
    required this.kind,
  });
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Database? _db;
  List<Map<String, dynamic>> wishlist = [];
  List<Map<String, dynamic>> watched = [];
  bool showWishlist = true;

  static const _omdbKey = '15c4b99e'; // Replace with your OMDb key

  @override
  void initState() {
    super.initState();
    _initDb();
  }

  Future<void> _initDb() async {
    _db = await openDatabase(
      p.join(await getDatabasesPath(), 'films.db'),
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE films(
            id INTEGER PRIMARY KEY AUTOINCREMENT, 
            title TEXT UNIQUE, 
            status TEXT, 
            rating INTEGER, 
            kind TEXT, 
            year TEXT, 
            posterUrl TEXT
          )
        ''');
      },
      version: 2,
    );
    await _loadFilms();
  }

  Future<void> _loadFilms() async {
    if (_db == null) return;
    final films = await _db!.query('films');
    setState(() {
      wishlist = films
          .where((f) => f['status'] == 'wishlist')
          .toList()
        ..sort((a, b) => (a['title'] as String).compareTo(b['title'] as String));

      watched = films
          .where((f) => f['status'] == 'watched')
          .toList()
        ..sort((a, b) => (a['title'] as String).compareTo(b['title'] as String));
    });
  }

  // ---- Save item with watched-priority check ----
  Future<void> _saveItem(MediaItem item) async {
    if (_db == null) return;

    // Check if item already exists
    final existing = await _db!.query(
      'films',
      where: 'title = ?',
      whereArgs: [item.title],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      final status = existing.first['status'] as String;
      if (status == 'watched') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${item.title} is already in Watched')),
        );
        return; // Do not overwrite watched
      } else if (status == 'wishlist') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${item.title} is already in Wishlist')),
        );
        return; // Already in wishlist
      }
    }

    // Otherwise, insert into wishlist
    await _db!.insert(
      'films',
      {
        'title': item.title,
        'status': 'wishlist',
        'rating': 0,
        'kind': item.kind.name,
        'year': item.year,
        'posterUrl': item.posterUrl,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await _loadFilms();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${item.title} added to Wishlist')),
    );
  }

  Future<void> _markWatched(int id) async {
    if (_db == null) return;
    await _db!.update('films', {'status': 'watched'}, where: 'id = ?', whereArgs: [id]);
    await _loadFilms();
  }

  Future<void> _markUnwatched(int id) async {
    if (_db == null) return;
    await _db!.update('films', {'status': 'wishlist'}, where: 'id = ?', whereArgs: [id]);
    await _loadFilms();
  }

  Future<void> _deleteFilm(int id) async {
    if (_db == null) return;
    await _db!.delete('films', where: 'id = ?', whereArgs: [id]);
    await _loadFilms();
  }

  Future<void> _rateFilm(int id, int rating) async {
    if (_db == null) return;
    await _db!.update('films', {'rating': rating}, where: 'id = ?', whereArgs: [id]);
    await _loadFilms();
  }

  // ---- API search ----
  Future<List<MediaItem>> _searchOmdb(String query, String type) async {
    try {
      final url = Uri.parse(
          'https://www.omdbapi.com/?apikey=$_omdbKey&s=${Uri.encodeComponent(query)}&type=$type');
      final r = await http.get(url);
      if (r.statusCode != 200) return [];
      final data = jsonDecode(r.body) as Map<String, dynamic>;
      if (data['Response'] == 'False' || data['Search'] == null) return [];
      final List results = data['Search'];
      return results.map<MediaItem>((e) {
        return MediaItem(
          title: e['Title'] ?? '',
          year: e['Year']?.toString(),
          posterUrl: (e['Poster'] != null && e['Poster'] != 'N/A')
              ? e['Poster'] as String
              : null,
          kind: type == 'series' ? MediaKind.series : MediaKind.movie,
        );
      }).toList();
    } catch (err) {
      print('OMDb error: $err');
      return [];
    }
  }

  Future<List<MediaItem>> _searchJikan(String query) async {
    try {
      final url = Uri.parse(
          'https://api.jikan.moe/v4/anime?q=${Uri.encodeComponent(query)}&limit=20');
      final r = await http.get(url);
      if (r.statusCode != 200) return [];
      final data = jsonDecode(r.body) as Map<String, dynamic>;
      final List results = (data['data'] as List<dynamic>?) ?? [];
      return results.map<MediaItem>((e) {
        return MediaItem(
          title: (e['title'] ?? '') as String,
          year: (e['year'] != null) ? e['year'].toString() : null,
          posterUrl: (e['images']?['jpg']?['image_url']) as String?,
          kind: MediaKind.anime,
        );
      }).toList();
    } catch (err) {
      print('Jikan error: $err');
      return [];
    }
  }

  // ---- Search popup ----
  void _showSearchDialog() {
    List<MediaItem> localResults = [];
    bool localSearching = false;
    final TextEditingController ctrl = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            Future<void> doSearch(String q) async {
              if (q.trim().isEmpty) return;
              setStateDialog(() => localSearching = true);
              final results = await Future.wait([
                _searchOmdb(q, 'movie'),
                _searchOmdb(q, 'series'),
                _searchJikan(q),
              ]);
              setStateDialog(() {
                localResults = results.expand((r) => r).toList();
                localSearching = false;
              });
            }

            final dialogBg = const Color(0xFF1E1E1E);
            final accent = Colors.deepPurpleAccent;

            return Dialog(
              backgroundColor: dialogBg,
              insetPadding: const EdgeInsets.all(16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Container(
                width: double.infinity,
                height: 520,
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    TextField(
                      controller: ctrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Search movies, shows, anime...',
                        hintStyle: const TextStyle(color: Colors.white54),
                        filled: true,
                        fillColor: const Color(0xFF2A2A2A),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.search),
                          color: accent,
                          onPressed: () => doSearch(ctrl.text),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: doSearch,
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: localSearching
                          ? const Center(child: CircularProgressIndicator())
                          : (localResults.isEmpty
                              ? const Center(
                                  child: Text(
                                    'No results',
                                    style: TextStyle(color: Colors.white54),
                                  ),
                                )
                              : ListView.builder(
                                  itemCount: localResults.length,
                                  itemBuilder: (context, i) {
                                    final it = localResults[i];
                                    return Card(
                                      color: const Color(0xFF2A2A2A),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      margin: const EdgeInsets.symmetric(vertical: 6),
                                      child: ListTile(
                                        leading: it.posterUrl != null
                                            ? ClipRRect(
                                                borderRadius: BorderRadius.circular(6),
                                                child: Image.network(it.posterUrl!,
                                                    width: 50,
                                                    height: 75,
                                                    fit: BoxFit.cover),
                                              )
                                            : const Icon(Icons.movie),
                                        title: Text(
                                          it.title,
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 20,
                                              fontWeight: FontWeight.bold),
                                        ),
                                        subtitle: Text(
                                          '${it.kind.name} · ${it.year ?? ''}',
                                          style: const TextStyle(
                                              color: Colors.white70, fontSize: 16),
                                        ),
                                        trailing: IconButton(
                                          icon: const Icon(Icons.add_circle_outline),
                                          color: accent,
                                          onPressed: () async {
                                            await _saveItem(it);
                                          },
                                        ),
                                      ),
                                    );
                                  },
                                )),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ---- Grouped lists with delete & move buttons ----
  Widget _buildGroupedList(List<Map<String, dynamic>> films, bool watchedList) {
    final movies = films.where((f) => f['kind'] == 'movie').toList();
    final series = films.where((f) => f['kind'] == 'series').toList();
    final anime = films.where((f) => f['kind'] == 'anime').toList();

    Widget buildSection(String title, List<Map<String, dynamic>> items) {
      if (items.isEmpty) return const SizedBox.shrink();
      return ExpansionTile(
        initiallyExpanded: false,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const Divider(color: Colors.white24),
          ],
        ),
        children: items.map((film) {
          return Card(
            color: const Color(0xFF1E1E1E),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
            child: ListTile(
              leading: film['posterUrl'] != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.network(film['posterUrl'],
                          width: 50, height: 75, fit: BoxFit.cover))
                  : const Icon(Icons.movie),
              title: Text(
                film['title'],
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: watchedList
                  ? Text(
                      'Rating: ${film['rating']}',
                      style: const TextStyle(color: Colors.white70, fontSize: 16),
                    )
                  : Text(
                      '${film['year'] ?? ''}',
                      style: const TextStyle(color: Colors.white70, fontSize: 16),
                    ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (watchedList)
                    IconButton(
                      icon: const Icon(Icons.undo),
                      color: Colors.deepPurpleAccent,
                      onPressed: () => _markUnwatched(film['id'] as int),
                    )
                  else
                    IconButton(
                      icon: const Icon(Icons.check),
                      color: Colors.deepPurpleAccent,
                      onPressed: () => _markWatched(film['id'] as int),
                    ),
                  if (watchedList)
                    IconButton(
                      icon: const Icon(Icons.star),
                      color: Colors.yellowAccent,
                      onPressed: () => _showRatingDialog(film['id'] as int),
                    ),
                  IconButton(
                    icon: const Icon(Icons.delete),
                    color: Colors.redAccent,
                    onPressed: () => _deleteFilm(film['id'] as int),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(top: 12),
      children: [
        buildSection("🎬 Movies", movies),
        buildSection("📺 Series", series),
        buildSection("🍥 Anime", anime),
      ],
    );
  }

  Widget _buildWishlist() => _buildGroupedList(wishlist, false);
  Widget _buildWatched() => _buildGroupedList(watched, true);

  void _showRatingDialog(int id) {
    int selectedRating = 0;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: const Text('Rate this',
              style: TextStyle(color: Colors.white, fontSize: 20)),
          content: DropdownButton<int>(
            value: selectedRating,
            dropdownColor: const Color(0xFF1E1E1E),
            items: List.generate(
              6,
              (i) => DropdownMenuItem(
                value: i,
                child: Text(
                  '$i Stars',
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
            ),
            onChanged: (val) => setStateDialog(() => selectedRating = val ?? 0),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _rateFilm(id, selectedRating);
              },
              child: const Text('Save'),
            )
          ],
        ),
      ),
    );
  }

  // ---- Modern header with pill-style tab selector ----
  Widget _buildHeader() {
  return Container(
    padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [
          Colors.black,
          Colors.black.withOpacity(0.95),
        ],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // App name as main header
        const Text(
          "BJ Binging Journey",
          style: TextStyle(
            height: 3,
            fontSize: 35, // larger font for app title
            fontWeight: FontWeight.bold,
            color: Colors.deepPurpleAccent, // accent color for app name
          ),
        ),
        const SizedBox(height: 14), // move pill buttons a bit lower
        // Pill buttons for Wishlist / Watched
        Row(
          children: [
            _pillButton("Wishlist", showWishlist, () {
              setState(() => showWishlist = true);
            }),
            const SizedBox(width: 12),
            _pillButton("Watched", !showWishlist, () {
              setState(() => showWishlist = false);
            }),
          ],
        )
      ],
    ),
  );
}


  Widget _pillButton(String text, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 20),
        decoration: BoxDecoration(
          color: selected ? Colors.deepPurpleAccent : Colors.transparent,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: Colors.deepPurpleAccent.withOpacity(0.7),
            width: 1.5,
          ),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: selected ? Colors.white : Colors.white70,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.deepPurpleAccent,
        child: const Icon(Icons.search),
        onPressed: _showSearchDialog,
      ),
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: showWishlist ? _buildWishlist() : _buildWatched(),
          ),
        ],
      ),
    );
  }
}
