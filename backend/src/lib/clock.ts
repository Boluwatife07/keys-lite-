// Injectable clock so tests can move time (code expiry, 30-day windows...).
let offsetMs = 0;
export const clock = {
  now: () => new Date(Date.now() + offsetMs),
  advance: (ms: number) => { offsetMs += ms; },
  reset: () => { offsetMs = 0; },
};
export const SECOND = 1000;
export const MINUTE = 60 * SECOND;
export const HOUR = 60 * MINUTE;
export const DAY = 24 * HOUR;
