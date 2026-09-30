# What changed, and the one-time setup

Do the steps in order. Steps 1–2 are enough for everything except username logins and phone notifications.

## 1. Put the files in your GitHub repo
Copy everything in this folder into the repo (replace `index.html` and `supabase-setup.sql`). Vercel redeploys by itself.
New files: `manifest.json`, `sw.js`, `icons/`, `supabase/functions/`.

## 2. Run the database script
Supabase → SQL Editor → New query → paste all of `supabase-setup.sql` → Run. Safe to run again.
This turns on: private tasks, the sign-in switches, username logins and the phone-notification table.
Old tasks get their "assigned by" person filled in by matching the name. Any old task whose assigner's name
doesn't match a team member will be visible only to the assignee and admins.

## 3. Username + password logins (needs the `admin-users` function)
Supabase CLI, from the repo folder:
    supabase functions deploy admin-users
Then in the app: Settings → Users & access → "Create a username login".
(If you would rather not use the CLI, Supabase dashboard → Edge Functions → Deploy a new function → paste `supabase/functions/admin-users/index.ts`.)

## 4. Phone notifications (needs the `send-push` function)
a. Make a key pair (once):  `npx web-push generate-vapid-keys`
b. Save the secrets:
    supabase secrets set VAPID_PUBLIC_KEY=... VAPID_PRIVATE_KEY=... VAPID_SUBJECT=mailto:you@example.com PUSH_WEBHOOK_SECRET=any-long-random-text
c. Deploy:  `supabase functions deploy send-push --no-verify-jwt`
d. Supabase dashboard → Database → Webhooks → Create: table `notifications`, event `Insert`, type "Supabase Edge Functions" (or HTTP POST to the function URL), add header `x-webhook-secret` = the same text as PUSH_WEBHOOK_SECRET.
e. In the app: Settings → Notifications → Phone notifications → paste the PUBLIC key (VAPID) → it saves itself.
f. On each phone: iPhone needs iOS 16.4 or newer. Delete the old Home Screen bookmark, open the app in Safari,
   Share → Add to Home Screen, open it from the new icon, then tap "Turn on" (More page or the pop-up). Android: open in Chrome, tap "Turn on".

## Where things are in the app
- Settings → Users & access: turn email sign-in on/off, turn username sign-in on/off, create username logins, change passwords.
- Settings → Notifications: master switches (all / email / WhatsApp / phone) and the phone-notification key.
- Settings → Lists → "Team “Works as” roles": add, rename, delete the tick-boxes. Keep "Manager" and "Planner".
- Team page: "Hide phone & email" button (also inside the New team member form).

## Good to know
- Tasks: given, updated and done alerts go to the app bell and the phone only (no email, no WhatsApp).
- Task privacy is enforced in the database, not just on screen. Admins see everything.
- "Hide phone & email" only masks the screen on that device. Anyone with app access can still read those details in the database.
- Email sign-in off = everyone except admins is blocked immediately. Admins can always use "Admin sign-in" on the login screen.
- If creating a username login fails with an "invalid email" error, change `users.vahan.invalid` to another domain in three places:
  `index.html` (USER_DOMAIN), `supabase-setup.sql` (app_role and my_team_id), `supabase/functions/admin-users/index.ts` (DOMAIN).
