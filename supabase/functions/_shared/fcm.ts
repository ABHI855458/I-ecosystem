// FCM HTTP v1 sender — used for both iOS and Android device tokens (Firebase
// can deliver to APNs under the hood for iOS, so this is the one push path
// for both platforms; see supabase/functions/README.md for the Firebase
// project setup this depends on).
//
// Needs three Edge Function secrets (`supabase secrets set ...`), not
// checked into this repo:
//   FCM_PROJECT_ID    — Firebase project id
//   FCM_CLIENT_EMAIL  — service account client_email
//   FCM_PRIVATE_KEY   — service account private_key (PEM, literal \n's ok)
//
// Get all three from Firebase Console → Project Settings → Service
// accounts → Generate new private key.

interface AccessToken {
  token: string;
  expiresAt: number; // epoch ms
}

let cachedToken: AccessToken | null = null;

function base64url(bytes: ArrayBuffer | Uint8Array): string {
  const arr = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  let str = "";
  for (const b of arr) str += String.fromCharCode(b);
  return btoa(str).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemToPkcs8(pem: string): ArrayBuffer {
  const clean = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const raw = atob(clean);
  const bytes = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) bytes[i] = raw.charCodeAt(i);
  return bytes.buffer;
}

async function getAccessToken(): Promise<string> {
  if (cachedToken && cachedToken.expiresAt > Date.now() + 30_000) {
    return cachedToken.token;
  }

  const projectId = Deno.env.get("FCM_PROJECT_ID");
  const clientEmail = Deno.env.get("FCM_CLIENT_EMAIL");
  const privateKeyPem = (Deno.env.get("FCM_PRIVATE_KEY") ?? "").replace(/\\n/g, "\n");
  if (!projectId || !clientEmail || !privateKeyPem) {
    throw new Error("FCM_PROJECT_ID / FCM_CLIENT_EMAIL / FCM_PRIVATE_KEY not configured");
  }

  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "RS256", typ: "JWT" };
  const claims = {
    iss: clientEmail,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  };

  const encoder = new TextEncoder();
  const signingInput =
    `${base64url(encoder.encode(JSON.stringify(header)))}.` +
    `${base64url(encoder.encode(JSON.stringify(claims)))}`;

  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToPkcs8(privateKeyPem),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    encoder.encode(signingInput),
  );
  const jwt = `${signingInput}.${base64url(signature)}`;

  const resp = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  if (!resp.ok) {
    throw new Error(`FCM token exchange failed: ${resp.status} ${await resp.text()}`);
  }
  const json = await resp.json();
  cachedToken = { token: json.access_token, expiresAt: Date.now() + json.expires_in * 1000 };
  return cachedToken.token;
}

export interface PushPayload {
  token: string;
  title: string;
  body: string;
  data: Record<string, string>;
}

export interface SendResult {
  ok: boolean;
  /** True when FCM says this token will NEVER work again — the app instance
   * was uninstalled, or a newer token superseded it. FCM v1's signal for
   * this is a plain HTTP 404 with `error.status: "UNREGISTERED"` (or, on
   * some responses, "NOT_FOUND"). Distinct from every other failure
   * (network blip, quota, malformed payload), which must NOT delete a
   * token that might still be good on the next attempt. */
  deadToken: boolean;
}

/** Sends one push. Never throws — callers fan out over many tokens without
 * one bad token failing the batch (see notify.ts sendToUser), and [deadToken]
 * tells the caller which rows are safe to delete from device_tokens.
 *
 * BUG FIX: this used to return a bare boolean and nothing downstream ever
 * acted on a failure — a token FCM had permanently given up on stayed in
 * device_tokens forever and kept being retried (and, worse, a token that
 * still half-works during its rotation grace period kept succeeding and
 * delivering a SEPARATE copy of every push). See sendToUser's own doc for
 * the "same notification several times" bug this was one half of. */
export async function sendPush(payload: PushPayload): Promise<SendResult> {
  const projectId = Deno.env.get("FCM_PROJECT_ID");
  const accessToken = await getAccessToken();

  const resp = await fetch(
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${accessToken}`,
      },
      body: JSON.stringify({
        message: {
          token: payload.token,
          notification: { title: payload.title, body: payload.body },
          data: payload.data,
          apns: { payload: { aps: { sound: "default" } } },
          android: { priority: "high" },
        },
      }),
    },
  );

  if (!resp.ok) {
    const errText = await resp.text();
    console.error(`FCM send failed for token ${payload.token.slice(0, 12)}…: ${resp.status} ${errText}`);
    // HTTP 404 is FCM v1's unambiguous "this registration token is gone,
    // stop sending to it" signal (error.status UNREGISTERED / NOT_FOUND).
    // Every other status (400 malformed, 401/403 auth, 429/5xx transient)
    // says nothing about the TOKEN's validity, so those tokens are left
    // alone — deleting on a transient error would drop a perfectly good
    // device the next time this exact send would have succeeded.
    return { ok: false, deadToken: resp.status === 404 };
  }
  return { ok: true, deadToken: false };
}
