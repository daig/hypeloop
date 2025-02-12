/**
 * Contains all prompts used in the story generation process.
 */

// Configuration
export const WORDS_PER_KEYFRAME = 15; // Reduced to ~5 seconds of narration

export const SCRIPT_GENERATION_PROMPT = `You are an expert storyteller tasked with creating a concise, impactful narrative.
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
`;

export const VISUAL_STYLE_PROMPT = `You are a visual art director tasked with determining the most suitable visual style for a screenplay.
Based on the mood, setting, and overall atmosphere of the script, select ONE of the following styles that would best represent the visual aesthetic.

Consider:
- The genre and tone of the story
- The setting and time period
- The level of realism vs. stylization needed
- The emotional impact desired

Script:
{script}
`;

export const KEYFRAME_EXTRACTION_PROMPT = `You are a visual storyteller and scene director.
Below is a complete screenplay. Your task is to break it down into exactly {num_keyframes} key visual moments or "keyframes" that best capture the story's progression.

For each keyframe, provide:
1. A concise title (e.g., "The Enchanted Forest Entrance")
2. A vivid description that captures:
   - The setting (location, time of day, atmosphere)
   - Key actions and events
   - Mood and visual details (colors, lighting, textures)
   - Any notable visual effects or cinematic style cues
3. A list of character names who are present in this scene (even if they are just in the background)
   IMPORTANT: You must ALWAYS include a characters_in_scene list for each keyframe, even if it's empty ([])

Guidelines:
- First keyframe should establish the setting and introduce key elements
- Middle keyframes should capture the story's main conflict or development
- Final keyframe should provide a satisfying visual conclusion
- Each description should be detailed and evocative, optimized for image generation
- For each keyframe, identify ALL characters who are present in the scene, even if they're not the main focus
- Maintain character consistency across keyframes (if a character appears in multiple scenes)
- If no characters are present in a scene, provide an empty list for characters_in_scene ([])

Script:
{script}

Return exactly {num_keyframes} keyframes in JSON format, where each keyframe MUST have:
- A 'title' field (string)
- A 'description' field (string)
- A 'characters_in_scene' field (array of strings, can be empty but must be present)

Example format:
{
  "keyframes": [
    {
      "title": "The Enchanted Forest Entrance",
      "description": "A mystical forest bathed in soft light...",
      "characters_in_scene": ["Hero", "Forest Spirit"]
    },
    {
      "title": "Empty Clearing",
      "description": "A serene clearing with no characters present...",
      "characters_in_scene": []
    }
  ]
}`;

export const DIALOG_EXTRACTION_PROMPT = `You are a narrative editor. Given the complete story, a specific keyframe description, and character profiles, craft a brief narration that captures the essence of this moment.

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
- text: Brief narrative text (~5 seconds when read aloud) in the chosen voice`;

export const CHARACTER_EXTRACTION_PROMPT = `You are a character designer and storyteller. Given a script, identify and develop the main characters that would best fit this narrative.

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

Return a list of characters, where each character has 'role', 'name', 'backstory', 'physical_description', and 'personality' fields.`;

export const SCRIPT_ENHANCEMENT_PROMPT = `You are a master storyteller tasked with enhancing a basic story outline by incorporating a cast of rich characters.

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

Return the enhanced version of the script that weaves in the characters while maintaining the core story.`;

export const IMAGE_GEN_REFINEMENT_PROMPT = `
Story Keyframes:
{keyframe_descriptions}

Visual Style:
{visual_style}

Your task:
1. For EACH keyframe, transform its 'description' into a single, richly detailed paragraph suitable for an image-generation AI. 
2. Preserve the key visual elements (setting, characters, atmosphere) from the original description.
3. Add any cinematic details (camera angle, lighting style, color palette) or stylistic cues (e.g., high-fantasy, photorealistic, painterly) that would help an image model generate the most vivid scene possible.
4. Your final output should consist of one refined image prompt per keyframe, each separated clearly (e.g., numbered list or distinct sections), but keep each prompt as a concise paragraph of descriptive text without bullet points.
`;

export const LEONARDO_PROMPT_OPTIMIZATION = `You are an expert at creating refined visual prompts for generative image models, such as Leonardo's Flux Schnell. Your task is to transform a series of keyframe descriptions into optimized prompts that will generate high-quality, visually consistent images.

Below, you will be given ALL the keyframes (with their titles, descriptions, and character information) that were produced by the KEYFRAME_EXTRACTION_PROMPT.

Story Keyframes:
{keyframe_descriptions}

Visual Style:
{visual_style}

Guidelines for optimization:
- Ensure visual consistency across all keyframes
- Maintain the same artistic style, lighting approach, and color palette
- Focus on the most visually important elements in each scene
- Use specific, descriptive adjectives for materials, lighting, and atmosphere
- Maintain consistency with the chosen visual style
- Keep each prompt concise but detailed
- Include relevant artistic keywords that enhance the style (e.g. cinematic, volumetric lighting, detailed)
- Use similar descriptive patterns across all prompts

Character Consistency Guidelines:
- For each character that appears in multiple scenes, maintain consistent:
  * Physical appearance (height, build, facial features)
  * Clothing style and colors
  * Hair color and style
  * Skin tone
  * Distinguishing features
- When a character first appears, establish their visual details clearly
- In subsequent appearances, reference the established appearance
- If a character is in the background, still mention them with consistent details

Format each prompt to emphasize:
1. Main subject and action
2. Setting and environment
3. Lighting and atmosphere
4. Camera angle and composition
5. Artistic style and rendering quality
6. Character details and positioning

Remove any non-visual narrative elements but keep all visual character details for consistency.

Return a list of optimized prompts, one for each keyframe, maintaining the same order as the input descriptions. Each prompt should be on a new line starting with the keyframe number (e.g., "1:", "2:", etc.).`;

export const KEYFRAME_SCENE_GENERATION_PROMPT = `You are a master storyteller and dialogue writer. For each keyframe, you will create two connected scenes that occur in the same setting and timespan:
1. A narration scene that introduces any new characters and sets the stage
2. A character dialogue scene that captures the primary actions

Keyframe Information:
Title: {title}
Description: {description}
Characters Present: {characters_in_scene}

Available Characters:
{character_profiles}

CRITICAL LENGTH CONSTRAINTS:
- Each scene's dialog MUST be exactly 10-15 words long
- Each scene MUST be readable in 5 seconds or less
- Longer scenes will be rejected by the text-to-speech system
- Count your words carefully before submitting

Guidelines:
1. For the Narration Scene:
   - Use the narrator's voice to introduce any new characters and set the stage
   - Keep descriptions extremely concise but vivid
   - Focus on the most important visual elements
   - MAXIMUM 15 WORDS - count them!

2. For the Character Dialog Scene:
   - Choose the most appropriate character to speak based on the action
   - Keep dialog natural but extremely concise
   - Focus on the main action or emotional moment
   - MAXIMUM 15 WORDS - count them!

Both scenes should:
- Take place in the exact same setting and moment in time
- Feel connected and flow naturally together
- STRICTLY adhere to the 10-15 word limit
- Be readable in 5 seconds or less
- Maintain consistent character personalities
- Support the overall story progression

Example Format (note the word count):
1. Narration (12 words):
   "In the moonlit garden, Sarah discovers an ancient stone glowing with magic."

2. Dialog (11 words):
   "The crystal pulses with power as I touch its surface."

Return exactly TWO scenes:
1. A narration scene using the narrator's voice to introduce new characters and set the stage
2. A character dialog scene featuring the most appropriate character for the main action`;