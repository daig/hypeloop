"""
Contains all prompts used in the story generation process.
"""

SCRIPT_GENERATION_PROMPT = '''You are an expert screenwriter tasked with creating an engaging, cinematic screenplay.
Theme Keywords: {keywords}.

Requirements:
- Write a short screenplay (approximately 800-1000 words) with clear scene headings (e.g., "Scene 1", "Scene 2", etc.).
- Introduce key characters and provide vivid descriptions of settings, moods, and actions.
- Include both narration and dialogue that evoke strong visual imagery and emotion.
- Ensure the script flows logically and builds an engaging story arc.

Please produce the complete screenplay in a structured format.
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

KEYFRAME_EXTRACTION_PROMPT = '''You are a visual storyteller and scene director.
Below is a complete screenplay. Your task is to break it down into a series of key visual moments or "keyframes".

For each keyframe, provide:
1. A concise title (e.g., "The Enchanted Forest Entrance")
2. A vivid description that captures:
   - The setting (location, time of day, atmosphere)
   - Key actions and events
   - Mood and visual details (colors, lighting, textures)
   - Any notable visual effects or cinematic style cues

Ensure that each keyframe description is detailed and evocative, optimized for use as a prompt in an image-generation API.

Script:
{script}

Return a list of keyframes, where each keyframe has a 'title' and 'description' field.'''

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