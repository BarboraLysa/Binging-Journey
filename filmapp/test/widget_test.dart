import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:filmapp/main.dart';
import 'package:flutter/material.dart';


void main() {
  // Setup SQLite FFI before tests
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi; // makes openDatabase() work in tests
  });

  testWidgets('App shows Film Tracker title', (tester) async {
    await tester.pumpWidget(const FilmTrackerApp());

    // Look for the AppBar title
    expect(find.text('Film Tracker'), findsOneWidget);
  });

  testWidgets('FloatingActionButton is present', (tester) async {
    await tester.pumpWidget(const FilmTrackerApp());

    // Look for the "+" button
    expect(find.byIcon(Icons.add), findsOneWidget);
  });
}
