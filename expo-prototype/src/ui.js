// Shared look (Trust blue, 22 Oct 2026): solid blue #1560BD everywhere (no gradient), grey ground #F2F5F9,
// white cards with a thin #DCE3EC border + very light shadow, › arrows on tappable rows, lifted floating tab bar. Plus Jakarta Sans.
import React, { useEffect, useState } from 'react';
import { Image, Modal, Pressable, ScrollView, Switch, Text, TextInput, View } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useBackHandler, useNav } from './nav';
import { app, LANGUAGES, actions, bedLabel, cleanHostelName, initials, useApp } from './state';

export const C = {
  blue: '#1560BD',
  blueSoft: '#E8F0FA',
  ground: '#F2F5F9',
  card: '#FFFFFF',
  ink: '#14213D',
  muted: '#5C6782',
  line: '#DCE3EC',
  green: '#15803D',
  greenSoft: '#DCF3E3',
  amber: '#B45309',
  amberSoft: '#FFF1DC',
  red: '#DC2626',
  redSoft: '#FDE8E8',
  purple: '#6B4FBB',
  purpleSoft: '#EFEAFB',
  pink: '#B0306A',
  pinkSoft: '#FCE8F1',
};

/** One light colour set per hostel card, in order; new hostels take the next one. */
export const HOSTEL_COLORS = [
  { tint: '#F5F8FC', band: '#1560BD', border: '#B9CDEB', dark: '#0C447C', strong: '#1560BD', door: '#8FB0E0' },
];
export const hostelColor = (i) => HOSTEL_COLORS[i % HOSTEL_COLORS.length];

const FONT = {
  400: 'PlusJakartaSans_400Regular',
  500: 'PlusJakartaSans_500Medium',
  600: 'PlusJakartaSans_600SemiBold',
  700: 'PlusJakartaSans_700Bold',
  800: 'PlusJakartaSans_800ExtraBold',
};
let fontsReady = false;
export const setFontsReady = (v) => (fontsReady = v);
/** App font for raw TextInput styles, so typed text matches the rest of the app. */
export const appFont = (weight = '600') => (fontsReady ? { fontFamily: FONT[weight] || FONT[600] } : { fontWeight: weight });

/** Text in the app font. weight: '400' … '800'. */
export function T({ children, size = 14, weight = '500', color = C.ink, style, center, numberOfLines, selectable, fit }) {
  const f = fontsReady ? { fontFamily: FONT[weight] || FONT[500] } : { fontWeight: weight === '800' ? '800' : weight };
  return (
    <Text selectable={selectable} numberOfLines={numberOfLines} adjustsFontSizeToFit={!!fit} minimumFontScale={fit ? (typeof fit === 'number' ? fit : 0.8) : undefined} style={[{ fontSize: size, color, textAlign: center ? 'center' : undefined }, f, style]}>
      {children}
    </Text>
  );
}

export function Icon({ name, size = 20, color = C.ink, style }) {
  return <Ionicons name={name} size={size} color={color} style={style} />;
}

// ---------------------------------------------------------------- layout
/** A full screen with header, scrolling body and optional bottom footer. */
export function Screen({ title, back = true, right, children, footer, scroll = true, headerContent, onBack, scrollRef, bottomSpace = 0, onScroll, onScrollLayout }) {
  const insets = useSafeAreaInsets();
  const nav = useNav();
  // the phone's back button does the same as this screen's back arrow
  useBackHandler(back && onBack ? () => { onBack(); return true; } : null);
  const showHeader = back || title || right || headerContent;
  return (
    <View style={{ flex: 1, backgroundColor: C.ground, paddingTop: insets.top }}>
      {showHeader ? (
        <View style={{ flexDirection: 'row', alignItems: 'center', paddingHorizontal: 8, minHeight: 52, gap: 4 }}>
          {back ? (
            <Pressable accessibilityLabel="Back" onPress={onBack || (() => nav.pop())} hitSlop={10} style={{ padding: 8 }}>
              <Icon name="arrow-back" size={24} />
            </Pressable>
          ) : (
            <View style={{ width: 8 }} />
          )}
          <View style={{ flex: 1 }}>{headerContent || (title ? <T size={20} weight="800" numberOfLines={1}>{title}</T> : null)}</View>
          {right ? <View style={{ flexDirection: 'row', alignItems: 'center', paddingRight: 8 }}>{right}</View> : null}
        </View>
      ) : null}
      {scroll ? (
        <ScrollView ref={scrollRef} contentContainerStyle={{ padding: 16, paddingTop: showHeader ? 4 : 16, paddingBottom: 32 + bottomSpace }} keyboardShouldPersistTaps="handled" automaticallyAdjustKeyboardInsets
          onScroll={onScroll} scrollEventThrottle={32} onLayout={onScrollLayout}>
          {children}
        </ScrollView>
      ) : (
        <View style={{ flex: 1 }}>{children}</View>
      )}
      {footer ? <View style={{ paddingHorizontal: 16, paddingTop: 8, paddingBottom: 12 + insets.bottom, backgroundColor: C.ground, gap: 8 }}>{footer}</View> : null}
    </View>
  );
}

/** Content of a tab page. `onBack` shows a back arrow (tabs go back to Home). */
export function TabPage({ title, right, children, onBack, fixed, fill }) {
  const insets = useSafeAreaInsets();
  if (fixed) {
    // header stays; the page lays out its own scrolling area (children fill the rest)
    return (
      <View style={{ flex: 1, backgroundColor: C.ground, paddingTop: insets.top + 12 }}>
        <View style={{ flexDirection: 'row', alignItems: 'center', marginBottom: 10, paddingHorizontal: 16 }}>
          {onBack ? (
            <Pressable accessibilityLabel="Back" onPress={onBack} hitSlop={10} style={{ paddingVertical: 6, paddingRight: 10, marginLeft: -4 }}>
              <Icon name="arrow-back" size={24} />
            </Pressable>
          ) : null}
          <T size={24} weight="800" style={{ flex: 1 }}>{title}</T>
          {right}
        </View>
        {children}
      </View>
    );
  }
  return (
    <ScrollView style={{ flex: 1, backgroundColor: C.ground }} contentContainerStyle={{ padding: 16, paddingTop: insets.top + 12, paddingBottom: fill ? 14 : 32, flexGrow: fill ? 1 : undefined }} keyboardShouldPersistTaps="handled">
      {title || onBack ? (
        <View style={{ flexDirection: 'row', alignItems: 'center', marginBottom: 14 }}>
          {onBack ? (
            <Pressable accessibilityLabel="Back" onPress={onBack} hitSlop={10} style={{ paddingVertical: 6, paddingRight: 10, marginLeft: -4 }}>
              <Icon name="arrow-back" size={24} />
            </Pressable>
          ) : null}
          <T size={24} weight="800" style={{ flex: 1 }}>{title}</T>
          {right}
        </View>
      ) : null}
      {children}
    </ScrollView>
  );
}

export function Row({ children, gap = 8, style, align = 'center' }) {
  return <View style={[{ flexDirection: 'row', alignItems: align, gap }, style]}>{children}</View>;
}
export const Gap = ({ h = 10 }) => <View style={{ height: h }} />;

export function Card({ children, onPress, style, border, bg, padding = 16 }) {
  const base = { backgroundColor: bg || C.card, borderRadius: 16, padding, borderWidth: border ? 1.4 : 1, borderColor: border || C.line, boxShadow: '0 1px 2px rgba(15,23,42,0.06)' };
  if (onPress) {
    return (
      <Pressable onPress={onPress} style={({ pressed }) => [base, { opacity: pressed ? 0.85 : 1 }, style]}>
        {children}
      </Pressable>
    );
  }
  return <View style={[base, style]}>{children}</View>;
}

export function SectionTitle({ children, right }) {
  return (
    <Row style={{ marginTop: 18, marginBottom: 10 }}>
      <T size={14} weight="600" style={{ flex: 1 }}>{children}</T>
      {right}
    </Row>
  );
}

// ---------------------------------------------------------------- small pieces
const TONES = {
  blue: [C.blue, C.blueSoft],
  green: [C.green, C.greenSoft],
  amber: [C.amber, C.amberSoft],
  red: [C.red, C.redSoft],
  purple: [C.purple, C.purpleSoft],
  grey: [C.muted, C.ground],
  pink: [C.pink, C.pinkSoft],
};
export function Pill({ text, tone = 'blue', icon }) {
  const [fg, bg] = TONES[tone];
  return (
    <View style={{ flexDirection: 'row', alignItems: 'center', alignSelf: 'flex-start', backgroundColor: bg, borderRadius: 99, paddingHorizontal: 10, paddingVertical: 4, gap: 4 }}>
      {icon ? <Icon name={icon} size={13} color={fg} /> : null}
      <T size={12.5} weight="600" color={fg}>{text}</T>
    </View>
  );
}

export function rentPill(t) {
  if (t.status === 'paid') return <Pill text="Paid" tone="green" />;
  if (t.status === 'pending') return <Pill text={`Due ${t.dueDate}`} tone="amber" />;
  if (t.status === 'late') return <Pill text={`${t.daysLate} days late`} tone="red" />;
  return <Pill text="Leaving" tone="purple" />;
}
export function typePill(type) {
  if (type === 'womens') return <Pill text="Women's" tone="pink" />;
  if (type === 'coliving') return <Pill text="Co-living" tone="purple" />;
  return <Pill text="Men's" />;
}

export function Btn({ title, onPress, variant = 'primary', icon, disabled, small, style }) {
  const styles = {
    primary: { bg: C.blue, fg: '#fff', border: C.blue },
    danger: { bg: C.red, fg: '#fff', border: C.red },
    success: { bg: C.green, fg: '#fff', border: C.green },
    outline: { bg: '#fff', fg: C.blue, border: C.line },
    dangerOutline: { bg: '#fff', fg: C.red, border: C.line },
    tonal: { bg: C.blueSoft, fg: C.blue, border: C.blueSoft },
    text: { bg: 'transparent', fg: C.blue, border: 'transparent' },
  }[variant];
  return (
    <Pressable
      accessibilityRole="button"
      disabled={disabled}
      onPress={onPress}
      style={({ pressed }) => [
        {
          minHeight: small ? 40 : variant === 'text' ? 40 : 52,
          paddingHorizontal: small ? 14 : 18,
          borderRadius: 12,
          backgroundColor: styles.bg,
          borderWidth: 1.2,
          borderColor: styles.border,
          flexDirection: 'row',
          alignItems: 'center',
          justifyContent: 'center',
          gap: 8,
          opacity: disabled ? 0.45 : pressed ? 0.8 : 1,
        },
        style,
      ]}
    >
      {icon ? <Icon name={icon} size={18} color={styles.fg} /> : null}
      <T size={14} weight="600" color={styles.fg} center>{title}</T>
    </Pressable>
  );
}

export function Field({ label, value, onChangeText, placeholder, keyboardType, multiline, secure, prefix, editable = true, maxLength, error, right, autoFocus, big }) {
  return (
    <View style={{ marginBottom: 14 }}>
      {label ? <T size={14} weight="600" style={{ marginBottom: 6 }}>{label}</T> : null}
      <View style={{ flexDirection: 'row', alignItems: 'center', backgroundColor: editable ? '#fff' : C.ground, borderRadius: 12, borderWidth: 1.2, borderColor: error ? C.red : C.line, paddingHorizontal: 14, minHeight: 50 }}>
        {prefix ? <T color={C.muted} style={{ marginRight: 4 }}>{prefix}</T> : null}
        <TextInput
          value={value}
          onChangeText={onChangeText}
          placeholder={placeholder}
          placeholderTextColor="#9AA7B8"
          keyboardType={keyboardType}
          multiline={multiline}
          secureTextEntry={secure}
          editable={editable}
          maxLength={maxLength}
          autoFocus={autoFocus}
          style={{ flex: 1, fontSize: big ? 24 : 15, letterSpacing: big ? 10 : 0, textAlign: big ? 'center' : 'left', color: C.ink, paddingVertical: 12, minHeight: multiline ? 84 : undefined, textAlignVertical: multiline ? 'top' : 'center', fontFamily: fontsReady ? (big ? FONT[800] : FONT[500]) : undefined }}
        />
        {right}
      </View>
      {error ? <T size={12.5} color={C.red} style={{ marginTop: 4 }}>{error}</T> : null}
    </View>
  );
}

export function Chips({ options, value, onChange }) {
  return (
    <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 8 }}>
      {options.map((o) => {
        const sel = o === value;
        return (
          <Pressable key={o} onPress={() => onChange(o)} style={{ paddingHorizontal: 14, paddingVertical: 8, borderRadius: 99, borderWidth: 1.2, borderColor: sel ? C.blue : C.line, backgroundColor: sel ? C.blueSoft : '#fff' }}>
            <T size={12.5} weight="600" color={sel ? C.blue : C.ink}>{o}</T>
          </Pressable>
        );
      })}
    </View>
  );
}

/** Multi-select chips. */
export function MultiChips({ options, values, onToggle }) {
  return (
    <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 8 }}>
      {options.map((o) => {
        const sel = values.includes(o);
        return (
          <Pressable key={o} onPress={() => onToggle(o)} style={{ flexDirection: 'row', alignItems: 'center', gap: 4, paddingHorizontal: 12, paddingVertical: 8, borderRadius: 12, borderWidth: 1.2, borderColor: sel ? C.blue : C.line, backgroundColor: sel ? C.blueSoft : '#fff' }}>
            {sel ? <Icon name="checkmark" size={14} color={C.blue} /> : null}
            <T size={12.5} weight="600" color={sel ? C.blue : C.ink}>{o}</T>
          </Pressable>
        );
      })}
    </View>
  );
}

export function Segmented({ options, value, onChange }) {
  return (
    <View style={{ flexDirection: 'row', backgroundColor: '#fff', borderRadius: 12, borderWidth: 1.2, borderColor: C.line, padding: 4, gap: 4 }}>
      {options.map((o) => {
        const sel = o.value === value;
        return (
          <Pressable key={String(o.value)} onPress={() => onChange(o.value)} style={{ flex: 1, flexDirection: 'row', justifyContent: 'center', alignItems: 'center', gap: 6, paddingVertical: 10, borderRadius: 12, backgroundColor: sel ? C.blue : 'transparent' }}>
            {o.icon ? <Icon name={o.icon} size={16} color={sel ? '#fff' : C.muted} /> : null}
            <T size={12.5} weight="600" color={sel ? '#fff' : C.ink} center>{o.label}</T>
          </Pressable>
        );
      })}
    </View>
  );
}

export function SwitchRow({ title, sub, value, onChange, last }) {
  return (
    <View style={{ flexDirection: 'row', alignItems: 'center', paddingVertical: 12, paddingHorizontal: 16, borderBottomWidth: last ? 0 : 1, borderBottomColor: C.line, gap: 10 }}>
      <View style={{ flex: 1 }}>
        <T weight="600">{title}</T>
        {sub ? <T size={12.5} color={C.muted}>{sub}</T> : null}
      </View>
      <Switch value={value} onValueChange={onChange} trackColor={{ true: C.blue, false: C.line }} thumbColor="#fff" />
    </View>
  );
}

export function CheckRow({ value, onChange, label }) {
  return (
    <Pressable onPress={() => onChange(!value)} style={{ flexDirection: 'row', alignItems: 'flex-start', gap: 10, paddingVertical: 8 }}>
      <Icon name={value ? 'checkbox' : 'square-outline'} size={24} color={value ? C.blue : C.muted} />
      <T style={{ flex: 1, lineHeight: 20 }} size={14}>{label}</T>
    </Pressable>
  );
}

export function InfoRow({ label, value, bold, color }) {
  return (
    <View style={{ flexDirection: 'row', paddingVertical: 5, gap: 12 }}>
      <T weight={bold ? '800' : '500'} color={bold ? C.ink : C.muted} style={{ flex: 1 }}>{label}</T>
      <T weight={bold ? '800' : '600'} size={bold ? 16 : 14} color={color || C.ink} style={{ flexShrink: 1, textAlign: 'right' }}>{value}</T>
    </View>
  );
}
export const Divider = () => <View style={{ height: 1, backgroundColor: C.line, marginVertical: 8 }} />;

export function Avatar({ name, size = 44, color = C.blue }) {
  return (
    <View style={{ width: size, height: size, borderRadius: size / 2, backgroundColor: color + '1F', alignItems: 'center', justifyContent: 'center' }}>
      <T size={size * 0.34} weight="800" color={color}>{initials(name)}</T>
    </View>
  );
}

export function IconBox({ name, color = C.blue, size = 40 }) {
  return (
    <View style={{ width: size, height: size, borderRadius: 12, backgroundColor: color + '1F', alignItems: 'center', justifyContent: 'center' }}>
      <Icon name={name} size={size * 0.5} color={color} />
    </View>
  );
}

export function StatTile({ label, value, sub, color = C.ink }) {
  return (
    <Card padding={14} style={{ flex: 1 }}>
      <T size={12.5} weight="400" color={C.muted}>{label}</T>
      <T size={20} weight="800" color={color} style={{ marginTop: 6 }}>{value}</T>
      {sub ? <T size={12.5} color={C.muted} style={{ marginTop: 2 }}>{sub}</T> : null}
    </Card>
  );
}

export function ProgressBar({ value, color = C.blue, height = 8 }) {
  return (
    <View style={{ height, borderRadius: height, backgroundColor: C.line, overflow: 'hidden' }}>
      <View style={{ width: `${Math.max(0, Math.min(1, value)) * 100}%`, height, backgroundColor: color, borderRadius: height }} />
    </View>
  );
}

export function MenuGroup({ children }) {
  const items = React.Children.toArray(children).filter(Boolean);
  return (
    <Card padding={0}>
      {items.map((c, i) => (
        <View key={i} style={{ borderBottomWidth: i < items.length - 1 ? 1 : 0, borderBottomColor: C.line }}>{c}</View>
      ))}
    </Card>
  );
}

export function MenuRow({ icon, title, sub, onPress, color = C.blue, badge, right }) {
  return (
    <Pressable onPress={onPress} style={({ pressed }) => ({ flexDirection: 'row', alignItems: 'center', gap: 12, paddingHorizontal: 14, paddingVertical: 12, opacity: pressed ? 0.7 : 1 })}>
      <IconBox name={icon} color={color} size={38} />
      <View style={{ flex: 1 }}>
        <T weight="600" color={color === C.red ? C.red : C.ink}>{title}</T>
        {sub ? <T size={12.5} color={C.muted}>{sub}</T> : null}
      </View>
      {badge ? (
        <View style={{ backgroundColor: C.red, borderRadius: 99, paddingHorizontal: 8, paddingVertical: 2 }}>
          <T size={12.5} weight="600" color="#fff">{badge}</T>
        </View>
      ) : null}
      {right || <Icon name="chevron-forward" size={20} color={C.blue} />}
    </Pressable>
  );
}

export function EmptyState({ icon, title, text, action }) {
  return (
    <View style={{ alignItems: 'center', paddingVertical: 36, paddingHorizontal: 20, gap: 8 }}>
      <IconBox name={icon} size={64} color={C.muted} />
      <T size={16} weight="800" center style={{ marginTop: 6 }}>{title}</T>
      <T color={C.muted} center style={{ lineHeight: 20 }}>{text}</T>
      {action}
    </View>
  );
}

export function UploadBox({ label, hint, done, onPress }) {
  return (
    <Card onPress={onPress} border={done ? C.green : C.line} bg={done ? C.greenSoft : '#fff'} padding={14}>
      <Row gap={12}>
        <IconBox name={done ? 'checkmark' : 'cloud-upload-outline'} color={done ? C.green : C.blue} />
        <View style={{ flex: 1 }}>
          <T weight="600">{done ? `${label} added` : label}</T>
          {hint ? <T size={12.5} color={C.muted}>{done ? 'Compressed · tap to change' : hint}</T> : null}
        </View>
      </Row>
    </Card>
  );
}

export function PhotoBox({ label = 'Hostel photo', color = C.blue, height = 170, width }) {
  return (
    <View style={{ height, width, borderRadius: 16, backgroundColor: color, alignItems: 'center', justifyContent: 'center', opacity: 0.9 }}>
      <Icon name="business" size={40} color="#fff" />
      <T weight="600" color="#fff" style={{ marginTop: 6 }}>{label}</T>
    </View>
  );
}

export function StepHeader({ step, title, subtitle, total = 4 }) {
  return (
    <View>
      <T size={11} weight="600" color={C.blue} style={{ letterSpacing: 1 }}>STEP {step} OF {total}</T>
      <Row gap={6} style={{ marginTop: 8 }}>
        {Array.from({ length: total }, (_, i) => i).map((i) => (
          <View key={i} style={{ flex: 1, height: 5, borderRadius: 8, backgroundColor: i < step ? C.blue : C.line }} />
        ))}
      </Row>
      <T size={24} weight="800" style={{ marginTop: 16, lineHeight: 30 }}>{title}</T>
      {subtitle ? <T color={C.muted} style={{ marginTop: 6, lineHeight: 20 }}>{subtitle}</T> : null}
    </View>
  );
}

/** Banner with the 15-minute bed hold countdown. */
export function HoldBanner() {
  const [, tick] = useState(0);
  useEffect(() => {
    const id = setInterval(() => tick((x) => x + 1), 1000);
    return () => clearInterval(id);
  }, []);
  const d = app.draft;
  const left = Math.max(0, Math.floor(((d.holdUntil || Date.now() + 900000) - Date.now()) / 1000));
  const mm = String(Math.floor(left / 60)).padStart(2, '0');
  const ss = String(left % 60).padStart(2, '0');
  return (
    <Row gap={10} style={{ backgroundColor: C.amberSoft, borderRadius: 12, paddingHorizontal: 14, paddingVertical: 12 }}>
      <Icon name="timer-outline" color={C.amber} />
      <T weight="600" color={C.amber} style={{ flex: 1 }}>{d.room ? `Room ${d.room.number} · Bed ${bedLabel(d.bedIndex)} held for you` : 'Bed held for you'}</T>
      <T weight="600" color={C.amber} style={{ fontVariant: ['tabular-nums'] }}>{mm}:{ss}</T>
    </Row>
  );
}

export function Stepper({ value, onChange, min = 1, label }) {
  return (
    <Row gap={10}>
      {label ? <T weight="600" style={{ flex: 1 }}>{label}</T> : null}
      <Pressable accessibilityLabel="Less" disabled={value <= min} onPress={() => onChange(value - 1)} style={{ width: 40, height: 40, borderRadius: 20, borderWidth: 1.2, borderColor: C.line, alignItems: 'center', justifyContent: 'center', opacity: value <= min ? 0.4 : 1 }}>
        <Icon name="remove" />
      </Pressable>
      <T size={20} weight="800" style={{ minWidth: 36, textAlign: 'center' }}>{value}</T>
      <Pressable accessibilityLabel="More" onPress={() => onChange(value + 1)} style={{ width: 40, height: 40, borderRadius: 20, borderWidth: 1.2, borderColor: C.line, alignItems: 'center', justifyContent: 'center' }}>
        <Icon name="add" />
      </Pressable>
    </Row>
  );
}

/** Bottom tab bar for the student and owner shells. */
export function TabBar({ tabs, active, onChange }) {
  const insets = useSafeAreaInsets();
  return (
    // lifted floating tab bar: thin border, light shadow, sits higher above the gesture line;
    // it is in the page flow (not on top), so no card ever hides behind it
    <View style={{ flexDirection: 'row', backgroundColor: '#fff', marginHorizontal: 12, marginTop: 6, marginBottom: insets.bottom + 14, borderRadius: 26, paddingVertical: 6, borderWidth: 1, borderColor: C.line, boxShadow: '0 2px 6px rgba(15,23,42,0.08)' }}>
      {tabs.map((t, i) => {
        const sel = i === active;
        return (
          <Pressable key={t.label} accessibilityRole="tab" onPress={() => onChange(i)} style={{ flex: 1, alignItems: 'center', gap: 2, paddingVertical: 4 }}>
            <View style={{ paddingHorizontal: 18, paddingVertical: 4, borderRadius: 99, backgroundColor: sel ? C.blueSoft : 'transparent' }}>
              <Icon name={sel ? t.icon : t.icon + '-outline'} size={22} color={sel ? C.blue : C.muted} />
              {t.badge ? (
                <View style={{ position: 'absolute', top: 0, right: 10, minWidth: 16, height: 16, borderRadius: 8, backgroundColor: C.red, alignItems: 'center', justifyContent: 'center', paddingHorizontal: 3 }}>
                  {t.badge === true ? null : <T size={11} weight="600" color="#fff">{t.badge}</T>}
                </View>
              ) : null}
            </View>
            <T size={11} weight={sel ? '600' : '400'} color={sel ? C.blue : C.muted}>{t.label}</T>
          </Pressable>
        );
      })}
    </View>
  );
}

/** Language picker pill (opens a sheet). */
export function LanguageButton({ onOpen }) {
  useApp();
  return (
    <Pressable onPress={onOpen} style={{ flexDirection: 'row', alignItems: 'center', gap: 4, backgroundColor: '#fff', borderRadius: 99, borderWidth: 1, borderColor: C.line, paddingHorizontal: 12, paddingVertical: 7 }}>
      <Icon name="language" size={16} color={C.blue} />
      <T size={12.5} weight="600">{app.language}</T>
      <Icon name="chevron-down" size={14} />
    </Pressable>
  );
}

export function LanguageList({ close, onPicked }) {
  return (
    <View>
      <T size={20} weight="800" style={{ marginBottom: 8 }}>Language</T>
      {LANGUAGES.map((l) => (
        <Pressable
          key={l}
          onPress={() => {
            app.language = l;
            actions.touch();
            close();
            onPicked && onPicked(l);
          }}
          style={{ flexDirection: 'row', alignItems: 'center', paddingVertical: 14, borderBottomWidth: 1, borderBottomColor: C.line }}
        >
          <T size={16} weight="600" style={{ flex: 1 }}>{l}</T>
          {l === app.language ? <Icon name="checkmark" color={C.blue} /> : null}
        </Pressable>
      ))}
      <T size={12.5} color={C.muted} style={{ marginTop: 10 }}>Prototype: text stays in English for now.</T>
    </View>
  );
}

/** Simple date chooser: move day by day (no extra packages). */
export function DateStepper({ date, onChange, min, max }) {
  const can = (d) => (!min || d >= min) && (!max || d <= max);
  const move = (n) => {
    const d = new Date(date.getTime() + n * 86400000);
    if (can(d)) onChange(d);
  };
  const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return (
    <View style={{ gap: 10 }}>
      <Row gap={8} style={{ justifyContent: 'center' }}>
        <Btn small variant="outline" title="−7" onPress={() => move(-7)} />
        <Btn small variant="outline" title="−1" onPress={() => move(-1)} />
        <View style={{ minWidth: 120, alignItems: 'center' }}>
          <T size={20} weight="800">{`${String(date.getDate()).padStart(2, '0')} ${MONTHS[date.getMonth()]} ${date.getFullYear()}`}</T>
        </View>
        <Btn small variant="outline" title="+1" onPress={() => move(1)} />
        <Btn small variant="outline" title="+7" onPress={() => move(7)} />
      </Row>
    </View>
  );
}

/** Filled-% ring drawn with small segments (no extra packages needed in Expo Go). */
export function PercentRing({ filled, hold, total, color, textColor, size = 60, thickness = 7 }) {
  const N = 90;
  const pct = total ? Math.round((filled / total) * 100) : 0;
  const fEnd = total ? filled / total : 0;
  const hEnd = total ? (filled + hold) / total : 0;
  const segW = Math.max(2.5, (Math.PI * size) / N + 0.8);
  return (
    <View accessibilityLabel={`${pct} percent of beds filled`} style={{ width: size, height: size }}>
      {Array.from({ length: N }, (_, i) => {
        const at = (i + 0.5) / N;
        const c = at < fEnd ? color : at < hEnd ? '#F2B35B' : '#E8F0FA';
        return (
          <View key={i} style={{ position: 'absolute', left: size / 2 - segW / 2, top: 0, width: segW, height: size, transform: [{ rotate: `${(i * 360) / N}deg` }] }}>
            <View style={{ width: segW, height: thickness, backgroundColor: c }} />
          </View>
        );
      })}
      <View style={{ position: 'absolute', left: 0, top: 0, width: size, height: size, alignItems: 'center', justifyContent: 'center' }}>
        <T size={16} weight="800" color={textColor}>{pct}%</T>
      </View>
    </View>
  );
}

/** Simple drawn building used until the owner adds a hostel photo. */
export function BuildingArt({ color, door }) {
  return (
    <View style={{ flex: 1, justifyContent: 'flex-end', alignItems: 'center' }}>
      <View style={{ width: 52, flex: 1, maxHeight: 96, backgroundColor: color, overflow: 'hidden' }}>
        <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 4, padding: 5 }}>
          {Array.from({ length: 25 }, (_, i) => (
            <View key={i} style={{ width: 5.5, height: 5.5, backgroundColor: '#FFFFFF', opacity: 0.85 }} />
          ))}
        </View>
        <View style={{ position: 'absolute', bottom: 0, left: 19, width: 14, height: 14, backgroundColor: door }} />
      </View>
    </View>
  );
}

// ---------------- Phase 1 "Your room" pickers (student form + owner's fix panel) ----------------
export const MAX_SHARING = 12;
/** Ground floor rooms are G + a number (G1, G2 …); rooms on other floors can't start with G. */
export const isGroundRoom = (no) => /^G\d{1,4}$/.test((no || '').trim());
export const startsWithG = (no) => /^g/i.test((no || '').trim());
export const roomMatchesFloor = (no, floor) => (String(floor) === '0' ? isGroundRoom(no) : !startsWithG(no));
export const MAX_FLOOR = 50;
export const floorText = (f) => (String(f) === '0' ? 'Ground floor' : `Floor ${parseInt(f, 10)}`);

/** Floor: a "Ground" chip and a "Floor" button that opens a pop-up over a dimmed screen:
 *  Floor 1–9 in a 3×3 grid, and a full-width "+ Tap to add next floor" bar (10, 11 … up to 50).
 *  `allowGround=false` disables Ground; `onlyGround` disables the Floor button (G rooms). */
export function FloorPicker({ value, onChange, locked, allowGround = true, onlyGround = false }) {
  const [open, setOpen] = useState(false);
  const [count, setCount] = useState(Math.max(9, parseInt(value, 10) || 0));
  const [added, setAdded] = useState([]);
  const ground = value === '0';
  const upper = value !== '' && value != null && !ground;
  const box = (sel) => ({ height: 42, paddingHorizontal: 12, borderRadius: 12, borderWidth: 1.2, justifyContent: 'center', borderColor: sel ? C.blue : C.line, backgroundColor: sel ? C.blueSoft : '#fff' });
  const floors = Array.from({ length: count }, (_, i) => i + 1);
  return (
    <View>
      <Row gap={6}>
        <Pressable disabled={locked || !allowGround} accessibilityLabel="Ground floor" onPress={() => onChange('0')} style={[box(ground), { opacity: (locked || !allowGround) && !ground ? 0.4 : 1 }]}>
          <T size={12.5} weight="600" color={ground ? C.blue : C.ink}>Ground</T>
        </Pressable>
        <Pressable disabled={locked || onlyGround} accessibilityLabel="Choose floor" onPress={() => setOpen(true)} style={[box(upper), { flexDirection: 'row', alignItems: 'center', gap: 4, opacity: (locked || onlyGround) && !upper ? 0.4 : 1 }]}>
          <T size={12.5} weight="600" color={upper ? C.blue : C.ink}>{upper ? `Floor ${parseInt(value, 10)}` : 'Floor'}</T>
          <Icon name="chevron-down" size={16} color={upper ? C.blue : C.muted} />
        </Pressable>
      </Row>
      <Modal visible={open} transparent animationType="fade" onRequestClose={() => setOpen(false)}>
        <Pressable onPress={() => setOpen(false)} style={{ flex: 1, backgroundColor: 'rgba(0,0,0,0.45)', alignItems: 'center', justifyContent: 'center', padding: 24 }}>
          <Pressable onPress={() => {}} style={{ width: '100%', maxWidth: 380, maxHeight: '85%', backgroundColor: '#fff', borderRadius: 16, padding: 16 }}>
            <T size={16} weight="800">Choose your floor</T>
            <ScrollView style={{ marginTop: 12 }} contentContainerStyle={{ flexDirection: 'row', flexWrap: 'wrap', gap: 8 }}>
              {floors.map((n) => {
                const sel = value === String(n);
                const isNew = added.includes(n) && !sel;
                return (
                  <Pressable key={n} accessibilityLabel={`Floor ${n}`} onPress={() => { onChange(String(n)); setOpen(false); }}
                    style={{ width: '31%', paddingVertical: 11, borderRadius: 12, alignItems: 'center', borderWidth: 1.2,
                      borderColor: sel ? C.blue : isNew ? C.green : C.line, backgroundColor: sel ? C.blueSoft : isNew ? C.greenSoft : '#fff' }}>
                    <T size={12.5} weight="600" color={sel ? C.blue : isNew ? C.green : C.ink}>Floor {n}</T>
                  </Pressable>
                );
              })}
            </ScrollView>
            {count < MAX_FLOOR ? (
              <Pressable accessibilityLabel="Add next floor" onPress={() => { setAdded([...added, count + 1]); setCount(count + 1); }}
                style={{ marginTop: 10, flexDirection: 'row', justifyContent: 'center', alignItems: 'center', gap: 6, paddingVertical: 11, borderRadius: 12, borderWidth: 1.2, borderStyle: 'dashed', borderColor: C.blue, backgroundColor: C.blueSoft }}>
                <Icon name="add" size={18} color={C.blue} />
                <T size={14} weight="600" color={C.blue}>Tap to add next floor</T>
              </Pressable>
            ) : null}
            <Pressable onPress={() => setOpen(false)} style={{ alignSelf: 'center', marginTop: 10, padding: 6 }}>
              <T weight="400" color={C.muted}>Cancel</T>
            </Pressable>
          </Pressable>
        </Pressable>
      </Modal>
    </View>
  );
}

/** Sharing: chips 1–5 then "+"; each "+" adds and selects the next number (up to MAX_SHARING). */
export function SharingPicker({ value, onChange, locked }) {
  const shown = Math.max(5, value || 0);
  const chip = (sel) => ({ minWidth: 40, height: 40, paddingHorizontal: 8, borderRadius: 12, alignItems: 'center', justifyContent: 'center', borderWidth: 1.2, borderColor: sel ? C.blue : C.line, backgroundColor: sel ? C.blueSoft : '#fff' });
  return (
    <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 6 }}>
      {Array.from({ length: shown }, (_, i) => i + 1).map((n) => {
        const sel = value === n;
        return (
          <Pressable key={n} disabled={locked} accessibilityLabel={`${n} sharing`} onPress={() => onChange(n)} style={[chip(sel), { opacity: locked && !sel ? 0.4 : 1 }]}>
            <T weight="600" color={sel ? C.blue : C.ink}>{n}</T>
          </Pressable>
        );
      })}
      {!locked && shown < MAX_SHARING ? (
        <Pressable accessibilityLabel="More sharing" onPress={() => onChange(shown + 1)} style={[chip(false), { borderStyle: 'dashed', borderColor: C.blue }]}>
          <Icon name="add" size={20} color={C.blue} />
        </Pressable>
      ) : null}
    </View>
  );
}

/** Short name of a hostel: first letters of its words, at most 3 (first word + last two).
 *  "Elite Deluxe Women's Hostel" -> "EWH", "Sunrise Boys PG" -> "SBP", "Nest Co-living" -> "NC". */
export function hostelShortName(name) {
  const words = (name || '').trim().split(/\s+/).filter(Boolean);
  const pick = words.length > 3 ? [words[0], ...words.slice(-2)] : words;
  return pick.map((w) => (w.match(/[A-Za-z0-9]/) || [''])[0].toUpperCase()).join('') || '?';
}

/** Box with the hostel's short name. Shown where the hostel photo will go (photos come in Phase 2).
 *  onBlue: white box for the blue Home header; otherwise light blue. */
export function ShortNameBox({ name, size = 56, height, onBlue }) {
  const s = hostelShortName(name);
  return (
    <View accessibilityLabel={name} style={{ width: size, height: height || size, borderRadius: 12, backgroundColor: onBlue ? '#FFFFFF' : C.blueSoft, alignItems: 'center', justifyContent: 'center' }}>
      <T size={s.length > 2 ? size * 0.32 : size * 0.38} weight="800" color={C.blue} style={{ letterSpacing: 0.5 }}>{s}</T>
    </View>
  );
}

/** Hostel photo if the owner added one, otherwise the short name box (decided 20 Oct 2026).
 *  onEdit: small button – pen (change) when there is a photo, camera (add) when there isn't.
 *  h.photo: an image source (prototype: the bundled sample photo). */
export function HostelPhoto({ h, width = 56, height = 56, onBlue, onEdit }) {
  return (
    <View style={{ width, height }}>
      {h.photo ? (
        <Image source={h.photo} accessibilityLabel={h.name}
          style={{ width, height, borderRadius: 12, borderWidth: onBlue ? 2 : 0, borderColor: '#FFFFFF' }} />
      ) : (
        <ShortNameBox name={cleanHostelName(h.name)} size={width} height={height} onBlue={onBlue} />
      )}
      {onEdit ? (
        <Pressable accessibilityLabel={h.photo ? 'Change hostel photo' : 'Add hostel photo'} onPress={onEdit} hitSlop={8}
          style={{ position: 'absolute', right: -6, bottom: -6, width: 26, height: 26, borderRadius: 13, backgroundColor: '#FFFFFF', borderWidth: 1, borderColor: C.line, alignItems: 'center', justifyContent: 'center' }}>
          <Icon name={h.photo ? 'pencil' : 'camera'} size={13} color={C.blue} />
        </Pressable>
      ) : null}
    </View>
  );
}

/** Ring drawn with small segments (works in Expo Go). value 0..1 of the ring in `color`; children in the middle. */
export function ProgressRing({ value = 1, color = C.blue, track = C.blueSoft, size = 76, thickness = 8, children }) {
  const N = 90;
  const segW = Math.max(2.5, (Math.PI * size) / N + 0.8);
  return (
    <View style={{ width: size, height: size }}>
      {Array.from({ length: N }, (_, i) => (
        <View key={i} style={{ position: 'absolute', left: size / 2 - segW / 2, top: 0, width: segW, height: size, transform: [{ rotate: `${(i * 360) / N}deg` }] }}>
          <View style={{ width: segW, height: thickness, backgroundColor: (i + 0.5) / N <= value ? color : track }} />
        </View>
      ))}
      <View style={{ position: 'absolute', left: 0, top: 0, width: size, height: size, alignItems: 'center', justifyContent: 'center' }}>{children}</View>
    </View>
  );
}

/** Solid Trust blue behind blue headers (gradient removed 22 Oct 2026). Put it first inside a View with overflow hidden. */
export function SkyBack() {
  return <View style={{ position: 'absolute', left: 0, right: 0, top: 0, bottom: 0, backgroundColor: C.blue }} />;
}
