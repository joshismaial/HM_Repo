// Owner sub-screens: tenant details, record payment, rooms, add room, complaints, notices,
// hostel settings, staff, invite, notifications, reports, app settings, delete account.
import React, { useEffect, useRef, useState } from 'react';
import { Dimensions, Keyboard, Platform, Pressable, ScrollView, Switch, TextInput, View } from 'react-native';
import { useNav } from '../nav';
import { confirm, showSheet, toast } from '../overlay';
import {
  FLOOR_OPTIONS, LANGUAGES, actions, app, bedLabel, countBeds, floorLabel, fmtDate, hostel, lateFee, roomTable, rupees, sharingPrices, totalBeds, typeLabel,
  unreadCount, useApp,
  hostelTitle,
} from '../state';
import {
  Avatar, Btn, C, Card, Chips, DateStepper, Divider, EmptyState, Field, Gap, Icon, IconBox, InfoRow, MenuGroup, MenuRow, MultiChips, Pill,
  ProgressBar, Row, Screen, SectionTitle, Segmented, Stepper, SwitchRow, T, rentPill, FloorPicker, SharingPicker, isGroundRoom, startsWithG, appFont,
} from '../ui';

const findTenant = (id) => app.tenants.find((t) => t.id === id);

// ======================================================================
// Tenant details
// ======================================================================
function EditTenantSheet({ t, close }) {
  const [name, setName] = useState(t.name);
  const [mobile, setMobile] = useState(t.mobile);
  return (
    <View>
      <T size={20} weight="800" style={{ marginBottom: 14 }}>Edit tenant</T>
      <Field label="Name" value={name} onChangeText={setName} />
      <Field label="Mobile" keyboardType="phone-pad" value={mobile} onChangeText={setMobile} />
      <Btn title="Save" onPress={() => { t.name = name; t.mobile = mobile; actions.touch(); close(); }} />
    </View>
  );
}

function VacateSheet({ t, close, onDone }) {
  const [deduct, setDeduct] = useState('0');
  const noNotice = t.status !== 'notice';
  return (
    <View>
      <T size={20} weight="800">Vacate {t.name}</T>
      {noNotice ? (
        <View style={{ backgroundColor: C.amberSoft, borderRadius: 12, padding: 10, marginTop: 10 }}>
          <T weight="800" color={C.amber}>No notice given. As per your rule, the deposit ({rupees(t.deposit)}) can be kept.</T>
        </View>
      ) : null}
      <Gap h={12} />
      <InfoRow label="Deposit held" value={rupees(t.deposit)} />
      <Gap h={8} />
      <Field label="Deduct (damages / dues)" prefix="₹" keyboardType="number-pad" value={deduct} onChangeText={setDeduct} />
      <Btn
        variant="danger"
        title="Vacate & free the bed"
        onPress={() => {
          const refund = Math.max(0, t.deposit - (parseInt(deduct, 10) || 0));
          actions.vacate(t);
          close();
          onDone();
          toast(`Bed freed. Refund ${rupees(refund)} recorded. ID will be deleted in 3 months.`);
        }}
      />
    </View>
  );
}

function DocSheet({ title }) {
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

export function TenantDetails({ params }) {
  const nav = useNav();
  useApp();
  const t = findTenant(params.id);
  const [revealed, setRevealed] = useState(false);
  if (!t) {
    return (
      <Screen title="Tenant details">
        <EmptyState icon="person-remove-outline" title="Tenant not found" text="This tenant was vacated." />
      </Screen>
    );
  }
  const reveal = async () => {
    if (revealed) return setRevealed(false);
    const ok = await confirm({ title: 'Reveal full ID number?', text: 'This is logged with your name and time, as required for Aadhaar privacy. Only reveal when needed (e.g. police verification).', confirmLabel: 'Reveal' });
    if (ok) setRevealed(true);
  };
  return (
    <Screen title="Tenant details" right={<Pressable accessibilityLabel="Edit" onPress={() => showSheet((close) => <EditTenantSheet t={t} close={close} />)} style={{ padding: 8 }}><Icon name="create-outline" /></Pressable>}>
      <Card>
        <Row gap={14}>
          <Avatar name={t.name} size={64} />
          <View style={{ flex: 1, gap: 4 }}>
            <T size={20} weight="800">{t.name}</T>
            <T color={C.muted}>Room {t.room} · Bed {t.bed}</T>
            <Row gap={6}>
              {rentPill(t)}
              <Pill text={t.stayType === 'monthly' ? 'Monthly' : 'Day-wise'} tone="grey" />
            </Row>
          </View>
        </Row>
      </Card>
      <Gap />
      <Row gap={8}>
        <Btn style={{ flex: 1 }} variant="outline" icon="call-outline" title="Call" onPress={() => toast(`Would call +91 ${t.mobile}`)} />
        <Btn style={{ flex: 1 }} variant="outline" icon="logo-whatsapp" title="WhatsApp" onPress={() => toast('Would open WhatsApp')} />
      </Row>
      <SectionTitle>Stay</SectionTitle>
      <Card>
        <InfoRow label="Joined" value={t.joined} />
        <InfoRow label="Rent" value={`${rupees(t.rent)} / month`} />
        <InfoRow label="Next due" value={t.dueDate} />
        <InfoRow label="Deposit held" value={rupees(t.deposit)} />
      </Card>
      <SectionTitle>Personal details</SectionTitle>
      <Card>
        <InfoRow label="Mobile" value={`+91 ${t.mobile}`} />
        <InfoRow label="Parent mobile" value={`+91 ${t.parentMobile}`} />
        <InfoRow label="Reference" value={t.reference} />
        <InfoRow label="Home" value={t.address} />
        {t.org ? <InfoRow label="Company / institute" value={t.org} /> : null}
        <InfoRow label="Company / institute address" value={t.office || '—'} />
      </Card>
      <SectionTitle>ID proof</SectionTitle>
      <Card>
        <Row gap={12}>
          <IconBox name="id-card-outline" />
          <View style={{ flex: 1 }}>
            <T size={12.5} color={C.muted}>Aadhaar</T>
            <T size={16} weight="800" style={{ letterSpacing: 1 }}>{revealed ? `5521 9083 ${t.idLast4}` : `XXXX XXXX ${t.idLast4}`}</T>
          </View>
          <Btn small variant="text" title={revealed ? 'Hide' : 'Reveal'} onPress={reveal} />
        </Row>
        <Row gap={8} style={{ marginTop: 10 }}>
          <Btn style={{ flex: 1 }} small variant="outline" icon="image-outline" title="ID copy" onPress={() => showSheet(() => <DocSheet title="Masked Aadhaar copy" />)} />
          <Btn style={{ flex: 1 }} small variant="outline" icon="person-outline" title="Photo" onPress={() => showSheet(() => <DocSheet title="Student photo" />)} />
        </Row>
        <T size={12.5} color={C.muted} style={{ marginTop: 8 }}>Stored encrypted · auto-deleted 3 months after leaving · every view is logged</T>
      </Card>
      <SectionTitle right={<Btn small variant="text" icon="add" title="Record payment" onPress={() => nav.push('RecordPayment', { id: t.id })} />}>Payments</SectionTitle>
      {t.payments.length === 0 ? (
        <Card><T color={C.muted}>No payments yet.</T></Card>
      ) : (
        <Card padding={0}>
          {t.payments.map((p, i) => (
            <Row key={i} gap={12} style={{ padding: 12, borderBottomWidth: i < t.payments.length - 1 ? 1 : 0, borderBottomColor: C.line }}>
              <IconBox name="receipt-outline" color={C.green} size={36} />
              <View style={{ flex: 1 }}>
                <T weight="600">{p.month}</T>
                <T size={12.5} color={C.muted}>{p.date} · {p.method} · {p.receipt}</T>
              </View>
              <T weight="800">{rupees(p.amount)}</T>
            </Row>
          ))}
        </Card>
      )}
      <SectionTitle>Actions</SectionTitle>
      <MenuGroup>
        <MenuRow icon="swap-horizontal" title="Change room" sub="Later feature" onPress={() => toast('Room change comes in a later version.')} />
        <MenuRow
          icon="link-outline"
          title="Reset access link"
          sub="Sends a new private link by SMS"
          onPress={async () => {
            const ok = await confirm({ title: `Reset ${t.name}’s link?`, text: `The old link stops working. A new link is sent to +91 ${t.mobile}.`, confirmLabel: 'Reset & send' });
            if (ok) toast('New link sent.');
          }}
        />
        <MenuRow icon="shield-outline" title="Police verification form" sub="PDF filled with tenant details" onPress={() => toast(`PDF would be generated: police_verification_${t.name.split(' ')[0]}.pdf`)} />
      </MenuGroup>
      <SectionTitle>Vacate & deposit</SectionTitle>
      <Card>
        <InfoRow label="Notice given" value={t.status === 'notice' ? 'Yes · leaving 20 Oct' : 'No'} />
        <InfoRow label="Notice rule" value={`${hostel().noticeDays} days`} />
        <InfoRow label="Deposit held" value={rupees(t.deposit)} />
        <Gap />
        <Btn variant="dangerOutline" title="Vacate & settle deposit" onPress={() => showSheet((close) => <VacateSheet t={t} close={close} onDone={() => nav.pop()} />)} />
      </Card>
    </Screen>
  );
}

// ======================================================================
// Record payment
// ======================================================================
export function RecordPayment({ params }) {
  const nav = useNav();
  const t = findTenant(params.id);
  const fee = t ? lateFee(t) : 0;
  const [waive, setWaive] = useState(false);
  const total = t ? t.rent + (waive ? 0 : fee) : 0;
  const [amount, setAmount] = useState(t ? String(t.rent + fee) : '0');
  const [method, setMethod] = useState('Cash');
  const [bill, setBill] = useState('October rent');
  const [date, setDate] = useState(new Date());
  const [receipt, setReceipt] = useState(true);
  if (!t) return <Screen title="Record payment"><T>Tenant not found.</T></Screen>;
  return (
    <Screen
      title="Record payment"
      footer={
        <Btn
          title="Save payment"
          onPress={() => {
            const a = parseInt(amount, 10) || 0;
            if (a <= 0) return toast('Enter the amount received.');
            actions.recordPayment(t, a, method, fmtDate(date));
            nav.pop();
            toast(`${rupees(a)} recorded${fee > 0 && waive ? ' · late fee waived' : ''}${receipt ? ' · receipt sent' : ''}.`);
          }}
        />
      }
    >
      <Card>
        <Row gap={12}>
          <Avatar name={t.name} />
          <View style={{ flex: 1 }}>
            <T weight="600">{t.name}</T>
            <T color={C.muted}>Room {t.room} · Bed {t.bed}</T>
          </View>
          {rentPill(t)}
        </Row>
      </Card>
      {fee > 0 ? (
        <Card style={{ marginTop: 12 }}>
          <T weight="600" style={{ marginBottom: 6 }}>Amount payable</T>
          <Row style={{ justifyContent: 'space-between', paddingVertical: 6 }}><T>Rent (Oct)</T><T weight="800">{rupees(t.rent)}</T></Row>
          <Row style={{ justifyContent: 'space-between', paddingVertical: 6 }}>
            <T color={C.muted}>Late fee · {t.daysLate} days × {rupees(app.lateFeePerDay)}</T>
            <T weight="800" color={waive ? C.muted : C.red} style={waive ? { textDecorationLine: 'line-through' } : null}>{rupees(fee)}</T>
          </Row>
          <Row style={{ justifyContent: 'space-between', paddingTop: 8, borderTopWidth: 1, borderTopColor: C.line }}>
            <T size={16} weight="800">Total payable</T>
            <T size={20} weight="800" color={C.green}>{rupees(total)}</T>
          </Row>
          <T size={12.5} color={C.muted} style={{ marginTop: 6 }}>Late fee stops on the payment date.</T>
        </Card>
      ) : null}
      <SectionTitle>Bill</SectionTitle>
      <Chips options={['October rent', 'Deposit', 'Electricity', 'Other']} value={bill} onChange={setBill} />
      <Gap h={16} />
      <Field label="Amount" prefix="₹" keyboardType="number-pad" value={amount} onChangeText={setAmount} />
      {fee > 0 ? (
        <Card padding={0} style={{ marginBottom: 14 }}>
          <SwitchRow title="Waive late fee" sub="Don't charge the late fee for this payment" value={waive} onChange={(v) => { setWaive(v); setAmount(String(t.rent + (v ? 0 : fee))); }} last />
        </Card>
      ) : null}
      <T size={14} weight="600" style={{ marginBottom: 8 }}>Method</T>
      <Chips options={['Cash', 'UPI', 'Bank', 'Cheque']} value={method} onChange={setMethod} />
      <SectionTitle>Paid on</SectionTitle>
      <Card>
        <DateStepper date={date} onChange={setDate} max={new Date()} />
      </Card>
      <Gap h={14} />
      <Field label="Note (optional)" placeholder="e.g. paid at office" />
      <Card padding={0}>
        <SwitchRow title="Send receipt to tenant" sub="By SMS / WhatsApp" value={receipt} onChange={setReceipt} last />
      </Card>
    </Screen>
  );
}

// ======================================================================
// Rooms (occupancy board)
// ======================================================================
function RoomSheet({ r }) {
  return (
    <View>
      <T size={20} weight="800">Room {r.number}</T>
      <T color={C.muted}>Floor {r.floor} · {r.sharing} sharing · {r.features.join(', ')}</T>
      <Gap h={12} />
      <InfoRow label="Monthly rent" value={rupees(r.rent)} />
      <InfoRow label="Monthly deposit" value={rupees(r.deposit)} />
      <InfoRow label="Per-day rent" value={rupees(r.perDay)} />
      <InfoRow label="Day-wise deposit" value={rupees(r.dayDeposit)} />
      <Divider />
      {r.beds.map((b, i) => {
        const t = app.tenants.find((x) => x.room === r.number && x.bed === bedLabel(i));
        return <InfoRow key={i} label={`Bed ${bedLabel(i)}`} value={b === 'filled' ? (t ? t.name : 'Filled') : b === 'vacant' ? 'Vacant' : 'On hold (someone is booking)'} />;
      })}
    </View>
  );
}

const roomFree = (r) => r.beds.filter((b) => b === 'vacant').length;
const floorName = (f) => (f === 0 ? 'Ground floor' : `Floor ${f}`);
const STATUS_HINT = { pay: { paid: 'Paid', pending: 'Rent due', late: 'Rent due', notice: 'Leaving' } };

/** Book a free bed: student, stay type, rent + deposit + total, payment method, Proceed to payment. */
export function BookBedSheet({ r, bedIndex, close }) {
  const [name, setName] = useState('');
  const [mobile, setMobile] = useState('');
  const [stay, setStay] = useState('monthly');
  const [days, setDays] = useState(7);
  const [method, setMethod] = useState('UPI');
  const [err, setErr] = useState('');
  const monthly = stay === 'monthly';
  const rent = monthly ? r.rent : r.perDay * days;
  const deposit = monthly ? r.deposit : r.dayDeposit;
  const total = rent + deposit;
  const bed = bedLabel(bedIndex);
  const row = (label, value, strong) => (
    <View style={{ flexDirection: 'row', justifyContent: 'space-between', paddingVertical: 6, ...(strong ? { borderTopWidth: 1.5, borderTopColor: C.line, marginTop: 4, paddingTop: 10 } : null) }}>
      <T size={strong ? 14 : 14} weight={strong ? '800' : '600'} color={strong ? C.ink : C.muted}>{label}</T>
      <T size={strong ? 20 : 14} weight="800" color={strong ? C.green : C.ink}>{value}</T>
    </View>
  );
  const proceed = () => {
    const digits = mobile.replace(/\D/g, '');
    if (name.trim().length < 2) return setErr("Enter the student's name.");
    if (!/^[6-9]\d{9}$/.test(digits)) return setErr('Enter a 10-digit mobile number.');
    const res = actions.bookBed({ roomNumber: r.number, bedIndex, name: name.trim(), mobile: digits.replace(/(\d{5})(\d{5})/, '$1 $2'), stayType: stay, days, method });
    close();
    if (!res.ok) return toast('Sorry, this bed was just taken.');
    toast(method === 'Cash'
      ? `Room ${r.number} · Bed ${bed} booked. ${rupees(res.total)} cash recorded, receipt sent.`
      : `Payment link for ${rupees(res.total)} sent to ${name.trim()}. Bed held for 15 minutes.`);
  };
  return (
    <View>
      <Row gap={12}>
        <View style={{ width: 46, height: 46, borderRadius: 12, backgroundColor: '#CDEEDC', alignItems: 'center', justifyContent: 'center' }}>
          <T size={11} weight="600" color={C.green}>BED</T>
          <T size={16} weight="800" color={C.green}>{bed}</T>
        </View>
        <View style={{ flex: 1 }}>
          <T size={20} weight="800">Book Room {r.number} · Bed {bed}</T>
          <T size={12.5} weight="400" color={C.muted}>{floorName(r.floor)} · {r.sharing} sharing{r.features.length ? ` · ${r.features[0]}` : ''}</T>
        </View>
      </Row>
      <Gap h={12} />
      <Field label="Student name" value={name} onChangeText={(v) => { setName(v); setErr(''); }} placeholder="Full name" />
      <Field label="Student mobile" value={mobile} onChangeText={(v) => { setMobile(v); setErr(''); }} placeholder="10-digit mobile" keyboardType="phone-pad" prefix="+91" maxLength={11} />
      <Segmented options={[{ value: 'monthly', label: 'Monthly' }, { value: 'day', label: 'Day-wise' }]} value={stay} onChange={setStay} />
      {!monthly ? <View style={{ marginTop: 10 }}><Stepper label="Days" value={days} onChange={setDays} min={1} /></View> : null}
      <View style={{ marginTop: 8 }}>
        {row(monthly ? 'Rent (first month)' : `Rent (${days} days × ${rupees(r.perDay)})`, rupees(rent))}
        {row('Security deposit', rupees(deposit))}
        {row('Total to pay', rupees(total), true)}
      </View>
      <T size={12.5} weight="600" color={C.muted} style={{ marginTop: 10, marginBottom: 6 }}>Payment method</T>
      <View style={{ flexDirection: 'row', gap: 8 }}>
        {[['UPI', 'GPay, PhonePe…'], ['Cash', 'Record now'], ['Bank', 'NEFT / IMPS']].map(([m, sub]) => {
          const on = method === m;
          return (
            <Pressable key={m} accessibilityRole="radio" accessibilityState={{ selected: on }} onPress={() => setMethod(m)}
              style={{ flex: 1, borderRadius: 12, borderWidth: 1.6, borderColor: on ? C.blue : C.line, backgroundColor: on ? C.blueSoft : '#fff', paddingVertical: 8, alignItems: 'center' }}>
              <T size={14} weight="600" color={on ? C.blue : C.ink}>{m}</T>
              <T size={11} weight="400" color={C.muted}>{sub}</T>
            </Pressable>
          );
        })}
      </View>
      {err ? <T size={12.5} weight="600" color={C.red} style={{ marginTop: 10 }}>{err}</T> : null}
      <Gap h={14} />
      <Btn title={`Proceed to payment · ${rupees(total)}`} onPress={proceed} />
      <T size={11} weight="400" color={C.muted} center style={{ marginTop: 8 }}>
        {method === 'Cash' ? 'Cash is recorded now and a receipt is sent to the student.' : 'The student gets a payment link. The bed is held for 15 minutes.'}
      </T>
    </View>
  );
}

/** Rooms board with filters: search by room number, floor, and All / Available / Occupied.
 *  Available lists only free beds (with Book); Occupied lists only filled beds (with who stays). */
export function RoomsContent() {
  const nav = useNav();
  useApp();
  const [q, setQ] = useState('');
  const [floor, setFloor] = useState('All floors');
  const [sharing, setSharing] = useState(0); // 0 = all sharing
  const [status, setStatus] = useState(app.roomsFilter || 'All');
  // Home can ask the Rooms tab to open on a filter (e.g. Available)
  const req = app.roomsFilterSeq || 0;
  const [seen, setSeen] = useState(req);
  if (req !== seen) {
    setSeen(req);
    setStatus(app.roomsFilter || 'All');
  }
  const floors = [...new Set(app.rooms.map((r) => r.floor))].sort((a, b) => a - b);
  const filled = countBeds('filled');
  const total = totalBeds();
  const rooms = app.rooms.filter((r) => {
    const mq = !q.trim() || r.number.toLowerCase().includes(q.trim().toLowerCase());
    const mf = floor === 'All floors' || floorName(r.floor) === floor;
    const ms = !sharing || r.sharing === sharing;
    return mq && mf && ms;
  });
  const sharings = [...new Set(app.rooms.map((r) => r.sharing))].sort((a, b) => a - b);
  const shareTxt = sharing ? ` in ${sharing}-sharing rooms` : '';
  const freeList = [];
  const filledList = [];
  rooms.forEach((r) => r.beds.forEach((b, i) => {
    if (b === 'vacant') freeList.push({ r, i });
    if (b === 'filled') filledList.push({ r, i, t: app.tenants.find((x) => x.room === r.number && x.bed === bedLabel(i)) });
  }));
  const book = (r, i) => (app.isStaff ? toast('Only the owner can book beds.') : showSheet((close) => <BookBedSheet r={r} bedIndex={i} close={close} />));
  const dot = (c, label) => (
    <Row gap={5} key={label}>
      <View style={{ width: 10, height: 10, borderRadius: 3, backgroundColor: c }} />
      <T size={12.5} color={C.muted}>{label}</T>
    </Row>
  );
  const byFloor = (list) => floors.map((f) => [f, list.filter((x) => x.r.floor === f)]).filter(([, l]) => l.length);
  const roomsCount = (list) => new Set(list.map((x) => x.r.number)).size;
  const line =
    status === 'Available' ? `${freeList.length} free ${freeList.length === 1 ? 'bed' : 'beds'}${shareTxt || ` in ${roomsCount(freeList)} rooms`}`
      : status === 'Occupied' ? `${filledList.length} beds filled${shareTxt || ` in ${roomsCount(filledList)} rooms`}`
        : `${rooms.length} ${sharing ? `${sharing}-sharing ` : ''}${rooms.length === 1 ? 'room' : 'rooms'}`;
  const empty = status === 'Available' ? !freeList.length : status === 'Occupied' ? !filledList.length : !rooms.length;
  return (
    <View>
      <Card>
        <Row>
          <T size={20} weight="800" style={{ flex: 1 }}>{total ? Math.round((filled / total) * 100) : 0}% occupied</T>
          <T weight="400" color={C.muted}>{filled}/{total} beds</T>
        </Row>
        <Gap />
        <ProgressBar value={total ? filled / total : 0} height={10} />
        <Row gap={14} style={{ marginTop: 12 }}>
          {dot(C.blue, `Filled ${filled}`)}
          {dot(C.green, `Vacant ${countBeds('vacant')}`)}
          {dot(C.amber, `On hold ${countBeds('held')}`)}
        </Row>
      </Card>
      <Gap h={12} />
      <Row gap={8} style={{ backgroundColor: '#fff', borderRadius: 12, borderWidth: 1.2, borderColor: C.line, paddingHorizontal: 12, minHeight: 48 }}>
        <Icon name="search" color={C.muted} />
        <TextInput value={q} onChangeText={setQ} placeholder="Search room number" placeholderTextColor="#9AA7B8" style={{ flex: 1, fontSize: 15, color: C.ink, paddingVertical: 10 }} />
      </Row>
      <Gap h={10} />
      <Chips options={['All floors', ...floors.map(floorName)]} value={floor} onChange={setFloor} />
      <Gap h={8} />
      {/* sharing: "All sharing", then just the numbers (only sizes the rooms have) */}
      <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ gap: 6, alignItems: 'center' }}>
        {[0, ...sharings].map((n) => {
          const on = sharing === n;
          return (
            <Pressable key={n} onPress={() => setSharing(n)} accessibilityRole="button" accessibilityState={{ selected: on }}
              accessibilityLabel={n ? `${n} sharing` : 'All sharing'}
              style={{ height: 34, minWidth: n ? 34 : undefined, paddingHorizontal: n ? 0 : 14, borderRadius: 17, borderWidth: 1.2, borderColor: on ? C.green : C.line, backgroundColor: on ? '#CDEEDC' : '#fff', alignItems: 'center', justifyContent: 'center' }}>
              <T size={n ? 14 : 12.5} weight="800" color={on ? C.green : C.ink}>{n ? String(n) : 'All sharing'}</T>
            </Pressable>
          );
        })}
      </ScrollView>
      <Gap h={8} />
      <Segmented
        options={[
          { value: 'All', label: `All (${app.rooms.length})` },
          { value: 'Available', label: `Available (${countBeds('vacant')})` },
          { value: 'Occupied', label: `Occupied (${filled})` },
        ]}
        value={status}
        onChange={setStatus}
      />
      <T weight="400" color={C.muted} style={{ marginTop: 12 }}>{line}</T>
      {empty ? <EmptyState icon="bed-outline" title="Nothing here" text="Try another floor, filter or room number." /> : null}

      {status === 'Available' ? byFloor(freeList).map(([f, list]) => (
        <View key={f}>
          <SectionTitle>{floorName(f)}</SectionTitle>
          {list.map(({ r, i }) => (
            <Card key={r.number + i} padding={12} style={{ marginBottom: 8 }} onPress={() => book(r, i)}>
              <Row gap={12}>
                <View style={{ width: 42, height: 42, borderRadius: 12, backgroundColor: '#CDEEDC', alignItems: 'center', justifyContent: 'center' }}>
                  <T size={11} weight="600" color={C.green}>BED</T>
                  <T size={16} weight="800" color={C.green}>{bedLabel(i)}</T>
                </View>
                <View style={{ flex: 1 }}>
                  <T size={14} weight="600">Room {r.number} · Bed {bedLabel(i)}</T>
                  <T size={12.5} weight="800" color={C.muted}>{r.sharing} sharing · {rupees(r.rent)}/month{r.features.includes('AC') ? ' · AC' : ''}</T>
                </View>
                <Btn small title="Book" onPress={() => book(r, i)} style={{ backgroundColor: C.green, borderColor: C.green }} />
              </Row>
            </Card>
          ))}
        </View>
      )) : null}

      {status === 'Occupied' ? byFloor(filledList).map(([f, list]) => (
        <View key={f}>
          <SectionTitle>{floorName(f)}</SectionTitle>
          {list.map(({ r, i, t }) => (
            <Card key={r.number + i} padding={12} style={{ marginBottom: 8 }} onPress={() => (t ? nav.push('TenantDetails', { id: t.id }) : showSheet(() => <RoomSheet r={r} />))}>
              <Row gap={12}>
                <Avatar name={t ? t.name : 'Not on app'} size={42} />
                <View style={{ flex: 1 }}>
                  <T size={14} weight="600">{t ? t.name : 'Tenant not on app yet'}</T>
                  <T size={12.5} weight="400" color={C.muted}>Room {r.number} · Bed {bedLabel(i)}{t ? ` · ${t.dueToday && t.status !== 'paid' ? 'Due today' : STATUS_HINT.pay[t.status] || ''}` : ''}</T>
                </View>
                <Icon name="chevron-forward" size={20} color={C.blue} />
              </Row>
            </Card>
          ))}
        </View>
      )) : null}

      {status === 'All' ? floors.filter((f) => rooms.some((r) => r.floor === f)).map((f) => (
        <View key={f}>
          <SectionTitle>{floorName(f)}</SectionTitle>
          <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 10 }}>
            {rooms.filter((r) => r.floor === f).map((r) => {
              const free = roomFree(r);
              return (
                <Card key={r.number} padding={12} style={{ width: '48%' }} onPress={() => showSheet(() => <RoomSheet r={r} />)}>
                  <Row>
                    <T size={20} weight="800" style={{ flex: 1 }}>{r.number}</T>
                    <T size={12.5} weight="400" color={C.muted}>{r.sharing} sh</T>
                  </Row>
                  <T size={12.5} color={C.muted}>{rupees(r.rent)}</T>
                  <T size={12.5} weight="600" color={free ? C.green : C.blue}>{free ? `${free} bed${free > 1 ? 's' : ''} free` : 'Full'}</T>
                  <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 5, marginTop: 10 }}>
                    {r.beds.map((b, i) => {
                      const c = b === 'filled' ? C.blue : b === 'vacant' ? C.green : C.amber;
                      return (
                        <Pressable key={i} disabled={b !== 'vacant'} accessibilityLabel={b === 'vacant' ? `Book room ${r.number} bed ${bedLabel(i)}` : undefined} onPress={() => book(r, i)} hitSlop={3}
                          style={{ width: 28, height: 24, borderRadius: 8, borderWidth: 1, borderColor: c, backgroundColor: b === 'filled' ? c : c + '24', alignItems: 'center', justifyContent: 'center' }}>
                          <T size={11} weight="600" color={b === 'filled' ? '#fff' : c}>{bedLabel(i)}</T>
                        </Pressable>
                      );
                    })}
                  </View>
                </Card>
              );
            })}
          </View>
        </View>
      )) : null}
    </View>
  );
}

/** More → Hostel settings → Rooms & beds: every room and bed (All / Available / Occupied), Add room. */
export function Rooms() {
  const nav = useNav();
  return (
    <Screen title="Rooms & beds" right={!app.isStaff ? <Btn small variant="text" icon="add" title="Add room" onPress={() => nav.push('AddRoom')} /> : null}>
      <RoomsContent />
    </Screen>
  );
}

// ======================================================================
// Add room
// ======================================================================
const FEATURES = ['AC', 'Geyser', 'Attached bathroom', 'Balcony', 'Cupboard', 'Study table', 'TV', 'Wi-Fi'];
export function AddRoom() {
  const nav = useNav();
  const [number, setNumber] = useState('');
  const [floor, setFloor] = useState(1);
  const [sharing, setSharing] = useState(3);
  const [rent, setRent] = useState('');
  const [deposit, setDeposit] = useState('');
  const [perDay, setPerDay] = useState('');
  const [dayDeposit, setDayDeposit] = useState('');
  const [features, setFeatures] = useState([]);

  // Save room → back to Hostel settings (the list updates and the new room is highlighted)
  const save = () => {
    const n = number.trim();
    if (!n) return toast('Enter a room number.');
    if (app.rooms.some((r) => r.number === n)) return toast(`Room ${n} already exists.`);
    if (!(+rent > 0)) return toast('Enter the monthly rent per bed.');
    actions.addRoom({ number: n, floor, sharing, rent: +rent, deposit: +deposit || 0, perDay: +perDay || 0, dayDeposit: +dayDeposit || 0, beds: Array(sharing).fill('vacant'), features, meter: false });
    app.lastAddedRoom = { number: n, beds: sharing, at: Date.now() };
    nav.pop();
  };
  const box = (child) => <View style={{ backgroundColor: '#fff', borderRadius: 16, borderWidth: 1, borderColor: C.line, padding: 14, marginBottom: 12 }}>{child}</View>;
  const half = (child) => <View style={{ flex: 1 }}>{child}</View>;

  return (
    <Screen title="Add room" footer={<Btn title="Save room" onPress={save} />}>
      {box(
        <>
          <T size={14} weight="600">Room</T>
          <Gap h={6} />
          <Row gap={10} align="flex-start">
            {half(
              <View>
                <T size={12.5} weight="400" color={C.muted} style={{ marginBottom: 6 }}>Floor</T>
                <Row gap={6}>
                  <Pressable accessibilityLabel="Lower floor" onPress={() => setFloor(Math.max(0, floor - 1))} style={{ width: 36, height: 48, borderRadius: 12, borderWidth: 1.2, borderColor: C.line, alignItems: 'center', justifyContent: 'center' }}><Icon name="remove" /></Pressable>
                  <View style={{ flex: 1, height: 48, borderRadius: 12, borderWidth: 1.2, borderColor: C.line, alignItems: 'center', justifyContent: 'center' }}>
                    <T weight="600">{floor === 0 ? 'Ground' : `Floor ${floor}`}</T>
                  </View>
                  <Pressable accessibilityLabel="Higher floor" onPress={() => setFloor(Math.min(20, floor + 1))} style={{ width: 36, height: 48, borderRadius: 12, borderWidth: 1.2, borderColor: C.line, alignItems: 'center', justifyContent: 'center' }}><Icon name="add" /></Pressable>
                </Row>
              </View>,
            )}
            {half(<Field label="Room number" placeholder="205" value={number} onChangeText={setNumber} />)}
          </Row>
          <T size={12.5} weight="400" color={C.muted} style={{ marginTop: 4, marginBottom: 6 }}>Sharing (beds in room)</T>
          <Row gap={6}>
            {[1, 2, 3, 4, 5, 6].map((n) => (
              <Pressable key={n} onPress={() => setSharing(n)} accessibilityRole="button" accessibilityState={{ selected: sharing === n }} accessibilityLabel={`${n} sharing`}
                style={{ flex: 1, height: 42, borderRadius: 12, borderWidth: 1.2, borderColor: sharing === n ? C.blue : C.line, backgroundColor: sharing === n ? C.blue : '#fff', alignItems: 'center', justifyContent: 'center' }}>
                <T size={14} weight="600" color={sharing === n ? '#fff' : C.ink}>{n}</T>
              </Pressable>
            ))}
          </Row>
        </>,
      )}
      {box(
        <>
          <T size={14} weight="600">Fees</T>
          <Gap h={6} />
          <Row gap={10} align="flex-start">
            {half(<Field label="Monthly rent / bed" prefix="₹" keyboardType="number-pad" placeholder="6500" value={rent} onChangeText={setRent} />)}
            {half(<Field label="Deposit (monthly)" prefix="₹" keyboardType="number-pad" placeholder="6500" value={deposit} onChangeText={setDeposit} />)}
          </Row>
          <Row gap={10} align="flex-start">
            {half(<Field label="Per-day rent" prefix="₹" keyboardType="number-pad" placeholder="450" value={perDay} onChangeText={setPerDay} />)}
            {half(<Field label="Deposit (day-wise)" prefix="₹" keyboardType="number-pad" placeholder="1000" value={dayDeposit} onChangeText={setDayDeposit} />)}
          </Row>
        </>,
      )}
      {box(
        <>
          <T size={14} weight="600">Features</T>
          <Gap h={8} />
          <MultiChips options={FEATURES} values={features} onToggle={(f) => setFeatures(features.includes(f) ? features.filter((x) => x !== f) : [...features, f])} />
        </>,
      )}
      <T size={12.5} color={C.muted} center>After saving you go back to Hostel settings</T>
    </Screen>
  );
}

// ======================================================================
// Complaints
// ======================================================================
function ReplySheet({ c, close }) {
  const [text, setText] = useState(c.reply);
  return (
    <View>
      <T size={20} weight="800" style={{ marginBottom: 12 }}>Reply to {c.student}</T>
      <Field multiline placeholder="e.g. Plumber is coming at 4 PM" value={text} onChangeText={setText} />
      <Btn
        title="Send reply"
        onPress={() => {
          if (text.trim()) {
            actions.setComplaintStatus(c, c.status === 'open' ? 'inProgress' : c.status, text.trim());
            toast(`Reply sent to ${c.student}.`);
          }
          close();
        }}
      />
    </View>
  );
}

export function Complaints() {
  useApp();
  const [filter, setFilter] = useState('open');
  const count = (s) => app.complaints.filter((c) => c.status === s).length;
  const list = app.complaints.filter((c) => c.status === filter);
  return (
    <Screen title="Complaints">
      <Segmented
        options={[
          { value: 'open', label: `Open (${count('open')})` },
          { value: 'inProgress', label: `Working (${count('inProgress')})` },
          { value: 'resolved', label: `Done (${count('resolved')})` },
        ]}
        value={filter}
        onChange={setFilter}
      />
      <Gap h={14} />
      {list.length === 0 ? (
        <EmptyState icon="checkmark-circle-outline" title="Nothing here" text="Complaints from students appear here." />
      ) : (
        list.map((c) => (
          <Card key={c.id} style={{ marginBottom: 12 }}>
            <Row>
              <Pill text={c.category} tone="grey" />
              <T weight="600">Room {c.room}</T>
              <View style={{ flex: 1 }} />
              <T size={12.5} color={C.muted}>{c.time}</T>
            </Row>
            <T size={14} style={{ marginTop: 10, lineHeight: 21 }}>{c.text}</T>
            <T color={C.muted} style={{ marginTop: 6 }}>— {c.student}</T>
            {c.hasPhoto ? (
              <Row gap={6} style={{ height: 80, borderRadius: 12, backgroundColor: C.ground, justifyContent: 'center', marginTop: 10 }}>
                <Icon name="image-outline" color={C.muted} />
                <T color={C.muted}>Photo attached</T>
              </Row>
            ) : null}
            {c.reply ? <T weight="600" color={C.blue} style={{ marginTop: 10 }}>You: {c.reply}</T> : null}
            {c.status !== 'resolved' ? (
              <Row gap={8} style={{ marginTop: 12 }}>
                <Btn style={{ flex: 1 }} variant="outline" title="Reply" onPress={() => showSheet((close) => <ReplySheet c={c} close={close} />)} />
                <Btn
                  style={{ flex: 1 }}
                  title={c.status === 'open' ? 'Start work' : 'Mark resolved'}
                  onPress={() => {
                    const next = c.status === 'open' ? 'inProgress' : 'resolved';
                    actions.setComplaintStatus(c, next);
                    toast(next === 'resolved' ? `Marked resolved. ${c.student} is notified.` : 'Moved to in progress.');
                  }}
                />
              </Row>
            ) : null}
          </Card>
        ))
      )}
    </Screen>
  );
}

// ======================================================================
// Leaving notices
// ======================================================================
export function LeavingNotices() {
  useApp();
  return (
    <Screen title="Leaving notices">
      {app.notices.length === 0 ? (
        <EmptyState icon="calendar-outline" title="No one is leaving" text="When a student gives notice, it shows up here." />
      ) : (
        app.notices.map((n, i) => (
          <Card key={n.name + i} style={{ marginBottom: 12 }}>
            <Row gap={10}>
              <Avatar name={n.name} size={40} color={C.purple} />
              <View style={{ flex: 1 }}>
                <T weight="600">{n.name}</T>
                <T size={12.5} color={C.muted}>{n.room}</T>
              </View>
              {n.onTime ? <Pill text="On time" tone="green" /> : <Pill text="Short notice" tone="red" />}
            </Row>
            <Gap />
            <InfoRow label="Notice given" value={n.givenOn} />
            <InfoRow label="Leaving on" value={n.leaveOn} />
            <InfoRow label="Deposit to settle" value={rupees(n.deposit)} />
            <Gap />
            <Btn
              variant="tonal"
              title="Vacate & settle deposit"
              onPress={() => {
                const t = app.tenants.find((x) => x.id === n.tenantId);
                if (t) actions.vacate(t);
                else {
                  app.notices = app.notices.filter((x) => x !== n);
                  actions.touch();
                }
                toast(`${n.name} vacated. Bed is free.`);
              }}
            />
          </Card>
        ))
      )}
    </Screen>
  );
}

/** Type a rule and tap Add – as many rules as needed. */
function RuleAdder({ onAdd }) {
  const [v, setV] = useState('');
  const add = () => {
    if (v.trim().length < 3) return toast('Write the rule first.');
    onAdd(v.trim());
    setV('');
  };
  return (
    <Row gap={8} style={{ marginTop: 4 }}>
      <TextInput value={v} onChangeText={setV} placeholder="Type a new rule, e.g. Visitors till 8 PM" placeholderTextColor={C.muted} onSubmitEditing={add}
        style={{ flex: 1, borderWidth: 1.2, borderColor: C.line, backgroundColor: '#fff', borderRadius: 12, paddingHorizontal: 12, paddingVertical: 10, fontSize: 14, color: C.ink }} />
      <Pressable onPress={add} style={{ flexDirection: 'row', alignItems: 'center', gap: 4, backgroundColor: C.blue, borderRadius: 12, paddingHorizontal: 14, height: 44 }}>
        <Icon name="add" size={18} color="#fff" /><T weight="600" color="#fff">Add</T>
      </Pressable>
    </Row>
  );
}

// ======================================================================
// Notice to students (shown on student Home under "From your owner")
// ======================================================================
const NOTICE_TEMPLATES = [
  { key: 'water', icon: 'water-outline', label: 'Water off', title: 'Water off 2–4 PM today', body: 'Tank cleaning. Please store water.' },
  { key: 'power', icon: 'flash-outline', label: 'Power cut', title: 'Power cut 10 AM – 1 PM', body: 'EB maintenance. Backup for lights only.' },
  { key: 'clean', icon: 'sparkles-outline', label: 'Cleaning', title: 'Room cleaning on Sunday', body: 'Please keep your things on the bed.' },
  { key: 'rent', icon: 'cash-outline', label: 'Rent reminder', title: 'Rent due on the 5th', body: 'Please pay on time to avoid late fee.' },
  { key: 'food', icon: 'restaurant-outline', label: 'Food timing', title: 'Dinner from 8 PM today', body: 'Kitchen work in the evening.' },
  { key: 'other', icon: 'megaphone-outline', label: 'Other', title: '', body: '' },
];
export function StudentNotices() {
  useApp();
  const [pick, setPick] = useState(null);
  const [title, setTitle] = useState('');
  const [body, setBody] = useState('');
  const list = app.ownerNotices || [];
  const shown = list.length ? list : [app.defaultNotice];
  const choose = (t) => {
    setPick(t.key);
    setTitle(t.title);
    setBody(t.body);
  };
  return (
    <Screen title="Notice to students">
      <T color={C.muted} style={{ marginTop: -8, marginBottom: 12 }}>All students see this on their Home screen.</T>

      <SectionTitle>Students see now</SectionTitle>
      <Card padding={0}>
        {shown.map((n, i, arr) => (
          <Row key={i} gap={12} style={{ paddingHorizontal: 14, paddingVertical: 12, borderBottomWidth: i < arr.length - 1 ? 1 : 0, borderBottomColor: C.line }}>
            <View style={{ width: 40, height: 40, borderRadius: 20, backgroundColor: '#F59E0B', alignItems: 'center', justifyContent: 'center' }}>
              <Icon name={n.icon} size={20} color="#fff" />
            </View>
            <View style={{ flex: 1 }}>
              <T weight="600">{n.title}</T>
              <T size={12.5} color={C.muted}>{list.length ? n.body : 'Default message – shown when you have no notice.'}</T>
            </View>
            {list.length ? (
              <Pressable hitSlop={10} onPress={async () => {
                const ok = await confirm({ title: 'Remove this notice?', text: 'Students will not see it any more.', confirmLabel: 'Remove', danger: true });
                if (ok) { app.ownerNotices = list.filter((x) => x !== n); actions.touch(); toast('Notice removed.'); }
              }}>
                <Icon name="trash-outline" size={20} color={C.red} />
              </Pressable>
            ) : null}
          </Row>
        ))}
      </Card>

      <SectionTitle>New notice</SectionTitle>
      <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 8 }}>
        {NOTICE_TEMPLATES.map((t) => {
          const on = pick === t.key;
          return (
            <Pressable key={t.key} onPress={() => choose(t)} style={{ width: '31%', flexGrow: 1, alignItems: 'center', gap: 4, paddingVertical: 12, borderRadius: 12, backgroundColor: on ? C.blueSoft : '#fff', borderWidth: 1.4, borderColor: on ? C.blue : C.line }}>
              <Icon name={t.icon} size={22} color={on ? C.blue : C.muted} />
              <T size={12.5} weight="600" color={on ? C.blue : C.ink}>{t.label}</T>
            </Pressable>
          );
        })}
      </View>
      {pick ? (
        <>
          <Gap h={12} />
          <Field label="Heading" value={title} onChangeText={setTitle} placeholder="e.g. Water off today" />
          <Field label="Message (short)" value={body} onChangeText={setBody} placeholder="One line for students" />
          <Btn
            icon="megaphone-outline"
            title="Send to all students"
            onPress={() => {
              if (!title.trim()) return toast('Please write a heading.');
              const t = NOTICE_TEMPLATES.find((x) => x.key === pick);
              app.ownerNotices = [{ icon: t.icon, title: title.trim(), body: body.trim(), when: 'Just now' }, ...list];
              actions.touch();
              setPick(null); setTitle(''); setBody('');
              toast('Sent. Students see it on their Home.');
            }}
          />
        </>
      ) : (
        <T size={12.5} color={C.muted} style={{ marginTop: 10, textAlign: 'center' }}>Tap a box to start. You can change the words.</T>
      )}
    </Screen>
  );
}

// ======================================================================
// Hostel settings
// ======================================================================
// ---------- simple Hostel settings (Style 1): Rent → Deposit → Rent date → Wi-Fi → Day-wise → Extra charges → Payments → Account
/** A box with a value and a pen; tap opens an edit sheet. */
function PenBox({ text, onPress, mono, muted, style }) {
  return (
    <Pressable onPress={onPress} style={[{ flex: 1, flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', borderWidth: 1.2, borderColor: C.line, borderRadius: 12, paddingHorizontal: 12, minHeight: 46, backgroundColor: '#fff', opacity: muted ? 0.45 : 1 }, style]}>
      <T weight="600" size={14} style={mono ? { fontFamily: undefined, letterSpacing: 0.3 } : null}>{text}</T>
      <Icon name="pencil" size={17} color={C.blue} />
    </Pressable>
  );
}

/** Bottom sheet with one field and Save. */
function editValue({ title, sub, value, prefix, number, placeholder, onSave, allowZero }) {
  showSheet((close) => <EditValueSheet title={title} sub={sub} value={value} prefix={prefix} number={number} placeholder={placeholder} close={close} onSave={onSave} allowZero={allowZero} />);
}
function EditValueSheet({ title, sub, value, prefix, number, placeholder, close, onSave, allowZero }) {
  const [v, setV] = useState(value == null ? '' : String(value));
  const save = () => {
    const out = number ? parseInt(v.replace(/\D/g, ''), 10) || 0 : v.trim();
    if (number && allowZero && v.replace(/\D/g, '') === '') return toast('Type a number.');
    if (number && !allowZero && out <= 0) return toast('Enter an amount.');
    if (!number && !out) return toast('This can’t be empty.');
    onSave(out);
    close();
  };
  return (
    <View>
      <T size={20} weight="800">{title}</T>
      {sub ? <T color={C.muted} style={{ marginTop: 2, marginBottom: 10 }}>{sub}</T> : <Gap h={10} />}
      <Field value={v} onChangeText={(x) => setV(number ? x.replace(/\D/g, '') : x)} prefix={prefix} keyboardType={number ? 'number-pad' : 'default'} placeholder={placeholder} autoFocus maxLength={number ? 6 : 60} />
      <Btn title="Save" onPress={save} />
    </View>
  );
}

/** Grey cover with "Your changes are saved" over one section (1½ seconds). */
const SavedCover = ({ sub }) => (
  <View pointerEvents="none" style={{ position: 'absolute', left: 0, right: 0, top: 0, bottom: 0, borderRadius: 16, backgroundColor: 'rgba(233,237,243,0.9)', alignItems: 'center', justifyContent: 'center' }}>
    <View style={{ backgroundColor: '#fff', borderRadius: 16, paddingVertical: 16, paddingHorizontal: 18, alignItems: 'center', width: 250, shadowColor: '#000', shadowOpacity: 0.18, shadowRadius: 14, shadowOffset: { width: 0, height: 6 }, elevation: 6 }}>
      <View style={{ width: 50, height: 50, borderRadius: 25, backgroundColor: C.green, alignItems: 'center', justifyContent: 'center', marginBottom: 8 }}>
        <Icon name="checkmark" size={30} color="#fff" />
      </View>
      <T size={16} weight="800" style={{ textAlign: 'center' }}>Your changes are saved</T>
      {sub ? <T size={14} color={C.muted} style={{ marginTop: 4, textAlign: 'center' }}>{sub}</T> : null}
    </View>
  </View>
);

/** A setting as one line with a down arrow; only one is open at a time (the parent decides). */
function SetCard({ icon, title, open, onToggle, saved, children, onLayout }) {
  return (
    <View style={{ marginBottom: 8 }} onLayout={onLayout}>
      <Card style={{ borderWidth: open ? 1.5 : 1, borderColor: open ? C.blue : C.line }}>
        <Pressable onPress={onToggle} style={{ flexDirection: 'row', alignItems: 'center', gap: 8 }}>
          <Icon name={icon} size={22} color={C.blue} />
          <T size={16} weight="800" style={{ flex: 1 }}>{title}</T>
          <Icon name={open ? 'chevron-up' : 'chevron-down'} size={22} color={C.blue} />
        </Pressable>
        {open && children ? <View style={{ marginTop: 10 }}>{children}</View> : null}
      </Card>
      {saved ? <SavedCover sub={saved} /> : null}
    </View>
  );
}
const AddLink = ({ title, onPress, disabled }) => (
  <Pressable disabled={disabled} onPress={onPress} style={{ flexDirection: 'row', alignItems: 'center', gap: 6, paddingTop: 8, opacity: disabled ? 0.35 : 1, alignSelf: 'flex-start' }}>
    <Icon name="add-circle-outline" size={20} color={disabled ? C.muted : C.blue} />
    <T weight="600" color={disabled ? C.muted : C.blue}>{title}</T>
  </Pressable>
);

function ensureSettings(h) {
  if (!h.sharingPrices) {
    const by = {};
    app.rooms.forEach((r) => { by[r.sharing] = Math.min(by[r.sharing] || Infinity, r.rent); });
    h.sharingPrices = Object.keys(by).map(Number).sort((a, b) => a - b).map((n) => ({ sharing: n, rent: by[n] }));
  }
  if (h.depositOn == null) { h.depositOn = true; h.depositAmount = 5000; }
  if (h.perDayRent == null) h.perDayRent = 500;
  if (!h.extraCharges) h.extraCharges = [
    { id: 'el', icon: 'flash-outline', name: 'Electricity bill', amount: 10, per: 'unit', on: !!h.electricitySeparate },
    { id: 'la', icon: 'shirt-outline', name: 'Laundry', amount: h.laundryCharge || 300, per: 'month', on: !!h.laundry },
  ];
  if (h.payGpay == null) { h.payGpay = true; h.payPhonepe = true; h.payPaytm = false; }
  if (h.cashNote == null) h.cashNote = 'Please pay cash in the office, 9 AM – 1 PM, Mon–Sat.';
  // sample Wi-Fi only the first time (an empty list later means the owner removed them all)
  if (!h.wifiReady) {
    h.wifiReady = true;
    if (!h.wifi || !h.wifi.length || h.wifi.some((w) => w.floor == null)) h.wifi = [{ floor: 1, password: 'f1@sai' }, { floor: 2, password: 'f2@sai' }];
  }
}

function SharingSheet({ close, current, taken, onSave }) {
  const [n, setN] = useState(current || null);
  return (
    <View>
      <T size={20} weight="800">Sharing</T>
      <T color={C.muted} style={{ marginTop: 2, marginBottom: 12 }}>How many beds in the room?</T>
      <SharingPicker value={n} onChange={(x) => (taken.includes(x) && x !== current ? toast(`${x} sharing already has a price.`) : setN(x))} />
      <Gap h={12} />
      <Btn title="Save" onPress={() => { if (!n) return toast('Pick the sharing.'); onSave(n); close(); }} />
    </View>
  );
}

function AddSharingSheet({ close, taken, onSave }) {
  const [n, setN] = useState(null);
  const [rent, setRent] = useState('');
  return (
    <View>
      <T size={20} weight="800">Add sharing</T>
      <T weight="600" style={{ marginTop: 12, marginBottom: 6 }}>How many beds in the room?</T>
      <SharingPicker value={n} onChange={(x) => (taken.includes(x) ? toast(`${x} sharing already has a price.`) : setN(x))} />
      <Gap h={10} />
      <Field label="Rent per bed, every month" prefix="₹" keyboardType="number-pad" placeholder="4500" value={rent} onChangeText={(v) => setRent(v.replace(/\D/g, ''))} maxLength={6} />
      <Btn title="Add" onPress={() => {
        if (!n) return toast('Pick the sharing.');
        if (!parseInt(rent, 10)) return toast('Enter the rent.');
        onSave(n, parseInt(rent, 10));
        close();
      }} />
    </View>
  );
}

function AddWifiSheet({ close, onSave }) {
  const [f, setF] = useState('');
  const [pw, setPw] = useState('');
  return (
    <View>
      <T size={20} weight="800">Add Wi-Fi</T>
      <T weight="600" style={{ marginTop: 12, marginBottom: 6 }}>Floor</T>
      <FloorPicker value={f} onChange={setF} />
      <Gap h={10} />
      <Field label="Password" placeholder="password" value={pw} onChangeText={setPw} maxLength={60} />
      <Btn title="Add" onPress={() => {
        if (f === '') return toast('Pick a floor.');
        if (!pw.trim()) return toast('Type the password.');
        onSave(parseInt(f, 10), pw.trim());
        close();
      }} />
    </View>
  );
}

function AddChargeSheet({ close, onSave }) {
  const [name, setName] = useState('');
  const [amount, setAmount] = useState('');
  const [per, setPer] = useState('month');
  return (
    <View>
      <T size={20} weight="800" style={{ marginBottom: 12 }}>Add another charge</T>
      <Field label="Name of service" placeholder="Bike parking" value={name} onChangeText={setName} maxLength={40} />
      <Field label="Amount" prefix="₹" keyboardType="number-pad" placeholder="200" value={amount} onChangeText={(v) => setAmount(v.replace(/\D/g, ''))} maxLength={6} />
      <T weight="600" style={{ marginBottom: 6 }}>How often</T>
      <Segmented options={[{ value: 'day', label: 'Per day' }, { value: 'month', label: 'Every month' }, { value: 'once', label: 'One time' }]} value={per} onChange={setPer} />
      <Gap h={12} />
      <Btn title="Save charge" onPress={() => {
        if (name.trim().length < 2) return toast('Enter the name of the service.');
        if (!parseInt(amount, 10)) return toast('Enter the amount.');
        onSave({ id: 'c' + Date.now(), icon: 'pricetag-outline', name: name.trim(), amount: parseInt(amount, 10), per, on: true });
        close();
      }} />
    </View>
  );
}

function FloorSheet({ close, current, onSave }) {
  const [f, setF] = useState(current == null ? '' : String(current));
  return (
    <View>
      <T size={20} weight="800" style={{ marginBottom: 12 }}>Which floor?</T>
      <FloorPicker value={f} onChange={setF} />
      <Gap h={14} />
      <Btn title="Save" onPress={() => { if (f === '') return toast('Pick a floor.'); onSave(parseInt(f, 10)); close(); }} />
    </View>
  );
}

function ChangePasswordSheet({ close }) {
  const [a, setA] = useState('');
  const [b, setB] = useState('');
  return (
    <View>
      <T size={20} weight="800" style={{ marginBottom: 12 }}>Change password</T>
      <Field label="New password" secure value={a} onChangeText={setA} />
      <Field label="Type it again" secure value={b} onChangeText={setB} />
      <Btn title="Save password" onPress={() => {
        if (a.length < 8) return toast('Use at least 8 letters or numbers.');
        if (a !== b) return toast('The two passwords are different.');
        close();
        toast('Password changed.');
      }} />
    </View>
  );
}

const perText = (p) => (p === 'unit' ? '/ unit' : p === 'once' ? 'one time' : p === 'day' ? '/ day' : '/ month');
const floorName2 = (f) => (f === 0 ? 'Ground' : `Floor ${f}`);

const ordinal = (d) => {
  const s = d % 100 >= 11 && d % 100 <= 13 ? 'th' : ({ 1: 'st', 2: 'nd', 3: 'rd' }[d % 10] || 'th');
  return `${d}${s}`;
};

const RemoveBtn = ({ onPress }) => (
  <Pressable onPress={onPress} style={{ width: 44, minHeight: 46, borderRadius: 12, borderWidth: 1.2, borderColor: '#F3C4C4', backgroundColor: '#FFF5F5', alignItems: 'center', justifyContent: 'center' }}>
    <Icon name="close" size={20} color={C.red} />
  </Pressable>
);

/** Empty line [A ✎] [B ✎] [✕] shown when a list is empty; tapping a box opens the add sheet. */
function BlankLine({ aText, bText, onAdd }) {
  return (
    <Row gap={8} style={{ marginBottom: 8 }}>
      <PenBox text={aText} muted onPress={onAdd} />
      <PenBox text={bText} muted onPress={onAdd} />
      <RemoveBtn onPress={() => {}} />
    </Row>
  );
}

const ColLabels = ({ a, b }) => (
  <Row gap={8} style={{ marginBottom: 3 }}>
    <T size={11} color={C.muted} style={{ flex: 1, marginLeft: 2 }}>{a}</T>
    <T size={11} color={C.muted} style={{ flex: 1, marginLeft: 2 }}>{b}</T>
    <View style={{ width: 44 }} />
  </Row>
);

const SaveBtn = ({ onPress }) => (
  <Pressable onPress={onPress} style={{ backgroundColor: C.blue, borderRadius: 12, paddingHorizontal: 24, paddingVertical: 10 }}>
    <T weight="600" color="#fff">Save</T>
  </Pressable>
);
/** "+ Add …" on the left (optional), Save on the right. */
const Foot = ({ left, onSave }) => (
  <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', marginTop: 8 }}>
    {left || <View />}
    <SaveBtn onPress={onSave} />
  </View>
);

const copy = (v) => JSON.parse(JSON.stringify(v));
/** The saved values of one section (what its draft starts from). */
function snapshot(h, key) {
  switch (key) {
    case 'rpb': return { prices: copy(h.sharingPrices) };
    case 'dep': return { depositOn: !!h.depositOn, depositAmount: h.depositAmount };
    case 'rd': return { rentSameAsJoining: !!h.rentSameAsJoining, fixedRentDay: h.fixedRentDay || null };
    case 'wf': return { wifi: copy(h.wifi) };
    case 'dw': return { allowDayWise: !!h.allowDayWise, perDayRent: h.perDayRent };
    case 'ec': return { extraCharges: copy(h.extraCharges) };
    case 'hd': return { name: h.name, address: h.address, contact: h.contact, isOpen: h.isOpen !== false };
    case 'add': return { floor: '', room: '', sharing: null };
    case 'np': return { noticeDays: h.noticeDays };
    case 'hr': return { rules: copy(h.rules || []) };
    case 'lf': return { lateFeeOn: !!app.lateFeeOn, lateFeePerDay: app.lateFeePerDay || 50 };
    case 'po': return { payOnline: h.payOnline !== false, payUpi: !!h.payUpi, upiId: h.upiId || '', payGpay: !!h.payGpay, payPhonepe: !!h.payPhonepe, payPaytm: !!h.payPaytm, payBank: !!h.payBank, bankDetails: h.bankDetails || '', payCash: !!h.payCash, cashNote: h.cashNote || '' };
    default: return {};
  }
}

export function HostelSettings() {
  useApp();
  const h = hostel();
  ensureSettings(h);
  const [openKey, setOpenKey] = useState(null); // only one setting open at a time
  const [d, setD] = useState({}); // draft of the open setting (saved only on Save)
  const [grid, setGrid] = useState(false); // Rent date: 1–28 grid shown
  const [saved, setSaved] = useState(null); // { key, sub } for 1½ seconds
  const scrollRef = useRef(null);
  const boxes = useRef({}); // where each setting is on the page: { y, h }
  const view = useRef({ h: 0, scroll: 0, kb: 0 }); // visible height, scroll position, keyboard height
  const sw = (value, onChange) => <Switch value={!!value} onValueChange={onChange} trackColor={{ true: C.blue, false: C.line }} thumbColor="#fff" />;
  const upd = (patch) => setD({ ...d, ...patch });
  const dirty = openKey && JSON.stringify(d) !== JSON.stringify(snapshot(h, openKey));

  // messages the students see on their home screen
  const tell = (m) => { app.studentMessages = [m, ...(app.studentMessages || [])].slice(0, 5); };
  const staying = () => app.tenants.filter((t) => t.status !== 'vacated' && t.stayType !== 'dayWise').length;
  /** "Yes, change" sheet. Resolves true / false. */
  const ask = (title, text) => new Promise((resolve) => showSheet((close) => (
    <View style={{ gap: 10 }}>
      <T size={20} weight="800">{title}</T>
      <View style={{ backgroundColor: '#FFF7E6', borderWidth: 1, borderColor: '#F5D38A', borderRadius: 12, padding: 12 }}>
        <T style={{ lineHeight: 20 }}>{text}</T>
      </View>
      <Gap h={4} />
      <Btn title="Yes, change" onPress={() => { close(); resolve(true); }} />
      <Btn title="Cancel" variant="text" onPress={() => { close(); resolve(false); }} />
    </View>
  )));
  const dayText = (v) => (v.rentSameAsJoining ? 'Joining date' : ordinal(v.fixedRentDay));

  const subFor = (key, v) => ({
    hd: 'Hostel details',
    add: `Room ${(v.room || '').toUpperCase()} · ${v.sharing} sharing`,
    np: `Notice period · ${v.noticeDays} days`,
    hr: `House rules · ${v.rules.length} rules`,
    lf: v.lateFeeOn ? `Late fee · ${rupees(v.lateFeePerDay)} per day` : 'Late fee · Off',
    rpb: `Sharing + price · ${v.prices.length} sharing${v.prices.length === 1 ? '' : 's'}`,
    dep: v.depositOn ? `Advance / deposit · ${rupees(v.depositAmount)}` : 'Advance / deposit · Off',
    rd: v.rentSameAsJoining ? 'Rent date · Same as joining date' : `Rent date · ${ordinal(v.fixedRentDay)} of every month`,
    wf: `Wi-Fi · ${v.wifi.length} floor${v.wifi.length === 1 ? '' : 's'}`,
    dw: v.allowDayWise ? `Day-wise stay · ${rupees(v.perDayRent)} per day` : 'Day-wise stay · Off',
    ec: 'Extra charges',
    po: 'Payment options',
  }[key]);

  /** Checks and stores the open setting. Returns false when something is missing. */
  const save = async () => {
    const key = openKey;
    if (key === 'hd') {
      if ((d.name || '').trim().length < 2) return toast('Enter the hostel name.'), false;
      if ((d.address || '').trim().length < 5) return toast('Enter the address.'), false;
      if ((d.contact || '').replace(/\D/g, '').length !== 10) return toast('Enter a 10-digit mobile number.'), false;
    }
    if (key === 'np' && !(d.noticeDays >= 1 && d.noticeDays <= 90)) return toast('Enter 1 to 90 days.'), false;
    if (key === 'add') {
      const no = (d.room || '').trim().toUpperCase();
      if (d.floor === '') return toast('Pick the floor.'), false;
      const fl = parseInt(d.floor, 10);
      if (!no) return toast('Type the room number.'), false;
      if (fl === 0 && !isGroundRoom(no)) return toast('Ground floor rooms are G + a number, like G1.'), false;
      if (fl !== 0 && startsWithG(no)) return toast('Only ground floor rooms start with G.'), false;
      if (app.rooms.some((r) => r.number.toUpperCase() === no)) return toast(`Room ${no} already exists.`), false;
      if (!d.sharing) return toast('Pick the sharing.'), false;
      const pr = h.sharingPrices.find((p) => p.sharing === d.sharing);
      if (!pr) return toast(`Add a price for ${d.sharing} sharing in "Sharing + price" first.`), false;
      app.rooms.push({ number: no, floor: fl, sharing: d.sharing, rent: pr.rent, deposit: h.depositOn ? h.depositAmount : 0, perDay: h.perDayRent, dayDeposit: 1000, beds: Array(d.sharing).fill('vacant'), features: [] });
      actions.touch();
      setD(snapshot(h, key));
      showSaved(key, subFor(key, { ...d, room: no }));
      return true;
    }
    if (key === 'rd') {
      if (!d.rentSameAsJoining && !d.fixedRentDay) return toast('Pick a date.'), false;
      const old = snapshot(h, 'rd');
      if (JSON.stringify(old) !== JSON.stringify(d) && staying() > 0) {
        const ok = await ask(`Fee date: ${dayText(old)} → ${dayText(d)}`,
          `${staying()} students are staying. They pay on the new date from now. The days in between are added once to their next fee (fee ÷ days in that month × days). If the new date is earlier, those days are taken off once. After that, the same fee every month. They all get a message.`);
        if (!ok) return false;
        const s = app.stay;
        if (!d.rentSameAsJoining) {
          const oldDay = old.rentSameAsJoining ? 5 : old.fixedRentDay;
          const days = d.fixedRentDay - oldDay;
          const part = Math.round((s.rent * Math.abs(days)) / 30);
          tell({ kind: 'rent', title: `Fee date changed to ${ordinal(d.fixedRentDay)}`,
            body: days >= 0
              ? `Next fee on ${d.fixedRentDay} Nov: ${rupees(s.rent)} + ${rupees(part)} for ${days} extra days (once) = ${rupees(s.rent + part)}.`
              : `Next fee on ${d.fixedRentDay} Nov: ${rupees(s.rent)} − ${rupees(part)} for ${-days} days already paid (once) = ${rupees(s.rent - part)}.` });
          s.dueDate = `${String(d.fixedRentDay).padStart(2, '0')} Nov 2026`;
        } else {
          tell({ kind: 'rent', title: 'Fee date is now your joining date', body: 'You pay on the day of the month you joined.' });
        }
      }
    }
    if (key === 'np' && d.noticeDays !== h.noticeDays) {
      tell({ kind: 'notice', title: `Notice period is now ${d.noticeDays} days`, body: `Tell the owner ${d.noticeDays} days before you leave.` });
      app.hostels[0].noticeDays = d.noticeDays;
    }
    if (key === 'rd' && !d.rentSameAsJoining && !d.fixedRentDay) return toast('Pick a date.'), false;
    if (key === 'dep' && d.depositOn && !d.depositAmount) return toast('Enter the deposit amount.'), false;
    if (key === 'dw' && d.allowDayWise && !d.perDayRent) return toast('Enter the price per day.'), false;
    if (key === 'hr' && d.rules.length === 0) return toast('Keep at least one rule.'), false;
    if (key === 'lf' && d.lateFeeOn && !(d.lateFeePerDay > 0)) return toast('Enter the late fee per day.'), false;
    if (key === 'po') {
      if (!d.payOnline && !d.payUpi && !d.payBank && !d.payCash) return toast('Keep at least one way to pay.'), false;
      if (d.payUpi && !d.upiId.trim()) return toast('Add your UPI ID.'), false;
      if (d.payBank && !d.bankDetails.trim()) return toast('Add bank details.'), false;
    }
    const v = copy(d);
    if (key === 'rpb') {
      h.sharingPrices = v.prices.sort((a, b) => a.sharing - b.sharing);
      h.sharingPrices.forEach((p) => app.rooms.forEach((rm) => { if (rm.sharing === p.sharing) rm.rent = p.rent; }));
    } else if (key === 'wf') h.wifi = v.wifi.sort((a, b) => a.floor - b.floor);
    else if (key === 'ec') {
      h.extraCharges = v.extraCharges;
      const el = v.extraCharges.find((c) => c.id === 'el');
      const la = v.extraCharges.find((c) => c.id === 'la');
      if (el) h.electricitySeparate = el.on;
      if (la) { h.laundry = la.on; h.laundryCharge = la.amount; if (h === app.hostels[0]) app.stay.laundry = la.amount; }
    }
    else if (key === 'lf') { app.lateFeeOn = v.lateFeeOn; app.lateFeePerDay = v.lateFeePerDay; }
    else if (key === 'po') Object.assign(h, v, { payGpay: v.payUpi && v.payGpay, payPhonepe: v.payUpi && v.payPhonepe, payPaytm: v.payUpi && v.payPaytm });
    else Object.assign(h, v);
    actions.touch();
    setD(snapshot(h, key));
    showSaved(key, subFor(key, v));
    return true;
  };

  /** Runs `next` after asking "Save changes?" when the open setting has unsaved changes. */
  const leave = (next) => {
    if (!dirty) return next();
    showSheet((close) => (
      <View style={{ gap: 10 }}>
        <T size={20} weight="800">Save changes?</T>
        <T color={C.muted}>You changed something in this setting.</T>
        <Gap h={6} />
        <Btn title="Save" onPress={async () => { close(); if (await save()) next(); }} />
        <Btn title="Don't save" variant="text" onPress={() => { close(); next(); }} />
      </View>
    ));
  };
  const toggle = (key) => leave(() => {
    if (openKey === key) return setOpenKey(null);
    setOpenKey(key);
    const snap = snapshot(h, key);
    setD(snap);
    setGrid(key === 'rd' && !snap.rentSameAsJoining && !snap.fixedRentDay);
  });
  // The opened setting sits just above the keyboard, whole, with a small gap. Without the keyboard
  // the page moves only if the setting doesn't fit. Too tall to fit → its title goes to the top.
  const GAP = 24;
  const reveal = (key) => {
    const b = boxes.current[key];
    const v = view.current;
    if (!b || !scrollRef.current || !v.h) return;
    const visible = v.h - (Platform.OS === 'ios' ? v.kb : 0); // Android makes the page shorter itself
    let y;
    if (b.h + GAP > visible) y = b.y - 4;
    else if (v.kb > 0) y = b.y + b.h + GAP - visible;
    else if (b.y >= v.scroll && b.y + b.h + GAP <= v.scroll + visible) return; // already fully visible
    else y = b.y + b.h + GAP - visible;
    scrollRef.current.scrollTo({ y: Math.max(0, y), animated: true });
  };
  const openRef = useRef(null);
  openRef.current = openKey;
  useEffect(() => {
    if (!openKey) return undefined;
    const tm = setTimeout(() => reveal(openKey), 150);
    return () => clearTimeout(tm);
  }, [openKey]);
  useEffect(() => {
    const show = Keyboard.addListener('keyboardDidShow', (e) => {
      view.current.kb = e.endCoordinates.height;
      setTimeout(() => openRef.current && reveal(openRef.current), 80);
    });
    const hide = Keyboard.addListener('keyboardDidHide', () => { view.current.kb = 0; });
    return () => { show.remove(); hide.remove(); };
  }, []);
  const showSaved = (key, sub) => {
    setSaved({ key, sub });
    setTimeout(() => setSaved((cur) => (cur && cur.key === key ? null : cur)), 1500);
  };
  const card = (key, icon, title, body) => (
    <SetCard icon={icon} title={title} open={openKey === key} onToggle={() => toggle(key)} saved={saved && saved.key === key ? saved.sub : null}
      onLayout={(e) => { const l = e.nativeEvent.layout; boxes.current[key] = { y: l.y, h: l.height }; }}>
      {openKey === key ? body() : null}
    </SetCard>
  );

  // ---- section bodies (they edit the draft `d`)
  const hostelDetails = () => {
    const line = (label, value, onPress) => (
      <View style={{ marginBottom: 8 }}>
        <T size={11} color={C.muted} style={{ marginBottom: 3, marginLeft: 2 }}>{label}</T>
        <Row><PenBox text={value} onPress={onPress} /></Row>
      </View>
    );
    return (
      <View>
        {line('Hostel name', d.name, () => editValue({ title: 'Hostel name', value: d.name, onSave: (v) => upd({ name: v }) }))}
        {line('Address', d.address, () => editValue({ title: 'Address', value: d.address, onSave: (v) => upd({ address: v }) }))}
        {line('Mobile number', `+91 ${d.contact}`, () => editValue({ title: 'Mobile number', value: d.contact, onSave: (v) => upd({ contact: v }) }))}
        <Row gap={8} style={{ marginBottom: 8 }}>
          <T weight="600" style={{ flex: 1 }}>Open for new students</T>
          {sw(d.isOpen, (v) => upd({ isOpen: v }))}
        </Row>
        <Foot onSave={save} />
      </View>
    );
  };

  // Add room: [Floor  box ✎] and [Room number  box] with their names beside them, Sharing, Save.
  // The rent comes from Sharing + price.
  const addRoom = () => {
    const pr = d.sharing ? h.sharingPrices.find((p) => p.sharing === d.sharing) : null;
    const row = (label, box) => (
      <Row gap={8} style={{ marginBottom: 10 }}>
        <T weight="600" style={{ width: 110 }}>{label}</T>
        {box}
      </Row>
    );
    const setFloor = (f) => {
      const no = (d.room || '').trim();
      upd({ floor: String(f), room: f === 0 && !startsWithG(no) ? `G${no}` : f !== 0 && startsWithG(no) ? no.slice(1) : no });
    };
    return (
      <View>
        {row('Floor', <PenBox text={d.floor === '' ? '—' : d.floor === '0' ? 'Ground' : d.floor} muted={d.floor === ''}
          onPress={() => editValue({ title: 'Floor', sub: 'Type the floor: 0 = Ground, 1, 2, 3 … up to 50.', value: d.floor, number: true, allowZero: true, onSave: (v) => (v > 50 ? toast('Up to floor 50.') : setFloor(v)) })} />)}
        {row('Room number', (
          <TextInput value={d.room} onChangeText={(v) => upd(startsWithG(v) && d.floor !== '0' ? { room: v, floor: '0' } : { room: v })}
            placeholder={d.floor === '0' ? 'G1' : '305'} placeholderTextColor="#9AA7B8" autoCapitalize="characters" maxLength={8}
            style={{ flex: 1, borderWidth: 1.4, borderColor: C.blue, borderRadius: 12, paddingHorizontal: 12, minHeight: 46, fontSize: 16, ...appFont('800'), color: C.ink }} />
        ))}
        <T weight="600" style={{ marginBottom: 6 }}>Sharing</T>
        <SharingPicker value={d.sharing} onChange={(n) => upd({ sharing: n })} />
        {d.sharing ? (
          <T size={12.5} color={pr ? C.muted : C.red} style={{ marginTop: 8 }}>
            {pr ? `Rent ${rupees(pr.rent)} per bed (from Sharing + price)` : `Add a price for ${d.sharing} sharing in "Sharing + price" first.`}
          </T>
        ) : null}
        <Foot onSave={save} />
      </View>
    );
  };

  const lateFeeBody = () => (
    <View>
      <T color={C.muted} style={{ marginBottom: 8 }}>Added for every day after the rent date until the student pays</T>
      <Row gap={8} style={{ marginBottom: 10 }}>
        <T weight="600" style={{ flex: 1 }}>Charge late fee</T>
        {sw(d.lateFeeOn, (v) => upd({ lateFeeOn: v }))}
      </Row>
      {d.lateFeeOn ? (
        <>
          <Row gap={8} style={{ flexWrap: 'wrap' }}>
            {[20, 50, 100].map((n) => (
              <Pressable key={n} onPress={() => upd({ lateFeePerDay: n })} style={{ borderWidth: 1.4, borderColor: d.lateFeePerDay === n ? C.blue : C.line, backgroundColor: d.lateFeePerDay === n ? C.blueSoft : '#fff', borderRadius: 12, paddingHorizontal: 14, paddingVertical: 9 }}>
                <T weight="800" color={d.lateFeePerDay === n ? C.blue : C.ink}>{rupees(n)} / day</T>
              </Pressable>
            ))}
          </Row>
          <T weight="600" style={{ marginTop: 12, marginBottom: 4 }}>Or type amount</T>
          <Row><PenBox text={[20, 50, 100].includes(d.lateFeePerDay) ? 'e.g. ₹30' : `${rupees(d.lateFeePerDay)} / day`} muted={[20, 50, 100].includes(d.lateFeePerDay)} onPress={() => editValue({ title: 'Late fee per day', value: '', prefix: '₹', number: true, onSave: (v) => upd({ lateFeePerDay: v }) })} /></Row>
          <View style={{ backgroundColor: '#FFF7E6', borderWidth: 1, borderColor: '#F5D38A', borderRadius: 12, padding: 12, marginTop: 10 }}>
            <T size={14}>Example: rent ₹8,000, paid 5 days late → 5 × {rupees(d.lateFeePerDay)} = {rupees(5 * d.lateFeePerDay)} late fee.</T>
          </View>
        </>
      ) : (
        <T size={12.5} color={C.muted}>Off – students see only the fee date, no late fee.</T>
      )}
      <Foot onSave={save} />
    </View>
  );

  const houseRules = () => (
    <View>
      <T color={C.muted} style={{ marginBottom: 8 }}>Students see these in Settings → House rules</T>
      {d.rules.map((r, i) => (
        <Row key={i} gap={8} style={{ marginBottom: 8 }}>
          <View style={{ width: 26, height: 26, borderRadius: 13, backgroundColor: C.blueSoft, alignItems: 'center', justifyContent: 'center' }}><T size={12.5} weight="600" color={C.blue}>{i + 1}</T></View>
          <View style={{ flex: 1 }}><PenBox text={r} onPress={() => editValue({ title: `Rule ${i + 1}`, value: r, onSave: (v) => upd({ rules: d.rules.map((x, j) => (j === i ? v : x)) }) })} /></View>
          <Pressable hitSlop={8} onPress={() => upd({ rules: d.rules.filter((x, j) => j !== i) })}><Icon name="trash-outline" size={20} color={C.red} /></Pressable>
        </Row>
      ))}
      <RuleAdder onAdd={(x) => upd({ rules: [...d.rules, x] })} />
      <T weight="600" style={{ marginTop: 10, marginBottom: 6 }}>Quick add</T>
      <Row gap={6} style={{ flexWrap: 'wrap' }}>
        {['No loud music after 10 PM', 'Switch off lights & fans', 'No cooking in rooms', 'Lock your room'].filter((x) => !d.rules.includes(x)).map((x) => (
          <Pressable key={x} onPress={() => upd({ rules: [...d.rules, x] })} style={{ flexDirection: 'row', alignItems: 'center', gap: 4, borderWidth: 1, borderColor: C.line, borderRadius: 99, paddingHorizontal: 10, paddingVertical: 6, backgroundColor: '#fff' }}>
            <Icon name="add" size={14} color={C.blue} /><T size={12.5} weight="600">{x}</T>
          </Pressable>
        ))}
      </Row>
      <Foot onSave={save} />
    </View>
  );

  const noticePeriod = () => {
    const preset = [15, 30, 45].includes(d.noticeDays);
    return (
      <View>
        <T color={C.muted} style={{ marginBottom: 8 }}>Days a student must tell you before leaving</T>
        <Row gap={8} style={{ flexWrap: 'wrap' }}>
          {[15, 30, 45].map((n) => (
            <Pressable key={n} onPress={() => upd({ noticeDays: n })} style={{ borderWidth: 1.4, borderColor: d.noticeDays === n ? C.blue : C.line, backgroundColor: d.noticeDays === n ? C.blueSoft : '#fff', borderRadius: 12, paddingHorizontal: 14, paddingVertical: 9 }}>
              <T weight="600" color={d.noticeDays === n ? C.blue : C.ink}>{n} days</T>
            </Pressable>
          ))}
        </Row>
        <T weight="600" style={{ marginTop: 12, marginBottom: 4 }}>Or type days</T>
        <Row><PenBox text={preset ? 'e.g. 7, 14, 21 days' : `${d.noticeDays} days`} muted={preset} onPress={() => editValue({ title: 'Notice period', sub: 'Enter 1 to 90 days', value: preset ? '' : d.noticeDays, number: true, onSave: (v) => upd({ noticeDays: v }) })} /></Row>
        <View style={{ backgroundColor: '#FFF7E6', borderWidth: 1, borderColor: '#F5D38A', borderRadius: 12, padding: 12, marginTop: 10 }}>
          <T size={14}>All students get a message and their screen shows the new notice period.</T>
        </View>
        <Foot onSave={save} />
      </View>
    );
  };

  const rentPerBed = () => {
    const rows = d.prices || [];
    const taken = rows.map((r) => r.sharing);
    const setRows = (r) => upd({ prices: r });
    const add = () => showSheet((close) => <AddSharingSheet close={close} taken={taken} onSave={(n, rent) => setRows([...rows, { sharing: n, rent }].sort((a, b) => a.sharing - b.sharing))} />);
    return (
      <View>
        <ColLabels a="Sharing" b="Price" />
        {rows.map((p, i) => (
          <Row key={i} gap={8} style={{ marginBottom: 8 }}>
            <PenBox text={`${p.sharing} sharing`} onPress={() => showSheet((close) => (
              <SharingSheet close={close} current={p.sharing} taken={taken} onSave={(n) => setRows(rows.map((r, j) => (j === i ? { ...r, sharing: n } : r)))} />
            ))} />
            <PenBox text={rupees(p.rent)} onPress={() => editValue({ title: `Rent for ${p.sharing} sharing`, sub: 'Per bed, every month. New price is for new students.', value: p.rent, prefix: '₹', number: true, onSave: (v) => setRows(rows.map((r, j) => (j === i ? { ...r, rent: v } : r))) })} />
            <RemoveBtn onPress={() => setRows(rows.filter((_, j) => j !== i))} />
          </Row>
        ))}
        {rows.length === 0 ? <BlankLine aText="Sharing" bText="₹ Price" onAdd={add} /> : null}
        <Foot left={rows.length < 12 ? <AddLink title="Add sharing" disabled={rows.length === 0} onPress={add} /> : null} onSave={save} />
      </View>
    );
  };

  const deposit = () => (
    <View>
      <Row gap={8} style={{ marginBottom: 8 }}>
        <T weight="600" style={{ flex: 1 }}>Take advance / deposit</T>
        {sw(d.depositOn, (v) => upd({ depositOn: v }))}
      </Row>
      <Row><PenBox muted={!d.depositOn} text={rupees(d.depositAmount)} onPress={() => editValue({ title: 'Advance / deposit', sub: 'Paid once when the student joins', value: d.depositAmount, prefix: '₹', number: true, onSave: (v) => upd({ depositAmount: v }) })} /></Row>
      <Foot onSave={save} />
    </View>
  );

  const rentDate = () => (
    <View>
      <Segmented options={[{ value: true, label: 'Joining date' }, { value: false, label: 'Fixed date' }]} value={d.rentSameAsJoining}
        onChange={(v) => { upd({ rentSameAsJoining: v }); setGrid(!v && !d.fixedRentDay); }} />
      {d.rentSameAsJoining ? (
        <T size={12.5} color={C.muted} style={{ marginTop: 8 }}>Joined on 12th → pays every 12th.</T>
      ) : grid ? (
        <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 6, marginTop: 10 }}>
          {Array.from({ length: 28 }, (_, i) => i + 1).map((day) => {
            const sel = d.fixedRentDay === day;
            return (
              <Pressable key={day} onPress={() => { upd({ fixedRentDay: day }); setGrid(false); }} style={{ width: '12.4%', paddingVertical: 8, borderRadius: 8, alignItems: 'center', borderWidth: 1.2, borderColor: sel ? C.blue : C.line, backgroundColor: sel ? C.blue : '#fff' }}>
                <T size={12.5} weight="600" color={sel ? '#fff' : C.ink}>{day}</T>
              </Pressable>
            );
          })}
        </View>
      ) : (
        <Row gap={10} style={{ marginTop: 12, backgroundColor: C.greenSoft, borderRadius: 12, padding: 12 }}>
          <T weight="600" size={14} color={C.green} style={{ flex: 1 }}>Your fixed fee date is {ordinal(d.fixedRentDay)} of every month</T>
          <Pressable onPress={() => setGrid(true)} style={{ flexDirection: 'row', alignItems: 'center', gap: 4, borderWidth: 1.4, borderColor: C.blue, borderRadius: 8, paddingHorizontal: 10, paddingVertical: 6, backgroundColor: '#fff' }}>
            <Icon name="pencil" size={14} color={C.blue} />
            <T weight="600" size={12.5} color={C.blue}>Change</T>
          </Pressable>
        </Row>
      )}
      <Foot onSave={save} />
    </View>
  );

  const wifi = () => {
    const rows = d.wifi || [];
    const setRows = (r) => upd({ wifi: r });
    const add = () => showSheet((close) => (
      <AddWifiSheet close={close} onSave={(floor, password) => (rows.some((r) => r.floor === floor)
        ? toast(`${floorName2(floor)} already has Wi-Fi.`)
        : setRows([...rows, { floor, password }].sort((a, b) => a.floor - b.floor)))} />
    ));
    return (
      <View>
        <ColLabels a="Floor" b="Password" />
        {rows.map((w, i) => (
          <Row key={i} gap={8} style={{ marginBottom: 8 }}>
            <PenBox text={floorName2(w.floor)} onPress={() => showSheet((close) => <FloorSheet close={close} current={w.floor} onSave={(f) => {
              if (f !== w.floor && rows.some((r) => r.floor === f)) return toast(`${floorName2(f)} already has Wi-Fi.`);
              setRows(rows.map((r, j) => (j === i ? { ...r, floor: f } : r)));
            }} />)} />
            <PenBox mono text={w.password} onPress={() => editValue({ title: `Wi-Fi password · ${floorName2(w.floor)}`, sub: 'Students on this floor see it', value: w.password, placeholder: 'password', onSave: (v) => setRows(rows.map((r, j) => (j === i ? { ...r, password: v } : r))) })} />
            <RemoveBtn onPress={() => setRows(rows.filter((_, j) => j !== i))} />
          </Row>
        ))}
        {rows.length === 0 ? <BlankLine aText="Floor" bText="Password" onAdd={add} /> : null}
        <Foot left={<AddLink title="Add Wi-Fi" disabled={rows.length === 0} onPress={add} />} onSave={save} />
      </View>
    );
  };

  const dayWise = () => (
    <View>
      <Row gap={8} style={{ marginBottom: 8 }}>
        <T weight="600" style={{ flex: 1 }}>Allow day-wise stay</T>
        {sw(d.allowDayWise, (v) => upd({ allowDayWise: v }))}
      </Row>
      <Row><PenBox muted={!d.allowDayWise} text={`${rupees(d.perDayRent)} per day`} onPress={() => editValue({ title: 'Price per day', sub: 'For students staying a few days', value: d.perDayRent, prefix: '₹', number: true, onSave: (v) => upd({ perDayRent: v }) })} /></Row>
      <Foot onSave={save} />
    </View>
  );

  const charges = () => {
    const list = d.extraCharges || [];
    const setC = (i, patch) => upd({ extraCharges: list.map((c, j) => (j === i ? { ...c, ...patch } : c)) });
    return (
      <View>
        {list.map((c, i) => (
          <Row key={c.id} gap={8} style={{ paddingVertical: 6 }}>
            <Icon name={c.icon} size={19} color={C.blue} />
            <T weight="600" style={{ flex: 1 }}>{c.name}</T>
            {c.per === 'unit' ? <T size={12.5} color={C.muted}>Added to the bill</T> : null}
            {c.per === 'unit' ? null : <Pressable onPress={() => editValue({ title: c.name, sub: 'Amount', value: c.amount, prefix: '₹', number: true, onSave: (v) => setC(i, { amount: v }) })}
              style={{ flexDirection: 'row', alignItems: 'center', gap: 4, borderWidth: 1.2, borderColor: C.line, borderRadius: 8, paddingHorizontal: 8, paddingVertical: 5, opacity: c.on ? 1 : 0.45 }}>
              <T size={12.5} weight="800">{rupees(c.amount)} {perText(c.per)}</T>
              <Icon name="pencil" size={14} color={C.blue} />
            </Pressable>}
            {sw(c.on, (v) => setC(i, { on: v }))}
          </Row>
        ))}
        <Foot left={<AddLink title="Add another charge" onPress={() => showSheet((close) => <AddChargeSheet close={close} onSave={(c) => upd({ extraCharges: [...list, c] })} />)} />} onSave={save} />
      </View>
    );
  };

  const payments = () => (
    <View>
      {[
        ['payUpi', 'qr-code-outline', 'UPI'],
        ['payGpay', 'logo-google', 'Google Pay'],
        ['payPhonepe', 'phone-portrait-outline', 'PhonePe'],
        ['payPaytm', 'phone-portrait-outline', 'Paytm'],
        ['payBank', 'business-outline', 'Bank transfer'],
        ['payCash', 'cash-outline', 'Cash'],
      ].map(([k, icon, label]) => {
        const app2 = ['payGpay', 'payPhonepe', 'payPaytm'].includes(k);
        return (
          <View key={k}>
            <Row gap={8} style={{ paddingVertical: 7, opacity: app2 && !d.payUpi ? 0.45 : 1 }}>
              <Icon name={icon} size={19} color={C.blue} />
              <T weight="600" style={{ flex: 1 }}>{label}</T>
              {sw(d[k], (v) => (app2 && !d.payUpi ? toast('Turn on UPI first.') : upd({ [k]: v })))}
            </Row>
            {k === 'payUpi' && d.payUpi ? (
              <Row style={{ paddingLeft: 27, marginBottom: 4 }}><PenBox text={d.upiId || 'Add UPI ID'} muted={!d.upiId} onPress={() => editValue({ title: 'Your UPI ID', sub: 'Google Pay, PhonePe and Paytm use this too', value: d.upiId, placeholder: 'name@okicici', onSave: (v) => upd({ upiId: v }) })} /></Row>
            ) : null}
            {k === 'payBank' && d.payBank ? (
              <Row style={{ paddingLeft: 27, marginBottom: 4 }}><PenBox text={d.bankDetails || 'Add bank details'} muted={!d.bankDetails} onPress={() => editValue({ title: 'Bank details', sub: 'Name, account number, IFSC', value: d.bankDetails, placeholder: 'A/c 1234 · IFSC SBIN0001234', onSave: (v) => upd({ bankDetails: v }) })} /></Row>
            ) : null}
            {k === 'payCash' && d.payCash ? (
              <View style={{ paddingLeft: 27, marginBottom: 4 }}>
                <T size={12.5} color={C.muted} style={{ marginBottom: 4 }}>Message students see when they pick Cash</T>
                <TextInput value={d.cashNote} onChangeText={(v) => upd({ cashNote: v })} multiline maxLength={160}
                  style={{ borderWidth: 1.2, borderColor: C.blue, backgroundColor: C.blueSoft, borderRadius: 12, padding: 10, fontSize: 13.5, color: C.ink, minHeight: 56, textAlignVertical: 'top' }} />
              </View>
            ) : null}
          </View>
        );
      })}
      <View style={{ borderTopWidth: 1, borderTopColor: C.line, marginTop: 6, paddingTop: 6 }}>
        <Row gap={8} style={{ paddingVertical: 7 }}>
          <Icon name="flash-outline" size={19} color={C.green} />
          <View style={{ flex: 1 }}>
            <T weight="600">Instant online pay</T>
            <T size={12.5} color={C.muted}>UPI, card or netbanking · paid at once, no checking</T>
          </View>
          {sw(d.payOnline, (v) => upd({ payOnline: v }))}
        </Row>
        {d.payOnline ? <T size={12.5} color={C.muted} style={{ paddingLeft: 27, marginBottom: 4 }}>Needs a Razorpay account (small fee per payment). Money comes to your bank in 2 days.</T> : null}
      </View>
      <Foot onSave={save} />
    </View>
  );

  return (
    <Screen title="Hostel settings" scrollRef={scrollRef} bottomSpace={openKey ? Math.round(Dimensions.get('window').height * 0.6) : 0}
      onScroll={(e) => { view.current.scroll = e.nativeEvent.contentOffset.y; }}
      onScrollLayout={(e) => { view.current.h = e.nativeEvent.layout.height; }}>
      <RoomsBlock />
      <Gap h={12} />
      {card('hd', 'business-outline', 'Hostel details', hostelDetails)}
      {card('room', 'create-outline', 'Change room details', () => <ChangeRoomBody onSaved={(sub) => showSaved('room', sub)} ask={ask} tell={tell} />)}
      {card('add', 'add-circle-outline', 'Add room', addRoom)}
      {card('rpb', 'cash-outline', 'Sharing + price', rentPerBed)}
      {card('dep', 'lock-closed-outline', 'Advance / deposit', deposit)}
      {card('rd', 'calendar-outline', 'Rent date', rentDate)}
      {card('lf', 'timer-outline', 'Late fee', lateFeeBody)}
      {card('np', 'hourglass-outline', 'Notice period', noticePeriod)}
      {card('hr', 'document-text-outline', 'House rules', houseRules)}
      {card('wf', 'wifi-outline', 'Wi-Fi', wifi)}
      {card('dw', 'sunny-outline', 'Allow day-wise stay', dayWise)}
      {card('ec', 'receipt-outline', 'Extra charges', charges)}
      {card('po', 'wallet-outline', 'Payment options', payments)}
      {card('ac', 'person-circle-outline', 'Account', () => (
        <MenuGroup>
          <MenuRow icon="lock-closed-outline" title="Change password" onPress={() => showSheet((close) => <ChangePasswordSheet close={close} />)} />
        </MenuGroup>
      ))}
    </Screen>
  );
}

// ======================================================================
// Staff (owner only): one line per staff member with a down arrow; opening shows duties
// (switches), duties the owner typed (+ Add any duty you wish), daily jobs, Remove and Save.
// ======================================================================
export const STAFF_DUTIES = [
  ['rent', 'cash-outline', 'Collect rent · record cash'],
  ['approve', 'person-add-outline', 'Approve new students'],
  ['rooms', 'bed-outline', 'Rooms & beds (book, free a bed)'],
  ['complaints', 'construct-outline', 'Complaints · reply & close'],
  ['leaving', 'log-out-outline', 'Leaving notices · check-out'],
  ['reminders', 'notifications-outline', 'Send rent reminders'],
  ['reports', 'bar-chart-outline', 'See reports & money totals'],
  ['ids', 'id-card-outline', 'See ID proofs'],
  ['checklist', 'checkbox-outline', 'Daily jobs checklist'],
];
export const JOBS = [['manager', 'Manager / warden'], ['cleaning', 'Cleaning'], ['security', 'Security'], ['cook', 'Cook'], ['other', 'Other']];
export const jobName = (st) => (st.job === 'other' && st.jobOther ? st.jobOther : (JOBS.find((j) => j[0] === st.job) || JOBS[4])[1]);
const JOB_DUTIES = { manager: ['rent', 'approve', 'rooms', 'complaints', 'leaving', 'checklist'], cleaning: ['complaints', 'checklist'], security: ['leaving', 'checklist'] };

function AddStaffSheet({ close }) {
  const [name, setName] = useState('');
  const [mobile, setMobile] = useState('');
  const [job, setJob] = useState('manager');
  const [other, setOther] = useState('');
  return (
    <View>
      <T size={20} weight="800" style={{ marginBottom: 14 }}>Add staff member</T>
      <Field label="Name" placeholder="e.g. Ramesh Kumar" value={name} onChangeText={setName} maxLength={80} />
      <Field label="Mobile number" prefix="+91" keyboardType="phone-pad" value={mobile} onChangeText={(v) => setMobile(v.replace(/\D/g, ''))} maxLength={10} />
      <T weight="600" style={{ marginBottom: 6 }}>Job</T>
      <Row gap={8} style={{ flexWrap: 'wrap' }}>
        {JOBS.map(([code, label]) => (
          <Pressable key={code} onPress={() => setJob(code)} style={{ borderWidth: 1.4, borderColor: job === code ? C.blue : C.line, backgroundColor: job === code ? C.blueSoft : '#fff', borderRadius: 12, paddingHorizontal: 12, paddingVertical: 8 }}>
            <T weight="600" color={job === code ? C.blue : C.ink}>{label}</T>
          </Pressable>
        ))}
      </Row>
      {job === 'other' ? <Field label="Which job?" value={other} onChangeText={setOther} maxLength={40} style={{ marginTop: 10 }} /> : null}
      <T size={12.5} color={C.muted} style={{ marginTop: 8, marginBottom: 12 }}>Duties are ticked for the job; change them after adding.</T>
      <Btn
        title="Add & send SMS invite"
        onPress={() => {
          if (name.trim().length < 2) return toast('Enter the name.');
          if (!/^[6-9][0-9]{9}$/.test(mobile)) return toast('Enter a 10-digit mobile number.');
          if (app.staff.some((x) => x.mobile.replace(/\D/g, '') === mobile)) return toast('This mobile number is already in your staff.');
          actions.addStaff({ id: 's' + Date.now(), name: name.trim(), mobile: `${mobile.slice(0, 5)} ${mobile.slice(5)}`, job, jobOther: other.trim(), duties: JOB_DUTIES[job] || ['checklist'], custom: [], checklist: '' });
          close();
          toast(`${name.trim()} added. SMS invite sent.`);
        }}
      />
    </View>
  );
}

function AddDutySheet({ close, onAdd }) {
  const [v, setV] = useState('');
  return (
    <View>
      <T size={20} weight="800">Add a duty</T>
      <T color={C.muted} style={{ marginTop: 2, marginBottom: 10 }}>Type the duty in your own words.</T>
      <Field placeholder="e.g. Buy vegetables" value={v} onChangeText={setV} maxLength={60} autoFocus />
      <Btn title="Add" onPress={() => { if (!v.trim()) return toast('This can’t be empty.'); onAdd(v.trim()); close(); }} />
    </View>
  );
}

export function StaffLogins() {
  useApp();
  const [openId, setOpenId] = useState(null);
  const [d, setD] = useState(null); // draft of the open one
  const [saved, setSaved] = useState(null);
  const snap = (st) => ({ duties: [...st.duties], custom: st.custom.map((c) => ({ ...c })), checklist: st.checklist || '' });
  const dirty = () => openId && d && JSON.stringify(d) !== JSON.stringify(snap(app.staff.find((x) => x.id === openId)));
  const save = () => {
    const st = app.staff.find((x) => x.id === openId);
    Object.assign(st, JSON.parse(JSON.stringify(d)));
    actions.touch();
    setSaved({ id: st.id, sub: st.name });
    setTimeout(() => setSaved((cur) => (cur && cur.id === st.id ? null : cur)), 1500);
    return true;
  };
  const leave = (next) => {
    if (!dirty()) return next();
    showSheet((close) => (
      <View style={{ gap: 10 }}>
        <T size={20} weight="800">Save changes?</T>
        <Btn title="Save" onPress={() => { close(); save(); next(); }} />
        <Btn title="Don't save" variant="text" onPress={() => { close(); next(); }} />
      </View>
    ));
  };
  const toggle = (st) => leave(() => {
    if (openId === st.id) { setOpenId(null); setD(null); return; }
    setOpenId(st.id);
    setD(snap(st));
  });
  const remove = async (st) => {
    const ok = await confirm({ title: `Remove ${st.name}?`, text: 'They can no longer use the app for this hostel.', confirmLabel: 'Remove staff', danger: true });
    if (!ok) return;
    app.staff = app.staff.filter((x) => x.id !== st.id);
    setOpenId(null);
    setD(null);
    actions.touch();
    toast(`${st.name} removed.`);
  };
  const sw = (value, onChange) => <Switch value={!!value} onValueChange={onChange} trackColor={{ true: C.blue, false: C.line }} thumbColor="#fff" />;
  const details = (st) => (
    <View style={{ marginTop: 12 }}>
      <T weight="600" style={{ marginBottom: 4 }}>Duties in the app</T>
      {STAFF_DUTIES.map(([code, icon, label]) => (
        <Row key={code} gap={10} style={{ paddingVertical: 6, borderBottomWidth: 1, borderBottomColor: '#F0F2F6' }}>
          <Icon name={icon} size={19} color={C.blue} />
          <T weight="600" style={{ flex: 1 }}>{label}</T>
          {sw(d.duties.includes(code), (on) => setD({ ...d, duties: on ? [...d.duties, code] : d.duties.filter((x) => x !== code) }))}
        </Row>
      ))}
      {d.custom.map((c, i) => (
        <Row key={'c' + i} gap={10} style={{ paddingVertical: 6, borderBottomWidth: 1, borderBottomColor: '#F0F2F6' }}>
          <Icon name="star-outline" size={19} color={C.blue} />
          <T weight="600" style={{ flex: 1 }}>{c.name}</T>
          <Pressable hitSlop={8} onPress={() => setD({ ...d, custom: d.custom.filter((_, j) => j !== i) })}><Icon name="close" size={20} color={C.red} /></Pressable>
          {sw(c.on, (on) => setD({ ...d, custom: d.custom.map((x, j) => (j === i ? { ...x, on } : x)) }))}
        </Row>
      ))}
      <AddLink title="Add any duty you wish" onPress={() => showSheet((close) => <AddDutySheet close={close} onAdd={(name) => setD({ ...d, custom: [...d.custom, { name, on: true }] })} />)} />
      <T weight="600" style={{ marginTop: 12, marginBottom: 6 }}>Daily jobs (checklist)</T>
      <Row><PenBox text={d.checklist || 'Tap to add daily jobs'} muted={!d.checklist} onPress={() => editValue({ title: 'Daily jobs', sub: 'What must be done every day', value: d.checklist, placeholder: 'Lock gate 10:30 PM · Check water tank', onSave: (v) => setD({ ...d, checklist: v }) })} /></Row>
      <Row style={{ justifyContent: 'space-between', alignItems: 'center', marginTop: 12 }}>
        <Pressable onPress={() => remove(st)}><T weight="600" color={C.red}>Remove staff</T></Pressable>
        <SaveBtn onPress={save} />
      </Row>
    </View>
  );
  return (
    <Screen title="Staff">
      <T color={C.muted} style={{ marginBottom: 10 }}>Tap a name to see and change his duties.</T>
      {app.staff.map((st) => {
        const open = openId === st.id;
        return (
          <View key={st.id} style={{ marginBottom: 8 }}>
            <Card style={{ borderWidth: open ? 1.5 : 1, borderColor: open ? C.blue : C.line }}>
              <Pressable onPress={() => toggle(st)} style={{ flexDirection: 'row', alignItems: 'center', gap: 10 }}>
                <Avatar name={st.name} size={40} />
                <View style={{ flex: 1 }}>
                  <T weight="800" size={16}>{st.name}</T>
                  <T size={12.5} color={C.muted}>{jobName(st)} · {st.mobile}</T>
                </View>
                <Icon name={open ? 'chevron-up' : 'chevron-down'} size={22} color={C.blue} />
              </Pressable>
              {open && d ? details(st) : null}
            </Card>
            {saved && saved.id === st.id ? <SavedCover sub={saved.sub} /> : null}
          </View>
        );
      })}
      <Pressable onPress={() => leave(() => showSheet((close) => <AddStaffSheet close={close} />))}
        style={{ borderWidth: 1.5, borderStyle: 'dashed', borderColor: C.blue, borderRadius: 12, padding: 14, alignItems: 'center', marginTop: 4, flexDirection: 'row', justifyContent: 'center', gap: 6 }}>
        <Icon name="add" size={20} color={C.blue} />
        <T weight="600" color={C.blue}>Add staff member</T>
      </Pressable>
    </Screen>
  );
}

// ======================================================================
// Invite students
// ======================================================================
function FakeQr() {
  const n = 21;
  const finder = (r, c, r0, c0) => {
    const rr = r - r0;
    const cc = c - c0;
    if (rr < 0 || cc < 0 || rr > 6 || cc > 6) return false;
    return rr === 0 || rr === 6 || cc === 0 || cc === 6 || (rr >= 2 && rr <= 4 && cc >= 2 && cc <= 4);
  };
  const on = (r, c) => {
    if (finder(r, c, 0, 0) || finder(r, c, 0, n - 7) || finder(r, c, n - 7, 0)) return true;
    if ((r < 8 && c < 8) || (r < 8 && c > n - 9) || (r > n - 9 && c < 8)) return false;
    return (r * 7 + c * 13 + r * c) % 5 < 2;
  };
  return (
    <View style={{ padding: 12, borderWidth: 1, borderColor: C.line, borderRadius: 12, alignSelf: 'center' }}>
      {Array.from({ length: n }, (_, r) => (
        <View key={r} style={{ flexDirection: 'row' }}>
          {Array.from({ length: n }, (_, c) => (
            <View key={c} style={{ width: 9, height: 9, backgroundColor: on(r, c) ? C.ink : '#fff' }} />
          ))}
        </View>
      ))}
    </View>
  );
}

export function InviteStudents() {
  const h = hostel();
  const link = 'myhostel.in/j/' + h.name.toLowerCase().replace(/[^a-z0-9]+/g, '-');
  return (
    <Screen title="Invite students">
      <Card>
        <View style={{ alignItems: 'center', gap: 4 }}>
          <T size={20} weight="800">{hostelTitle(h)}</T>
          <T color={C.muted}>Scan to see rooms & join</T>
        </View>
        <Gap h={16} />
        <FakeQr />
        <Gap h={12} />
        <Btn small variant="tonal" icon="download-outline" title="Download QR code" onPress={() => toast('QR code saved to your phone (Photos / Gallery).')} style={{ alignSelf: 'center' }} />
        <Gap h={12} />
        <T weight="600" color={C.blue} center selectable>{link}</T>
        <T size={12.5} color={C.muted} center style={{ marginTop: 6 }}>Prototype: QR pattern is a placeholder.</T>
      </Card>
      <Gap h={14} />
      <Btn icon="copy-outline" title="Copy link" onPress={() => toast('Link copied (prototype)')} />
      <Gap />
      <Btn variant="outline" icon="logo-whatsapp" title="Share on WhatsApp" onPress={() => toast('Would open WhatsApp with the link and a short message.')} />
      <Gap />
      <Btn variant="outline" icon="print-outline" title="Print poster (PDF)" onPress={() => toast('An A4 poster PDF with the QR would be created.')} />
    </Screen>
  );
}

// ======================================================================
// Notifications (bell)
// ======================================================================
const KIND_ICON = { pay: 'wallet-outline', issue: 'construct-outline', join: 'person-add-outline', rent: 'time-outline', notice: 'log-out-outline' };
export function Notifications() {
  useApp();
  const today = app.notifications.filter((n) => n.today);
  const earlier = app.notifications.filter((n) => !n.today);
  const group = (list) => (
    <Card padding={0}>
      {list.map((n, i) => (
        <Pressable key={n.id} onPress={() => { n.unread = false; actions.touch(); }} style={{ flexDirection: 'row', gap: 12, padding: 14, borderBottomWidth: i < list.length - 1 ? 1 : 0, borderBottomColor: C.line }}>
          <IconBox name={KIND_ICON[n.kind] || 'notifications-outline'} />
          <View style={{ flex: 1 }}>
            <T weight={n.unread ? '800' : '600'}>{n.title}</T>
            <T size={12.5} color={C.muted} style={{ marginTop: 2, lineHeight: 18 }}>{n.body}</T>
            <T size={12.5} color={C.muted} style={{ marginTop: 4 }}>{n.time}</T>
          </View>
          {n.unread ? <View style={{ width: 10, height: 10, borderRadius: 5, backgroundColor: C.blue, marginTop: 6 }} /> : null}
        </Pressable>
      ))}
    </Card>
  );
  return (
    <Screen title="Notifications" right={<Btn small variant="text" title="Mark all read" disabled={!unreadCount()} onPress={actions.markAllRead} />}>
      {today.length ? (<><SectionTitle>Today</SectionTitle>{group(today)}</>) : null}
      {earlier.length ? (<><SectionTitle>Yesterday</SectionTitle>{group(earlier)}</>) : null}
    </Screen>
  );
}

// ======================================================================
// Reports (charts + Excel)
// ======================================================================
const MONTHS6 = ['May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct'];
const COLLECTED = [118000, 126500, 131000, 142500, 149000, 136500];
const OCCUPANCY = [72, 78, 81, 86, 90, 85];

function BarChart() {
  const max = Math.max(...COLLECTED);
  return (
    <Row align="flex-end" gap={8} style={{ height: 190 }}>
      {COLLECTED.map((v, i) => {
        const last = i === COLLECTED.length - 1;
        return (
          <View key={i} style={{ flex: 1, alignItems: 'center', justifyContent: 'flex-end' }}>
            <T size={11} weight="800" color={last ? C.blue : C.muted}>₹{Math.round(v / 1000)}k</T>
            <View style={{ width: '100%', height: (130 * v) / max, backgroundColor: last ? C.blue : C.blue + '59', borderTopLeftRadius: 6, borderTopRightRadius: 6, marginTop: 4 }} />
            <T size={12.5} color={C.muted} style={{ marginTop: 6 }}>{MONTHS6[i]}</T>
          </View>
        );
      })}
    </Row>
  );
}

/** Occupancy shown as dots on a 50–100% scale (no chart library needed). */
function DotChart() {
  const H = 120;
  const y = (v) => H - ((v - 50) / 50) * H;
  return (
    <View>
      <View style={{ height: H, position: 'relative' }}>
        {[60, 80, 100].map((g) => (
          <View key={g} style={{ position: 'absolute', left: 0, right: 0, top: y(g), borderTopWidth: 1, borderTopColor: C.line }}>
            <T size={11} color={C.muted} style={{ position: 'absolute', top: -14 }}>{g}%</T>
          </View>
        ))}
        <Row style={{ position: 'absolute', left: 0, right: 0, top: 0, bottom: 0 }} gap={0} align="stretch">
          {OCCUPANCY.map((v, i) => {
            const last = i === OCCUPANCY.length - 1;
            return (
              <View key={i} style={{ flex: 1, alignItems: 'center' }}>
                <View style={{ position: 'absolute', top: y(v), bottom: 0, width: 3, backgroundColor: C.green + '33' }} />
                <View style={{ position: 'absolute', top: y(v) - (last ? 6 : 4), width: last ? 12 : 8, height: last ? 12 : 8, borderRadius: 8, backgroundColor: C.green }} />
                {last ? <T size={12.5} weight="600" color={C.green} style={{ position: 'absolute', top: y(v) - 26 }}>{v}%</T> : null}
              </View>
            );
          })}
        </Row>
      </View>
      <Row gap={0} style={{ marginTop: 6 }}>
        {MONTHS6.map((m) => <T key={m} size={12.5} color={C.muted} center style={{ flex: 1 }}>{m}</T>)}
      </Row>
    </View>
  );
}

function HBar({ label, value, max, color, amount }) {
  return (
    <Row gap={10} style={{ paddingVertical: 6 }}>
      <T size={12.5} style={{ width: 96 }}>{label}</T>
      <View style={{ flex: 1 }}><ProgressBar value={value / max} color={color} height={14} /></View>
      <T size={12.5} weight="600" style={{ width: 64, textAlign: 'right' }}>{amount}</T>
    </Row>
  );
}

export function Reports() {
  useApp();
  const [rent, setRent] = useState(true);
  const [yearMode, setYearMode] = useState(false);
  const [month, setMonth] = useState(9); // 0 = Jan · prototype "today" is Oct 2026
  const [year, setYear] = useState(2026);
  const [filter, setFilter] = useState('all');
  const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  const label = yearMode ? String(year) : `${MONTHS[month]} ${year}`;
  const step = (d) => {
    if (yearMode) return setYear(year + d);
    let m = month + d, y = year;
    if (m < 0) { m = 11; y -= 1; }
    if (m > 11) { m = 0; y += 1; }
    setMonth(m); setYear(y);
  };
  // ---- sample numbers from the prototype tenants
  const rows = app.tenants.map((t) => {
    const paid = t.status === 'paid' || t.status === 'notice';
    const p = t.payments[0];
    const allPaid = !yearMode && month < 9; // sample: months before October are fully paid
    const full = paid || allPaid;
    const day = (t.dueDate || '05').slice(0, 2);
    return { name: t.name, room: `${t.room}${t.bed}`, due: t.rent * (yearMode ? 7 : 1), paid: full ? t.rent * (yearMode ? 7 : 1) : (yearMode ? t.rent * 6 : 0), method: full ? (p ? p.method : 'UPI') : '', date: full ? (p ? p.date : `${day} ${MONTHS[month].slice(0, 3)}`) : '', dueOn: `${day} ${MONTHS[month].slice(0, 3)}` };
  });
  const expected = rows.reduce((a, r) => a + r.due, 0);
  const collected = rows.reduce((a, r) => a + r.paid, 0);
  const pending = expected - collected;
  const shownRent = rows.filter((r) => filter === 'all' || (filter === 'paid' ? r.paid >= r.due : r.paid < r.due));
  const MON_ROWS = yearMode ? ['Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct'].map((m, i) => ({ m, exp: 98000 + i * 6000, col: 98000 + i * 6000 - (i ? 2000 : 0) - (m === 'Oct' ? 19000 : 0) })) : [];
  const students = [
    ...app.tenants.map((t, i) => ({ name: t.name, room: `${t.room}${t.bed}`, mobile: t.mobile, deposit: t.deposit, hasId: i !== 2, joined: t.joined, org: t.org || t.office, state: t.status === 'notice' ? 'Leaving 20 Oct' : t.joined.includes('Oct') ? 'Joined' : 'Staying' })),
    { name: 'Nikhil Rao', room: '302C', mobile: '99122 33445', deposit: 5500, hasId: true, joined: '02 Jun 2026', org: 'Amazon', state: 'Left 30 Sep' },
  ];
  const inPeriod = (j) => (yearMode ? j.endsWith(String(year)) : j.includes(MONTHS[month].slice(0, 3)) && j.endsWith(String(year)));
  const stuShown = students.filter((s) => filter === 'all' || (filter === 'staying' ? !s.state.startsWith('Left') : filter === 'joined' ? inPeriod(s.joined) : s.state.startsWith('Left')));
  const kpi = (l, v, c) => (
    <View style={{ flex: 1, backgroundColor: '#fff', borderRadius: 12, borderWidth: 1, borderColor: C.line, padding: 10 }}>
      <T size={11} weight="400" color={C.muted} numberOfLines={1}>{l}</T>
      <T size={16} weight="800" color={c} numberOfLines={1}>{v}</T>
    </View>
  );
  const kind = (on, icon, text, onPress) => (
    <Pressable onPress={onPress} accessibilityRole="button" accessibilityState={{ selected: on }}
      style={{ flex: 1, flexDirection: 'row', alignItems: 'center', gap: 10, padding: 12, borderRadius: 12, borderWidth: 1.5, borderColor: on ? C.blue : C.line, backgroundColor: on ? C.blueSoft : '#fff' }}>
      <View style={{ width: 34, height: 34, borderRadius: 12, backgroundColor: on ? C.blue : C.blueSoft, alignItems: 'center', justifyContent: 'center' }}>
        <Icon name={icon} size={18} color={on ? '#fff' : C.blue} />
      </View>
      <T size={14} weight="600" style={{ flex: 1 }}>{text}</T>
    </Pressable>
  );
  const tag = (text, fg, bg) => <View style={{ backgroundColor: bg, borderRadius: 8, paddingHorizontal: 8, paddingVertical: 3 }}><T size={11} weight="600" color={fg}>{text}</T></View>;
  return (
    <Screen title="Reports" footer={<Btn icon="download-outline" title="Download report" style={{ backgroundColor: C.green, borderColor: C.green }} onPress={() => showSheet((close) => <DownloadSheet close={close} rent={rent} label={label} monthLabel={`${MONTHS[month]} ${year}`} year={year} yearMode={yearMode} />)} />}>
      <Row gap={8}>
        {kind(rent, 'cash-outline', 'Rent report', () => { setRent(true); setFilter('all'); })}
        {kind(!rent, 'people-outline', 'Students list', () => { setRent(false); setFilter('all'); })}
      </Row>
      <Gap h={10} />
      <Segmented options={[{ value: false, label: 'Month-wise' }, { value: true, label: 'Year-wise' }]} value={yearMode} onChange={setYearMode} />
      <View style={{ flexDirection: 'row', alignItems: 'center', backgroundColor: '#fff', borderRadius: 12, borderWidth: 1, borderColor: C.line, marginTop: 10 }}>
        <Pressable accessibilityLabel="Previous" onPress={() => step(-1)} style={{ padding: 12 }}><Icon name="chevron-back" color={C.blue} /></Pressable>
        <T size={16} weight="800" center style={{ flex: 1 }}>{label}</T>
        <Pressable accessibilityLabel="Next" onPress={() => step(1)} style={{ padding: 12 }}><Icon name="chevron-forward" color={C.blue} /></Pressable>
      </View>
      <Gap h={10} />
      {rent ? (
        <>
          <Row gap={8}>{kpi('Collected', rupees(collected), C.green)}{kpi('Expected', rupees(expected), C.ink)}{kpi('Pending', rupees(pending), C.red)}</Row>
          {yearMode ? (
            <Card padding={0} style={{ marginTop: 10 }}>
              <Row style={{ backgroundColor: '#FAFBFD', paddingHorizontal: 12, paddingVertical: 8 }}>
                {['Month', 'Expected', 'Collected', 'Pending'].map((h) => <T key={h} size={11} weight="600" color={C.muted} style={{ flex: 1 }}>{h}</T>)}
              </Row>
              {MON_ROWS.map((r) => (
                <Pressable key={r.m} onPress={() => { setYearMode(false); setMonth(MONTHS.findIndex((x) => x.startsWith(r.m))); }} style={{ flexDirection: 'row', paddingHorizontal: 12, paddingVertical: 10, borderTopWidth: 1, borderTopColor: '#EEF1F5' }}>
                  <T size={12.5} weight="600" style={{ flex: 1 }}>{r.m} {year}</T>
                  <T size={12.5} style={{ flex: 1 }}>{rupees(r.exp)}</T>
                  <T size={12.5} weight="800" color={C.green} style={{ flex: 1 }}>{rupees(r.col)}</T>
                  <T size={12.5} weight="800" color={r.exp - r.col ? C.red : C.muted} style={{ flex: 1 }}>{r.exp - r.col ? rupees(r.exp - r.col) : '—'}</T>
                </Pressable>
              ))}
            </Card>
          ) : null}
          {pending === 0 && rows.length ? (
            <View style={{ backgroundColor: '#E3F4E8', borderRadius: 12, padding: 10, marginTop: 10 }}>
              <T weight="600" color={C.green} center>✓ All rent collected for {label}</T>
            </View>
          ) : null}
          <Card padding={0} style={{ marginTop: 10, overflow: 'hidden' }}>
            <Row style={{ backgroundColor: C.blue, paddingHorizontal: 10, paddingVertical: 9 }}>
              {[['Room', 3], ['Name', 5], ['Rent', 4], ['Due', 3], ['Status', 4]].map(([h, f]) => <T key={h} size={11} weight="600" color="#fff" style={{ flex: f }}>{h}</T>)}
            </Row>
            {rows.map((r, i) => (
              <Row key={r.name} style={{ paddingHorizontal: 10, paddingVertical: 10, backgroundColor: i % 2 ? '#F8FAFC' : '#fff' }}>
                <T size={12.5} style={{ flex: 3 }}>{r.room}</T>
                <T size={12.5} style={{ flex: 5 }} numberOfLines={1}>{r.name.split(' ')[0]}</T>
                <T size={12.5} style={{ flex: 4 }}>{rupees(r.due)}</T>
                <T size={12.5} style={{ flex: 3 }}>{r.dueOn}</T>
                <View style={{ flex: 4, alignItems: 'flex-start' }}>{r.paid >= r.due ? tag('Paid', C.green, '#DDF3E8') : tag('Due', C.red, C.redSoft)}</View>
              </Row>
            ))}
            <Row style={{ paddingHorizontal: 10, paddingVertical: 10, backgroundColor: '#EEF1F6' }}>
              <T size={12.5} weight="600" style={{ flex: 8 }}>Total</T>
              <T size={12.5} weight="800" style={{ flex: 4 }}>{rupees(expected)}</T>
              <T size={12.5} weight="800" color={pending ? C.red : C.green} style={{ flex: 7 }}>{pending ? `${rupees(pending)} due` : 'All paid'}</T>
            </Row>
          </Card>
        </>
      ) : (
        <>
          <Row gap={8}>{kpi('Staying now', String(students.filter((s) => !s.state.startsWith('Left')).length), C.blue)}{kpi('Joined', String(students.filter((s) => inPeriod(s.joined)).length), C.green)}{kpi('Left', String(students.filter((s) => s.state.startsWith('Left')).length), C.ink)}</Row>
          <View style={{ marginTop: 12, marginBottom: 8 }}>
            <Chips options={['All', 'Staying', 'Joined', 'Left']} value={filter === 'all' ? 'All' : filter[0].toUpperCase() + filter.slice(1)} onChange={(v) => setFilter(v.toLowerCase())} />
          </View>
          {stuShown.map((s) => (
            <Card key={s.name} style={{ marginBottom: 8, flexDirection: 'row', alignItems: 'center', gap: 10, padding: 12 }}>
              <Avatar name={s.name} size={42} />
              <View style={{ flex: 1 }}>
                <T size={14} weight="600">{s.name} <T size={14} weight="400" color={C.muted}>· {s.room}</T></T>
                <T size={12.5} color={C.muted}>📞 {s.mobile} · Joined {s.joined.replace(' 2026', '')} · Deposit {rupees(s.deposit)}</T>
                {s.state.startsWith('Left') || s.state.startsWith('Leaving') ? <View style={{ marginTop: 4, alignSelf: 'flex-start' }}>{tag(s.state, s.state.startsWith('Left') ? C.muted : C.red, s.state.startsWith('Left') ? '#EEF1F5' : C.redSoft)}</View> : null}
              </View>
              {s.hasId ? tag('ID ✓', C.green, '#DDF3E8') : tag('ID ?', C.amber, C.amberSoft)}
            </Card>
          ))}
        </>
      )}
    </Screen>
  );
}

/** Download: the report and period on screen; only PDF or Excel is chosen. The file is saved on the phone and opens. */
function DownloadSheet({ close, rent, monthLabel, year, yearMode }) {
  const period = yearMode ? `${year}` : monthLabel;
  const go = (pdf) => {
    const name = `${rent ? 'Rent_Report' : 'Students_List'}_${yearMode ? year : monthLabel.slice(0, 3) + '_' + year}.${pdf ? 'pdf' : 'xlsx'}`;
    close();
    toast(`${name} saved on this phone · it opens in the real app`);
  };
  const row = (pdf, title, sub) => (
    <Pressable onPress={() => go(pdf)} style={{ flexDirection: 'row', alignItems: 'center', gap: 12, borderWidth: 1.4, borderColor: C.line, backgroundColor: '#fff', borderRadius: 12, padding: 12, marginBottom: 8 }}>
      <View style={{ width: 44, height: 44, borderRadius: 12, backgroundColor: pdf ? '#C0392B' : '#1D7A45', alignItems: 'center', justifyContent: 'center' }}>
        <T size={12.5} weight="600" color="#fff">{pdf ? 'PDF' : 'XLS'}</T>
      </View>
      <View style={{ flex: 1 }}>
        <T size={14} weight="600">{title}</T>
        <T size={12.5} color={C.muted}>{sub}</T>
      </View>
      <View style={{ width: 38, height: 38, borderRadius: 12, backgroundColor: '#DDF3E8', alignItems: 'center', justifyContent: 'center' }}>
        <Icon name="download-outline" color={C.green} size={20} />
      </View>
    </Pressable>
  );
  return (
    <View>
      <T size={20} weight="800">Download {rent ? 'Rent report' : 'Students list'}</T>
      <T size={12.5} color={C.muted} style={{ marginTop: 2, marginBottom: 12 }}>{period}</T>
      {row(true, 'PDF', 'To print or keep')}
      {row(false, 'Excel', 'To edit or for accountant')}
      <T size={12.5} color={C.muted} center style={{ marginTop: 4 }}>The file is saved on this phone and opens straight away.</T>
    </View>
  );
}

// ======================================================================
// App settings
// ======================================================================
export function AppSettings() {
  useApp();
  const s = app.settings;
  const set = (k) => (v) => {
    s[k] = v;
    actions.touch();
  };
  return (
    <Screen title="App settings">
      <SectionTitle>Notify me about</SectionTitle>
      <Card padding={0}>
        <SwitchRow title="Join requests" value={s.notifyJoins} onChange={set('notifyJoins')} />
        <SwitchRow title="Payments" value={s.notifyPayments} onChange={set('notifyPayments')} />
        <SwitchRow title="Complaints" value={s.notifyComplaints} onChange={set('notifyComplaints')} />
        <SwitchRow title="Daily summary at 9 PM" value={s.dailySummary} onChange={set('dailySummary')} last />
      </Card>
      <SectionTitle>Messages to students</SectionTitle>
      <Card padding={0}>
        <SwitchRow title="App notification" sub="Free" value={s.msgPush} onChange={set('msgPush')} />
        <SwitchRow title="SMS" sub="About ₹0.15 per SMS" value={s.msgSms} onChange={set('msgSms')} />
        <SwitchRow title="WhatsApp" sub="About ₹0.12 per message" value={s.msgWhatsapp} onChange={set('msgWhatsapp')} last />
      </Card>
      <SectionTitle>Security</SectionTitle>
      <Card padding={0}>
        <SwitchRow title="App lock (fingerprint / Face ID)" value={s.appLock} onChange={set('appLock')} />
        <MenuRow icon="lock-closed-outline" title="Change password" onPress={() => toast('Change password form')} />
        <MenuRow icon="phone-portrait-outline" title="Logged-in devices" sub="This phone · Chrome on Windows" onPress={() => toast('Logged out of other devices.')} right={<T size={12.5} weight="600" color={C.blue}>Log out others</T>} />
      </Card>
      <SectionTitle>Appearance</SectionTitle>
      <Card>
        <T weight="600" style={{ marginBottom: 8 }}>Theme</T>
        <Chips options={['Light', 'Dark', 'System']} value={s.theme} onChange={set('theme')} />
        <T weight="600" style={{ marginTop: 14, marginBottom: 8 }}>Language</T>
        <Chips options={LANGUAGES} value={app.language} onChange={(v) => { app.language = v; actions.touch(); }} />
      </Card>
      <T size={12.5} color={C.muted} center style={{ marginTop: 16 }}>Version 0.1.0 (prototype)</T>
    </Screen>
  );
}

// ======================================================================
// Delete account
// ======================================================================
export function DeleteAccount() {
  const nav = useNav();
  const [reason, setReason] = useState('Not using it');
  const [typed, setTyped] = useState('');
  const [otp, setOtp] = useState('');
  const [sent, setSent] = useState(false);
  const ready = typed === 'DELETE' && otp === '123456';
  return (
    <Screen
      title="Delete account"
      footer={
        <Btn
          variant="danger"
          disabled={!ready}
          title="Delete my account"
          onPress={() => {
            actions.logout();
            nav.popToTop();
            toast('Account will be deleted in 7 days. Log in before then to cancel.');
          }}
        />
      }
    >
      <Card bg={C.redSoft}>
        <T weight="600" color={C.red} style={{ marginBottom: 8 }}>This will delete</T>
        <T style={{ lineHeight: 22 }}>• Your owner account and all your hostels{'\n'}• Rooms, tenants, ID copies and photos{'\n'}• Staff logins{'\n\n'}Payment records are kept only as long as the law requires.</T>
      </Card>
      <Gap />
      <Btn variant="outline" icon="download-outline" title="Download my data first" onPress={() => toast('Download link sent by SMS.')} />
      <SectionTitle>Why are you leaving?</SectionTitle>
      <Chips options={['Not using it', 'Closed my hostel', 'Too costly', 'Missing features', 'Other']} value={reason} onChange={setReason} />
      <SectionTitle>Confirm</SectionTitle>
      <Field label="Type DELETE" placeholder="DELETE" value={typed} onChangeText={setTyped} />
      <Row gap={10} align="flex-start">
        <View style={{ flex: 1 }}>
          <Field placeholder="OTP (demo 123456)" keyboardType="number-pad" maxLength={6} editable={sent} value={otp} onChangeText={setOtp} />
        </View>
        <Btn small variant="tonal" title={sent ? 'Resend' : 'Send OTP'} style={{ marginTop: 5 }} onPress={() => { setSent(true); toast(`OTP sent to +91 ${app.ownerMobile}`); }} />
      </Row>
      <T color={C.muted}>You have 7 days to cancel by logging in again.</T>
    </Screen>
  );
}

// ======================================================================
// Rooms → Book: Share with student (QR for one bed, held 15 minutes)
// ======================================================================
/** A QR-looking grid drawn with Views (Expo Go has no QR package here). */
function BedQr({ seed = 7, size = 200 }) {
  const n = 25;
  const cell = size / n;
  let x = seed * 9301 + 49297;
  const rnd = () => {
    x = (x * 9301 + 49297) % 233280;
    return x / 233280;
  };
  const finder = (r, c) => (r < 7 && c < 7) || (r < 7 && c >= n - 7) || (r >= n - 7 && c < 7);
  const finderOn = (r, c) => {
    const rr = r >= n - 7 ? r - (n - 7) : r;
    const cc = c >= n - 7 ? c - (n - 7) : c;
    return rr === 0 || rr === 6 || cc === 0 || cc === 6 || (rr >= 2 && rr <= 4 && cc >= 2 && cc <= 4);
  };
  const rows = [];
  for (let r = 0; r < n; r++) {
    const cells = [];
    for (let c = 0; c < n; c++) {
      const on = finder(r, c) ? finderOn(r, c) : rnd() < 0.47;
      cells.push(<View key={c} style={{ width: cell, height: cell, backgroundColor: on ? '#14213D' : '#fff' }} />);
    }
    rows.push(<View key={r} style={{ flexDirection: 'row' }}>{cells}</View>);
  }
  return <View accessibilityLabel="QR code for the student to scan" style={{ backgroundColor: '#fff', padding: 8, borderRadius: 8 }}>{rows}</View>;
}

export function ShareBed({ params }) {
  const nav = useNav();
  useApp();
  const r = app.rooms.find((x) => x.number === params.room);
  const i = params.bedIndex;
  const [hold, setHold] = useState(() => actions.ownerHoldBed(params.room, i));
  const [, tick] = useState(0);
  React.useEffect(() => {
    const id = setInterval(() => tick((x) => x + 1), 1000);
    return () => clearInterval(id);
  }, []);
  if (!r || !hold) return <Screen title="Share with student"><T>Bed not found.</T></Screen>;
  const left = Math.max(0, Math.floor((hold.until - Date.now()) / 1000));
  const expired = left === 0;
  const mmss = `${String(Math.floor(left / 60)).padStart(2, '0')}:${String(left % 60).padStart(2, '0')}`;
  const bed = bedLabel(i);
  const total = r.rent + r.deposit;
  const h = hostel();
  const link = `myhostel.app/j/${(h.name || 'HOSTEL').replace(/[^A-Za-z]/g, '').slice(0, 6).toUpperCase()}?bed=${r.number}${bed}`;
  const row = (label, value, strong) => (
    <Row style={{ marginTop: 7 }}>
      <T weight={strong ? '800' : '600'} color={strong ? C.ink : C.muted} style={{ flex: 1 }}>{label}</T>
      <T size={strong ? 20 : 14} weight="800" color={strong ? C.green : C.ink}>{value}</T>
    </Row>
  );
  return (
    <Screen title="Share with student">
      <Card border={C.line}>
        <Row gap={12}>
          <View style={{ width: 50, height: 50, borderRadius: 12, backgroundColor: '#DDF3E8', alignItems: 'center', justifyContent: 'center' }}>
            <T size={14} weight="600" color={C.green}>{r.number}</T>
            <T size={12.5} weight="600" color={C.green}>{bed}</T>
          </View>
          <View style={{ flex: 1 }}>
            <T size={16} weight="800">Room {r.number} · Bed {bed}</T>
            <T size={12.5} color={C.muted}>{floorName(r.floor)} · {r.sharing} sharing{r.features[0] ? ` · ${r.features.slice(0, 2).join(' · ')}` : ''}</T>
          </View>
        </Row>
        {row('Monthly rent', rupees(r.rent))}
        {row('Security deposit', rupees(r.deposit))}
        <Divider />
        {row('To pay now', rupees(total), true)}
      </Card>
      <Gap h={14} />
      <View style={{ alignItems: 'center', backgroundColor: '#F7FCF9', borderWidth: 1.5, borderColor: '#CDEEDC', borderStyle: 'dashed', borderRadius: 16, padding: 16 }}>
        <View style={{ opacity: expired ? 0.15 : 1 }}><BedQr seed={r.number.charCodeAt(0) + i} size={190} /></View>
        <T size={16} weight="800" center style={{ marginTop: 10 }}>{expired ? 'Hold ended' : 'Ask the student to scan'}</T>
        <T size={12.5} color={C.muted} center style={{ marginTop: 4 }}>They fill details, accept house rules and pay. You approve.</T>
        {expired ? (
          <Btn small title="Hold again" icon="refresh" style={{ marginTop: 10 }} onPress={() => { app.qrHold = null; setHold(actions.ownerHoldBed(params.room, i)); }} />
        ) : (
          <View style={{ flexDirection: 'row', alignItems: 'center', gap: 5, marginTop: 10, backgroundColor: C.amberSoft, borderRadius: 99, paddingHorizontal: 12, paddingVertical: 6 }}>
            <Icon name="timer-outline" size={16} color={C.amber} />
            <T size={12.5} weight="600" color={C.amber}>Bed held for you · {mmss}</T>
          </View>
        )}
      </View>
      <Row gap={10} style={{ marginTop: 14 }}>
        <Btn style={{ flex: 1, backgroundColor: '#1B7A43', borderColor: '#1B7A43' }} icon="logo-whatsapp" title="WhatsApp link" disabled={expired}
          onPress={() => toast(`Would open WhatsApp with: Room ${r.number} · Bed ${bed} is held for you. Pay ${rupees(total)} here: ${link}`)} />
        <Btn style={{ flex: 1 }} variant="outline" icon="copy-outline" title="Copy link" disabled={expired} onPress={() => toast('Link copied')} />
      </Row>
      <Gap />
      <Btn variant="tonal" icon="qr-code-outline" title="Prototype: open as student (scan QR)" disabled={expired}
        onPress={() => { actions.startBookedFlow(r.number, i); nav.push('GetApp'); }} />
      <Btn variant="text" title="Cancel booking" onPress={() => { actions.ownerReleaseBed(r.number, i); nav.pop(); }} />
    </Screen>
  );
}

// ======================================================================
// Hostel settings → Rooms & beds (counts, Add room, scrollable room list)
// ======================================================================
/** Wi-Fi for students: whole hostel or one floor. Students see only their floor + whole-hostel networks. */
function WifiBlock() {
  useApp();
  const h = hostel();
  const list = h.wifi || (h.wifi = []);
  const edit = (i) => {
    const cur = i >= 0 ? list[i] : { floor: null, name: '', password: '' };
    const floors = ['Whole hostel', ...[...new Set(app.rooms.map((r) => r.floor))].sort((a, b) => a - b).map((f) => `Floor ${f}`)];
    showSheet((close) => <WifiSheet close={close} cur={cur} floors={floors} onSave={(w) => {
      if (i >= 0) list[i] = w; else list.push(w);
      actions.touch();
      toast('Wi-Fi saved');
    }} onDelete={i >= 0 ? () => { list.splice(i, 1); actions.touch(); toast('Wi-Fi removed'); } : null} />);
  };
  return (
    <>
      <SectionTitle right={<Btn small variant="text" icon="add" title="Add" onPress={() => edit(-1)} />}>Wi-Fi for students</SectionTitle>
      <Card padding={0}>
        {list.length === 0 ? <T color={C.muted} style={{ padding: 14 }}>No Wi-Fi added. Students see it on their My room tab.</T> : null}
        {list.map((w, i) => (
          <Pressable key={i} onPress={() => edit(i)} style={{ flexDirection: 'row', alignItems: 'center', gap: 10, padding: 14, borderTopWidth: i ? 1 : 0, borderTopColor: C.line }}>
            <IconBox name="wifi" />
            <View style={{ flex: 1 }}>
              <T weight="600">{w.name}</T>
              <T size={12.5} color={C.muted}>{w.floor == null ? 'Whole hostel' : `Floor ${w.floor}`} · {w.password ? '•••••••' : 'open'}</T>
            </View>
            <Icon name="create-outline" color={C.muted} />
          </Pressable>
        ))}
      </Card>
    </>
  );
}

function WifiSheet({ close, cur, floors, onSave, onDelete }) {
  const [where, setWhere] = useState(cur.floor == null ? 'Whole hostel' : `Floor ${cur.floor}`);
  const [name, setName] = useState(cur.name);
  const [pw, setPw] = useState(cur.password);
  return (
    <View>
      <T size={20} weight="800">{cur.name ? 'Edit Wi-Fi' : 'Add Wi-Fi'}</T>
      <Gap />
      <T size={12.5} weight="400" color={C.muted}>WHERE</T>
      <Chips options={floors} value={where} onChange={setWhere} />
      <Gap />
      <Field label="Wi-Fi name" value={name} onChangeText={setName} placeholder="SunrisePG" />
      <Field label="Password" value={pw} onChangeText={setPw} placeholder="optional" />
      <Btn title="Save" disabled={name.trim().length < 1} onPress={() => { onSave({ floor: where === 'Whole hostel' ? null : Number(where.replace('Floor ', '')), name: name.trim(), password: pw.trim() }); close(); }} />
      {onDelete ? <Btn variant="text" title="Delete" onPress={() => { onDelete(); close(); }} /> : null}
    </View>
  );
}

/** Hostel settings → Rooms & beds: counts, then "Change room details" (switch on → type a room number
 *  → change its number, sharing and rent → Save). */
function RoomsBlock() {
  useApp();
  const total = totalBeds();
  const occupied = countBeds('filled');
  const free = countBeds('vacant');
  const floors = [...new Set(app.rooms.map((r) => r.floor))];
  const upper = floors.filter((f) => f > 0).length;
  const stat = (v, label, color) => (
    <View style={{ flex: 1, alignItems: 'center' }}>
      <T size={20} weight="800" color={color}>{v}</T>
      <T size={11} weight="400" color={C.muted} numberOfLines={1}>{label}</T>
    </View>
  );
  const div = <View style={{ width: 1, height: 28, backgroundColor: C.line }} />;
  return (
    <View>
      <Row style={{ marginTop: 4, marginBottom: 8 }}>
        <T size={16} weight="800" style={{ flex: 1 }}>Rooms & beds</T>
        <T size={12.5} color={C.muted}>{app.rooms.length} rooms</T>
      </Row>
      <View style={{ flexDirection: 'row', alignItems: 'center', backgroundColor: '#fff', borderRadius: 16, borderWidth: 1, borderColor: C.line, paddingVertical: 12, paddingHorizontal: 4 }}>
        {stat(total, 'Total beds', C.ink)}
        {div}
        {stat(occupied, 'Occupied', C.blue)}
        {div}
        {stat(free, 'Available', C.green)}
        {div}
        {stat(floors.includes(0) ? `${upper}+G` : upper, 'Floors', C.ink)}
      </View>
    </View>
  );
}

function ChangeRoomBody({ onSaved, ask, tell }) {
  useApp();
  const h = hostel();
  const [q, setQ] = useState('');
  const [sharing, setSharing] = useState(null); // new sharing picked (null = unchanged)
  const room = app.rooms.find((r) => r.number.toLowerCase() === q.trim().toLowerCase());
  const staying = room ? room.beds.filter((b) => b !== 'vacant').length : 0;
  const newSharing = sharing || (room ? room.sharing : null);
  const price = (n) => ((h.sharingPrices || []).find((p) => p.sharing === n) || {}).rent;
  const save = async () => {
    if (!room) return toast('Type a room number first.');
    if (newSharing < staying) return toast(`${staying} people stay here. Sharing can't be less than ${staying}.`);
    const rent = price(newSharing);
    if (!rent) return toast(`Add a price for ${newSharing} sharing in "Sharing + price" first.`);
    const old = room.sharing;
    if (staying > 0) {
      const ok = await ask(`Room ${room.number} · ${old} sharing → ${newSharing} sharing`,
        `${staying} students stay in this room. Their fee becomes ${rupees(rent)} (was ${rupees(room.rent)}) from their next fee date. They all get a message.`);
      if (!ok) return undefined;
      if (app.stay.room === room.number) {
        tell({ kind: 'sharing', title: `Your room becomes ${newSharing} sharing`, body: `Room ${room.number} · from ${app.stay.dueDate} your fee is ${rupees(rent)} a month (was ${rupees(app.stay.rent)}).` });
        app.stay.rent = rent;
        app.stay.sharing = newSharing;
      }
      app.tenants.forEach((t) => { if (t.room === room.number) t.rent = rent; });
    }
    const beds = room.beds.filter((b) => b !== 'vacant');
    while (beds.length < newSharing) beds.push('vacant');
    Object.assign(room, { sharing: newSharing, rent, beds });
    setSharing(null);
    setQ(''); // back to the empty look, same as when it was opened
    actions.touch();
    onSaved(`Room ${room.number} · ${old} sharing to ${newSharing} sharing`);
  };
  const box = (label, text, onPress) => (
    <View style={{ flex: 1 }}>
      <T size={11} color={C.muted} style={{ marginBottom: 3, marginLeft: 2 }}>{label}</T>
      {onPress ? (
        <Row><PenBox text={text} onPress={onPress} muted={!room} /></Row>
      ) : (
        <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', borderWidth: 1.2, borderColor: C.line, borderRadius: 12, paddingHorizontal: 12, minHeight: 46, backgroundColor: C.ground }}>
          <T weight="400" size={14} color={C.muted}>{text}</T>
          <Icon name="lock-closed-outline" size={15} color={C.muted} />
        </View>
      )}
    </View>
  );
  return (
        <View>
          <View style={{ flexDirection: 'row', alignItems: 'center', gap: 8, borderWidth: 1.4, borderColor: C.blue, borderRadius: 12, paddingHorizontal: 12, minHeight: 48 }}>
            <Icon name="search" size={18} color={C.muted} />
            <TextInput value={q} onChangeText={(v) => { setQ(v); setSharing(null); }} placeholder="Type room number, e.g. 204" placeholderTextColor="#9AA7B8" autoCapitalize="characters" maxLength={8}
              style={{ flex: 1, fontSize: 16, ...appFont('800'), color: C.ink, paddingVertical: 10 }} />
          </View>
          {q.trim() && !room ? <T color={C.red} size={12.5} style={{ marginTop: 6 }}>No room "{q.trim()}". Check the number.</T> : null}
          <Row gap={8} align="flex-start" style={{ marginTop: 10 }}>
            {box('Room no.', room ? room.number : '—')}
            {box('Sharing', newSharing ? `${newSharing} sharing` : '—', () => (room
              ? showSheet((close) => <SharingSheet close={close} current={newSharing} taken={[]} onSave={(n) => setSharing(n)} />)
              : toast('Type a room number first.')))}
          </Row>
          {room ? (
            <T size={12.5} color={C.muted} style={{ marginTop: 8 }}>
              {floorName(room.floor)} · {staying} staying · rent {price(newSharing) ? rupees(price(newSharing)) : 'not set'} (from Sharing + price)
            </T>
          ) : null}
          <Btn title="Save room" disabled={!room || newSharing === room.sharing} style={{ marginTop: 10 }} onPress={save} />
        </View>
  );
}

/** Rent day: two large option cards; "Fixed day" has a small number box (1–28). */
function RentDayCard({ h, set }) {
  const [txt, setTxt] = useState(String(h.fixedRentDay || 5));
  const fixed = !h.rentSameAsJoining;
  const option = (same, title, sub, right) => {
    const on = h.rentSameAsJoining === same;
    return (
      <Pressable onPress={() => set('rentSameAsJoining')(same)} accessibilityRole="radio" accessibilityState={{ selected: on }}
        style={{ flexDirection: 'row', alignItems: 'center', gap: 10, borderWidth: 1.5, borderColor: on ? C.blue : C.line, backgroundColor: on ? C.blueSoft : '#fff', borderRadius: 12, padding: 12, marginBottom: 8 }}>
        <Icon name={on ? 'radio-button-on' : 'radio-button-off'} color={C.blue} size={22} />
        <View style={{ flex: 1 }}>
          <T size={16} weight="600">{title}</T>
          <T size={12.5} color={C.muted}>{sub}</T>
        </View>
        {right}
      </Pressable>
    );
  };
  return (
    <Card padding={12}>
      {option(true, 'Same as joining date', 'Joined on 12th → pays every 12th')}
      {option(false, 'Fixed day for everyone', fixed ? `Everyone pays on day ${h.fixedRentDay} of the month` : 'All tenants pay on the same day', (
        <View style={{ width: 64 }}>
          <TextInput value={fixed ? txt : '–'} editable={fixed} keyboardType="number-pad" maxLength={2} accessibilityLabel="Rent day of the month"
            onChangeText={(v) => { const d = v.replace(/\D/g, ''); setTxt(d); const n = parseInt(d, 10); if (n >= 1 && n <= 28) set('fixedRentDay')(n); }}
            style={{ height: 52, borderRadius: 12, borderWidth: 1.6, borderColor: fixed ? C.blue : C.line, backgroundColor: fixed ? '#fff' : '#F5F7FA', textAlign: 'center', fontSize: 22, ...appFont('800'), color: fixed ? C.blue : '#A0ABB8' }} />
          <T size={11} color={C.muted} center>day</T>
        </View>
      ))}
      {fixed && !(parseInt(txt, 10) >= 1 && parseInt(txt, 10) <= 28) ? <T size={12.5} color={C.red}>Enter a day from 1 to 28.</T> : null}
      <View style={{ backgroundColor: C.blueSoft, borderRadius: 12, paddingHorizontal: 10, paddingVertical: 8, marginTop: 4 }}>
        <T size={12.5} weight="600" color={C.blue}>Tenants get an SMS when the rent day changes.</T>
      </View>
    </Card>
  );
}



// ======================================================================
// Phase 1: rooms entered by tenants
// (students type floor, room, sharing, price and deposit in "Your details";
//  the owner checks and corrects them here — students are not told about corrections)
// ======================================================================
const statusPill = (st) =>
  st === 'confirmed' ? <Pill text="Confirmed" tone="green" /> : st === 'fix' ? <Pill text="Fix" tone="amber" icon="alert-circle-outline" /> : <Pill text="OK" tone="blue" />;

/** Card shown in Hostel settings → Rooms & beds that opens "Rooms from tenants". */
function TenantRoomsLink() {
  const nav = useNav();
  useApp();
  const rows = roomTable();
  if (!hostel().tenantRoomEntry && !rows.length) return null;
  const toFix = rows.filter((r) => r.status === 'fix').length;
  const pending = rows.filter((r) => r.status !== 'confirmed').length;
  return (
    <Card onPress={() => nav.push('TenantRooms')} padding={12} style={{ marginTop: 10 }} border={toFix ? C.amber + '88' : C.line}>
      <Row gap={10}>
        <IconBox name="people-outline" size={36} color={toFix ? C.amber : C.blue} />
        <View style={{ flex: 1 }}>
          <T weight="600">Rooms from tenants</T>
          <T size={12.5} color={C.muted}>{rows.length} rooms entered · {pending ? `${pending} to confirm` : 'all confirmed'}{toFix ? ` · ${toFix} to fix` : ''}</T>
        </View>
        <Icon name="chevron-forward" size={20} color={C.blue} />
      </Row>
    </Card>
  );
}

/** Inline editor for one room: pick the correct sharing, price and deposit, then Save. */
function FixRow({ r, close }) {
  const [sharing, setSharing] = useState(r.sharing);
  const [price, setPrice] = useState(String(r.price));
  const [deposit, setDeposit] = useState(String(r.deposit || ''));
  const [floor, setFloor] = useState(String(r.floor));
  const save = () => {
    const p = parseInt(price, 10);
    if (!p) return toast('Enter the monthly price.');
    actions.fixRoom(r.room, { floor, sharing, price: p, deposit: parseInt(deposit, 10) || 0 });
    toast(`Room ${r.room} confirmed.`);
    close();
  };
  return (
    <View style={{ backgroundColor: C.amberSoft, padding: 12, borderBottomWidth: 1, borderBottomColor: '#EEF1F5' }}>
      <T size={12.5} weight="600" color={C.amber}>What tenants entered</T>
      {r.entries.map((e) => (
        <T key={e.id} size={12.5} color={C.ink} style={{ marginTop: 2 }}>
          {e.name}: {e.sharing} sharing · {rupees(e.price)} · {e.deposit ? rupees(e.deposit) : 'no deposit'}
        </T>
      ))}
      <T size={12.5} weight="600" style={{ marginTop: 10, marginBottom: 6 }}>Correct details</T>
      <T size={12.5} color={C.muted} style={{ marginBottom: 4 }}>Floor</T>
      <FloorPicker value={floor} onChange={setFloor} allowGround={isGroundRoom(r.room)} onlyGround={isGroundRoom(r.room)} />
      <T size={12.5} color={C.muted} style={{ marginTop: 8, marginBottom: 4 }}>Sharing</T>
      <SharingPicker value={sharing} onChange={setSharing} />
      <Row gap={8} style={{ marginTop: 8 }}>
        <View style={{ flex: 1 }}><Field label="Monthly price" prefix="₹" keyboardType="number-pad" value={price} onChangeText={(v) => setPrice(v.replace(/\D/g, ''))} maxLength={6} /></View>
        <View style={{ flex: 1 }}><Field label="Deposit" prefix="₹" keyboardType="number-pad" value={deposit} placeholder="None" onChangeText={(v) => setDeposit(v.replace(/\D/g, ''))} maxLength={6} /></View>
      </Row>
      <Row gap={8}>
        <Btn small variant="outline" title="Cancel" onPress={close} style={{ flex: 1 }} />
        <Btn small title={`Save room ${r.room}`} onPress={save} style={{ flex: 1 }} />
      </Row>
    </View>
  );
}

/** More → Rooms from tenants (also Hostel settings → Rooms & beds): table grouped by floor. */
export function TenantRooms() {
  const nav = useNav();
  useApp();
  const [open, setOpen] = useState(null);
  const rows = roomTable();
  const floors = [...new Set(rows.map((r) => String(r.floor)))].sort();
  const confirmed = rows.filter((r) => r.status === 'confirmed').length;
  const toFix = rows.filter((r) => r.status === 'fix').length;
  const okCount = rows.filter((r) => r.status === 'ok').length;
  const tenants = rows.reduce((n, r) => n + r.count, 0);
  const cell = (txt, w, opts = {}) => (
    <View style={{ width: w, paddingRight: 4 }}>
      <T size={12.5} weight={opts.bold ? '800' : '600'} color={opts.color || C.ink} numberOfLines={2}>{txt}</T>
    </View>
  );
  if (!rows.length) {
    return (
      <Screen title="Rooms from tenants">
        <EmptyState icon="bed-outline" title="No rooms entered yet" text="When tenants scan your join QR, the floor, room, sharing and price they type show up here for you to check."
          action={<Btn small icon="qr-code-outline" title="Share join QR" onPress={() => nav.push('InviteStudents')} />} />
      </Screen>
    );
  }
  return (
    <Screen
      title="Rooms from tenants"
      footer={okCount ? (
        <Btn icon="checkmark-done" title={`Confirm all correct rooms (${okCount})`} onPress={() => { const n = actions.confirmCorrectRooms(); toast(`${n} ${n === 1 ? 'room' : 'rooms'} confirmed and added to Rooms & beds.`); }} />
      ) : null}
    >
      <T color={C.muted}>{floors.length} {floors.length === 1 ? 'floor' : 'floors'} · {rows.length} rooms · {tenants} tenants entered</T>
      <Row gap={6} style={{ marginTop: 8, flexWrap: 'wrap' }}>
        <Pill text={`${confirmed} confirmed`} tone="green" />
        {okCount ? <Pill text={`${okCount} to confirm`} tone="blue" /> : null}
        {toFix ? <Pill text={`${toFix} to fix`} tone="amber" /> : null}
      </Row>
      <Card padding={0} style={{ marginTop: 12, overflow: 'hidden' }}>
        <Row gap={0} style={{ paddingHorizontal: 12, paddingVertical: 8, borderBottomWidth: 1, borderBottomColor: C.line }}>
          {cell('Room', '17%', { color: C.muted })}
          {cell('Sharing', '20%', { color: C.muted })}
          {cell('Price', '27%', { color: C.muted })}
          {cell('Filled', '14%', { color: C.muted })}
          <View style={{ flex: 1 }} />
        </Row>
        {floors.map((f) => (
          <View key={f}>
            <View style={{ backgroundColor: '#FAFBFD', paddingHorizontal: 12, paddingVertical: 6 }}>
              <T size={11} weight="600" color={C.muted} style={{ letterSpacing: 0.5 }}>{floorLabel(f).toUpperCase()}</T>
            </View>
            {rows.filter((r) => String(r.floor) === f).map((r) => {
              const clashS = r.status === 'fix' && r.sharings.length > 1;
              const clashP = r.status === 'fix' && r.prices.length > 1;
              return (
                <View key={r.room}>
                  <Pressable
                    onPress={() => (app.isStaff ? toast('Only the owner can change rooms.') : setOpen(open === r.room ? null : r.room))}
                    style={{ flexDirection: 'row', alignItems: 'center', paddingHorizontal: 12, paddingVertical: 10, borderBottomWidth: 1, borderBottomColor: '#EEF1F5' }}
                  >
                    {cell(r.room, '17%', { bold: true })}
                    {cell(clashS ? r.sharings.join(' / ') + '?' : String(r.sharing), '20%', { color: clashS ? C.amber : C.ink })}
                    {cell(clashP ? r.prices.map((p) => rupees(p)).join(' / ') + '?' : rupees(r.price), '27%', { color: clashP ? C.amber : C.ink })}
                    {cell(`${Math.min(r.count, r.sharing)}/${r.sharing}`, '14%')}
                    <View style={{ flex: 1, alignItems: 'flex-end' }}>{statusPill(r.status)}</View>
                  </Pressable>
                  {open === r.room ? <FixRow r={r} close={() => setOpen(null)} /> : null}
                </View>
              );
            })}
          </View>
        ))}
      </Card>
      <T size={12.5} color={C.muted} style={{ marginTop: 8, lineHeight: 18 }}>
        Tap any room to correct it. Tenants are not told about your corrections. Confirmed rooms are added to Rooms & beds, so new students can pick them.
      </T>
      <Gap h={8} />
      <Btn variant="outline" icon="pricetags-outline" title="Price by sharing" onPress={() => nav.push('SharingPrices')} />
      <Btn variant="text" icon="download-outline" title="Download table (Excel)" onPress={() => toast('Prototype: the Excel file downloads here.')} />
    </Screen>
  );
}

function SharingPriceSheet({ row, close }) {
  const [price, setPrice] = useState(String(row.prices[0] || ''));
  const [deposit, setDeposit] = useState(String(row.deposits[0] || ''));
  return (
    <View style={{ gap: 4 }}>
      <T size={20} weight="800">{row.sharing} sharing · {row.rooms} {row.rooms === 1 ? 'room' : 'rooms'}</T>
      <T color={C.muted} style={{ marginBottom: 10 }}>Sets the price and deposit for every {row.sharing}-sharing room.</T>
      <Field label="Price per bed / month" prefix="₹" keyboardType="number-pad" value={price} onChangeText={(v) => setPrice(v.replace(/\D/g, ''))} maxLength={6} />
      <Field label="Deposit" prefix="₹" keyboardType="number-pad" value={deposit} placeholder="None" onChangeText={(v) => setDeposit(v.replace(/\D/g, ''))} maxLength={6} />
      <Btn title="Save" onPress={() => {
        const p = parseInt(price, 10);
        if (!p) return toast('Enter the price.');
        actions.setSharingPrice(row.sharing, p, parseInt(deposit, 10) || 0);
        close();
        toast(`${row.sharing} sharing price saved.`);
      }} />
    </View>
  );
}

/** More → Hostel settings → Price by sharing (built from what tenants entered). */
export function SharingPrices() {
  const nav = useNav();
  useApp();
  const h = hostel();
  const rows = sharingPrices();
  const set = (k) => (v) => { h[k] = v; actions.touch(); };
  const edit = (row) => (app.isStaff ? toast('Only the owner can change prices.') : showSheet((close) => <SharingPriceSheet row={row} close={close} />));
  const col = (txt, w, opts = {}) => (
    <View style={{ width: w }}><T size={12.5} weight={opts.bold ? '800' : '600'} color={opts.color || C.ink}>{txt}</T></View>
  );
  return (
    <Screen title="Price by sharing">
      <T color={C.muted}>Built from what tenants entered. Tap a row to change it.</T>
      {rows.length ? (
        <Card padding={0} style={{ marginTop: 12, overflow: 'hidden' }}>
          <Row gap={0} style={{ paddingHorizontal: 12, paddingVertical: 8, borderBottomWidth: 1, borderBottomColor: C.line }}>
            {col('Sharing', '28%', { color: C.muted })}
            {col('Rooms', '16%', { color: C.muted })}
            {col('Price / bed', '28%', { color: C.muted })}
            {col('Deposit', '28%', { color: C.muted })}
          </Row>
          {rows.map((r) => (
            <Pressable key={r.sharing} onPress={() => edit(r)} style={{ flexDirection: 'row', alignItems: 'center', paddingHorizontal: 12, paddingVertical: 12, borderBottomWidth: 1, borderBottomColor: '#EEF1F5' }}>
              {col(`${r.sharing} sharing`, '28%', { bold: true })}
              {col(String(r.rooms), '16%')}
              <View style={{ width: '28%' }}>{r.prices.length > 1 ? <Pill text={`${r.prices.length} prices`} tone="amber" /> : <T size={12.5} weight="800">{rupees(r.prices[0])}</T>}</View>
              <View style={{ width: '28%' }}>{r.deposits.length > 1 ? <Pill text={`${r.deposits.length} deposits`} tone="amber" /> : <T size={12.5} weight="800">{r.deposits[0] ? rupees(r.deposits[0]) : 'None'}</T>}</View>
            </Pressable>
          ))}
        </Card>
      ) : (
        <EmptyState icon="pricetags-outline" title="No prices yet" text="Prices appear here once tenants enter their room details." />
      )}
      <Gap h={14} />
      <Card padding={0}>
        <SwitchRow title="Use these prices for new joiners" sub="New students see these prices when booking a free bed." value={!!h.useTenantPrices} onChange={set('useTenantPrices')} />
        <SwitchRow title="Tenants enter room details" sub="Phase 1 only. Turn off once all rooms are set." value={!!h.tenantRoomEntry} onChange={set('tenantRoomEntry')} last />
      </Card>
      <Gap h={10} />
      <Btn variant="outline" icon="people-outline" title="Rooms from tenants" onPress={() => nav.push('TenantRooms')} />
    </Screen>
  );
}
