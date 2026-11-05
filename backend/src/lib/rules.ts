// Phase 1 limits that apply everywhere (Read Me + XFR rows).
export const MB = 1024 * 1024;
export const MEDIA = {
  photo: { maxBytes: 15 * MB, mimes: ['image/jpeg', 'image/png'], tooLarge: 'The image you selected is too large. Please choose a different image.' },
  video: { maxBytes: 100 * MB, maxSeconds: 60, mimes: ['video/mp4', 'video/quicktime'], tooLarge: 'The video you selected is too large. Please choose a video of 100 MB or less.', tooLong: 'Videos can be up to 60 seconds long. Please trim your video.' },
  document: { maxBytes: 25 * MB, mimes: ['application/pdf', 'application/msword', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', 'application/vnd.ms-excel', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', 'application/vnd.ms-powerpoint', 'application/vnd.openxmlformats-officedocument.presentationml.presentation', 'text/plain'], tooLarge: 'The document you selected is too large. Please choose a file of 25 MB or less.' },
  audio: { maxBytes: 25 * MB, maxSeconds: 600, mimes: ['audio/mp4', 'audio/mpeg', 'audio/aac', 'audio/ogg', 'audio/webm', 'audio/wav'], tooLarge: 'This voice note is too large.' },
  // Address verification documents: design says "PDF, JPG, PNG up to 10MB" (AVW-Q4, decided: follow design).
  verificationDoc: { maxBytes: 10 * MB, mimes: ['application/pdf', 'image/jpeg', 'image/png'], tooLarge: 'The file you selected is too large. Please choose a file of 10 MB or less.' },
} as const;

export const LIMITS = {
  bio: 160,
  codeTtlSeconds: 60,
  resendAfterSeconds: 60,
  maxCodeAttempts: 5,
  maxCodeSendsPerHour: 6,
  maxCodeSendsPerIpHour: Number(process.env.MAX_CODES_PER_IP_HOUR ?? 30),
  maxFailedLogins: 5,
  lockoutMinutes: 15,
  devStreetsMax: 5,
  devNameRadiusKm: 10,
  countsVisibleAbove: 500,     // ONB-13.4: counts only when a community has more than 500 residents
  verifyAttemptsPerDay: 5,     // AVW baseline, to confirm
  deactivationWindowDays: 30,
  redeactivateBlockDays: 7,
};

// One shared report reason list (XFR-03.1). "Other" needs text.
export const REPORT_REASONS = [
  'Spam or misleading',
  'Harassment or bullying',
  'Hate speech or discrimination',
  'Violence or threats',
  'Nudity or sexual content',
  'Scams or fraud',
  'False information',
  'Impersonation',
  'Sharing private information',
  'Other',
] as const;

export const REPORT_ITEM_TYPES = [
  'user', 'post', 'comment', 'reply', 'poll', 'update', 'additional_update', 'club',
  'announcement', 'chat', 'group_chat', 'member', 'event',
] as const;

export function passwordProblems(pw: string): string[] {
  const out: string[] = [];
  if (pw.length < 8 || pw.length > 15) out.push('Between 8-15 characters');
  if (!/[A-Za-z]/.test(pw) || !/\d/.test(pw)) out.push('Contain letters and numbers');
  if (!/[^A-Za-z0-9]/.test(pw)) out.push('At least one special character');
  return out;
}

export const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
