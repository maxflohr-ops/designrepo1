-- Content Posting API: a claim can carry an in-flight TikTok publish. The
-- publish id is how we tie the upload the clipper made in-app to the video
-- id TikTok hands back once it goes live.
alter table claim add column tiktok_publish_id text;
create index claim_publish_idx on claim (tiktok_publish_id) where tiktok_publish_id is not null;
