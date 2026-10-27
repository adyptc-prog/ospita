import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pensiune_app/main.dart';

// Cinci rezervări de test (tabelul pornește gol la prima instalare).
const _names = ['Ion Popescu', 'Maria Ionescu', 'Andrei Pop', 'Elena Dobre', 'Mihai Radu'];

Map<String, Object> _withItems() => {
      'management_items_b1': jsonEncode([
        for (var i = 0; i < _names.length; i++)
          {
            'syncId': 'test$i',
            'number': i + 1,
            'name': _names[i],
            'description': '',
            'createdAt': '2026-0${i + 1}-01T10:00:00.000',
            'expiresAt': '2030-0${i + 1}-02T11:00:00.000',
          },
      ]),
      'management_next_number_b1': _names.length + 1,
    };

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    try { await NotificationService.init(); } catch (_) {}
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('afișează spinner la pornire apoi tabelul', (tester) async {
    await tester.pumpWidget(const ManagementApp());

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpAndSettle();

    expect(find.text('Ospita'), findsOneWidget);
    expect(find.text('Nr.'), findsOneWidget);
    expect(find.text('Nume'), findsOneWidget);
    expect(find.text('Descriere'), findsOneWidget);
  });

  testWidgets('prima lansare pornește cu tabelul gol', (tester) async {
    await tester.pumpWidget(const ManagementApp());
    await tester.pumpAndSettle();

    expect(find.text('Proiect Alpha'), findsNothing);
    expect(find.text('0 înregistrări'), findsOneWidget);
  });

  testWidgets('rezervările salvate apar în tabel', (tester) async {
    SharedPreferences.setMockInitialValues(_withItems());
    await tester.pumpWidget(const ManagementApp());
    await tester.pumpAndSettle();

    expect(find.text('Ion Popescu'), findsOneWidget);
    expect(find.text('Maria Ionescu'), findsOneWidget);
    expect(find.text('5 înregistrări'), findsOneWidget);
  });

  testWidgets('butonul Adaugă deschide dialogul', (tester) async {
    await tester.pumpWidget(const ManagementApp());
    await tester.pumpAndSettle();

    // Butonul din AppBar are icon Icons.add
    await tester.tap(find.byIcon(Icons.add_circle_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Adaugă înregistrare'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Nume *'), findsOneWidget);
  });

  testWidgets('adăugarea unui item îl include în tabel', (tester) async {
    SharedPreferences.setMockInitialValues(_withItems());
    await tester.pumpWidget(const ManagementApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add_circle_rounded));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Nume *'), 'Test Item');
    // 'Adaugă' apare în AppBar și în dialog; .last = butonul din dialog
    await tester.tap(find.text('Adaugă').last);
    await tester.pumpAndSettle();

    expect(find.text('Test Item'), findsOneWidget);
    expect(find.text('6 înregistrări'), findsOneWidget);
  });

  testWidgets('căutarea filtrează rândurile', (tester) async {
    SharedPreferences.setMockInitialValues(_withItems());
    await tester.pumpWidget(const ManagementApp());
    await tester.pumpAndSettle();

    // Search-ul este ascuns implicit — activăm cu butonul search
    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Andrei');
    await tester.pumpAndSettle();

    expect(find.text('Andrei Pop'), findsOneWidget);
    expect(find.text('Ion Popescu'), findsNothing);
    expect(find.textContaining('1 din 5'), findsOneWidget);
  });

  testWidgets('ștergerea unui item îl elimină din tabel', (tester) async {
    SharedPreferences.setMockInitialValues(_withItems());
    await tester.pumpWidget(const ManagementApp());
    await tester.pumpAndSettle();

    // Butonul de delete poate fi în afara viewport-ului orizontal;
    // scrollăm tabelul la dreapta ca să-l facem vizibil
    await tester.ensureVisible(find.byIcon(Icons.delete_outlined).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.delete_outlined).first);
    await tester.pumpAndSettle();

    // Confirmă ștergerea
    await tester.tap(find.text('Șterge').last);
    await tester.pumpAndSettle();

    expect(find.text('4 înregistrări'), findsOneWidget);
  });

  testWidgets('tabelele pot fi comutate și sunt independente',
      (tester) async {
    SharedPreferences.setMockInitialValues(_withItems());
    await tester.pumpWidget(const ManagementApp());
    await tester.pumpAndSettle();

    // Tabelul activ implicit e „Tabel 1”, cu rezervările de test.
    expect(find.text('Tabel 1'), findsOneWidget);
    expect(find.text('5 înregistrări'), findsOneWidget);

    // Deschidem selectorul de tabele din AppBar.
    await tester.tap(find.text('Tabel 1'));
    await tester.pumpAndSettle();

    expect(find.text('Tabele'), findsOneWidget);
    expect(find.text('Tabel 2'), findsOneWidget);
    expect(find.text('Tabel 3'), findsOneWidget);

    // Comutăm pe „Tabel 2” — trebuie să fie complet gol, independent de Tabel 1.
    await tester.tap(find.text('Tabel 2'));
    await tester.pumpAndSettle();

    expect(find.text('Tabel 2'), findsOneWidget);
    expect(find.text('Ion Popescu'), findsNothing);
    expect(find.text('0 înregistrări'), findsOneWidget);
  });

  testWidgets('al 10-lea tabel e în selector și poate fi folosit',
      (tester) async {
    await tester.pumpWidget(const ManagementApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Tabel 1'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Tabel 10'), 100,
        scrollable: find.descendant(
            of: find.byType(SimpleDialog),
            matching: find.byType(Scrollable)));
    await tester.tap(find.text('Tabel 10'));
    await tester.pumpAndSettle();

    expect(find.text('Tabel 10'), findsOneWidget);
    expect(find.text('0 înregistrări'), findsOneWidget);
  });

  testWidgets('redenumirea unui tabel actualizează selectorul', (tester) async {
    await tester.pumpWidget(const ManagementApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Tabel 1'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Redenumește').first);
    await tester.pumpAndSettle();

    expect(find.text('Redenumește tabelul'), findsOneWidget);
    await tester.enterText(
        find.widgetWithText(TextField, 'Nume tabel'), 'Familie');
    await tester.tap(find.text('Salvează'));
    await tester.pumpAndSettle();

    expect(find.text('Familie'), findsOneWidget);
    expect(find.text('Tabel 1'), findsNothing);
  });

  group('versiunea aplicației', () {
    setUp(() {
      PackageInfo.setMockInitialValues(
        appName: 'Ospita',
        packageName: 'app.sayitapp.pensiune',
        version: '1.0.0',
        buildNumber: '1',
        buildSignature: '',
      );
    });

    testWidgets('apare sub tabel', (tester) async {
      await tester.pumpWidget(const ManagementApp());
      await tester.pumpAndSettle();
      expect(find.text('v1.0.0'), findsOneWidget);
    });

    testWidgets('încape pe un telefon îngust (360 px)', (tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const ManagementApp());
      await tester.pumpAndSettle();
      expect(find.text('v1.0.0'), findsOneWidget);
      expect(tester.takeException(), isNull); // fără RenderFlex overflow
    });
  });

  testWidgets('aplicația de pensiune: check-in/check-out, fără comutator de mod',
      (tester) async {
    await tester.pumpWidget(const ManagementApp());
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.hotel), findsNothing);

    await tester.tap(find.byIcon(Icons.add_circle_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Check-in: nesetat'), findsOneWidget);
    expect(find.text('Check-out: nesetat'), findsOneWidget);
  });
}

