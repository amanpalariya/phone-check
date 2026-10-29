import { readFileSync } from 'node:fs';
import { before, after, beforeEach, test } from 'node:test';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { get, ref, set, update } from 'firebase/database';

let env;
const uid = 'owner', peer = '11111111-1111-4111-8111-111111111111';
const pair = '22222222-2222-4222-8222-222222222222';
const request = '33333333-3333-4333-8333-333333333333';
const session = '44444444-4444-4444-8444-444444444444';
const proof = 'A'.repeat(43) + '=';
const path = suffix => `accounts/${uid}/${suffix}`;
const owner = () => env.authenticatedContext(uid).database();
before(async () => {
  env = await initializeTestEnvironment({ projectId: 'demo-phone-check', database: {
    host: '127.0.0.1', port: 9000, rules: readFileSync(new URL('../database.rules.json', import.meta.url), 'utf8')
  }});
});
after(async () => { await env?.cleanup(); });
beforeEach(async () => { await env.clearDatabase(); });
async function paired(db = owner()) {
  await set(ref(db, path('control/pair')), { id: pair, expiresAt: Date.now() + 300000 });
  await update(ref(db, path('control/pair')), { phone: peer, proof });
  await set(ref(db, path('control/request')), { id: request, peer, proof });
  await set(ref(db, path('control/offer')), { id: session, request, expiresAt: Date.now() + 840000, proof });
  return db;
}
test('only the owner can create/read pair metadata; root reads stay denied', async () => {
  const db = owner();
  await assertSucceeds(set(ref(db, path('control/pair')), { id: pair, expiresAt: Date.now() + 300000 }));
  await assertSucceeds(get(ref(db, path('control'))));
  await assertFails(get(ref(db, `accounts/${uid}`)));
  for (const other of [env.unauthenticatedContext().database(), env.authenticatedContext('stranger').database()]) {
    await assertFails(get(ref(other, path('control'))));
    await assertFails(set(ref(other, path('control/pair')), { id: pair, expiresAt: Date.now() + 300000 }));
  }
});
test('invites are short-lived and can bind only one peer', async () => {
  const db = owner();
  await assertFails(set(ref(db, path('control/pair')), { id: pair, expiresAt: Date.now() + 900000 }));
  await paired(db);
  await assertFails(update(ref(db, path('control/pair')), { phone: session, proof }));
  await env.withSecurityRulesDisabled(async context => {
    await set(ref(context.database(), path('control/pair')), { id: pair, expiresAt: Date.now() - 1000 });
  });
  await assertFails(update(ref(db, path('control/pair')), { phone: peer, proof }));
});
test('mailboxes require current, unexpired offer, enforce sizes and known lanes', async () => {
  const db = await paired();
  const mailbox = suffix => ref(db, path(`mailboxes/${session}/${suffix}`));
  await assertSucceeds(set(mailbox('phoneToMac'), '{"ciphertext":"opaque"}'));
  await assertSucceeds(get(mailbox('phoneToMac')));
  await assertSucceeds(set(mailbox('macToPhoneAck'), '1'));
  await assertFails(set(mailbox('macToPhoneAck'), 'invalid'));
  await assertFails(set(mailbox('unknown'), 'data'));
  await assertFails(set(mailbox('phoneToMac'), 'x'.repeat(2097153)));
  await assertFails(set(ref(db, path(`mailboxes/${pair}/phoneToMac`)), 'stale'));
  await assertFails(get(ref(db, path(`mailboxes/${session}`))));
  await assertFails(get(ref(env.authenticatedContext('stranger').database(), path(`mailboxes/${session}/phoneToMac`))));
  await env.withSecurityRulesDisabled(async context => {
    await set(ref(context.database(), path('control/offer/expiresAt')), Date.now() - 1000);
  });
  await assertFails(get(mailbox('phoneToMac')));
  await assertFails(set(mailbox('phoneToMac'), 'expired'));
  await assertSucceeds(set(ref(db, path(`mailboxes/${session}`)), null));
});
test('rotation atomically clears old values and invalidates the old session', async () => {
  const db = await paired();
  await set(ref(db, path(`mailboxes/${session}/macToPhone`)), 'encrypted');
  await assertSucceeds(update(ref(db, `accounts/${uid}`), {
    mailboxes: null,
    'control/offer': { id: pair, request, expiresAt: Date.now() + 840000, proof }
  }));
  await assertFails(set(ref(db, path(`mailboxes/${session}/phoneToMac`)), 'old session'));
  await assertSucceeds(set(ref(db, path(`mailboxes/${pair}/phoneToMac`)), 'new session'));
  await assertFails(set(ref(db, path('control/offer')), { id: pair, request, expiresAt: Date.now() + 840000, proof }));
  await assertSucceeds(set(ref(db, `accounts/${uid}`), null));
  await assertFails(set(ref(db, path(`mailboxes/${pair}/phoneToMac`)), 'unpaired'));
});
test('extra metadata cannot become a notification history store', async () => {
  const db = await paired();
  await assertFails(set(ref(db, path('history')), { text: 'body' }));
  await assertFails(set(ref(db, path('control/history')), { text: 'body' }));
  await assertFails(update(ref(db, path('control/pair')), { secret: 'forbidden' }));
});
