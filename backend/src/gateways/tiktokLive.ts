import type { TikTokClient, TikTokProfile, TikTokVideo } from "./tiktok.js";
import { getTikTokTokens, saveTikTokTokens } from "../modules/identity/tokens.js";

// Production TikTok client over the Display API + Login Kit.
//
// Env: TIKTOK_CLIENT_KEY, TIKTOK_CLIENT_SECRET, TIKTOK_REDIRECT_URI.
//
// Reality check before launch (this is the external dependency that gates the
// whole product):
//  - Login Kit gives user.info.basic (open_id, display_name).
//  - Display API's video.list/video.query return view_count, share_url, etc.
//    for the AUTHENTICATED user's own videos — which is exactly what the
//    counting job needs, because the clipper connected their account at
//    onboarding. Store each clipper's access/refresh token and poll their own
//    video objects with it.
//  - music_id is not first-class in the public Display API response; the
//    submission-time sound check falls back to oEmbed/share-url metadata
//    until the app is approved for richer scopes. Keep every raw payload on
//    view_sample.source so counts can be re-derived (§5).
export class LiveTikTok implements TikTokClient {
  constructor(
    private clientKey = process.env.TIKTOK_CLIENT_KEY ?? "",
    private clientSecret = process.env.TIKTOK_CLIENT_SECRET ?? "",
    // access-token lookup per video owner; defaults to the identity module's
    // token store with automatic refresh
    private tokenFor?: (openId: string) => Promise<string | null>,
  ) {
    if (!this.clientKey || !this.clientSecret)
      throw new Error("TIKTOK_CLIENT_KEY / TIKTOK_CLIENT_SECRET are not set");
    this.tokenFor ??= (openId) => this.storedToken(openId);
  }

  // Read the stored token; refresh through TikTok's token endpoint when it's
  // inside a minute of expiry.
  private async storedToken(openId: string): Promise<string | null> {
    const stored = await getTikTokTokens(openId);
    if (!stored) return null;
    if (stored.expiresAt.getTime() > Date.now() + 60_000) return stored.accessToken;
    if (!stored.refreshToken) return null;
    const res = await fetch("https://open.tiktokapis.com/v2/oauth/token/", {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        client_key: this.clientKey,
        client_secret: this.clientSecret,
        grant_type: "refresh_token",
        refresh_token: stored.refreshToken,
      }).toString(),
    });
    const body = (await res.json()) as {
      access_token?: string; refresh_token?: string; expires_in?: number;
    };
    if (!res.ok || !body.access_token) return null;
    await saveTikTokTokens(openId, {
      accessToken: body.access_token,
      refreshToken: body.refresh_token,
      expiresInSec: body.expires_in ?? 3600,
    });
    return body.access_token;
  }

  async exchangeCode(code: string) {
    const res = await fetch("https://open.tiktokapis.com/v2/oauth/token/", {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        client_key: this.clientKey,
        client_secret: this.clientSecret,
        code,
        grant_type: "authorization_code",
        redirect_uri: process.env.TIKTOK_REDIRECT_URI ?? "",
      }).toString(),
    });
    const body = (await res.json()) as {
      access_token?: string; refresh_token?: string; expires_in?: number;
      open_id?: string; scope?: string; error?: string; error_description?: string;
    };
    if (!res.ok || !body.open_id || !body.access_token)
      throw new Error(`tiktok oauth: ${body.error ?? res.status} — ${body.error_description ?? ""}`);
    await saveTikTokTokens(body.open_id, {
      accessToken: body.access_token,
      refreshToken: body.refresh_token,
      expiresInSec: body.expires_in ?? 3600,
      scopes: body.scope?.split(",") ?? [],
    });
    const info = await this.userInfo(body.access_token);
    return { openId: body.open_id, handle: info.handle };
  }

  private async userInfo(accessToken: string): Promise<{ handle: string }> {
    const res = await fetch(
      "https://open.tiktokapis.com/v2/user/info/?fields=open_id,display_name",
      { headers: { authorization: `Bearer ${accessToken}` } },
    );
    const body = (await res.json()) as { data?: { user?: { display_name?: string } } };
    return { handle: body.data?.user?.display_name ?? "unknown" };
  }

  async getProfile(openId: string): Promise<TikTokProfile | null> {
    const token = await this.tokenFor!(openId);
    if (!token) return null;
    const res = await fetch(
      "https://open.tiktokapis.com/v2/user/info/?fields=open_id,display_name,follower_count",
      { headers: { authorization: `Bearer ${token}` } },
    );
    if (!res.ok) return null;
    const body = (await res.json()) as {
      data?: { user?: { open_id?: string; display_name?: string; follower_count?: number } };
    };
    const u = body.data?.user;
    if (!u?.open_id) return null;
    return {
      openId: u.open_id,
      handle: u.display_name ?? "unknown",
      followerCount: u.follower_count ?? 0,
      // account age isn't exposed by the Display API; the §7 floor falls back
      // to follower count + our own first-seen date until scopes allow better
      accountAgeDays: 0,
    };
  }

  // Poll one video through its owner's token. videoId format: "{openId}:{id}"
  // so the counting job can find the right token without a schema change.
  async getVideo(videoId: string): Promise<TikTokVideo | null> {
    const [openId, id] = videoId.includes(":") ? videoId.split(":", 2) : [null, videoId];
    const token = openId ? await this.tokenFor!(openId) : null;
    if (!token || !id) return null;
    const res = await fetch(
      "https://open.tiktokapis.com/v2/video/query/?fields=id,view_count,share_url,create_time,music_id",
      {
        method: "POST",
        headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
        body: JSON.stringify({ filters: { video_ids: [id] } }),
      },
    );
    if (!res.ok) return null;
    const body = (await res.json()) as {
      data?: { videos?: { id: string; view_count?: number; create_time?: number; music_id?: string }[] };
    };
    const v = body.data?.videos?.[0];
    if (!v) return null; // deleted or private-to-API → counting job voids per §5
    return {
      videoId,
      authorOpenId: openId ?? "",
      musicId: v.music_id ?? null,
      isPublic: true, // the query API only returns publicly visible videos
      viewCount: v.view_count ?? 0,
      postedAt: new Date((v.create_time ?? 0) * 1000),
    };
  }
}
