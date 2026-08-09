// TikTok Display API client, stubbed behind an interface. The counting job
// and the submission checks depend only on this shape.

export interface TikTokVideo {
  videoId: string;
  authorOpenId: string;
  musicId: string | null;
  isPublic: boolean;
  viewCount: number;
  postedAt: Date;
}

export interface TikTokProfile {
  openId: string;
  handle: string;
  followerCount: number;
  accountAgeDays: number;
}

export interface TikTokClient {
  getVideo(videoId: string): Promise<TikTokVideo | null>; // null = deleted
  getProfile(openId: string): Promise<TikTokProfile | null>;
  exchangeCode(code: string): Promise<{ openId: string; handle: string }>;
}

// In-memory stub; tests and the dev server mutate `videos` directly to
// simulate view growth, deletions, and sound swaps.
export class StubTikTok implements TikTokClient {
  videos = new Map<string, TikTokVideo>();
  profiles = new Map<string, TikTokProfile>();

  async getVideo(videoId: string) {
    return this.videos.get(videoId) ?? null;
  }
  async getProfile(openId: string) {
    return this.profiles.get(openId) ?? null;
  }
  async exchangeCode(code: string) {
    // "code" doubles as the open id in the stub; handle defaults from it
    return { openId: code, handle: code.replace(/^oid_/, "") };
  }

  seedVideo(v: TikTokVideo) { this.videos.set(v.videoId, v); }
  seedProfile(p: TikTokProfile) { this.profiles.set(p.openId, p); }
}
