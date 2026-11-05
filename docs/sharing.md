# Sharing the app with a link

The app is published as a web page that anyone can open in a browser:

**https://boluwatife07.github.io/keys-lite-/**

It rebuilds on every push to `claude/hopeful-mccarthy-vdo9v6` (or `main`):

- The web app is built by GitHub Actions and published on GitHub Pages
  (`.github/workflows/web.yml`).
- The server and its database run on Render and redeploy on every push
  (`render.yaml`).

## One-time setup (about 5 minutes)

1. **Turn on GitHub Pages.** In the repository on GitHub: Settings > Pages >
   Build and deployment > Source: **GitHub Actions**. Then open the Actions tab
   and re-run the latest "Web app" run (or push any commit).
2. **Connect Render.** Sign in at render.com with GitHub, then New >
   **Blueprint**, pick `keys-lite-`, and confirm. Render creates the free
   database and the `keys-lite-api` server from `render.yaml`.
3. If Render gives the server a different address than
   `https://keys-lite-api.onrender.com`, add it on GitHub under Settings >
   Secrets and variables > Actions > Variables as `API_BASE_URL`, then re-run
   the "Web app" workflow.

## Trying it

- Demo account: `amy@keys.test`, password `Keys2026!` (more accounts are listed
  in `backend/src/db/seed.ts`).
- New sign-ups: any email works; the verification code is always **123456** on
  this demo server (`DEMO_CODE`). Emails are not really sent.
- Test addresses: "5 Cedar Close" (no community yet), "4 Elm Street"
  (connected streets), "3 Oak Avenue".

## Limits of the free demo

- The free Render server sleeps after 15 minutes without use; the first
  request then takes about a minute.
- Uploaded photos are kept on the server's disk and are lost when it
  redeploys. The free database expires after 30 days on Render's free plan.
- Address search uses sample London streets until a Google Places key is
  added (`GOOGLE_PLACES_KEY`, `MOCK_PLACES=false` in Render).
- Camera scanning, voice notes and phone sharing behave as the browser allows;
  the phone apps are the full experience.
