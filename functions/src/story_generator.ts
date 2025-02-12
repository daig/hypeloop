import OpenAI from 'openai';
import { task, entrypoint, type LangGraphRunnableConfig, MemorySaver } from '@langchain/langgraph';
import * as dotenv from 'dotenv';
import path from 'path';
import fs from 'fs/promises';
import { z } from 'zod';
import { zodResponseFormat } from 'openai/helpers/zod';
import {
  Role,
  type Character,
  type Characters,
  type VisualStyleResponse,
  type DialogResponse,
  type Keyframe,
  type KeyframeResponse,
  type KeyframeScene,
  type KeyframesWithDialog,
  type LeonardoStyle
} from './schemas';
import { generateSpeechFromText } from './tts_core';
import {
  SCRIPT_GENERATION_PROMPT,
  KEYFRAME_EXTRACTION_PROMPT,
  DIALOG_EXTRACTION_PROMPT,
  VISUAL_STYLE_PROMPT,
  CHARACTER_EXTRACTION_PROMPT,
  SCRIPT_ENHANCEMENT_PROMPT,
  LEONARDO_PROMPT_OPTIMIZATION,
  WORDS_PER_KEYFRAME,
  KEYFRAME_SCENE_GENERATION_PROMPT
} from './prompts';

// Load environment variables
const envPath = path.join(__dirname, '..', '.env');
dotenv.config({ path: envPath });

// Initialize OpenAI client
const client = new OpenAI({
  apiKey: process.env.OPENAI_API_KEY
});

// Helper function to invoke OpenAI chat completion
async function invokeChatCompletion<T>(
  prompt: string,
  responseFormat?: { schema: z.ZodSchema<T> }
): Promise<T | string> {
  const params = {
    model: "gpt-4o-mini",
    messages: [{ role: "user" as const, content: prompt }],
    temperature: 0.7,
  };

  if (responseFormat) {
    // Get the schema description or fall back to a generic name
    const schemaDescription = responseFormat.schema.description || 'structured_response';

    const completion = await client.beta.chat.completions.parse({
      ...params,
      response_format: zodResponseFormat(responseFormat.schema, schemaDescription)
    });

    const message = completion.choices[0]?.message;
    if (!message?.parsed) {
      throw new Error("No parsed response received");
    }
    return message.parsed as T;
  } else {
    const response = await client.chat.completions.create(params);
    return response.choices[0].message.content!;
  }
}

// Define Zod schemas for our types
const KeyframeResponseSchema = z.object({
  keyframes: z.array(z.object({
    title: z.string(),
    description: z.string(),
    characters_in_scene: z.array(z.string())
  }))
});

const VisualStyleResponseSchema = z.object({
  style: z.enum([
    "RENDER_3D", "ACRYLIC", "ANIME_GENERAL", "CREATIVE", "DYNAMIC",
    "FASHION", "GAME_CONCEPT", "GRAPHIC_DESIGN_3D", "ILLUSTRATION",
    "NONE", "PORTRAIT", "PORTRAIT_CINEMATIC", "RAY_TRACED",
    "STOCK_PHOTO", "WATERCOLOR"
  ])
});

const CharactersSchema = z.object({
  characters: z.array(z.object({
    role: z.enum(["narrator", "child", "elder", "fairy", "hero", "villain", "sage", "sidekick"]),
    name: z.string(),
    backstory: z.string(),
    physical_description: z.string(),
    personality: z.string()
  }))
});

const KeyframesWithDialogSchema = z.object({
  scenes: z.array(z.object({
    title: z.string(),
    description: z.string(),
    characters_in_scene: z.array(z.string()),
    character: z.object({
      role: z.enum(["narrator", "child", "elder", "fairy", "hero", "villain", "sage", "sidekick"]),
      name: z.string(),
      backstory: z.string(),
      physical_description: z.string(),
      personality: z.string()
    }),
    dialog: z.string(),
    leonardo_prompt: z.string().optional()
  }))
});

const DialogResponseSchema = z.object({
  character: z.object({
    role: z.enum(["narrator", "child", "elder", "fairy", "hero", "villain", "sage", "sidekick"]),
    name: z.string(),
    backstory: z.string(),
    physical_description: z.string(),
    personality: z.string()
  }),
  text: z.string()
});

// Task definitions
export const generateScript = task("generate_script", async (keywords: string[]): Promise<string> => {
  console.log("Generating script with keywords:", keywords.join(", "));
  const prompt = SCRIPT_GENERATION_PROMPT.replace("{keywords}", keywords.join(", "));
  return await invokeChatCompletion(prompt) as string;
});

export const extractKeyframes = task("extract_keyframes", async (
  script: string,
  numKeyframes: number
): Promise<KeyframeResponse> => {
  console.log("Extracting keyframes from script");
  const prompt = KEYFRAME_EXTRACTION_PROMPT
    .replace("{script}", script)
    .replace("{num_keyframes}", numKeyframes.toString());
  
  return await invokeChatCompletion(prompt, { schema: KeyframeResponseSchema }) as KeyframeResponse;
});

export const determineVisualStyle = task("determine_visual_style", async (
  script: string
): Promise<LeonardoStyle> => {
  console.log("Determining visual style for the script");
  const prompt = VISUAL_STYLE_PROMPT.replace("{script}", script);
  const response = await invokeChatCompletion(prompt, { schema: VisualStyleResponseSchema }) as VisualStyleResponse;
  return response.style;
});

export const generateVoiceover = task("generate_voiceover", async (
  scene: KeyframeScene
): Promise<ArrayBuffer> => {
  console.log(`Generating voiceover for ${scene.character.name} (${scene.character.role}): ${scene.dialog.slice(0, 50)}...`);
  return await generateSpeechFromText(scene.dialog, scene.character.role);
});

export const extractCharacters = task("extract_characters", async (
  script: string
): Promise<Character[]> => {
  console.log("Extracting characters from script");
  const prompt = CHARACTER_EXTRACTION_PROMPT.replace("{script}", script);
  const response = await invokeChatCompletion(prompt, { schema: CharactersSchema }) as Characters;
  return response.characters;
});

export const enhanceScript = task("enhance_script", async (
  script: string,
  characters: Character[],
  numKeyframes: number
): Promise<string> => {
  console.log("Enhancing script with character details");
  
  const charInfo = characters.map(char => 
    `Character: ${char.name} (${char.role})\n` +
    `Backstory: ${char.backstory}\n` +
    `Personality: ${char.personality}`
  ).join("\n\n");
  
  const totalWords = numKeyframes * WORDS_PER_KEYFRAME;
  
  const prompt = SCRIPT_ENHANCEMENT_PROMPT
    .replace("{script}", script)
    .replace("{characters}", charInfo)
    .replace("{total_words}", totalWords.toString());
  
  return await invokeChatCompletion(prompt) as string;
});

export const optimizeLeonardoPrompts = task("optimize_leonardo_prompts", async (
  keyframes: Array<{
    description: string;
    characters_in_scene: string[];
    title: string;
  }>,
  visualStyle: LeonardoStyle,
  outputDir: string
): Promise<string[]> => {
  console.log("Optimizing all scenes for Leonardo prompts");

  const sceneDescriptions = keyframes.map((kf, idx) => 
    `Scene ${idx + 1}:\n` +
    `Title: ${kf.title}\n` +
    `Description: ${kf.description}\n` +
    `Characters Present: ${kf.characters_in_scene.length ? kf.characters_in_scene.join(", ") : "None"}`
  ).join("\n\n");

  const prompt = LEONARDO_PROMPT_OPTIMIZATION
    .replace("{keyframe_descriptions}", sceneDescriptions)
    .replace("{visual_style}", visualStyle);

  const response = await invokeChatCompletion(prompt) as string;
  
  // Parse the numbered responses
  const optimizedPrompts: string[] = [];
  let currentPrompt: string[] = [];
  let currentNumber = 1;

  for (const line of response.split('\n')) {
    const trimmedLine = line.trim();
    if (!trimmedLine) continue;

    if (trimmedLine.startsWith(`${currentNumber}:`)) {
      if (currentPrompt.length) {
        optimizedPrompts.push(currentPrompt.join('\n'));
        currentPrompt = [];
      }
      currentPrompt.push(trimmedLine.slice(String(currentNumber).length + 1).trim());
      currentNumber++;
    } else {
      currentPrompt.push(trimmedLine);
    }
  }

  if (currentPrompt.length) {
    optimizedPrompts.push(currentPrompt.join('\n'));
  }

  // Save prompts to files
  const outputPath = path.join(outputDir);
  await fs.mkdir(outputPath, { recursive: true });

  await Promise.all(optimizedPrompts.map(async (promptText, idx) => {
    const promptFile = path.join(outputPath, `scene_prompt_${idx + 1}.txt`);
    await fs.writeFile(promptFile, promptText);
  }));

  return optimizedPrompts;
});

export const generateKeyframeScenes = task("generate_keyframe_scenes", async (
  keyframe: Keyframe,
  characters: Character[],
  previouslySeenCharacters: Set<string>
): Promise<KeyframesWithDialog> => {
  console.log(`Generating scenes for keyframe: ${keyframe.title}`);

  const characterProfiles = characters.map(char =>
    `Character: ${char.name} (${char.role})\n` +
    `Personality: ${char.personality}\n` +
    `Physical Description: ${char.physical_description}\n` +
    "---"
  ).join("\n");

  const prompt = KEYFRAME_SCENE_GENERATION_PROMPT
    .replace("{title}", keyframe.title)
    .replace("{description}", keyframe.description)
    .replace("{characters_in_scene}", keyframe.characters_in_scene.join(", "))
    .replace("{character_profiles}", characterProfiles);

  const scenes = await invokeChatCompletion(prompt, { schema: KeyframesWithDialogSchema }) as KeyframesWithDialog;

  // Update previously seen characters
  scenes.scenes.forEach(scene => {
    scene.characters_in_scene.forEach(charName => {
      previouslySeenCharacters.add(charName);
    });
  });

  return scenes;
});

// This function will be used in future implementations
export const extractDialog = task("extract_dialog", async (
  script: string,
  keyframeDescription: string,
  characters: Character[]
): Promise<DialogResponse> => {
  console.log("Extracting dialog for keyframe:", keyframeDescription.slice(0, 100) + "...");
  
  const narrator: Character = {
    role: Role.NARRATOR,
    name: "Narrator",
    backstory: "An omniscient storyteller who guides the audience through the narrative.",
    physical_description: "A disembodied voice with gravitas and warmth.",
    personality: "Wise, neutral, and observant, with a clear and engaging speaking style."
  };

  const prompt = DIALOG_EXTRACTION_PROMPT
    .replace("{keyframe_description}", keyframeDescription)
    .replace("{script}", script)
    .replace("{characters}", characters.map(char => 
      `- ${char.name} (${char.role}): ${char.personality}`
    ).join("\n"));

  const dialog = await invokeChatCompletion(prompt, { schema: DialogResponseSchema }) as DialogResponse;
  
  // If narrator is chosen, use our narrator character
  if (dialog.character.role === Role.NARRATOR) {
    dialog.character = narrator;
  }

  return dialog;
});

// Main entrypoint
export interface StoryInput {
  keywords: string[];
}

export interface StoryConfig {
  extract_chars?: boolean;
  generate_voiceover?: boolean;
  generate_images?: boolean;
  save_script?: boolean;
  num_keyframes?: number;
  output_dir?: string;
}

export type StoryResult = [
  Array<[string, KeyframeScene[], LeonardoStyle, ArrayBuffer | null]>,
  Character[] | null,
  [string, string] | null
];

export const generateStory = entrypoint(
  { checkpointer: new MemorySaver(), name: "generate_story" },
  async (
    inputs: StoryInput,
    config?: LangGraphRunnableConfig & { configurable?: StoryConfig }
  ): Promise<StoryResult> => {
    console.log("Starting story generation process");
    const startTime = Date.now();

    const keywords = inputs.keywords;
    console.log("Processing keywords:", keywords.join(", "));

    // Get config options
    const storyConfig = config?.configurable ?? {};
    const extractChars = storyConfig.extract_chars ?? false;
    const shouldGenerateVoiceover = storyConfig.generate_voiceover ?? false;
    const shouldGenerateImages = storyConfig.generate_images ?? false;
    const saveScript = storyConfig.save_script ?? false;
    const numKeyframes = storyConfig.num_keyframes ?? 4;
    const outputDir = storyConfig.output_dir ?? "output";

    // Create output directory
    await fs.mkdir(outputDir, { recursive: true });

    // Generate initial script
    const script = await generateScript(keywords);
    const characters = await extractCharacters(script);
    const enhancedScript = await enhanceScript(script, characters, numKeyframes);

    // Extract keyframes and determine visual style in parallel
    const [keyframeResponse, visualStyle] = await Promise.all([
      extractKeyframes(enhancedScript, numKeyframes),
      determineVisualStyle(enhancedScript)
    ]);

    const keyframes = keyframeResponse.keyframes;
    const previouslySeenCharacters = new Set<string>();

    // Generate scenes for each keyframe
    const allScenes = await Promise.all(
      keyframes.map((kf: Keyframe) => generateKeyframeScenes(kf, characters, previouslySeenCharacters))
    );

    // Handle image generation if enabled
    if (shouldGenerateImages) {
      const sceneDescriptions = allScenes.flatMap((keyframeScenes: KeyframesWithDialog) =>
        keyframeScenes.scenes.map((scene: KeyframeScene) => ({
          description: scene.description,
          characters_in_scene: scene.characters_in_scene,
          title: scene.title
        }))
      );

      const optimizedPrompts = await optimizeLeonardoPrompts(
        sceneDescriptions,
        visualStyle,
        outputDir
      );

      // Update scene descriptions with optimized prompts
      let promptIdx = 0;
      for (const keyframeScenes of allScenes) {
        for (const scene of keyframeScenes.scenes) {
          scene.leonardo_prompt = optimizedPrompts[promptIdx++];
        }
      }
    }

    // Generate voiceovers if requested
    let voiceovers: (ArrayBuffer | null)[] = [];
    if (shouldGenerateVoiceover) {
      const voiceoverTasks = allScenes.flatMap((keyframeScenes: KeyframesWithDialog) =>
        keyframeScenes.scenes.map((scene: KeyframeScene) => generateVoiceover(scene))
      );
      const allVoiceovers = await Promise.all(voiceoverTasks);
      
      // Group voiceovers back by keyframe (2 scenes per keyframe)
      voiceovers = Array.from({ length: allScenes.length }, (_, i) => {
        const keyframeVoiceovers = allVoiceovers.slice(i * 2, (i + 1) * 2);
        return keyframeVoiceovers.length > 0 ? keyframeVoiceovers[0] : null;
      });
    } else {
      voiceovers = Array(allScenes.length).fill(null);
    }

    // Combine results
    const storyResults: StoryResult[0] = allScenes.map((scenes: KeyframesWithDialog, idx: number) => [
      scenes.scenes[0].description,
      scenes.scenes,
      visualStyle,
      voiceovers[idx]
    ]);

    const totalTime = (Date.now() - startTime) / 1000;
    console.log(`Story generation completed in ${totalTime.toFixed(2)} seconds`);

    return [
      storyResults,
      extractChars ? characters : null,
      saveScript ? [script, enhancedScript] : null
    ];
  }
); 