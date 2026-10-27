#!/usr/bin/env node
// Generator manual de licențe Ospita — același format și aceeași
// semnătură ca licențele emise automat de site (voltacademy_web/lib/licenseSigner.js).
//
// Utilizare (din folderul pensiune_app):
//   node tools/generate_license.js --cod pensiune-1700000000000 --zile 365
//   node tools/generate_license.js --cod pensiune-1700000000000 --pana 2027-12-31
//   node tools/generate_license.js --cod pensiune-1700000000000 --permanenta
//   ... --out C:\cale\pensiune_license.json   (implicit: pensiune_license.json aici)
//
// Codul de instalare îl vede clientul în aplicație, pe ecranul Licență.
// Cheia privată: D:\PensiuneLicenseTool\private.pem, sau calea din variabila
// PENSIUNE_PRIVATE_KEY (nu se pune niciodată în git).
// Alternativ: D:\PensiuneLicenseTool\generate_license_v2.ps1 (aceeași comandă
// ca la Appunta / Tally).

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const PRIVATE_KEY = process.env.PENSIUNE_PRIVATE_KEY || 'D:\\PensiuneLicenseTool\\private.pem';
const LICENSE_STORE = path.join(ROOT,
  'android/app/src/main/kotlin/com/example/management_app/LicenseStore.kt');

function fail(msg) {
  console.error(`EROARE: ${msg}`);
  process.exit(1);
}

function parseArgs(argv) {
  const args = {};
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--permanenta') args.permanenta = true;
    else if (['--cod', '--zile', '--pana', '--out'].includes(a)) args[a.slice(2)] = argv[++i];
    else fail(`argument necunoscut: ${a}`);
  }
  return args;
}

// Identic cu canonicalLicensePayload() din LicenseVerifier.kt și licenseSigner.js.
function canonical(p) {
  return [
    p.licenseId ?? '', p.businessId ?? '', p.stickId ?? '', p.issuedAt ?? '',
    String(Boolean(p.isLifetime)), p.validUntil == null ? '' : p.validUntil,
  ].join('|');
}

// yyyy-MM-dd'T'HH:mm:ss'Z' (UTC, fără milisecunde) — ce acceptă aplicația.
const stamp = (d) => d.toISOString().replace(/\.\d{3}Z$/, 'Z');

// Cheia publică din aplicație (LicenseStore.PUBLIC_KEY_B64) — verificăm că
// private.pem e chiar perechea ei, altfel licența ar fi respinsă.
function appPublicKey() {
  const src = fs.readFileSync(LICENSE_STORE, 'utf8');
  const block = src.match(/PUBLIC_KEY_B64\s*=([\s\S]*?)\n\s*\n/);
  if (!block) fail('nu găsesc PUBLIC_KEY_B64 în LicenseStore.kt');
  const b64 = [...block[1].matchAll(/"([^"]*)"/g)].map((m) => m[1]).join('');
  return crypto.createPublicKey({ key: Buffer.from(b64, 'base64'), format: 'der', type: 'spki' });
}

const args = parseArgs(process.argv.slice(2));
const cod = (args.cod || '').trim();
if (!/^pensiune-\d+$/.test(cod)) {
  fail('--cod trebuie să fie codul de instalare din aplicație (ex. pensiune-1700000000000)');
}
const modes = [args.zile != null, args.pana != null, !!args.permanenta].filter(Boolean).length;
if (modes !== 1) fail('alege exact una: --zile N, --pana AAAA-LL-ZZ sau --permanenta');

const now = new Date();
let validUntil = null;
if (args.zile != null) {
  const n = Number(args.zile);
  if (!Number.isInteger(n) || n < 1 || n > 3650) fail('--zile trebuie să fie între 1 și 3650');
  validUntil = new Date(now.getTime() + n * 24 * 60 * 60 * 1000);
} else if (args.pana != null) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(args.pana)) fail('--pana trebuie să fie AAAA-LL-ZZ');
  validUntil = new Date(`${args.pana}T23:59:59Z`);
  if (isNaN(validUntil) || validUntil <= now) fail('--pana trebuie să fie o dată validă din viitor');
}

if (!fs.existsSync(PRIVATE_KEY)) fail(`lipsește ${PRIVATE_KEY}`);
const privateKey = crypto.createPrivateKey(fs.readFileSync(PRIVATE_KEY));
const publicKey = appPublicKey();
const derived = crypto.createPublicKey(privateKey).export({ format: 'der', type: 'spki' });
if (!derived.equals(publicKey.export({ format: 'der', type: 'spki' }))) {
  fail('private.pem NU corespunde cheii publice din aplicație — licența ar fi respinsă');
}

const payload = {
  licenseId: crypto.randomUUID(),
  businessId: cod,
  stickId: '',
  issuedAt: stamp(now),
  isLifetime: !!args.permanenta,
  validUntil: validUntil ? stamp(validUntil) : null,
};
const signature = crypto.sign('sha256', Buffer.from(canonical(payload), 'utf8'), privateKey)
  .toString('base64');

// Verificare finală, la fel ca aplicația (SHA256withRSA pe forma canonică).
if (!crypto.verify('sha256', Buffer.from(canonical(payload), 'utf8'), publicKey,
  Buffer.from(signature, 'base64'))) {
  fail('verificarea semnăturii a eșuat');
}

const out = path.resolve(args.out || 'pensiune_license.json');
fs.writeFileSync(out, JSON.stringify({ payload, signature }, null, 2));

console.log(`Licență creată: ${out}`);
console.log(`  Cod instalare: ${cod}`);
console.log(`  Valabilă:      ${payload.isLifetime ? 'permanent' : `până la ${payload.validUntil} (UTC)`}`);
console.log(`  ID licență:    ${payload.licenseId}`);
console.log('Semnătura a fost verificată cu cheia publică din aplicație.');
console.log('Trimite fișierul clientului; îl importă din ecranul Licență al aplicației.');
