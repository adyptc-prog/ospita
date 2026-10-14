part of '../main.dart';

// Modelul de date: rezervări, tabele, setările botului.

// ─── Model ────────────────────────────────────────────────────────────────────
class Item {
  final String syncId;
  final int number;
  final String name;
  final String description;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final DateTime? warningAt;
  final String? phoneNumber;
  final String? phoneNumber2;
  final String? phoneNumber3;
  // Data de check-in — durata unui sejur variază per rezervare. Poate lipsi
  // la sejururile introduse manual fără check-in (atunci se consideră o
  // noapte înainte de check-out).
  final DateTime? startsAt;
  // Marcaj manual „plată confirmată”. Nu afectează ocuparea (un sejur
  // nevalidat rămâne blocat la fel ca unul validat).
  final bool validated;
  // Rezervare făcută de client prin botul SMS. Telefonul ei e al clientului
  // (pentru anulare/confirmări), nu un destinatar de alerte: la expirare nu
  // primește SMS-ul „EXPIRAT”.
  final bool viaBot;
  // Prezența la programare, confirmată de pensiune după check-out:
  // null = neconfirmată, 'came' = a venit, 'noShow' = nu a venit.
  final String? attendance;
  // „Nu a venit” pus automat (neconfirmată în 24h), nu de pensiune.
  final bool attendanceAuto;
  // Ultima modificare făcută din aplicație (pe oricare telefon). La
  // sincronizare, o versiune mai veche decât cea locală e ignorată — SMS-urile
  // pot sosi în altă ordine decât au fost trimise.
  final DateTime? updatedAt;

  const Item({
    required this.syncId,
    required this.number,
    required this.name,
    required this.description,
    required this.createdAt,
    this.expiresAt,
    this.warningAt,
    this.phoneNumber,
    this.phoneNumber2,
    this.phoneNumber3,
    this.startsAt,
    this.validated = false,
    this.viaBot = false,
    this.attendance,
    this.attendanceAuto = false,
    this.updatedAt,
  });

  // Telefonul după care e recunoscut clientul (neprezentări).
  String? get clientPhone =>
      noShowClientPhone(phoneNumber, name, description);

  List<String> get phones => [
        if (phoneNumber  != null && phoneNumber!.isNotEmpty)  phoneNumber!,
        if (phoneNumber2 != null && phoneNumber2!.isNotEmpty) phoneNumber2!,
        if (phoneNumber3 != null && phoneNumber3!.isNotEmpty) phoneNumber3!,
      ];

  Item copyWith({
    String? syncId,
    int? number,
    String? name,
    String? description,
    DateTime? createdAt,
    DateTime? expiresAt,
    bool clearExpiry = false,
    DateTime? warningAt,
    bool clearWarning = false,
    String? phoneNumber,
    bool clearPhone = false,
    String? phoneNumber2,
    bool clearPhone2 = false,
    String? phoneNumber3,
    bool clearPhone3 = false,
    DateTime? startsAt,
    bool clearStartsAt = false,
    bool? validated,
    String? attendance,
    bool clearAttendance = false,
    bool? attendanceAuto,
    DateTime? updatedAt,
  }) {
    return Item(
      syncId:       syncId       ?? this.syncId,
      number:       number       ?? this.number,
      name:         name         ?? this.name,
      description:  description  ?? this.description,
      createdAt:    createdAt    ?? this.createdAt,
      expiresAt:    clearExpiry   ? null : (expiresAt   ?? this.expiresAt),
      warningAt:    clearWarning  ? null : (warningAt   ?? this.warningAt),
      phoneNumber:  clearPhone    ? null : (phoneNumber  ?? this.phoneNumber),
      phoneNumber2: clearPhone2   ? null : (phoneNumber2 ?? this.phoneNumber2),
      phoneNumber3: clearPhone3   ? null : (phoneNumber3 ?? this.phoneNumber3),
      startsAt:     clearStartsAt ? null : (startsAt ?? this.startsAt),
      validated:    validated ?? this.validated,
      viaBot:       viaBot,
      attendance:   clearAttendance ? null : (attendance ?? this.attendance),
      attendanceAuto: clearAttendance
          ? false
          : (attendanceAuto ?? (attendance != null ? false : this.attendanceAuto)),
      updatedAt:    updatedAt ?? this.updatedAt,
    );
  }

  // Persistență locală (JSON complet)
  Map<String, dynamic> toJson() => {
        'syncId':       syncId,
        'number':       number,
        'name':         name,
        'description':  description,
        'createdAt':    createdAt.toIso8601String(),
        'expiresAt':    expiresAt?.toIso8601String(),
        'warningAt':    warningAt?.toIso8601String(),
        'phoneNumber':  phoneNumber,
        'phoneNumber2': phoneNumber2,
        'phoneNumber3': phoneNumber3,
        'startsAt':     startsAt?.toIso8601String(),
        'validated':    validated,
        'viaBot':       viaBot,
        'attendance':   attendance,
        if (attendanceAuto) 'attendanceAuto': true,
        if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
      };

  factory Item.fromJson(Map<String, dynamic> json) => Item(
        // Migrare: dacă syncId lipsește (date vechi), generăm unul nou
        syncId:       (json['syncId'] as String?) ?? _generateSyncId(),
        number:       json['number']      as int,
        name:         json['name']        as String,
        description:  json['description'] as String,
        createdAt:    DateTime.parse(json['createdAt'] as String),
        expiresAt:    json['expiresAt']  != null
            ? DateTime.parse(json['expiresAt']  as String) : null,
        warningAt:    json['warningAt']  != null
            ? DateTime.parse(json['warningAt']  as String) : null,
        phoneNumber:  json['phoneNumber']  as String?,
        phoneNumber2: json['phoneNumber2'] as String?,
        phoneNumber3: json['phoneNumber3'] as String?,
        // Migrare: date vechi nu au aceste câmpuri — implicit null/false.
        startsAt:     json['startsAt'] != null
            ? DateTime.parse(json['startsAt'] as String) : null,
        validated:    json['validated'] as bool? ?? false,
        viaBot:       json['viaBot'] as bool? ?? false,
        attendance:   json['attendance'] as String?,
        attendanceAuto: json['attendanceAuto'] == true,
        updatedAt: json['updatedAt'] != null
            ? DateTime.tryParse(json['updatedAt'] as String) : null,
      );

  // Format compact pentru SMS (câmpuri opționale omise dacă sunt goale/null)
  Map<String, dynamic> toSyncJson() => {
        's': syncId,
        'n': name,
        if (description.isNotEmpty) 'd': description,
        'c': _isoShort(createdAt),
        if (expiresAt != null) 'e': _isoShort(expiresAt!),
        if (warningAt != null) 'w': _isoShort(warningAt!),
        if (phoneNumber  != null && phoneNumber!.isNotEmpty)  'p1': phoneNumber,
        if (phoneNumber2 != null && phoneNumber2!.isNotEmpty) 'p2': phoneNumber2,
        if (phoneNumber3 != null && phoneNumber3!.isNotEmpty) 'p3': phoneNumber3,
        if (startsAt != null) 'st': _isoShort(startsAt!),
        if (validated) 'v': true,
        if (viaBot) 'b': true,
        if (attendance == kCame) 'a': 'c',
        if (attendance == kNoShow) 'a': 'n',
        if (updatedAt != null) 'u': updatedAt!.millisecondsSinceEpoch,
      };

  factory Item.fromSyncJson(Map<String, dynamic> j) => Item(
        syncId:       j['s'] as String,
        number:       0, // numărul local se asignează la merge
        name:         j['n'] as String,
        description:  (j['d'] as String?) ?? '',
        createdAt:    DateTime.parse(j['c'] as String),
        expiresAt:    j['e'] != null ? DateTime.parse(j['e'] as String) : null,
        warningAt:    j['w'] != null ? DateTime.parse(j['w'] as String) : null,
        phoneNumber:  j['p1'] as String?,
        phoneNumber2: j['p2'] as String?,
        phoneNumber3: j['p3'] as String?,
        startsAt:     j['st'] != null ? DateTime.parse(j['st'] as String) : null,
        validated:    j['v'] == true,
        viaBot:       j['b'] == true,
        attendance:   switch (j['a']) { 'c' => kCame, 'n' => kNoShow, _ => null },
        updatedAt: j['u'] is int
            ? DateTime.fromMillisecondsSinceEpoch(j['u'] as int) : null,
      );

  /// [incoming] e o versiune mai veche decât aceasta (ambele cu marcaj).
  bool isNewerThan(Item incoming) =>
      updatedAt != null &&
      incoming.updatedAt != null &&
      incoming.updatedAt!.isBefore(updatedAt!);
}

// ─── Buffer înregistrări șterse (6 luni) ─────────────────────────────────────
class DeletedItem {
  final Item item;
  final DateTime deletedAt;

  const DeletedItem({required this.item, required this.deletedAt});

  bool get isExpiredFromBuffer => deletedAt.isBefore(
        DateTime.now().subtract(const Duration(days: 180)));

  Map<String, dynamic> toJson() => {
        'item': item.toJson(),
        'deletedAt': deletedAt.toIso8601String(),
      };

  factory DeletedItem.fromJson(Map<String, dynamic> json) => DeletedItem(
        item: Item.fromJson(json['item'] as Map<String, dynamic>),
        deletedAt: DateTime.parse(json['deletedAt'] as String),
      );
}

// fromPartner: mesajul a venit de la partenerul de sincronizare (nu se
// retrimite). Altfel e o schimbare locală făcută nativ (botul de rezervări,
// anularea automată) pe care partenerul trebuie s-o primească.
// forwarded: schimbarea locală a fost deja trimisă partenerului nativ.
typedef SyncQueueEntry = ({
  String id,
  String boardId,
  String msg,
  bool fromPartner,
  bool forwarded,
});

typedef ReportEntry = ({Item item, DateTime? deletedAt});

enum SortColumn { number, name, description, createdAt, expiresAt }

// ─── Tabel (board) ─────────────────────────────────────────────────────────────
class Board {
  final String id;
  final String name;

  const Board({required this.id, required this.name});

  Board copyWith({String? name}) => Board(id: id, name: name ?? this.name);

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  factory Board.fromJson(Map<String, dynamic> json) => Board(
        id:   json['id']   as String,
        name: json['name'] as String,
      );
}

// ─── Setări rezervări prin SMS (per tabel) ────────────────────────────────────
/// Orele sejururilor care încep într-o anumită zi a săptămânii (minute de la
/// miezul nopții): check-in în ziua sosirii, check-out în ziua plecării.
class DayHours {
  final int checkInMin;
  final int checkOutMin;
  const DayHours(this.checkInMin, this.checkOutMin);

  @override
  bool operator ==(Object other) =>
      other is DayHours &&
      other.checkInMin == checkInMin &&
      other.checkOutMin == checkOutMin;

  @override
  int get hashCode => Object.hash(checkInMin, checkOutMin);
}

const _kDefaultDayHours = DayHours(14 * 60, 11 * 60);

/// „840” → „14:00”.
String formatMinutesOfDay(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
    '${(minutes % 60).toString().padLeft(2, '0')}';

/// Orele pe zile ↔ textul salvat („1:840-660,5:960-720”). Intrările invalide
/// sunt sărite. Aceeași regulă ca parseWorkHours din BookingSettings.kt.
String encodeWorkHours(Map<int, DayHours> hours) => (hours.keys.toList()..sort())
    .map((d) => '$d:${hours[d]!.checkInMin}-${hours[d]!.checkOutMin}')
    .join(',');

Map<int, DayHours> parseWorkHours(String raw) {
  final result = <int, DayHours>{};
  for (final part in raw.split(',')) {
    final m = RegExp(r'^(\d+):(\d+)-(\d+)$').firstMatch(part.trim());
    if (m == null) continue;
    final day = int.parse(m[1]!);
    final checkIn = int.parse(m[2]!);
    final checkOut = int.parse(m[3]!);
    if (day < 1 || day > 7 || checkIn >= 24 * 60 || checkOut >= 24 * 60) {
      continue;
    }
    result[day] = DayHours(checkIn, checkOut);
  }
  return result;
}

class BookingSettingsData {
  final bool enabled;
  // Zilele în care se acceptă check-in (DateTime.weekday: 1=luni ..
  // 7=duminică), fiecare cu orele ei; în zilele care lipsesc nu se face
  // check-in.
  final Map<int, DayHours> workHours;
  // Cont bancar (IBAN) afișat clientului în SMS-ul „așteaptă validarea
  // plății”. Gol dacă nu a fost completat.
  final String iban;

  const BookingSettingsData({
    required this.enabled,
    required this.workHours,
    this.iban = '',
  });

  static const defaults = BookingSettingsData(
    enabled: false,
    workHours: {
      1: _kDefaultDayHours, 2: _kDefaultDayHours, 3: _kDefaultDayHours,
      4: _kDefaultDayHours, 5: _kDefaultDayHours, 6: _kDefaultDayHours,
      7: _kDefaultDayHours,
    },
    iban: '',
  );

  /// Orele propuse pentru o sosire în ziua [weekday]; pentru o zi fără
  /// check-in (sau necunoscută), cele ale primei zile cu check-in.
  DayHours hoursFor(int? weekday) {
    final h = workHours[weekday];
    if (h != null) return h;
    if (workHours.isEmpty) return _kDefaultDayHours;
    return workHours[workHours.keys.reduce((a, b) => a < b ? a : b)]!;
  }

  BookingSettingsData copyWith({
    bool? enabled,
    Map<int, DayHours>? workHours,
    String? iban,
  }) =>
      BookingSettingsData(
        enabled:   enabled   ?? this.enabled,
        workHours: workHours ?? this.workHours,
        iban:      iban      ?? this.iban,
      );
}

// Setările salvate în formatul vechi: aceleași ore în toate zilele, mai puțin
// cele fără check-in.
Map<int, DayHours> _legacyWorkHours(SharedPreferences prefs, String boardId) {
  final closed = (prefs.getString(_closedDaysKeyFor(boardId)) ?? '')
      .split(',')
      .map((s) => int.tryParse(s.trim()))
      .whereType<int>()
      .toSet();
  final hours = DayHours(
    prefs.getInt(_workStartKeyFor(boardId)) ?? _kDefaultDayHours.checkInMin,
    prefs.getInt(_workEndKeyFor(boardId)) ?? _kDefaultDayHours.checkOutMin,
  );
  return {
    for (var d = 1; d <= 7; d++)
      if (!closed.contains(d)) d: hours,
  };
}

Future<BookingSettingsData> _loadBookingSettings(
    SharedPreferences prefs, String boardId) async {
  final hoursStr = prefs.getString(_workHoursKeyFor(boardId));
  return BookingSettingsData(
    enabled: prefs.getBool(_bookingEnabledKeyFor(boardId)) ??
        BookingSettingsData.defaults.enabled,
    workHours: hoursStr != null
        ? parseWorkHours(hoursStr)
        : _legacyWorkHours(prefs, boardId),
    iban: prefs.getString(_ibanKeyFor(boardId)) ?? '',
  );
}

Future<void> _saveBookingSettings(String boardId, BookingSettingsData s) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_bookingEnabledKeyFor(boardId), s.enabled);
  await prefs.setString(_workHoursKeyFor(boardId), encodeWorkHours(s.workHours));
  await prefs.setString(_ibanKeyFor(boardId), s.iban);
}

// Graficul orelor: câte un rând pe zi, pe o axă de 24h, cu un marcaj la ora
// de check-out și unul la ora de check-in ale sejururilor care încep în acea zi.
class _WorkHoursChart extends StatelessWidget {
  final Map<int, String> dayLabels;
  final Map<int, DayHours> workHours;
  final void Function(int day) onTapDay;

  const _WorkHoursChart({
    required this.dayLabels,
    required this.workHours,
    required this.onTapDay,
  });

  static const _labelWidth = 30.0;
  static const _hoursWidth = 104.0;
  static const _markWidth = 5.0;
  static final _checkInColor = Colors.green.shade600;
  static final _checkOutColor = Colors.orange.shade700;

  Widget _mark(double trackWidth, int minutes, Color color) => Positioned(
        left: (trackWidth - _markWidth) * minutes / (24 * 60),
        width: _markWidth,
        top: 0,
        bottom: 0,
        child: Container(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );

  Widget _legend(Color color, String text, TextStyle style) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 8, height: 8, color: color),
          const SizedBox(width: 3),
          Text(text, style: style),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final axisStyle = TextStyle(fontSize: 10, color: Colors.grey.shade600);

    return Column(
      children: [
        for (final e in dayLabels.entries)
          InkWell(
            onTap: () => onTapDay(e.key),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  SizedBox(
                    width: _labelWidth,
                    child: Text(e.value,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                  Expanded(
                    child: LayoutBuilder(builder: (_, c) {
                      final h = workHours[e.key];
                      return Stack(
                        children: [
                          Container(
                            height: 16,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          if (h != null) ...[
                            _mark(c.maxWidth, h.checkOutMin, _checkOutColor),
                            _mark(c.maxWidth, h.checkInMin, _checkInColor),
                          ],
                        ],
                      );
                    }),
                  ),
                  SizedBox(
                    width: _hoursWidth,
                    child: Text(
                      workHours[e.key] == null
                          ? tr('fără check-in', 'no check-in')
                          : '${formatMinutesOfDay(workHours[e.key]!.checkInMin)} → '
                              '${formatMinutesOfDay(workHours[e.key]!.checkOutMin)}',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          fontSize: 12,
                          color: workHours[e.key] == null
                              ? Colors.grey.shade500
                              : Colors.black87),
                    ),
                  ),
                ],
              ),
            ),
          ),
        Padding(
          padding:
              const EdgeInsets.only(left: _labelWidth, right: _hoursWidth),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('00:00', style: axisStyle),
              _legend(_checkInColor, 'check-in', axisStyle),
              _legend(_checkOutColor, 'check-out', axisStyle),
              Text('24:00', style: axisStyle),
            ],
          ),
        ),
      ],
    );
  }
}

// Numărul de tabele (categorii de servicii). ID-urile alarmelor includ indexul
// tabelului (index × 10.000.000 pentru SMS) — cu 10 tabele rămân sub
// 100.000.000, departe de plaja reminderelor botului (BotReminders.kt).
const kBoardCount = 10;

/// Completează lista de tabele până la [kBoardCount] (b1..b10), fără să
/// atingă tabelele existente (nume, ordine, date). Null dacă nu lipsește nimic.
List<Board>? completeBoards(List<Board> boards) {
  final ids = boards.map((b) => b.id).toSet();
  final added = [
    for (var i = 1; i <= kBoardCount; i++)
      if (!ids.contains('b$i')) Board(id: 'b$i', name: tr('Tabel $i', 'Table $i')),
  ];
  if (added.isEmpty || boards.length >= kBoardCount) return null;
  return [...boards, ...added.take(kBoardCount - boards.length)];
}

// Încarcă lista de tabele; la prima rulare după actualizare, migrează datele
// vechi (un singur tabel implicit) în „Tabel 1”. Instalările cu mai puține
// tabele (versiunile cu 3) primesc restul, goale, până la [kBoardCount].
Future<List<Board>> _loadOrMigrateBoards(SharedPreferences prefs) async {
  final boardsJson = prefs.getString(_kBoardsKey);
  if (boardsJson != null) {
    final boards = (jsonDecode(boardsJson) as List<dynamic>)
        .map((e) => Board.fromJson(e as Map<String, dynamic>))
        .toList();
    final completed = completeBoards(boards);
    if (completed == null) return boards;
    await prefs.setString(
        _kBoardsKey, jsonEncode(completed.map((b) => b.toJson()).toList()));
    return completed;
  }

  final b1 = Board(id: 'b1', name: tr('Tabel 1', 'Table 1'));
  final boards = completeBoards([b1])!;

  final legacyItems = prefs.getString(_kLegacyItemsKey);
  if (legacyItems != null) {
    await prefs.setString(_itemsKeyFor(b1.id), legacyItems);
    await prefs.remove(_kLegacyItemsKey);
  }
  final legacyNext = prefs.getInt(_kLegacyNextNumberKey);
  if (legacyNext != null) {
    await prefs.setInt(_nextNumberKeyFor(b1.id), legacyNext);
    await prefs.remove(_kLegacyNextNumberKey);
  }
  final legacyDeleted = prefs.getString(_kLegacyDeletedBufferKey);
  if (legacyDeleted != null) {
    await prefs.setString(_deletedBufferKeyFor(b1.id), legacyDeleted);
    await prefs.remove(_kLegacyDeletedBufferKey);
  }
  final legacyPartner = prefs.getString(_kLegacySyncPartnerKey);
  if (legacyPartner != null) {
    await prefs.setString(_syncPartnerKeyFor(b1.id), legacyPartner);
    await prefs.remove(_kLegacySyncPartnerKey);
  }

  await prefs.setString(
      _kBoardsKey, jsonEncode(boards.map((b) => b.toJson()).toList()));
  await prefs.setString(_kActiveBoardKey, b1.id);
  return boards;
}
