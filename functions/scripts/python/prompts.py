"""
Contains all prompts used in the story generation process.
"""

# Configuration
NUM_KEYFRAMES = 4
WORDS_PER_KEYFRAME = 125  # Approximate words per scene for good pacing

SCRIPT_GENERATION_PROMPT = f'''You are an expert screenwriter tasked with creating a concise, impactful screenplay.
Theme Keywords: {{keywords}}.

Requirements:
- Write a very short screenplay (approximately {NUM_KEYFRAMES * WORDS_PER_KEYFRAME} words) that can be effectively told in {NUM_KEYFRAMES} key scenes.
- Focus on a single, clear story arc with a beginning, middle, and end.
- Introduce only essential characters and provide vivid descriptions of key settings and actions.
- Include both narration and dialogue that evoke strong visual imagery and emotion.
- Keep the story focused and tight - each scene should have clear visual impact.

Please produce the complete screenplay in a structured format with clear scene headings.
'''

VISUAL_STYLE_PROMPT = '''You are a visual art director tasked with determining the most suitable visual style for a screenplay.
Based on the mood, setting, and overall atmosphere of the script, select ONE of the following styles that would best represent the visual aesthetic.

Consider:
- The genre and tone of the story
- The setting and time period
- The level of realism vs. stylization needed
- The emotional impact desired

Script:
{script}
'''

KEYFRAME_EXTRACTION_PROMPT = f'''You are a visual storyteller and scene director.
Below is a complete screenplay. Your task is to break it down into exactly {NUM_KEYFRAMES} key visual moments or "keyframes" that best capture the story's progression.

For each keyframe, provide:
1. A concise title (e.g., "The Enchanted Forest Entrance")
2. A vivid description that captures:
   - The setting (location, time of day, atmosphere)
   - Key actions and events
   - Mood and visual details (colors, lighting, textures)
   - Any notable visual effects or cinematic style cues

Guidelines:
- First keyframe should establish the setting and introduce key elements
- Middle keyframes should capture the story's main conflict or development
- Final keyframe should provide a satisfying visual conclusion
- Each description should be detailed and evocative, optimized for image generation

Script:
{{script}}

Return exactly {NUM_KEYFRAMES} keyframes, where each keyframe has a 'title' and 'description' field.'''

DIALOG_EXTRACTION_PROMPT = '''You are a narrative editor. Given the complete screenplay and a specific keyframe description, extract or rewrite the dialogue and narration that best correspond to that keyframe.

Keyframe Description:
{keyframe_description}

Script:
{script}

For this keyframe, please provide:
- A "Narration" section that describes the overall scene context.
- A "Dialogue" section that includes any character lines, clearly indicating the speaker for each line.

Output Format:
Narration: [Narrative text]
Dialogue:
  - [Character Name]: [Dialogue text]
  - [Character Name]: [Dialogue text] (if applicable)
''' 