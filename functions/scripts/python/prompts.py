"""
Contains all prompts used in the story generation process.
"""

# Configuration
NUM_KEYFRAMES = 4
WORDS_PER_KEYFRAME = 15  # Reduced to ~5 seconds of narration

SCRIPT_GENERATION_PROMPT = f'''You are an expert storyteller tasked with creating a concise, impactful narrative.
Theme Keywords: {{keywords}}.

Requirements:
- Write a very short story (approximately {NUM_KEYFRAMES * WORDS_PER_KEYFRAME} words) that can be effectively told in {NUM_KEYFRAMES} brief scenes.
- Focus on a single, clear story arc with a beginning, middle, and end.
- Tell the entire story through a single narrator's voice - no character dialogue.
- Use concise, impactful language - each scene should be about 10-15 words.
- Write in a way that would work well when read aloud in about 5 seconds per scene.

Please produce the complete story in a structured format with clear scene headings.
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

DIALOG_EXTRACTION_PROMPT = '''You are a narrative editor. Given the complete story and a specific keyframe description, craft a brief narration that captures the essence of this moment.

Keyframe Description:
{keyframe_description}

Story:
{script}

Create a single brief narration that:
- Uses approximately 10-15 words
- Captures the most important action or moment
- Uses vivid, concise language
- Can be read aloud in about 5 seconds

Output Format:
Narration: [Brief narrative text, ~5 seconds when read aloud]
''' 