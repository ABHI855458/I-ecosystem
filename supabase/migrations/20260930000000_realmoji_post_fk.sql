-- post_realmoji_reactions.post_id had NO foreign key (group_post_id and the
-- plain-emoji `reactions` table both cascade). Hard-deleting a post left its
-- RealMoji reactions behind — 3 orphans found in the 2026-09-30 audit.
-- Clean them up and cascade from now on, same as everything else.
delete from public.post_realmoji_reactions r
 where r.post_id is not null
   and not exists (select 1 from public.posts p where p.id = r.post_id);

alter table public.post_realmoji_reactions
  add constraint post_realmoji_reactions_post_id_fkey
  foreign key (post_id) references public.posts(id) on delete cascade;
