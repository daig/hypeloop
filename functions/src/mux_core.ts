import Mux from "@mux/mux-node";
import {muxTokenId, muxTokenSecret} from './config.js';

// Initialize Mux client (lazy loading)
let client: Mux;

function getMuxClient(): Mux {
  if (!client) {
    client = new Mux({
      tokenId: muxTokenId.value(),
      tokenSecret: muxTokenSecret.value()
    });
  }
  return client;
}

/**
 * Upload audio buffer to Mux
 * @param audioBuffer - The audio buffer to upload
 * @param metadata - Optional metadata for the upload
 * @returns The Mux upload ID and URL
 */
export async function uploadAudioToMux(
  audioBuffer: ArrayBuffer,
  metadata?: {
    filename?: string;
    description?: string;
  }
): Promise<{uploadId: string; url: string}> {
  const muxClient = getMuxClient();
  
  // Create a direct upload URL
  const upload = await muxClient.video.uploads.create({
    new_asset_settings: {
      playback_policy: ["public"]
    },
    cors_origin: "*", // TODO: Update with your domain in production
    timeout: 3600 // 1 hour to complete the upload
  });

  // Convert ArrayBuffer to Buffer for upload
  const buffer = Buffer.from(audioBuffer);

  // Upload the audio file
  const response = await fetch(upload.url, {
    method: 'PUT',
    body: buffer,
    headers: {
      'Content-Type': 'audio/mp3'
    }
  });

  if (!response.ok) {
    throw new Error(`Failed to upload audio to Mux: ${response.statusText}`);
  }

  return {
    uploadId: upload.id,
    url: upload.url
  };
} 