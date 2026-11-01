// Bottom sheets, confirm dialogs and toasts shown above every screen.
import React, { useEffect, useState } from 'react';
import { KeyboardAvoidingView, Modal, Platform, Pressable, ScrollView, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { C, T, Btn } from './ui';

let setSheetState = null;
let setToastState = null;
let toastTimer = null;

/** Show a bottom sheet. `render(close)` returns its content. */
export function showSheet(render) {
  setSheetState && setSheetState({ render });
}
export function closeSheet() {
  setSheetState && setSheetState(null);
}

/** Yes / no confirmation built into the app. Resolves true or false. */
export function confirm({ title, text, confirmLabel = 'OK', danger = false }) {
  return new Promise((resolve) => {
    showSheet((close) => (
      <View style={{ gap: 10 }}>
        <T size={20} weight="800">{title}</T>
        {text ? <T color={C.muted} style={{ lineHeight: 20 }}>{text}</T> : null}
        <View style={{ height: 8 }} />
        <Btn title={confirmLabel} variant={danger ? 'danger' : 'primary'} onPress={() => { close(); resolve(true); }} />
        <Btn title="Cancel" variant="text" onPress={() => { close(); resolve(false); }} />
      </View>
    ));
  });
}

export function toast(message) {
  if (!setToastState) return;
  setToastState(message);
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => setToastState(null), 2600);
}

export function OverlayHost() {
  const [sheet, setSheet] = useState(null);
  const [toastMsg, setToast] = useState(null);
  const insets = useSafeAreaInsets();

  useEffect(() => {
    setSheetState = setSheet;
    setToastState = setToast;
    return () => {
      setSheetState = null;
      setToastState = null;
    };
  }, []);

  const close = () => setSheet(null);

  return (
    <>
      <Modal visible={!!sheet} transparent animationType="slide" onRequestClose={close}>
        <KeyboardAvoidingView behavior={Platform.OS === 'ios' ? 'padding' : undefined} style={{ flex: 1 }}>
          <Pressable style={{ flex: 1, backgroundColor: 'rgba(10,20,40,0.45)' }} onPress={close} />
          <View style={{ backgroundColor: '#fff', borderTopLeftRadius: 24, borderTopRightRadius: 24, paddingHorizontal: 20, paddingTop: 12, paddingBottom: 16 + insets.bottom, maxHeight: '85%' }}>
            <View style={{ alignSelf: 'center', width: 40, height: 5, borderRadius: 3, backgroundColor: C.line, marginBottom: 14 }} />
            <ScrollView keyboardShouldPersistTaps="handled">{sheet ? sheet.render(close) : null}</ScrollView>
          </View>
        </KeyboardAvoidingView>
      </Modal>
      {toastMsg ? (
        <View pointerEvents="none" style={{ position: 'absolute', left: 16, right: 16, bottom: 90 + insets.bottom, backgroundColor: '#1d2a40', borderRadius: 12, paddingVertical: 12, paddingHorizontal: 16 }}>
          <T color="#fff" weight="600">{toastMsg}</T>
        </View>
      ) : null}
    </>
  );
}
