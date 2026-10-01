// Sends a phone (Web Push) notification whenever a row is added to the `notifications` table.
// Wire it up with a Database Webhook: table notifications, event INSERT, POST to this function,
// HTTP header  x-webhook-secret: <same value as the PUSH_WEBHOOK_SECRET secret>.
import { createClient } from "npm:@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";

Deno.serve(async (req) => {
  try {
    if (req.headers.get("x-webhook-secret") !== Deno.env.get("PUSH_WEBHOOK_SECRET")) return new Response("forbidden", { status: 403 });
    const payload = await req.json();
    const rec = payload?.record;
    if (payload?.type !== "INSERT" || !rec?.recipient_email) return new Response("skipped");

    const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

    // the admin's master switches (Settings → Notifications) are enforced here too
    const { data: sw } = await admin.from("app_settings").select("key,value").in("key", ["notif_all", "notif_push", "app_url"]);
    const flag = Object.fromEntries((sw || []).map((r: { key: string; value: unknown }) => [r.key, r.value]));
    if (flag.notif_all === false || flag.notif_push === false) return new Response("switched off");

    const { data: subs } = await admin.from("push_subscriptions").select("id,endpoint,p256dh,auth").eq("user_email", String(rec.recipient_email).toLowerCase());
    if (!subs?.length) return new Response("no devices");

    webpush.setVapidDetails(Deno.env.get("VAPID_SUBJECT") || "mailto:admin@example.com", Deno.env.get("VAPID_PUBLIC_KEY")!, Deno.env.get("VAPID_PRIVATE_KEY")!);
    const body = JSON.stringify({
      title: String(rec.title || "Parts Tracker").slice(0, 120),
      body: String(rec.body || "").slice(0, 200),
      url: "./#/" + String(rec.link || ""),
      tag: String(rec.id || ""),
    });
    let sent = 0;
    await Promise.all(subs.map(async (s: { id: string; endpoint: string; p256dh: string; auth: string }) => {
      try {
        await webpush.sendNotification({ endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } }, body, { TTL: 86400, urgency: "high" });
        sent++;
      } catch (e) {
        const code = (e as { statusCode?: number }).statusCode;
        if (code === 404 || code === 410) await admin.from("push_subscriptions").delete().eq("id", s.id); // device gone
        else console.warn("push failed", code);
      }
    }));
    return new Response(`sent ${sent}`);
  } catch (e) {
    console.error(e);
    return new Response("error", { status: 500 });
  }
});
