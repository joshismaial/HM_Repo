// Student app after joining (private link / app, no login): Home · Fees · My room · Settings.
import React, { useState } from 'react';
import { Image, Pressable, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useBackHandler, useNav } from '../nav';
import { confirm, showSheet, toast } from '../overlay';
import { actions, addDays, billDue, billPaidSoFar, protoToday, app, billParts, billTotal, feeState, fmtDate, hostelTitle, initials, lateFeeActive, rupees, useApp } from '../state';
import {
  Avatar, Btn, C, Card, ProgressRing, Chips, Divider, EmptyState, Field, Gap, Icon, IconBox, InfoRow, LanguageButton, LanguageList, Pill, Row,
  Screen, SectionTitle, SkyBack, T, TabBar, TabPage, UploadBox,
} from '../ui';
import { BookingStatus } from './student';
import { QrSheet, UpiTiles, openUpiApp } from './upiPay';

const IND = '#1560BD';
const VIO = '#1560BD';

export function StudentShell() {
  useApp();
  const [tab, setTab] = useState(0);
  // phone back button: other tabs go back to Home first
  useBackHandler(() => {
    if (tab !== 0) {
      setTab(0);
      return true;
    }
    return false;
  });
  const pages = [
    <HomeTab key="0" goFees={() => setTab(1)} />,
    <FeesTab key="1" />,
    <IssuesTab key="2" />,
    <SettingsTab key="3" />,
  ];
  return (
    <View style={{ flex: 1, backgroundColor: C.ground }}>
      <View style={{ flex: 1 }}>
        {pages.map((p, i) => (
          <View key={i} style={i === tab ? { flex: 1 } : { display: 'none' }}>{p}</View>
        ))}
      </View>
      <TabBar
        active={tab}
        onChange={setTab}
        tabs={[
          { label: 'Home', icon: 'home' },
          { label: 'Fees', icon: 'cash', badge: (app.stay.billPaid ? 0 : 1) + (app.stay.alerts || []).filter((a) => a.tab === 'fee' && !a.seen).length || null },
          { label: 'Report issue', icon: 'construct', badge: (app.myIssues || []).filter((c) => c.seen === false).length || null },
          { label: 'Settings', icon: 'settings' },
        ]}
      />
    </View>
  );
}

function showReceipt(r) {
  showSheet(() => (
    <View style={{ alignItems: 'stretch' }}>
      <View style={{ alignItems: 'center', marginBottom: 12 }}>
        <Icon name="shield-checkmark" size={40} color={C.green} />
        <T size={20} weight="800" style={{ marginTop: 8 }}>Receipt {r.receipt}</T>
      </View>
      <InfoRow label="Hostel" value={app.hostels[0].name} />
      <InfoRow label="For" value={r.month} />
      <InfoRow label="Paid on" value={r.date} />
      <InfoRow label="Method" value={r.method} />
      <InfoRow label="Amount" value={rupees(r.amount)} bold />
    </View>
  ));
}

function ReceiptRow({ r }) {
  return (
    <Card padding={12} onPress={() => showReceipt(r)} style={{ marginBottom: 8 }}>
      <Row gap={12}>
        <IconBox name="receipt-outline" color={C.green} size={36} />
        <View style={{ flex: 1 }}>
          <T weight="600">{r.month}</T>
          <T size={12.5} color={C.muted}>{r.date} · {r.method} · {r.receipt}</T>
        </View>
        <T weight="800">{rupees(r.amount)}</T>
      </Row>
    </Card>
  );
}

// Vacate: the student leaves on the next fee date. Notice at least noticeDays before it = deposit back.
function vacateInfo() {
  const s = app.stay;
  const h = app.hostels[0];
  return {
    onTime: s.daysToDue >= h.noticeDays,
    deadline: fmtDate(addDays(protoToday(), s.daysToDue - h.noticeDays)).slice(0, 6),
  };
}

async function startNotice() {
  const s = app.stay;
  const { onTime, deadline } = vacateInfo();
  if (!onTime) {
    const ok = await confirm({
      title: `Leave on ${s.dueDate}?`,
      text: `Notice date ${deadline} has passed. If you leave on ${s.dueDate}: no refund (deposit and rent).`,
      confirmLabel: 'Give notice – no refund',
      danger: true,
    });
    if (!ok) return;
  }
  actions.giveNotice(s.dueDate, onTime, s.daysToDue);
  toast('Notice sent to the owner.');
}

function copyText(text, msg) {
  try {
    if (typeof navigator !== 'undefined' && navigator.clipboard) navigator.clipboard.writeText(text);
  } catch (e) {}
  toast(msg);
}

// ---------------------------------------------------------------- Home
// Decided 20 Oct 2026: name band (photo + full name + room chips), fee card (days left / days delay / paid),
// ad space (sponsored card or empty box), Wi-Fi (2 lines + Copy), vacate rule + notice, notices from the owner.
// Fee receipts live only in the Fees tab. Everything fits on one screen.
function HomeTab({ goFees }) {
  const nav = useNav();
  const insets = useSafeAreaInsets();
  const s = app.stay;
  const h = app.hostels[0];
  const waiting = s.status.startsWith('Waiting');
  useApp();
  const state = feeState();
  const parts = billParts();
  const extras = parts.filter((p) => p.key !== 'rent' && p.key !== 'late');
  const late = parts.find((p) => p.key === 'late');
  const total = billDue(); // what is still to pay (after any part payments)
  const paidPart = billPaidSoFar();
  const [dd, mon, yr] = s.dueDate.split(' ');
  const breakdown = extras.length ? parts.filter((p) => p.key !== 'late').map((p) => `${p.key === 'rent' ? 'Rent' : p.label.toLowerCase().replace('electricity', 'elec')} ${rupees(p.amount)}`).join(' + ') : null;
  const { onTime, deadline } = vacateInfo();
  const giveNotice = startNotice;
  const cancelNotice = async () => {
    const ok = await confirm({ title: 'Cancel your notice?', text: 'You will keep staying. The owner is told.', confirmLabel: 'Yes, I am staying' });
    if (ok) {
      actions.cancelNotice();
      toast('Notice cancelled.');
    }
  };
  const ad = (app.studentAds || [])[0];
  const wifi = (h.wifi || []).find((w) => w.floor === s.floor) || (h.wifi || []).find((w) => w.floor == null);

  // ---------- fee card: before the fee date / late / paid ----------

  // ---------- section colours (prototype: app.homeLook 1-6) ----------
  const LOOKS = {
    // 1 Mint & coral – soft pastel tiles
    1: { card: '#fff', line: '#E6EBF3', ad: { bg: '#F4F1FF', fg: '#7C6CF2' }, wifi: { bg: '#E8F6F2', fg: '#12A38A', solid: true, btnBg: '#fff', btnFg: '#0F7C69' }, leave: { bg: '#FFEEEB', fg: '#EF5A45', solid: true, btnBg: '#fff', btnFg: '#D9432F' }, notice: { bg: '#FFF7E8', fg: '#E59A2E', solid: true } },
    // 2 Clean white – white tiles, thin border, coloured icon circles
    2: { card: '#fff', border: true, line: '#E6EBF3', round: true, ad: { bg: '#FAFAFF', fg: '#8B5CF6' }, wifi: { bg: '#fff', fg: '#14B8A6', solid: true, btnBg: '#F0FDFA', btnFg: '#0F766E' }, leave: { bg: '#fff', fg: '#F43F5E', solid: true, btnBg: '#FFF1F2', btnFg: '#E11D48' }, notice: { bg: '#fff', fg: '#F59E0B', solid: true } },
    // 3 Navy & rose – one dark tile for contrast
    3: { card: '#fff', line: '#E6EBF3', ad: { bg: '#F5F7FB', fg: '#5B6B8C' }, wifi: { bg: '#14213D', fg: '#2DD4BF', solid: false, iconBg: 'rgba(255,255,255,0.12)', title: '#fff', text: '#B9C4DA', btnBg: '#2DD4BF', btnFg: '#0B1B33' }, leave: { bg: '#fff', fg: '#E11D48', solid: true, btnBg: '#FFF1F2', btnFg: '#E11D48' }, notice: { bg: '#fff', fg: '#1560BD', solid: false }, shadow: '0 4px 14px rgba(20,33,61,0.08)' },
    // 4 Soft shadow – white cards lifted with shadow, big faded icons
    4: { card: '#fff', line: '#EEF2F7', watermark: true, shadow: '0 6px 18px rgba(20,33,61,0.09)', ad: { bg: '#F7F5FF', fg: '#7C6CF2' }, wifi: { bg: '#fff', fg: '#0EA5A4', solid: false, btnBg: '#E6F7F6', btnFg: '#0E7C7B' }, leave: { bg: '#fff', fg: '#F05252', solid: false, btnBg: '#FDECEC', btnFg: '#D63A3A' }, notice: { bg: '#fff', fg: '#F2A93B', solid: false } },
    // 5 Blue family – calm, matches the blue header
    5: { card: '#fff', line: '#DCE3EC', ad: { bg: '#F2F6FD', fg: '#4A6FA5' }, wifi: { bg: '#E8F0FA', fg: '#1560BD', solid: true, btnBg: '#fff', btnFg: '#1560BD' }, leave: { bg: '#EEF1F8', fg: '#C2410C', solid: true, btnBg: '#fff', btnFg: '#C2410C' }, notice: { bg: '#fff', fg: '#1560BD', solid: false } },
    // 6 Sunset – warm peach & teal
    6: { card: '#fff', line: '#EFE6DE', ad: { bg: '#FFF8F1', fg: '#D97706' }, wifi: { bg: '#E7F5F5', fg: '#0F766E', solid: true, btnBg: '#fff', btnFg: '#0F766E' }, leave: { bg: '#FFF0E6', fg: '#EA580C', solid: true, btnBg: '#fff', btnFg: '#C2410C' }, notice: { bg: '#fff', fg: '#EA580C', solid: false }, shadow: '0 4px 14px rgba(120,60,20,0.07)' },
  };
  // approved: 2 Clean white, with soft blue shadows instead of borders (sky-blue look, 20 Oct 2026)
  const L = { ...LOOKS[app.homeLook || 2], border: true, line: '#DCE3EC', shadow: '0 1px 2px rgba(15,23,42,0.06)' };
  const icon = (kind, name, size = 40) => {
    const k = L[kind];
    return (
      <View style={{ width: size, height: size, borderRadius: L.round ? size / 2 : 12, backgroundColor: k.iconBg || (k.solid ? k.fg : k.fg + '1F'), alignItems: 'center', justifyContent: 'center' }}>
        <Icon name={name} size={size * 0.5} color={k.iconBg ? k.fg : k.solid ? '#fff' : k.fg} />
      </View>
    );
  };
  const tile = (kind) => ({ flex: 1, gap: 1, backgroundColor: L[kind].bg, borderRadius: 16, padding: 14, paddingBottom: 12, overflow: 'hidden', borderWidth: L.border ? 1 : 0, borderColor: L.line, ...(L.shadow ? { boxShadow: L.shadow } : null) });
  const tileBtn = (kind) => ({ marginTop: 'auto', height: 40, borderRadius: 12, backgroundColor: L[kind].btnBg, flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 6, ...(L[kind].btnBg === '#fff' ? { borderWidth: 1, borderColor: L.line } : null), alignSelf: 'stretch', top: 4 });
  const mark = (kind, name) => (L.watermark ? <View style={{ position: 'absolute', right: -14, bottom: 26, opacity: 0.07 }}><Icon name={name} size={96} color={L[kind].fg} /></View> : null);

  // ---------- compact fee card (half height): status ring | label + amount + one line | Pay ----------
  // approved look (20 Oct 2026): white card with a coloured border, solid date box, breakdown in a tinted strip.
  // Colour follows the fee: blue before the date, red late, amber late fee off, green paid.
  const feeCard = ({ ring, label, labelColor = C.muted, amount, line, lineColor = C.muted, line2, btn, tone, act }) => {
    const [fg, soft] = tone || [C.blue, C.blueSoft];
    const box =
      act === 'Pay' ? (
        <View style={{ width: 58, height: 58, borderRadius: 12, backgroundColor: fg, alignItems: 'center', justifyContent: 'center' }}>
          <T size={11} weight="600" color="#fff">{(mon || '').toUpperCase()}</T>
          <T size={20} weight="800" color="#fff" style={{ lineHeight: 22 }}>{dd}</T>
        </View>
      ) : ring;
    return (
      <View style={{ backgroundColor: '#fff', borderRadius: 16, padding: 12, borderWidth: 1, borderColor: '#DCE3EC', overflow: 'hidden', boxShadow: '0 1px 2px rgba(15,23,42,0.06)', borderLeftWidth: 6, borderLeftColor: fg }}>
        <Row gap={12}>
          {box}
          <View style={{ flex: 1 }}>
            <T size={12.5} weight="600" color={labelColor} numberOfLines={1}>{label}</T>
            <T size={24} weight="800" style={{ lineHeight: 28 }}>{rupees(amount)}</T>
            {line ? <T size={11} weight="600" color={lineColor} numberOfLines={1}>{line}</T> : null}
          </View>
          {btn}
        </Row>
        {line2 ? (
          <View style={{ marginTop: 10, marginHorizontal: -12, marginBottom: -12, backgroundColor: soft, paddingHorizontal: 12, paddingVertical: 7 }}>
            <T size={11} weight="600" color={C.ink} numberOfLines={1}>{line2}</T>
          </View>
        ) : null}
      </View>
    );
  };
  const payBtn = (bg) => (
    <Pressable onPress={goFees} style={{ backgroundColor: bg, borderRadius: 12, paddingHorizontal: 14, height: 44, flexDirection: 'row', alignItems: 'center', gap: 4 }}>
      <Icon name="flash" size={16} color="#fff" />
      <T weight="600" color="#fff">Pay</T>
    </Pressable>
  );
  // approved style (sample 3): date box on the left, colour by state
  const dateBox = (fg, bg) => (
    <View style={{ width: 58, height: 58, borderRadius: 12, backgroundColor: bg, alignItems: 'center', justifyContent: 'center' }}>
      <T size={11} weight="600" color={fg}>{(mon || '').toUpperCase()}</T>
      <T size={20} weight="800" color={fg} style={{ lineHeight: 22 }}>{dd}</T>
    </View>
  );
  // one line: rent + extra charges + late fee (only when there is one)
  const fullBreak = parts.map((p) => (p.key === 'rent' ? `Rent ${rupees(p.amount)}` : p.key === 'late' ? `late fee ${rupees(p.amount)}` : `${p.label.toLowerCase().replace('electricity', 'elec')} ${rupees(p.amount)}`)).join(' + ');
  let fee;
  if (state === 'paid') {
    const r = s.receipts[0];
    fee = feeCard({
      tone: [C.green, C.greenSoft], act: 'Receipt',
      ring: (
        <View style={{ width: 58, height: 58, borderRadius: 12, backgroundColor: C.green, alignItems: 'center', justifyContent: 'center' }}>
          <Icon name="checkmark" size={34} color="#fff" />
        </View>
      ),
      label: `${r.month.split(' ')[0]} fee paid ✓`,
      labelColor: C.green,
      amount: r.amount,
      line: `Paid ${r.date} · ${r.method}`,
      line2: `Next fee on ${s.dueDate} · paid on time ★`,
      line2Color: C.green,
      btn: (
        <Pressable onPress={() => showReceipt(r)} style={{ borderWidth: 1.2, borderColor: C.line, borderRadius: 12, paddingHorizontal: 12, height: 44, flexDirection: 'row', alignItems: 'center', gap: 4 }}>
          <Icon name="receipt-outline" size={16} color={C.blue} />
          <T weight="600" color={C.blue}>Receipt</T>
        </Pressable>
      ),
    });
  } else if (state === 'late' && lateFeeActive()) {
    fee = feeCard({
      tone: [C.red, C.redSoft], act: 'Pay',
      ring: dateBox(C.red, C.redSoft),
      label: `Overdue · due ${dd} ${mon}`,
      labelColor: C.red,
      amount: total,
      line: `${s.daysLate} days late · ${rupees(app.lateFeePerDay)}/day`,
      lineColor: C.red,
      line2: fullBreak,
      btn: payBtn(C.red),
    });
  } else if (state === 'late') {
    fee = feeCard({
      tone: [C.amber, C.amberSoft], act: 'Pay',
      ring: dateBox(C.amber, C.amberSoft),
      label: `Fee due · ${dd} ${mon}`,
      labelColor: C.amber,
      amount: total,
      line: 'Please pay now',
      lineColor: C.amber,
      line2: fullBreak,
      btn: payBtn(C.green),
    });
  } else {
    const left = Math.max(0, s.daysToDue);
    fee = feeCard({
      tone: [C.blue, C.blueSoft], act: 'Pay',
      ring: dateBox(C.blue, C.blueSoft),
      label: paidPart > 0 ? `Part paid · rest due ${dd} ${mon}` : left === 0 ? 'Next fee · due today' : `Next fee · due ${dd} ${mon}`,
      labelColor: paidPart > 0 ? C.amber : C.muted,
      amount: total,
      line: paidPart > 0 && !s.cashPending ? `${rupees(paidPart)} paid of ${rupees(billTotal())}` : s.cashPending ? (s.cashPending.when === 'paid' ? 'Cash paid · waiting for owner' : `Cash ${s.cashPending.when} · owner told`) : left === 0 ? 'Pay today' : `${left} days left${lateFeeActive() ? ` · then +${rupees(app.lateFeePerDay)}/day` : ''}`,
      lineColor: s.cashPending || paidPart > 0 ? C.amber : C.muted,
      line2: fullBreak,
      btn: payBtn(C.green),
    });
  }

  // 25 Oct 2026: a new joiner sees only the booking status until the owner confirms (or rejects)
  if (!s.existing && (s.rejected || waiting)) {
    return (
      <TabPage title="Your booking">
        <BookingStatus />
      </TabPage>
    );
  }

  return (
    <TabPage fill>
      {/* name band (approved "Design 2"): photo, full name, hostel, room & sharing chips */}
      <View style={{ backgroundColor: C.blue, marginTop: -(insets.top + 12), marginHorizontal: -16, paddingTop: insets.top + 16, paddingHorizontal: 18, paddingBottom: 18, borderBottomLeftRadius: 26, borderBottomRightRadius: 26, marginBottom: 12, overflow: 'hidden' }}>
        <SkyBack />
        <Row gap={14}>
          {s.photo ? (
            <Image source={s.photo} style={{ width: 64, height: 64, borderRadius: 32, borderWidth: 3, borderColor: '#fff' }} />
          ) : (
            <View style={{ width: 64, height: 64, borderRadius: 32, borderWidth: 3, borderColor: '#fff', backgroundColor: 'rgba(255,255,255,0.18)', alignItems: 'center', justifyContent: 'center' }}>
              <T size={20} weight="800" color="#fff">{initials(s.name)}</T>
            </View>
          )}
          <View style={{ flex: 1 }}>
            <T size={20} weight="800" color="#fff" numberOfLines={1}>{s.name}</T>
            <T size={12.5} weight="600" color="#D6ECFC" numberOfLines={2}>{hostelTitle(h)}</T>
            <Row gap={6} style={{ marginTop: 8 }}>
              <View style={{ flexDirection: 'row', alignItems: 'center', gap: 5, backgroundColor: 'rgba(255,255,255,0.16)', borderWidth: 1, borderColor: 'rgba(255,255,255,0.35)', borderRadius: 99, paddingHorizontal: 10, paddingVertical: 4 }}>
                <Icon name="bed-outline" size={13} color="#fff" />
                <T size={12.5} weight="600" color="#fff">{s.room} · Bed {s.bed}</T>
              </View>
              <View style={{ backgroundColor: 'rgba(255,255,255,0.16)', borderWidth: 1, borderColor: 'rgba(255,255,255,0.35)', borderRadius: 99, paddingHorizontal: 10, paddingVertical: 4 }}>
                <T size={12.5} weight="600" color="#fff">{s.sharing} sharing</T>
              </View>
            </Row>
          </View>
        </Row>
      </View>

      {s.justApproved ? (
        <Pressable onPress={() => { s.justApproved = false; actions.touch(); }}
          style={{ marginBottom: 10, backgroundColor: C.green, borderRadius: 14, padding: 14, flexDirection: 'row', alignItems: 'center', gap: 12 }}>
          <Icon name="checkmark-circle" size={28} color="#fff" />
          <View style={{ flex: 1 }}>
            <T size={15} weight="800" color="#fff">Bed booked!</T>
            <T size={12.5} color="#DCF3E3">Room {s.room} · Bed {s.bed} is yours. Tap to close.</T>
          </View>
        </Pressable>
      ) : null}
      {s.left ? null : fee}

      {waiting ? (
        <Row gap={10} style={{ backgroundColor: C.amberSoft, borderRadius: 12, padding: 12, marginTop: 10 }}>
          <Icon name="hourglass-outline" color={C.amber} />
          <T weight="600" color={C.amber} style={{ flex: 1 }}>Waiting for the owner to confirm your booking</T>
        </Row>
      ) : null}
      {/* ad space – grows to fill the free space so Home fits one screen */}
      <View style={{ flexGrow: 1, minHeight: 92, marginTop: 12, borderRadius: 16, ...(ad ? { backgroundColor: L.card, borderWidth: L.border ? 1 : 0, borderColor: L.line } : { borderWidth: 1.5, borderStyle: 'dashed', borderColor: L.ad.fg + '80', backgroundColor: L.ad.bg }), padding: 12, justifyContent: 'center' }}>
        {ad ? (
          <>
            <Row style={{ marginBottom: 6 }}>
              <T size={11} weight="600" color={C.muted} style={{ flex: 1, letterSpacing: 0.5 }}>SPONSORED · near you</T>
              <Pressable hitSlop={10} onPress={() => { app.studentAds = []; actions.touch(); }}><Icon name="close" size={16} color={C.muted} /></Pressable>
            </Row>
            <Row gap={12}>
              {icon('ad', ad.icon, 48)}
              <View style={{ flex: 1 }}>
                <T weight="600" size={14}>{ad.shop}</T>
                <T size={12.5} color={C.muted}>{ad.offer}</T>
              </View>
              <Btn title={ad.action} style={{ minHeight: 36, paddingHorizontal: 14, backgroundColor: L.ad.fg, borderColor: L.ad.fg }} onPress={() => toast('Would call the shop.')} />
            </Row>
          </>
        ) : (
          <View style={{ alignItems: 'center' }}>
            <Icon name="megaphone-outline" size={22} color={L.ad.fg} />
            <T weight="600" color={L.ad.fg}>Ad space</T>
            <T size={12.5} color={C.muted} style={{ textAlign: 'center' }}>Local shops can advertise here – shown to students near this hostel.</T>
          </View>
        )}
      </View>

      {(() => {
        // owner's own notices + automatic messages when he changes rent date, notice period or room price
        const KIND = { sharing: 'bed-outline', rent: 'calendar-outline', notice: 'hourglass-outline', price: 'pricetag-outline' };
        const changes = (app.studentMessages || []).map((m) => ({ icon: KIND[m.kind] || 'information-circle-outline', title: m.title, body: m.body, when: m.when || 'New' }));
        const all = [...changes, ...(app.ownerNotices || [])];
        const posted = all.length > 0;
        const list = posted ? all.slice(0, 3) : [app.defaultNotice];
        return (
        <>
          <Row gap={6} style={{ marginTop: 14, marginBottom: 8, paddingHorizontal: 4 }}>
            <T size={14} weight="600">Notice</T>
            {posted ? <View style={{ backgroundColor: C.red, borderRadius: 8, paddingHorizontal: 6, paddingVertical: 1 }}><T size={11} weight="600" color="#fff">NEW</T></View> : null}
          </Row>
          <View style={{ backgroundColor: L.notice.bg, borderRadius: 16, borderWidth: L.border ? 1 : 0, borderColor: L.line, overflow: 'hidden', ...(L.shadow ? { boxShadow: L.shadow } : null) }}>
            {list.map((n, i, arr) => (
              <View key={i} style={{ flexDirection: 'row', alignItems: 'center', gap: 12, paddingHorizontal: 14, paddingVertical: 10, borderBottomWidth: i < arr.length - 1 ? 1 : 0, borderBottomColor: L.line }}>
                {icon('notice', n.icon, 38)}
                <View style={{ flex: 1 }}>
                  <T weight="600">{n.title}</T>
                  <T size={12.5} color={C.muted}>{n.body}</T>
                </View>
                <T size={11} color={C.muted}>{n.when}</T>
              </View>
            ))}
          </View>
        </>
        );
      })()}

      {/* Wi-Fi + leaving: two tiles side by side */}
      <View style={{ flexDirection: 'row', gap: 12, marginTop: 12 }}>
        {wifi ? (
          <View style={tile('wifi')}>
            {mark('wifi', 'wifi')}
            <Row gap={10} style={{ marginBottom: 8 }}>
              {icon('wifi', 'wifi', 36)}
              <T weight="800" size={16} color={L.wifi.title || C.ink}>Wi-Fi</T>
            </Row>
            <T weight="600" size={14} color={L.wifi.title || C.ink} numberOfLines={1}>{wifi.name}</T>
            <T size={12.5} color={L.wifi.text || C.muted} numberOfLines={1}>Password: <T size={12.5} weight="600" color={L.wifi.title || C.ink}>{wifi.password}</T></T>
            <Pressable onPress={() => copyText(wifi.password, 'Wi-Fi password copied')} style={tileBtn('wifi')}>
              <Icon name="copy-outline" size={17} color={L.wifi.btnFg} />
              <T weight="600" color={L.wifi.btnFg}>Copy</T>
            </Pressable>
          </View>
        ) : null}
        {s.left ? (
          <View style={tile('leave')}>
            <Row gap={10} style={{ marginBottom: 8 }}>
              <View style={{ width: 36, height: 36, borderRadius: 18, backgroundColor: C.green, alignItems: 'center', justifyContent: 'center' }}><Icon name="checkmark-done" size={18} color="#fff" /></View>
              <T weight="800" size={16} style={{ flex: 1 }}>You have left</T>
            </Row>
            <T size={12.5} color={C.muted}>Left on <T size={12.5} weight="600">{s.left.on}</T></T>
            <T size={12.5} weight="800" color={s.left.short ? C.red : C.green}>{s.left.short ? 'Short notice – no refund' : `${rupees(s.left.deposit)} deposit settled`}</T>
            <T size={12.5} color={C.muted} style={{ marginTop: 'auto' }}>Thank you for staying with us.</T>
          </View>
        ) : waiting ? null : (
          <View style={tile('leave')}>
            {mark('leave', s.noticeGiven ? 'calendar' : 'log-out')}
            <Row gap={10} style={{ marginBottom: 8 }}>
              {icon('leave', s.noticeGiven ? 'calendar-outline' : 'log-out-outline', 36)}
              <T weight="800" size={16} color={L.leave.title || C.ink} style={{ flex: 1 }}>{s.noticeGiven ? 'Notice given' : 'Leaving?'}</T>
            </Row>
            {s.noticeGiven ? (
              <>
                <T size={12.5} color={L.leave.text || C.muted}>Leaving on <T size={12.5} weight="600" color={L.leave.title || C.ink}>{s.leaveOn}</T></T>
                <T size={12.5} weight="800" color={s.noticeOnTime === false ? C.red : C.green}>{s.noticeOnTime === false ? 'Short notice – no refund' : `${rupees(s.deposit)} deposit back`}</T>
                <Pressable onPress={cancelNotice} style={tileBtn('leave')}><T weight="600" color={L.leave.btnFg}>Cancel notice</T></Pressable>
              </>
            ) : (
              <>
                {onTime ? (
                  <T size={12.5} color={L.leave.text || C.muted}>Give notice by <T size={12.5} weight="600" color={L.leave.title || C.ink}>{deadline}</T> → <T size={12.5} weight="600" color={L.okColor || C.green}>deposit back</T></T>
                ) : (
                  <T size={12.5} color={L.leave.text || C.muted}>Notice date <T size={12.5} weight="600" color={L.leave.title || C.ink}>{deadline}</T> passed → <T size={12.5} weight="600" color={C.red}>no refund</T></T>
                )}
                <Pressable onPress={giveNotice} style={tileBtn('leave')}><T weight="600" color={L.leave.btnFg}>Give notice</T></Pressable>
              </>
            )}
          </View>
        )}
      </View>

    </TabPage>
  );
}

// ---------------------------------------------------------------- Report issue (tab; replaced "My room" 20 Oct 2026)
function IssuesTab() {
  return (
    <TabPage title="Report an issue">
      <IssuesBody />
    </TabPage>
  );
}

// ---------------------------------------------------------------- Settings
// ---------------------------------------------------------------- Settings (student)
function RoomSheet() {
  const s = app.stay;
  return (
    <View>
      <T size={20} weight="800" style={{ marginBottom: 8 }}>My room</T>
      <InfoRow label="Room · bed" value={`${s.room} · Bed ${s.bed}`} bold />
      <InfoRow label="Sharing" value={`${s.sharing} sharing`} />
      <InfoRow label="Floor" value={`Floor ${s.floor}`} />
      <InfoRow label="Joined" value={s.checkIn} />
      <InfoRow label="Monthly rent" value={rupees(s.rent)} />
      <InfoRow label="Deposit" value={rupees(s.deposit)} />
    </View>
  );
}
function RulesSheet() {
  return (
    <View style={{ gap: 8 }}>
      <T size={20} weight="800">House rules</T>
      {(app.hostels[0].rules || []).map((r, k) => (
        <Row key={k} gap={10}><Icon name="checkmark-circle" size={18} color={C.blue} /><T style={{ flex: 1 }}>{r}</T></Row>
      ))}
    </View>
  );
}
function DetailsSheet() {
  const s = app.stay;
  return (
    <View>
      <T size={20} weight="800" style={{ marginBottom: 8 }}>My details</T>
      <InfoRow label="Mobile" value={`+91 ${s.mobile}`} />
      <InfoRow label="ID" value={`Aadhaar •••• ${s.idLast4 || '4821'}`} />
      <InfoRow label="Parent" value={s.parentName ? `${s.parentName} · +91 ${s.parent}` : '+91 94401 22334'} />
      <InfoRow label="Company / institute" value={s.org || 'Wipro, Gachibowli'} />
      <InfoRow label="Home address" value={s.homeAddress || 'Gandhi Nagar, Vijayawada'} />
      <T size={12.5} color={C.muted} style={{ marginTop: 8 }}>To change your details, ask your hostel owner.</T>
    </View>
  );
}
function DemoSheet() {
  useApp();
  return (
    <View>
      <T size={20} weight="800" style={{ marginBottom: 4 }}>Prototype demo</T>
      <T size={12.5} color={C.muted} style={{ marginBottom: 10 }}>Only in the prototype – not in the real app.</T>
      <Chips options={['Before fee date', '4 days late', 'Paid']} value={app.stay.billPaid ? 'Paid' : app.stay.daysLate > 0 ? '4 days late' : 'Before fee date'} onChange={(o) => actions.setFeeDemo(o === 'Paid' ? 'paid' : o === '4 days late' ? 'late' : 'due')} />
      <Gap h={10} />
      <Chips options={['Late fee on', 'Late fee off']} value={app.lateFeeOn ? 'Late fee on' : 'Late fee off'} onChange={(o) => { app.lateFeeOn = o === 'Late fee on'; actions.touch(); }} />
      <Gap h={10} />
      <Chips options={['No ad', 'Sample ad']} value={(app.studentAds || []).length ? 'Sample ad' : 'No ad'} onChange={(o) => { app.studentAds = o === 'Sample ad' ? [app.sampleAd] : []; actions.touch(); }} />
    </View>
  );
}

function SettingsTab() {
  const nav = useNav();
  const s = app.stay;
  const h = app.hostels[0];
  const sheet = (Cmp) => () => showSheet(() => <Cmp />);
  const askDelete = async () => {
    const ok = await confirm({ title: 'Request my data deletion', text: 'Your details and ID copy will be deleted after your stay is closed and dues are settled. The owner keeps payment records as required by law.', confirmLabel: 'Send request', danger: true });
    if (ok) { actions.requestDataDelete(); toast('Deletion request sent to the owner.'); }
  };
  const items = [
    { icon: 'bed-outline', color: C.blue, title: 'My room', sub: 'Floor, joining date, rent, deposit', on: sheet(RoomSheet) },
    { icon: 'document-text-outline', color: C.blue, title: 'House rules', sub: `${(h.rules || []).length} rules`, on: sheet(RulesSheet) },
    { icon: 'person-outline', color: C.blue, title: 'My details', sub: 'Parent, address, ID', on: sheet(DetailsSheet) },
    { icon: 'language-outline', color: C.blue, title: 'Language', sub: app.language, on: () => showSheet((close) => <LanguageList close={close} />) },
    { icon: 'shield-checkmark-outline', color: C.green, title: 'Privacy & terms', sub: 'How your data is kept safe', on: () => nav.push('Privacy') },
    { icon: 'trash-outline', color: C.red, title: 'Delete my data', sub: s.deleteRequested ? 'Requested · owner deletes after you leave' : 'After you leave the hostel', on: s.deleteRequested ? () => toast('Already requested. The owner deletes your data after you leave.') : askDelete },
  ];
  const photo = (size, ring = '#fff') =>
    s.photo ? <Image source={s.photo} style={{ width: size, height: size, borderRadius: size / 2, borderWidth: 3, borderColor: ring }} /> : <Avatar name={s.name} size={size} />;
  const row = (it, i, arr) => (
    <Pressable key={it.title} onPress={it.on} style={{ flexDirection: 'row', alignItems: 'center', gap: 12, paddingHorizontal: 14, paddingVertical: 12, borderBottomWidth: i < arr.length - 1 ? 1 : 0, borderBottomColor: C.line }}>
      <View style={{ width: 40, height: 40, borderRadius: 12, backgroundColor: it.color + '1F', alignItems: 'center', justifyContent: 'center' }}><Icon name={it.icon} size={21} color={it.color} /></View>
      <View style={{ flex: 1 }}>
        <T weight="600" size={14} color={it.color === C.red ? C.red : C.ink}>{it.title}</T>
        <T size={12.5} color={C.muted} numberOfLines={1}>{it.sub}</T>
      </View>
      <Icon name="chevron-forward" size={20} color={C.blue} />
    </Pressable>
  );
  const footer = (
    <>
      <Pressable onPress={sheet(DemoSheet)} style={{ marginTop: 14, alignItems: 'center' }}><T size={12.5} weight="400" color={C.muted}>Prototype demo ›</T></Pressable>
      <Btn variant="text" title="Prototype: back to start" onPress={() => nav.popToTop()} />
    </>
  );

  // approved 20 Oct 2026: name card (photo + name + room/sharing) + grouped list "My stay" / "App"
  const group = (title) => <T size={12.5} weight="600" color={C.muted} style={{ marginTop: 14, marginBottom: 6, paddingHorizontal: 4 }}>{title}</T>;
  return (
    <TabPage title="Settings">
      <Card padding={14}>
        <Row gap={12}>
          {photo(56, C.blueSoft)}
          <View style={{ flex: 1 }}>
            <T size={16} weight="800">{s.name}</T>
            <T color={C.muted}>Room {s.room} · Bed {s.bed} · {s.sharing} sharing</T>
          </View>
        </Row>
      </Card>
      {group('MY STAY')}
      <Card padding={0}>{items.slice(0, 3).map(row)}</Card>
      {group('APP')}
      <Card padding={0}>{items.slice(3).map(row)}</Card>
      {footer}
    </TabPage>
  );
}

// ---------------------------------------------------------------- Fees
/** Full amount or a part now (rest later by any method). */
function AmountPicker({ value, onChange }) {
  const due = billDue();
  const [part, setPart] = useState(value < due);
  const [txt, setTxt] = useState(value < due ? String(value) : '');
  const box = (on, title, sub, onPress) => (
    <Pressable onPress={onPress} style={{ flex: 1, borderWidth: 1.5, borderColor: on ? C.blue : C.line, backgroundColor: on ? C.blueSoft : '#fff', borderRadius: 12, padding: 10 }}>
      <Row gap={6}><Icon name={on ? 'radio-button-on' : 'radio-button-off'} size={18} color={on ? C.blue : C.muted} /><T weight="600" color={on ? C.blue : C.ink}>{title}</T></Row>
      <T size={12.5} color={C.muted} style={{ marginTop: 2, marginLeft: 24 }}>{sub}</T>
    </Pressable>
  );
  return (
    <View style={{ gap: 8 }}>
      <T weight="600">How much now?</T>
      <Row gap={8}>
        {box(!part, `Full ${rupees(due)}`, 'Clear this bill', () => { setPart(false); onChange(due); })}
        {box(part, 'Part now', 'Pay the rest later', () => { setPart(true); onChange(parseInt(txt, 10) || 0); })}
      </Row>
      {part ? (
        <View>
          <Field label="Amount now" prefix="₹" keyboardType="number-pad" value={txt} placeholder="e.g. 4000"
            onChangeText={(v) => { const t = v.replace(/\D/g, ''); setTxt(t); onChange(Math.min(parseInt(t, 10) || 0, due)); }} />
          {parseInt(txt, 10) > 0 && parseInt(txt, 10) < due ? <T size={12.5} weight="800" color={C.amber} style={{ marginTop: -6 }}>{rupees(due - parseInt(txt, 10))} still due after this – pay it later by cash or online.</T> : null}
        </View>
      ) : null}
    </View>
  );
}

// Pay rent by UPI (25 Oct 2026): free, straight to the owner. Tap the app (amount + note filled) →
// receipt → 12 checks (see upiPay.js). Only the apps the owner turned on + Any UPI app.
function OnlinePaySheet({ close, nav }) {
  const s = app.stay;
  const h = app.hostels[0];
  const [total, setTotal] = useState(billDue());
  const note = `SUNRISE-${s.room}${s.bed}-NOV`;
  const okAmount = () => (total > 0 ? true : (toast('Enter the amount you are paying now.'), false));
  const go = (res) => nav.push('UpiReceipt', { purpose: 'rent', amount: total, note, ...res });
  return (
    <View style={{ gap: 10 }}>
      <T size={20} weight="800">Pay {rupees(total)}</T>
      <T size={12.5} weight="600" color={C.green} style={{ marginTop: -6 }}>Straight to the owner · no extra charges · amount is filled in</T>
      <AmountPicker value={total} onChange={setTotal} />
      {h.payUpi !== false ? <UpiTiles onPick={(a) => { if (!okAmount()) return; close(); openUpiApp(a, total, note, go); }} /> : null}
      {h.payUpi !== false ? (
        <Btn variant="outline" icon="qr-code-outline" title="Paying from another phone? Show QR" onPress={() => okAmount() && showSheet(() => <QrSheet amount={total} note={note} />)} />
      ) : null}
      {h.payBank && h.bankDetails ? (
        <Btn variant="outline" icon="business-outline" title="Bank transfer" onPress={() => { if (!okAmount()) return; close(); go({ app: 'Bank transfer', bank: true, fromApp: false, utr: '', seconds: 60 }); }} />
      ) : null}
      <Btn variant="text" title="Close" onPress={close} />
    </View>
  );
}

// Pay by cash: owner's cash timing/place from Hostel settings
function CashSheet({ close }) {
  const h = app.hostels[0];
  const [when, setWhen] = useState('today');
  const [amount, setAmount] = useState(billDue());
  const opts = [
    { key: 'today', icon: 'sunny-outline', label: 'Today' },
    { key: 'tomorrow', icon: 'calendar-outline', label: 'Tomorrow' },
    { key: 'paid', icon: 'checkmark-done-outline', label: 'Already paid' },
  ];
  return (
    <View style={{ gap: 12, alignItems: 'stretch' }}>
      <View style={{ alignItems: 'center', gap: 8 }}>
        <View style={{ width: 64, height: 64, borderRadius: 32, backgroundColor: C.greenSoft, alignItems: 'center', justifyContent: 'center' }}>
          <Icon name="cash-outline" size={32} color={C.green} />
        </View>
        <T size={20} weight="800">Pay in cash</T>
      </View>
      <View style={{ backgroundColor: C.amberSoft, borderRadius: 12, padding: 14, flexDirection: 'row', gap: 10 }}>
        <Icon name="time-outline" size={22} color={C.amber} />
        <T weight="600" style={{ flex: 1, lineHeight: 21 }}>{h.cashNote || 'Pay cash to the owner at the hostel office.'}</T>
      </View>
      <AmountPicker value={amount} onChange={setAmount} />
      <T weight="600">When will you pay?</T>
      <Row gap={8}>
        {opts.map((o) => {
          const on = when === o.key;
          return (
            <Pressable key={o.key} onPress={() => setWhen(o.key)} style={{ flex: 1, alignItems: 'center', gap: 4, paddingVertical: 10, borderRadius: 12, borderWidth: 1.5, borderColor: on ? C.blue : C.line, backgroundColor: on ? C.blueSoft : '#fff' }}>
              <Icon name={o.icon} size={20} color={on ? C.blue : C.muted} />
              <T size={12.5} weight="600" color={on ? C.blue : C.ink}>{o.label}</T>
            </Pressable>
          );
        })}
      </Row>
      <Btn
        icon="notifications-outline"
        title={when === 'paid' ? 'Tell owner I paid' : 'Tell owner'}
        onPress={() => {
          if (!(amount > 0)) return toast('Enter the amount you are paying now.');
          actions.tellOwnerCash(when, amount);
          close();
          toast('Owner is told. He marks it paid when he gets the cash.');
        }}
      />
      <T size={12.5} color={C.muted} style={{ textAlign: 'center', marginTop: -4 }}>The owner gets an alert. Your receipt comes here after he confirms.</T>
    </View>
  );
}

function FeesTab() {
  const nav = useNav();
  const s = app.stay;
  const h = app.hostels[0];
  return (
    <TabPage title="Fees">
      <Card>
        <Row style={{ marginBottom: 10 }}>
          <T size={16} weight="800" style={{ flex: 1 }}>November 2026 bill</T>
          {s.billPaid ? <Pill text="Paid" tone="green" /> : <Pill text={`Due ${s.dueDate}`} tone="amber" />}
        </Row>
        {billParts().map((p) => (
          <InfoRow key={p.key} label={p.label} value={rupees(p.amount)} color={p.key === 'late' ? C.red : undefined} />
        ))}
        <Divider />
        <InfoRow label="Total" value={rupees(billTotal())} bold />
        {billPaidSoFar() > 0 && !s.billPaid ? (
          <>
            <InfoRow label="Paid so far" value={`− ${rupees(billPaidSoFar())}`} color={C.green} />
            <InfoRow label="Still due" value={rupees(billDue())} bold color={C.amber} />
          </>
        ) : null}
      </Card>
      {(s.alerts || []).filter((x) => x.tab === 'fee' && !x.seen).map((x) => (
        <Row key={x.id} gap={10} align="flex-start" style={{ backgroundColor: x.tone === 'bad' ? C.redSoft : C.greenSoft, borderRadius: 12, padding: 12, marginTop: 12 }}>
          <Icon name={x.tone === 'bad' ? 'alert-circle' : 'checkmark-circle'} size={20} color={x.tone === 'bad' ? C.red : C.green} />
          <T weight="600" color={x.tone === 'bad' ? C.red : C.green} style={{ flex: 1 }}>{x.text}</T>
          <Pressable hitSlop={8} onPress={() => { x.seen = true; actions.touch(); }} style={{ backgroundColor: '#fff', borderRadius: 8, paddingHorizontal: 10, paddingVertical: 4 }}>
            <T size={12.5} weight="600" color={x.tone === 'bad' ? C.red : C.green}>OK</T>
          </Pressable>
        </Row>
      ))}
      <Gap h={14} />
      {s.billPaid ? (
        <Card><T color={C.muted}>Nothing to pay right now. We will remind you 3 days before the next rent day.</T></Card>
      ) : (
        <View style={{ gap: 10 }}>
          {s.checkPending ? (
            <Card padding={14} style={{ borderWidth: 1.5, borderColor: '#F6DDB8', backgroundColor: '#FFFBF3' }}>
              <Row gap={12}>
                <View style={{ width: 42, height: 42, borderRadius: 21, backgroundColor: C.amber, alignItems: 'center', justifyContent: 'center' }}><Icon name="hourglass-outline" size={20} color="#fff" /></View>
                <View style={{ flex: 1 }}>
                  <T weight="600">Waiting for owner to confirm</T>
                  <T size={12.5} color={C.muted}>{rupees(s.checkPending.amount)} · UTR …{s.checkPending.utr.slice(-4)} · receipt comes when he confirms</T>
                </View>
              </Row>
            </Card>
          ) : h.payUpi !== false || h.payBank ? (
            <Btn icon="phone-portrait-outline" title={`Pay ${rupees(billDue())} by UPI`} onPress={() => showSheet((close) => <OnlinePaySheet close={close} nav={nav} />)} />
          ) : null}
          {h.payCash && s.cashPending ? (
            <Card padding={14} style={{ borderWidth: 1.5, borderColor: '#F6DDB8', backgroundColor: '#FFFBF3' }}>
              <Row gap={12}>
                <View style={{ width: 42, height: 42, borderRadius: 21, backgroundColor: C.amber, alignItems: 'center', justifyContent: 'center' }}><Icon name="hourglass-outline" size={20} color="#fff" /></View>
                <View style={{ flex: 1 }}>
                  <T weight="600">{s.cashPending.when === 'paid' ? 'Cash paid – owner told' : `Paying cash ${s.cashPending.when} – owner told`}</T>
                  <T size={12.5} color={C.muted}>Waiting for the owner to confirm {rupees(s.cashPending.amount)}</T>
                </View>
              </Row>
              <Row gap={10} style={{ marginTop: 10 }}>
                <Btn small variant="outline" title="Change" style={{ flex: 1 }} onPress={() => showSheet((close) => <CashSheet close={close} />)} />
                <Btn small variant="text" title="Cancel" style={{ flex: 1 }} onPress={() => { actions.cancelCash(); toast('Cancelled. The owner is told.'); }} />
              </Row>
            </Card>
          ) : h.payCash ? <Btn variant="outline" icon="cash-outline" title="Pay by cash" onPress={() => showSheet((close) => <CashSheet close={close} />)} /> : null}
        </View>
      )}
      <SectionTitle>Payment history</SectionTitle>
      {s.receipts.length === 0 ? (
        <Card><T color={C.muted}>No receipts yet. They appear here after the owner confirms your payment.</T></Card>
      ) : (
        s.receipts.map((r, i) => <ReceiptRow key={r.receipt + i} r={r} />)
      )}
    </TabPage>
  );
}

// ---------------------------------------------------------------- Report an issue (from Home)
const CATS = ['Water', 'Electricity', 'Wi-Fi', 'Cleaning', 'Food', 'Furniture', 'Plumbing', 'Security', 'Other'];
function IssuesBody() {
  const [cat, setCat] = useState('Water');
  const [text, setText] = useState('');
  const [photo, setPhoto] = useState(false);
  return (
    <>
      <T color={C.muted} style={{ marginTop: -8, marginBottom: 14 }}>The owner gets it straight away.</T>
      <Chips options={CATS} value={cat} onChange={setCat} />
      <Gap h={14} />
      <Field placeholder="What is the problem? Where exactly?" multiline value={text} onChangeText={setText} />
      <UploadBox label="Photo (optional)" hint="Helps the owner fix it faster" done={photo} onPress={() => setPhoto(!photo)} />
      <Gap h={14} />
      <Btn
        title="Send to owner"
        onPress={() => {
          if (!text.trim()) return toast('Please describe the problem.');
          actions.reportIssue(cat, text.trim(), photo);
          setText('');
          setPhoto(false);
          toast('Sent to owner.');
        }}
      />
      <SectionTitle>My issues</SectionTitle>
      {app.myIssues.length === 0 ? (
        <EmptyState icon="checkmark-circle-outline" title="No issues reported" text="Issues you send appear here with their status." />
      ) : (
        app.myIssues.map((c) => (
          <Card key={c.id} onPress={() => { if (c.seen === false) { c.seen = true; actions.touch(); } }} border={c.seen === false ? C.blue : null} style={{ marginBottom: 8 }}>
            {c.seen === false ? <T size={11} weight="600" color={C.blue} style={{ marginBottom: 4 }}>NEW UPDATE · tap to mark read</T> : null}
            <Row>
              <Pill text={c.category} tone="grey" />
              <View style={{ flex: 1 }} />
              {c.status === 'open' ? <Pill text="Open" tone="amber" /> : c.status === 'inProgress' ? <Pill text="In progress" /> : <Pill text="Resolved" tone="green" />}
            </Row>
            <T style={{ marginTop: 8 }}>{c.text}</T>
            {c.reply ? <T weight="600" color={C.blue} style={{ marginTop: 8 }}>Owner: {c.reply}</T> : null}
            <T size={12.5} color={C.muted} style={{ marginTop: 4 }}>{c.time}</T>
          </Card>
        ))
      )}
    </>
  );
}

export function StudentIssues() {
  return (
    <Screen title="Report an issue">
      <IssuesBody />
    </Screen>
  );
}

