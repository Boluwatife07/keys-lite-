import { config } from '../config.js';
import { AppError } from '../lib/errors.js';

// Stripe zero-amount address check (BE-10.1).
//
// Pass rule (decided in build: Engineering + Dorcas "your choice", AVW-Q1):
//   Stripe's address_postal_code_check AND address_line1_check must both be
//   "pass". line1 carries the house number, so a neighbour's card on the same
//   postcode does not pass.
//
// The billing address checked is always the resident's Keys home address. The
// server writes it onto the payment method before confirming, so Keys never
// needs to read an address back from Stripe (AVW-02.5). The payment method is
// detached afterwards: the card is not saved (AVW-10.1).

export type Method = 'card' | 'apple_pay' | 'google_pay';
export interface CheckInput {
  method: Method;
  paymentMethodId: string;   // created on device by Stripe SDK (card form or wallet sheet)
  home: { line1: string; postcode: string; town: string };
}
export interface CheckResult { result: 'pass' | 'fail'; brand: string; last4: string }

export interface AddressCheckProvider { check(input: CheckInput): Promise<CheckResult> }

// Mock: "pm_mock_<pass|fail>_<brand>_<last4>". Lets the app demo both paths.
export const mockAddressCheck: AddressCheckProvider = {
  async check({ paymentMethodId }) {
    const [, , outcome, brand = 'visa', last4 = '4242'] = paymentMethodId.split('_');
    if (!paymentMethodId.startsWith('pm_mock_')) throw new AppError(400, 'PAYMENT_METHOD_INVALID', 'Card details are not valid.');
    return { result: outcome === 'pass' ? 'pass' : 'fail', brand, last4 };
  },
};

async function stripe(path: string, params: Record<string, string>) {
  const res = await fetch(`https://api.stripe.com/v1/${path}`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${config.stripeSecretKey}`, 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams(params),
  });
  const json = (await res.json()) as any;
  if (!res.ok) throw new AppError(502, 'STRIPE_ERROR', json?.error?.message ?? 'Card check failed.');
  return json;
}

export const stripeAddressCheck: AddressCheckProvider = {
  async check({ paymentMethodId, home }) {
    await stripe(`payment_methods/${paymentMethodId}`, {
      'billing_details[address][line1]': home.line1,
      'billing_details[address][postal_code]': home.postcode,
      'billing_details[address][city]': home.town,
      'billing_details[address][country]': 'GB',
    });
    const si = await stripe('setup_intents', {
      payment_method: paymentMethodId,
      confirm: 'true',
      usage: 'off_session',
      'payment_method_types[]': 'card',
      'expand[]': 'payment_method',
    });
    const card = si.payment_method?.card ?? {};
    const pass = card.checks?.address_postal_code_check === 'pass' && card.checks?.address_line1_check === 'pass';
    await stripe(`payment_methods/${paymentMethodId}/detach`, {}).catch(() => undefined);
    return { result: pass ? 'pass' : 'fail', brand: card.brand ?? 'card', last4: card.last4 ?? '' };
  },
};

export const addressCheck: AddressCheckProvider = config.mocks.stripe ? mockAddressCheck : stripeAddressCheck;
