// Owner: login, sign up, forgot password, my hostels, register hostel, setup checklist.
import React, { useEffect, useRef, useState } from 'react';
import { ActivityIndicator, Animated, Image, Pressable, ScrollView, TextInput, View } from 'react-native';

// App logo (24 Oct 2026): coral square, house outline with "My", "Hostel" below (Lora serif).
const APP_LOGO = require('../../assets/logo.png');
import { useNav } from '../nav';
import { showSheet, toast } from '../overlay';
import { DEMO_OTP, LANGUAGES, actions, app, cleanHostelName, hostelStats, hostelTitle, typeLabel, useApp } from '../state';
import {
  BuildingArt, ShortNameBox, HostelPhoto, hostelShortName, Btn, C, Card, Chips, Field, Gap, Icon, IconBox, LanguageButton, LanguageList, PercentRing, ProgressBar, Row, Screen, Segmented, Stepper, T,
  UploadBox, appFont, hostelColor, EmptyState,
} from '../ui';

// ======================================================================
// Owner 1. Login (app start)
// ======================================================================
/** Shown for a moment right after login (lavender), then opens My hostels by itself. Tap to skip. */
export function Welcome({ params }) {
  const nav = useNav();
  const done = useRef(false);
  const scale = useRef(new Animated.Value(0.6)).current;
  const first = (app.ownerName || '').trim().split(/\s+/)[0];
  const open = () => {
    if (done.current) return;
    done.current = true;
    nav.replace(params?.next || 'MyHostels');
  };
  useEffect(() => {
    Animated.spring(scale, { toValue: 1, friction: 5, useNativeDriver: true }).start();
    const id = setTimeout(open, 1500);
    return () => clearTimeout(id);
  }, []);
  return (
    <Pressable onPress={open} style={{ flex: 1, backgroundColor: C.blue }}>
      <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center', paddingHorizontal: 24 }}>
        <Animated.View style={{ transform: [{ scale }], width: 108, height: 108, borderRadius: 54, backgroundColor: 'rgba(255,255,255,0.18)', alignItems: 'center', justifyContent: 'center' }}>
          <View style={{ width: 84, height: 84, borderRadius: 42, backgroundColor: '#fff', alignItems: 'center', justifyContent: 'center' }}>
            <Icon name="checkmark" size={48} color={C.blue} />
          </View>
        </Animated.View>
        <T size={14} weight="600" color="#D6ECFC" style={{ marginTop: 26 }}>Logged in</T>
        <T size={24} weight="800" color="#fff" center style={{ marginTop: 6 }}>{first ? `Welcome, ${first}` : 'Welcome'}</T>
        <ActivityIndicator color="#fff" style={{ marginTop: 40 }} />
        <T size={12.5} color="#D6ECFC" style={{ marginTop: 10 }}>Opening My hostels</T>
      </View>
      <T weight="600" color="#D6ECFC" center style={{ paddingBottom: 30, letterSpacing: 0.5 }}>My Hostel</T>
    </Pressable>
  );
}

// Login (24 Oct 2026, option 4c): centred logo, mobile and password boxes with phone / lock icons,
// Forgot password, Log in, "or", Create owner account, small student line. No Owner / Staff tabs:
// the app knows a staff member from the mobile number the owner added in More → Staff.
function IconField({ icon, prefix, value, onChangeText, placeholder, keyboardType, secure, right }) {
  const [focus, setFocus] = useState(false);
  return (
    <View style={{ flexDirection: 'row', alignItems: 'center', gap: 10, minHeight: 50, borderRadius: 12, borderWidth: 1.2,
      borderColor: focus ? C.blue : C.line, backgroundColor: '#fff', paddingHorizontal: 14, marginBottom: 12 }}>
      <Icon name={icon} size={20} color={C.blue} />
      {prefix ? <T size={16} color={C.muted}>{prefix}</T> : null}
      <TextInput
        value={value}
        onChangeText={onChangeText}
        placeholder={placeholder}
        placeholderTextColor="#9AA7B8"
        keyboardType={keyboardType}
        secureTextEntry={secure}
        onFocus={() => setFocus(true)}
        onBlur={() => setFocus(false)}
        style={{ flex: 1, fontSize: 16, color: C.ink, paddingVertical: 12, ...appFont('600') }}
      />
      {right}
    </View>
  );
}

export function Login() {
  const nav = useNav();
  const [mobile, setMobile] = useState('99887 76655');
  const [password, setPassword] = useState('demo1234');
  const [show, setShow] = useState(false);

  const login = () => {
    const digits = mobile.replace(/\D/g, '');
    if (digits.length !== 10 || password.length < 6) {
      toast('Enter your 10-digit mobile and password (min 6 characters).');
      return;
    }
    // staff are known from their mobile number (added by the owner in More → Staff)
    const staff = (app.staff || []).some((x) => x.mobile.replace(/\D/g, '') === digits);
    actions.login(staff);
    nav.push('Welcome', { next: staff ? 'OwnerShell' : 'MyHostels' });
  };

  const openStudent = () => {
    // Prototype: as if the student scanned the hostel QR in the office (app not installed yet)
    actions.startStudentFlow();
    nav.push('GetApp');
  };

  // Fits on one screen (no scrolling): spacers share the free height.
  return (
    <Screen back={false} scroll={false} right={<LanguageButton onOpen={() => showSheet((close) => <LanguageList close={close} />)} />}>
      <View style={{ flex: 1, paddingHorizontal: 16, paddingBottom: 8 }}>
        <View style={{ flex: 1, maxHeight: 36 }} />
        <View style={{ alignItems: 'center' }}>
          <Image source={APP_LOGO} accessibilityLabel="My Hostel" style={{ width: 96, height: 96, borderRadius: 24 }} />
          <T size={14} color={C.muted} style={{ marginTop: 12 }}>Owner and staff login</T>
        </View>
        <View style={{ flex: 1, minHeight: 16, maxHeight: 32 }} />

        <IconField icon="call-outline" prefix="+91" placeholder="Mobile number" keyboardType="phone-pad" value={mobile} onChangeText={setMobile} />
        <IconField
          icon="lock-closed-outline"
          placeholder="Password"
          value={password}
          onChangeText={setPassword}
          secure={!show}
          right={
            <Pressable accessibilityLabel={show ? 'Hide password' : 'Show password'} onPress={() => setShow(!show)} hitSlop={10}>
              <Icon name={show ? 'eye-off-outline' : 'eye-outline'} size={20} color={C.muted} />
            </Pressable>
          }
        />
        <Row style={{ justifyContent: 'flex-end', marginTop: -4, marginBottom: 12 }}>
          <Pressable hitSlop={8} onPress={() => nav.push('ForgotPassword')}>
            <T size={14} weight="600" color={C.blue}>Forgot password?</T>
          </Pressable>
        </Row>
        <Btn title="Log in" onPress={login} />

        <Row gap={10} style={{ marginVertical: 14 }}>
          <View style={{ flex: 1, height: 1, backgroundColor: C.line }} />
          <T size={12.5} color={C.muted}>or</T>
          <View style={{ flex: 1, height: 1, backgroundColor: C.line }} />
        </Row>
        <Btn variant="outline" title="Create owner account" onPress={() => nav.push('SignUp')} />

        <View style={{ flex: 2 }} />
        <Row gap={6} style={{ justifyContent: 'center' }}>
          <Icon name="qr-code-outline" size={16} color={C.muted} />
          <T size={12.5} color={C.muted}>Student? Scan your hostel's QR code</T>
        </Row>
        {/* Prototype only: opens the student flow, as if the QR code was scanned. */}
        <Pressable hitSlop={6} onPress={openStudent} style={{ alignSelf: 'center', marginTop: 6 }}>
          <T size={12.5} weight="600" color={C.blue}>Prototype: open as a student</T>
        </Pressable>
        <Pressable hitSlop={6} onPress={() => nav.push('PreHub')} style={{ alignSelf: 'center', marginTop: 6 }}>
          <T size={12.5} weight="600" color={C.blue}>Prototype: student-first flow</T>
        </Pressable>
        <Pressable hitSlop={6} onPress={() => nav.push('Privacy')} style={{ alignSelf: 'center', marginTop: 10 }}>
          <T size={12.5} weight="600" color={C.blue}>Privacy policy · Terms of use</T>
        </Pressable>
      </View>
    </Screen>
  );
}

// ======================================================================
// Owner 2. Sign up
// ======================================================================
/** Slim boxed field for the one-screen sign-up (24 Oct 2026): 42 px boxes, 14 px text, so the whole form fits one screen. */
function SlimField({ value, onChangeText, placeholder, keyboardType, secure, prefix, editable = true, maxLength, error, right, multiline }) {
  const [focus, setFocus] = useState(false);
  return (
    <View style={{ marginBottom: 8 }}>
      <View style={{ flexDirection: 'row', alignItems: multiline ? 'flex-start' : 'center', minHeight: multiline ? 58 : 42, borderRadius: 10, borderWidth: 1.2,
        borderColor: error ? C.red : focus ? C.blue : C.line, backgroundColor: editable ? '#fff' : C.ground, paddingHorizontal: 12 }}>
        {prefix ? <T size={14} color={C.muted} style={{ marginRight: 6 }}>{prefix}</T> : null}
        <TextInput
          value={value}
          onChangeText={onChangeText}
          placeholder={placeholder}
          placeholderTextColor="#9AA7B8"
          keyboardType={keyboardType}
          secureTextEntry={secure}
          editable={editable}
          maxLength={maxLength}
          multiline={multiline}
          onFocus={() => setFocus(true)}
          onBlur={() => setFocus(false)}
          style={{ flex: 1, fontSize: 14, color: editable ? C.ink : C.muted, paddingVertical: multiline ? 9 : 6, textAlignVertical: multiline ? 'top' : 'center', ...appFont('500') }}
        />
        {right ? <View style={{ marginTop: multiline ? 10 : 0 }}>{right}</View> : null}
      </View>
      {error ? <T size={12.5} color={C.red} style={{ marginTop: 3 }}>{error}</T> : null}
    </View>
  );
}

// 24 Oct 2026: one screen creates the owner account AND the first hostel.
// YOU card: name · mobile + Send OTP · 6-digit OTP + Verify (then "Verified") · password · confirm password (eye icons).
// YOUR HOSTEL card: hostel name · type · full address · city · pincode. No location, floors, photos or contact here.
// Create account → saves both and opens the new hostel. "Already have an account? Log in" at the bottom.
export function SignUp() {
  const nav = useNav();
  useApp();
  const [name, setName] = useState('');
  const [mobile, setMobile] = useState('');
  const [sent, setSent] = useState(false);
  const [otp, setOtp] = useState('');
  const [otpErr, setOtpErr] = useState(null);
  const [verified, setVerified] = useState(false);
  const [pw, setPw] = useState('');
  const [pw2, setPw2] = useState('');
  const [show, setShow] = useState(false);
  const [show2, setShow2] = useState(false);
  const [hName, setHName] = useState('');
  const [type, setType] = useState("Men's");
  const [address, setAddress] = useState('');
  const [city, setCity] = useState('Hyderabad');
  const [pin, setPin] = useState('');
  const [wait, setWait] = useState(0);

  useEffect(() => {
    if (wait <= 0) return undefined;
    const id = setTimeout(() => setWait(wait - 1), 1000);
    return () => clearTimeout(id);
  }, [wait]);

  const digits = mobile.replace(/\D/g, '');
  const sendOtp = () => {
    if (!/^[6-9]\d{9}$/.test(digits)) return toast('Enter a valid 10-digit mobile number.');
    setSent(true);
    setWait(30);
    toast('OTP sent. Demo OTP: 123456');
  };
  const verify = () => (otp === DEMO_OTP ? (setVerified(true), setOtpErr(null)) : setOtpErr('Wrong OTP. Try again.'));

  const create = () => {
    if (!name.trim()) return toast('Add your name.');
    if (!verified) return toast('Verify your mobile number first.');
    if (pw.length < 6) return toast('Password needs at least 6 characters.');
    if (pw !== pw2) return toast('Passwords do not match.');
    if (!hName.trim()) return toast('Add the hostel name.');
    if (!address.trim() || !city.trim()) return toast('Add the hostel address and city.');
    if (pin.length !== 6) return toast('Enter the 6-digit pincode.');
    app.ownerName = name.trim();
    app.ownerMobile = `${digits.slice(0, 5)} ${digits.slice(5)}`;
    actions.login(false);
    actions.addHostel({
      id: 'h' + Date.now(),
      name: hName.trim(),
      type: type === "Women's" ? 'womens' : type === 'Co-living' ? 'coliving' : 'mens',
      area: `${city.trim()}, ${pin}`,
      address: address.trim(),
      contact: app.ownerMobile,
    });
    actions.selectHostel(app.hostels.length - 1);
    toast('Account created');
    nav.replace('OwnerShell');
  };

  const head = (t) => <T size={12.5} weight="800" color={C.blue} style={{ letterSpacing: 0.4, marginBottom: 8 }}>{t}</T>;
  const link = (title, onPress) => (
    <Pressable hitSlop={8} onPress={onPress}><T weight="600" color={C.blue}>{title}</T></Pressable>
  );
  const eye = (on, set) => (
    <Pressable hitSlop={10} onPress={() => set(!on)} accessibilityLabel={on ? 'Hide password' : 'Show password'}>
      <Icon name={on ? 'eye-off-outline' : 'eye-outline'} size={20} color={C.muted} />
    </Pressable>
  );

  return (
    <Screen title="Create owner account" footer={<Btn title="Create account" onPress={create} />}>
      <T size={12.5} color={C.muted} style={{ marginTop: -8, marginBottom: 8 }}>You and your hostel, on one screen</T>

      <Card padding={12}>
        {head('YOU')}
        <SlimField placeholder="Your name" value={name} onChangeText={setName} />
        <SlimField
          prefix="+91"
          placeholder="Mobile number"
          keyboardType="phone-pad"
          maxLength={11}
          value={mobile}
          editable={!verified}
          onChangeText={(v) => { setMobile(v); setSent(false); setOtp(''); }}
          right={verified
            ? <Row gap={4}><Icon name="checkmark-circle" size={18} color={C.green} /><T size={12.5} weight="600" color={C.green}>Verified</T></Row>
            : link(sent ? 'Change' : 'Send OTP', sent ? () => { setSent(false); setOtp(''); } : sendOtp)}
        />
        {sent && !verified ? (
          <>
            <SlimField
              placeholder="6-digit OTP"
              keyboardType="number-pad"
              maxLength={6}
              value={otp}
              onChangeText={(v) => { setOtp(v); setOtpErr(null); }}
              error={otpErr}
              right={link('Verify', verify)}
            />
            <Row style={{ marginTop: 2, marginBottom: 6 }}>
              <T size={12.5} color={C.muted} style={{ flex: 1 }}>Demo OTP 123456</T>
              {wait > 0 ? <T size={12.5} color={C.muted}>Resend in {wait}s</T> : link('Resend OTP', sendOtp)}
            </Row>
          </>
        ) : null}
        <SlimField placeholder="Password · at least 6 characters" secure={!show} value={pw} onChangeText={setPw} right={eye(show, setShow)} />
        <SlimField
          placeholder="Confirm password"
          secure={!show2}
          value={pw2}
          onChangeText={setPw2}
          error={pw2 && pw2 !== pw ? 'Passwords do not match.' : null}
          right={eye(show2, setShow2)}
        />
      </Card>

      <Gap h={10} />
      <Card padding={12}>
        {head('YOUR HOSTEL')}
        <SlimField placeholder="Hostel name" value={hName} onChangeText={setHName} />
        <Chips options={["Men's", "Women's", 'Co-living']} value={type} onChange={setType} />
        <Gap h={8} />
        <SlimField placeholder="Full address · house, street, area" multiline value={address} onChangeText={setAddress} />
        <View style={{ marginBottom: -8 }}>
          <Row gap={10} align="flex-start">
            <View style={{ flex: 1 }}><SlimField placeholder="City" value={city} onChangeText={setCity} /></View>
            <View style={{ flex: 1 }}><SlimField placeholder="Pincode" keyboardType="number-pad" maxLength={6} value={pin} onChangeText={setPin} /></View>
          </Row>
        </View>
      </Card>

      <Gap h={10} />
      <Row gap={6} style={{ justifyContent: 'center' }}>
        <T color={C.muted}>Already have an account?</T>
        {link('Log in', () => nav.pop())}
      </Row>
      <Gap h={4} />
      <T size={11} color={C.muted} style={{ textAlign: 'center' }}>By signing up you agree to the Terms of use and Privacy policy.</T>
    </Screen>
  );
}

// ======================================================================
// Forgot password (reset via OTP)
// ======================================================================
export function ForgotPassword() {
  const nav = useNav();
  const [step, setStep] = useState(0);
  const text = ['Enter your registered mobile. We will send an OTP.', 'Enter the OTP sent to your mobile (demo: 123456).', 'Choose a new password.'][step];
  return (
    <Screen
      title="Reset password"
      onBack={() => (step > 0 ? setStep(step - 1) : nav.pop())}
      footer={
        <Btn
          title={['Send OTP', 'Verify OTP', 'Save new password'][step]}
          onPress={() => {
            if (step < 2) setStep(step + 1);
            else {
              nav.pop();
              toast('Password changed. Log in with your new password.');
            }
          }}
        />
      }
    >
      <T color={C.muted}>{text}</T>
      <Gap h={18} />
      {step === 0 ? <Field label="Mobile number" prefix="+91" placeholder="99887 76655" keyboardType="phone-pad" /> : null}
      {step === 1 ? <Field label="6-digit OTP" keyboardType="number-pad" maxLength={6} /> : null}
      {step === 2 ? (
        <>
          <Field label="New password" secure />
          <Field label="Confirm new password" secure />
        </>
      ) : null}
    </Screen>
  );
}

// ======================================================================
// Owner 4. My hostels  (approved design: coloured cards, 2x2 boxes, % ring)
// ======================================================================
const SAMPLE_PHOTO = require('../../assets/sample-hostel.jpg');

/** Add / change / remove the hostel photo. Without a photo the short name is shown. */
export function PhotoSheet({ h, close }) {
  const short = hostelShortName(cleanHostelName(h.name));
  const pick = (how) => {
    actions.setHostelPhoto(h, SAMPLE_PHOTO);
    close();
    toast(`Prototype: the ${how} opens in the real app – a sample photo is used.`);
  };
  return (
    <View style={{ gap: 10 }}>
      <T size={20} weight="800">Hostel photo</T>
      <T color={C.muted}>Shown on your hostel card, the hostel Home and to students when they join. Without a photo, the short name {short} is shown.</T>
      <Btn icon="camera-outline" title="Take a photo" onPress={() => pick('camera')} />
      <Btn variant="outline" icon="images-outline" title="Choose from gallery" onPress={() => pick('gallery')} />
      {h.photo ? (
        <Btn variant="dangerOutline" icon="trash-outline" title={`Remove photo (show ${short})`}
          onPress={() => { actions.setHostelPhoto(h, null); close(); }} />
      ) : null}
      <Btn variant="text" title="Cancel" onPress={close} />
    </View>
  );
}

export function PenButton({ onPress }) {
  return (
    <Pressable accessibilityLabel="Change hostel photo" onPress={onPress} hitSlop={8}
      style={{ position: 'absolute', right: -4, bottom: -4, width: 26, height: 26, borderRadius: 13, backgroundColor: '#fff', borderWidth: 1, borderColor: C.line, alignItems: 'center', justifyContent: 'center' }}>
      <Icon name="pencil" size={13} color={C.blue} />
    </Pressable>
  );
}

function StatBox({ n, label, color }) {
  return (
    <View style={{ flex: 1, flexDirection: 'row', alignItems: 'baseline', gap: 5, backgroundColor: '#F2F5F9', borderRadius: 8, paddingHorizontal: 8, paddingVertical: 6 }}>
      <T size={16} weight="800" color={color}>{n}</T>
      <T size={11} weight="400" color={C.muted} numberOfLines={1}>{label}</T>
    </View>
  );
}

// Confirm sheet before a hostel is removed from the list.
function RemoveHostelSheet({ h, tenants = 0, close, onRemove }) {
  const bullet = (text) => (
    <Row gap={6} style={{ alignItems: 'flex-start' }}>
      <T color={C.muted}>•</T>
      <T color={C.muted} style={{ flex: 1, lineHeight: 20 }}>{text}</T>
    </Row>
  );
  return (
    <View style={{ gap: 10 }}>
      <View style={{ width: 44, height: 44, borderRadius: 22, backgroundColor: '#FCECEA', alignItems: 'center', justifyContent: 'center' }}>
        <Icon name="close" size={22} color={C.red} />
      </View>
      <T size={20} weight="800">Remove {hostelTitle(h)}?</T>
      <View style={{ gap: 4 }}>
        {bullet('Hidden from My hostels. No new joins.')}
        {bullet('No new rent bills or reminders while removed.')}
        {bullet('Tenants, rooms and payments are kept.')}
        {bullet('You can restore it any time from Removed hostels.')}
      </View>
      {tenants > 0 ? (
        <View style={{ backgroundColor: C.amberSoft, borderRadius: 10, padding: 10 }}>
          <T size={12.5} color={C.amber} style={{ lineHeight: 18 }}>
            {tenants} tenants still live here. They stay in your records, but rent bills stop while it is removed.
          </T>
        </View>
      ) : null}
      <View style={{ height: 6 }} />
      <Btn title="Remove hostel" variant="danger" onPress={() => { close(); onRemove(); }} />
      <Btn title="Keep it" variant="outline" onPress={close} />
    </View>
  );
}

function HostelCard({ h, i, onOpen, onRemove }) {
  const col = hostelColor(h.colorIndex ?? i); // colour stays with the hostel
  const st = hostelStats(i);
  const total = st.filled + st.free + st.hold;
  const place = (h.area || '').split(',')[0];
  const openPhoto = () => showSheet((close) => <PhotoSheet h={h} close={close} />);
  return (
    <Pressable onPress={onOpen} style={({ pressed }) => ({ borderRadius: 16, borderWidth: 1, borderColor: '#DCE3EC', backgroundColor: '#FFFFFF', elevation: 1, overflow: 'hidden', marginBottom: 10, opacity: pressed ? 0.9 : 1 })}>
      <View style={{ flexDirection: 'row', alignItems: 'center', gap: 8, backgroundColor: col.band, paddingVertical: 10, paddingLeft: 14, paddingRight: 10 }}>
        <View style={{ flex: 1 }}>
          <T size={14} weight="600" color="#FFFFFF" numberOfLines={2}>{hostelTitle(h)}</T>
          {place ? <T size={12.5} weight="400" color="#D6ECFC" numberOfLines={1}>{place}</T> : null}
        </View>
        <Pressable
          accessibilityRole="button"
          accessibilityLabel={`Remove ${hostelTitle(h)}`}
          hitSlop={10}
          onPress={() => showSheet((close) => <RemoveHostelSheet h={h} tenants={st.filled} close={close} onRemove={onRemove} />)}
          style={({ pressed }) => ({ width: 24, height: 24, borderRadius: 12, backgroundColor: '#fff', alignItems: 'center', justifyContent: 'center', opacity: pressed ? 0.6 : 1 })}
        >
          <Icon name="close" size={14} color="#1560BD" />
        </Pressable>
      </View>
      {h.setupDone ? (
        <View style={{ flexDirection: 'row', alignItems: 'stretch', gap: 10, padding: 10 }}>
          {/* hostel photo, or its short name until a photo is added */}
          <View style={{ width: 56, justifyContent: 'center' }}>
            <HostelPhoto h={h} height={72} onEdit={openPhoto} />
          </View>
          <View style={{ flex: 1, gap: 5 }}>
            <View style={{ flexDirection: 'row', gap: 5 }}>
              <StatBox n={st.filled} label="Filled" color={C.ink} />
              <StatBox n={st.free} label="Free" color={C.green} />
            </View>
            <View style={{ flexDirection: 'row', gap: 5 }}>
              <StatBox n={st.hold} label="On hold" color={C.amber} />
              <StatBox n={st.alerts} label="Alerts" color={st.alerts ? C.red : C.green} />
            </View>
          </View>
          <View style={{ justifyContent: 'center' }}>
            <PercentRing filled={st.filled} hold={st.hold} total={total} color={col.strong} textColor={col.dark} />
          </View>
        </View>
      ) : (
        <View style={{ flexDirection: 'row', alignItems: 'stretch', gap: 10, padding: 10 }}>
          <HostelPhoto h={h} height={64} onEdit={openPhoto} />
          <View style={{ flex: 1, justifyContent: 'center', gap: 6 }}>
            <Row gap={8}>
              <View style={{ flex: 1 }}><ProgressBar value={0.4} color="#1560BD" height={7} /></View>
              <T size={11} weight="600" color="#1560BD">2 of 5</T>
            </Row>
            <T size={12.5} weight="600" color={C.blue}>Finish setup →</T>
          </View>
        </View>
      )}
    </Pressable>
  );
}

// Small drawing of three buildings with a "+" badge (used on the add-hostel card).
function MiniTown({ scale = 1 }) {
  const k = (n) => n * scale;
  const blocks = [
    { x: 4, w: 17, h: 26, bg: '#E8F0FA', cols: 2, rows: 3 },
    { x: 24, w: 20, h: 33, bg: '#FAE5EE', cols: 3, rows: 4 },
    { x: 47, w: 11, h: 22, bg: '#E1F3E9', cols: 0, rows: 0 },
  ];
  return (
    <View style={{ width: k(60), height: k(40) }}>
      {blocks.map((b, i) => (
        <View key={i} style={{ position: 'absolute', left: k(b.x), bottom: k(2), width: k(b.w), height: k(b.h), borderRadius: k(1.5), backgroundColor: b.bg,
          flexDirection: 'row', flexWrap: 'wrap', paddingTop: k(4), paddingHorizontal: k(3), gap: k(3) }}>
          {Array.from({ length: b.cols * b.rows }).map((_, j) => (
            <View key={j} style={{ width: k(3), height: k(3), backgroundColor: '#fff' }} />
          ))}
        </View>
      ))}
      <View style={{ position: 'absolute', left: 0, right: 0, bottom: 0, height: k(2), borderRadius: k(1), backgroundColor: '#DDE3EC' }} />
      <View style={{ position: 'absolute', right: 0, top: 0, width: k(13), height: k(13), borderRadius: k(6.5), backgroundColor: C.blue, alignItems: 'center', justifyContent: 'center' }}>
        <Icon name="add" size={k(11)} color="#fff" />
      </View>
    </View>
  );
}

const DASHED = { borderWidth: 2, borderStyle: 'dashed', borderColor: '#B9CDEB', backgroundColor: '#FBFCFE', borderRadius: 16 };

// 1–2 hostels: big "Run another hostel?" card.
function AddHostelCardBig({ onAdd }) {
  return (
    <View style={[DASHED, { paddingVertical: 20, paddingHorizontal: 18, alignItems: 'center', gap: 10 }]}>
      <MiniTown scale={2} />
      <T size={16} weight="800" center>Run another hostel?</T>
      <T size={12.5} color={C.muted} center style={{ maxWidth: 270, lineHeight: 19 }}>
        Add it here and see beds, rent and alerts for all your hostels on one screen.
      </T>
      <Btn icon="add" title="Add another hostel" onPress={onAdd} style={{ alignSelf: 'stretch', marginTop: 6 }} />
    </View>
  );
}

// 3+ hostels (while it still fits): one-row "Another hostel?" card.
function AddHostelCardSmall({ onAdd }) {
  return (
    <View style={[DASHED, { padding: 12, paddingLeft: 14, flexDirection: 'row', alignItems: 'center', gap: 12 }]}>
      <MiniTown />
      <View style={{ flex: 1, minWidth: 0 }}>
        <T size={14} weight="600" numberOfLines={1}>Another hostel?</T>
        <T size={12.5} color={C.muted} numberOfLines={1}>Add it in a minute.</T>
      </View>
      <Btn small icon="add" title="Add hostel" onPress={onAdd} style={{ minHeight: 44 }} />
    </View>
  );
}

export function MyHostels() {
  const nav = useNav();
  useApp();
  // Below the hostel list:
  //  - 1–2 hostels: big "Run another hostel?" card
  //  - 3+ hostels: small one-row "Another hostel?" card, if it fits on screen
  //  - screen full: card goes, "Add another hostel" button fixed at the bottom, list scrolls
  const [areaH, setAreaH] = useState(0);
  const [listH, setListH] = useState(0);
  const [extraH, setExtraH] = useState(0);
  const GAP = 12;
  const PAD = 16;
  const few = app.hostels.length <= 2;
  const onAdd = () => nav.push('RegisterHostel');
  // Keep the last measured card height so the check stays stable once the card is hidden.
  const cardH = extraH || (few ? 270 : 76);
  const overflow = areaH > 0 && !few && PAD + listH + GAP + cardH + PAD > areaH;
  return (
    <Screen back={false} scroll={false} footer={overflow ? <Btn icon="add" title="Add another hostel" onPress={onAdd} /> : null}>
      <View style={{ flexDirection: 'row', alignItems: 'center', gap: 12, paddingHorizontal: 16, paddingTop: 8, paddingBottom: 10 }}>
        <Image source={APP_LOGO} accessibilityLabel="My Hostel" style={{ width: 44, height: 44, borderRadius: 12 }} />
        <View style={{ flex: 1 }}>
          <T size={12.5} weight="400" color={C.muted}>Hi {app.ownerName.split(' ')[0]}</T>
          <T size={24} weight="800">My hostels</T>
        </View>
        <Pressable accessibilityLabel="Log out" onPress={() => { actions.logout(); nav.popToTop(); }}
          style={{ width: 44, height: 44, borderRadius: 22, borderWidth: 1, borderColor: C.line, backgroundColor: '#fff', alignItems: 'center', justifyContent: 'center' }}>
          <Icon name="log-out-outline" color={C.blue} />
        </Pressable>
      </View>
      <View style={{ flex: 1 }} onLayout={(e) => setAreaH(e.nativeEvent.layout.height)}>
        <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingHorizontal: 16, paddingTop: 4, paddingBottom: PAD }}>
          <View onLayout={(e) => setListH(e.nativeEvent.layout.height)}>
            {app.hostels.map((h, i) => (
              <HostelCard
                key={h.id}
                h={h}
                i={i}
                onOpen={() => {
                  actions.selectHostel(i);
                  nav.push(h.setupDone ? 'OwnerShell' : 'SetupChecklist');
                }}
                onRemove={() => {
                  actions.removeHostel(i);
                  toast(`${hostelTitle(h)} removed`);
                  // No hostels left: go straight to "Register hostel", like a first-time owner.
                  if (app.hostels.length === 0) nav.push('RegisterHostel');
                }}
              />
            ))}
          </View>
          {!overflow ? (
            <View style={{ marginTop: GAP - 10 }} onLayout={(e) => setExtraH(e.nativeEvent.layout.height)}>
              {few ? <AddHostelCardBig onAdd={onAdd} /> : <AddHostelCardSmall onAdd={onAdd} />}
            </View>
          ) : null}
          {app.removedHostels.length > 0 ? (
            <Pressable onPress={() => nav.push('RemovedHostels')} accessibilityLabel="Removed hostels"
              style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 8, paddingVertical: 12, marginTop: 8 }}>
              <Icon name="file-tray-full-outline" size={18} color={C.blue} />
              <T weight="600" color={C.blue}>Removed hostels ({app.removedHostels.length})</T>
            </Pressable>
          ) : null}
        </ScrollView>
      </View>
    </Screen>
  );
}

// ======================================================================
// Owner 3. Register hostel (24 Oct 2026: short form)
// Hostel name · type · "Are you at the hostel now?" → Yes: phone location saves the exact point
// (latitude / longitude) and fills area, city, pincode · No: type area, city, pincode.
// House / street is optional. No floors, photos or contact number here (students type their rooms;
// photo is added from My hostels; contact = owner's login number). One button: Create hostel.
// Prototype: the location is sample data (no GPS).
// ======================================================================
const SAMPLE_LOCATION = { area: 'Madhapur', city: 'Hyderabad', pin: '500081', lat: 17.4486, lng: 78.3908 };

export function RegisterHostel({ params }) {
  const nav = useNav();
  useApp(); // the Restore link follows the removed hostels list
  const [name, setName] = useState('');
  const [type, setType] = useState("Men's");
  const [mode, setMode] = useState(null); // null = not asked yet · 'gps' · 'type'
  const [finding, setFinding] = useState(false);
  const [loc, setLoc] = useState(null); // saved GPS point
  const [area, setArea] = useState('');
  const [city, setCity] = useState('Hyderabad');
  const [pin, setPin] = useState('');
  const [street, setStreet] = useState('');

  const useLocation = () => {
    setMode('gps');
    setFinding(true);
    setTimeout(() => {
      setFinding(false);
      setLoc(SAMPLE_LOCATION);
    }, 900);
  };
  const reset = () => {
    setMode(null);
    setLoc(null);
  };

  const save = () => {
    if (!name.trim()) return toast('Add the hostel name.');
    const place = mode === 'gps' ? loc : mode === 'type' ? { area: area.trim(), city: city.trim(), pin } : null;
    if (!place || !place.area || !place.city) return toast('Add the hostel location.');
    if (mode === 'type' && pin && pin.length !== 6) return toast('Pincode has 6 digits.');
    actions.addHostel({
      id: 'h' + Date.now(),
      name: name.trim(),
      type: type === "Women's" ? 'womens' : type === 'Co-living' ? 'coliving' : 'mens',
      area: `${place.area}, ${place.city}`,
      address: [street.trim(), place.area, place.city, place.pin].filter(Boolean).join(', '),
      lat: place.lat ?? null,
      lng: place.lng ?? null,
      contact: app.ownerMobile,
      setupDone: false,
    });
    toast(`${name.trim()} created`);
    params.firstTime ? nav.replace('MyHostels') : nav.pop();
  };

  const answer = (icon, title, sub, onPress, primary) => (
    <Pressable
      onPress={onPress}
      style={{ flex: 1, alignItems: 'center', gap: 4, paddingVertical: 12, paddingHorizontal: 6, borderRadius: 12, borderWidth: 1.2,
        borderColor: primary ? C.blue : C.line, backgroundColor: primary ? C.blue : '#fff' }}
    >
      <Icon name={icon} size={22} color={primary ? '#fff' : C.blue} />
      <T weight="600" color={primary ? '#fff' : C.ink} style={{ textAlign: 'center' }}>{title}</T>
      <T size={11} color={primary ? '#D6ECFC' : C.muted} style={{ textAlign: 'center' }}>{sub}</T>
    </Pressable>
  );

  return (
    <Screen title="Register hostel" footer={<Btn title="Create hostel" onPress={save} />}>
      <Field label="Hostel name" placeholder="Sunrise Boys PG" value={name} onChangeText={setName} />
      <T size={14} weight="600" style={{ marginBottom: 8 }}>Type</T>
      <Chips options={["Men's", "Women's", 'Co-living']} value={type} onChange={setType} />
      <Gap h={16} />
      <T size={14} weight="600" style={{ marginBottom: 8 }}>Location</T>

      {mode === null ? (
        <Card padding={14} bg={C.blueSoft} border="#B9CDEB">
          <Row gap={10} style={{ marginBottom: 12 }}>
            <Icon name="location" size={22} color={C.blue} />
            <View style={{ flex: 1 }}>
              <T size={16} weight="800" color="#0C447C">Are you at the hostel now?</T>
              <T size={12.5} color={C.muted}>Your phone can save its exact location</T>
            </View>
          </Row>
          <Row gap={10} align="stretch">
            {answer('navigate', 'Yes, use my location', 'Fills area and pincode', useLocation, true)}
            {answer('create-outline', 'No, type address', 'Area, city, pincode', () => setMode('type'))}
          </Row>
        </Card>
      ) : mode === 'gps' ? (
        <>
          {finding || !loc ? (
            <Card padding={14}>
              <Row gap={10}>
                <ActivityIndicator color={C.blue} />
                <T color={C.muted}>Finding your location…</T>
              </Row>
            </Card>
          ) : (
            <Card padding={12} bg="#EAF6EE" border="#BFE3CB">
              <Row gap={10}>
                <View style={{ width: 36, height: 36, borderRadius: 18, backgroundColor: C.green, alignItems: 'center', justifyContent: 'center' }}>
                  <Icon name="location" size={18} color="#fff" />
                </View>
                <View style={{ flex: 1 }}>
                  <T weight="600" color={C.green}>Exact location saved</T>
                  <T size={12.5} color={C.muted}>{loc.area}, {loc.city} {loc.pin}</T>
                </View>
                <Pressable hitSlop={10} onPress={reset}><T size={12.5} weight="600" color={C.blue}>Change</T></Pressable>
              </Row>
            </Card>
          )}
          <Gap h={12} />
          <Field label="House / street (optional)" placeholder="Plot 12, Road 5" value={street} onChangeText={setStreet} />
        </>
      ) : (
        <>
          <Field label="Area" placeholder="Madhapur" value={area} onChangeText={setArea} />
          <Row gap={10} align="flex-start">
            <View style={{ flex: 1 }}><Field label="City" value={city} onChangeText={setCity} /></View>
            <View style={{ flex: 1 }}><Field label="Pincode" placeholder="500081" keyboardType="number-pad" maxLength={6} value={pin} onChangeText={setPin} /></View>
          </Row>
          <Field label="House / street (optional)" placeholder="Plot 12, Road 5" value={street} onChangeText={setStreet} />
          <Pressable onPress={useLocation} style={{ flexDirection: 'row', alignItems: 'center', gap: 6, alignSelf: 'flex-start' }} hitSlop={8}>
            <Icon name="navigate" size={16} color={C.blue} />
            <T size={12.5} weight="600" color={C.blue}>At the hostel now? Use my location</T>
          </Pressable>
        </>
      )}
      <Gap h={14} />
      <T size={12.5} color={C.muted}>Photos, rooms and rules can be added later. Students type their own room when they join.</T>
      {app.removedHostels.length > 0 ? (
        <Pressable onPress={() => nav.push('RemovedHostels')} hitSlop={8}
          style={{ flexDirection: 'row', alignItems: 'center', gap: 6, alignSelf: 'flex-start', marginTop: 12 }}>
          <Icon name="arrow-undo-outline" size={18} color={C.blue} />
          <T weight="600" color={C.blue}>Restore a removed hostel ({app.removedHostels.length})</T>
        </Pressable>
      ) : null}
    </Screen>
  );
}

// ======================================================================
// Removed hostels: hostels taken off My hostels, with Restore.
// Opened from My hostels, More (You) and Register hostel. Restoring shows the hostel in My hostels
// again, open for joins; rent bills and reminders resume.
// ======================================================================
function RestoreHostelSheet({ h, close, onRestore }) {
  const bullet = (text) => (
    <Row gap={6} style={{ alignItems: 'flex-start' }}>
      <T color={C.muted}>•</T>
      <T color={C.muted} style={{ flex: 1, lineHeight: 20 }}>{text}</T>
    </Row>
  );
  return (
    <View style={{ gap: 10 }}>
      <View style={{ width: 44, height: 44, borderRadius: 22, backgroundColor: C.blueSoft, alignItems: 'center', justifyContent: 'center' }}>
        <Icon name="arrow-undo-outline" size={22} color={C.blue} />
      </View>
      <T size={20} weight="800">Restore {hostelTitle(h)}?</T>
      <View style={{ gap: 4 }}>
        {bullet('Shows in My hostels again.')}
        {bullet('Join link opens for new students.')}
        {bullet('Rent bills and reminders resume.')}
      </View>
      <View style={{ height: 6 }} />
      <Btn title="Restore hostel" onPress={() => { close(); onRestore(); }} />
      <Btn title="Cancel" variant="outline" onPress={close} />
    </View>
  );
}

export function RemovedHostels() {
  const nav = useNav();
  useApp();
  const list = app.removedHostels;
  return (
    <Screen title="Removed hostels">
      {list.length === 0 ? (
        <EmptyState icon="file-tray-full-outline" title="No removed hostels" text="Hostels you remove show here. You can restore them any time." />
      ) : (
        <>
          {list.map((h) => (
            <Card key={h.id} style={{ marginBottom: 12 }}>
              <T size={16} weight="800">{hostelTitle(h)}</T>
              {h.area ? <T color={C.muted} style={{ marginTop: 2 }}>{h.area}</T> : null}
              <T size={12.5} color={C.muted} style={{ marginTop: 4, marginBottom: 12 }}>Removed {h.removedAt} · {h.removedTenants} tenants</T>
              <Btn
                title="Restore hostel"
                onPress={() => showSheet((close) => (
                  <RestoreHostelSheet
                    h={h}
                    close={close}
                    onRestore={() => {
                      actions.restoreHostel(h);
                      toast(`${hostelTitle(h)} restored`);
                      nav.popTo('MyHostels'); // the restored hostel is shown again
                    }}
                  />
                ))}
              />
            </Card>
          ))}
          <T size={12.5} color={C.muted} center>Removed hostels keep all their data.</T>
        </>
      )}
    </Screen>
  );
}

// ======================================================================
// Empty state: new hostel setup checklist
// ======================================================================
export function SetupChecklist() {
  const nav = useNav();
  useApp();
  const h = app.hostels[app.currentHostel];
  const [done, setDone] = useState([true, true, false, false, false]);
  const items = [
    ['Hostel details', 'Name, type, address', 'business', null],
    ['Photos', '3 photos added', 'images', null],
    ['Add rooms & beds', 'Sharing, rent and deposit for each room', 'bed', 'AddRoom'],
    ['Payment options', 'UPI ID, bank, cash or online', 'wallet', 'HostelSettings'],
    ['Rent day, notice & rules', 'Students see these before paying', 'reader', 'HostelSettings'],
  ];
  const count = done.filter(Boolean).length;
  return (
    <Screen
      title={hostelTitle(h)}
      footer={
        <Btn
          disabled={count < 5}
          title={count === 5 ? 'Open hostel' : 'Complete all steps to open'}
          onPress={() => {
            h.setupDone = true;
            actions.touch();
            nav.replace('OwnerShell');
          }}
        />
      }
    >
      <T size={20} weight="800">Finish setup to start taking students</T>
      <T color={C.muted} style={{ marginVertical: 6 }}>{count} of 5 done</T>
      <ProgressBar value={count / 5} />
      <Gap h={16} />
      {items.map(([title, sub, icon, screen], i) => (
        <Card
          key={title}
          style={{ marginBottom: 10 }}
          onPress={screen ? () => {
            nav.push(screen);
            setDone((d) => d.map((x, j) => (j === i ? true : x)));
          } : undefined}
        >
          <Row gap={12}>
            <IconBox name={done[i] ? 'checkmark' : icon} color={done[i] ? C.green : C.blue} />
            <View style={{ flex: 1 }}>
              <T weight="600" style={done[i] ? { textDecorationLine: 'line-through' } : null}>{title}</T>
              <T size={12.5} color={C.muted}>{sub}</T>
            </View>
            {!done[i] ? <Icon name="chevron-forward" size={20} color={C.blue} /> : null}
          </Row>
        </Card>
      ))}
      <T size={12.5} color={C.muted}>Tap a step to open it. It is ticked when you come back.</T>
    </Screen>
  );
}
