// My Hostel – clickable prototype for Expo Go.
// All data is sample data in memory (src/state.js). No database, SMS or payments yet.
import React, { useEffect, useReducer } from 'react';
import { View } from 'react-native';
import { StatusBar } from 'expo-status-bar';
import { SafeAreaProvider } from 'react-native-safe-area-context';
import {
  useFonts,
  PlusJakartaSans_400Regular,
  PlusJakartaSans_500Medium,
  PlusJakartaSans_600SemiBold,
  PlusJakartaSans_700Bold,
  PlusJakartaSans_800ExtraBold,
} from '@expo-google-fonts/plus-jakarta-sans';

import { Navigator } from './src/nav';
import { OverlayHost } from './src/overlay';
import { C, setFontsReady } from './src/ui';
import * as Student from './src/screens/student';
import { StudentIssues, StudentShell } from './src/screens/studentShell';
import * as Owner from './src/screens/owner';
import { OwnerShell, TenantsScreen } from './src/screens/ownerShell';
import * as More from './src/screens/ownerMore';
import { UpiReceipt } from './src/screens/upiPay';
import * as Pre from './src/screens/preReg';

export const SCREENS = {
  // owner
  Login: Owner.Login,
  SignUp: Owner.SignUp,
  ForgotPassword: Owner.ForgotPassword,
  Welcome: Owner.Welcome,
  MyHostels: Owner.MyHostels,
  RegisterHostel: Owner.RegisterHostel,
  RemovedHostels: Owner.RemovedHostels,
  SetupChecklist: Owner.SetupChecklist,
  OwnerShell,
  Tenants: TenantsScreen,
  TenantDetails: More.TenantDetails,
  RecordPayment: More.RecordPayment,
  Rooms: More.Rooms,
  TenantRooms: More.TenantRooms,
  SharingPrices: More.SharingPrices,
  AddRoom: More.AddRoom,
  ShareBed: More.ShareBed,
  Complaints: More.Complaints,
  LeavingNotices: More.LeavingNotices,
  StudentNotices: More.StudentNotices,
  HostelSettings: More.HostelSettings,
  StaffLogins: More.StaffLogins,
  InviteStudents: More.InviteStudents,
  Notifications: More.Notifications,
  Reports: More.Reports,
  AppSettings: More.AppSettings,
  DeleteAccount: More.DeleteAccount,
  // student
  GetApp: Student.GetApp,
  StudentWelcome: Student.StudentWelcome,
  StudentProfile: Student.StudentProfile,
  RoomSelection: Student.RoomSelection,
  VerifyMobile: Student.VerifyMobile,
  HostelDetails: Student.HostelDetails,
  AvailableRooms: Student.AvailableRooms,
  YourDetails: Student.YourDetails,
  StayPayment: Student.StayPayment,
  Submitted: Student.Submitted,
  UpiReceipt,
  StudentShell,
  StudentIssues,
  ExtendStay: Student.ExtendStay,
  PaymentFailed: Student.PaymentFailed,
  BedTaken: Student.BedTaken,
  NoInternet: Student.NoInternet,
  DemoScreens: Student.DemoScreens,
  // student-first onboarding (1 Nov 2026)
  PreHub: Pre.PreHub,
  PreJoin: Pre.PreJoin,
  PreVerify: Pre.PreVerify,
  PreDetails: Pre.PreDetails,
  PreDates: Pre.PreDates,
  PreStatus: Pre.PreStatus,
  PreSms: Pre.PreSms,
  PreComplete: Pre.PreComplete,
  PreOwnerClaim: Pre.PreOwnerClaim,
  PreOwnerList: Pre.PreOwnerList,
  PreOwnerVerify: Pre.PreOwnerVerify,
  PreWelcome: Pre.PreWelcome,
  PreOwnerSignUp: Pre.PreOwnerSignUp,
  PreOwnerCheck: Pre.PreOwnerCheck,
  PreOwnerNo: Pre.PreOwnerNo,
  PreOwnerAccount: Pre.PreOwnerAccount,
  Privacy: Student.Privacy,
};

export default function App() {
  const [fontsLoaded] = useFonts({
    PlusJakartaSans_400Regular,
    PlusJakartaSans_500Medium,
    PlusJakartaSans_600SemiBold,
    PlusJakartaSans_700Bold,
    PlusJakartaSans_800ExtraBold,
  });
  const [, rerender] = useReducer((x) => x + 1, 0);
  useEffect(() => {
    setFontsReady(!!fontsLoaded);
    rerender();
  }, [fontsLoaded]);

  return (
    <SafeAreaProvider>
      <StatusBar style="dark" />
      <View style={{ flex: 1, backgroundColor: C.ground }}>
        <Navigator key={fontsLoaded ? 'fonts' : 'system'} screens={SCREENS} initial="Login" />
        <OverlayHost />
      </View>
    </SafeAreaProvider>
  );
}
