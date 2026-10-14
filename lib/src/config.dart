part of '../main.dart';

// Chei de stocare, constante și funcții ajutătoare comune.

// ─── Constante ───────────────────────────────────────────────────────────────
const _kBoardsKey      = 'management_boards';
const _kActiveBoardKey = 'management_active_board';
const _kSmsTemplateKey = 'sms_template';

// Chei folosite înainte de suportul pentru mai multe tabele — păstrate doar
// pentru migrarea automată a datelor existente în „Tabel 1”.
const _kLegacyItemsKey         = 'management_items';
const _kLegacyNextNumberKey    = 'management_next_number';
const _kLegacyDeletedBufferKey = 'management_deleted_buffer';
const _kLegacySyncPartnerKey   = 'sync_partner_phone';

String _itemsKeyFor(String boardId)         => 'management_items_$boardId';
String _nextNumberKeyFor(String boardId)    => 'management_next_number_$boardId';
String _deletedBufferKeyFor(String boardId) => 'management_deleted_buffer_$boardId';
String _syncPartnerKeyFor(String boardId)   => 'sync_partner_phone_$boardId';
// Codul de împerechere al tabelului — semnează mesajele de sincronizare
// (SyncAuth.kt); trebuie introdus identic pe ambele telefoane.
String _syncSecretKeyFor(String boardId)    => 'sync_secret_$boardId';

// ── Chei pentru setările de rezervări prin SMS (per tabel) ────────────────────
String _bookingEnabledKeyFor(String boardId)      => 'booking_enabled_$boardId';
// Orele pe zile de sosire: „1:840-660,5:960-720” (zi:check-in-check-out, în
// minute). Citit și nativ de BookingSettings.kt — formatul trebuie să rămână
// identic.
String _workHoursKeyFor(String boardId)           => 'work_hours_$boardId';
// Chei vechi (aceleași ore în toate zilele + zile fără check-in) — doar
// citite, pentru tabelele salvate înainte de orele pe zile.
String _workStartKeyFor(String boardId)           => 'work_start_$boardId';
String _workEndKeyFor(String boardId)             => 'work_end_$boardId';
String _closedDaysKeyFor(String boardId)          => 'closed_days_$boardId';
String _ibanKeyFor(String boardId)                => 'iban_$boardId';

// ── Cu cât timp înainte de sosire vine alerta (per tabel, în minute) ─────────
// Ultima valoare aleasă în „Setează alertă” — folosită automat pentru
// rezervările noi (adăugate manual sau prin botul SMS). Citită și nativ de
// ClientBookingReceiver, ca rezervările prin bot să aibă alerta din start.
// Alerta se socotește față de sosire (startsAt); rezervările fără dată de
// sosire o socotesc față de plecare (expiresAt).
String _alertLeadKeyFor(String boardId) => 'alert_lead_minutes_$boardId';
const kDefaultAlertLeadMin = 60;

int _loadAlertLead(SharedPreferences prefs, String boardId) {
  final v = prefs.getInt(_alertLeadKeyFor(boardId));
  return v != null && v > 0 ? v : kDefaultAlertLeadMin;
}

/// Ora alertei pentru o rezervare cu sosirea (sau, fără ea, plecarea) la
/// [anchor]: cu [leadMin] minute înainte. Null dacă acel moment a trecut deja
/// (alerta n-ar mai pleca niciodată).
DateTime? autoWarningFor(DateTime? anchor, int leadMin, {DateTime? now}) {
  if (anchor == null || leadMin <= 0) return null;
  final w = anchor.subtract(Duration(minutes: leadMin));
  return w.isAfter(now ?? DateTime.now()) ? w : null;
}

/// „90” → „1h 30min”, „1440” → „1 zi”.
String formatAlertLead(int minutes) {
  if (minutes < 60) return '$minutes min';
  if (minutes % 1440 == 0) {
    final d = minutes ~/ 1440;
    return tr('$d ${d == 1 ? "zi" : "zile"}', '$d ${d == 1 ? "day" : "days"}');
  }
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (m == 0) return tr('$h ${h == 1 ? "oră" : "ore"}', '$h ${h == 1 ? "hour" : "hours"}');
  return '${h}h ${m}min';
}

// Identice cu DEFAULT_TEMPLATE_RO / DEFAULT_TEMPLATE_EN din BotReminders.kt.
const _kDefaultSmsTemplateRo =
    'Alertă: [NUME]. Va expira la [DATA_EXPIRARE]. Te rugăm să iei măsurile necesare.';
const _kDefaultSmsTemplateEn =
    'Reminder: [NAME]. It expires on [EXPIRY_DATE]. Please take the necessary steps.';

// Mesajul implicit urmează limba aplicației. Un mesaj salvat identic cu unul
// din cele implicite e tratat tot ca implicit; unul editat de utilizator
// rămâne neatins la schimbarea limbii.
String get _defaultSmsTemplate =>
    tr(_kDefaultSmsTemplateRo, _kDefaultSmsTemplateEn);

String _effectiveSmsTemplate(String? saved) =>
    (saved == null ||
            saved.trim().isEmpty ||
            saved == _kDefaultSmsTemplateRo ||
            saved == _kDefaultSmsTemplateEn)
        ? _defaultSmsTemplate
        : saved;

enum _AlertMode { lead, exact, none }

// ── Prezența la programare ────────────────────────────────────────────────────
const kCame   = 'came';
const kNoShow = 'noShow';
// Momentul de la care aplicația cere confirmarea prezenței — programările
// încheiate înainte de această funcție nu devin „de confirmat”.
const _kAttendanceSinceKey = 'attendance_since';

/// Sejur încheiat (după check-out), încă neconfirmat de pensiune.
bool needsAttendance(Item item, DateTime? since, {DateTime? now}) =>
    item.attendance == null &&
    item.expiresAt != null &&
    item.expiresAt!.isBefore(now ?? DateTime.now()) &&
    since != null &&
    item.expiresAt!.isAfter(since);

// Datele demonstrative create la prima instalare de versiunile vechi
// (moștenite din Organizator) — recunoscute după nume + data creării.
const _kDemoItems = {
  'Proiect Alpha': (2026, 1, 10, 9, 0),
  'Raport lunar': (2026, 2, 1, 8, 30),
  'Întâlnire echipă': (2026, 3, 15, 10, 0),
  'Audit intern': (2026, 4, 5, 11, 0),
  'Buget anual': (2026, 5, 20, 14, 0),
};

@visibleForTesting
bool isDemoItem(Item item) {
  final c = _kDemoItems[item.name];
  return c != null &&
      item.phones.isEmpty &&
      item.createdAt == DateTime(c.$1, c.$2, c.$3, c.$4, c.$5);
}

// ─── Helper: ID unic stabil pentru sincronizare ───────────────────────────────
String _generateSyncId() {
  final r = Random.secure();
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  return List.generate(16, (_) => chars[r.nextInt(chars.length)]).join();
}

// Format ISO scurt (fără secunde) pentru SMS compact
String _isoShort(DateTime dt) =>
    '${dt.year}-'
    '${dt.month.toString().padLeft(2, '0')}-'
    '${dt.day.toString().padLeft(2, '0')}T'
    '${dt.hour.toString().padLeft(2, '0')}:'
    '${dt.minute.toString().padLeft(2, '0')}';
