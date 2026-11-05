// Typed errors. The app maps `code` to a screen state; `message` is the
// exact user-facing copy from the design where one exists.
export class AppError extends Error {
  constructor(
    public status: number,
    public code: string,
    message: string,
    public details?: Record<string, unknown>,
  ) {
    super(message);
  }
}

export const badRequest = (code: string, message: string, details?: Record<string, unknown>) =>
  new AppError(400, code, message, details);
export const unauthorized = (message = 'Please log in again.') => new AppError(401, 'UNAUTHORIZED', message);
export const forbidden = (code: string, message: string) => new AppError(403, code, message);
export const notFound = (message = 'This is not available.') => new AppError(404, 'NOT_AVAILABLE', message);
export const conflict = (code: string, message: string, details?: Record<string, unknown>) =>
  new AppError(409, code, message, details);
export const tooMany = (message: string) => new AppError(429, 'RATE_LIMITED', message);

// AVW-08.1 / BE-10.3: one typed error the app maps to the verify sheet.
export const verificationRequired = () =>
  new AppError(
    403,
    'VERIFICATION_REQUIRED',
    'In order to perform this action, kindly verify your home address using your bank card.',
  );
