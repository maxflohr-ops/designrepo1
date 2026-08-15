// TikTok client, stubbed behind an interface. Two products live here:
//   Display API      — reading a clipper's own videos (the counting job)
//   Content Posting  — posting the clip from inside our app (direct post)
// The counting job and submission checks depend only on these shapes.

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

// Content Posting API requires showing the creator's real posting options
// before a post is composed — privacy choices, interaction toggles, and the
// duration cap all come from creator_info and must be reflected in the UI.
export interface TikTokCreatorInfo {
  nickname: string;
  privacyOptions: string[]; // PUBLIC_TO_EVERYONE | MUTUAL_FOLLOW_FRIENDS | FOLLOWER_OF_CREATOR | SELF_ONLY
  maxVideoDurationSec: number;
  commentDisabled: boolean;
  duetDisabled: boolean;
  stitchDisabled: boolean;
}

export interface DirectPostInit {
  publishId: string;
  uploadUrl: string | null; // FILE_UPLOAD only; null for PULL_FROM_URL
}

export interface PublishStatus {
  state: "processing" | "complete" | "failed";
  videoId: string | null; // present once the post is publicly available
  failReason?: string;
}

export interface DirectPostRequest {
  caption: string;
  privacyLevel: string;
  videoSizeBytes: number;
  disableComment?: boolean;
  disableDuet?: boolean;
  disableStitch?: boolean;
}

export interface TikTokClient {
  getVideo(videoId: string): Promise<TikTokVideo | null>; // null = deleted
  getProfile(openId: string): Promise<TikTokProfile | null>;
  exchangeCode(code: string): Promise<{ openId: string; handle: string }>;

  // -- Content Posting API (needs the video.publish scope + a passed app
  // audit before posts can be anything but SELF_ONLY) ----------------------
  creatorInfo(openId: string): Promise<TikTokCreatorInfo | null>;
  initDirectPost(openId: string, req: DirectPostRequest): Promise<DirectPostInit>;
  publishStatus(openId: string, publishId: string): Promise<PublishStatus>;
}

// In-memory stub; tests and the dev server mutate `videos` directly to
// simulate view growth, deletions, and sound swaps, and drive publishes
// through completePublish().
export class StubTikTok implements TikTokClient {
  videos = new Map<string, TikTokVideo>();
  profiles = new Map<string, TikTokProfile>();
  publishes = new Map<string, PublishStatus>();
  private publishSeq = 0;

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

  async creatorInfo(openId: string): Promise<TikTokCreatorInfo | null> {
    const profile = this.profiles.get(openId);
    if (!profile) return null;
    return {
      nickname: profile.handle,
      privacyOptions: ["PUBLIC_TO_EVERYONE", "MUTUAL_FOLLOW_FRIENDS", "SELF_ONLY"],
      maxVideoDurationSec: 600,
      commentDisabled: false,
      duetDisabled: false,
      stitchDisabled: false,
    };
  }

  async initDirectPost(openId: string, _req: DirectPostRequest): Promise<DirectPostInit> {
    const publishId = `pub_${openId}_${++this.publishSeq}`;
    this.publishes.set(publishId, { state: "processing", videoId: null });
    return { publishId, uploadUrl: `https://stub.upload/${publishId}` };
  }

  async publishStatus(_openId: string, publishId: string): Promise<PublishStatus> {
    return this.publishes.get(publishId) ?? { state: "failed", videoId: null, failReason: "unknown_publish" };
  }

  seedVideo(v: TikTokVideo) { this.videos.set(v.videoId, v); }
  seedProfile(p: TikTokProfile) { this.profiles.set(p.openId, p); }

  // Test driver: land the publish. `indexed: false` models the real lag where
  // TikTok reports the post live before the Display API can return it.
  completePublish(publishId: string, video: TikTokVideo, opts: { indexed?: boolean } = {}) {
    if (opts.indexed !== false) this.videos.set(video.videoId, video);
    this.publishes.set(publishId, { state: "complete", videoId: video.videoId });
  }
  failPublish(publishId: string, reason: string) {
    this.publishes.set(publishId, { state: "failed", videoId: null, failReason: reason });
  }
}
