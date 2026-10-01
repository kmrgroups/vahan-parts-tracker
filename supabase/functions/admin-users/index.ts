// Admin-only: create / reset password / remove a username login.
// Username logins are stored as <username>@users.vahan.invalid (no real mailbox). Keep DOMAIN in sync with index.html (USER_DOMAIN) and the SQL.
import { createClient } from "npm:@supabase/supabase-js@2";

const DOMAIN = "users.vahan.invalid";
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const json = (b: unknown, status = 200) =>
  new Response(JSON.stringify(b), { status, headers: { ...cors, "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const token = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
    const { data: who, error: authErr } = await admin.auth.getUser(token);
    if (authErr || !who?.user) return json({ error: "Please sign in again." }, 401);
    const { data: me } = await admin.from("profiles").select("role").eq("id", who.user.id).maybeSingle();
    if (me?.role !== "admin") return json({ error: "Only admins can do this." }, 403);

    const b = await req.json();
    const username = String(b.username || "").trim().toLowerCase();
    if (!/^[a-z0-9._-]{3,30}$/.test(username)) return json({ error: "Username: 3–30 letters, numbers, dot, dash or underscore." }, 400);
    const email = `${username}@${DOMAIN}`;

    if (b.action === "create") {
      const password = String(b.password || "");
      if (password.length < 6) return json({ error: "Password needs at least 6 characters." }, 400);
      const role = ["member", "editor", "viewer"].includes(b.role) ? b.role : "member";
      const { data, error } = await admin.auth.admin.createUser({
        email, password, email_confirm: true,
        user_metadata: { full_name: String(b.full_name || username).slice(0, 80) },
      });
      if (error) return json({ error: /already/i.test(error.message) ? "That username is already taken." : error.message }, 400);
      // the sign-up trigger creates the profile; give it the chosen access level
      const { error: pe } = await admin.from("profiles").update({ role, full_name: String(b.full_name || username).slice(0, 80) }).eq("id", data.user.id);
      if (pe) return json({ error: "Login created but access level could not be set: " + pe.message }, 500);
      return json({ ok: true, id: data.user.id });
    }

    const { data: target } = await admin.from("profiles").select("id,email").eq("email", email).maybeSingle();
    if (!target) return json({ error: "No such username." }, 404);

    if (b.action === "set_password") {
      const password = String(b.password || "");
      if (password.length < 6) return json({ error: "Password needs at least 6 characters." }, 400);
      const { error } = await admin.auth.admin.updateUserById(target.id, { password });
      if (error) return json({ error: error.message }, 400);
      return json({ ok: true });
    }
    if (b.action === "delete") {
      const { error } = await admin.auth.admin.deleteUser(target.id);
      if (error) return json({ error: error.message }, 400);
      await admin.from("profiles").delete().eq("id", target.id);
      return json({ ok: true });
    }
    return json({ error: "Unknown action." }, 400);
  } catch (e) {
    return json({ error: String((e as Error)?.message || e) }, 500);
  }
});
