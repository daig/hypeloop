import {OpenAI} from 'openai';
import {Role} from './schemas.js';
import {openAiKey} from './config.js';

// OpenAI's supported voice types
type OpenAIVoice = 'alloy' | 'ash' | 'coral' | 'echo' | 'fable' | 'onyx' | 'nova' | 'sage' | 'shimmer';

// Type for the character voice mapping
type CharacterVoices = {
  [key in Role]: OpenAIVoice;
};

const characterVoices: CharacterVoices = {
  narrator: 'fable',  // Warm, engaging narrator voice
  child: 'nova',      // Youthful, bright voice
  elder: 'onyx',      // Deep, authoritative voice
  fairy: 'shimmer',   // Light, whimsical voice
  hero: 'alloy',      // Balanced, confident voice
  villain: 'ash',     // Dramatic, resonant voice
  sage: 'sage',
  sidekick: 'coral'
};

/**
 * Maps character types to appropriate voices
 * @param character - The character role
 * @returns The corresponding voice ID
 */
export function getVoiceForCharacter(character: Role): OpenAIVoice {
  return characterVoices[character] || 'fable';  // Default to fable if character not found
}

type TTSModel = 'tts-1' | 'tts-1-hd';

// Initialize OpenAI client (lazy loading)
let client: OpenAI;

function getOpenAIClient(): OpenAI {
  if (!client) {
    client = new OpenAI({
      apiKey: openAiKey.value()
    });
  }
  return client;
}

/**
 * Generate speech from text using OpenAI's TTS API
 * @param text - The text to convert to speech
 * @param character - The character role (defaults to narrator)
 * @param model - The TTS model to use
 * @returns Promise containing the audio response as an ArrayBuffer
 */
export async function generateSpeechFromText(
  text: string,
  character: Role = 'narrator',
  model: TTSModel = 'tts-1'
): Promise<ArrayBuffer> {
  try {
    const voice = getVoiceForCharacter(character);

    // Generate speech
    const response = await getOpenAIClient().audio.speech.create({
      model,
      voice,
      input: text,
      response_format: 'mp3'
    });

    // Convert the response to ArrayBuffer
    const arrayBuffer = await response.arrayBuffer();
    return arrayBuffer;
  } catch (error) {
    console.error('Error generating speech:', error);
    throw error;
  }
} 