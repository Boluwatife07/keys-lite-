import { config } from '../config.js';
import { q } from '../db/pool.js';

export type EmailTemplate =
  | 'signup_code'
  | 'reset_code'
  | 'change_email_code'
  | 'create_password_code'
  | 'verification_approved'
  | 'verification_rejected'
  // Event and club emails: data carries subject and text (EVT-26, CLB-16).
  | 'notice';

const subjects: Record<EmailTemplate, string> = {
  signup_code: 'Your Keys verification code',
  reset_code: 'Reset your Keys password',
  change_email_code: 'Confirm your new email address',
  create_password_code: 'Your Keys verification code',
  verification_approved: 'Your address is verified',
  verification_rejected: 'We could not verify your address',
  notice: 'Keys',
};

function body(t: EmailTemplate, d: Record<string, unknown>): string {
  switch (t) {
    case 'signup_code':
    case 'change_email_code':
    case 'create_password_code':
      return `Your Keys verification code is ${d.code}. It expires in 60 seconds.`;
    case 'reset_code':
      return `Your Keys password reset code is ${d.code}. It expires in 60 seconds.`;
    case 'verification_approved':
      return `Hi ${d.firstName}, good news: your home address has been verified. You now have full access to your community on Keys.`;
    case 'verification_rejected':
      return `Hi ${d.firstName}, we reviewed your document (ref ${d.ref}) but could not verify your home address. Your account stays unverified.`;
    case 'notice':
      return String(d.text ?? '');
  }
}

// Every email is logged to email_outbox. With MOCK_EMAIL off it is also sent
// through Resend.
export async function sendEmail(to: string, template: EmailTemplate, data: Record<string, unknown>) {
  await q('insert into email_outbox(to_email, template, data) values ($1,$2,$3)', [to, template, data]);
  if (config.mocks.email) {
    // Mock mode: show codes in the server console so you can sign up locally.
    if (data.code && process.env.NODE_ENV !== 'test') console.log(`[mock email] ${to}: ${body(template, data)}`);
    return;
  }
  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: { Authorization: `Bearer ${config.resendApiKey}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ from: config.emailFrom, to, subject: template === 'notice' ? String(data.subject) : subjects[template], text: body(template, data) }),
  });
  if (!res.ok) throw new Error(`Resend failed: ${res.status} ${await res.text()}`);
}
