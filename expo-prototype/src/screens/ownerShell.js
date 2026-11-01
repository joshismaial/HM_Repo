// Owner inside a hostel: 5-tab bar (Home, Requests, Tenants, Rent, More).
import React, { useState } from 'react';
import { Image, Pressable, ScrollView, Switch, TextInput, View, useWindowDimensions } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useBackHandler, useNav } from '../nav';
import { closeSheet, confirm, showSheet, toast } from '../overlay';
import { PhotoSheet } from './owner';
import { ChecksList, ReceiptThumb, ReceiptView } from './upiPay';
import {
  actions, app, bedLabel, typeLabel, hostelTitle, dueToday, TODAY_LABEL, initials, collectedRent, countBeds, expectedRent, hostel, lateFee, openComplaints, pendingTenants, requestCount, roomTable, rupees, totalBeds, unreadCount, useApp,
} from '../state';
import {
  Avatar, Btn, C, Card, Chips, EmptyState, Field, Gap, Icon, IconBox, InfoRow, LanguageList, MenuGroup, MenuRow, Pill, ProgressBar, Row,
  Screen, SectionTitle, Segmented, SkyBack, StatTile, SwitchRow, T, TabBar, TabPage, rentPill, typePill, BuildingArt, ShortNameBox, HostelPhoto,
} from '../ui';

export function OwnerShell() {
  useApp();
  const [tab, setTab] = useState(0);
  // Requests tab: which half is open ('pay' or 'join'). Home shortcuts choose it, the tab bar leaves it as it was.
  const [reqTab, setReqTab] = useState('pay');
  const goTo = (i, sub) => {
    if (i === 1 && sub) setReqTab(sub);
    setTab(i);
  };
  const goHome = () => setTab(0);
  // phone back button: a non-Home tab goes back to Home first (then back leaves the hostel)
  useBackHandler(() => {
    if (tab !== 0) {
      setTab(0);
      return true;
    }
    return false;
  });
  const pages = [
    <HomeTab key="0" goTo={goTo} />,
    <RequestsTab key="1" goHome={goHome} tab={reqTab} setTab={setReqTab} />,
    <RoomsTab key="2" goHome={goHome} />,
    <RentTab key="3" goHome={goHome} goRequests={() => goTo(1, 'pay')} />,
    <MoreTab key="4" goHome={goHome} />,
  ];
  const rc = requestCount();
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
          { label: 'Requests', icon: 'file-tray', badge: rc || null },
          { label: 'Rooms', icon: 'bed' },
          { label: 'Rent', icon: 'cash' },
          { label: 'More', icon: 'grid', badge: unreadCount() || null },
        ]}
      />
    </View>
  );
}

// ======================================================================
// Tab 1: Hostel home
// ======================================================================
// Hostel home colours (Trust blue top, darker text for contrast).
const OR = { bg: '#1560BD', dark: '#FFFFFF', mid: '#D6ECFC', soft: '#E8F0FA', line: '#B9CDEB', chip: 'rgba(255,255,255,0.16)', chipLine: 'rgba(255,255,255,0.4)' };
const HC = { ink: '#14213D', muted: '#5C6782', blue: '#1560BD', green: '#15803D', red: '#DC2626', purple: '#1560BD', due: '#9C3A0E', dueBar: '#B8621C' };
// cards: thin border (stays visible on dim, low-cost screens) + very light shadow
const SHADOW = { shadowColor: '#0F172A', shadowOpacity: 0.06, shadowRadius: 2, shadowOffset: { width: 0, height: 1 }, elevation: 1 };
const card = { backgroundColor: '#fff', borderRadius: 16, borderWidth: 1, borderColor: '#DCE3EC', ...SHADOW };

function Bar({ pct, color, bg }) {
  return (
    <View style={{ height: 8, borderRadius: 4, backgroundColor: bg, overflow: 'hidden', marginTop: 7 }}>
      <View style={{ width: `${Math.max(0, Math.min(100, pct))}%`, height: 8, borderRadius: 4, backgroundColor: color }} />
    </View>
  );
}

function CardHead({ title, right }) {
  return (
    <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' }}>
      <T size={12.5} weight="600" color={HC.muted}>{title}</T>
      {right}
    </View>
  );
}

function Faces({ names }) {
  const shown = names.slice(0, 3);
  const extra = names.length - shown.length;
  const cols = ['#A8401A', '#9C420E', '#B8621C'];
  const dot = (label, bg, i) => (
    <View key={label + i} style={{ width: 24, height: 24, borderRadius: 12, backgroundColor: bg, borderWidth: 2, borderColor: '#fff', marginLeft: i ? -6 : 0, alignItems: 'center', justifyContent: 'center' }}>
      <T size={11} weight="600" color="#fff">{label}</T>
    </View>
  );
  return (
    <View style={{ flexDirection: 'row', justifyContent: 'flex-end' }}>
      {shown.map((n, i) => dot(initials(n), cols[i % 3], i))}
      {extra > 0 ? dot(`+${extra}`, '#6B7A90', shown.length) : null}
    </View>
  );
}

function HomeTile({ icon, color, bg, value, label, sub, dot, onPress }) {
  return (
    <Pressable onPress={onPress} accessibilityRole="button" accessibilityLabel={`${label}: ${value}`}
      style={({ pressed }) => ({ flex: 1, flexDirection: 'row', alignItems: 'center', gap: 10, ...card, borderRadius: 16, paddingVertical: 8, paddingHorizontal: 10, opacity: pressed ? 0.85 : 1 })}>
      <View style={{ width: 34, height: 34, borderRadius: 12, backgroundColor: bg, alignItems: 'center', justifyContent: 'center' }}>
        <Icon name={icon} size={17} color={color} />
      </View>
      <View style={{ flex: 1, minWidth: 0 }}>
        <T size={20} weight="800" color={HC.ink} numberOfLines={1}>{value}</T>
        <T size={12.5} weight="600" color={HC.ink} numberOfLines={1}>{label}</T>
        <T size={11} weight="400" color={HC.muted} numberOfLines={1}>{sub}</T>
      </View>
      <Icon name="chevron-forward" size={18} color={HC.blue} />
      {dot ? <View style={{ position: 'absolute', top: 8, right: 8, minWidth: 20, height: 20, borderRadius: 10, paddingHorizontal: 5, backgroundColor: HC.red, alignItems: 'center', justifyContent: 'center' }}><T size={11} weight="600" color="#fff">{value}</T></View> : null}
    </Pressable>
  );
}

function SmallPill({ icon, title, onPress, white }) {
  return (
    <Pressable onPress={onPress} accessibilityRole="button" hitSlop={6}
      style={({ pressed }) => ({ flex: 1, flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 6, height: 32, paddingHorizontal: 8, borderRadius: 16, backgroundColor: white ? '#FFFFFF' : OR.soft, borderWidth: 1, borderColor: OR.line, opacity: pressed ? 0.7 : 1 })}>
      <Icon name={icon} size={14} color="#1560BD" />
      <T size={12.5} weight="600" color="#1560BD" numberOfLines={1}>{title}</T>
    </Pressable>
  );
}

// Static count tile: just a number and label, not tappable.
function BedBox({ n, label, color, bg, small }) {
  return (
    <View accessible accessibilityLabel={`${n} ${label}`}
      style={{ flex: 1, backgroundColor: bg, borderRadius: 12, paddingVertical: small ? 3 : 5, alignItems: 'center' }}>
      <T size={small ? 16 : 20} weight="800" color={color}>{n}</T>
      <T size={11} weight="600" color={color}>{label}</T>
    </View>
  );
}

/** Staff login: the home shows only what this staff member's duties allow, plus today's jobs. */
function StaffHome({ goTo }) {
  useApp();
  const st = app.staff[0] || { name: 'Staff', duties: [], custom: [], checklist: '' };
  const h = hostel();
  const [done, setDone] = useState({});
  const has = (d) => st.duties.includes(d);
  const today = dueToday();
  const jobs = (st.checklist || '').split(/\s*·\s*|\n/).map((x) => x.trim()).filter(Boolean);
  const card = (icon, title, value, onPress) => (
    <Card onPress={onPress} style={{ marginTop: 10 }}>
      <Row gap={10}>
        <Icon name={icon} size={22} color={C.blue} />
        <T weight="800" size={16} style={{ flex: 1 }}>{title}</T>
        {value != null ? <T weight="800" size={20}>{value}</T> : null}
      </Row>
    </Card>
  );
  return (
    <ScrollView style={{ flex: 1, backgroundColor: '#F2F5F9' }} contentContainerStyle={{ padding: 16, paddingTop: 50 }}>
      <T size={20} weight="800">Hi {st.name.split(' ')[0]} 👋</T>
      <T color={C.muted}>Staff · {hostelTitle(h)}</T>
      {has('rent') ? card('cash-outline', `Rent to collect today · ${today.unpaid.length} students`, rupees(today.pending), () => goTo(3)) : null}
      {has('approve') ? card('person-add-outline', 'New students to approve', app.joinRequests.length, () => goTo(1, 'join')) : null}
      {has('complaints') ? card('construct-outline', 'Open complaints', app.complaints.filter((c) => c.status !== 'resolved').length, () => goTo(4)) : null}
      {has('rooms') ? card('bed-outline', 'Free beds', app.rooms.reduce((n, r) => n + r.beds.filter((b) => b === 'vacant').length, 0), () => goTo(2)) : null}
      {has('checklist') || st.custom.some((c) => c.on) ? (
        <Card style={{ marginTop: 10 }}>
          <Row gap={10} style={{ marginBottom: 6 }}>
            <Icon name="checkbox-outline" size={22} color={C.blue} />
            <T weight="800" size={16}>Today's jobs</T>
          </Row>
          {[...(has('checklist') ? jobs : []), ...st.custom.filter((c) => c.on).map((c) => c.name)].map((j) => (
            <Pressable key={j} onPress={() => setDone({ ...done, [j]: !done[j] })} style={{ flexDirection: 'row', alignItems: 'center', gap: 10, paddingVertical: 7 }}>
              <Icon name={done[j] ? 'checkbox' : 'square-outline'} size={22} color={done[j] ? C.green : C.muted} />
              <T weight="600" style={{ flex: 1, textDecorationLine: done[j] ? 'line-through' : 'none' }}>{j}</T>
            </Pressable>
          ))}
        </Card>
      ) : null}
    </ScrollView>
  );
}

function HomeTab(props) {
  return app.isStaff ? <StaffHome {...props} /> : <OwnerHomeTab {...props} />;
}

function OwnerHomeTab({ goTo }) {
  // Owner Home (22 Oct 2026): header = My hostels / Switch, "Name – Type" (up to 2 lines) and area;
  // Payments card (month + today, eye hides amounts); Needs your action (incl. Available beds); Invite students.
  useApp();
  const nav = useNav();
  const insets = useSafeAreaInsets();
  const h = hostel();
  const staff = app.isStaff;
  const free = countBeds('vacant');
  const total = totalBeds();
  const got = collectedRent();
  const expected = expectedRent();
  const today = dueToday();
  const payToConfirm = app.paymentRequests.filter((p) => !p.online).length;
  const joins = app.joinRequests.length;
  const freeRooms = app.rooms.filter((r) => r.beds.includes('vacant')).length;
  const hide = !!app.hideAmounts; // remembered while the app is open
  const money = (v) => (hide ? '₹ ••••' : rupees(v));
  const unpaidNames = today.unpaid.map((t) => t.name.split(' ')[0]);
  const chip = { backgroundColor: OR.chip, borderWidth: 1, borderColor: OR.chipLine };
  const openAvailable = () => {
    app.roomsFilter = 'Available';
    app.roomsFilterSeq = (app.roomsFilterSeq || 0) + 1;
    goTo(2);
  };
  const winH = useWindowDimensions().height;
  // Home must fit one screen (measured 22 Oct 2026): compact spacing below 860 high, extra compact below 800.
  const tight = winH < 860;
  const xtight = winH < 800;
  const gap = xtight ? 6 : tight ? 8 : 10;
  const [viewH, setViewH] = useState(0);
  const [contentH, setContentH] = useState(0);

  // one half of the Payments card (no bar): received (green), "of total", then what's left in red on its own line
  const half = (label, received, of, left) => (
    <View style={{ flex: 1, minWidth: 0, paddingHorizontal: 12, paddingTop: 2, paddingBottom: 8 }}>
      <T size={11} weight="600" color={HC.muted} numberOfLines={1}>{label}</T>
      <T size={20} weight="800" color={hide ? HC.ink : HC.green} numberOfLines={1} fit={0.6} style={hide ? { letterSpacing: 2 } : null}>{money(received)}</T>
      <T size={11} weight="400" color={HC.muted} numberOfLines={1} fit={0.7}>of {money(of)}</T>
      {left > 0 || hide ? (
        <T size={12.5} weight="800" color={HC.red} numberOfLines={1} fit={0.7}>{money(left)} left</T>
      ) : (
        <T size={12.5} weight="800" color={HC.green} numberOfLines={1}>All paid</T>
      )}
    </View>
  );
  const actionRow = (icon, color, bg, title, count, onPress, sub, last) => (
    <Pressable key={title} onPress={onPress} accessibilityRole="button" accessibilityLabel={`${title}: ${count}`}
      style={({ pressed }) => ({ flexDirection: 'row', alignItems: 'center', gap: 10, flex: 1, minHeight: xtight ? 32 : tight ? 36 : 40, paddingVertical: tight ? 2 : 3, borderBottomWidth: last ? 0 : 1, borderBottomColor: '#EEF2F6', opacity: pressed ? 0.7 : 1 })}>
      <View style={{ width: tight ? 30 : 34, height: tight ? 30 : 34, borderRadius: 12, backgroundColor: bg, alignItems: 'center', justifyContent: 'center' }}>
        <Icon name={icon} size={tight ? 16 : 18} color={color} />
      </View>
      <View style={{ flex: 1 }}>
        <T size={14} weight="600">{title}</T>
        {sub ? <T size={11} weight="400" color={HC.muted}>{sub}</T> : null}
      </View>
      <View style={{ minWidth: 24, height: 24, borderRadius: 12, paddingHorizontal: 6, backgroundColor: bg, alignItems: 'center', justifyContent: 'center' }}>
        <T size={12.5} weight="800" color={color}>{count}</T>
      </View>
      <Icon name="chevron-forward" size={18} color={HC.blue} />
    </Pressable>
  );

  return (
    // Home fits the screen: the action rows grow or shrink with the phone height. Scrolling switches on only
    // if a very small phone still can't fit everything (nothing is ever cut off).
    <ScrollView style={{ flex: 1, backgroundColor: '#F2F5F9' }} contentContainerStyle={{ flexGrow: 1, paddingBottom: 8 }}
      scrollEnabled={contentH > viewH + 1} onLayout={(e) => setViewH(e.nativeEvent.layout.height)} onContentSizeChange={(w, hh) => setContentH(hh)}>
      {/* ---------- blue top ---------- */}
      <View style={{ backgroundColor: OR.bg, paddingTop: insets.top + 6, paddingBottom: tight ? 26 : 30, paddingHorizontal: 16 }}>
        <View style={{ flexDirection: 'row', alignItems: 'center', gap: 8 }}>
          {staff ? (
            <T size={12.5} weight="600" color={OR.dark} style={{ flex: 1 }}>Staff login</T>
          ) : (
            <>
              <Pressable accessibilityLabel="Back to My hostels" onPress={() => nav.pop()} style={[chip, { width: 38, height: 38, borderRadius: 19, alignItems: 'center', justifyContent: 'center' }]}>
                <Icon name="chevron-back" size={20} color={OR.dark} />
              </Pressable>
              <T size={14} weight="600" color={OR.dark} style={{ flex: 1 }}>My hostels</T>
              <Pressable accessibilityLabel="Switch hostel" onPress={() => nav.pop()} style={[chip, { flexDirection: 'row', alignItems: 'center', gap: 6, height: 34, paddingHorizontal: 12, borderRadius: 17 }]}>
                <Icon name="swap-horizontal" size={15} color={OR.dark} />
                <T size={12.5} weight="600" color={OR.dark}>Switch</T>
              </Pressable>
            </>
          )}
        </View>
        {/* name and type: one line if it fits, otherwise 2 lines (text shrinks a little rather than a 3rd line) */}
        <T size={20} weight="800" color={OR.dark} numberOfLines={2} fit style={{ marginTop: tight ? 10 : 14, lineHeight: 25 }}>{hostelTitle(h)}</T>
        <Row gap={4} style={{ marginTop: 4 }}>
          <Icon name="location-outline" size={14} color={OR.mid} />
          <T size={12.5} weight="400" color={OR.mid} numberOfLines={1} style={{ flexShrink: 1 }}>{h.area}</T>
        </Row>
      </View>

      {/* ---------- light sheet ---------- */}
      <View style={{ flex: 1, marginTop: -22, backgroundColor: '#F2F5F9', borderTopLeftRadius: 24, borderTopRightRadius: 24, paddingTop: 7 }}>
        {tight ? null : <View style={{ width: 40, height: 4, borderRadius: 2, backgroundColor: '#C5CEDB', alignSelf: 'center', marginBottom: 8 }} />}
        <View style={{ flex: 1, paddingHorizontal: 16, gap }}>
          {/* payments: month and today side by side; eye hides the amounts */}
          <View style={{ ...card }}>
            <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: 12, paddingTop: tight ? 6 : 8 }}>
              <T size={12.5} weight="600" color={HC.muted}>Payments</T>
              <Pressable accessibilityRole="button" accessibilityLabel={hide ? 'Show amounts' : 'Hide amounts'} hitSlop={8}
                onPress={() => { app.hideAmounts = !hide; actions.touch(); }}
                style={({ pressed }) => ({ width: tight ? 28 : 32, height: tight ? 28 : 32, borderRadius: 16, backgroundColor: '#E8F0FA', alignItems: 'center', justifyContent: 'center', opacity: pressed ? 0.7 : 1 })}>
                <Icon name={hide ? 'eye-off-outline' : 'eye-outline'} size={18} color={HC.blue} />
              </Pressable>
            </View>
            <Pressable onPress={() => goTo(3)} accessibilityRole="button" accessibilityLabel="Open rent" style={{ flexDirection: 'row' }}>
              {half('Month · October', got, expected, Math.max(0, expected - got))}
              <View style={{ width: 1, backgroundColor: '#EEF2F6', marginBottom: 8 }} />
              {half(`Today · ${TODAY_LABEL}`, today.paid, today.total, today.pending)}
            </Pressable>
            <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', borderTopWidth: 1, borderTopColor: '#EEF2F6', paddingHorizontal: 12, paddingVertical: 6, gap: 8 }}>
              <T size={12.5} weight="400" color={HC.muted} numberOfLines={1} style={{ flex: 1 }}>
                {unpaidNames.length ? `${unpaidNames.join(', ')} not paid today` : 'Everyone due today has paid'}
              </T>
              {unpaidNames.length ? (
                <Pressable accessibilityRole="button" onPress={() => toast(`Reminder sent to ${unpaidNames.join(', ')}.`)}
                  style={({ pressed }) => ({ backgroundColor: HC.blue, borderRadius: 12, paddingHorizontal: 12, paddingVertical: 6, opacity: pressed ? 0.85 : 1 })}>
                  <T size={12.5} weight="600" color="#fff">Remind</T>
                </Pressable>
              ) : null}
            </View>
          </View>

          {/* needs your action */}
          <View style={{ ...card, flex: 1, paddingHorizontal: 12, paddingTop: 8, paddingBottom: 2 }}>
            <T size={12.5} weight="600" color={HC.muted}>Needs your action</T>
            {actionRow('cash-outline', HC.blue, '#E8F0FA', 'Confirm payments', payToConfirm, () => goTo(1, 'pay'))}
            {actionRow('person-add-outline', '#0F6E56', '#E1F5EE', 'Approve joins', joins, () => goTo(1, 'join'))}
            {actionRow('construct-outline', '#A32D2D', '#FCEBEB', 'Complaints', openComplaints(), () => nav.push('Complaints'))}
            {actionRow('log-out-outline', '#534AB7', '#EEEDFE', 'Leaving notices', app.notices.length, () => nav.push('LeavingNotices'))}
            {actionRow('bed-outline', '#3B6D11', '#EAF3DE', 'Available beds', free, openAvailable, `In ${freeRooms} ${freeRooms === 1 ? 'room' : 'rooms'} · ${total} total`, true)}
          </View>

          {/* invite (22 Oct 2026, "light blue card"): pale blue card + blue border, white QR box, bigger text, same size */}
          <Pressable onPress={() => nav.push('InviteStudents')} accessibilityRole="button" accessibilityLabel="Invite students"
            style={({ pressed }) => ({ flexDirection: 'row', alignItems: 'center', gap: 12, ...card, backgroundColor: '#E8F0FA', borderColor: '#B9CDEB', padding: 10, opacity: pressed ? 0.9 : 1 })}>
            <View style={{ alignItems: 'center', gap: 4 }}>
              <View style={{ width: tight ? 48 : 60, height: tight ? 48 : 60, borderRadius: 12, backgroundColor: '#FFFFFF', alignItems: 'center', justifyContent: 'center' }}>
                <Icon name="qr-code" size={tight ? 34 : 44} color={HC.ink} />
              </View>
              <Pressable accessibilityRole="button" accessibilityLabel="Download QR code" hitSlop={8} onPress={() => toast('QR code saved to your phone (Photos / Gallery).')}
                style={({ pressed }) => ({ flexDirection: 'row', alignItems: 'center', gap: 3, opacity: pressed ? 0.6 : 1 })}>
                <Icon name="download-outline" size={13} color={HC.blue} />
                <T size={11} weight="600" color={HC.blue}>Download</T>
              </Pressable>
            </View>
            <View style={{ flex: 1, gap: 8 }}>
              <View>
                <T size={16} weight="800" color="#0C447C" numberOfLines={1}>Invite students</T>
                <T size={14} weight="600" color="#0C447C" numberOfLines={1}>Scan this QR to join</T>
              </View>
              <View style={{ flexDirection: 'row', gap: 8 }}>
                <SmallPill white icon="share-social-outline" title="Share link" onPress={() => toast('Would open the share menu with your hostel link.')} />
                <SmallPill white icon="print-outline" title="Poster" onPress={() => toast('An A4 poster PDF with the QR would be created.')} />
              </View>
            </View>
          </Pressable>
        </View>
      </View>
    </ScrollView>
  );
}

// ======================================================================
// Tab 2: Requests (payments + join requests)
// ======================================================================
function AmountSheet({ p, close }) {
  const [amount, setAmount] = useState(String(p.amount));
  return (
    <View>
      <T size={20} weight="800">Amount received</T>
      <T color={C.muted} style={{ marginTop: 4, marginBottom: 14, lineHeight: 20 }}>
        Check your bank / UPI app for UTR {p.utr || '—'}. Change the amount if it was a part payment.
      </T>
      <Field label="Amount received" prefix="₹" keyboardType="number-pad" value={amount} onChangeText={setAmount} />
      <Btn
        title="Confirm received & send receipt"
        onPress={() => {
          const a = parseInt(amount, 10) || p.amount;
          actions.confirmPayment(p, a);
          close();
          toast(a < p.amount ? `Part payment ${rupees(a)} recorded. ${rupees(p.amount - a)} still due.` : `Confirmed. Receipt sent to ${p.tenantName}.`);
        }}
      />
    </View>
  );
}

function PaymentCard({ p }) {
  const received = () => showSheet((close) => <AmountSheet p={p} close={close} />);
  return (
    <Card border={p.duplicateUtr ? C.red : null} style={{ marginBottom: 12 }}>
      <Row gap={10}>
        <Avatar name={p.tenantName} size={40} />
        <View style={{ flex: 1 }}>
          <T weight="600">{p.tenantName}</T>
          <T size={12.5} color={C.muted}>{p.room} · {p.time}</T>
        </View>
        <T size={20} weight="800">{rupees(p.amount)}</T>
      </Row>
      <Row gap={6} style={{ marginTop: 10, flexWrap: 'wrap' }}>
        <Pill text={p.method} tone="grey" />
        <Pill text={p.purpose} tone="grey" />
        {p.online ? <Pill text="Auto-confirmed" tone="green" icon="flash" /> : null}
        {p.pendingCheck ? <Pill text={p.pass ? `${p.checks.length} of ${p.checks.length} checks · check your bank` : 'Checks failed · check your bank'} tone={p.pass ? 'green' : 'amber'} /> : null}
      </Row>
      <PayChecks p={p} name={p.tenantName} />
      {p.check ? (
        <View style={{ backgroundColor: '#FFF7E6', borderRadius: 12, padding: 10, marginTop: 10 }}>
          <Row gap={8}><Icon name="search-outline" size={17} color={C.amber} /><T size={12.5} weight="600" color={C.amber}>Student says paid – check your bank / UPI</T></Row>
          <T size={12.5} color={C.ink} style={{ marginTop: 4 }}>Look for {rupees(p.amount)} with note {p.note}</T>
        </View>
      ) : null}
      {!p.online && p.utr ? (
        <View style={{ marginTop: 10 }}>
          <InfoRow label="UTR" value={p.utr} />
          <InfoRow label="Payment note" value={p.note} />
        </View>
      ) : null}
      {p.duplicateUtr ? (
        <Row gap={8} align="flex-start" style={{ backgroundColor: C.redSoft, borderRadius: 12, padding: 10, marginTop: 6 }}>
          <Icon name="warning-outline" size={18} color={C.red} />
          <T size={12.5} weight="600" color={C.red} style={{ flex: 1 }}>This UTR was already used by another payment. Check your bank before confirming.</T>
        </Row>
      ) : null}
      {p.join ? (
        <View style={{ backgroundColor: C.blueSoft, borderRadius: 12, padding: 10, marginTop: 10 }}>
          <T size={12.5} weight="600" color={C.blue}>New tenant · approve to add them and fill the bed</T>
          <T size={12.5} color={C.ink} style={{ marginTop: 4 }}>Mobile {p.join.mobile} · Parent {p.join.parent || '—'}</T>
          {p.join.org ? <T size={12.5} color={C.ink}>{p.join.org}</T> : null}
        </View>
      ) : null}
      <Gap h={12} />
      {p.pendingCheck && p.pass ? (
        <Row gap={10}>
          <Btn
            style={{ flex: 1 }}
            variant="dangerOutline"
            title="Not received"
            onPress={async () => {
              const ok = await confirm({ title: `${rupees(p.amount)} not in your bank?`, text: `${p.tenantName} is told to check and pay again. This UTR is blocked.`, confirmLabel: 'Not received', danger: true });
              if (ok) { actions.rejectPayment(p); toast(`${p.tenantName} is told.`); }
            }}
          />
          <Btn style={{ flex: 1.4 }} variant="success" title="Confirm" onPress={() => { actions.confirmPayment(p, p.amount); toast('Confirmed. Receipt sent to the student.'); }} />
        </Row>
      ) : p.join && p.online ? (
        <Btn title="Approve tenant" icon="checkmark" onPress={() => { actions.confirmPayment(p); toast(`${p.join.name} added to Tenants. Bed filled.`); }} />
      ) : p.online ? (
        <Btn variant="outline" title="OK, remove from list" onPress={() => actions.confirmPayment(p)} />
      ) : p.method === 'Cash' ? (
        <Row gap={10}>
          <Btn
            style={{ flex: 1 }}
            variant="dangerOutline"
            title="Not received"
            onPress={async () => {
              const ok = await confirm({ title: 'Cash not received?', text: `${p.tenantName} gets a message to pay at the office and tell you again.`, confirmLabel: 'Not received', danger: true });
              if (ok) { actions.rejectPayment(p); toast(`${p.tenantName} is told.`); }
            }}
          />
          <Btn style={{ flex: 1 }} title="Cash received" onPress={received} />
        </Row>
      ) : (
        <Row gap={10}>
          <Btn
            style={{ flex: 1 }}
            variant="dangerOutline"
            title="Not received"
            onPress={async () => {
              const ok = await confirm({ title: 'Mark as not received?', text: `${p.tenantName} will get an SMS to check the payment and submit the correct UTR.`, confirmLabel: 'Not received', danger: true });
              if (ok) actions.rejectPayment(p);
            }}
          />
          <Btn style={{ flex: 1 }} title="Received" onPress={received} />
        </Row>
      )}
    </Card>
  );
}

// New joiner (25 Oct 2026): details + payment on one card, one Confirm booking button (Reject needs a reason).
const REJECT_REASONS = ['Wrong details', 'Aadhaar not clear', 'Payment not received', 'Bed not available', 'Other'];
function RejectSheet({ p, close }) {
  const [reason, setReason] = useState('');
  return (
    <View>
      <T size={20} weight="800">Reject {p.join.name}?</T>
      <T size={12.5} color={C.muted} style={{ marginTop: 4 }}>Room {p.join.room} · Bed {bedLabel(p.join.bedIndex)} becomes free for others again</T>
      <T size={12.5} weight="600" color={C.muted} style={{ marginTop: 16, marginBottom: 8 }}>REASON (PICK ONE)</T>
      <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 8 }}>
        {REJECT_REASONS.map((r) => (
          <Pressable key={r} onPress={() => setReason(r)}
            style={{ paddingHorizontal: 14, height: 36, borderRadius: 18, justifyContent: 'center', borderWidth: 1.2,
              borderColor: reason === r ? C.red : C.line, backgroundColor: reason === r ? C.redSoft : '#fff' }}>
            <T size={12.5} weight="600" color={reason === r ? C.red : C.ink}>{r}</T>
          </Pressable>
        ))}
      </View>
      <T size={12.5} color={C.muted} style={{ marginTop: 14 }}>The student sees this reason. Return the money they paid ({rupees(p.amount)}).</T>
      <Gap h={14} />
      <Btn variant="danger" title="Reject" disabled={!reason}
        onPress={() => { actions.rejectJoiner(p, reason); close(); toast(`${p.join.name} is told. Bed is free again.`); }} />
    </View>
  );
}

/** Receipt + 12-check summary on a payment (25 Oct 2026). Tap the receipt to see what the app read. */
function PayChecks({ p, name }) {
  if (!p.checks || !p.receipt) return null;
  const okN = p.checks.filter((c) => c.state === 'ok').length;
  const failed = p.checks.filter((c) => c.state !== 'ok');
  const view = () => showSheet(() => <ReceiptView p={{ name, receipt: p.receipt, amount: p.amount, utr: p.utr, app: p.app }} />);
  return (
    <Row gap={12} align="flex-start" style={{ marginTop: 10 }}>
      <ReceiptThumb r={p.receipt} width={52} onPress={view} />
      <View style={{ flex: 1 }}>
        <T size={12.5} weight="800" color={failed.length ? C.amber : C.green}>
          {failed.length ? `${failed.length} of ${p.checks.length} checks failed` : `All ${p.checks.length} checks passed`}
        </T>
        {failed.slice(0, 4).map((c) => (
          <Row key={c.label} gap={6} style={{ marginTop: 2 }}>
            <Icon name={c.state === 'soft' ? 'alert-circle' : 'close-circle'} size={15} color={c.state === 'soft' ? C.amber : C.red} />
            <T size={12} style={{ flex: 1 }}>{c.label}</T>
          </Row>
        ))}
        <Pressable onPress={view} hitSlop={6}><T size={12} weight="600" color={C.blue} style={{ marginTop: 4 }}>View receipt</T></Pressable>
      </View>
    </Row>
  );
}

function DocView({ title }) {
  return (
    <View>
      <T size={20} weight="800" style={{ marginBottom: 12 }}>{title}</T>
      <View style={{ height: 180, borderRadius: 12, backgroundColor: C.ground, alignItems: 'center', justifyContent: 'center', gap: 8 }}>
        <Icon name="lock-closed-outline" size={40} color={C.muted} />
        <T color={C.muted} center>Opened with a 60-second private link</T>
      </View>
    </View>
  );
}

function JoinerCard({ p }) {
  const j = p.join;
  const doc = (label, sub, flex) => (
    <Pressable onPress={() => showSheet(() => <DocView title={label} />)}
      style={{ flex, height: 64, borderRadius: 10, backgroundColor: '#DDE4EE', alignItems: 'center', justifyContent: 'center' }}>
      <T size={12.5} weight="600" color={C.muted}>{label}</T>
      {sub ? <T size={11} color={C.muted}>{sub}</T> : null}
    </Pressable>
  );
  return (
    <Card style={{ marginBottom: 12 }}>
      <Row>
        <Pill text="New joiner" />
        <View style={{ flex: 1 }} />
        <T size={11} color={C.muted}>{p.time}</T>
      </Row>
      <T size={18} weight="800" style={{ marginTop: 8 }}>{j.name}</T>
      <T size={12.5} color={C.muted}>Room {j.room} · Bed {bedLabel(j.bedIndex)} · Monthly</T>

      <T size={11} weight="600" color={C.muted} style={{ marginTop: 14, marginBottom: 6, letterSpacing: 0.5 }}>DETAILS</T>
      <Row gap={8}>
        {doc('Photo', null, 1)}
        {doc('Aadhaar photo', j.idLast4 ? `XXXX XXXX ${j.idLast4} · tap to view` : 'tap to view', 2.6)}
      </Row>
      <Gap h={8} />
      <InfoRow label="Mobile" value={`+91 ${j.mobile}`} />
      <InfoRow label="Parent mobile" value={j.parent ? `+91 ${j.parent}` : '—'} />
      {j.reference ? <InfoRow label="Reference" value={j.reference} /> : null}
      {j.org ? <InfoRow label="College / office" value={j.org} /> : null}
      {j.homeAddress ? <InfoRow label="Home address" value={j.homeAddress} /> : null}

      <View style={{ height: 1, backgroundColor: C.line, marginVertical: 10 }} />
      <T size={11} weight="600" color={C.muted} style={{ marginBottom: 6, letterSpacing: 0.5 }}>PAYMENT</T>
      <InfoRow label="Rent + deposit" value={rupees(p.amount)} bold color={C.green} />
      <InfoRow label="Method" value={p.app ? `${p.method} · ${p.app}` : p.method} />
      {p.utr ? <InfoRow label="UTR" value={p.utr} /> : null}
      {p.note ? <InfoRow label="Note" value={p.note} /> : null}
      {p.duplicateUtr ? (
        <Row gap={8} align="flex-start" style={{ backgroundColor: C.redSoft, borderRadius: 10, padding: 10, marginTop: 6 }}>
          <Icon name="warning-outline" size={18} color={C.red} />
          <T size={12.5} weight="600" color={C.red} style={{ flex: 1 }}>This UTR was already used by another payment.</T>
        </Row>
      ) : null}
      <PayChecks p={p} name={j.name} />
      {p.online ? null : (
        <View style={{ backgroundColor: C.amberSoft, borderRadius: 10, padding: 10, marginTop: 6 }}>
          <T size={12.5} weight="600" color={C.amber}>{p.method === 'Cash' ? `Check you got ${rupees(p.amount)} cash first` : `Check your bank app for ${rupees(p.amount)} first`}</T>
        </View>
      )}
      <Gap h={14} />
      <Row gap={10}>
        <Btn style={{ flex: 1 }} variant="dangerOutline" title="Reject" onPress={() => showSheet((close) => <RejectSheet p={p} close={close} />)} />
        <Btn style={{ flex: 2.2 }} variant="success" title="Confirm booking"
          onPress={() => { actions.confirmPayment(p, p.amount); toast(`${j.name} booked. Room ${j.room} · Bed ${bedLabel(j.bedIndex)}.`); }} />
      </Row>
    </Card>
  );
}

function JoinCard({ j }) {
  return (
    <Card style={{ marginBottom: 12 }}>
      <Row gap={10}>
        <Avatar name={j.name} size={40} />
        <View style={{ flex: 1 }}>
          <T weight="600">{j.name}</T>
          <T size={12.5} color={C.muted}>+91 {j.mobile} · {j.time}</T>
        </View>
      </Row>
      <Row gap={6} style={{ marginTop: 10, flexWrap: 'wrap' }}>
        <Pill text={`Room ${j.room} · Bed ${j.bed}`} />
        <Pill text={j.stayType === 'monthly' ? 'Monthly' : 'Day-wise'} tone="grey" />
        {j.existing ? <Pill text={`Existing tenant · joined ${j.joinedOn}`} tone="purple" /> : null}
      </Row>
      <T size={12.5} color={C.muted} style={{ marginTop: 6 }}>ID and photo added · consent given</T>
      <Gap h={12} />
      <Row gap={10}>
        <Btn
          style={{ flex: 1 }}
          variant="dangerOutline"
          title="Reject"
          onPress={async () => {
            const ok = await confirm({ title: `Reject ${j.name}?`, text: 'They get an SMS. The bed becomes free again.', confirmLabel: 'Reject', danger: true });
            if (ok) actions.rejectJoin(j);
          }}
        />
        <Btn
          style={{ flex: 1 }}
          title="Approve"
          onPress={() => {
            actions.approveJoin(j);
            toast(`${j.name} approved. Welcome SMS sent.`);
          }}
        />
      </Row>
    </Card>
  );
}

function RequestsTab({ goHome, tab, setTab }) {
  const pays = app.paymentRequests;
  const joins = app.joinRequests;
  return (
    <TabPage title="Requests" onBack={goHome}>
      <Segmented options={[{ value: 'pay', label: `Payments (${pays.length})` }, { value: 'join', label: `Join requests (${joins.length})` }]} value={tab} onChange={setTab} />
      <Gap h={14} />
      {tab === 'pay'
        ? pays.length === 0
          ? <EmptyState icon="checkmark-done" title="All payments confirmed" text="New UPI, bank and cash payments appear here." />
          : [...pays.filter((p) => p.join), ...pays.filter((p) => !p.join)].map((p) => (p.join ? <JoinerCard key={p.id} p={p} /> : <PaymentCard key={p.id} p={p} />))
        : joins.length === 0
          ? <EmptyState icon="person-add-outline" title="No join requests" text="Share your hostel QR or link to get students." />
          : joins.map((j) => <JoinCard key={j.id} j={j} />)}
    </TabPage>
  );
}

// ======================================================================
// Tab 3: Tenants
// ======================================================================
// Rooms tab: only FREE beds, one card per bed ("201 A", "201 B"), grouped by floor, filtered by
// sharing. Full rooms and beds on hold are hidden. Tap a bed to book it.
// Rooms are added / edited in More → Hostel settings → Rooms (Add room, Rooms & beds).
const RG = { green: '#15803D', soft: '#DDF3E8', line: '#CDEEDC', blue: '#1560BD', blueSoft: '#E8F0FA', sheet: '#F2F5F9' };
const floorTitle = (f) => (f === 0 ? 'Ground floor' : `Floor ${f}`);
/** ₹6,500 → ₹6.5k (keeps the small bed card on one line) */
const shortRupees = (v) => (v < 1000 ? rupees(v) : `₹${(v / 1000).toFixed(1).replace(/\.0$/, '')}k`);

function RoomsTab({ goHome }) {
  const nav = useNav();
  useApp();
  const insets = useSafeAreaInsets();
  const winW = useWindowDimensions().width;
  const h = hostel();
  const [sharing, setSharing] = useState(0); // 0 = all
  const free = [];
  app.rooms.forEach((r) => r.beds.forEach((b, i) => { if (b === 'vacant') free.push({ r, i }); }));
  const sharings = [...new Set(app.rooms.map((r) => r.sharing))].sort((a, b) => a - b);
  const shown = free.filter((x) => !sharing || x.r.sharing === sharing);
  const roomsShown = new Set(shown.map((x) => x.r.number)).size;
  const floors = [...new Set(shown.map((x) => x.r.floor))].sort((a, b) => a - b);
  const total = totalBeds();
  const pct = total ? Math.round((100 * countBeds('filled')) / total) : 0;
  const cols = winW >= 600 ? 6 : 4;
  const cardW = Math.floor((Math.min(winW, 640) - 32 - 6 * (cols - 1)) / cols);
  const chip = { backgroundColor: OR.chip, borderWidth: 1, borderColor: OR.chipLine };
  // Book → "Share with student" QR screen for this bed
  const book = (r, i) => (app.isStaff ? toast('Only the owner can book beds.') : nav.push('ShareBed', { room: r.number, bedIndex: i }));
  const stat = (v, label, color) => (
    <View style={{ flex: 1, alignItems: 'center' }}>
      <T size={20} weight="800" color={color}>{v}</T>
      <T size={11} weight="400" color={C.muted} numberOfLines={1}>{label}</T>
    </View>
  );
  const divider = <View style={{ width: 1, height: 28, backgroundColor: C.line }} />;
  return (
    <ScrollView style={{ flex: 1, backgroundColor: RG.sheet }} contentContainerStyle={{ paddingBottom: 24 }}>
      {/* peach header: back, type, Switch · hostel name, area · stats */}
      <View style={{ backgroundColor: OR.bg, paddingTop: insets.top + 6, paddingHorizontal: 16, paddingBottom: 16, borderBottomLeftRadius: 26, borderBottomRightRadius: 26 , overflow: 'hidden' }}>
        <SkyBack />
        <View style={{ flexDirection: 'row', alignItems: 'center', gap: 8 }}>
          <Pressable accessibilityLabel="Back to Home" onPress={goHome} style={[chip, { width: 38, height: 38, borderRadius: 19, alignItems: 'center', justifyContent: 'center' }]}>
            <Icon name="chevron-back" size={20} color={OR.dark} />
          </Pressable>
          <View style={[chip, { paddingHorizontal: 10, paddingVertical: 4, borderRadius: 99 }]}>
            <T size={11} weight="600" color={OR.dark}>{typeLabel(h.type)} · Rooms</T>
          </View>
          <View style={{ flex: 1 }} />
          <Pressable accessibilityLabel="Switch hostel" onPress={() => nav.pop()} style={[chip, { flexDirection: 'row', alignItems: 'center', gap: 6, height: 34, paddingHorizontal: 12, borderRadius: 17 }]}>
            <Icon name="swap-horizontal" size={16} color={OR.dark} />
            <T size={12.5} weight="600" color={OR.dark}>Switch</T>
          </Pressable>
        </View>
        <T size={20} weight="800" color={OR.dark} numberOfLines={2} fit style={{ marginTop: 10, lineHeight: 25 }}>{hostelTitle(h)}</T>
        <View style={{ flexDirection: 'row', alignItems: 'center', gap: 3, marginTop: 2 }}>
          <Icon name="location-outline" size={15} color={OR.mid} />
          <T size={12.5} weight="600" color={OR.mid} numberOfLines={1}>{h.area}</T>
        </View>
        <View style={{ flexDirection: 'row', alignItems: 'center', backgroundColor: '#fff', borderRadius: 16, paddingVertical: 10, paddingHorizontal: 6, marginTop: 12 }}>
          {/* whole-hostel numbers: they don't change with the sharing filter */}
          {stat(countBeds('filled'), 'occupied', RG.blue)}
          {divider}
          {stat(free.length, 'available', RG.green)}
          {divider}
          {stat(`${pct}%`, 'occupied %', RG.blue)}
        </View>
      </View>

      <View style={{ paddingHorizontal: 16, paddingTop: 14 }}>
        {/* sharing filter with the free-bed count on each chip */}
        <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ gap: 6, alignItems: 'center' }}>
          <T size={12.5} weight="400" color={C.muted} style={{ marginRight: 2 }}>Sharing</T>
          {[0, ...sharings].map((n) => {
            const on = sharing === n;
            const count = n ? free.filter((x) => x.r.sharing === n).length : free.length;
            return (
              <Pressable key={n} onPress={() => setSharing(n)} accessibilityRole="button" accessibilityState={{ selected: on }}
                accessibilityLabel={`${n ? `${n} sharing` : 'All'}: ${count} free beds`}
                style={{ flexDirection: 'row', alignItems: 'center', gap: 6, paddingLeft: 12, paddingRight: 7, paddingVertical: 6, borderRadius: 16, borderWidth: 1, borderColor: on ? RG.green : C.line, backgroundColor: on ? RG.green : '#fff' }}>
                <T size={12.5} weight="600" color={on ? '#fff' : C.ink}>{n ? String(n) : 'All'}</T>
                <View style={{ backgroundColor: on ? '#fff' : RG.soft, borderRadius: 8, paddingHorizontal: 7, paddingVertical: 1 }}>
                  <T size={11} weight="600" color={RG.green}>{count}</T>
                </View>
              </Pressable>
            );
          })}
        </ScrollView>
        <View style={{ flexDirection: 'row', alignItems: 'center', marginTop: 14 }}>
          <T size={14} weight="600" style={{ flex: 1 }}>{shown.length} {shown.length === 1 ? 'bed' : 'beds'} free{sharing ? ` · ${sharing} sharing` : ''}</T>
          {shown.length ? <T size={12.5} weight="400" color={C.muted}>Tap Book to share QR</T> : null}
        </View>
        {!shown.length ? (
          <EmptyState icon="bed-outline" title="No free beds" text={sharing ? `Every ${sharing}-sharing bed is filled or on hold.` : 'Every bed is filled or on hold. Add rooms in More → Hostel settings.'} />
        ) : null}
        {floors.map((f) => {
          const list = shown.filter((x) => x.r.floor === f);
          return (
            <View key={f}>
              <View style={{ flexDirection: 'row', alignItems: 'center', marginTop: 14, marginBottom: 8, paddingHorizontal: 2 }}>
                <T size={12.5} weight="600" color={C.muted} style={{ flex: 1, letterSpacing: 0.3 }}>{floorTitle(f).toUpperCase()}</T>
                <T size={12.5} weight="600" color={RG.green}>{list.length} free</T>
              </View>
              <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 6 }}>
                {list.map(({ r, i }) => (
                  <View key={r.number + i} style={{ width: cardW, backgroundColor: '#fff', borderRadius: 12, borderWidth: 1.2, borderColor: RG.line, paddingHorizontal: 7, paddingTop: 6, paddingBottom: 7 }}>
                    <View style={{ flexDirection: 'row', alignItems: 'center', gap: 3 }}>
                      <T size={14} weight="600" numberOfLines={1}>{r.number}</T>
                      <View style={{ backgroundColor: RG.soft, borderRadius: 8, paddingHorizontal: 4 }}>
                        <T size={12.5} weight="600" color={RG.green}>{bedLabel(i)}</T>
                      </View>
                      <View style={{ flex: 1 }} />
                      {r.features.includes('AC') ? (
                        <View style={{ backgroundColor: RG.blueSoft, borderRadius: 4, paddingHorizontal: 3 }}>
                          <T size={11} weight="600" color={RG.blue}>AC</T>
                        </View>
                      ) : null}
                    </View>
                    <T size={11} color={C.muted} numberOfLines={1}>{r.sharing} sh · {shortRupees(r.rent)}</T>
                    <Pressable onPress={() => book(r, i)} accessibilityRole="button"
                      accessibilityLabel={`Book room ${r.number} bed ${bedLabel(i)}, ${r.sharing} sharing, ${rupees(r.rent)} a month`}
                      style={({ pressed }) => ({ marginTop: 5, backgroundColor: RG.green, borderRadius: 8, paddingVertical: 5, alignItems: 'center', opacity: pressed ? 0.8 : 1 })}>
                      <T size={12.5} weight="600" color="#fff">Book</T>
                    </Pressable>
                  </View>
                ))}
              </View>
            </View>
          );
        })}
      </View>
    </ScrollView>
  );
}

/** Tenants list (opened from the Tenants tile on Home). */
export function TenantsScreen() {
  useApp();
  return (
    <Screen title="Tenants" right={<Btn small variant="text" icon="download-outline" title="Excel" onPress={() => toast(`Excel file would download: tenants_${hostel().name}.xlsx`)} />}>
      <TenantsList />
    </Screen>
  );
}

function TenantsList() {
  const nav = useNav();
  const [q, setQ] = useState('');
  const [filter, setFilter] = useState('All');
  const list = app.tenants.filter((t) => {
    const mq = !q || t.name.toLowerCase().includes(q.toLowerCase()) || t.room.includes(q) || t.mobile.replace(/ /g, '').includes(q);
    const mf =
      filter === 'Paid' ? t.status === 'paid'
        : filter === 'Rent due' ? t.status === 'pending' || t.status === 'late'
          : filter === 'Leaving' ? t.status === 'notice'
            : filter === 'Day-wise' ? t.stayType === 'dayWise'
              : true;
    return mq && mf;
  });
  return (
    <View>
      <Row gap={8} style={{ backgroundColor: '#fff', borderRadius: 12, borderWidth: 1.2, borderColor: C.line, paddingHorizontal: 12, minHeight: 48 }}>
        <Icon name="search" color={C.muted} />
        <TextInput value={q} onChangeText={setQ} placeholder="Search name, room or mobile" placeholderTextColor="#9AA7B8" style={{ flex: 1, fontSize: 15, color: C.ink, paddingVertical: 10 }} />
      </Row>
      <Gap h={10} />
      <Chips options={['All', 'Paid', 'Rent due', 'Leaving', 'Day-wise']} value={filter} onChange={setFilter} />
      <T weight="400" color={C.muted} style={{ marginTop: 12, marginBottom: 8 }}>{list.length} tenants</T>
      {list.length === 0 ? (
        <EmptyState icon="search" title="No tenants found" text="Try another name or filter." />
      ) : (
        <Card padding={0}>
          {list.map((t, i) => (
            <Pressable key={t.id} onPress={() => nav.push('TenantDetails', { id: t.id })} style={{ flexDirection: 'row', alignItems: 'center', gap: 12, padding: 12, borderBottomWidth: i < list.length - 1 ? 1 : 0, borderBottomColor: C.line }}>
              <Avatar name={t.name} size={42} />
              <View style={{ flex: 1 }}>
                <T weight="600">{t.name}</T>
                <T size={12.5} color={C.muted}>Room {t.room} · Bed {t.bed}{t.stayType === 'dayWise' ? ' · Day-wise' : ''}</T>
              </View>
              {rentPill(t)}
            </Pressable>
          ))}
        </Card>
      )}
    </View>
  );
}

// ======================================================================
// Tab 4: Rent
// ======================================================================
function ChargeSheet({ room, value, close }) {
  const [v, setV] = useState(String(value));
  return (
    <View>
      <T size={20} weight="800" style={{ marginBottom: 12 }}>Room {room} electricity</T>
      <Field prefix="₹" keyboardType="number-pad" value={v} onChangeText={setV} />
      <T size={12.5} color={C.muted} style={{ marginTop: -6, marginBottom: 14 }}>Split equally between tenants of this room.</T>
      <Btn
        title="Save"
        onPress={() => {
          app.electricityByRoom[room] = parseInt(v, 10) || 0;
          actions.touch();
          close();
        }}
      />
    </View>
  );
}

/** Rent status in the prototype: late, due (rent day today), upcoming (later this month), paid. */
function rentStatus(t) {
  if (t.status === 'paid') return 'paid';
  if (t.status === 'part') return 'due'; // part paid: still something to collect
  if (t.status === 'late') return 'late';
  return t.dueToday ? 'due' : 'upcoming';
}
const RENT_TONE = { late: C.red, due: C.amber, upcoming: C.blue, paid: C.green };

// 25 Oct 2026: student payments are confirmed only in Home › Confirm payments (Requests › Payments).
// The Rent tab just points there.
function ToConfirmLink({ goRequests }) {
  const n = app.paymentRequests.filter((p) => !p.join).length;
  if (!n) return null;
  return (
    <Pressable onPress={goRequests} style={{ flexDirection: 'row', alignItems: 'center', backgroundColor: C.blueSoft, borderRadius: 12, padding: 12, marginBottom: 10 }}>
      <T size={13} weight="600" color={C.blue} style={{ flex: 1 }}>{n} {n === 1 ? 'payment' : 'payments'} to confirm · Home › Confirm payments</T>
      <Icon name="chevron-forward" size={18} color={C.blue} />
    </Pressable>
  );
}

function RentTab({ goHome, goRequests }) {
  const nav = useNav();
  const [filter, setFilter] = useState('all');
  const [month, setMonth] = useState('October');
  const order = ['late', 'due', 'upcoming', 'paid'];
  const rows = [...app.tenants].map((t) => ({ t, s: rentStatus(t), fee: lateFee(t) }))
    .sort((a, b) => order.indexOf(a.s) - order.indexOf(b.s) || b.t.daysLate - a.t.daysLate);
  const of = (s) => rows.filter((r) => r.s === s);
  const sum = (list) => list.reduce((x, r) => x + r.t.rent + r.fee, 0);
  const expected = expectedRent();
  const collected = collectedRent();
  const pct = expected ? Math.round((collected / expected) * 100) : 0;
  const late = of('late');
  const toPay = [...of('due'), ...of('upcoming')];
  const dt = dueToday();
  const toRemind = late.length + of('due').length;
  // "All" = due today, late and paid; future rent only under "Upcoming"
  const allRows = rows.filter((r) => r.s !== 'upcoming');
  const shown = filter === 'all' ? allRows : of(filter);
  const auto = app.autoRemind !== false;
  const feeOn = app.lateFeeOn && app.lateFeePerDay > 0;
  const paidToday = app.tenants.filter((t) => t.dueToday && t.status === 'paid').length;

  const box = (title, right, tiles, footer) => (
    <View style={{ backgroundColor: '#fff', borderRadius: 16, paddingHorizontal: 12, paddingVertical: 10, marginBottom: 10, boxShadow: '0 1px 2px rgba(15,23,42,0.06)', borderWidth: 1, borderColor: '#DCE3EC' }}>
      <Row style={{ justifyContent: 'space-between', alignItems: 'center' }}>
        {title}
        <T size={11} weight="400" color={C.muted} numberOfLines={1} style={{ flexShrink: 1, textAlign: 'right', marginLeft: 8 }}>{right}</T>
      </Row>
      <Row gap={6} style={{ marginTop: 8 }}>
        {tiles.map(([label, value, color, sub]) => (
          <View key={label} style={{ flex: 1, backgroundColor: color + '14', borderRadius: 12, paddingHorizontal: 8, paddingVertical: 8 }}>
            <T size={11} weight="600" color={color} numberOfLines={1}>{label}</T>
            <T size={16} weight="800" color={color} numberOfLines={1} adjustsFontSizeToFit>{value}</T>
            <T size={11} color={C.muted} numberOfLines={1}>{sub}</T>
          </View>
        ))}
      </Row>
      {footer}
    </View>
  );

  const editLateFee = () => showSheet((close) => <LateFeeSheet close={close} />);

  const openTenant = (t, s, fee) => {
    if (s === 'paid') return nav.push('TenantDetails', { id: t.id });
    showSheet((close) => (
      <View>
        <T size={20} weight="800">{t.name}</T>
        <T color={C.muted}>Room {t.room} · {rupees(t.rent + fee)}</T>
        <Gap />
        <MenuRow icon="card-outline" title="Record payment" onPress={() => { close(); nav.push('RecordPayment', { id: t.id }); }} />
        <MenuRow icon="logo-whatsapp" title="Send WhatsApp reminder" onPress={() => { close(); toast(`WhatsApp reminder opened for ${t.name}.`); }} />
        <MenuRow icon="person-outline" title="Open tenant details" onPress={() => { close(); nav.push('TenantDetails', { id: t.id }); }} />
      </View>
    ));
  };

  const statusText = (t, s) => {
    if (s === 'late') return `${t.daysLate} days late`;
    if (t.status === 'part') return `Part paid · ${rupees(t.dueLeft)} due`;
    if (s === 'due') return 'Due today';
    if (s === 'upcoming') return `Due ${t.dueDate}`;
    const p = t.payments[0];
    return p ? `Paid ${p.date} · ${p.method}` : 'Paid';
  };

  return (
    <TabPage
      fixed
      title="Rent"
      onBack={goHome}
      right={!app.isStaff ? (
        <Row gap={4}>
          <Pressable onPress={() => nav.push('Reports')} style={{ padding: 8 }}><Icon name="bar-chart-outline" size={22} color={C.ink} /></Pressable>
          <Pressable onPress={() => nav.push('HostelSettings')} style={{ padding: 8 }}><Icon name="settings-outline" size={22} color={C.ink} /></Pressable>
        </Row>
      ) : null}
    >
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingHorizontal: 16, paddingBottom: 16 }}>
        <ToConfirmLink goRequests={goRequests} />
        {box(
          <Pressable onPress={() => showSheet((close) => (
            <View>
              <T size={20} weight="800" style={{ marginBottom: 8 }}>Choose month</T>
              {['October', 'September', 'August', 'July'].map((m) => (
                <MenuRow key={m} icon="calendar-outline" title={`${m} 2026`} onPress={() => { close(); setMonth(m); if (m !== 'October') toast('Prototype shows October numbers for every month.'); }} />
              ))}
            </View>
          ))} style={{ flexDirection: 'row', alignItems: 'center' }}>
            <T size={14} weight="600">{month}</T>
            <Icon name="caret-down" size={14} color={C.ink} />
          </Pressable>,
          `${rupees(collected)} of ${rupees(expected)} · ${pct}%`,
          [
            ['Collected', rupees(collected), C.green, `${of('paid').length} paid`],
            ['Still to pay', rupees(sum(toPay)), C.amber, `${toPay.length} tenants`],
            ['Late now', rupees(sum(late)), C.red, `${late.length} tenants`],
          ],
        )}
        {box(
          <T size={14} weight="600">Today · {TODAY_LABEL}</T>,
          `${dt.unpaid.length + paidToday} tenants due`,
          [
            ['Collected', rupees(dt.paid), C.green, `${paidToday} paid`],
            ['Still to pay', rupees(dt.pending), C.amber, `${dt.unpaid.length} tenants`],
            ['Late now', rupees(sum(late)), C.red, `${late.length} tenants`],
          ],
          <Pressable onPress={() => { app.autoRemind = !auto; actions.touch(); }} style={{ flexDirection: 'row', alignItems: 'center', gap: 5, marginTop: 4 }}>
            <Icon name="notifications-outline" size={16} color={C.blue} />
            <T size={12.5} weight="600" color={C.blue}>Auto-remind</T>
            <T size={12.5} color={C.muted} numberOfLines={1} style={{ flex: 1 }}>3 days before & on rent day</T>
            <Switch value={auto} onValueChange={(v) => { app.autoRemind = v; actions.touch(); }} style={{ transform: [{ scale: 0.8 }] }} />
          </Pressable>,
        )}
        <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ gap: 6, paddingBottom: 8 }}>
          {[['all', 'All', allRows.length], ['late', 'Late', late.length], ['due', 'Due', of('due').length], ['upcoming', 'Upcoming', of('upcoming').length], ['paid', 'Paid', of('paid').length]].map(([k, label, n]) => (
            <Pressable key={k} onPress={() => setFilter(k)} style={{ flexDirection: 'row', alignItems: 'center', gap: 6, paddingHorizontal: 12, paddingVertical: 6, borderRadius: 99, borderWidth: 1, borderColor: filter === k ? (RENT_TONE[k] || C.ink) : C.line, backgroundColor: filter === k ? (RENT_TONE[k] || C.ink) : '#fff' }}>
              {k !== 'all' && filter !== k ? <View style={{ width: 8, height: 8, borderRadius: 4, backgroundColor: RENT_TONE[k] }} /> : null}
              <T size={12.5} weight="600" color={filter === k ? '#fff' : C.ink}>{label} {n}</T>
            </Pressable>
          ))}
        </ScrollView>
        {shown.length === 0 ? (
          <EmptyState icon="happy-outline" title="Everyone has paid" text="Nothing here this month." />
        ) : (
          <Card padding={0}>
            {shown.map(({ t, s, fee }, i) => (
              <Pressable key={t.id} onPress={() => openTenant(t, s, fee)} style={{ flexDirection: 'row', alignItems: 'center', gap: 10, paddingHorizontal: 12, paddingVertical: 11, borderBottomWidth: i === shown.length - 1 ? 0 : 1, borderBottomColor: '#EEF1F5' }}>
                {t.photo ? (
                  // small thumbnail (~10 KB) made on the phone at upload; full photo only in tenant details
                  <Image source={t.photo} style={{ width: 40, height: 40, borderRadius: 20, borderWidth: 2, borderColor: RENT_TONE[s] }} />
                ) : (
                  <View style={{ width: 40, height: 40, borderRadius: 20, alignItems: 'center', justifyContent: 'center', backgroundColor: RENT_TONE[s] + '1F' }}>
                    <T size={12.5} weight="600" color={RENT_TONE[s]}>{initials(t.name)}</T>
                  </View>
                )}
                <View style={{ flex: 1 }}>
                  <T weight="600" numberOfLines={1}>{t.name}</T>
                  {fee > 0 ? (
                    <T size={12.5} color={C.muted} numberOfLines={1}>Room {t.room} · {rupees(t.rent)} + <T size={12.5} weight="800" color={C.red}>{rupees(fee)} fee</T></T>
                  ) : (
                    <T size={12.5} color={C.muted}>Room {t.room}</T>
                  )}
                </View>
                <View style={{ alignItems: 'flex-end' }}>
                  <T weight="800">{rupees(t.rent + fee)}</T>
                  <T size={12.5} weight="600" color={RENT_TONE[s]}>{statusText(t, s)}</T>
                </View>
              </Pressable>
            ))}
          </Card>
        )}
        <T size={12.5} color={C.muted} center style={{ marginTop: 8 }}>Tap a tenant to record payment or send reminder</T>
      </ScrollView>
      {toRemind > 0 ? (
        <View style={{ paddingHorizontal: 16, paddingVertical: 10, borderTopWidth: 1, borderTopColor: C.line, backgroundColor: C.ground }}>
          <Btn
            icon="megaphone-outline"
            title={`Send reminder to all · ${toRemind} unpaid`}
            onPress={async () => {
              const ok = await confirm({ title: `Remind ${toRemind} tenants?`, text: 'Each gets an SMS with the amount (incl. late fee), due date and your hostel name. Tenants reminded in the last 12 hours are skipped.', confirmLabel: 'Send reminders' });
              if (ok) toast(`Reminders sent: ${toRemind}`);
            }}
          />
        </View>
      ) : null}
    </TabPage>
  );
}

/** Late fee: on/off, amount per day, example, Save. */
function LateFeeSheet({ close }) {
  const [on, setOn] = useState(true);
  const [amount, setAmount] = useState(String(app.lateFeePerDay > 0 ? app.lateFeePerDay : 50));
  const per = parseInt(amount, 10) || 0;
  return (
    <View>
      <T size={20} weight="800">Late fee</T>
      <T size={12.5} color={C.muted} style={{ marginBottom: 12 }}>Charged for every day after the rent day until paid</T>
      <Card padding={0} style={{ borderWidth: 1, borderColor: C.line }}>
        <SwitchRow title="Charge late fee" value={on} onChange={setOn} last />
      </Card>
      {on ? (
        <>
          <Gap h={12} />
          <Field label="Amount per day" prefix="₹" keyboardType="number-pad" value={amount} onChangeText={setAmount} />
          <Chips options={['20', '30', '50', '100']} value={amount} onChange={setAmount} />
          {per > 0 ? (
            <View style={{ backgroundColor: '#FFF7E8', borderRadius: 12, padding: 10, marginTop: 12 }}>
              <T size={12.5} color="#5B4100">Example: rent ₹8,000, paid 17 days late → 17 × {rupees(per)} = {rupees(17 * per)} fee · total {rupees(8000 + 17 * per)}</T>
            </View>
          ) : null}
        </>
      ) : null}
      <Gap h={14} />
      <Btn
        title="Save"
        onPress={() => {
          if (on && per <= 0) return toast('Enter the amount per day.');
          app.lateFeeOn = on;
          if (per > 0) app.lateFeePerDay = per;
          actions.touch();
          close();
          toast('Late fee saved');
        }}
      />
    </View>
  );
}

// ======================================================================
// Tab 5: More
// ======================================================================
function MoreTab({ goHome }) {
  const nav = useNav();
  const staff = app.isStaff;
  const h = hostel();
  // Simple More: Hostel (Tenants, Hostel settings, Staff, Invite, Reports) and You (settings, privacy, help, log out).
  // Notifications are on the Home bell; Language is inside App settings; Rooms from tenants is in Hostel settings.
  const privacySheet = () => showSheet((close) => (
    <View style={{ gap: 4 }}>
      <T size={20} weight="800" style={{ marginBottom: 6 }}>Privacy & account</T>
      <MenuGroup>
        <MenuRow icon="shield-checkmark-outline" title="Privacy policy" onPress={() => { close(); nav.push('Privacy'); }} />
        <MenuRow icon="document-text-outline" title="Terms of use" onPress={() => { close(); nav.push('Privacy'); }} />
        <MenuRow icon="cloud-download-outline" title="Download my data" onPress={() => { close(); toast('We will SMS a download link within 24 hours.'); }} />
        {!staff ? <MenuRow icon="trash-outline" color={C.red} title="Delete account" onPress={() => { close(); nav.push('DeleteAccount'); }} /> : null}
      </MenuGroup>
    </View>
  ));
  const helpSheet = () => showSheet((close) => (
    <View style={{ gap: 4 }}>
      <T size={20} weight="800" style={{ marginBottom: 6 }}>Help</T>
      <MenuGroup>
        <MenuRow icon="logo-whatsapp" title="WhatsApp support" onPress={() => { close(); toast('WhatsApp support would open here.'); }} />
        <MenuRow icon="help-circle-outline" title="FAQs" onPress={() => { close(); toast('FAQs would open here.'); }} />
        <MenuRow icon="bug-outline" color={C.muted} title="Error & test screens" sub="Prototype only" onPress={() => { close(); nav.push('DemoScreens'); }} />
      </MenuGroup>
    </View>
  ));
  const fix = !staff ? roomTable().filter((x) => x.status === 'fix').length : 0;
  return (
    <TabPage title="More" onBack={goHome}>
      <Row gap={12}>
        <Avatar name={staff ? 'Ramesh Warden' : app.ownerName} size={48} />
        <View style={{ flex: 1 }}>
          <T size={16} weight="800">{staff ? 'Ramesh (Warden)' : app.ownerName}</T>
          <T color={C.muted}>{staff ? 'Staff' : 'Owner'} · {hostelTitle(h)}</T>
        </View>
      </Row>
      <SectionTitle>Hostel</SectionTitle>
      <MenuGroup>
        <MenuRow icon="people-outline" title="Tenants/Students List" onPress={() => nav.push('Tenants')} />
        {!staff ? (
          <MenuRow icon="options-outline" title="Hostel settings" right={fix ? <Pill text={`${fix} rooms to fix`} tone="amber" /> : null} onPress={() => nav.push('HostelSettings')} />
        ) : null}
        {!staff ? <MenuRow icon="id-card-outline" title="Staff" onPress={() => nav.push('StaffLogins')} /> : null}
        <MenuRow icon="megaphone-outline" title="Notice to students" sub={(app.ownerNotices || []).length ? `${app.ownerNotices.length} active` : 'Default: Keep the hostel clean'} onPress={() => nav.push('StudentNotices')} />
        <MenuRow icon="qr-code-outline" title="Invite students" onPress={() => nav.push('InviteStudents')} />
        {!staff ? <MenuRow icon="bar-chart-outline" title="Reports" onPress={() => nav.push('Reports')} /> : null}
        {!staff && app.removedHostels.length > 0 ? (
          <MenuRow icon="file-tray-full-outline" title={`Removed hostels (${app.removedHostels.length})`} onPress={() => nav.push('RemovedHostels')} />
        ) : null}
      </MenuGroup>
      <SectionTitle>You</SectionTitle>
      <MenuGroup>
        <MenuRow icon="settings-outline" title="App settings & language" onPress={() => nav.push('AppSettings')} />
        <MenuRow icon="shield-checkmark-outline" title="Privacy & account" onPress={privacySheet} />
        <MenuRow icon="help-circle-outline" title="Help" onPress={helpSheet} />
        <MenuRow
          icon="log-out-outline"
          color={C.red}
          title="Log out"
          right={<View />}
          onPress={async () => {
            const ok = await confirm({ title: 'Log out?', text: 'You can log in again with your mobile and password.', confirmLabel: 'Log out' });
            if (ok) {
              actions.logout();
              nav.popToTop();
            }
          }}
        />
      </MenuGroup>
      <T size={12.5} color={C.muted} center style={{ marginTop: 16 }}>My Hostel · prototype v0.1</T>
    </TabPage>
  );
}
