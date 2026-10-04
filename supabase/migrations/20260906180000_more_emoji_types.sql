-- ---------------------------------------------------------------------------
-- More RealMoji reactions.
--
-- emoji_type_enum had six values (like/joy/surprise/love/laughter/instant),
-- which is what the tray and the RealMoji library could ever offer —
-- "add more emoji as such, plenty of them". Twelve more, chosen to cover the
-- registers students actually react in rather than to pad the list: each one
-- costs a person a separate selfie to fill, so this stays curated.
--
-- ADD VALUE only. Nothing is renamed or removed, so every existing
-- user_realmojis / post_realmoji_reactions row keeps its meaning and no
-- backfill is needed. Order matters only for display, and the client keeps
-- its own order anyway (RealmojiType's declaration order).
-- ---------------------------------------------------------------------------

alter type public.emoji_type_enum add value if not exists 'fire';
alter type public.emoji_type_enum add value if not exists 'cry';
alter type public.emoji_type_enum add value if not exists 'cool';
alter type public.emoji_type_enum add value if not exists 'heart_eyes';
alter type public.emoji_type_enum add value if not exists 'clap';
alter type public.emoji_type_enum add value if not exists 'wink';
alter type public.emoji_type_enum add value if not exists 'angry';
alter type public.emoji_type_enum add value if not exists 'shy';
alter type public.emoji_type_enum add value if not exists 'party';
alter type public.emoji_type_enum add value if not exists 'mind_blown';
alter type public.emoji_type_enum add value if not exists 'skull';
alter type public.emoji_type_enum add value if not exists 'hundred';
