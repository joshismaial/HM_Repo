// Student joining flow (no login): opened from the hostel's QR code / link.
import React, { useEffect, useState } from 'react';
import { Linking, Pressable, ScrollView, TextInput, View } from 'react-native';
import { useNav, useBackHandler } from '../nav';
import { showSheet, toast } from '../overlay';
import {
  DEMO_OTP, DUPLICATE_UTR, FLOOR_OPTIONS, actions, addDays, app, bedLabel, countBeds, fmtDate, freeBeds, joiningDeposit, joiningTotal, ordinal, rupees,
  shortFlow, useApp,
  cleanHostelName, hostelTitle,
} from '../state';
import {
  Btn, C, Card, CheckRow, Chips, DateStepper, Divider, Field, Gap, HoldBanner, Icon, IconBox, InfoRow, LanguageButton, LanguageList, Pill,
  PhotoBox, Row, Screen, SectionTitle, Segmented, StatTile, StepHeader, Stepper, T, UploadBox, Avatar, typePill, FloorPicker, SharingPicker, floorText, isGroundRoom, roomMatchesFloor, startsWithG,
  SkyBack, appFont,
} from '../ui';
import { QrSheet, UpiTiles, openUpiApp } from './upiPay';

const openLanguage = () => showSheet((close) => <LanguageList close={close} />);

// ======================================================================
// 0a. "Get the app" web page (office QR or the owner's bed QR, app not installed)
// ======================================================================
export function GetApp() {
  const nav = useNav();
  const d = app.draft;
  const h = app.hostels[0];
  return (
    <ScrollView style={{ flex: 1, backgroundColor: C.ground }} contentContainerStyle={{ paddingBottom: 30 }}>
      <View style={{ backgroundColor: '#1560BD', paddingTop: 50, paddingBottom: 28, alignItems: 'center', overflow: 'hidden' }}>
        <SkyBack />
        <T size={12.5} color="#D6ECFC" style={{ position: 'absolute', top: 20, left: 16 }}>🔒 myhostel.app/j/7KQ2</T>
        <View style={{ width: 80, height: 80, borderRadius: 16, backgroundColor: '#fff', alignItems: 'center', justifyContent: 'center' }}>
          <Icon name="home" size={42} color="#1560BD" />
        </View>
        <T weight="600" color="#fff" style={{ marginTop: 8 }}>My Hostel</T>
      </View>
      <View style={{ padding: 16, alignItems: 'center' }}>
        <T size={24} weight="800">Welcome!</T>
        <T size={14} color={C.muted} center style={{ marginTop: 4 }}>You've been invited by <T size={14} weight="600">{app.ownerName}</T> to join</T>
        <Card style={{ alignSelf: 'stretch', marginTop: 14, alignItems: 'center' }}>
          <T size={20} weight="800" center>{hostelTitle(h)}</T>
          <T color={C.muted}>{h.area}</T>
          {d.booked && d.room ? (
            <View style={{ alignSelf: 'stretch', backgroundColor: C.greenSoft, borderRadius: 12, padding: 8, marginTop: 10 }}>
              <T weight="600" color={C.green} center>🛏  Room {d.room.number} · Bed {bedLabel(d.bedIndex)} held for you</T>
            </View>
          ) : null}
        </Card>
        <T size={20} weight="800" style={{ marginTop: 24 }}>Get the app to continue</T>
        <Pressable
          onPress={() => { toast('Prototype: Google Play opens, the app installs and opens on this hostel.'); nav.replace('StudentWelcome'); }}
          style={{ flexDirection: 'row', alignItems: 'center', gap: 8, backgroundColor: '#000', borderRadius: 12, paddingHorizontal: 22, paddingVertical: 10, marginTop: 12 }}
        >
          <Icon name="logo-google-playstore" size={26} color="#34D399" />
          <View>
            <T size={11} color="#fff">GET IT ON</T>
            <T size={20} weight="800" color="#fff">Google Play</T>
          </View>
        </Pressable>
        <T size={12.5} color={C.muted} center style={{ marginTop: 10 }}>After installing, the app opens on {hostelTitle(h)}</T>
      </View>
    </ScrollView>
  );
}

// ======================================================================
// 0b. App welcome: hostel name + Student registration (15-minute timer starts for a held bed)
// ======================================================================
export function StudentWelcome() {
  const nav = useNav();
  const d = app.draft;
  const h = app.hostels[0];
  useEffect(() => {
    if (d.booked && !d.timerStarted) {
      d.timerStarted = true;
      d.holdUntil = Date.now() + 15 * 60 * 1000;
      actions.touch();
    }
  }, []);
  return (
    <Screen right={<LanguageButton onOpen={openLanguage} />}>
      <Gap h={20} />
      <T size={24} weight="800" center>Welcome</T>
      <Card style={{ marginTop: 16, alignItems: 'center', padding: 20 }}>
        <View style={{ width: 56, height: 56, borderRadius: 16, backgroundColor: '#1560BD', alignItems: 'center', justifyContent: 'center' }}>
          <T size={24} weight="800" color="#fff">{cleanHostelName(h.name)[0]}</T>
        </View>
        <T size={20} weight="800" center style={{ marginTop: 10 }}>{hostelTitle(h)}</T>
        <T color={C.muted}>{h.area}</T>
        <T size={12.5} color={C.muted}>Owner · {app.ownerName}</T>
        {d.booked && d.room ? (
          <View style={{ alignSelf: 'stretch', backgroundColor: C.greenSoft, borderRadius: 12, padding: 8, marginTop: 10 }}>
            <T weight="600" color={C.green} center>🛏  Room {d.room.number} · Bed {bedLabel(d.bedIndex)} held for you</T>
          </View>
        ) : null}
      </Card>
      {d.booked ? <><Gap h={10} /><HoldBanner /></> : null}
      <Pressable onPress={() => nav.push('VerifyMobile', { booked: d.booked })} style={{ flexDirection: 'row', alignItems: 'center', gap: 12, backgroundColor: '#1560BD', borderRadius: 16, padding: 16, marginTop: 20 }}>
        <View style={{ width: 46, height: 46, borderRadius: 12, backgroundColor: 'rgba(255,255,255,0.18)', alignItems: 'center', justifyContent: 'center' }}>
          <Icon name="person-add" color="#fff" />
        </View>
        <View style={{ flex: 1 }}>
          <T size={16} weight="800" color="#fff">Student registration</T>
          <T size={12.5} color="#D6ECFC">{d.booked ? 'Verify mobile · details · pay' : 'Verify mobile · details · room · pay'}</T>
        </View>
        <Icon name="chevron-forward" color="#D6ECFC" />
      </Pressable>
      <Btn variant="text" title="Already joined? Find my booking" onPress={() => nav.push('VerifyMobile', { findBooking: true })} />
      <Gap h={20} />
      <T size={12.5} color={C.muted} center>No account or password needed</T>
    </Screen>
  );
}

// ======================================================================
// 1. Verify mobile (Step 1 of 4) – also used for "Find my booking"
//    Two steps on one screen: enter mobile → enter OTP (6 boxes).
//    Wrong OTP: red boxes + tries left. 3 wrong: locked for 10 minutes.
// ======================================================================
const OTP_LEN = 6;
const RESEND_SECS = 30;
const LOCK_SECS = 600;
const MAX_TRIES = 3;
const mmss = (s) => `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
const fmtMobile = (m) => { const d = m.replace(/\D/g, ''); return d.length > 5 ? `${d.slice(0, 5)} ${d.slice(5)}` : d; };

function OtpBoxes({ value, onChange, error, locked }) {
  const ref = React.useRef(null);
  useEffect(() => { if (!locked) setTimeout(() => ref.current && ref.current.focus(), 250); }, [locked]);
  return (
    <View>
      <Pressable onPress={() => ref.current && ref.current.focus()} disabled={locked} accessibilityLabel="Enter the 6-digit OTP" style={{ flexDirection: 'row', gap: 8 }}>
        {Array.from({ length: OTP_LEN }).map((_, i) => {
          const ch = value[i] || '';
          const active = !locked && !error && i === Math.min(value.length, OTP_LEN - 1);
          return (
            <View key={i} style={{ flex: 1, height: 54, borderRadius: 12, alignItems: 'center', justifyContent: 'center', backgroundColor: locked ? C.ground : error ? C.redSoft : '#fff', borderWidth: active || error ? 2 : 1.2, borderColor: error ? C.red : active ? C.blue : C.line }}>
              <T size={22} weight="800" color={error ? C.red : locked ? C.muted : C.ink}>{ch}</T>
            </View>
          );
        })}
      </Pressable>
      <TextInput
        ref={ref}
        value={value}
        onChangeText={(v) => onChange(v.replace(/\D/g, '').slice(0, OTP_LEN))}
        keyboardType="number-pad"
        maxLength={OTP_LEN}
        editable={!locked}
        textContentType="oneTimeCode"
        autoComplete="sms-otp"
        caretHidden
        style={{ position: 'absolute', opacity: 0, width: 1, height: 1 }}
      />
    </View>
  );
}

export function VerifyMobile({ params }) {
  const nav = useNav();
  const find = !!params.findBooking;
  const booked = !!params.booked && app.draft.booked && app.draft.room; // opened from the owner's QR for one bed
  const [mobile, setMobile] = useState('');
  const [otp, setOtp] = useState('');
  const [sent, setSent] = useState(false);
  const [mobileError, setMobileError] = useState(null);
  const [wrong, setWrong] = useState(false);
  const [tries, setTries] = useState(0);
  const [resendIn, setResendIn] = useState(0);
  const [lockedIn, setLockedIn] = useState(0);
  const locked = lockedIn > 0;

  useEffect(() => {
    if (resendIn <= 0) return undefined;
    const id = setTimeout(() => setResendIn((s) => s - 1), 1000);
    return () => clearTimeout(id);
  }, [resendIn]);
  useEffect(() => {
    if (lockedIn <= 0) return undefined;
    const id = setTimeout(() => {
      if (lockedIn === 1) { setTries(0); setWrong(false); setOtp(''); setResendIn(0); }
      setLockedIn((s) => s - 1);
    }, 1000);
    return () => clearTimeout(id);
  }, [lockedIn]);

  const sendOtp = () => {
    if (mobile.replace(/\D/g, '').length !== 10) {
      setMobileError('Enter your 10-digit mobile number.');
      return;
    }
    setMobileError(null);
    setSent(true);
    setResendIn(RESEND_SECS);
    toast(`OTP sent by SMS. Demo OTP: ${DEMO_OTP}`);
  };

  const resend = () => {
    if (resendIn > 0 || locked) return;
    setOtp(''); setWrong(false);
    setResendIn(RESEND_SECS);
    toast(`OTP sent again. Demo OTP: ${DEMO_OTP}`);
  };

  const changeNumber = () => { setSent(false); setOtp(''); setWrong(false); setTries(0); setResendIn(0); };

  const verify = () => {
    if (locked) return;
    if (otp.length < OTP_LEN) { setWrong(false); toast('Enter all 6 digits.'); return; }
    if (otp !== DEMO_OTP) {
      const n = tries + 1;
      setTries(n);
      setWrong(true);
      if (n >= MAX_TRIES) { setLockedIn(LOCK_SECS); setOtp(''); }
      return;
    }
    app.draft.mobile = mobile;
    app.draft.verified = true;
    if (find) nav.resetTo('StudentShell');
    else nav.replace('YourDetails'); // details first; scanned the hostel QR → room selection after the profile
  };

  const callOwner = () => {
    const h = app.hostels[0];
    const num = (h.contact || app.ownerMobile || '').replace(/\D/g, '');
    Linking.openURL(`tel:+91${num}`).catch(() => toast(`Owner: +91 ${h.contact || app.ownerMobile}`));
  };

  const left = MAX_TRIES - tries;
  const title = locked ? 'Too many tries' : sent ? 'Enter the OTP' : find ? 'Find my booking' : null;
  const sub = locked
    ? `For your safety, try again in ${mmss(lockedIn)}.`
    : sent ? `Sent to +91 ${fmtMobile(mobile)}`
    : find ? 'Enter the mobile number you used when joining. We’ll send a 6-digit OTP.' : null;

  return (
    <Screen right={<LanguageButton onOpen={openLanguage} />}>
      {title ? (
        <View>
          <T size={24} weight="800">{title}</T>
          <T color={C.muted} style={{ marginTop: 6, lineHeight: 20 }}>{sub}</T>
        </View>
      ) : (
        <StepHeader step={1} total={booked || shortFlow() ? 4 : 5} title="Verify your mobile" subtitle="We’ll send a 6-digit OTP to confirm it’s you. No account or password needed." />
      )}
      <Gap h={20} />

      {booked ? <BookedBedCard /> : null}
      {!sent && !booked ? (
        <Card>
          <Row gap={12}>
            <IconBox name="business" />
            <View style={{ flex: 1 }}>
              <T size={16} weight="800">{app.hostels[0].name}</T>
              <T size={12.5} color={C.muted}>From your hostel’s link</T>
            </View>
          </Row>
        </Card>
      ) : null}
      {!sent ? <Gap h={20} /> : null}

      {!sent ? (
        <Field label="Mobile number" prefix="+91" placeholder="98765 43210" value={mobile} onChangeText={setMobile} keyboardType="phone-pad" maxLength={11} error={mobileError} autoFocus={find} />
      ) : (
        <View>
          <View style={{ flexDirection: 'row', alignItems: 'center', gap: 10, backgroundColor: C.ground, borderRadius: 12, borderWidth: 1.2, borderColor: C.line, paddingHorizontal: 14, minHeight: 50 }}>
            <Icon name="lock-closed-outline" size={18} color={C.muted} />
            <T style={{ flex: 1 }} color={C.ink}>+91 {fmtMobile(mobile)}</T>
            <Btn small variant="text" title="Change" onPress={changeNumber} />
          </View>
          <Gap h={18} />
          <T size={14} weight="600" style={{ marginBottom: 8 }}>6-digit OTP</T>
          <OtpBoxes value={otp} onChange={(v) => { setOtp(v); setWrong(false); }} error={wrong && !locked} locked={locked} />
          <Gap h={10} />
          {locked ? null : wrong ? (
            <Row gap={6} style={{ marginBottom: 4 }}>
              <Icon name="alert-circle-outline" size={16} color={C.red} />
              <T size={13} color={C.red} weight="600">Wrong OTP. {left} {left === 1 ? 'try' : 'tries'} left.</T>
            </Row>
          ) : null}
          {locked ? null : (
            resendIn > 0
              ? <T size={13} color={C.muted} style={{ marginTop: 2 }}>Resend OTP in {mmss(resendIn)}</T>
              : <View style={{ alignSelf: 'flex-start', marginLeft: -14 }}><Btn small variant="text" title="Resend OTP" onPress={resend} /></View>
          )}
        </View>
      )}

      {locked ? (
        <View style={{ backgroundColor: C.amberSoft, borderRadius: 12, padding: 12, marginTop: 14 }}>
          <T size={13} color={C.amber} style={{ lineHeight: 19 }}>Can’t wait? Ask the owner of {app.hostels[0].name} to send your link again.</T>
        </View>
      ) : null}

      {booked && !sent ? (
        <View style={{ flexDirection: 'row', gap: 8, backgroundColor: C.blueSoft, borderRadius: 12, padding: 12, marginTop: 14 }}>
          <Icon name="lock-closed-outline" size={18} color={C.blue} />
          <T size={12.5} color={C.ink} style={{ flex: 1 }}>No password. This phone is remembered — next time the app opens straight to your stay.</T>
        </View>
      ) : null}

      <Gap h={20} />
      {locked ? <Btn variant="outline" icon="call-outline" title="Call owner" onPress={callOwner} /> : null}
      {locked ? <Gap h={10} /> : null}
      <Btn title={sent ? 'Verify and continue' : 'Send OTP'} onPress={sent ? verify : sendOtp} disabled={locked} />
      {!find && !booked && !sent ? (
        <>
          <Gap h={10} />
          <Btn variant="outline" icon="search" title="Already booked? Find my booking" onPress={() => nav.push('VerifyMobile', { findBooking: true })} />
        </>
      ) : null}
      <Gap h={14} />
      <Btn variant="text" title="Privacy policy · Terms of use" onPress={() => nav.push('Privacy')} />
    </Screen>
  );
}

// ======================================================================
// 1b. Hostel details
// ======================================================================
export function HostelDetails() {
  const nav = useNav();
  useApp();
  const h = app.hostels[0];
  const minRent = Math.min(...app.rooms.map((r) => r.rent));
  const minDay = Math.min(...app.rooms.map((r) => r.perDay));
  const sharings = [...new Set(app.rooms.map((r) => r.sharing))].sort((a, b) => a - b);
  return (
    <Screen
      headerContent={<Pill text="Mobile verified" tone="green" icon="checkmark-circle" />}
      right={<LanguageButton onOpen={openLanguage} />}
      footer={<Btn title="View available rooms" onPress={() => nav.push('AvailableRooms')} />}
    >
      <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ gap: 10 }}>
        <PhotoBox width={290} label="Front view" />
        <PhotoBox width={290} label="Room 102" color={C.green} />
        <PhotoBox width={290} label="Dining area" color={C.purple} />
      </ScrollView>
      <Gap h={16} />
      <Row>
        <T size={20} weight="800" numberOfLines={2} fit style={{ flex: 1 }}>{hostelTitle(h)}</T>
      </Row>
      <Row gap={4} align="flex-start" style={{ marginTop: 6 }}>
        <Icon name="location-outline" size={16} color={C.muted} />
        <T color={C.muted} style={{ flex: 1 }}>{h.address}</T>
      </Row>
      <Gap h={16} />
      <Row gap={10} align="stretch">
        <StatTile label="Monthly from" value={rupees(minRent)} sub="per bed" />
        <StatTile label="Day-wise from" value={rupees(minDay)} sub="per day" />
        <StatTile label="Beds free" value={String(countBeds('vacant'))} sub="right now" color={C.green} />
      </Row>
      <SectionTitle>Sharing</SectionTitle>
      <Row style={{ flexWrap: 'wrap' }}>{sharings.map((s) => <Pill key={s} text={`${s} sharing`} tone="grey" />)}</Row>
      <SectionTitle>Amenities</SectionTitle>
      <Row style={{ flexWrap: 'wrap' }}>{h.amenities.map((a) => <Pill key={a} text={a} icon="checkmark" />)}</Row>
      <SectionTitle>Rent & rules</SectionTitle>
      <Card>
        <InfoRow label="Rent day" value={h.rentSameAsJoining ? 'Same date as your joining day' : `Every month on day ${h.fixedRentDay}`} />
        <InfoRow label="Notice period" value={`${h.noticeDays} days before leaving`} />
        <InfoRow label="Security deposit" value="Shown with each room" />
        {h.electricitySeparate ? <InfoRow label="Electricity" value="Room meter bill, split equally" /> : null}
        {h.laundry ? <InfoRow label="Laundry" value={`${rupees(h.laundryCharge)} / month`} /> : null}
      </Card>
      <Gap />
      <Card>
        <T weight="600" style={{ marginBottom: 8 }}>House rules</T>
        {h.rules.map((r) => (
          <Row key={r} style={{ paddingVertical: 3 }}>
            <View style={{ width: 6, height: 6, borderRadius: 3, backgroundColor: C.muted }} />
            <T style={{ flex: 1 }}>{r}</T>
          </Row>
        ))}
      </Card>
      <SectionTitle>Owner contact</SectionTitle>
      <Card>
        <Row gap={12}>
          <Avatar name={app.ownerName} />
          <View style={{ flex: 1 }}>
            <T weight="600">{app.ownerName}</T>
            <T color={C.muted} selectable>+91 {h.contact}</T>
          </View>
        </Row>
      </Card>
    </Screen>
  );
}

// ======================================================================
// 2. Available rooms (Step 2 of 4)
// ======================================================================
export function AvailableRooms() {
  const nav = useNav();
  useApp();
  const [filter, setFilter] = useState('All');
  const [pick, setPick] = useState(null); // { room, bed }
  const sharings = [...new Set(app.rooms.map((r) => r.sharing))].sort((a, b) => a - b);
  const rooms = app.rooms.filter((r) => filter === 'All' || `${r.sharing} sharing` === filter);

  const legend = (color, label) => (
    <Row gap={5} key={label}>
      <View style={{ width: 10, height: 10, borderRadius: 3, backgroundColor: color }} />
      <T size={12.5} color={C.muted}>{label}</T>
    </Row>
  );

  return (
    <Screen
      footer={
        <Btn
          disabled={!pick}
          title={pick ? `Hold Room ${pick.room.number} · Bed ${bedLabel(pick.bed)} & continue` : 'Select a free bed'}
          onPress={() => {
            actions.holdBed(pick.room, pick.bed);
            nav.push('YourDetails');
          }}
        />
      }
    >
      <StepHeader step={2} title="Choose your bed" subtitle="Tap a free bed. We hold it for 15 minutes while you finish." />
      <Gap h={16} />
      <Chips options={['All', ...sharings.map((s) => `${s} sharing`)]} value={filter} onChange={setFilter} />
      <Row gap={14} style={{ marginVertical: 12, flexWrap: 'wrap' }}>
        {legend(C.green, 'Free')}
        {legend(C.muted, 'Taken')}
        {legend(C.amber, 'On hold')}
        {legend(C.blue, 'Your pick')}
      </Row>
      {rooms.map((r) => {
        const full = freeBeds(r) === 0;
        return (
          <Card key={r.number} border={pick && pick.room === r ? C.blue : null} style={{ marginBottom: 10, opacity: full ? 0.5 : 1 }}>
            <Row>
              <T size={16} weight="800">Room {r.number}</T>
              <Pill text={`${r.sharing} sharing`} tone="grey" />
              <View style={{ flex: 1 }} />
              <T size={16} weight="800">{rupees(r.rent)}</T>
              <T size={12.5} color={C.muted}>/mo</T>
            </Row>
            <T size={12.5} color={C.muted} style={{ marginTop: 4 }}>Floor {r.floor} · {r.features.join(' · ')}</T>
            <Row style={{ marginTop: 12 }}>
              {r.beds.map((b, i) => {
                const mine = pick && pick.room === r && pick.bed === i;
                const color = mine ? C.blue : b === 'vacant' ? C.green : b === 'held' ? C.amber : C.muted;
                return (
                  <Pressable
                    key={i}
                    accessibilityLabel={`Room ${r.number} bed ${bedLabel(i)}`}
                    onPress={() => (b === 'vacant' ? setPick({ room: r, bed: i }) : toast(b === 'held' ? 'Someone is booking this bed right now.' : 'This bed is taken.'))}
                    style={{ width: 52, height: 46, borderRadius: 12, borderWidth: 1.4, borderColor: color, backgroundColor: mine ? C.blue : color + '1F', alignItems: 'center', justifyContent: 'center' }}
                  >
                    <Icon name="bed" size={18} color={mine ? '#fff' : color} />
                    <T size={11} weight="600" color={mine ? '#fff' : color}>{bedLabel(i)}</T>
                  </Pressable>
                );
              })}
              <View style={{ flex: 1 }} />
              <T weight="600" color={full ? C.muted : C.green}>{full ? 'Full' : `${freeBeds(r)} free`}</T>
            </Row>
          </Card>
        );
      })}
    </Screen>
  );
}

// ======================================================================
// 3. Your details (Step 3 of 4)
// ======================================================================
const roomEntryOn = () => !!(app.hostels[0].tenantRoomEntry && !app.draft.booked);

function detailsReady(d) {
  const digits = (v) => (v || '').replace(/\D/g, '');
  const idDigits = d.idNumber.replace(/\s/g, '');
  const idOk = d.idType === 'Aadhaar' ? /^\d{12}$/.test(idDigits) : idDigits.length >= 6;
  const roomOk = !roomEntryOn() || (d.roomNo.trim().length >= 1 && d.roomFloor !== '' && roomMatchesFloor(d.roomNo, d.roomFloor) && d.roomSharing > 0 && digits(d.roomPrice).length >= 3);
  return roomOk && d.name.trim().length >= 2 && idOk && d.homeAddress.trim().length >= 5 && d.parentName.trim().length >= 2 &&
    digits(d.parent).length === 10 && (!d.reference || digits(d.reference).length === 10) && d.org.trim().length >= 2 &&
    d.idUploaded && d.acceptRules && d.consent;
}

function PhotoPen({ onPress, initialsText }) {
  const d = app.draft;
  return (
    <Pressable onPress={onPress} accessibilityLabel="Profile photo" style={{ alignSelf: 'center', width: 92, height: 92 }}>
      <View style={{ width: 92, height: 92, borderRadius: 46, alignItems: 'center', justifyContent: 'center', backgroundColor: d.photoUploaded ? C.green : initialsText ? '#1560BD' : '#E3E6EE' }}>
        {d.photoUploaded ? <Icon name="happy" size={46} color="#fff" /> : initialsText ? <T size={24} weight="800" color="#fff">{initialsText}</T> : <Icon name="person" size={46} color="#8B93A7" />}
      </View>
      <View style={{ position: 'absolute', right: 0, bottom: 2, width: 30, height: 30, borderRadius: 15, backgroundColor: '#1560BD', borderWidth: 3, borderColor: C.ground, alignItems: 'center', justifyContent: 'center' }}>
        <Icon name="pencil" size={13} color="#fff" />
      </View>
    </Pressable>
  );
}

/** Small upload tile used side by side (ID copy · Your photo). */
function UploadTile({ icon, label, done, onPress }) {
  return (
    <Pressable onPress={onPress} accessibilityLabel={label} style={{ flex: 1, borderRadius: 12, borderWidth: 1.4, borderStyle: done ? 'solid' : 'dashed', borderColor: done ? C.green : '#B9C3D3', backgroundColor: done ? C.greenSoft : '#fff', paddingVertical: 14, alignItems: 'center', gap: 4 }}>
      <Icon name={done ? 'checkmark-circle' : icon} size={24} color={done ? C.green : C.blue} />
      <T size={12.5} weight="600" color={done ? C.green : C.ink}>{done ? `${label} added` : label}</T>
      <T size={11} color={C.muted}>{done ? 'Tap to change' : 'Tap to add'}</T>
    </Pressable>
  );
}

const SectionHead = ({ icon, title }) => (
  <Row gap={6} style={{ marginTop: 18, marginBottom: 8 }}>
    <Icon name={icon} size={18} color={C.blue} />
    <T size={14} weight="600">{title}</T>
  </Row>
);

/** Student Details Entry: Joining → Your room (Phase 1) → About you → ID proof → Address → consent. */
export function YourDetails() {
  const nav = useNav();
  const d = app.draft;
  const [, refresh] = useState(0);
  const [otherId, setOtherId] = useState(d.idType !== 'Aadhaar');
  const set = (k, v) => {
    d[k] = v;
    refresh((x) => x + 1);
  };
  const roomOn = roomEntryOn();
  const ready = detailsReady(d);
  const fillSample = () => {
    Object.assign(d, { name: 'Rohith Sharma', parentName: 'Mr. Ramesh Sharma', parent: '94949 49494', referenceName: 'Mr. Vivek Singh', reference: '99886 65544', idNumber: '4821 5532 4821', idLast4: '4821', idUploaded: true, photoUploaded: false, homeAddress: 'Gandhi Nagar, Vijayawada 520003', org: 'Wipro', office: 'Gachibowli, Hyderabad', acceptRules: true, consent: true });
    if (roomOn && !d.roomNo) Object.assign(d, { roomNo: '205', roomFloor: '2', roomSharing: 3, roomPrice: '6500', roomDeposit: '5000', roomLocked: false });
    refresh((x) => x + 1);
  };
  const row = (label, key, opts = {}) => (
    <View style={{ flexDirection: 'row', alignItems: opts.multiline ? 'flex-start' : 'center', paddingHorizontal: 14, paddingVertical: 4, borderBottomWidth: opts.last ? 0 : 1, borderBottomColor: '#EEF0F5' }}>
      <T size={14} weight="600" color="#475467" style={{ width: 130, paddingTop: opts.multiline ? 12 : 0 }}>{label}{opts.optional ? '' : ' *'} :</T>
      <TextInput
        value={d[key]}
        onChangeText={(v) => { set(key, v); if (key === 'idNumber') set('idLast4', v.replace(/\D/g, '').slice(-4)); }}
        placeholder={opts.ph}
        placeholderTextColor="#A3ABBD"
        keyboardType={opts.kb || 'default'}
        multiline={!!opts.multiline}
        maxLength={opts.max}
        style={{ flex: 1, fontSize: 16, ...appFont('800'), color: C.ink, paddingVertical: 10, minHeight: opts.multiline ? 60 : undefined }}
      />
    </View>
  );
  const box = { backgroundColor: '#fff', borderRadius: 16, borderWidth: 1, borderColor: C.line };
  const smallInput = (key, ph, opts = {}) => (
    <View style={{ flex: 1 }}>
      <T size={12.5} weight="600" color="#475467" style={{ marginBottom: 4 }}>{opts.label}{opts.optional ? '' : ' *'}</T>
      <View style={{ flexDirection: 'row', alignItems: 'center', backgroundColor: d.roomLocked && opts.lockable ? C.ground : '#fff', borderRadius: 12, borderWidth: 1.2, borderColor: C.line, paddingHorizontal: 12, minHeight: 46 }}>
        {opts.prefix ? <T color={C.muted} style={{ marginRight: 4 }}>{opts.prefix}</T> : null}
        {key === 'roomNo' && groundOn ? (
          <View style={{ backgroundColor: C.blueSoft, borderRadius: 8, paddingHorizontal: 7, paddingVertical: 2, marginRight: 4 }}>
            <T weight="600" color={C.blue}>G</T>
          </View>
        ) : null}
        <TextInput
          value={key === 'roomNo' && groundOn ? d.roomNo.replace(/^G/, '') : d[key]}
          editable={!(d.roomLocked && opts.lockable)}
          onChangeText={(v) => {
            if (key === 'roomNo') return roomNoTyped(v);
            const val = opts.kb === 'number-pad' ? v.replace(/\D/g, '') : v;
            set(key, val);
          }}
          placeholder={key === 'roomNo' && groundOn ? '1' : ph}
          placeholderTextColor="#A3ABBD"
          keyboardType={key === 'roomNo' && groundOn ? 'number-pad' : opts.kb || 'default'}
          maxLength={opts.max}
          style={{ flex: 1, fontSize: 16, ...appFont('800'), color: C.ink, paddingVertical: 10 }}
        />
      </View>
    </View>
  );
  // Ground floor rooms are G + a number. Typing a G picks Ground; with Ground on only digits are typed.
  const groundOn = d.roomFloor === '0';
  const roomNoTyped = (v) => {
    let val;
    if (groundOn) val = v.replace(/\D/g, '') ? 'G' + v.replace(/\D/g, '') : '';
    else if (startsWithG(v) && !startsWithG(d.roomNo)) {
      d.roomFloor = '0';
      const n = v.slice(1).replace(/\D/g, '');
      val = n ? 'G' + n : '';
    } else val = v;
    set('roomNo', val);
    actions.lookupTypedRoom(val);
    refresh((x) => x + 1);
  };
  const pickFloor = (f) => {
    // switching to Ground: a non-G number can't stay
    if (f === '0' && d.roomNo && !isGroundRoom(d.roomNo)) d.roomNo = '';
    set('roomFloor', f);
  };
  const roomFloorError = d.roomNo && d.roomFloor !== '' && !roomMatchesFloor(d.roomNo, d.roomFloor)
    ? (d.roomFloor === '0' ? 'Ground floor rooms are G + a number, like G1.' : 'G rooms are on the ground floor. Pick Ground or change the room number.')
    : null;
  const submitTitle = d.existing ? 'Send to owner for approval' : 'Save & continue';
  return (
    <Screen
      footer={
        <View>
          <Btn title={roomOn ? submitTitle : 'Save & Submit'} disabled={!ready} onPress={() => (ready ? nav.push('StudentProfile') : toast('Fill all * fields to continue.'))} />
          {!ready ? <T size={12.5} color={C.muted} center style={{ marginTop: 6 }}>Enabled when all * fields are filled</T> : null}
        </View>
      }
    >
      <StepHeader step={2} total={shortFlow() ? 4 : 5} title="Your details" subtitle="Shared only with your hostel owner." />
      <Gap h={12} />
      {d.booked ? <HoldBanner /> : (
        <>
          <Chips options={['New joiner', 'Already staying here']} value={d.existing ? 'Already staying here' : 'New joiner'} onChange={(v) => set('existing', v !== 'New joiner')} />
          {d.existing ? (
            <View style={{ ...box, padding: 12, marginTop: 10 }}>
              <T size={12.5} weight="600" color="#475467" style={{ marginBottom: 8 }}>Joined on *</T>
              <DateStepper date={d.joinDate} max={new Date()} onChange={(v) => set('joinDate', v)} />
            </View>
          ) : null}
        </>
      )}

      {roomOn ? (
        <>
          <SectionHead icon="bed-outline" title="Your room" />
          <View style={{ ...box, padding: 12, borderColor: C.blue + '55' }}>
            <Row gap={10} align="flex-start">
              {smallInput('roomNo', '204', { label: 'Room no.', max: 6 })}
              <View style={{ flex: 1.4 }}>
                <T size={12.5} weight="600" color="#475467" style={{ marginBottom: 4 }}>Floor *</T>
                <FloorPicker value={d.roomFloor} locked={d.roomLocked} onChange={pickFloor} />
              </View>
            </Row>
            {roomFloorError ? <T size={12.5} color={C.red} style={{ marginTop: 6 }}>{roomFloorError}</T> : null}
            <T size={12.5} weight="600" color="#475467" style={{ marginTop: 12, marginBottom: 6 }}>Sharing *</T>
            <SharingPicker value={d.roomSharing} locked={d.roomLocked} onChange={(n) => set('roomSharing', n)} />
            <Row gap={10} align="flex-start" style={{ marginTop: 12 }}>
              {smallInput('roomPrice', '6500', { label: 'Monthly price', prefix: '₹', kb: 'number-pad', max: 6, lockable: true })}
              {smallInput('roomDeposit', 'Empty if none', { label: 'Deposit', prefix: '₹', kb: 'number-pad', max: 6, optional: true, lockable: true })}
            </Row>
            {d.roomLocked ? (
              <Row gap={6} style={{ marginTop: 10 }}>
                <Icon name="lock-closed-outline" size={15} color={C.green} />
                <T size={12.5} color={C.green} style={{ flex: 1 }}>Your hostel has already set this room. Details filled in for you.</T>
              </Row>
            ) : (
              <T size={12.5} color={C.muted} style={{ marginTop: 10 }}>Your owner will check these room details.</T>
            )}
          </View>
        </>
      ) : null}

      <SectionHead icon="person-outline" title="About you" />
      <View style={box}>
        {row('Full name', 'name', { ph: 'Rohith Sharma' })}
        <View style={{ flexDirection: 'row', alignItems: 'center', paddingHorizontal: 14, paddingVertical: 12, borderBottomWidth: 1, borderBottomColor: '#EEF0F5' }}>
          <T size={14} weight="600" color="#475467" style={{ width: 130 }}>Mobile * :</T>
          <T weight="600" color={C.green} style={{ flex: 1 }}>+91 {d.mobile || '98765 43210'}</T>
          <Icon name="checkmark-circle" size={18} color={C.green} />
        </View>
        {row('Parent name', 'parentName', { ph: 'Mr. Ramesh Sharma' })}
        {row('Parent number', 'parent', { ph: '+91', kb: 'phone-pad', max: 11 })}
        {row('Reference name', 'referenceName', { ph: 'optional', optional: true })}
        {row('Reference number', 'reference', { ph: 'optional', kb: 'phone-pad', max: 11, optional: true, last: true })}
      </View>

      <SectionHead icon="card-outline" title="ID proof" />
      {otherId ? <><Chips options={['Aadhaar', 'Passport', 'Driving licence']} value={d.idType} onChange={(v) => set('idType', v)} /><Gap h={10} /></> : null}
      <View style={box}>
        {row(`${d.idType} number`, 'idNumber', { ph: d.idType === 'Aadhaar' ? '12-digit number' : 'A1234567', kb: d.idType === 'Aadhaar' ? 'number-pad' : 'default', max: 14, last: true })}
      </View>
      <T size={12.5} color={C.muted} style={{ marginTop: 4 }}>Stored safely. Only the last 4 digits are shown.</T>
      {!otherId ? <Btn small variant="text" title="No Aadhaar? Use another ID" onPress={() => setOtherId(true)} style={{ alignSelf: 'flex-start' }} /> : <Gap h={10} />}
      <Row gap={10} align="stretch">
        <UploadTile icon="cloud-upload-outline" label={`${d.idType} copy *`} done={d.idUploaded} onPress={() => set('idUploaded', !d.idUploaded)} />
        <UploadTile icon="camera-outline" label="Your photo" done={d.photoUploaded} onPress={() => set('photoUploaded', !d.photoUploaded)} />
      </Row>

      <SectionHead icon="home-outline" title="Address" />
      <View style={box}>
        {row('Home address', 'homeAddress', { ph: 'House no, street, city, PIN', multiline: true })}
        {row('College / office', 'org', { ph: 'Name' })}
        {row('College / office address', 'office', { ph: 'optional', optional: true, last: true })}
      </View>

      <SectionTitle>House rules</SectionTitle>
      <Card padding={12}>
        {(app.hostels[0].rules || []).slice(0, 5).map((rule, k) => (
          <T key={k} size={12.5} color={C.ink} style={{ lineHeight: 19 }}>• {rule}</T>
        ))}
        <T size={12.5} color={C.muted} style={{ marginTop: 6, lineHeight: 19 }}>
          Give {app.hostels[0].noticeDays} days’ notice before leaving. Without notice, the deposit and that month’s rent are not refunded.
        </T>
      </Card>
      <Gap h={8} />
      <CheckRow value={d.acceptRules} onChange={(v) => set('acceptRules', v)} label="I have read and accept the house rules" />
      <CheckRow value={d.consent} onChange={(v) => set('consent', v)} label="I agree that this hostel can store my details and ID for my stay, as per the privacy policy (DPDP Act 2023)." />
      <Btn variant="text" title="Prototype: fill sample details" onPress={fillSample} />
    </Screen>
  );
}

/** Student Profile (Student App folder design): check details, View Aadhaar, Save & Select Room / continue to payment. */
export function StudentProfile() {
  const nav = useNav();
  const d = app.draft;
  const row = (l, v, col) => (
    <View key={l} style={{ paddingVertical: 11, paddingHorizontal: 14, borderBottomWidth: 1, borderBottomColor: '#EEF0F5', flexDirection: col ? 'column' : 'row', justifyContent: 'space-between', gap: col ? 2 : 10 }}>
      <T color={C.muted}>{l}</T>
      <T weight="600" style={col ? null : { flexShrink: 1, textAlign: 'right' }}>{v}</T>
    </View>
  );
  const ini = d.name.trim().split(/\s+/).filter(Boolean).slice(0, 2).map((x) => x[0]).join('').toUpperCase();
  const roomOn = roomEntryOn();
  const next = () => {
    if (roomOn) actions.useTypedRoom(); // Phase 1: the typed room, no room selection
    else if (!d.booked) return nav.push('RoomSelection');
    if (d.existing) {
      actions.submitJoining();
      return nav.resetTo('Submitted', { existing: true });
    }
    nav.push('StayPayment');
  };
  return (
    <Screen footer={<Btn icon={d.booked || roomOn ? null : 'save-outline'} title={roomOn && d.existing ? 'Send to owner for approval' : d.booked || roomOn ? 'Save & continue to payment' : 'Save & Select Room'} onPress={next} />}>
      <StepHeader step={2} total={shortFlow() ? 4 : 5} title="Student Profile" subtitle="Check your details." />
      <Gap h={14} />
      <PhotoPen onPress={() => nav.pop()} initialsText={ini} />
      <T size={20} weight="800" center style={{ marginTop: 8 }}>{d.name}</T>
      <Gap h={10} />
      <Card padding={0}>
        {row('Full name', d.name)}
        {d.existing ? row('Joined on', fmtDate(d.joinDate)) : null}
        {roomOn ? row('Room', `${d.roomNo} · ${floorText(d.roomFloor)} · ${d.roomSharing} sharing`) : null}
        {roomOn ? row('Monthly price · deposit', `${rupees(parseInt(d.roomPrice, 10) || 0)} · ${d.roomDeposit ? rupees(parseInt(d.roomDeposit, 10)) : 'None'}`) : null}
        {row(`${d.idType} number`, `•••• •••• ${d.idLast4}`)}
        {row('Parent name', d.parentName)}
        {row('Parent number', `+91 ${d.parent}`)}
        {d.referenceName ? row('Reference name', d.referenceName) : null}
        {d.reference ? row('Reference number', `+91 ${d.reference}`) : null}
        {row('Address', d.homeAddress, true)}
        {row('College / office', [d.org, d.office].filter(Boolean).join(' · '), true)}
      </Card>
      <Gap h={12} />
      <Btn variant="outline" icon="eye-outline" title={`View ${d.idType} card`} onPress={() => toast(`Prototype: the ${d.idType} photo opens here.`)} />
      <Btn variant="text" icon="create-outline" title="Edit details" onPress={() => nav.pop()} />
    </Screen>
  );
}

/** Room Selection (Student App folder design) — only when the student scanned the hostel QR. */
export function RoomSelection() {
  const nav = useNav();
  const d = app.draft;
  const [floor, setFloor] = useState('All');
  const [sharing, setSharing] = useState('All');
  const [room, setRoom] = useState(null);
  const [bed, setBed] = useState(-1);
  const [agree, setAgree] = useState(false);
  const floors = ['All', ...[...new Set(app.rooms.map((r) => r.floor))].sort((a, b) => a - b).map(String)];
  const sharings = ['All', ...[...new Set(app.rooms.map((r) => r.sharing))].sort((a, b) => a - b).map(String)];
  const shown = app.rooms.filter((r) => (floor === 'All' || String(r.floor) === floor) && (sharing === 'All' || String(r.sharing) === sharing));
  const freeIdx = (r) => r.beds.map((b, i) => (b === 'vacant' ? i : -1)).filter((i) => i >= 0);
  const pick = (r) => { setRoom(r); setBed(freeIdx(r)[0]); };
  return (
    <Screen
      footer={
        <Btn
          title={room ? 'Confirm and proceed to payment' : 'Pick a room'}
          disabled={!room || !agree}
          style={{ backgroundColor: C.green, borderColor: C.green }}
          onPress={() => {
            if (!room || !agree) return;
            actions.holdBed(room, bed);
            if (d.existing) {
              actions.submitJoining();
              return nav.resetTo('Submitted', { existing: true });
            }
            nav.push('StayPayment');
          }}
        />
      }
    >
      <StepHeader step={3} total={5} title="Room Selection" subtitle="Pick a free room. It's held for 15 minutes while you pay." />
      <Gap h={12} />
      <T size={12.5} weight="400" color={C.muted}>FLOOR</T>
      <Chips options={floors} value={floor} onChange={setFloor} />
      <Gap h={8} />
      <T size={12.5} weight="400" color={C.muted}>SHARING</T>
      <Chips options={sharings} value={sharing} onChange={setSharing} />
      <Gap h={12} />
      <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 8 }}>
        {shown.map((r) => {
          const open = freeIdx(r).length > 0;
          const sel = room && room.number === r.number;
          return (
            <Pressable key={r.number} disabled={!open} onPress={() => pick(r)} style={{ width: '23%', paddingVertical: 12, borderRadius: 12, alignItems: 'center', borderWidth: 1.5, borderColor: sel ? '#1560BD' : open ? '#B7E4CB' : '#F0F1F5', backgroundColor: sel ? '#1560BD' : open ? '#fff' : '#F0F1F5' }}>
              <T weight="600" color={sel ? '#fff' : open ? '#0E5C3E' : '#B0B6C4'} style={open ? null : { textDecorationLine: 'line-through' }}>{r.number}</T>
            </Pressable>
          );
        })}
      </View>
      {room ? (
        <>
          <View style={{ backgroundColor: '#E8F0FA', borderRadius: 12, padding: 12, marginTop: 12 }}>
            <Row>
              <T size={16} weight="800" style={{ flex: 1 }}>Room {room.number} · Bed {bedLabel(bed)}</T>
              <Pill text="Selected" tone="green" />
            </Row>
            <T size={12.5} color={C.muted}>{room.sharing} sharing · {freeIdx(room).length} beds free · Floor {room.floor}</T>
            {freeIdx(room).length > 1 ? (
              <Row gap={6} style={{ marginTop: 8, flexWrap: 'wrap' }}>
                {freeIdx(room).map((i) => (
                  <Pressable key={i} onPress={() => setBed(i)} style={{ paddingHorizontal: 12, paddingVertical: 6, borderRadius: 99, backgroundColor: bed === i ? '#1560BD' : '#fff' }}>
                    <T size={12.5} weight="600" color={bed === i ? '#fff' : C.ink}>Bed {bedLabel(i)}</T>
                  </Pressable>
                ))}
              </Row>
            ) : null}
          </View>
          <Card style={{ marginTop: 10 }}>
            <T weight="600" style={{ marginBottom: 6 }}>Fee details · Room {room.number}</T>
            <InfoRow label="Rent (monthly)" value={rupees(room.rent)} />
            <InfoRow label="Security deposit (one-time)" value={rupees(room.deposit)} />
            <Divider />
            <InfoRow label="First payment" value={rupees(room.rent + room.deposit)} bold color={C.green} />
            <InfoRow label="Every month after" value={rupees(room.rent)} />
          </Card>
          <Gap h={8} />
          <CheckRow value={agree} onChange={setAgree} label="I agree to the Terms & Conditions and hostel policies" />
        </>
      ) : null}
    </Screen>
  );
}

// ======================================================================
// 4. Stay & payment (Step 4 of 4)
// ======================================================================
function PayOption({ value, group, title, sub, icon, onPress, instant }) {
  const sel = value === group;
  return (
    <Card onPress={onPress} border={sel ? C.blue : C.line} padding={12} style={{ marginBottom: 8 }}>
      <Row gap={12}>
        <IconBox name={icon} size={38} />
        <View style={{ flex: 1 }}>
          <Row gap={6}>
            <T weight="600">{title}</T>
            {instant ? <Pill text="Instant" tone="green" /> : null}
          </Row>
          <T size={12.5} color={C.muted}>{sub}</T>
        </View>
        <Icon name={sel ? 'radio-button-on' : 'radio-button-off'} color={sel ? C.blue : C.muted} />
      </Row>
    </Card>
  );
}

export function StayPayment() {
  const nav = useNav();
  const d = app.draft;
  const h = app.hostels[0];
  const r = d.room;
  const [, refresh] = useState(0);
  const set = (k, v) => {
    d[k] = v;
    refresh((x) => x + 1);
  };
  const [utr, setUtr] = useState('');
  const [utrError, setUtrError] = useState(null);

  if (!r) {
    return (
      <Screen title="Stay & payment">
        <T>Choose a bed first.</T>
      </Screen>
    );
  }

  const checkIn = new Date();
  const rentDay = h.rentSameAsJoining ? checkIn.getDate() : h.fixedRentDay;
  const note = `SUNRISE-${r.number}${bedLabel(d.bedIndex)}-JOIN`;

  const finish = () => {
    actions.submitJoining();
    nav.resetTo('Submitted', { online: d.payMethod === 'online' });
  };

  const submit = () => {
    if (!d.agreedRefund) {
      toast('Please read the refund rule and tick "I agree".');
      return;
    }
    if (d.payMethod === 'online') {
      showSheet((close) => (
        <View style={{ gap: 10 }}>
          <T size={20} weight="800">Payment gateway (simulated)</T>
          <T color={C.muted}>Paying {rupees(joiningTotal())} to {hostelTitle(h)}</T>
          <Gap h={6} />
          <Btn title="Payment succeeds" onPress={() => { close(); finish(); }} />
          <Btn variant="outline" title="Test: payment fails" onPress={() => { close(); nav.push('PaymentFailed'); }} />
          <Btn variant="outline" title="Test: bed got taken while paying" onPress={() => { close(); nav.push('BedTaken'); }} />
        </View>
      ));
      return;
    }
    if (d.payMethod === 'upi' || d.payMethod === 'bank') {
      if (utr.length !== 12) {
        setUtrError('UTR / reference number is 12 digits. Find it in your UPI app under payment details.');
        return;
      }
      if (utr === DUPLICATE_UTR) {
        setUtrError('This UTR was already used for another payment. Check the number and try again.');
        return;
      }
      d.utr = utr;
    }
    finish();
  };

  // 25 Oct 2026: tap a UPI app (amount + note filled) → receipt → checks. Cash is a small link.
  const payUpi = (appName) => {
    if (!d.agreedRefund) return toast('Please read the refund rule and tick "I agree".');
    d.payMethod = 'upi';
    openUpiApp(appName, joiningTotal(), note, (res) => nav.push('UpiReceipt', { purpose: 'join', amount: joiningTotal(), note, ...res }));
  };
  const payBank = () => {
    if (!d.agreedRefund) return toast('Please read the refund rule and tick "I agree".');
    d.payMethod = 'bank';
    nav.push('UpiReceipt', { purpose: 'join', amount: joiningTotal(), note, app: 'Bank transfer', bank: true, fromApp: false, utr: '', seconds: 60 });
  };

  return (
    <Screen footer={d.payMethod === 'cash' ? <Btn title="Confirm – I will pay cash" onPress={submit} /> : null}>
      <StepHeader step={shortFlow() ? 3 : 4} total={shortFlow() ? 4 : 5} title="Choose payment" />
      <Gap h={14} />
      {r.fromTenant ? null : <HoldBanner />}
      <SectionTitle>How long are you staying?</SectionTitle>
      {h.allowDayWise ? (
        <Segmented
          options={[{ value: 'monthly', label: 'Monthly', icon: 'calendar' }, { value: 'dayWise', label: 'Day-wise', icon: 'today' }]}
          value={d.stayType}
          onChange={(v) => set('stayType', v)}
        />
      ) : null}
      <Gap h={12} />
      <Card>
        <InfoRow label="Check-in" value={fmtDate(checkIn)} />
        {d.stayType === 'monthly' ? (
          <InfoRow label="Rent day" value={`Every month on the ${ordinal(rentDay)}`} />
        ) : (
          <>
            <View style={{ paddingVertical: 6 }}>
              <Stepper label="Days" value={d.days} onChange={(v) => set('days', v)} />
            </View>
            <InfoRow label="Check-out" value={fmtDate(addDays(checkIn, d.days))} />
          </>
        )}
      </Card>
      <SectionTitle>Amount to pay now</SectionTitle>
      <Card>
        <InfoRow label={`Room ${r.number} · Bed ${bedLabel(d.bedIndex)}`} value={`${r.sharing} sharing`} />
        <Divider />
        {d.stayType === 'monthly' ? (
          <InfoRow label="First month rent" value={rupees(r.rent)} />
        ) : (
          <InfoRow label={`${d.days} days × ${rupees(r.perDay)}`} value={rupees(r.perDay * d.days)} />
        )}
        <InfoRow label={d.stayType === 'monthly' ? 'Security deposit' : 'Day-wise deposit'} value={rupees(joiningDeposit())} />
        <Divider />
        <InfoRow label="Total" value={rupees(joiningTotal())} bold />
      </Card>
      <Gap h={12} />
      <Card bg={C.amberSoft}>
        <Row>
          <Icon name="information-circle-outline" color={C.amber} />
          <T weight="600" color={C.amber}>Refund rule</T>
        </Row>
        <T style={{ marginTop: 6, lineHeight: 20 }}>Give {h.noticeDays} days’ notice before leaving. If you leave without notice, the deposit and that month’s rent are not refunded.</T>
        <CheckRow value={d.agreedRefund} onChange={(v) => set('agreedRefund', v)} label="I agree" />
      </Card>
      <SectionTitle>Pay {rupees(joiningTotal())} – tap your UPI app</SectionTitle>
      <T size={12.5} weight="600" color={C.green} style={{ marginTop: -4, marginBottom: 10 }}>Paid straight to the owner · no extra charges · amount is filled in</T>
      {h.payUpi !== false ? <UpiTiles onPick={payUpi} /> : null}
      <Gap h={10} />
      {h.payUpi !== false ? (
        <Card onPress={() => showSheet(() => <QrSheet amount={joiningTotal()} note={note} />)} padding={12} style={{ marginBottom: 8 }}>
          <Row><T weight="600" color={C.blue} style={{ flex: 1 }}>Paying from another phone? Show QR</T><Icon name="chevron-forward" color={C.blue} /></Row>
        </Card>
      ) : null}
      {h.payCash ? (
        <Card onPress={() => set('payMethod', d.payMethod === 'cash' ? 'upi' : 'cash')} border={d.payMethod === 'cash' ? C.blue : C.line} padding={12} style={{ marginBottom: 8 }}>
          <Row><T weight="600" color={C.blue} style={{ flex: 1 }}>Pay cash at the office</T><Icon name={d.payMethod === 'cash' ? 'radio-button-on' : 'chevron-forward'} color={C.blue} /></Row>
          {d.payMethod === 'cash' && h.cashNote ? <T size={12.5} style={{ marginTop: 6, lineHeight: 19 }}>{h.cashNote}</T> : null}
        </Card>
      ) : null}
      {h.payBank ? (
        <Card onPress={payBank} padding={12}>
          <Row><T weight="600" color={C.blue} style={{ flex: 1 }}>Bank transfer</T><Icon name="chevron-forward" color={C.blue} /></Row>
        </Card>
      ) : null}
    </Screen>
  );
}

// ======================================================================
// Booking status (25 Oct 2026): a new joiner waits for the owner to confirm details + payment.
// The bed is kept for him meanwhile (nobody else can book it). Call owner to ask for a faster OK.
// Rejected: reason from the owner, bed free for others, money returned by the owner.
// ======================================================================
export function callOwner() {
  const h = app.hostels[0];
  const num = (h.contact || app.ownerMobile || '').replace(/\D/g, '');
  Linking.openURL(`tel:+91${num}`).catch(() => toast(`Owner: +91 ${h.contact || app.ownerMobile}`));
}

function StatusStep({ state, title, sub, last }) {
  const done = state === 'done';
  const now = state === 'now';
  return (
    <Row gap={12} align="flex-start">
      <View style={{ alignItems: 'center' }}>
        <View style={{ width: 24, height: 24, borderRadius: 12, alignItems: 'center', justifyContent: 'center',
          backgroundColor: done ? C.green : now ? C.amberSoft : '#fff', borderWidth: done ? 0 : 2, borderColor: now ? C.amber : C.line }}>
          {done ? <Icon name="checkmark" size={15} color="#fff" /> : now ? <View style={{ width: 8, height: 8, borderRadius: 4, backgroundColor: C.amber }} /> : null}
        </View>
        {last ? null : <View style={{ width: 3, height: 26, backgroundColor: done ? C.green : C.line }} />}
      </View>
      <View style={{ flex: 1, paddingBottom: last ? 0 : 6 }}>
        <T size={14} weight="600" color={now ? C.amber : done ? C.ink : C.muted}>{title}</T>
        <T size={12} color={C.muted}>{sub}</T>
      </View>
    </Row>
  );
}

export function BookingStatus() {
  const nav = useNav();
  const s = app.stay;
  const rej = s.rejected;
  if (rej) {
    return (
      <View>
        <Card bg={C.redSoft} border="#F3B4B4">
          <Row gap={12}>
            <View style={{ width: 36, height: 36, borderRadius: 18, backgroundColor: C.red, alignItems: 'center', justifyContent: 'center' }}>
              <Icon name="close" size={22} color="#fff" />
            </View>
            <View style={{ flex: 1 }}>
              <T size={16} weight="800" color={C.red}>Booking not confirmed</T>
              <T size={12.5} color="#991B1B">Bed {rej.room} {rej.bed} is free for others again</T>
            </View>
          </Row>
          <View style={{ backgroundColor: '#fff', borderRadius: 10, padding: 12, marginTop: 12 }}>
            <T size={11} color={C.muted}>Reason from owner</T>
            <T size={15} weight="800">{rej.reason}</T>
          </View>
          <T size={13} weight="600" style={{ marginTop: 12 }}>Your money ({rupees(rej.amount)}) will be returned by the owner.</T>
        </Card>
        <Gap h={14} />
        <Row gap={10}>
          <Btn style={{ flex: 1 }} variant="outline" icon="call-outline" title="Call owner" onPress={callOwner} />
          <Btn style={{ flex: 1 }} title="Pick another bed" onPress={() => {
            actions.startStudentFlow();
            Object.assign(app.draft, { mobile: s.mobile, verified: true });
            nav.push('AvailableRooms');
          }} />
        </Row>
      </View>
    );
  }
  return (
    <View>
      <Card bg={C.amberSoft} border="#F3D19C">
        <Row gap={12}>
          <View style={{ width: 36, height: 36, borderRadius: 18, backgroundColor: C.amber, alignItems: 'center', justifyContent: 'center' }}>
            <Icon name="hourglass-outline" size={20} color="#fff" />
          </View>
          <View style={{ flex: 1 }}>
            <T size={16} weight="800" color={C.amber}>Waiting for owner</T>
            <T size={12.5} color="#92400E">Owner must check your details & payment</T>
          </View>
        </Row>
        <View style={{ backgroundColor: '#fff', borderRadius: 10, paddingVertical: 8, paddingHorizontal: 12, marginTop: 12 }}>
          <T size={12.5} weight="600">Room {s.room} · Bed {s.bed} · kept for you</T>
        </View>
      </Card>
      <Gap h={12} />
      <Card>
        <T size={11} weight="600" color={C.muted} style={{ marginBottom: 10, letterSpacing: 0.5 }}>STATUS</T>
        <StatusStep state="done" title="Details sent" sub="Name, mobiles, Aadhaar, photo" />
        <StatusStep state="done" title="Payment sent" sub={`${rupees(s.paidTotal || 0)} by ${s.payMethod || 'UPI'}${s.utr ? ` · UTR ${s.utr}` : ''}`} />
        <StatusStep state="now" title="Owner confirming" sub="Details + payment check" />
        <StatusStep state="next" title="Bed booked" sub="You get a message" last />
      </Card>
      <Gap h={12} />
      <Card bg={C.blueSoft} border="#B9CDEB">
        <T size={14} weight="800">Want it confirmed faster?</T>
        <T size={12.5} color={C.muted} style={{ marginTop: 2, marginBottom: 12 }}>Call the owner and ask him to confirm.</T>
        <Btn icon="call-outline" title="Call owner" onPress={callOwner} />
      </Card>
      <Gap h={12} />
      <Card>
        <Row>
          <T size={12.5} color={C.muted} style={{ flex: 1 }}>Paid (rent + deposit)</T>
          <T size={15} weight="800">{rupees(s.paidTotal || 0)}</T>
        </Row>
        <T size={11.5} color={C.muted} style={{ marginTop: 4 }}>If not confirmed, the owner returns your money.</T>
      </Card>
    </View>
  );
}

// ======================================================================
// 5. Payment submitted / sent to owner
// ======================================================================
export function Submitted({ params }) {
  const nav = useNav();
  // after paying, back must not return to the payment form: go to the status page instead
  useBackHandler(() => {
    nav.resetTo('StudentShell');
    return true;
  });
  const s = app.stay;
  const online = !!params.online;
  const existing = !!params.existing;
  // every new joiner waits for the owner's approval (then the bed is filled and the stay starts)
  const title = existing ? 'Sent to owner' : 'Booking submitted';
  const text = existing
    ? 'The owner will check your joining date and approve. You will get an SMS.'
    : online
      ? 'Payment received. The owner will approve your booking; you will get an SMS and your home page opens.'
      : 'The owner will check your payment and confirm. You will get a notification.';
  const h = app.hostels[0];
  useApp();
  if (!existing) {
    return (
      <Screen back={false} title="Your booking" footer={<Btn variant="outline" title="Go to Home" onPress={() => nav.resetTo('StudentShell')} />}>
        <BookingStatus />
      </Screen>
    );
  }
  return (
    <Screen back={false}>
      <Gap h={24} />
      <View style={{ alignSelf: 'center', width: 88, height: 88, borderRadius: 44, backgroundColor: C.amberSoft, alignItems: 'center', justifyContent: 'center' }}>
        <Icon name="hourglass-outline" size={46} color={C.amber} />
      </View>
      <T size={24} weight="800" center style={{ marginTop: 20 }}>{title}</T>
      <T color={C.muted} center style={{ marginTop: 8, lineHeight: 20 }}>{text}</T>
      <Gap h={24} />
      <Card>
        <InfoRow label="Room" value={`${s.room} · Bed ${s.bed} · ${s.sharing} sharing`} />
        <InfoRow label="Date of joining" value={fmtDate(new Date())} />
        {!existing ? <InfoRow label="Next fee date" value={fmtDate(addDays(new Date(), 30))} /> : null}
        {!existing ? <InfoRow label="Amount paid" value={rupees(joiningTotal())} bold /> : null}
        <InfoRow label="Status" value="Owner will confirm" color={C.amber} />
      </Card>
      <Gap h={12} />
      <Card bg={C.amberSoft}>
        <Row gap={10} align="flex-start">
          <Icon name="shield-checkmark-outline" color={C.amber} />
          <T style={{ flex: 1, lineHeight: 20 }}>Waiting for the owner to verify. Your home page shows the status; you get a notification once confirmed.</T>
        </Row>
      </Card>
      <Gap h={24} />
      <Btn title="Go to Home" onPress={() => nav.resetTo('StudentShell')} />
    </Screen>
  );
}

// ======================================================================
// Extend stay (day-wise)
// ======================================================================
export function ExtendStay() {
  const nav = useNav();
  const s = app.stay;
  const [days, setDays] = useState(3);
  const [monthly, setMonthly] = useState(false);
  const pay = monthly ? s.rent + 5500 : days * s.perDay;
  return (
    <Screen
      title="Extend stay"
      footer={
        <Btn
          title={monthly ? `Pay ${rupees(pay)} & switch` : `Pay ${rupees(pay)} to confirm`}
          onPress={() => {
            if (!monthly) actions.extendStay(days);
            nav.pop();
            toast(monthly ? 'Request to switch to monthly sent to owner.' : `Stay extended by ${days} days. Receipt sent.`);
          }}
        />
      }
    >
      <Card bg={C.blueSoft}>
        <Row gap={10} align="flex-start">
          <Icon name="notifications" color={C.blue} />
          <T style={{ flex: 1, lineHeight: 20 }}>Reminder: your stay ends on {s.checkOut}. Extend now to keep your bed.</T>
        </Row>
      </Card>
      <Gap h={14} />
      <Segmented options={[{ value: false, label: 'Add days' }, { value: true, label: 'Switch to monthly' }]} value={monthly} onChange={setMonthly} />
      <Gap h={14} />
      <Card>
        {monthly ? (
          <>
            <InfoRow label="Monthly rent" value={rupees(s.rent)} />
            <InfoRow label="Extra deposit" value="₹5,500" />
            <Divider />
            <InfoRow label="Pay now" value={rupees(pay)} bold />
          </>
        ) : (
          <>
            <Stepper label="Extra days" value={days} onChange={setDays} />
            <Divider />
            <InfoRow label={`${days} days × ${rupees(s.perDay)}`} value={rupees(days * s.perDay)} />
            <InfoRow label="Pay now" value={rupees(pay)} bold />
          </>
        )}
      </Card>
    </Screen>
  );
}

// ======================================================================
// Error screens
// ======================================================================
function ErrorPage({ icon, color, bg, title, text, primary, onPrimary, secondary, onSecondary }) {
  return (
    <Screen footer={
      <>
        <Btn title={primary} onPress={onPrimary} />
        {secondary ? <Btn variant="outline" title={secondary} onPress={onSecondary} /> : null}
      </>
    }>
      <View style={{ alignItems: 'center', paddingTop: 60, paddingHorizontal: 12 }}>
        <View style={{ width: 96, height: 96, borderRadius: 48, backgroundColor: bg, alignItems: 'center', justifyContent: 'center' }}>
          <Icon name={icon} size={48} color={color} />
        </View>
        <T size={24} weight="800" center style={{ marginTop: 20 }}>{title}</T>
        <T color={C.muted} center style={{ marginTop: 8, lineHeight: 21 }}>{text}</T>
      </View>
    </Screen>
  );
}

export function PaymentFailed() {
  const nav = useNav();
  return (
    <ErrorPage
      icon="alert-circle-outline" color={C.red} bg={C.redSoft}
      title="Payment failed"
      text="No money was taken. If it was, it comes back to your account in 5–7 days. Your bed is still held for you."
      primary="Try again" onPrimary={() => nav.pop()}
      secondary="Pay by UPI to owner instead" onSecondary={() => { app.draft.payMethod = 'upi'; actions.touch(); nav.pop(); }}
    />
  );
}

export function BedTaken() {
  const nav = useNav();
  return (
    <ErrorPage
      icon="bed-outline" color={C.amber} bg={C.amberSoft}
      title="This bed was just taken"
      text="Your 15-minute hold ran out and someone else booked it. No money was taken. Your details are saved, so pick another bed."
      primary="Choose another bed" onPrimary={() => nav.resetTo('AvailableRooms')}
      secondary="Back" onSecondary={() => nav.pop()}
    />
  );
}

export function NoInternet() {
  const nav = useNav();
  return (
    <ErrorPage
      icon="cloud-offline-outline" color={C.muted} bg="#E6EBF2"
      title="No internet"
      text="Check your mobile data or Wi-Fi. What you typed is saved on this phone."
      primary="Try again" onPrimary={() => { nav.pop(); toast('Back online'); }}
    />
  );
}

// ======================================================================
// Prototype-only list of test screens
// ======================================================================
export function DemoScreens() {
  const nav = useNav();
  return (
    <Screen title="Test screens">
      <T color={C.muted} style={{ lineHeight: 20 }}>Prototype only. These screens appear in the real app when something goes wrong.</T>
      <Gap h={14} />
      <Card padding={0}>
        {[
          ['key-outline', 'Wrong OTP', 'Enter any OTP except 123456', () => { actions.startStudentFlow(); nav.push('VerifyMobile'); }, C.blue],
          ['alert-circle-outline', 'Payment failed', null, () => nav.push('PaymentFailed'), C.red],
          ['bed-outline', 'Bed taken while paying', null, () => nav.push('BedTaken'), C.amber],
          ['cloud-offline-outline', 'No internet', null, () => nav.push('NoInternet'), C.muted],
          ['time-outline', 'Extend stay (day-wise student)', null, () => nav.push('ExtendStay'), C.blue],
          ['search', 'Find my booking', null, () => nav.push('VerifyMobile', { findBooking: true }), C.blue],
          ['home-outline', 'Student status page (sample student)', null, () => nav.push('StudentShell'), C.blue],
        ].map(([icon, title, sub, onPress, color], i, arr) => (
          <Pressable key={title} onPress={onPress} style={{ flexDirection: 'row', alignItems: 'center', gap: 12, padding: 14, borderBottomWidth: i < arr.length - 1 ? 1 : 0, borderBottomColor: C.line }}>
            <IconBox name={icon} color={color} size={38} />
            <View style={{ flex: 1 }}>
              <T weight="600">{title}</T>
              {sub ? <T size={12.5} color={C.muted}>{sub}</T> : null}
            </View>
            <Icon name="chevron-forward" size={20} color={C.blue} />
          </Pressable>
        ))}
      </Card>
      <Gap h={12} />
      <T color={C.muted}>New hostel setup checklist: log in as owner and open “Nest Co-living”.</T>
    </Screen>
  );
}

// ======================================================================
// Privacy & legal (draft template)
// ======================================================================
const PRIVACY = [
  ['What we collect', 'Your name, mobile, parent’s mobile, addresses, photo, ID type, last 4 digits of your ID and a masked copy of it, your stay and payment details.'],
  ['Why we collect it', 'To confirm your booking, keep the hostel safe, prepare police verification if required, send rent reminders and receipts.'],
  ['Who can see it', 'Only the owner of the hostel you joined, and staff the owner allows. We never sell your data.'],
  ['How we protect it', 'ID copies are stored encrypted in a private store and opened only with short-lived links. Every time the owner reveals your ID, it is logged.'],
  ['How long we keep it', 'ID copies are deleted 3 months after you leave. Payment records are kept as long as the law requires.'],
  ['Your rights (DPDP Act 2023)', 'You can see your data, ask for corrections, ask for deletion after your stay, and withdraw consent.'],
  ['Grievance officer', '[Name] · [email] · [phone] – to be filled in before launch.'],
];
const TERMS = [
  ['Using the app', 'Owners and staff log in with their mobile and password. Students do not need an account.'],
  ['Payments', 'Online payments go through a payment gateway. UPI, bank and cash payments go directly to the owner, who confirms them.'],
  ['Notice and refunds', 'Each hostel sets its notice period. Leaving without notice means the deposit and that month’s rent are not refunded.'],
  ['Owner responsibilities', 'Owners must keep tenant data private, use it only for the stay, and follow Aadhaar rules.'],
  ['Deleting your account', 'Owners can delete their account in the app. There is a 7-day window to cancel.'],
];

export function Privacy() {
  const [tab, setTab] = useState('privacy');
  const items = tab === 'privacy' ? PRIVACY : TERMS;
  return (
    <Screen title="Privacy & legal">
      <Segmented options={[{ value: 'privacy', label: 'Privacy policy' }, { value: 'terms', label: 'Terms of use' }]} value={tab} onChange={setTab} />
      <Gap h={12} />
      <View style={{ backgroundColor: C.amberSoft, borderRadius: 12, padding: 12 }}>
        <T weight="600" color={C.amber}>Draft template. Get it checked by a lawyer before launch.</T>
      </View>
      <Gap h={12} />
      {items.map(([h, b]) => (
        <View key={h} style={{ marginBottom: 16 }}>
          <T size={16} weight="800">{h}</T>
          <T color={C.muted} style={{ marginTop: 4, lineHeight: 21 }}>{b}</T>
        </View>
      ))}
    </Screen>
  );
}

/** QR booking: the bed the owner held for this student, with rent, deposit and the hold timer. */
function BookedBedCard({ timer = true }) {
  const d = app.draft;
  const r = d.room;
  return (
    <View style={{ marginBottom: 14 }}>
      {timer ? <><HoldBanner /><Gap h={10} /></> : null}
      <Card border={C.line}>
        <Row gap={12}>
          <View style={{ width: 50, height: 50, borderRadius: 12, backgroundColor: C.greenSoft, alignItems: 'center', justifyContent: 'center' }}>
            <T size={14} weight="600" color={C.green}>{r.number}</T>
            <T size={12.5} weight="600" color={C.green}>{bedLabel(d.bedIndex)}</T>
          </View>
          <View style={{ flex: 1 }}>
            <T size={16} weight="800">Room {r.number} · Bed {bedLabel(d.bedIndex)}</T>
            <T size={12.5} color={C.muted}>{app.hostels[0].name} · {r.sharing} sharing</T>
          </View>
        </Row>
        <Gap />
        <InfoRow label="Monthly rent" value={rupees(r.rent)} />
        <InfoRow label="Deposit" value={rupees(r.deposit)} />
      </Card>
    </View>
  );
}

