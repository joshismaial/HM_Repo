// A tiny stack navigator (no extra packages needed, works in Expo Go).
//
// BACK BUTTON (standing rule): the phone's back button / gesture and every on-screen back arrow
// must go to the previous screen. Order on the phone's back button:
//   1. an open sheet closes (overlay.js Modal handles that itself);
//   2. the top screen's own back handler, if it registered one with useBackHandler()
//      (e.g. OwnerShell: a non-Home tab goes back to Home; a screen with a custom onBack);
//   3. otherwise the top screen is popped;
//   4. on the first screen, Android closes the app.
// New screens: use <Screen> (back arrow built in) or <TabPage onBack>, and register any custom
// back behaviour with useBackHandler so the arrow and the phone's button do the same thing.
import React, { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState } from 'react';
import { BackHandler, View } from 'react-native';

const NavContext = createContext(null);
export const useNav = () => useContext(NavContext);
const ScreenKeyContext = createContext(null);
const BackRegistry = createContext(null);

/** Register a back handler for the screen this component is in. `fn()` returns true when it
 *  handled back (then the screen is not popped). Pass null to register nothing. */
export function useBackHandler(fn) {
  const key = useContext(ScreenKeyContext);
  const registry = useContext(BackRegistry);
  const fnRef = useRef(fn);
  fnRef.current = fn;
  useEffect(() => {
    if (!registry || !key) return undefined;
    const handler = () => (fnRef.current ? fnRef.current() : false);
    const list = registry.current[key] || (registry.current[key] = []);
    list.push(handler);
    return () => {
      const l = registry.current[key] || [];
      const i = l.indexOf(handler);
      if (i >= 0) l.splice(i, 1);
      if (!l.length) delete registry.current[key];
    };
  }, [key, registry]);
}

let keySeq = 0;
const entry = (name, params) => ({ key: 'r' + keySeq++, name, params: params || {} });

export function Navigator({ screens, initial }) {
  const [stack, setStack] = useState([entry(initial)]);
  const stackRef = useRef(stack);
  stackRef.current = stack;

  const push = useCallback((name, params) => setStack((s) => [...s, entry(name, params)]), []);
  const pop = useCallback((n = 1) => setStack((s) => (s.length > n ? s.slice(0, s.length - n) : s.slice(0, 1))), []);
  const replace = useCallback((name, params) => setStack((s) => [...s.slice(0, -1), entry(name, params)]), []);
  const popToTop = useCallback(() => setStack((s) => s.slice(0, 1)), []);
  /** Go back to the first screen, then open `name` on top of it. */
  const resetTo = useCallback((name, params) => setStack((s) => [s[0], entry(name, params)]), []);
  /** Pop back to the most recent screen called `name` (if it exists). */
  const popTo = useCallback(
    (name) =>
      setStack((s) => {
        for (let i = s.length - 1; i >= 0; i--) if (s[i].name === name) return s.slice(0, i + 1);
        return s;
      }),
    [],
  );

  const handlers = useRef({}); // screen key -> back handlers (newest last)

  useEffect(() => {
    const sub = BackHandler.addEventListener('hardwareBackPress', () => {
      const s = stackRef.current;
      const top = s[s.length - 1];
      const list = (handlers.current[top.key] || []).slice().reverse();
      for (const h of list) if (h()) return true;
      if (s.length > 1) {
        pop();
        return true;
      }
      return false; // first screen: let Android close the app
    });
    return () => sub.remove();
  }, [pop]);

  const nav = useMemo(() => ({ push, pop, replace, popToTop, resetTo, popTo, depth: stack.length }), [push, pop, replace, popToTop, resetTo, popTo, stack.length]);

  return (
    <NavContext.Provider value={nav}>
      <BackRegistry.Provider value={handlers}>
      <View style={{ flex: 1 }}>
        {stack.map((e, i) => {
          const Screen = screens[e.name];
          const top = i === stack.length - 1;
          if (!Screen) throw new Error('Unknown screen: ' + e.name);
          // Keep lower screens mounted (so their state survives) but hidden.
          return (
            <View key={e.key} style={top ? { flex: 1 } : { display: 'none' }}>
              <ScreenKeyContext.Provider value={e.key}>
                <Screen params={e.params} />
              </ScreenKeyContext.Provider>
            </View>
          );
        })}
      </View>
      </BackRegistry.Provider>
    </NavContext.Provider>
  );
}
