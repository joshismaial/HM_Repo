// Student-first onboarding (prototype, 1 Nov 2026).
// Students register BEFORE the owner is on the app, using the owner's mobile number.
// Flow: student joins (owner number typed twice) -> OTP -> room details -> joining + fee date -> waiting
//       -> owner signs up and confirms the waiting list -> every student gets a message (SMS) at once
//       -> students complete the rest (photo, Aadhaar, parent, reference) -> owner verifies and adds the tenant.
// Backend rule shown here: when the count of students for an owner number first reaches 25, 50 and 100,
// the backend sends the owner ONE fixed SMS (nobody else can trigger it). All data is sample data in memory.
import React, { useState } from 'react';
import { Linking, Pressable, View } from 'react-native';
import { useNav } from '../nav';
import { toast } from '../overlay';
import { DEMO_OTP, app, fmtDate, notify, ordinal, rupees, useApp } from '../state';
import {
  Btn, C, Card, CheckRow, DateStepper, Field, Gap, Icon, IconBox, Pill, Row, Screen, SectionTitle, SharingPicker, T, UploadBox, Avatar,
} from '../ui';

// ---------------------------------------------------------------- data
const MILESTONES = [25, 50, 100];
const RETENTION_DAYS = 90;
const OWNER_SMS = (n) => `${n} students from your hostel are using My Hostel. Log in to see all student details and fee alerts: myhostel.app/o – MYHSTL`;
const STUDENT_SMS = 'My Hostel: Your hostel owner has joined. Please complete your details: photo, Aadhaar, parent and reference contacts. Open: myhostel.app/c/x7Kq2';

const SAMPLE_NAMES = ['Arjun Reddy', 'Kiran Naidu', 'Sneha Patel', 'Mohammed Faiz', 'Vikram Singh', 'Sai Teja', 'Pranav Joshi', 'Ananya Rao', 'Harsha Vardhan', 'Divya Menon', 'Nikhil Kumar', 'Pooja Sharma', 'Ravi Teja', 'Meena Iyer', 'Suresh Babu', 'Lakshmi Devi'];
const SAMPLE_ROOMS = ['101', '102', '103', '201', '202', '203', '204', '301', '302', '303', '401', '402'];

const fresh = () => ({
  hostelName: 'Sunrise Boys PG',
  ownerMobile: '98765 43210',
  me: null, // the student using the prototype
  others: [], // other (sample) students
  claimed: false, // owner has confirmed the waiting list
  smsLog: [], // everything the backend "sent"
  fired: {}, // milestone -> true
  seq: 0,
});
export const pre = (app.pre = app.pre || fresh());
const reset = () => { Object.assign(pre, fresh()); notify(); };

const allStudents = () => (pre.me ? [pre.me] : []).concat(pre.others).filter((s) => s.status !== 'rejected');
const countStudents = () => allStudents().length;
const digits = (v) => (v || '').replace(/\D/g, '');
const fmtMobile = (v) => { const d = digits(v).slice(0, 10); return d.length > 5 ? `${d.slice(0, 5)} ${d.slice(5)}` : d; };
const maskName = (n) => { const p = (n || '').trim().split(/\s+/); return p.length > 1 ? `${p[0]} ${p[p.length - 1][0]}.` : p[0] || ''; };
const feeText = (s) => (s.sameFee ? `${ordinal(s.joinDate.getDate())} (same as joining)` : `${ordinal(s.feeDay)} of every month`);
const feeDay = (s) => (s.sameFee ? s.joinDate.getDate() : s.feeDay);

function log(to, text) {
  pre.smsLog.unshift({ id: ++pre.seq, to, text });
}

/** Backend rule: the owner gets ONE fixed SMS the first time the count reaches 25, 50 and 100. */
function checkMilestones() {
  if (pre.claimed) return; // owner already on the app: no SMS needed
  const n = countStudents();
  MILESTONES.forEach((m) => {
    if (n >= m && !pre.fired[m]) {
      pre.fired[m] = true;
      log(`+91 ${pre.ownerMobile}`, OWNER_SMS(m));
      toast(`Backend: SMS sent to the owner (${m} students).`);
    }
  });
}

function addSamples(n) {
  for (let i = 0; i < n; i++) {
    const k = pre.others.length;
    const name = SAMPLE_NAMES[k % SAMPLE_NAMES.length] + (k >= SAMPLE_NAMES.length ? ` ${Math.floor(k / SAMPLE_NAMES.length) + 1}` : '');
    pre.others.push({
      id: 's' + (++pre.seq), name, mobile: `9${String(100000000 + k * 7919).slice(0, 4)} ${String(10000 + k * 37).slice(0, 5)}`,
      room: SAMPLE_ROOMS[k % SAMPLE_ROOMS.length], sharing: 2 + (k % 3), rent: 5500 + (k % 4) * 1000,
      joinDate: new Date(2026, 7, 5 + (k % 20)), sameFee: k % 3 !== 0, feeDay: 5, status: 'waiting', complete: null, createdAt: Date.now(),
    });
  }
  checkMilestones();
  notify();
}

const sampleComplete = (name) => ({ photo: true, aadhaar: '4821 5532 4821', aadhaarCopy: true, parentName: 'Mr. ' + name.split(' ').slice(-1)[0], parent: '94401 22334', referenceName: 'Anil Kumar', reference: '98480 55667' });

/** Owner confirms the waiting list: every student gets the message at once. */
function claim() {
  pre.claimed = true;
  pre.others.forEach((s, i) => { if (s.status === 'waiting' && i % 2 === 0) { s.complete = sampleComplete(s.name); s.status = 'ready'; } });
  const n = allStudents().filter((s) => s.status === 'waiting').length;
  log(`${n} students`, STUDENT_SMS);
  notify();
}

const daysLeft = (s) => Math.max(0, RETENTION_DAYS - Math.floor((Date.now() - s.createdAt) / 86400000));

// ---------------------------------------------------------------- small pieces
function Warn({ children }) {
  return (
    <View style={{ flexDirection: 'row', gap: 8, backgroundColor: C.amberSoft, borderRadius: 12, padding: 12, marginVertical: 8 }}>
      <Icon name="warning-outline" size={18} color={C.amber} />
      <T size={12.5} color={C.amber} style={{ flex: 1, lineHeight: 19 }}>{children}</T>
    </View>
  );
}
function Note({ children, tone = 'blue' }) {
  const bg = tone === 'green' ? C.greenSoft : C.blueSoft;
  const fg = tone === 'green' ? C.green : C.blue;
  return (
    <View style={{ flexDirection: 'row', gap: 8, backgroundColor: bg, borderRadius: 12, padding: 12, marginVertical: 8 }}>
      <Icon name={tone === 'green' ? 'checkmark-circle-outline' : 'information-circle-outline'} size={18} color={fg} />
      <T size={12.5} color={C.ink} style={{ flex: 1, lineHeight: 19 }}>{children}</T>
    </View>
  );
}
function Line({ label, value, last }) {
  return (
    <View style={{ flexDirection: 'row', justifyContent: 'space-between', paddingVertical: 9, borderBottomWidth: last ? 0 : 1, borderBottomColor: C.line }}>
      <T color={C.muted} size={13.5}>{label}</T>
      <T weight="600" size={13.5} style={{ flexShrink: 1, textAlign: 'right', marginLeft: 12 }}>{value}</T>
    </View>
  );
}
function DayGrid({ value, onChange }) {
  return (
    <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 6 }}>
      {Array.from({ length: 28 }, (_, i) => i + 1).map((n) => {
        const sel = n === value;
        return (
          <Pressable key={n} onPress={() => onChange(n)} accessibilityLabel={`Day ${n}`} style={{ width: 42, height: 40, borderRadius: 10, alignItems: 'center', justifyContent: 'center', borderWidth: 1.2, borderColor: sel ? C.blue : C.line, backgroundColor: sel ? C.blue : '#fff' }}>
            <T weight="600" color={sel ? '#fff' : C.ink}>{n}</T>
          </Pressable>
        );
      })}
    </View>
  );
}

// ======================================================================
// Prototype hub: jump to every part of the student-first flow
// ======================================================================
export function PreHub() {
  const nav = useNav();
  useApp();
  const n = countStudents();
  const step = (icon, title, sub, onPress, color = C.blue) => (
    <Card onPress={onPress} style={{ marginBottom: 10 }}>
      <Row gap={12}>
        <IconBox name={icon} color={color} />
        <View style={{ flex: 1 }}>
          <T weight="800">{title}</T>
          <T size={12.5} color={C.muted}>{sub}</T>
        </View>
        <Icon name="chevron-forward" color={C.muted} />
      </Row>
    </Card>
  );
  return (
    <Screen title="Student-first flow">
      <Note>Prototype only. In the real app these steps happen on different phones and days. Use this page to jump between them.</Note>
      <Card style={{ marginBottom: 10 }}>
        <T size={12.5} color={C.muted}>Students registered with owner +91 {pre.ownerMobile}</T>
        <Row style={{ justifyContent: 'space-between', marginTop: 2 }}>
          <T size={26} weight="800">{n}</T>
          <Pill text={pre.claimed ? 'Owner joined' : 'Owner not on app'} tone={pre.claimed ? 'green' : 'amber'} />
        </Row>
        <Row gap={8} style={{ marginTop: 10, flexWrap: 'wrap' }}>
          <Btn small variant="outline" title="Add 10 students" onPress={() => addSamples(10)} />
          <Btn small variant="outline" title="Add 25 students" onPress={() => addSamples(25)} />
        </Row>
        <T size={12.5} color={C.muted} style={{ marginTop: 8 }}>
          The owner gets one SMS when the count first reaches {MILESTONES.join(', ')}. Add students and watch the SMS log below.
        </T>
      </Card>

      <SectionTitle>Student side</SectionTitle>
      {step('person-add-outline', '1. Student registers', 'Owner number twice · OTP · room · dates', () => nav.push('PreJoin'))}
      {step('time-outline', '2. Student status', 'Waiting, edit, invite my owner', () => (pre.me ? nav.push('PreStatus') : toast('Register as a student first (step 1).')))}
      {step('chatbubble-ellipses-outline', '3. Message after owner joins', 'The SMS and the complete-your-details form', () => (pre.claimed && pre.me ? nav.push('PreSms') : toast('Do step 4 first, after registering in step 1.')), C.green)}

      <SectionTitle>Owner side</SectionTitle>
      {step('log-in-outline', '4. Owner signs up and sees the waiting list', 'Needs the same mobile number as the students typed', () => (n > 0 ? nav.push('PreOwnerClaim') : toast('No students yet. Register one in step 1 or add sample students.')), C.purple)}
      {step('checkmark-done-outline', '5. Students to verify', 'Ready and waiting students, reminders, verify', () => (pre.claimed ? nav.push('PreOwnerList') : toast('Confirm the waiting list first (step 4).')), C.purple)}

      <SectionTitle>Backend SMS log</SectionTitle>
      {pre.smsLog.length === 0 ? (
        <T size={13} color={C.muted}>Nothing sent yet.</T>
      ) : pre.smsLog.map((m) => (
        <Card key={m.id} style={{ marginBottom: 8 }} padding={12}>
          <T size={12} color={C.muted}>To {m.to}</T>
          <T size={13} style={{ marginTop: 3, lineHeight: 19 }}>{m.text}</T>
        </Card>
      ))}
      <Gap h={12} />
      <Btn variant="outline" title="Reset the whole flow" onPress={() => { reset(); toast('Reset.'); }} />
    </Screen>
  );
}

// ======================================================================
// Student 1. Join: hostel name + owner's number typed twice
// ======================================================================
export function PreJoin({ params }) {
  const nav = useNav();
  const edit = !!params.edit;
  const [hostel, setHostel] = useState(pre.hostelName);
  const [m1, setM1] = useState(edit ? pre.ownerMobile : '');
  const [m2, setM2] = useState(edit ? pre.ownerMobile : '');
  const d1 = digits(m1);
  const d2 = digits(m2);
  const match = d1.length === 10 && d1 === d2;
  const mismatch = d2.length === 10 && d1 !== d2;
  const ok = match && hostel.trim().length >= 2;
  const go = () => {
    pre.hostelName = hostel.trim();
    pre.ownerMobile = fmtMobile(d1);
    notify();
    if (edit) { toast('Owner number updated.'); nav.pop(); } else nav.push('PreVerify');
  };
  return (
    <Screen title={edit ? 'Change owner number' : 'Join your hostel'} footer={<Btn title={edit ? 'Save' : 'Continue'} disabled={!ok} onPress={go} />}>
      <Note>Your owner may not be on My Hostel yet. Save your details now. They go only to your owner, after the owner joins.</Note>
      <Field label="Hostel name" value={hostel} onChangeText={setHostel} placeholder="Sunrise Boys PG" />
      <Field label="Owner's mobile number" prefix="+91" value={m1} onChangeText={(v) => setM1(fmtMobile(v))} keyboardType="phone-pad" maxLength={11} placeholder="98765 43210" />
      <Field
        label="Type the owner's number again" prefix="+91" value={m2} onChangeText={(v) => setM2(fmtMobile(v))} keyboardType="phone-pad" maxLength={11} placeholder="98765 43210"
        error={mismatch ? 'The two numbers do not match.' : null}
        right={match ? <Pill text="Matches" tone="green" /> : null}
      />
      {match ? <T size={22} weight="800" center style={{ letterSpacing: 1.5, marginBottom: 6 }}>+91 {fmtMobile(d1)}</T> : null}
      <Warn>
        Please check this number carefully. If you enter the wrong owner's number, your details and your room and rent information go to the wrong person. It can also cause problems with your real hostel owner. Only continue if you are sure.
      </Warn>
      <Pressable onPress={() => { setM1('98765 43210'); setM2('98765 43210'); }} hitSlop={8}>
        <T size={12.5} weight="600" color={C.blue}>Prototype: fill sample number</T>
      </Pressable>
    </Screen>
  );
}

// ======================================================================
// Student 2. Verify the student's own mobile (OTP)
// ======================================================================
export function PreVerify() {
  const nav = useNav();
  const [mobile, setMobile] = useState('');
  const [sent, setSent] = useState(false);
  const [otp, setOtp] = useState('');
  const [err, setErr] = useState(null);
  const send = () => {
    if (digits(mobile).length !== 10) { setErr('Enter your 10-digit mobile number.'); return; }
    setErr(null); setSent(true); toast(`OTP sent by SMS. Demo OTP: ${DEMO_OTP}`);
  };
  const verify = () => {
    if (otp !== DEMO_OTP) { setErr('Wrong OTP. Try again.'); return; }
    pre.draftMobile = mobile;
    nav.replace('PreDetails');
  };
  return (
    <Screen title="Verify your mobile" footer={<Btn title={sent ? 'Verify and continue' : 'Send OTP'} onPress={sent ? verify : send} />}>
      <T color={C.muted} style={{ marginBottom: 14 }}>We send a 6-digit OTP to confirm it is you. No account or password needed.</T>
      <Field label="Your mobile number" prefix="+91" value={mobile} onChangeText={(v) => setMobile(fmtMobile(v))} keyboardType="phone-pad" maxLength={11} placeholder="90000 11223" editable={!sent} />
      {sent ? <Field label="6-digit OTP" value={otp} onChangeText={(v) => { setOtp(digits(v).slice(0, 6)); setErr(null); }} keyboardType="number-pad" maxLength={6} big error={err} /> : err ? <T size={12.5} color={C.red}>{err}</T> : null}
    </Screen>
  );
}

// ======================================================================
// Student 3. Name + room details
// ======================================================================
export function PreDetails({ params }) {
  const nav = useNav();
  const s = pre.me;
  const edit = !!params.edit && s;
  const [name, setName] = useState(edit ? s.name : '');
  const [room, setRoom] = useState(edit ? s.room : '');
  const [sharing, setSharing] = useState(edit ? s.sharing : 0);
  const [rent, setRent] = useState(edit ? String(s.rent) : '');
  const ok = name.trim().length >= 2 && room.trim().length >= 1 && sharing > 0 && digits(rent).length >= 3;
  const next = () => {
    pre.form = { name: name.trim(), room: room.trim(), sharing, rent: parseInt(digits(rent), 10) };
    nav.push('PreDates', { edit: !!edit });
  };
  return (
    <Screen title="Your details" footer={<Btn title="Next" disabled={!ok} onPress={next} />}>
      <Field label="Full name" value={name} onChangeText={setName} placeholder="Rahul Verma" />
      <View style={{ marginBottom: 14, flexDirection: 'row', alignItems: 'center', gap: 8, backgroundColor: '#fff', borderRadius: 12, borderWidth: 1.2, borderColor: C.line, paddingHorizontal: 14, minHeight: 50 }}>
        <T color={C.muted}>Mobile</T>
        <T weight="600" style={{ flex: 1 }}>+91 {edit ? s.mobile : pre.draftMobile}</T>
        <Icon name="checkmark-circle" size={18} color={C.green} />
      </View>
      <Field label="Room name or number" value={room} onChangeText={setRoom} placeholder="204" maxLength={8} />
      <T size={14} weight="600" style={{ marginBottom: 6 }}>Sharing</T>
      <SharingPicker value={sharing} onChange={setSharing} />
      <Gap h={14} />
      <Field label="Rent per month" prefix="₹" value={rent} onChangeText={(v) => setRent(digits(v).slice(0, 6))} keyboardType="number-pad" placeholder="6500" />
      <Note>Your owner will check these room details. Only the owner of this number can see them, after the owner signs up. If no owner joins in {RETENTION_DAYS} days, they are deleted.</Note>
      <Pressable onPress={() => { setName('Rahul Verma'); setRoom('204'); setSharing(3); setRent('6500'); }} hitSlop={8}>
        <T size={12.5} weight="600" color={C.blue}>Prototype: fill sample details</T>
      </Pressable>
    </Screen>
  );
}

// ======================================================================
// Student 4. Joining date + fee date
// ======================================================================
export function PreDates({ params }) {
  const nav = useNav();
  const s = pre.me;
  const edit = !!params.edit && s;
  const [joinDate, setJoinDate] = useState(edit ? s.joinDate : new Date(2026, 7, 18));
  const [same, setSame] = useState(edit ? s.sameFee : true);
  const [day, setDay] = useState(edit ? s.feeDay : 5);
  const save = () => {
    const f = pre.form;
    if (edit) {
      Object.assign(pre.me, { ...f, joinDate, sameFee: same, feeDay: day });
      toast('Details updated.');
      notify();
      nav.popTo('PreStatus');
      return;
    }
    pre.me = { id: 'me', ...f, mobile: fmtMobile(pre.draftMobile), joinDate, sameFee: same, feeDay: day, status: 'waiting', complete: null, createdAt: Date.now() };
    checkMilestones();
    notify();
    nav.popTo('PreHub');
    nav.push('PreStatus');
  };
  return (
    <Screen title="Joining and fee date" footer={<Btn title={edit ? 'Save' : 'Save and wait for owner'} onPress={save} />}>
      <T size={14} weight="600" style={{ marginBottom: 6 }}>Joining date</T>
      <Card padding={12}><DateStepper date={joinDate} onChange={setJoinDate} /></Card>
      <Gap h={8} />
      <CheckRow value={same} onChange={setSame} label="My fee date is the same as my joining date" />
      {same ? (
        <Card style={{ marginTop: 6 }}>
          <Row style={{ justifyContent: 'space-between' }}>
            <T color={C.muted}>Fee due every month on</T>
            <T size={18} weight="800">{ordinal(joinDate.getDate())}</T>
          </Row>
        </Card>
      ) : (
        <View style={{ marginTop: 6 }}>
          <T size={14} weight="600" style={{ marginBottom: 8 }}>Fee due every month on day</T>
          <DayGrid value={day} onChange={setDay} />
          <Note>Some hostels collect fees on a fixed day, such as the 5th. Your owner will confirm what you pay for the first part month.</Note>
        </View>
      )}
    </Screen>
  );
}

// ======================================================================
// Student 5. Status: waiting / complete your details / sent / added
// ======================================================================
export function PreStatus() {
  const nav = useNav();
  useApp();
  const s = pre.me;
  if (!s) return <Screen title="My hostel"><T color={C.muted}>Nothing saved yet.</T></Screen>;
  const invite = () => {
    const msg = `Hi, I registered for ${pre.hostelName} on My Hostel using your number. Please install the app so you can see all students and fee details: myhostel.app/o`;
    Linking.openURL(`whatsapp://send?text=${encodeURIComponent(msg)}`).catch(() => toast('WhatsApp would open with a ready message to the owner.'));
  };
  const state = s.status === 'verified' ? 'added' : s.status === 'ready' ? 'sent' : pre.claimed ? 'complete' : 'waiting';
  return (
    <Screen title="My hostel" onBack={() => nav.popTo('PreHub')}>
      {state === 'waiting' ? (
        <Card>
          <T size={17} weight="800">Waiting for your owner</T>
          <T size={12.5} color={C.muted} style={{ marginTop: 3 }}>{pre.hostelName} · owner +91 {pre.ownerMobile}</T>
          <T size={13} style={{ marginTop: 8 }}>{daysLeft(s)} days left. After that your details are deleted.</T>
        </Card>
      ) : null}
      {state === 'complete' ? (
        <Card border={C.green} bg={C.greenSoft}>
          <T size={17} weight="800" color={C.green}>{pre.hostelName} owner has joined</T>
          <T size={13} style={{ marginTop: 4 }}>Please complete your details so your owner can verify you.</T>
          <Gap h={10} />
          <Btn title="Complete my details" onPress={() => nav.push('PreComplete')} />
        </Card>
      ) : null}
      {state === 'sent' ? (
        <Card border={C.green} bg={C.greenSoft}>
          <T size={17} weight="800" color={C.green}>Sent to your owner</T>
          <T size={13} style={{ marginTop: 4 }}>Waiting for your owner to verify you.</T>
        </Card>
      ) : null}
      {state === 'added' ? (
        <Card border={C.green} bg={C.greenSoft}>
          <T size={17} weight="800" color={C.green}>Your owner added you</T>
          <T size={13} style={{ marginTop: 4 }}>From here the app works as before: your stay, rent bills and complaints.</T>
        </Card>
      ) : null}

      <Gap h={10} />
      <Card>
        <Line label="Name" value={s.name} />
        <Line label="Mobile" value={`+91 ${s.mobile}`} />
        <Line label="Room · sharing" value={`${s.room} · ${s.sharing} sharing`} />
        <Line label="Rent" value={rupees(s.rent)} />
        <Line label="Joining date" value={fmtDate(s.joinDate)} />
        <Line label="Fee due" value={feeText(s)} last />
      </Card>
      {state !== 'added' ? (
        <>
          <Gap h={10} />
          <Btn variant="outline" icon="create-outline" title="Edit my details" onPress={() => nav.push('PreDetails', { edit: true })} />
          {!pre.claimed ? (
            <>
              <Gap h={8} />
              <Btn variant="outline" icon="swap-horizontal-outline" title="Change owner number" onPress={() => nav.push('PreJoin', { edit: true })} />
              <Gap h={8} />
              <Btn icon="logo-whatsapp" title="Invite my owner on WhatsApp" onPress={invite} />
            </>
          ) : null}
        </>
      ) : null}
      <Gap h={10} />
      <T size={12} color={C.muted} center>Only your owner can see your details. They are deleted automatically after {RETENTION_DAYS} days if no owner joins.</T>
    </Screen>
  );
}

// ======================================================================
// Student 6. The message the student receives + complete the details
// ======================================================================
export function PreSms() {
  const nav = useNav();
  return (
    <Screen title="Messages">
      <T size={12} color={C.muted} center>Today, 11:20</T>
      <View style={{ backgroundColor: '#fff', borderRadius: 16, borderBottomLeftRadius: 4, borderWidth: 1, borderColor: C.line, padding: 14, marginTop: 10 }}>
        <T size={14} style={{ lineHeight: 21 }}>{STUDENT_SMS.replace(' Open: myhostel.app/c/x7Kq2', '')}</T>
        <Pressable onPress={() => nav.push('PreComplete')}>
          <T size={14} weight="600" color={C.blue} style={{ marginTop: 4, textDecorationLine: 'underline' }}>myhostel.app/c/x7Kq2</T>
        </Pressable>
      </View>
      <Note>This message goes to every student on the list at the moment the owner confirms the waiting list. Tap the link to continue.</Note>
    </Screen>
  );
}

export function PreComplete() {
  const nav = useNav();
  const s = pre.me;
  const [f, setF] = useState({ photo: false, aadhaar: '', aadhaarCopy: false, parentName: '', parent: '', referenceName: '', reference: '', consent: false });
  const set = (k, v) => setF((x) => ({ ...x, [k]: v }));
  const idDigits = digits(f.aadhaar);
  const ok = f.photo && idDigits.length === 12 && f.aadhaarCopy && f.parentName.trim().length >= 2 && digits(f.parent).length === 10 &&
    f.referenceName.trim().length >= 2 && digits(f.reference).length === 10 && f.consent;
  const send = () => {
    s.complete = { ...f };
    s.status = 'ready';
    notify();
    toast('Sent to your owner.');
    nav.pop();
  };
  const groups = (v) => digits(v).slice(0, 12).replace(/(\d{4})(?=\d)/g, '$1 ');
  return (
    <Screen title="Complete your details" footer={<Btn title="Send to owner" disabled={!ok} onPress={send} />}>
      <Note tone="green">{pre.hostelName} accepted you. These are the last details your owner needs.</Note>
      <UploadBox label="Your photo" hint="Tap to take or upload" done={f.photo} onPress={() => set('photo', !f.photo)} />
      <Gap h={12} />
      <Field label="Aadhaar number" value={f.aadhaar} onChangeText={(v) => set('aadhaar', groups(v))} keyboardType="number-pad" maxLength={14} placeholder="12-digit number" />
      <UploadBox label="Aadhaar copy" hint="Tap to upload" done={f.aadhaarCopy} onPress={() => set('aadhaarCopy', !f.aadhaarCopy)} />
      <Gap h={14} />
      <Field label="Parent's name" value={f.parentName} onChangeText={(v) => set('parentName', v)} placeholder="Mr. Suresh Verma" />
      <Field label="Parent's mobile" prefix="+91" value={f.parent} onChangeText={(v) => set('parent', fmtMobile(v))} keyboardType="phone-pad" maxLength={11} placeholder="94401 22334" />
      <Field label="Reference name" value={f.referenceName} onChangeText={(v) => set('referenceName', v)} placeholder="Anil Kumar" />
      <Field label="Reference mobile" prefix="+91" value={f.reference} onChangeText={(v) => set('reference', fmtMobile(v))} keyboardType="phone-pad" maxLength={11} placeholder="98480 55667" />
      <CheckRow value={f.consent} onChange={(v) => set('consent', v)} label="I agree. Only my owner can see these, and every time the owner views my Aadhaar it is logged (DPDP Act 2023)." />
      <Pressable onPress={() => setF({ photo: true, aadhaar: '4821 5532 4821', aadhaarCopy: true, parentName: 'Mr. Suresh Verma', parent: '94401 22334', referenceName: 'Anil Kumar', reference: '98480 55667', consent: true })} hitSlop={8}>
        <T size={12.5} weight="600" color={C.blue}>Prototype: fill sample details</T>
      </Pressable>
    </Screen>
  );
}

// ======================================================================
// Owner 1. Owner signed up: students are waiting. Confirm the hostel.
// ======================================================================
export function PreOwnerClaim() {
  const nav = useNav();
  useApp();
  const list = allStudents();
  const yes = () => {
    claim();
    toast(`Message sent to ${list.filter((s) => s.status === 'waiting').length} students.`);
    nav.replace('PreOwnerList');
  };
  return (
    <Screen
      title="My hostels"
      footer={
        <View>
          <Btn title="Yes, these are my students" onPress={yes} />
          <Gap h={8} />
          <Btn variant="outline" title="Not my students" onPress={() => { toast('They will not be shown to you.'); nav.pop(); }} />
        </View>
      }
    >
      <T size={20} weight="800">{list.length} {list.length === 1 ? 'student is' : 'students are'} waiting for you</T>
      <T size={13} color={C.muted} style={{ marginTop: 4, marginBottom: 12 }}>They gave your number, +91 {pre.ownerMobile}. Only you can see this list.</T>
      <Card padding={12}>
        {list.slice(0, 5).map((s, i) => (
          <View key={s.id} style={{ flexDirection: 'row', justifyContent: 'space-between', paddingVertical: 8, borderBottomWidth: i < Math.min(5, list.length) - 1 ? 1 : 0, borderBottomColor: C.line }}>
            <T>{maskName(s.name)}</T>
            <T color={C.muted} size={13}>Room {s.room}</T>
          </View>
        ))}
        {list.length > 5 ? <T size={13} color={C.muted} style={{ marginTop: 8 }}>+ {list.length - 5} more</T> : null}
      </Card>
      <Note>Are these students of your hostel? Confirm the hostel name: <T size={12.5} weight="800">{pre.hostelName}</T>. When you confirm, every student gets a message to complete their details.</Note>
    </Screen>
  );
}

// ======================================================================
// Owner 2. Students to verify
// ======================================================================
export function PreOwnerList() {
  const nav = useNav();
  useApp();
  const list = allStudents();
  const ready = list.filter((s) => s.status === 'ready').length;
  const waiting = list.filter((s) => s.status === 'waiting').length;
  const added = list.filter((s) => s.status === 'verified').length;
  const open = (s) => {
    if (s.status === 'waiting') { toast('Still adding details.'); return; }
    nav.push('PreOwnerVerify', { id: s.id });
  };
  const remind = () => {
    if (!waiting) { toast('Nobody is waiting.'); return; }
    log(`${waiting} students`, STUDENT_SMS);
    notify();
    toast(`Reminder sent to ${waiting} students.`);
  };
  return (
    <Screen title="Students to verify" onBack={() => nav.popTo('PreHub')}>
      <T color={C.muted} style={{ marginBottom: 10 }}>{list.length} students · {ready} ready · {waiting} still adding details{added ? ` · ${added} added` : ''}</T>
      <Card padding={0}>
        {list.map((s, i) => (
          <Pressable key={s.id} onPress={() => open(s)} style={{ flexDirection: 'row', alignItems: 'center', gap: 10, padding: 12, borderBottomWidth: i < list.length - 1 ? 1 : 0, borderBottomColor: C.line }}>
            <Avatar name={s.name} size={38} />
            <View style={{ flex: 1 }}>
              <T weight="600">{s.name}</T>
              <T size={12.5} color={C.muted}>Room {s.room} · {s.sharing} sharing</T>
            </View>
            {s.status === 'verified' ? <Pill text="Added" tone="green" /> : s.status === 'ready' ? <Pill text="Ready" tone="green" /> : <Pill text="Waiting" tone="amber" />}
            <Icon name="chevron-forward" size={18} color={C.muted} />
          </Pressable>
        ))}
      </Card>
      <Gap h={12} />
      <Btn variant="outline" icon="notifications-outline" title="Send reminder to waiting students" onPress={remind} />
      <Note>You can verify only students whose details are complete.</Note>
    </Screen>
  );
}

// ======================================================================
// Owner 3. Verify one full record
// ======================================================================
export function PreOwnerVerify({ params }) {
  const nav = useNav();
  useApp();
  const s = allStudents().find((x) => x.id === params.id);
  const [edit, setEdit] = useState(false);
  const [room, setRoom] = useState(s ? s.room : '');
  const [sharing, setSharing] = useState(s ? s.sharing : 2);
  const [rent, setRent] = useState(s ? String(s.rent) : '');
  const [joinDate, setJoinDate] = useState(s ? s.joinDate : new Date());
  const [same, setSame] = useState(s ? s.sameFee : true);
  const [day, setDay] = useState(s ? s.feeDay : 5);
  const [revealed, setRevealed] = useState(false);
  if (!s || !s.complete) return <Screen title="Student"><T color={C.muted}>Details are not complete yet.</T></Screen>;
  const c = s.complete;
  const applyEdits = () => Object.assign(s, { room: room.trim(), sharing, rent: parseInt(digits(rent), 10) || s.rent, joinDate, sameFee: same, feeDay: day });
  const verify = () => {
    applyEdits();
    s.status = 'verified';
    app.tenants.push({
      id: 'pre-' + s.id, name: s.name, mobile: s.mobile, parentMobile: c.parent, room: s.room, bed: 'A', joined: fmtDate(s.joinDate), rent: s.rent, deposit: s.rent,
      status: 'pending', dueDate: `${ordinal(feeDay(s))}`, stayType: 'monthly', idLast4: digits(c.aadhaar).slice(-4), address: '—', office: '—', reference: c.referenceName, daysLate: 0, payments: [],
    });
    notify();
    toast(`${s.name} added as a tenant. Bills start on the ${ordinal(feeDay(s))}.`);
    nav.pop();
  };
  const back = () => {
    s.status = 'waiting'; s.complete = null;
    log(`${s.name}`, 'My Hostel: Your owner asked you to correct some details. Please open the link and update them: myhostel.app/c/x7Kq2');
    notify();
    toast('Sent back to the student for correction.');
    nav.pop();
  };
  return (
    <Screen
      title={s.name}
      footer={
        <View>
          <Btn title="Verify and add as tenant" onPress={verify} />
          <Gap h={8} />
          <Btn variant="outline" title="Send back for correction" onPress={back} />
        </View>
      }
    >
      <Card>
        <Line label="Mobile" value={`+91 ${s.mobile}`} />
        <Line label="Parent" value={`${c.parentName} · +91 ${c.parent}`} />
        <Line label="Reference" value={`${c.referenceName} · +91 ${c.reference}`} />
        <Line label="Aadhaar" value={revealed ? c.aadhaar : `•••• •••• ${digits(c.aadhaar).slice(-4)}`} last />
      </Card>
      <Gap h={10} />
      <Row gap={8}>
        <View style={{ flex: 1 }}><Btn small variant="outline" title="View photo" onPress={() => toast('Photo opened for 5 minutes.')} /></View>
        <View style={{ flex: 1 }}><Btn small variant="outline" title="Aadhaar copy" onPress={() => toast('Opened and logged.')} /></View>
        <View style={{ flex: 1 }}><Btn small variant="outline" title={revealed ? 'Hide' : 'Reveal'} onPress={() => { setRevealed(!revealed); if (!revealed) toast('Aadhaar number revealed. Logged.'); }} /></View>
      </Row>
      <Gap h={6} />

      <SectionTitle right={<Btn small variant="text" title={edit ? 'Done' : 'Edit'} onPress={() => setEdit(!edit)} />}>Room, rent and dates (please confirm)</SectionTitle>
      {!edit ? (
        <Card>
          <Line label="Room · sharing" value={`${room} · ${sharing} sharing`} />
          <Line label="Rent" value={rupees(parseInt(digits(rent), 10) || 0)} />
          <Line label="Joining date" value={fmtDate(joinDate)} />
          <Line label="Fee due" value={same ? `${ordinal(joinDate.getDate())} (same as joining)` : `${ordinal(day)} of every month`} last />
        </Card>
      ) : (
        <View>
          <Field label="Room" value={room} onChangeText={setRoom} maxLength={8} />
          <T size={14} weight="600" style={{ marginBottom: 6 }}>Sharing</T>
          <SharingPicker value={sharing} onChange={setSharing} />
          <Gap h={12} />
          <Field label="Rent per month" prefix="₹" value={rent} onChangeText={(v) => setRent(digits(v).slice(0, 6))} keyboardType="number-pad" />
          <T size={14} weight="600" style={{ marginBottom: 6 }}>Joining date</T>
          <Card padding={12}><DateStepper date={joinDate} onChange={setJoinDate} /></Card>
          <CheckRow value={same} onChange={setSame} label="Fee date is the same as the joining date" />
          {!same ? <DayGrid value={day} onChange={setDay} /> : null}
        </View>
      )}
      <Note>Bills start only after you verify. From then the student is a normal tenant in the app.</Note>
    </Screen>
  );
}
