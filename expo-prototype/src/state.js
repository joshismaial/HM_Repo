// All data in this prototype is SAMPLE data kept in memory.
// Nothing is saved: closing the app resets everything.
// Later, each action here becomes a Supabase call.
import { useEffect, useReducer } from 'react';

const listeners = new Set();
let version = 0;
export function notify() {
  version++;
  listeners.forEach((l) => l(version));
}

/** Re-render the calling component whenever app data changes. */
export function useApp() {
  const [, force] = useReducer((x) => x + 1, 0);
  useEffect(() => {
    listeners.add(force);
    return () => listeners.delete(force);
  }, []);
  return app;
}

export const LANGUAGES = ['English', 'हिन्दी', 'తెలుగు', 'தமிழ்', 'मराठी', 'ಕನ್ನಡ', 'বাংলা'];
export const DEMO_OTP = '123456';
export const DUPLICATE_UTR = '428913775201';

export const typeLabel = (t) => ({ mens: "Men's", womens: "Women's", coliving: 'Co-living' }[t]);

// Hostel name shown as "Name – Type" (22 Oct 2026). Words that only say who the hostel is for
// (Ladies, Girls, Gents, Boys, Men's, Women's, Co-living, PG) are dropped from the display;
// the name the owner typed is kept unchanged in h.name.
const TYPE_WORDS = new Set(['ladies', 'girls', 'women', 'womens', 'gents', 'boys', 'men', 'mens', 'coliving', 'pg']);
const norm = (w) => w.toLowerCase().replace(/[’'`.\-]/g, '');
export function cleanHostelName(name) {
  const words = String(name || '').trim().split(/\s+/).filter(Boolean);
  const out = [];
  for (let i = 0; i < words.length; i++) {
    const w = norm(words[i]);
    if (w === 'co' && words[i + 1] && norm(words[i + 1]) === 'living') { i++; continue; } // "Co Living"
    if (!TYPE_WORDS.has(w)) out.push(words[i]);
  }
  return out.join(' ') || String(name || '').trim();
}
/** "Sai Residency – Women's". The type is joined with no-break spaces so it never splits across lines. */
export function hostelTitle(h) {
  if (!h) return '';
  const type = typeLabel(h.type);
  const clean = cleanHostelName(h.name);
  return type ? `${clean}\u00A0–\u00A0${type.replace('-', '\u2011')}` : clean;
}

function makeHostel(o) {
  return {
    setupDone: true,
    rentSameAsJoining: true,
    fixedRentDay: 5,
    allowDayWise: true,
    noticeDays: 15,
    electricitySeparate: true,
    laundry: true,
    laundryCharge: 300,
    payOnline: true,
    payUpi: true,
    payBank: true,
    payCash: true,
    upiId: 'sunrisepg@okicici',
    bankDetails: 'Sunrise PG · HDFC Bank · A/c 5010 0234 4410 · IFSC HDFC0001234',
    payGpay: true,
    payPhonepe: true,
    payPaytm: false,
    cashNote: 'Please pay cash in the office, 9 AM – 1 PM, Mon–Sat.',
    amenities: ['Wi-Fi', 'Food (3 meals)', 'Hot water', 'Washing machine', 'CCTV', 'Power backup'],
    rules: ['Gate closes at 10:30 PM', 'No smoking or alcohol', 'Visitors only in the lobby', 'Keep rooms clean'],
    wifi: [], // Wi-Fi for students: { floor: null (whole hostel) | number, name, password }
    // Phase 1 only: students type their floor, room, sharing, price and deposit in "Your details";
    // the owner checks them in "Rooms from tenants". Turn off once all rooms are set (Phase 2/3).
    tenantRoomEntry: true,
    useTenantPrices: true, // new joiners see the confirmed "Price by sharing"
    ...o,
  };
}

function room(number, floor, sharing, rent, deposit, perDay, dayDeposit, beds, features) {
  return { number, floor, sharing, rent, deposit, perDay, dayDeposit, beds, features };
}
export const bedLabel = (i) => String.fromCharCode(65 + i);
export const freeBeds = (r) => r.beds.filter((b) => b === 'vacant').length;

function tenant(o) {
  return {
    stayType: 'monthly',
    idLast4: '4821',
    address: 'H.No 12-4, Gandhi Nagar, Vijayawada, AP',
    office: 'Infosys, Gachibowli, Hyderabad',
    reference: 'REF-2291',
    daysLate: 0,
    payments: [],
    ...o,
  };
}
export const initials = (name) =>
  name
    .split(' ')
    .filter(Boolean)
    .slice(0, 2)
    .map((p) => p[0])
    .join('')
    .toUpperCase();

function newDraft() {
  return {
    mobile: '',
    verified: false,
    room: null,
    bedIndex: -1,
    holdUntil: null,
    name: '',
    parentName: '',
    parent: '',
    referenceName: '',
    reference: '',
    idType: 'Aadhaar',
    idLast4: '',
    idNumber: '', // full Aadhaar / ID number (stored encrypted in the real app)
    org: '', // company / institute name
    acceptRules: false, // hostel terms & house rules
    booked: false, // opened from the owner's "Share with student" QR for one bed
    idUploaded: false,
    photoUploaded: false,
    homeAddress: '',
    office: '',
    consent: false,
    existing: false,
    joinDate: protoToday(),
    // Phase 1 "Your room" (typed by the student)
    roomEntry: false,
    roomFloor: '',
    roomNo: '',
    roomSharing: 0,
    roomPrice: '',
    roomDeposit: '',
    roomLocked: false, // room already confirmed by the owner → details filled in and locked
    stayType: 'monthly',
    days: 5,
    agreedRefund: false,
    payMethod: 'upi', // 25 Oct 2026: free UPI straight to the owner (no gateway)
    utr: '',
  };
}

export const app = {
  lateFeeOn: true,
  lateFeePerDay: 50,
  autoRemind: true,
  // ---------------- owner session ----------------
  ownerName: 'Rohith Sharma',
  ownerMobile: '99887 76655',
  loggedIn: false,
  isStaff: false,
  currentHostel: 0,
  removedHostels: [], // hostels the owner removed from My hostels (can be restored)
  hostels: [
    makeHostel({ id: 'h1', colorIndex: 0, wifi: [{ floor: null, name: 'SunrisePG', password: 'sunrise@123' }, { floor: 2, name: 'SunrisePG_F2', password: 'floor2@pg' }], name: 'Sunrise Boys PG', type: 'mens', area: 'Madhapur, Hyderabad', address: 'Plot 42, Ayyappa Society, Madhapur, Hyderabad 500081', contact: '99887 76655' }),
    makeHostel({ id: 'h2', colorIndex: 1, name: 'Lotus Ladies Hostel', type: 'womens', area: 'Kukatpally, Hyderabad', address: '8-3-221, KPHB Phase 3, Kukatpally, Hyderabad 500072', contact: '99887 76655', stats: { filled: 18, free: 4, hold: 0, alerts: 0 } }),
    makeHostel({ id: 'h4', colorIndex: 2, name: 'Green Valley PG', type: 'mens', area: 'Ameerpet, Hyderabad', address: '7-1-58, Ameerpet, Hyderabad 500016', contact: '99887 76655', stats: { filled: 24, free: 2, hold: 2, alerts: 3 } }),
    makeHostel({ id: 'h5', colorIndex: 3, name: 'Sai Residency Ladies PG', type: 'womens', area: 'Dilsukhnagar, Hyderabad', address: '16-11-740, Dilsukhnagar, Hyderabad 500060', contact: '99887 76655', stats: { filled: 9, free: 7, hold: 0, alerts: 1 } }),
    makeHostel({ id: 'h3', colorIndex: 4, name: 'Nest Co-living', type: 'coliving', area: 'Gachibowli, Hyderabad', address: 'Road 2, Financial District, Gachibowli 500032', contact: '99887 76655', setupDone: false }),
  ],
  rooms: [
    room('101', 1, 2, 8000, 8000, 550, 1000, ['filled', 'filled'], ['AC', 'Attached bathroom']),
    room('102', 1, 3, 6500, 6500, 450, 1000, ['filled', 'vacant', 'filled'], ['Attached bathroom']),
    room('103', 1, 1, 12000, 12000, 800, 2000, ['vacant'], ['AC', 'Attached bathroom', 'Balcony']),
    room('201', 2, 4, 5500, 5500, 400, 1000, ['filled', 'filled', 'held', 'vacant'], ['Common bathroom']),
    room('202', 2, 2, 8000, 8000, 550, 1000, ['filled', 'filled'], ['AC', 'Attached bathroom']),
    room('203', 2, 3, 6500, 6500, 450, 1000, ['vacant', 'vacant', 'filled'], ['Attached bathroom']),
    room('204', 2, 3, 6500, 6500, 450, 1000, ['filled', 'filled', 'filled'], ['Attached bathroom']),
    room('301', 3, 2, 7500, 7500, 500, 1000, ['filled', 'vacant'], ['Attached bathroom', 'Balcony']),
    room('302', 3, 4, 5500, 5500, 400, 1000, ['vacant', 'filled', 'vacant', 'filled'], ['Common bathroom']),
    room('303', 3, 3, 6500, 6500, 450, 1000, ['filled', 'filled', 'filled'], ['Attached bathroom']),
    room('401', 4, 3, 7000, 7000, 480, 1000, ['filled', 'vacant', 'vacant'], ['AC', 'Attached bathroom']),
    room('402', 4, 2, 7500, 7500, 500, 1000, ['vacant', 'vacant'], ['Attached bathroom', 'Balcony']),
  ],
  tenants: [
    tenant({ id: 't1', photo: require('../assets/sample-student.jpg'), name: 'Rahul Verma', mobile: '98765 43210', parentMobile: '94401 22334', room: '204', bed: 'B', joined: '05 Sep 2026', rent: 6500, deposit: 6500, status: 'paid', dueDate: '05 Nov', payments: [
      { month: 'Oct 2026', amount: 7220, method: 'UPI', date: '05 Oct', receipt: 'RCP-1042' },
      { month: 'Sep 2026 + deposit', amount: 13000, method: 'Online', date: '05 Sep', receipt: 'RCP-0987' },
    ] }),
    tenant({ id: 't2', name: 'Arjun Reddy', mobile: '90000 11223', parentMobile: '90000 44556', room: '101', bed: 'A', joined: '12 Jun 2026', rent: 8000, deposit: 8000, status: 'late', dueDate: '12 Oct', daysLate: 8, payments: [
      { month: 'Sep 2026', amount: 8840, method: 'Cash', date: '13 Sep', receipt: 'RCP-0991' },
    ] }),
    tenant({ id: 't3', name: 'Kiran Naidu', mobile: '91234 56780', parentMobile: '91234 00011', room: '102', bed: 'A', joined: '01 Aug 2026', rent: 6500, deposit: 6500, status: 'pending', dueDate: '20 Oct', dueToday: true }),
    tenant({ id: 't4', name: 'Mohammed Faiz', mobile: '93939 12121', parentMobile: '93939 45454', room: '201', bed: 'A', joined: '20 Jul 2026', rent: 5500, deposit: 5500, status: 'notice', dueDate: '20 Oct' }),
    tenant({ id: 't5', name: 'Vikram Singh', mobile: '97777 88990', parentMobile: '97777 11000', room: '202', bed: 'B', joined: '03 Mar 2026', rent: 8000, deposit: 8000, status: 'late', dueDate: '03 Oct', daysLate: 17 }),
    tenant({ id: 't6', name: 'Sai Teja', mobile: '96666 55443', parentMobile: '96666 00112', room: '203', bed: 'C', joined: '15 Sep 2026', rent: 6500, deposit: 6500, status: 'paid', dueDate: '20 Nov', stayType: 'dayWise', dueToday: true, payments: [
      { month: 'Oct 2026', amount: 6500, method: 'Cash', date: '20 Oct', receipt: 'RCP-1050' },
    ] }),
    tenant({ id: 't7', name: 'Pranav Joshi', mobile: '95555 22110', parentMobile: '95555 33221', room: '301', bed: 'A', joined: '10 May 2026', rent: 7500, deposit: 7500, status: 'pending', dueDate: '20 Oct', dueToday: true }),
  ],
  // 25 Oct 2026 – free UPI with checks: UTRs and receipt images already used (any hostel),
  // (blocks reuse)
  usedUtrs: ['428913775201'],
  usedReceipts: ['img-used-before'],
  paymentRequests: [
    { id: 'p1', tenantName: 'Kiran Naidu', room: '102 · Bed A', amount: 7120, method: 'UPI', purpose: 'October rent', time: '10 min ago', utr: '428913775201', note: 'SUNRISE-102A-OCT' },
    { id: 'p2', tenantName: 'Ravi Teja', room: '203 · Bed A', amount: 13000, method: 'UPI', purpose: 'Joining · rent + deposit', time: '1 hr ago', utr: '428913775201', note: 'SUNRISE-203A-JOIN', duplicateUtr: true },
    { id: 'p3', tenantName: 'Sai Teja', room: '203 · Bed C', amount: 2250, method: 'Online', purpose: 'Extend stay · 5 days', time: '2 hr ago', online: true },
  ],
  joinRequests: [
    { id: 'j1', name: 'Ravi Teja', mobile: '98480 12345', room: '203', bed: 'A', stayType: 'monthly', time: '1 hr ago' },
    { id: 'j2', name: 'Nikhil Rao', mobile: '99122 33445', room: '301', bed: 'B', stayType: 'monthly', time: 'Yesterday', existing: true, joinedOn: '02 Jun 2026' },
  ],
  complaints: [
    { id: 'c1', category: 'Water', text: 'No hot water in the 2nd floor bathroom since morning.', student: 'Rahul Verma', room: '204', time: '25 min ago', status: 'open', hasPhoto: true, reply: '' },
    { id: 'c2', category: 'Wi-Fi', text: 'Wi-Fi keeps disconnecting every few minutes in room 101.', student: 'Arjun Reddy', room: '101', time: '3 hr ago', status: 'inProgress', reply: 'Technician coming at 5 PM.' },
    { id: 'c3', category: 'Furniture', text: 'Cupboard lock is broken.', student: 'Pranav Joshi', room: '301', time: '2 days ago', status: 'resolved', reply: 'Lock replaced.' },
  ],
  notices: [{ tenantId: 't4', name: 'Mohammed Faiz', room: '201 · Bed A', givenOn: '05 Oct 2026', leaveOn: '20 Oct 2026', deposit: 5500, onTime: true }],
  notifications: [
    { id: 'n1', title: 'Payment to confirm', body: 'Kiran Naidu paid ₹7,120 by UPI · UTR 428913775201', time: '10 min ago', today: true, unread: true, kind: 'pay' },
    { id: 'n2', title: 'New complaint', body: 'Rahul Verma (204): No hot water in the 2nd floor bathroom', time: '25 min ago', today: true, unread: true, kind: 'issue' },
    { id: 'n3', title: 'New join request', body: 'Ravi Teja wants Room 203 · Bed A (monthly)', time: '1 hr ago', today: true, unread: true, kind: 'join' },
    { id: 'n4', title: 'Online payment received', body: 'Sai Teja paid ₹2,250 to extend stay by 5 days', time: '2 hr ago', today: true, unread: false, kind: 'pay' },
    { id: 'n5', title: 'Existing tenant request', body: 'Nikhil Rao says he joined on 02 Jun 2026 · Room 301', time: 'Yesterday, 6:40 PM', today: false, unread: true, kind: 'join' },
    { id: 'n6', title: 'Rent overdue', body: 'Vikram Singh is 17 days late (₹8,000)', time: 'Yesterday, 9:00 AM', today: false, unread: false, kind: 'rent' },
  ],
  // Staff (More → Staff). duties = what they may do in the app; custom = duties the owner typed.
  staff: [
    { id: 's1', name: 'Ramesh Kumar', mobile: '98480 11223', job: 'manager', duties: ['rent', 'approve', 'rooms', 'complaints', 'leaving', 'checklist'], custom: [], checklist: 'Lock gate 10:30 PM · Check water tank' },
    { id: 's2', name: 'Sunita Lakshmi', mobile: '90000 55667', job: 'cleaning', duties: ['complaints', 'checklist'], custom: [{ name: 'Buy cleaning items', on: true }], checklist: 'Clean bathrooms 8 AM · Common area 5 PM' },
    { id: 's3', name: 'Mahesh', mobile: '91234 77889', job: 'security', duties: ['leaving', 'checklist'], custom: [], checklist: 'Lock gate 10:30 PM · Night round 1 AM' },
    { id: 's4', name: 'Prakash', mobile: '93939 22110', job: 'cook', duties: ['checklist'], custom: [], checklist: 'Breakfast 7:30 AM · Dinner 8 PM' },
  ],
  electricityByRoom: { 101: 840, 102: 610, 204: 1260 },
  settings: {
    notifyJoins: true, notifyPayments: true, notifyComplaints: true, dailySummary: false,
    msgPush: true, msgSms: true, msgWhatsapp: true, appLock: false, theme: 'System',
  },
  language: 'English',

  // ---------------- Phase 1: rooms typed by tenants ----------------
  // one entry per student who typed their room in "Your details"
  roomEntries: [
    { id: 'e0', name: 'Gopi Krishna', room: 'G1', floor: '0', sharing: 2, price: 7000, deposit: 5000 },
    { id: 'e1', name: 'Anil Kumar', room: '105', floor: '1', sharing: 3, price: 6500, deposit: 5000 },
    { id: 'e2', name: 'Kiran Kumar', room: '105', floor: '1', sharing: 3, price: 6500, deposit: 5000 },
    { id: 'e3', name: 'Suresh P', room: '105', floor: '1', sharing: 4, price: 6500, deposit: 0 },
    { id: 'e4', name: 'Manoj Varma', room: '106', floor: '1', sharing: 2, price: 7500, deposit: 5000 },
    { id: 'e5', name: 'Deepak Rao', room: '106', floor: '1', sharing: 2, price: 7500, deposit: 5000 },
    { id: 'e6', name: 'Ravi Kumar', room: '205', floor: '2', sharing: 3, price: 6500, deposit: 5000 },
    { id: 'e7', name: 'Harsha V', room: '206', floor: '2', sharing: 4, price: 5500, deposit: 5000 },
    { id: 'e8', name: 'Naveen G', room: '206', floor: '2', sharing: 4, price: 6000, deposit: 5000 },
    { id: 'e9', name: 'Ajay Singh', room: '206', floor: '2', sharing: 4, price: 5500, deposit: 5000 },
    { id: 'e10', name: 'Srinivas M', room: '305', floor: '3', sharing: 1, price: 11000, deposit: 10000 },
    { id: 'e11', name: 'Prakash Reddy', room: '306', floor: '3', sharing: 2, price: 7500, deposit: 5000 },
  ],
  // owner's corrections / confirmations per room: { [room]: { floor, sharing, price, deposit, confirmed } }
  roomFixes: {},

  // ---------------- student session ----------------
  draft: newDraft(),
  stay: {
    name: 'Rahul Verma', mobile: '98765 43210', room: '204', bed: 'B', floor: 2, sharing: 3, stayType: 'monthly',
    checkIn: '05 Sep 2026', checkOut: '18 Oct 2026', rent: 6500, perDay: 450, deposit: 6500,
    electricity: 420, laundry: 300, dueDate: '05 Nov 2026', billPaid: false, status: 'Active',
    daysToDue: 16, daysLate: 0, // prototype: days before / after the fee date
    photo: require('../assets/sample-student.jpg'), // student photo from joining (null = initials)
    noticeGiven: false, leaveOn: '', noticeGivenOn: '', noticeDaysGiven: 0,
    cashPending: null, // { when: 'today' | 'tomorrow' | 'paid' } after the student tells the owner about cash
    receipts: [
      { month: 'October 2026', amount: 7220, method: 'UPI', date: '05 Oct 2026', receipt: 'RCP-1042' },
      { month: 'September 2026 + deposit', amount: 13000, method: 'Online', date: '05 Sep 2026', receipt: 'RCP-0987' },
    ],
  },
  myIssues: [],
  // sponsored cards for student Home (local shops near the hostel). Empty = show the "Ad space" box.
  // Never shown on owner screens or on payment / ID screens.
  studentAds: [],

  sampleAd: { shop: 'QuickWash Laundry', offer: 'Pickup from your hostel · ₹49/kg · 24h', icon: 'shirt-outline', action: 'Call' },
  // notices the owner posted for all students (shown on student Home)
  // the owner posts these from the owner app; when there are none, students see the default message
  ownerNotices: [],
  defaultNotice: { icon: 'sparkles-outline', title: 'Keep the hostel clean', body: 'Please keep your room and common areas clean.', when: '' },
};

// ---------------- derived numbers ----------------
export const hostel = () => app.hostels[app.currentHostel];
export const totalBeds = () => app.rooms.reduce((s, r) => s + r.beds.length, 0);
export const countBeds = (state) => app.rooms.reduce((s, r) => s + r.beds.filter((b) => b === state).length, 0);
export const expectedRent = () => app.tenants.reduce((s, t) => s + t.rent, 0);
export const collectedRent = () => app.tenants.filter((t) => t.status === 'paid').reduce((s, t) => s + t.rent, 0);
/** Late fee (owner setting in the Rent tab): days late × amount per day, 0 when switched off. */
export const lateFee = (t) => (app.lateFeeOn && app.lateFeePerDay > 0 && t.status === 'late' ? t.daysLate * app.lateFeePerDay : 0);
export const pendingTenants = () => app.tenants.filter((t) => t.status === 'pending' || t.status === 'late');
/** Prototype "today" is 20 Oct 2026 for both apps (owner and student). Tenants whose rent day is today (paid or not). */
export const TODAY_LABEL = '20 Oct';
export function protoToday() { return new Date(2026, 9, 20); }
export function dueToday() {
  const all = app.tenants.filter((t) => t.dueToday);
  const unpaid = all.filter((t) => t.status !== 'paid');
  const total = all.reduce((s, t) => s + t.rent, 0);
  const pending = unpaid.reduce((s, t) => s + t.rent, 0);
  return { total, paid: total - pending, pending, unpaid };
}
export const openComplaints = () => app.complaints.filter((c) => c.status !== 'resolved').length;
export const unreadCount = () => app.notifications.filter((n) => n.unread).length;
export const requestCount = () => app.paymentRequests.filter((p) => !p.online).length + app.joinRequests.length;
/** Beds and alerts shown on the My hostels card. */
export function hostelStats(i) {
  const h = app.hostels[i];
  if (h.id === 'h1') return { filled: countBeds('filled'), free: countBeds('vacant'), hold: countBeds('held'), alerts: requestCount() + openComplaints() };
  return h.stats || { filled: 0, free: 0, hold: 0, alerts: 0 };
}
// ---------------- Phase 1: rooms typed by tenants ----------------
const mostCommon = (vals) => {
  const n = {};
  vals.forEach((v) => (n[v] = (n[v] || 0) + 1));
  return vals.slice().sort((a, b) => n[b] - n[a])[0];
};
const uniq = (vals) => [...new Set(vals)];
export const FLOOR_OPTIONS = ['Ground', '1st', '2nd', '3rd', '4th', '5th', '6th'];
export const floorLabel = (f) => (String(f) === '0' ? 'Ground floor' : `Floor ${f}`);

/** One row per room the tenants typed: what they entered, and whether the owner must fix it. */
export function roomTable() {
  const byRoom = {};
  app.roomEntries.forEach((e) => (byRoom[e.room] = byRoom[e.room] || []).push(e));
  return Object.keys(byRoom).sort().map((no) => {
    const list = byRoom[no];
    const fix = app.roomFixes[no];
    const sharings = uniq(list.map((e) => e.sharing));
    const prices = uniq(list.map((e) => e.price));
    const deposits = uniq(list.map((e) => e.deposit));
    const value = fix || {
      floor: mostCommon(list.map((e) => e.floor)),
      sharing: mostCommon(list.map((e) => e.sharing)),
      price: mostCommon(list.map((e) => e.price)),
      deposit: mostCommon(list.map((e) => e.deposit)),
    };
    const clash = !fix && (sharings.length > 1 || prices.length > 1);
    return {
      room: no, entries: list, sharings, prices, deposits, ...value, count: list.length,
      status: fix && fix.confirmed ? 'confirmed' : clash ? 'fix' : 'ok',
    };
  });
}

/** Price by sharing, built from the room table. */
export function sharingPrices() {
  const rows = roomTable();
  return uniq(rows.map((r) => r.sharing)).sort((a, b) => a - b).map((s) => {
    const rs = rows.filter((r) => r.sharing === s);
    // rooms still to fix count every price / deposit their tenants typed
    const all = (k, many) => uniq(rs.flatMap((r) => (r.status === 'fix' ? r[many] : [r[k]])));
    return { sharing: s, rooms: rs.length, prices: all('price', 'prices'), deposits: all('deposit', 'deposits') };
  });
}

/** True when the student skips "Room selection" (owner's bed QR, or Phase 1 room entry). */
export const shortFlow = () => !!(app.draft.booked || app.hostels[0].tenantRoomEntry);

/** Lines of the student's current bill. Extra charges and late fee only when the owner turned them on. */
export function billParts() {
  const s = app.stay;
  const h = app.hostels[0];
  const parts = [{ key: 'rent', label: 'Rent', amount: s.rent }];
  if (h.electricitySeparate && s.electricity > 0) parts.push({ key: 'elec', label: 'Electricity', amount: s.electricity });
  if (h.laundry && s.laundry > 0) parts.push({ key: 'laundry', label: 'Laundry', amount: s.laundry });
  if (studentLateFee() > 0) parts.push({ key: 'late', label: `Late fee · ${s.daysLate} days × ${rupees(app.lateFeePerDay)}`, amount: studentLateFee() });
  return parts;
}
export const lateFeeActive = () => app.lateFeeOn && app.lateFeePerDay > 0;
export const studentLateFee = () => (lateFeeActive() && !app.stay.billPaid ? app.stay.daysLate * app.lateFeePerDay : 0);
export const billTotal = () => billParts().reduce((sum, p) => sum + p.amount, 0);
/** Part payments: any mix of cash / UPI / online counts towards this month's bill. */
export const billPaidSoFar = () => (app.stay.receipts || []).filter((r) => r.month === 'November 2026').reduce((sum, r) => sum + r.amount, 0);
export const billDue = () => Math.max(0, billTotal() - billPaidSoFar());
/** 'paid' | 'late' (after the fee date) | 'due' (before or on the fee date) */
export const feeState = () => (app.stay.billPaid ? 'paid' : app.stay.daysLate > 0 ? 'late' : 'due');

export function joiningRent() {
  const d = app.draft;
  if (!d.room) return 0;
  return d.stayType === 'monthly' ? d.room.rent : d.room.perDay * d.days;
}
export function joiningDeposit() {
  const d = app.draft;
  if (!d.room) return 0;
  return d.stayType === 'monthly' ? d.room.deposit : d.room.dayDeposit;
}
export const joiningTotal = () => joiningRent() + joiningDeposit();

// ---------------- owner actions ----------------

// ---- one student, two views: the student app (app.stay) and the owner's tenant row (t1) stay in step
const meTenant = () => app.tenants.find((t) => t.id === 't1');
function tenantPaid(method, amount, receipt) {
  const t = meTenant();
  if (!t) return;
  t.payments.unshift({ month: 'November rent', amount, method, date: 'Today', receipt });
  const left = billDue();
  if (left > 0) {
    t.status = 'part'; // part paid – owner's Rent list shows how much is still due
    t.dueLeft = left;
  } else {
    t.status = 'paid';
    t.dueLeft = 0;
    t.daysLate = 0;
    t.dueToday = false;
  }
}
/** Message for the student (shown in Fees until he taps OK; the tab shows how many are unread). */
function studentAlert(tab, text, tone) {
  const s = app.stay;
  s.alerts = [{ id: 'sa' + Date.now() + Math.random(), tab, text, tone, seen: false }, ...(s.alerts || [])];
}
function ownerAlert(title, body, kind) {
  app.notifications.unshift({ id: 'n' + Date.now() + Math.random(), title, body, time: 'Just now', today: true, unread: true, kind });
}

/**
 * The 12 checks (25 Oct 2026): 7 on the payment, 5 on the receipt the student added.
 * state: 'ok' | 'soft' (could not be checked – owner checks) | 'bad'
 */
export function runChecks({ amount, due, fromApp, utr, seconds, receipt }) {
  const h = app.hostels[0];
  const c = (group, label, state) => ({ group, label, state });
  const used = app.usedUtrs.includes(utr);
  return [
    c('pay', fromApp ? 'UPI app said “Success”' : 'UPI app did not reply', fromApp ? 'ok' : 'soft'),
    c('pay', fromApp ? 'Reply matches this payment' : 'Reply not received', fromApp ? 'ok' : 'soft'),
    c('pay', fromApp ? 'UTR filled by the UPI app' : 'UTR typed by student', fromApp ? 'ok' : 'soft'),
    c('pay', used ? 'UTR was used before' : 'UTR never used before', used ? 'bad' : 'ok'),
    c('pay', amount > due ? `Amount more than ${rupees(due)} due` : `Amount ${rupees(amount)} (due ${rupees(due)})`, amount > 0 && amount <= due ? 'ok' : 'bad'),
    c('pay', seconds < 8 ? `Back after ${seconds} s – too quick` : seconds > 600 ? 'Away too long in the UPI app' : 'Time in UPI app looks normal', seconds >= 8 && seconds <= 600 ? 'ok' : 'bad'),
    c('pay', app.stay.flagged ? 'Had “Not received” before' : 'No “Not received” before', app.stay.flagged ? 'bad' : 'ok'),
    c('receipt', 'Says “Successful”', receipt.status === 'Successful' ? 'ok' : 'bad'),
    c('receipt', receipt.payee === h.upiId ? `Paid to ${h.upiId} (owner)` : `Paid to ${receipt.payee} – not the owner`, receipt.payee === h.upiId ? 'ok' : 'bad'),
    c('receipt', 'Same UTR and amount', receipt.utr === utr && receipt.amount === amount ? 'ok' : 'bad'),
    c('receipt', receipt.old ? 'Receipt is older than the payment' : 'Time after tapping Pay', receipt.old ? 'bad' : 'ok'),
    c('receipt', app.usedReceipts.includes(receipt.hash) ? 'Image was used before' : 'New image (not used before)', app.usedReceipts.includes(receipt.hash) ? 'bad' : 'ok'),
  ];
}

export const actions = {
  login(staff) {
    app.loggedIn = true;
    app.isStaff = !!staff;
    if (staff) app.currentHostel = 0;
    notify();
  },
  logout() {
    app.loggedIn = false;
    notify();
  },
  /** Hostel photo (prototype: a bundled sample photo; null = show the short name). */
  setHostelPhoto(h, photo) {
    h.photo = photo;
    notify();
  },
  /** Prototype only: show the student fee card before the fee date, late, or paid. */
  setFeeDemo(state) {
    const s = app.stay;
    if (state === 'paid') {
      if (!s.billPaid) actions.payBill();
    } else {
      s.receipts = s.receipts.filter((r) => r.month !== 'November 2026');
      s.billPaid = false;
      s.daysLate = state === 'late' ? 4 : 0;
    }
    notify();
  },
  selectHostel(i) {
    app.currentHostel = i;
    notify();
  },
  removeHostel(i) {
    const cur = app.hostels[app.currentHostel];
    const h = app.hostels[i];
    // Removed, not deleted: kept in Removed hostels (tenants, rooms and payments stay) so it can be restored.
    const d = new Date();
    const two = (n) => String(n).padStart(2, '0');
    app.removedHostels.unshift({
      ...h,
      removedAt: `${two(d.getDate())}/${two(d.getMonth() + 1)}/${d.getFullYear()}`,
      removedTenants: hostelStats(i).filled,
    });
    app.hostels.splice(i, 1);
    const k = app.hostels.indexOf(cur);
    app.currentHostel = k >= 0 ? k : 0;
    notify();
  },
  /** Bring a removed hostel back: shown in My hostels again, open for joins. */
  restoreHostel(h) {
    const { removedAt, removedTenants, ...hostelData } = h;
    app.removedHostels = app.removedHostels.filter((x) => x.id !== h.id);
    app.hostels.push(hostelData);
    notify();
  },
  addHostel(h) {
    // each hostel keeps its colour even when others are removed
    // (first free colour; if all 5 are used, the colours repeat)
    const used = [...app.hostels, ...app.removedHostels].map((x) => (x.colorIndex ?? 0) % 5);
    const free = [0, 1, 2, 3, 4].find((c) => !used.includes(c));
    app.hostels.push(makeHostel({ ...h, colorIndex: free ?? app.hostels.length }));
    notify();
  },
  confirmPayment(p, amount) {
    if (p.join) return actions.approveNewJoiner(p, amount);
    if (p.id === 'cash-me') {
      // the student told the owner about cash → now paid, receipt in the student app, tenant paid in Rent
      app.paymentRequests = app.paymentRequests.filter((x) => x !== p);
      const receipt = 'RCP-' + (1300 + app.stay.receipts.length);
      app.stay.receipts.unshift({ month: 'November 2026', amount: amount ?? p.amount, method: 'Cash', date: 'Today', receipt });
      app.stay.billPaid = billDue() <= 0;
      if (app.stay.billPaid) app.stay.daysLate = 0;
      app.stay.cashPending = null;
      tenantPaid('Cash', amount ?? p.amount, receipt);
      studentAlert('fee', `Owner got your cash of ${rupees(amount ?? p.amount)}. Receipt ${receipt} is below.`, 'good');
      return notify();
    }
    if (p.id === 'pay-me' && p.pendingCheck) {
      // checks failed, owner found the money → paid now, receipt for the student
      app.paymentRequests = app.paymentRequests.filter((x) => x !== p);
      const s = app.stay;
      const rc = 'RCP-' + (1300 + s.receipts.length);
      s.receipts.unshift({ month: 'November 2026', amount: amount ?? p.amount, method: p.method, date: 'Today', receipt: rc, utr: p.utr });
      s.billPaid = billDue() <= 0;
      if (s.billPaid) s.daysLate = 0;
      s.checkPending = null;
      tenantPaid(p.method, amount ?? p.amount, rc);
      studentAlert('fee', `Owner confirmed your payment of ${rupees(amount ?? p.amount)}. Receipt ${rc} is below.`, 'good');
      return notify();
    }
    if (p.id === 'pay-me') {
      // owner found the UPI / bank money → tenant paid in Rent (student already shows paid)
      app.paymentRequests = app.paymentRequests.filter((x) => x !== p);
      tenantPaid(p.method, amount ?? p.amount, app.stay.receipts[0] ? app.stay.receipts[0].receipt : '');
      return notify();
    }
    app.paymentRequests = app.paymentRequests.filter((x) => x !== p);
    app.tenants.forEach((t) => {
      if (t.name === p.tenantName) {
        t.status = 'paid';
        t.daysLate = 0;
        t.payments.unshift({ month: p.purpose, amount: amount ?? p.amount, method: p.method, date: 'Today', receipt: 'RCP-' + (1100 + t.payments.length) });
      }
    });
    notify();
  },
  rejectPayment(p) {
    if (p.id === 'cash-me') {
      app.stay.cashPending = null;
      studentAlert('fee', `Owner says he did not get your cash of ${rupees(p.amount)}. Please pay at the office and tell him again.`, 'bad');
    }
    if (p.id === 'pay-me' && p.pendingCheck) {
      const s = app.stay;
      s.checkPending = null;
      s.flagged = true;
      studentAlert('fee', `Owner did not get your payment of ${rupees(p.amount)} (UTR …${(p.utr || '').slice(-4)}). Check your UPI app or pay again.`, 'bad');
      app.paymentRequests = app.paymentRequests.filter((x) => x !== p);
      return notify();
    }
    if (p.id === 'pay-me') {
      // owner did not get the money → student's fee goes back to unpaid with a message
      const s = app.stay;
      s.billPaid = false;
      s.receipts = s.receipts.filter((r) => r.receipt !== p.receipt);
      studentAlert('fee', `Owner did not get your ${p.method} payment of ${rupees(p.amount)}. Please check and pay again.`, 'bad');
    }
    app.paymentRequests = app.paymentRequests.filter((x) => x !== p);
    notify();
  },
  /** Approve a new joiner's payment: tenant added, bed filled, the student's page shows "Approved". */
  approveNewJoiner(p, amount) {
    const j = p.join;
    app.paymentRequests = app.paymentRequests.filter((x) => x !== p);
    const r = app.rooms.find((x) => x.number === j.room);
    if (r && j.bedIndex >= 0 && j.bedIndex < r.beds.length) r.beds[j.bedIndex] = 'filled';
    app.tenants.unshift(tenant({
      id: 't' + Date.now(), name: j.name, mobile: j.mobile, parentMobile: j.parent || '—', room: j.room, bed: bedLabel(j.bedIndex),
      joined: '20 Oct 2026', rent: j.rent, deposit: j.deposit, status: 'paid', dueDate: '20 Nov',
      org: j.org, office: j.orgAddress || '', address: j.homeAddress || '', reference: j.reference || '', idLast4: j.idLast4,
      payments: [{ month: 'Oct 2026 + deposit', amount: amount ?? p.amount, method: p.method, date: '20 Oct', receipt: 'RCP-' + (1400 + app.tenants.length) }],
    }));
    if (app.stay.room === j.room && app.stay.bed === bedLabel(j.bedIndex)) {
      app.stay.status = 'Active';
      app.stay.approved = true;
      app.stay.justApproved = true; // student Home shows "Bed booked!" once
      app.stay.receipts.unshift({ month: 'Joining · rent + deposit', amount: amount ?? p.amount, method: p.method, date: 'Today', receipt: 'RCP-' + Date.now().toString().slice(-4) });
    }
    if (app.qrHold && app.qrHold.room === j.room && app.qrHold.bedIndex === j.bedIndex) app.qrHold = null;
    app.notifications.unshift({ id: 'n' + Date.now(), title: 'New tenant added', body: `${j.name} · Room ${j.room} · Bed ${bedLabel(j.bedIndex)}`, time: 'Just now', today: true, unread: false, kind: 'join' });
    notify();
  },
  /** Owner rejects a new joiner (25 Oct 2026): reason required, bed free for others again, student sees the reason. */
  rejectJoiner(p, reason) {
    const j = p.join;
    app.paymentRequests = app.paymentRequests.filter((x) => x !== p);
    const r = app.rooms.find((x) => x.number === j.room);
    if (r && r.beds[j.bedIndex] === 'held') r.beds[j.bedIndex] = 'vacant';
    if (app.qrHold && app.qrHold.room === j.room && app.qrHold.bedIndex === j.bedIndex) app.qrHold = null;
    const s = app.stay;
    if (s.room === j.room && s.bed === bedLabel(j.bedIndex) && !s.approved) {
      s.status = 'Rejected';
      s.rejected = { reason, amount: p.amount, room: j.room, bed: bedLabel(j.bedIndex) };
    }
    notify();
  },
  approveJoin(j) {
    app.joinRequests = app.joinRequests.filter((x) => x !== j);
    app.tenants.unshift(tenant({ id: 't' + Date.now(), name: j.name, mobile: j.mobile, parentMobile: '—', room: j.room, bed: j.bed, joined: j.existing ? j.joinedOn : 'Today', rent: j.rent || 6500, deposit: j.deposit ?? 6500, status: j.existing ? 'pending' : 'paid', dueDate: '—' }));
    const r = app.rooms.find((x) => x.number === j.room);
    const idx = j.bed.charCodeAt(0) - 65;
    if (r && idx >= 0 && idx < r.beds.length) r.beds[idx] = 'filled';
    notify();
  },
  rejectJoin(j) {
    app.joinRequests = app.joinRequests.filter((x) => x !== j);
    notify();
  },
  setComplaintStatus(c, status, reply) {
    c.status = status;
    c.seen = false; // student sees a number on Report issue until he opens this issue
    if (reply) c.reply = reply;
    notify();
  },
  markAllRead() {
    app.notifications.forEach((n) => (n.unread = false));
    notify();
  },
  /** Owner taps Book on a free bed: hold it for 15 minutes for the QR (student flow). */
  ownerHoldBed(roomNumber, bedIndex) {
    const r = app.rooms.find((x) => x.number === roomNumber);
    if (!r) return null;
    if (r.beds[bedIndex] === 'vacant') r.beds[bedIndex] = 'held';
    app.qrHold = { room: roomNumber, bedIndex, until: (app.qrHold && app.qrHold.room === roomNumber && app.qrHold.bedIndex === bedIndex && app.qrHold.until > Date.now()) ? app.qrHold.until : Date.now() + 15 * 60 * 1000 };
    notify();
    return app.qrHold;
  },
  /** Owner cancels the QR booking before the student starts. */
  ownerReleaseBed(roomNumber, bedIndex) {
    const r = app.rooms.find((x) => x.number === roomNumber);
    if (r && r.beds[bedIndex] === 'held') r.beds[bedIndex] = 'vacant';
    app.qrHold = null;
    notify();
  },
  /** Prototype: the student "scans" the owner's QR and starts the 3-step flow for that bed. */
  startBookedFlow(roomNumber, bedIndex) {
    const r = app.rooms.find((x) => x.number === roomNumber);
    app.draft = newDraft();
    Object.assign(app.draft, { booked: true, room: r, bedIndex, holdUntil: (app.qrHold && app.qrHold.until) || Date.now() + 15 * 60 * 1000 });
    notify();
  },
  /** Owner books a free bed. Cash = paid now (tenant added); UPI / Bank = bed held while the student pays. */
  bookBed({ roomNumber, bedIndex, name, mobile, stayType, days, method }) {
    const r = app.rooms.find((x) => x.number === roomNumber);
    if (!r || r.beds[bedIndex] !== 'vacant') return { ok: false };
    const monthly = stayType === 'monthly';
    const rent = monthly ? r.rent : r.perDay * days;
    const deposit = monthly ? r.deposit : r.dayDeposit;
    const bed = bedLabel(bedIndex);
    if (method === 'Cash') {
      r.beds[bedIndex] = 'filled';
      app.tenants.push(tenant({
        id: 't' + Date.now(), name, mobile, parentMobile: '', room: r.number, bed, joined: '20 Oct 2026',
        rent: r.rent, deposit, status: 'paid', dueDate: monthly ? '13 Nov' : `${13 + days} Oct`, stayType: monthly ? 'monthly' : 'dayWise',
        payments: [{ month: monthly ? 'Oct 2026 + deposit' : `${days} days + deposit`, amount: rent + deposit, method: 'Cash', date: '20 Oct', receipt: 'RCP-' + (1300 + app.tenants.length) }],
      }));
    } else {
      r.beds[bedIndex] = 'held';
    }
    notify();
    return { ok: true, total: rent + deposit };
  },
  addRoom(r) {
    app.rooms.push(r);
    app.rooms.sort((a, b) => a.number.localeCompare(b.number));
    notify();
  },
  recordPayment(t, amount, method, date) {
    const receipt = 'RCP-' + (1200 + t.payments.length);
    t.payments.unshift({ month: 'Recorded payment', amount, method, date, receipt });
    t.status = 'paid';
    t.daysLate = 0;
    if (t.id === 't1') {
      // the owner recorded it → the student's fee card turns paid and the receipt shows in Fees
      const s = app.stay;
      s.receipts.unshift({ month: 'November 2026', amount, method, date, receipt });
      s.billPaid = billDue() <= 0;
      if (s.billPaid) s.daysLate = 0;
      if (!s.billPaid) { t.status = 'part'; t.dueLeft = billDue(); }
      s.cashPending = null;
      app.paymentRequests = app.paymentRequests.filter((p) => p.id !== 'cash-me' && p.id !== 'pay-me');
      studentAlert('fee', `Owner recorded your payment of ${rupees(amount)} (${method}). Receipt ${receipt} is below.`, 'good');
    }
    notify();
  },
  vacate(t) {
    if (t.id === 't1') app.stay.left = { on: fmtDate(protoToday()), deposit: t.deposit, short: app.stay.noticeOnTime === false };
    app.tenants = app.tenants.filter((x) => x !== t);
    app.notices = app.notices.filter((n) => n.tenantId !== t.id);
    const r = app.rooms.find((x) => x.number === t.room);
    const idx = t.bed.charCodeAt(0) - 65;
    if (r && idx >= 0 && idx < r.beds.length) r.beds[idx] = 'vacant';
    notify();
  },
  addStaff(s) {
    app.staff.push(s);
    notify();
  },
  touch: notify,

  /** Owner corrects one room (no message to the students) and confirms it. */
  fixRoom(no, v) {
    app.roomFixes[no] = { ...v, confirmed: true };
    actions.addConfirmedRoom(no);
    notify();
  },
  /** Confirm every room the tenants entered the same way. */
  confirmCorrectRooms() {
    let n = 0;
    roomTable().forEach((r) => {
      if (r.status !== 'ok') return;
      app.roomFixes[r.room] = { floor: r.floor, sharing: r.sharing, price: r.price, deposit: r.deposit, confirmed: true };
      actions.addConfirmedRoom(r.room);
      n += 1;
    });
    notify();
    return n;
  },
  /** A confirmed room becomes a real room (beds filled for the tenants who entered it). */
  addConfirmedRoom(no) {
    const row = roomTable().find((r) => r.room === no);
    if (!row) return;
    const filled = Math.min(row.count, row.sharing);
    const beds = Array.from({ length: row.sharing }, (_, i) => (i < filled ? 'filled' : 'vacant'));
    const perDay = Math.round(row.price / 30 / 10) * 10;
    const existing = app.rooms.find((r) => r.number === no);
    if (existing) Object.assign(existing, { floor: parseInt(row.floor, 10) || 0, sharing: row.sharing, rent: row.price, deposit: row.deposit, beds, perDay });
    else app.rooms.push(room(no, parseInt(row.floor, 10) || 0, row.sharing, row.price, row.deposit, perDay, 1000, beds, []));
    app.rooms.sort((a, b) => a.number.localeCompare(b.number));
  },
  /** Owner edits the price / deposit for one sharing type (all rooms of that sharing). */
  setSharingPrice(sharing, price, deposit) {
    roomTable().filter((r) => r.sharing === sharing).forEach((r) => {
      app.roomFixes[r.room] = { floor: r.floor, sharing, price, deposit, confirmed: r.status === 'confirmed' };
      if (r.status === 'confirmed') actions.addConfirmedRoom(r.room);
    });
    notify();
  },
  /** Student typed a room number: fill and lock the details if the owner already set that room. */
  lookupTypedRoom(no) {
    const d = app.draft;
    const r = app.rooms.find((x) => x.number === no.trim());
    if (r) {
      Object.assign(d, { roomFloor: String(r.floor), roomSharing: r.sharing, roomPrice: String(r.rent), roomDeposit: String(r.deposit), roomLocked: true });
    } else if (d.roomLocked) {
      Object.assign(d, { roomFloor: '', roomSharing: 0, roomPrice: '', roomDeposit: '', roomLocked: false });
    }
  },
  /** Use the typed room for the rest of the joining flow. */
  useTypedRoom() {
    const d = app.draft;
    const no = d.roomNo.trim();
    const price = parseInt(d.roomPrice, 10) || 0;
    const deposit = parseInt(d.roomDeposit, 10) || 0;
    let r = app.rooms.find((x) => x.number === no);
    if (!r) {
      const taken = app.roomEntries.filter((e) => e.room === no).length;
      const sharing = d.roomSharing || 1;
      r = room(no, parseInt(d.roomFloor, 10) || 0, sharing, price, deposit, Math.round(price / 30 / 10) * 10, deposit, Array(sharing).fill('vacant'), []);
      r.fromTenant = true;
      d.room = r;
      d.bedIndex = taken % sharing;
    } else {
      d.room = r;
      const free = r.beds.indexOf('vacant');
      d.bedIndex = free >= 0 ? free : 0;
    }
    d.roomEntry = true;
    notify();
  },

  // ---------------- student actions ----------------
  startStudentFlow() {
    app.draft = newDraft();
    notify();
  },
  holdBed(r, i) {
    app.draft.room = r;
    app.draft.bedIndex = i;
    app.draft.holdUntil = Date.now() + 15 * 60 * 1000;
    notify();
  },
  submitJoining() {
    const d = app.draft;
    const r = d.room;
    const s = app.stay;
    Object.assign(s, {
      name: d.name || 'New Student',
      mobile: d.mobile || '98765 43210',
      room: r.number,
      bed: bedLabel(d.bedIndex),
      sharing: r.sharing,
      stayType: d.stayType,
      rent: r.rent,
      perDay: r.perDay,
      deposit: d.stayType === 'monthly' ? r.deposit : r.dayDeposit,
      status: 'Waiting for owner approval',
      approved: false,
      billPaid: true,
      receipts: [],
      noticeGiven: false,
      parent: d.parent, reference: d.reference, org: d.org, orgAddress: d.office, homeAddress: d.homeAddress,
      idLast4: (d.idNumber || '').replace(/\D/g, '').slice(-4) || d.idLast4,
      checkIn: '20 Oct 2026', dueDate: '20 Nov 2026',
      // 25 Oct 2026: booking status page (new joiner waits for the owner to confirm details + payment)
      existing: !!d.existing, rejected: null, justApproved: false,
      paidTotal: d.existing ? 0 : joiningTotal(), payMethod: d.payApp && d.payMethod === 'upi' ? d.payApp : { online: 'Online', upi: 'UPI', bank: 'Bank', cash: 'Cash' }[d.payMethod], utr: d.utr || '',
    });
    if (d.utr) app.usedUtrs.push(d.utr);
    if (d.payReceipt) app.usedReceipts.push(d.payReceipt.hash);
    // the bed stays held until the owner approves (then it becomes filled)
    if (r.beds[d.bedIndex] === 'vacant') r.beds[d.bedIndex] = 'held';
    // Phase 1: remember what the student typed for the owner's "Rooms from tenants" table
    if (d.roomEntry && d.roomNo.trim()) {
      app.roomEntries.push({ id: 'e' + Date.now(), name: s.name, room: d.roomNo.trim(), floor: d.roomFloor || '0', sharing: d.roomSharing || r.sharing, price: parseInt(d.roomPrice, 10) || r.rent, deposit: parseInt(d.roomDeposit, 10) || 0 });
    }
    const method = { online: 'Online', upi: 'UPI', bank: 'Bank', cash: 'Cash' }[d.payMethod];
    if (!d.existing) {
      app.paymentRequests.unshift({
        id: 'p' + Date.now(), tenantName: s.name, room: `${r.number} · Bed ${s.bed}`, amount: joiningTotal(), method,
        purpose: 'Joining · rent + deposit', time: 'Just now', utr: d.utr, note: `SUNRISE-${r.number}${s.bed}-JOIN`, online: d.payMethod === 'online',
        app: d.payApp, checks: d.payChecks, receipt: d.payReceipt,
        // new joiner: approving adds the tenant and fills the bed
        join: { name: s.name, mobile: s.mobile, parent: d.parent, reference: d.reference, org: d.org, orgAddress: d.office, homeAddress: d.homeAddress,
          idLast4: s.idLast4, room: r.number, bedIndex: d.bedIndex, rent: r.rent, deposit: s.deposit },
      });
    } else {
      app.joinRequests.unshift({ id: 'j' + Date.now(), name: s.name, mobile: s.mobile, room: r.number, bed: s.bed, stayType: d.stayType, time: 'Just now', existing: true, joinedOn: fmtDate(d.joinDate), rent: r.rent, deposit: s.deposit });
    }
    app.notifications.unshift({ id: 'n' + Date.now(), title: d.existing ? 'Existing tenant request' : 'New joining payment', body: `${s.name} · Room ${r.number} · Bed ${s.bed}`, time: 'Just now', today: true, unread: true, kind: d.existing ? 'join' : 'pay' });
    notify();
  },
  /**
   * Rent by UPI with checks (25 Oct 2026). Every payment waits for the owner in Home › Confirm payments
   * (nothing counts as paid until he confirms). The 12 checks are shown to him: all passed = green
   * "Confirm"; any failed = amber "Check" with the reasons.
   */
  payRentUpi({ amount, app: appName, utr, receipt, checks, pass }) {
    const s = app.stay;
    app.usedUtrs.push(utr);
    app.usedReceipts.push(receipt.hash);
    s.cashPending = null;
    s.checkPending = { amount, utr, pass };
    app.paymentRequests = app.paymentRequests.filter((p) => p.id !== 'cash-me' && p.id !== 'pay-me');
    app.paymentRequests.unshift({
      id: 'pay-me', pendingCheck: true, pass, tenantName: s.name, room: `${s.room} · Bed ${s.bed}`, amount, method: 'UPI', app: appName,
      purpose: pass ? 'November rent' : 'November rent · checks failed', time: 'Just now', utr, note: `SUNRISE-${s.room}${s.bed}-NOV`, receipt, checks,
    });
    ownerAlert(pass ? 'Payment to confirm' : 'Payment to check',
      `${s.name} (${s.room}) paid ${rupees(amount)} by ${appName} · UTR …${utr.slice(-4)} · ${pass ? `all ${checks.length} checks passed` : 'some checks failed'}. Check your bank and confirm.`, 'pay');
    notify();
  },
  payBill(method = 'Online', amount) {
    const s = app.stay;
    amount = amount || billDue();
    s.cashPending = null;
    app.paymentRequests = app.paymentRequests.filter((p) => p.id !== 'cash-me' && p.id !== 'pay-me');
    const receipt = 'RCP-' + (1300 + s.receipts.length);
    s.receipts.unshift({ month: 'November 2026', amount, method, date: 'Today', receipt });
    s.billPaid = billDue() <= 0;
    if (s.billPaid) s.daysLate = 0;
    const part = s.billPaid ? '' : ` (part · ${rupees(billDue())} still due)`;
    if (method === 'Online') {
      tenantPaid('Online', amount, receipt);
      ownerAlert('Online payment received', `${s.name} (${s.room}) paid ${rupees(amount)} online${part}`, 'pay');
    } else {
      app.paymentRequests.unshift({ id: 'pay-me', tenantName: s.name, room: `${s.room} · Bed ${s.bed}`, amount, method, purpose: s.billPaid ? 'November rent' : 'November rent · part', time: 'Just now', note: `SUNRISE-${s.room}${s.bed}-NOV`, check: true, receipt });
      ownerAlert('Payment to check', `${s.name} (${s.room}) says he paid ${rupees(amount)} by ${method}${part}. Check your bank.`, 'pay');
    }
    notify();
  },
  reportIssue(category, text, hasPhoto) {
    const c = { id: 'm' + Date.now(), category, text, student: app.stay.name, room: app.stay.room, time: 'Just now', status: 'open', hasPhoto, reply: '', seen: true };
    app.myIssues.unshift(c);
    app.complaints.unshift(c);
    app.notifications.unshift({ id: 'n' + Date.now(), title: 'New complaint', body: `${app.stay.name} (${app.stay.room}): ${text}`, time: 'Just now', today: true, unread: true, kind: 'issue' });
    notify();
  },
  giveNotice(leaveOn, onTime, days) {
    const s = app.stay;
    const again = s.noticeGiven;
    s.noticeGiven = true;
    s.leaveOn = leaveOn;
    s.noticeOnTime = onTime;
    s.noticeDaysGiven = days || 0;
    if (!again) s.noticeGivenOn = fmtDate(protoToday());
    s.status = 'Notice given';
    ownerAlert(again ? 'Leaving date changed' : 'Vacate notice', `${s.name} (${s.room}) leaves on ${leaveOn}${onTime ? '' : ' · short notice'}`, 'notice');
    app.notices = app.notices.filter((n) => n.tenantId !== 'me');
    app.notices.unshift({ tenantId: 'me', name: s.name, room: `${s.room} · Bed ${s.bed}`, givenOn: 'Today', leaveOn, deposit: s.deposit, onTime });
    notify();
  },
  // student tells the owner about a cash payment → owner gets an alert + a request to confirm
  tellOwnerCash(when, amount) {
    const s = app.stay;
    amount = amount || billDue();
    s.cashPending = { when, amount };
    const say = when === 'paid' ? 'says he paid' : when === 'today' ? 'will pay today' : 'will pay tomorrow';
    app.paymentRequests = app.paymentRequests.filter((p) => p.id !== 'cash-me');
    app.paymentRequests.unshift({ id: 'cash-me', tenantName: s.name, room: `${s.room} · Bed ${s.bed}`, amount, method: 'Cash', purpose: (when === 'paid' ? 'November rent · paid cash' : `November rent · cash ${when}`) + (amount < billDue() ? ' · part' : ''), time: 'Just now' });
    app.notifications.unshift({ id: 'nc' + Date.now(), title: 'Cash payment', body: `${s.name} (${s.room}) ${say} ₹${amount.toLocaleString('en-IN')} cash`, time: 'Just now', today: true, unread: true, kind: 'pay' });
    notify();
  },
  requestDataDelete() {
    const s = app.stay;
    s.deleteRequested = true;
    const t = meTenant();
    if (t) t.deleteRequested = 'Today';
    ownerAlert('Data deletion request', `${s.name} (${s.room}) asked to delete his details after leaving`, 'join');
    notify();
  },
  cancelCash() {
    app.stay.cashPending = null;
    app.paymentRequests = app.paymentRequests.filter((p) => p.id !== 'cash-me');
    notify();
  },
  cancelNotice() {
    const s = app.stay;
    s.noticeGiven = false;
    s.leaveOn = '';
    s.noticeGivenOn = '';
    s.status = 'Active';
    ownerAlert('Notice cancelled', `${s.name} (${s.room}) is staying – vacate notice cancelled`, 'notice');
    app.notices = app.notices.filter((n) => n.tenantId !== 'me');
    notify();
  },
  extendStay(days) {
    const s = app.stay;
    s.receipts.unshift({ month: `Extend stay · ${days} days`, amount: days * s.perDay, method: 'Online', date: 'Today', receipt: 'RCP-' + (1400 + s.receipts.length) });
    s.checkOut = `Extended by ${days} days`;
    notify();
  },
};

// ---------------- formatting ----------------
export function rupees(v) {
  const s = Math.round(v).toString();
  if (s.length <= 3) return '₹' + s;
  const last3 = s.slice(-3);
  let rest = s.slice(0, -3);
  const parts = [];
  while (rest.length > 2) {
    parts.unshift(rest.slice(-2));
    rest = rest.slice(0, -2);
  }
  if (rest) parts.unshift(rest);
  return '₹' + parts.join(',') + ',' + last3;
}

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
export const fmtDate = (d) => `${String(d.getDate()).padStart(2, '0')} ${MONTHS[d.getMonth()]} ${d.getFullYear()}`;
export const addDays = (d, n) => new Date(d.getTime() + n * 86400000);
export const ordinal = (n) => {
  if (n >= 11 && n <= 13) return n + 'th';
  return n + ({ 1: 'st', 2: 'nd', 3: 'rd' }[n % 10] || 'th');
};
