// Constants
export const WORDS_PER_KEYFRAME = 200;

// Prompt templates
export const SCRIPT_GENERATION_PROMPT = `
Generate a creative and engaging story based on the following themes/keywords: {keywords}

The story should be suitable for a children's storybook with visual scenes and dialog.
Focus on creating a clear narrative arc with:
1. A compelling beginning that introduces the main characters
2. A middle section with rising action and conflict
3. A satisfying resolution

Please write the story in a way that can be naturally broken into visual scenes.
`;

export const KEYFRAME_EXTRACTION_PROMPT = `
Given the following story, extract {num_keyframes} key visual moments that would make compelling illustrations.
Each keyframe should capture an important story beat and include any characters present in the scene.

Story:
{script}

Please format your response as a JSON object with this structure:
{
  "keyframes": [
    {
      "title": "Brief scene title",
      "description": "Detailed visual description of the scene",
      "characters_in_scene": ["Character names present"]
    }
  ]
}
`;

export const DIALOG_EXTRACTION_PROMPT = `
For the following scene, create natural dialog or narration that moves the story forward.
Choose the most appropriate character to speak or narrate this moment.

Scene Description:
{keyframe_description}

Full Story Context:
{script}

Available Characters:
{characters}

Please format your response as a JSON object with this structure:
{
  "character": {
    "role": "narrator|child|elder|fairy|hero|villain|sage|sidekick",
    "name": "Character name",
    "backstory": "Brief character backstory",
    "physical_description": "How they look",
    "personality": "Their personality traits"
  },
  "text": "The dialog or narration text"
}
`;

export const VISUAL_STYLE_PROMPT = `
Based on the following story, determine the most appropriate visual style for the illustrations.
Consider the tone, setting, and target audience.

Story:
{script}

Please format your response as a JSON object with this structure:
{
  "style": "RENDER_3D|ACRYLIC|ANIME_GENERAL|CREATIVE|DYNAMIC|FASHION|GAME_CONCEPT|GRAPHIC_DESIGN_3D|ILLUSTRATION|NONE|PORTRAIT|PORTRAIT_CINEMATIC|RAY_TRACED|STOCK_PHOTO|WATERCOLOR"
}
`;

export const CHARACTER_EXTRACTION_PROMPT = `
From the following story, identify and create detailed character profiles for all major characters.
Include both speaking characters and important background characters.

Story:
{script}

Please format your response as a JSON object with this structure:
{
  "characters": [
    {
      "role": "narrator|child|elder|fairy|hero|villain|sage|sidekick",
      "name": "Character name",
      "backstory": "Brief character backstory",
      "physical_description": "How they look",
      "personality": "Their personality traits"
    }
  ]
}
`;

export const SCRIPT_ENHANCEMENT_PROMPT = `
Enhance the following story by incorporating the character details more naturally into the narrative.
The enhanced version should be approximately {total_words} words and maintain the same core story
while making better use of the characters' personalities and relationships.

Original Story:
{script}

Character Details:
{characters}

Please write an enhanced version that:
1. Maintains the core plot points
2. Incorporates character personalities and relationships
3. Adds natural dialog where appropriate
4. Creates clear scene transitions
5. Is suitable for visual adaptation
`;

export const LEONARDO_PROMPT_OPTIMIZATION = `
Optimize the following scene descriptions for Leonardo's image generation model.
Create prompts that will generate consistent, high-quality illustrations in the specified style.

Scenes:
{keyframe_descriptions}

Visual Style: {visual_style}

For each scene, provide an optimized prompt that:
1. Maintains visual consistency across all images
2. Emphasizes the chosen art style
3. Includes specific details about lighting, composition, and mood
4. Incorporates character descriptions naturally

Format each prompt as a numbered list (1:, 2:, etc.)
`;

export const KEYFRAME_SCENE_GENERATION_PROMPT = `
Create two connected scenes for the following keyframe that will work together
to tell this part of the story effectively.

Keyframe Title: {title}
Description: {description}
Characters Present: {characters_in_scene}

Character Profiles:
{character_profiles}

Please format your response as a JSON object with this structure:
{
  "scenes": [
    {
      "character": {
        "role": "narrator|child|elder|fairy|hero|villain|sage|sidekick",
        "name": "Character name",
        "backstory": "Brief character backstory",
        "physical_description": "How they look",
        "personality": "Their personality traits"
      },
      "dialog": "The spoken text for this scene",
      "title": "Brief scene title",
      "description": "Detailed visual description",
      "characters_in_scene": ["Character names present"]
    }
  ]
}

The first scene should focus on setting the stage and introducing any new characters.
The second scene should capture the main action or emotional moment.
`; 