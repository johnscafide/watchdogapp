#!/usr/bin/env node
// Node 20+. Bounded, read-only live requests; no account, schema or production writes.
import { readFile, writeFile } from 'node:fs/promises';
import assert from 'node:assert/strict';

const swift = await readFile(new URL('../Sources/WatchdogCore/PropertyService.swift', import.meta.url), 'utf8');
function defaultURL(name) {
  const match = swift.match(new RegExp(`${name}: URL = URL\\(string: "([^"]+)"`));
  assert(match, `Could not read ${name} from Swift configuration`);
  return match[1];
}
const configuration = {
  parcel: defaultURL('parcelEndpoint'), geocode: defaultURL('geocodeEndpoint'),
  website: defaultURL('websiteBase'), backend: defaultURL('backendBase'),
  key: swift.match(/publishableKey: String = "(sb_publishable_[^"]+)"/)?.[1]
};
assert(configuration.key, 'A public client key is required');
const report = { checkedAt: new Date().toISOString(), checks: [], notes: [] };
async function check(name, operation) {
  const started = Date.now();
  try {
    const detail = await operation();
    report.checks.push({ name, ok: true, milliseconds: Date.now() - started, ...detail });
    return detail;
  } catch (error) {
    report.checks.push({ name, ok: false, milliseconds: Date.now() - started, error: String(error.message || error) });
    return null;
  }
}
async function document(url, { body, apiKey = false } = {}) {
  const response = await fetch(url, {
    method: body ? 'POST' : 'GET', signal: AbortSignal.timeout(25000),
    headers: { Accept: 'application/json', ...(body ? { 'Content-Type': 'application/json' } : {}), ...(apiKey ? { apikey: configuration.key } : {}) },
    ...(body ? { body: JSON.stringify(body) } : {})
  });
  assert.equal(response.status, 200, `HTTP ${response.status} from ${new URL(url).pathname}`);
  const data = await response.json();
  assert(!data.error, `Source error from ${new URL(url).pathname}: ${JSON.stringify(data.error)}`);
  return data;
}
function queryURL(endpoint, values) {
  const url = new URL(endpoint);
  for (const [key, value] of Object.entries(values)) url.searchParams.set(key, value);
  return url;
}

let pin;
await Promise.all([
  check('NJ parcel search and coordinate contract', async () => {
    const fieldBlock = swift.match(/public static let parcelFields = \[([\s\S]*?)\]\.joined/)[1];
    const fields = [...fieldBlock.matchAll(/"([A-Z0-9_]+)"/g)].map(x => x[1]);
    assert(!fields.some(x => /OWNER|ZIP5|ZIP_CODE|ST_ADDRESS|CITY_STATE/.test(x)), 'Owner/mailing fields must not be requested');
    const data = await document(queryURL(configuration.parcel, {
      where: "UPPER(MUN_NAME) LIKE 'HADDONFIELD%' AND PAMS_PIN IS NOT NULL",
      outFields: fields.join(','), returnGeometry: 'false', returnCentroid: 'true', outSR: '4326',
      resultRecordCount: '2', orderByFields: 'PROP_LOC ASC,PAMS_PIN ASC', f: 'json'
    }));
    assert(Array.isArray(data.features) && data.features.length > 0 && data.features.length <= 2);
    const first = data.features[0];
    pin = first.attributes.PAMS_PIN;
    assert.equal(typeof pin, 'string');
    assert(first.centroid && first.centroid.x < -73 && first.centroid.y > 38);
    assert(!Object.keys(first.attributes).some(x => /OWNER|ZIP5/.test(x)));
    return { count: data.features.length, coordinatesAvailable: true, effectiveTaxYearAvailable: false, effectiveAssessmentYearAvailable: false };
  }),
  check('Watchdog municipal directory', async () => {
    const data = await document(new URL('/towns/town-manifest.json', configuration.website));
    assert(Array.isArray(data.pages) && data.pages.length >= 500);
    const districts = data.pages.map(x => x.district);
    assert(districts.every(x => /^\d{4}$/.test(x)));
    assert.equal(new Set(districts).size, districts.length);
    return { count: districts.length };
  }),
  check('NJ address geocoder', async () => {
    const data = await document(queryURL(configuration.geocode, {
      SingleLine: '24 Kings Highway East, Haddonfield, NJ', outFields: 'Addr_type', outSR: '4326', maxLocations: '3', f: 'json'
    }));
    assert(Array.isArray(data.candidates));
    const candidate = data.candidates.find(x => x.score >= 90 && ['PointAddress', 'StreetAddress', 'Subaddress', 'StreetInt'].includes(x.attributes?.Addr_type));
    assert(candidate, 'No address-quality match; examine the source contract');
    return { addressCandidateAvailable: true, addressType: candidate.attributes.Addr_type };
  }),
  check('Chapter 123 single district', async () => {
    const data = await document(queryURL(new URL('/functions/v1/chapter123-provider', configuration.backend), { district: '0417' }));
    assert.equal(data.district, '0417');
    assert(data.data?.ratio > 0 && data.data.ratio <= 200);
    assert(Number.isInteger(data.tax_year));
    assert(new URL(data.source_url).protocol === 'https:');
    return { taxYear: data.tax_year, ratioPercent: data.data.ratio, source: data.source_url };
  }),
  check('Chapter 123 batch contract', async () => {
    const data = await document(new URL('/functions/v1/chapter123-provider', configuration.backend), { body: { districts: ['0417', '1204'] } });
    assert(data.districts?.['0417']?.ratio > 0 && data.districts?.['1204']?.ratio > 0);
    return { requested: 2, returned: Object.keys(data.districts).length, taxYear: data.tax_year };
  })
]);
if (pin) {
  await check('Canonical public Watchdog Score RPC', async () => {
    const data = await document(new URL('/rest/v1/rpc/get_public_property_watchdog_score_details', configuration.backend), { body: { p_pins: [pin] }, apiKey: true });
    assert(Array.isArray(data));
    assert(data.every(x => x.pams_pin === pin && x.model_version === 'ROBUST-v1' && x.watchdog_score !== null && Number(x.watchdog_score) >= 0 && Number(x.watchdog_score) <= 100));
    if (!data.length) report.notes.push('The sampled live parcel has no canonical score. The app keeps it unavailable; this is valid source behavior, not a fabricated score.');
    return { requested: 1, returned: data.length, missingScoreIsValid: true };
  });
}
report.notes.push('These are endpoint contract probes run with Node fetch. They do not compile Swift, exercise URLSession on a device, or certify native UI.');
report.ok = report.checks.length === 6 && report.checks.every(x => x.ok);
const output = new URL('../public-api-smoke.latest.json', import.meta.url);
await writeFile(output, JSON.stringify(report, null, 2) + '\n');
console.log(JSON.stringify(report, null, 2));
process.exitCode = report.ok ? 0 : 1;
