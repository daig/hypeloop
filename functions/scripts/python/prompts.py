"""
Contains all prompts used in the story generation process.
"""

# Configuration
WORDS_PER_KEYFRAME = 15  # Reduced to ~5 seconds of narration

SCRIPT_GENERATION_PROMPT = '''You are an expert storyteller tasked with creating a concise, impactful narrative.
Theme Keywords: {keywords}.

Requirements:
- Write a story that captures the essence of the theme keywords
- Focus on a single, clear story arc with a beginning, middle, and end
- Tell the entire story through a single narrator's voice - no character dialogue
- Focus on the core narrative elements and key moments
- Use vivid, descriptive language that sets up the world and events

The story should establish:
- The setting and atmosphere
- Key events and conflicts
- Important story beats
- Emotional moments and turning points
- A satisfying resolution

This is an initial draft that will be enhanced later with character details, so focus on creating a strong narrative foundation.
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
Below is a complete screenplay. Your task is to break it down into exactly {num_keyframes} key visual moments or "keyframes" that best capture the story's progression.

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
{script}

Return exactly {num_keyframes} keyframes, where each keyframe has a 'title' and 'description' field.'''

DIALOG_EXTRACTION_PROMPT = '''You are a narrative editor. Given the complete story, a specific keyframe description, and character profiles, craft a brief narration that captures the essence of this moment.

Keyframe Description:
{keyframe_description}

Story:
{script}

Available Characters:
{characters}

IMPORTANT: The primary voice should be the narrator's, creating a cohesive storytelling experience. Only use character voices in specific moments where their direct perspective significantly enhances the emotional impact.

Guidelines for choosing who speaks:
1. Use the narrator voice (default) when:
   - Describing scenes, settings, or atmosphere
   - Explaining actions or events
   - Bridging moments or transitions
   - Providing context or background
   - Conveying general emotions or mood
2. Only use character voices when:
   - A character performs a highly significant or emotionally charged action
   - The moment represents a critical turning point for that character
   - The character's unique perspective would create substantially more impact than narration
   - The character's voice would reveal something the narrator cannot

Create a single brief narration that:
- Uses approximately 10-15 words
- Captures the most important action or moment
- Uses vivid, concise language
- Can be read aloud in about 5 seconds
- Maintains a consistent narrative tone
- Focuses on emotional impact and story progression

Output Format:
A DialogResponse with:
- character: Either a full Character object from the available list, or a narrator (role="narrator", name="Narrator")
- text: Brief narrative text (~5 seconds when read aloud) in the chosen voice'''

CHARACTER_EXTRACTION_PROMPT = '''You are a character designer and storyteller. Given a script, identify and develop the main characters that would best fit this narrative.

Script:
{script}

For each character, provide:
1. A role from the following options: child, elder, fae, hero, villain, sage, sidekick
2. A unique and fitting name that matches their role in the story
3. A rich backstory that explains their motivations and history
4. A detailed physical description including appearance and distinguishing features
5. A personality profile including traits, mannerisms, and speaking style

Guidelines:
- Each character should feel unique and memorable
- Descriptions should be detailed enough for both visual and audio representation
- Characters should naturally fit within the story's world and tone
- Consider how each character would sound when speaking (voice acting considerations)
- Focus on the main characters that drive the story (typically 2-4 characters)

Return a list of characters, where each character has 'role', 'name', 'backstory', 'physical_description', and 'personality' fields.'''

SCRIPT_ENHANCEMENT_PROMPT = '''You are a master storyteller tasked with enhancing a basic story outline by incorporating a cast of rich characters.

Original Script:
{script}

Available Characters:
{characters}

Your task is to rewrite the story while:
1. Maintaining the same core plot and themes
2. Incorporating all provided characters naturally into the narrative
3. Using each character's unique traits and background to enrich the story
4. Ensuring the story flows naturally and each character's involvement makes sense
5. Maintaining a single narrative voice - no direct dialogue
6. Creating a concise, impactful narrative (approximately {total_words} words)
7. Writing in a way that would work well when read aloud (about 5 seconds per scene)

Guidelines:
- Use the characters' backstories and personalities to add depth
- Ensure each character's involvement aligns with their established traits
- Keep the story focused and avoid unnecessary tangents
- Write in a way that works well for visual adaptation and narration

Return the enhanced version of the script that weaves in the characters while maintaining the core story.'''

IMAGE_GEN_REFINEMENT_PROMPT = """

Story Keyframes:
{{keyframe_descriptions}}

Visual Style:
{{visual_style}}

Your task:
1. For EACH keyframe, transform its 'description' into a single, richly detailed paragraph suitable for an image-generation AI. 
2. Preserve the key visual elements (setting, characters, atmosphere) from the original description.
3. Add any cinematic details (camera angle, lighting style, color palette) or stylistic cues (e.g., high-fantasy, photorealistic, painterly) that would help an image model generate the most vivid scene possible.
4. Your final output should consist of one refined image prompt per keyframe, each separated clearly (e.g., numbered list or distinct sections), but keep each prompt as a concise paragraph of descriptive text without bullet points.
"""

LEONARDO_PROMPT_OPTIMIZATION = '''You are an expert at creating refined visual prompts for generative image models, such as Leonardo’s Flux Schnell. Your task is to transform a series of keyframe descriptions into optimized prompts that will generate high-quality, visually consistent images.

Below, you will be given ALL the keyframes (with their titles and descriptions) that were produced by the KEYFRAME_EXTRACTION_PROMPT.

Story Keyframes:
{keyframe_descriptions}

Visual Style:
{visual_style}

Guidelines for optimization:
- Ensure visual consistency across all keyframes.
- Maintain the same artistic style, lighting approach, and color palette
- Focus on the most visually important elements in each scene
- Use specific, descriptive adjectives for materials, lighting, and atmosphere
- Maintain consistency with the chosen visual style
- Keep each prompt concise but detailed. 
- Include relevant artistic keywords that enhance the style (e.g. cinematic, volumetric lighting, detailed)
- Use similar descriptive patterns across all prompts

Format each prompt to emphasize ONLY:
1. Main subject and action
2. Setting and environment
3. Lighting and atmosphere
4. Camera angle and composition
5. Artistic style and rendering quality

Remove any non-visual narrative elements
If a character appears in multiple keyframes, make sure to keep their hair color, skin color, and clothing consistent and reitterated in each prompt.

Return a list of optimized prompts, one for each keyframe, maintaining the same order as the input descriptions. Each prompt should be on a new line starting with the keyframe number (e.g., "1:", "2:", etc.).'''

# ---------- Response Formats ---------- 