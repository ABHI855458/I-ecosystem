-- Length limits on prompt text.
--
-- Both tables were unbounded `text`. These render as chips in the app's
-- prompt bar and ping sheet, where a long string either truncates to
-- meaninglessness or breaks the row — so the limit belongs in the database,
-- not only in whichever client happens to check.
--
-- 80 is chosen off the live data, not invented: the longest existing prompt
-- is 44 characters (ping_sheet_prompts) and 60 (daily_prompts), so 80 leaves
-- real headroom while staying inside what the chip can show.

ALTER TABLE public.ping_prompts DROP CONSTRAINT IF EXISTS ping_prompts_len;
ALTER TABLE public.ping_prompts ADD CONSTRAINT ping_prompts_len
  CHECK (char_length(btrim(prompt_text)) BETWEEN 1 AND 80);

ALTER TABLE public.ping_sheet_prompts DROP CONSTRAINT IF EXISTS ping_sheet_prompts_len;
ALTER TABLE public.ping_sheet_prompts ADD CONSTRAINT ping_sheet_prompts_len
  CHECK (char_length(btrim(prompt_text)) BETWEEN 1 AND 80);

ALTER TABLE public.daily_prompts DROP CONSTRAINT IF EXISTS daily_prompts_len;
ALTER TABLE public.daily_prompts ADD CONSTRAINT daily_prompts_len
  CHECK (char_length(btrim(prompt_text)) BETWEEN 1 AND 120);

SELECT 'ping_prompts' t, max(char_length(prompt_text)) longest FROM public.ping_prompts
UNION ALL SELECT 'ping_sheet_prompts', max(char_length(prompt_text)) FROM public.ping_sheet_prompts
UNION ALL SELECT 'daily_prompts', max(char_length(prompt_text)) FROM public.daily_prompts;
