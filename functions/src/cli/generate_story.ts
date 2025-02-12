#!/usr/bin/env node

import {program} from 'commander';
import * as path from 'path';
import * as fs from 'fs/promises';
import * as dotenv from 'dotenv';
import {LeonardoAPI} from '../leonardo_api';
import {generateStory} from '../story_generator';
import type {StoryInput} from '../story_generator';
import {generateSpeechFromText} from '../tts_core';
import type {Character, KeyframeScene} from '../schemas';
import {spawn} from 'child_process';
import {createLogger, format, transports} from 'winston';

// Add global error handlers for unhandled rejections and exceptions
process.on('unhandledRejection', (reason, promise) => {
  console.error('Unhandled Rejection at:', promise, 'reason:', reason);
  process.exit(1);
});

process.on('uncaughtException', (error) => {
  console.error('Uncaught Exception:', error);
  process.exit(1);
});

// Setup logger with better error formatting
const logger = createLogger({
  level: 'info',
  format: format.combine(
    format.timestamp(),
    format.errors({stack: true}),
    format.json()
  ),
  transports: [
    new transports.Console({
      format: format.combine(
        format.colorize(),
        format.simple(),
        format.errors({stack: true})
      )
    })
  ]
});

// Type for story tuple
type StoryTuple = [string, KeyframeScene[], string, ArrayBuffer | null];
type StoryResult = [StoryTuple[], Character[] | null, [string, string] | null];

async function generateImageForKeyframe(
  leonardoClient: LeonardoAPI,
  keyframeDesc: string,
  visualStyle: string,
  outputDir: string,
  keyframeNum: number | string,
  maxRetries: number = 2
): Promise<[string | null, string | null, string | null]> {
  async function attemptGeneration(prompt: string, attempt: number = 1): Promise<[string | null, string | null, string | null]> {
    try {
      const generationResult = await leonardoClient.generateImageForKeyframe(prompt, visualStyle as any);
      
      if (!generationResult) {
        logger.error(`Failed to generate image for keyframe ${keyframeNum} (attempt ${attempt})`);
        return [null, null, null];
      }

      const [generationId] = generationResult;
      const startTime = Date.now();
      const maxPollTime = 300000; // 5 minutes in milliseconds

      while (true) {
        if (Date.now() - startTime > maxPollTime) {
          logger.error(`Image generation timed out after ${maxPollTime / 1000} seconds for keyframe ${keyframeNum} (attempt ${attempt})`);
          return [null, null, null];
        }

        const pollResult = await leonardoClient.pollGenerationStatus(generationId);
        
        if (pollResult) {
          const [generationData, imageId] = pollResult;
          if (generationData.generations_by_pk?.status === "COMPLETE") {
            const generatedImages = generationData.generations_by_pk.generated_images;
            if (generatedImages?.length && 'url' in generatedImages[0]) {
              const imageUrl = generatedImages[0].url;
              if (imageUrl) {
                const imageFilename = `keyframe_${keyframeNum}.jpg`;
                const imagePath = path.join(outputDir, imageFilename);

                const response = await fetch(imageUrl as string);
                if (response.ok) {
                  const buffer = await response.arrayBuffer();
                  await fs.writeFile(imagePath, Buffer.from(buffer));
                  logger.info(`Saved image for keyframe ${keyframeNum} to ${imagePath} (attempt ${attempt})`);
                  return [imagePath, generationId, imageId];
                } else {
                  logger.error(`Failed to download image for keyframe ${keyframeNum}: ${response.status} (attempt ${attempt})`);
                }
              }
            }
          } else if (generationData.generations_by_pk?.status === "FAILED" || generationData.generations_by_pk?.status === "DELETED") {
            logger.error(`Generation failed for keyframe ${keyframeNum} with status: ${generationData.generations_by_pk.status} (attempt ${attempt})`);
            break;
          }
        } else {
          logger.error(`Poll failed for keyframe ${keyframeNum} (attempt ${attempt})`);
          break;
        }

        await new Promise(resolve => setTimeout(resolve, 2000));
      }
    } catch (error) {
      logger.error(`Error generating image for keyframe ${keyframeNum}: ${error} (attempt ${attempt})`);
    }

    return [null, null, null];
  }

  // First attempt with original prompt
  let result = await attemptGeneration(keyframeDesc, 1);
  if (result[0]) return result;

  // Retry with modified prompts
  for (let retry = 2; retry <= maxRetries; retry++) {
    const modifiedPrompt = `${keyframeDesc} Detailed high quality illustration, perfect composition, professional photography, 8k resolution.`;
    logger.info(`Retrying image generation for keyframe ${keyframeNum} with modified prompt (attempt ${retry})`);
    result = await attemptGeneration(modifiedPrompt, retry);
    if (result[0]) return result;
  }

  logger.error(`All ${maxRetries} attempts to generate image for keyframe ${keyframeNum} failed`);
  return [null, null, null];
}

async function generateMotionForImage(
  leonardoClient: LeonardoAPI,
  imageId: string,
  outputDir: string,
  keyframeNum: number | string,
  imagePath: string
): Promise<void> {
  try {
    const motionGenerationId = await leonardoClient.generateMotion(imageId);

    if (!motionGenerationId) {
      logger.error(`Failed to start motion generation for keyframe ${keyframeNum}, falling back to static video`);
      await generateStaticVideoFromImage(imagePath, outputDir, keyframeNum);
      return;
    }

    const startTime = Date.now();
    const maxPollTime = 300000; // 5 minutes in milliseconds

    while (true) {
      if (Date.now() - startTime > maxPollTime) {
        logger.error(`Motion generation timed out after ${maxPollTime / 1000} seconds for keyframe ${keyframeNum}, falling back to static video`);
        await generateStaticVideoFromImage(imagePath, outputDir, keyframeNum);
        return;
      }

      const motionResult = await leonardoClient.pollMotionStatus(motionGenerationId);

      if (motionResult) {
        const videoUrl = motionResult.url;
        if (videoUrl) {
          logger.info(`Got video URL for keyframe ${keyframeNum}: ${videoUrl}`);
          const videoPath = path.join(outputDir, `keyframe_${keyframeNum}.mp4`);

          try {
            const response = await fetch(videoUrl);
            if (response.ok) {
              const buffer = await response.arrayBuffer();
              await fs.writeFile(videoPath, Buffer.from(buffer));
              logger.info(`Saved motion video for keyframe ${keyframeNum} to ${videoPath}`);
              return;
            } else {
              logger.error(`Failed to download motion video for keyframe ${keyframeNum}: ${response.status}, falling back to static video`);
              await generateStaticVideoFromImage(imagePath, outputDir, keyframeNum);
              return;
            }
          } catch (error) {
            logger.error(`Error downloading motion video for keyframe ${keyframeNum}: ${error}, falling back to static video`);
            await generateStaticVideoFromImage(imagePath, outputDir, keyframeNum);
            return;
          }
        }
      }

      await new Promise(resolve => setTimeout(resolve, 2000));
    }
  } catch (error) {
    logger.error(`Error generating motion for keyframe ${keyframeNum}: ${error}, falling back to static video`);
    await generateStaticVideoFromImage(imagePath, outputDir, keyframeNum);
  }
}

async function generateStaticVideoFromImage(
  imagePath: string,
  outputDir: string,
  keyframeNum: number | string
): Promise<void> {
  try {
    const videoPath = path.join(outputDir, `keyframe_${keyframeNum}.mp4`);

    // FFmpeg command to create static video
    const ffmpegArgs = [
      '-y',
      '-loop', '1',
      '-i', imagePath,
      '-c:v', 'libx264',
      '-t', '5',
      '-vf', 'scale=512:512:force_original_aspect_ratio=decrease,pad=512:512:(ow-iw)/2:(oh-ih)/2',
      '-r', '24',
      '-pix_fmt', 'yuv420p',
      videoPath
    ];

    return new Promise((resolve, reject) => {
      const ffmpeg = spawn('ffmpeg', ffmpegArgs);

      ffmpeg.stderr.on('data', (data) => {
        logger.debug(`ffmpeg: ${data}`);
      });

      ffmpeg.on('close', (code) => {
        if (code === 0) {
          logger.info(`Generated static video for keyframe ${keyframeNum} at ${videoPath}`);
          resolve();
        } else {
          logger.error(`Failed to generate static video for keyframe ${keyframeNum} with code ${code}`);
          reject(new Error(`FFmpeg exited with code ${code}`));
        }
      });

      ffmpeg.on('error', (err) => {
        logger.error(`Error generating static video for keyframe ${keyframeNum}: ${err}`);
        reject(err);
      });
    });
  } catch (error) {
    logger.error(`Error generating static video for keyframe ${keyframeNum}: ${error}`);
    throw error;
  }
}

async function processKeyframe(
  leonardoClient: LeonardoAPI | null,
  desc: string,
  scenes: KeyframeScene[],
  audioData: ArrayBuffer[] | null,
  visualStyle: string,
  keyframeNum: number,
  outputDir: string,
  imagesDir: string | null,
  generateVideo: boolean,
  useMotion: boolean
): Promise<void> {
  try {
    // Write overall keyframe description
    const keyframeFile = path.join(outputDir, `keyframe_${keyframeNum}.txt`);
    await fs.writeFile(keyframeFile, desc);
    logger.info(`Wrote keyframe ${keyframeNum} to ${keyframeFile}`);

    // Write individual scene descriptions and dialog
    for (let sceneIdx = 1; sceneIdx <= scenes.length; sceneIdx++) {
      const scene = scenes[sceneIdx - 1];

      // Write scene description
      const sceneFile = path.join(outputDir, `scene_${keyframeNum}_${sceneIdx}.txt`);
      const sceneContent = [
        `Title: ${scene.title}`,
        `Description: ${scene.description}`,
        `Characters in scene: ${scene.characters_in_scene.join(', ')}`
      ].join('\n');
      await fs.writeFile(sceneFile, sceneContent);
      logger.info(`Wrote scene ${keyframeNum}.${sceneIdx} to ${sceneFile}`);

      // Write dialog
      const dialogPath = path.join(outputDir, `dialog_${keyframeNum}_${sceneIdx}.json`);
      const dialogDict = {
        character: scene.character,
        dialog: scene.dialog
      };
      await fs.writeFile(dialogPath, JSON.stringify(dialogDict, null, 2));
      logger.info(`Wrote dialog ${keyframeNum}.${sceneIdx} to ${dialogPath}`);
    }

    // Write voiceover if generated
    if (audioData) {
      for (let sceneIdx = 1; sceneIdx <= audioData.length; sceneIdx++) {
        const sceneAudio = audioData[sceneIdx - 1];
        if (sceneAudio) {
          const voiceoverPath = path.join(outputDir, `voiceover_${keyframeNum}_${sceneIdx}.mp3`);
          await fs.writeFile(voiceoverPath, Buffer.from(sceneAudio));
          logger.info(`Wrote voiceover ${keyframeNum}.${sceneIdx} to ${voiceoverPath}`);
        }
      }
    }

    // Only attempt image/video generation if we have a leonardo client and images directory
    if (leonardoClient && imagesDir) {
      // Generate images for all scenes in parallel
      const imageTasks = scenes.map((scene, idx) => {
        const prompt = scene.leonardo_prompt || scene.description;
        console.log(`\nStarting image generation for scene ${keyframeNum}.${idx + 1}...`);
        return generateImageForKeyframe(
          leonardoClient,
          prompt,
          visualStyle,
          imagesDir,
          `${keyframeNum}_${idx + 1}`,
          2
        );
      });

      const imageResults = await Promise.all(imageTasks);

      // Generate videos in parallel if requested
      if (generateVideo) {
        const videoTasks = imageResults.map((result, idx) => {
          const [imagePath, , imageId] = result;
          if (imagePath && imageId) {
            if (useMotion) {
              console.log(`\nStarting motion generation for scene ${keyframeNum}.${idx + 1}...`);
              return generateMotionForImage(
                leonardoClient,
                imageId,
                imagesDir,
                `${keyframeNum}_${idx + 1}`,
                imagePath
              );
            } else {
              console.log(`\nGenerating static video for scene ${keyframeNum}.${idx + 1}...`);
              return generateStaticVideoFromImage(
                imagePath,
                imagesDir,
                `${keyframeNum}_${idx + 1}`
              );
            }
          }
          return Promise.resolve();
        });

        await Promise.all(videoTasks);
      }
    }

    // Print feedback
    console.log(`Keyframe ${keyframeNum} Description:\n${desc}\n`);
    scenes.forEach((scene, idx) => {
      console.log(`Keyframe ${keyframeNum}.${idx + 1} Dialog/Narration:\n${scene.dialog}\n`);
    });
    if (audioData) {
      console.log(`Voiceovers saved to: ${outputDir}/voiceover_${keyframeNum}_*.mp3\n`);
    }
    console.log("=".repeat(80));

  } catch (error) {
    logger.error(`Error processing keyframe ${keyframeNum}: ${error}`);
    throw error;
  }
}

async function main() {
  try {
    program
      .name('generate-story')
      .description('Generate a story based on theme keywords')
      .argument('<keywords...>', 'Theme keywords for the story (e.g., "adventure" "mystical forest")')
      .option('--thread-id <id>', 'Thread ID for the story generation', 'default_thread')
      .option('--debug', 'Enable debug logging')
      .option('--output-dir <dir>', 'Directory to save the generated files', 'output')
      .option('--images <dir>', 'Generate images for keyframes and save to specified directory')
      .option('--motion', 'Generate motion video for the first keyframe image')
      .option('--static-vid', 'Generate static videos (5 seconds) from keyframe images')
      .option('--characters', 'Extract and save character profiles to characters.json')
      .option('--voiceover', 'Generate voiceover audio for each keyframe')
      .option('--script', 'Save the full story script to script.txt')
      .option('--keyframes <number>', 'Number of keyframes to generate', '4')
      .parse();

    const options = program.opts();
    const keywords = program.args;

    // Set debug logging if flag is provided
    if (options.debug) {
      logger.level = 'debug';
      logger.debug('Debug logging enabled');
    }

    // Create output directory
    const outputDir = path.resolve(options.outputDir);
    await fs.mkdir(outputDir, {recursive: true});
    logger.info(`Writing output to directory: ${outputDir}`);

    // Initialize Leonardo API if needed
    let leonardoClient: LeonardoAPI | null = null;
    let imageDir: string | null = null;

    if (options.images) {
      const envPath = path.join(__dirname, '../../../.env');
      dotenv.config({path: envPath});

      const leonardoApiKey = process.env.LEONARDO_API_KEY;
      if (!leonardoApiKey) {
        throw new Error('LEONARDO_API_KEY not found in environment variables');
      }

      leonardoClient = new LeonardoAPI(leonardoApiKey);
      imageDir = path.resolve(options.images);
      await fs.mkdir(imageDir, {recursive: true});
      logger.info(`Will generate images in directory: ${imageDir}`);
    }

    logger.info(`Starting story generation with thread ID: ${options.threadId}`);

    const config = {
      configurable: {
        extract_chars: options.characters,
        generate_voiceover: options.voiceover,
        generate_images: Boolean(options.images),
        save_script: options.script,
        num_keyframes: parseInt(options.keyframes),
        output_dir: outputDir,
        thread_id: options.threadId
      }
    };

    logger.debug('Config values:', config.configurable);

    const storyInput: StoryInput = {keywords};
    const storyResult = await generateStory.invoke(storyInput, config) as StoryResult;

    if (!storyResult) {
      throw new Error('Story generation failed');
    }

    const [story, characters, scripts] = storyResult;

    console.log('\nGenerating story with keywords:', keywords.join(', '));
    console.log('='.repeat(80) + '\n');

    if (!story || !story.length) {
      throw new Error('No story content generated');
    }

    // Write metadata
    const visualStyle = story[0][2];
    const metadataFile = path.join(outputDir, 'metadata.json');
    await fs.writeFile(
      metadataFile,
      JSON.stringify({visual_style: visualStyle}, null, 2)
    );
    logger.info(`Wrote metadata to ${metadataFile}`);
    console.log(`\nSelected Visual Style: ${visualStyle}\n`);
    console.log('='.repeat(80) + '\n');

    // Write character profiles if requested
    if (options.characters && characters) {
      const charactersFile = path.join(outputDir, 'characters.json');
      await fs.writeFile(
        charactersFile,
        JSON.stringify({characters}, null, 2)
      );
      logger.info(`Wrote character profiles to ${charactersFile}`);
      console.log('\nGenerated Character Profiles:');
      characters.forEach((char: Character) => {
        console.log(`- ${char.name} (${char.role})`);
      });
      console.log('='.repeat(80) + '\n');
    }

    // Write full script if requested
    if (options.script && scripts) {
      const [originalScript, enhancedScript] = scripts;
      const scriptFile = path.join(outputDir, 'script.txt');
      const scriptContent = [
        '# Original Story Script\n',
        originalScript,
        '\n' + '='.repeat(80) + '\n',
        '# Enhanced Story Script',
        '(Incorporating character details and backgrounds)\n',
        enhancedScript,
        '\n' + '='.repeat(80) + '\n',
        '# Scene Breakdown\n',
        ...story.map((storyPart: [string, KeyframeScene[], string, ArrayBuffer | null], idx: number) => {
          const [desc, scenes] = storyPart;
          return [
            `Scene ${idx + 1}:`,
            `Description: ${desc}`,
            ...scenes.map((scene: KeyframeScene, sceneIdx: number) => [
              `Scene ${idx + 1}.${sceneIdx + 1}:`,
              `Dialog: ${scene.dialog}`,
              `Spoken by: ${scene.character.name} (${scene.character.role})\n`
            ].join('\n'))
          ].join('\n');
        })
      ].join('\n');

      await fs.writeFile(scriptFile, scriptContent);
      logger.info(`Wrote full script to ${scriptFile}`);
      console.log('\nFull script (original and enhanced versions) saved to:', scriptFile);
      console.log('='.repeat(80) + '\n');
    }

    // Generate voiceovers if requested
    let voiceovers: ArrayBuffer[][] = [];
    if (options.voiceover) {
      logger.info('Launching parallel voiceover generation for all scenes');
      const voiceoverTasks = story.flatMap(([, scenes]: [string, KeyframeScene[], string, ArrayBuffer | null]) =>
        scenes.map((scene: KeyframeScene) =>
          generateSpeechFromText(scene.dialog, scene.character.role)
        )
      );

      const voiceoverResults = await Promise.all(voiceoverTasks);

      // Group voiceovers back by keyframe
      let i = 0;
      for (const [, scenes] of story as Array<[string, KeyframeScene[], string, ArrayBuffer | null]>) {
        const numScenes = scenes.length;
        voiceovers.push(voiceoverResults.slice(i, i + numScenes));
        i += numScenes;
      }
    }

    // Process all keyframes in parallel
    const tasks = story.map(([desc, scenes, style]: [string, KeyframeScene[], string, ArrayBuffer | null], idx: number) =>
      processKeyframe(
        leonardoClient,
        desc,
        scenes,
        voiceovers[idx] || null,
        visualStyle,
        idx + 1,
        outputDir,
        imageDir,
        options.motion || options.staticVid,
        options.motion
      )
    );

    await Promise.all(tasks);
  } catch (error) {
    logger.error('Error in story generation:', error);
    if (error instanceof Error) {
      logger.error(error.stack);
    }
    process.exit(1);
  }
}

// Use a proper async main wrapper with error handling
const runMain = async () => {
  try {
    await main();
  } catch (error) {
    logger.error('Fatal error:', error);
    if (error instanceof Error) {
      logger.error(error.stack);
    }
    process.exit(1);
  }
};

runMain(); 