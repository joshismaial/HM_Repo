// Free UPI payment straight to the owner (decided 25 Oct 2026).
// Student taps his UPI app (amount + note filled) → comes back → must add the payment receipt
// (Share > My Hostel from the UPI app, or pick a screenshot) → the app runs 12 checks
// (7 on the payment, 5 on the receipt). Every payment then waits for the owner in Home › Confirm payments
// (decided 25 Oct 2026): checks passed = green Confirm, failed = amber Check. Nothing is paid until he confirms.
// New joiners always wait for the owner's Confirm booking.
// Receipt image: kept on the server for at most 7 days, then only on the owner's phone (90 days).
// PROTOTYPE: Expo Go cannot open a UPI app and read its reply, or read text in an image,
// so those steps are simulated with buttons (marked "Prototype").
import React, { useState } from 'react';
import { Pressable, View } from 'react-native';
import { useBackHandler, useNav } from '../nav';
import { showSheet, toast } from '../overlay';
import { actions, app, billDue, joiningTotal, rupees, runChecks, useApp } from '../state';
import { Btn, C, Card, Field, Gap, Icon, InfoRow, Row, Screen, T } from '../ui';

export const UPI_APPS = [
  { key: 'payGpay', name: 'Google Pay', color: '#1A73E8', mark: 'G' },
  { key: 'payPhonepe', name: 'PhonePe', color: '#5F259F', mark: 'Pe' },
  { key: 'payPaytm', name: 'Paytm', color: '#00BAF2', mark: 'P' },
  { key: null, name: 'Any UPI app', color: '#5C6782', mark: 'UPI' },
];

const newUtr = () => '6' + String(Math.floor(Math.random() * 1e11)).padStart(11, '0');
export const last4 = (utr) => (utr || '').slice(-4);
const fmtUtr = (u) => (u || '').replace(/(\d{4})(?=\d)/g, '$1 ');

/** Big app buttons. Only the apps the owner switched on (Hostel settings › Payment options) + Any UPI app. */
export function UpiTiles({ onPick }) {
  const h = app.hostels[0];
  const apps = UPI_APPS.filter((a) => !a.key || h[a.key]);
  return (
    <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 10 }}>
      {apps.map((a) => (
        <Pressable key={a.name} onPress={() => onPick(a.name)} accessibilityRole="button" accessibilityLabel={`Pay with ${a.name}`}
          style={({ pressed }) => ({ width: '48%', flexGrow: 1, alignItems: 'center', paddingVertical: 14, borderRadius: 14, borderWidth: 1, borderColor: C.line, backgroundColor: '#fff', opacity: pressed ? 0.75 : 1 })}>
          <View style={{ width: 42, height: 42, borderRadius: 21, backgroundColor: a.color, alignItems: 'center', justifyContent: 'center' }}>
            <T size={a.mark.length > 2 ? 11 : 14} weight="800" color="#fff">{a.mark}</T>
          </View>
          <T size={12.5} weight="600" style={{ marginTop: 8 }}>{a.name}</T>
        </Pressable>
      ))}
    </View>
  );
}

/** QR for paying from another phone (prototype: a drawn placeholder). */
export function QrSheet({ amount, note }) {
  const h = app.hostels[0];
  return (
    <View style={{ alignItems: 'center' }}>
      <T size={20} weight="800">Scan with any UPI app</T>
      <T size={12.5} color={C.muted} style={{ marginTop: 4 }}>{rupees(amount)} and note {note} are filled in</T>
      <View style={{ width: 180, height: 180, borderRadius: 12, borderWidth: 1, borderColor: C.line, marginTop: 16, alignItems: 'center', justifyContent: 'center', backgroundColor: '#fff' }}>
        <Icon name="qr-code" size={150} color={C.ink} />
      </View>
      <T size={12.5} weight="600" style={{ marginTop: 10 }}>{h.upiId}</T>
      <T size={12} color={C.muted} center style={{ marginTop: 8 }}>After paying, tap the UPI app again here and choose “Paid – app sent nothing” to type the number.</T>
    </View>
  );
}

/**
 * Opens the UPI app (prototype: a sheet). onResult({ app, fromApp, utr, seconds }) after the student comes back.
 */
export function openUpiApp(appName, amount, note, onResult) {
  const h = app.hostels[0];
  showSheet((close) => (
    <View style={{ gap: 10 }}>
      <T size={20} weight="800">Opening {appName}</T>
      <Card bg={C.ground} padding={12}>
        <InfoRow label="To" value={h.upiId} bold />
        <InfoRow label="Amount" value={rupees(amount)} bold />
        <InfoRow label="Note" value={note} />
      </Card>
      <T size={12} color={C.muted}>Prototype: Expo Go can’t open {appName}. Choose what happened:</T>
      <Btn variant="success" title="Paid – app sent the number" onPress={() => { close(); onResult({ app: appName, fromApp: true, utr: newUtr(), seconds: 38 }); }} />
      <Btn variant="outline" title="Paid – app sent nothing (I’ll type it)" onPress={() => { close(); onResult({ app: appName, fromApp: false, utr: '', seconds: 52 }); }} />
      <Btn variant="outline" title="Test: came back after 2 seconds" onPress={() => { close(); onResult({ app: appName, fromApp: true, utr: newUtr(), seconds: 2 }); }} />
      <Btn variant="text" title="I didn’t pay" onPress={close} />
    </View>
  ));
}

/** Small picture of a receipt (used in lists). */
export function ReceiptThumb({ r, width = 56, onPress }) {
  const body = (
    <View style={{ width, height: width * 1.6, borderRadius: 8, backgroundColor: r?.payee === app.hostels[0].upiId ? '#5F259F' : '#7A8597', padding: 4 }}>
      <View style={{ flex: 1, borderRadius: 5, backgroundColor: '#fff', alignItems: 'center', paddingTop: 6 }}>
        <View style={{ width: 16, height: 16, borderRadius: 8, backgroundColor: C.green, alignItems: 'center', justifyContent: 'center' }}>
          <Icon name="checkmark" size={11} color="#fff" />
        </View>
        <T size={9.5} weight="800" style={{ marginTop: 3 }}>{r ? rupees(r.amount) : ''}</T>
        <T size={7.5} weight="600" color={C.green}>Successful</T>
      </View>
    </View>
  );
  return onPress ? <Pressable onPress={onPress}>{body}</Pressable> : body;
}

/** Full receipt + what the app read from it (owner side). */
export function ReceiptView({ p }) {
  const h = app.hostels[0];
  const r = p.receipt;
  const ok = (cond) => <Icon name={cond ? 'checkmark-circle' : 'close-circle'} size={18} color={cond ? C.green : C.red} />;
  return (
    <View>
      <T size={20} weight="800" style={{ marginBottom: 10 }}>{p.name}’s receipt</T>
      <View style={{ backgroundColor: r.payee === h.upiId ? '#5F259F' : '#7A8597', borderRadius: 14, padding: 10 }}>
        <View style={{ backgroundColor: '#fff', borderRadius: 10, padding: 14, alignItems: 'center' }}>
          <Icon name="checkmark-circle" size={34} color={C.green} />
          <T size={22} weight="800">{rupees(r.amount)}</T>
          <T size={12.5} weight="600" color={C.green}>Transaction {r.status}</T>
          <View style={{ alignSelf: 'stretch', marginTop: 8 }}>
            <InfoRow label="To" value={r.payee} />
            <InfoRow label="UTR" value={r.utr} />
            <InfoRow label="Date" value={r.time} />
          </View>
          <T size={11} color={C.muted}>{r.shared ? `shared from ${p.app}` : 'screenshot'}</T>
        </View>
      </View>
      <T size={11} weight="600" color={C.muted} style={{ marginTop: 14, marginBottom: 4, letterSpacing: 0.5 }}>APP READ THE RECEIPT</T>
      <Row gap={8} style={{ paddingVertical: 3 }}>{ok(r.amount === p.amount)}<T style={{ flex: 1 }}>Amount {rupees(r.amount)}</T></Row>
      <Row gap={8} style={{ paddingVertical: 3 }}>{ok(r.payee === h.upiId)}<T style={{ flex: 1 }}>Paid to {r.payee}</T></Row>
      <Row gap={8} style={{ paddingVertical: 3 }}>{ok(r.utr === p.utr)}<T style={{ flex: 1 }}>UTR {fmtUtr(r.utr)}</T></Row>
      <Row gap={8} style={{ paddingVertical: 3 }}>{ok(!r.old)}<T style={{ flex: 1 }}>Time {r.time}</T></Row>
      <View style={{ backgroundColor: C.amberSoft, borderRadius: 10, padding: 10, marginTop: 10 }}>
        <T size={12.5} weight="600" color={C.amber}>A receipt can be edited – your bank is final.</T>
      </View>
      <T size={11.5} color={C.muted} style={{ marginTop: 8 }}>Saved on your phone for 90 days. The server copy is deleted after 7 days.</T>
    </View>
  );
}

/** The 12 checks as a list. */
export function ChecksList({ checks }) {
  const groups = [['pay', 'Payment'], ['receipt', 'Receipt']];
  return (
    <View>
      {groups.map(([g, title]) => (
        <View key={g} style={{ marginBottom: 6 }}>
          <T size={12.5} weight="800" style={{ marginBottom: 4 }}>{title}</T>
          {checks.filter((c) => c.group === g).map((c) => (
            <Row key={c.label} gap={8} style={{ paddingVertical: 2 }}>
              <Icon name={c.state === 'ok' ? 'checkmark-circle' : c.state === 'soft' ? 'alert-circle' : 'close-circle'} size={18}
                color={c.state === 'ok' ? C.green : c.state === 'soft' ? C.amber : C.red} />
              <T size={12.5} style={{ flex: 1 }}>{c.label}</T>
            </Row>
          ))}
        </View>
      ))}
    </View>
  );
}

// ======================================================================
// After the UPI app: UTR (filled by the app or typed) + receipt (required) → checks → result
// params: { purpose: 'join' | 'rent', amount, note, app, fromApp, utr, seconds, bank }
// ======================================================================
export function UpiReceipt({ params }) {
  useApp();
  const nav = useNav();
  const h = app.hostels[0];
  const { purpose, amount, note } = params;
  const [utr, setUtr] = useState(params.utr || '');
  const [utrError, setUtrError] = useState(null);
  const [receipt, setReceipt] = useState(null);
  const [result, setResult] = useState(null); // { checks, pass }
  const fromApp = !!params.fromApp;
  const appName = params.app;

  useBackHandler(() => {
    if (result) { nav.pop(); return true; }
    return false;
  });

  const makeReceipt = (kind, shared) => ({
    amount,
    payee: kind === 'otherPayee' ? 'rahul.friend@ybl' : h.upiId,
    utr: utr || params.utr,
    status: 'Successful',
    time: kind === 'old' ? '02 Nov 2026, 18:40' : 'Today, just now',
    old: kind === 'old',
    hash: kind === 'old' ? 'img-used-before' : 'img-' + Date.now(),
    shared,
  });

  const addReceipt = (shared) => {
    if (utr.length !== 12) {
      setUtrError('Enter the 12-digit UTR first.');
      return;
    }
    showSheet((close) => (
      <View style={{ gap: 10 }}>
        <T size={20} weight="800">{shared ? `Share from ${appName}` : 'Pick screenshot'}</T>
        <T size={12.5} color={C.muted}>
          {shared ? `In ${appName}, open the payment and tap Share › My Hostel. The receipt comes here by itself.` : 'Newest photos show first. Tap your payment screenshot.'}
        </T>
        <T size={12} color={C.muted}>Prototype: choose a sample receipt.</T>
        <Btn variant="success" title="Receipt OK" onPress={() => { close(); setReceipt(makeReceipt('ok', shared)); }} />
        <Btn variant="outline" title="Test: old screenshot (used before)" onPress={() => { close(); setReceipt(makeReceipt('old', false)); }} />
        <Btn variant="outline" title="Test: paid to someone else" onPress={() => { close(); setReceipt(makeReceipt('otherPayee', false)); }} />
        <Btn variant="text" title="Cancel" onPress={close} />
      </View>
    ));
  };

  const finish = () => {
    if (utr.length !== 12) return setUtrError('UTR / reference number is 12 digits. Find it in your UPI app under payment details.');
    if (!receipt) return toast('Add the payment receipt to finish.');
    const info = { purpose, amount, due: purpose === 'join' ? joiningTotal() : billDue(), app: appName, fromApp, utr, seconds: params.seconds ?? 40, receipt };
    const checks = runChecks(info);
    const pass = checks.every((c) => c.state === 'ok');
    if (purpose === 'join') {
      const d = app.draft;
      Object.assign(d, { payMethod: params.bank ? 'bank' : 'upi', utr, payApp: appName, payChecks: checks, payReceipt: receipt, utrFromApp: fromApp });
      actions.submitJoining();
      nav.resetTo('Submitted', {});
      return;
    }
    actions.payRentUpi({ ...info, checks, pass });
    setResult({ checks, pass });
  };

  // ---------- result (rent) ----------
  if (result) {
    return (
      <Screen back={false} title="Rent payment" footer={<Btn title="Done" onPress={() => nav.pop()} />}>
        {result.pass ? (
          <Card bg={C.amberSoft} border="#F3D19C">
            <Row gap={12}>
              <Icon name="hourglass-outline" size={32} color={C.amber} />
              <View style={{ flex: 1 }}>
                <T size={17} weight="800" color={C.amber}>Payment sent · waiting for owner</T>
                <T size={12.5} color="#92400E">{rupees(amount)} · {appName}. All checks passed. The owner checks his bank and confirms – then your receipt comes.</T>
              </View>
            </Row>
          </Card>
        ) : (
          <Card bg={C.amberSoft} border="#F3D19C">
            <Row gap={12}>
              <Icon name="hourglass-outline" size={32} color={C.amber} />
              <View style={{ flex: 1 }}>
                <T size={17} weight="800" color={C.amber}>Owner is checking your payment</T>
                <T size={12.5} color="#92400E">Some checks did not pass. You get a message when he confirms.</T>
              </View>
            </Row>
          </Card>
        )}
        <Gap h={12} />
        <Card>
          <T size={11} weight="600" color={C.muted} style={{ marginBottom: 8, letterSpacing: 0.5 }}>
            CHECKED BY THE APP · {result.checks.filter((c) => c.state === 'ok').length} OF {result.checks.length}
          </T>
          <ChecksList checks={result.checks} />
        </Card>
      </Screen>
    );
  }

  return (
    <Screen title={purpose === 'join' ? 'Finish payment' : 'Pay rent'} footer={
      <View>
        <Btn variant="success" title={purpose === 'join' ? 'Send to owner' : 'Finish payment'} disabled={!receipt || utr.length !== 12} onPress={finish} />
        <T size={11.5} color={C.muted} center style={{ marginTop: 6 }}>{!receipt ? 'Turns on after the receipt is added' : ' '}</T>
      </View>
    }>
      {params.bank ? (
        <Card bg={C.ground} style={{ marginBottom: 10 }}>
          <T weight="600" style={{ lineHeight: 21 }}>{h.bankDetails}</T>
          <InfoRow label="Amount" value={rupees(amount)} bold />
          <InfoRow label="Remarks" value={note} />
        </Card>
      ) : null}
      {fromApp ? (
        <Card bg={C.greenSoft} border="#A7DDB8">
          <T size={12.5} weight="600" color="#166534">Back from {appName}</T>
          <T size={17} weight="800" style={{ marginTop: 2 }}>{rupees(amount)} · UTR {fmtUtr(utr)}</T>
          <T size={12} weight="600" color={C.green}>Filled by your UPI app</T>
        </Card>
      ) : (
        <Card>
          <T size={12.5} color={C.muted} style={{ marginBottom: 8 }}>{params.bank ? 'After paying, enter the bank reference.' : `${appName} didn’t share the number. Copy it from the payment details.`}</T>
          <Field label="UTR / reference number (12 digits)" placeholder="e.g. 428913775999" keyboardType="number-pad" maxLength={12} value={utr}
            onChangeText={(v) => { setUtr(v.replace(/\D/g, '')); setUtrError(null); }} error={utrError} />
        </Card>
      )}
      <Gap h={14} />
      <T size={15} weight="800">Last step: add the payment receipt</T>
      <T size={12.5} color={C.muted} style={{ marginBottom: 10 }}>Needed to finish. Takes one tap.</T>
      {receipt ? (
        <Card border={C.green}>
          <Row gap={12}>
            <ReceiptThumb r={receipt} width={48} />
            <View style={{ flex: 1 }}>
              <T weight="600">Receipt added</T>
              <T size={12.5} color={C.muted}>{rupees(receipt.amount)} · {receipt.payee}</T>
            </View>
            <Btn small variant="text" title="Change" onPress={() => setReceipt(null)} />
          </Row>
        </Card>
      ) : (
        <View style={{ gap: 10 }}>
          {params.bank ? null : (
            <Card border={C.blue}>
              <T size={13.5} weight="800">In {appName}, tap Share › My Hostel</T>
              <T size={12.5} color={C.muted} style={{ marginBottom: 10 }}>The receipt comes here by itself</T>
              <Btn variant="tonal" icon="share-social-outline" title={`Share from ${appName}`} onPress={() => addReceipt(true)} />
            </Card>
          )}
          <Card>
            <T size={13.5} weight="800">Took a screenshot?</T>
            <T size={12.5} color={C.muted} style={{ marginBottom: 10 }}>Newest photos show first</T>
            <Btn variant="outline" icon="image-outline" title="Pick screenshot" onPress={() => addReceipt(false)} />
          </Card>
          <View style={{ backgroundColor: C.amberSoft, borderRadius: 10, padding: 10 }}>
            <T size={12} weight="600" color={C.amber}>Parent paid from another phone? Ask them to send the receipt on WhatsApp, then pick it.</T>
          </View>
        </View>
      )}
    </Screen>
  );
}
