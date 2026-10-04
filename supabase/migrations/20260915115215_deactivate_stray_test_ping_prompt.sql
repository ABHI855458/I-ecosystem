UPDATE public.ping_prompts SET active = false
 WHERE prompt_text = 'DEFINETLY BRO'
   AND daily_prompt_id = (SELECT id FROM public.daily_prompts WHERE prompt_text = 'OVERRRATED COLLEGE PLACE');
