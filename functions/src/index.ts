/**
 * Import function triggers from their respective submodules:
 *
 * import {onCall} from "firebase-functions/v2/https";
 * import {onDocumentWritten} from "firebase-functions/v2/firestore";
 *
 * See a full list of supported triggers at https://firebase.google.com/docs/functions
 */

import {onCall, onRequest, HttpsError} from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import Mux from "@mux/mux-node";
import crypto from "crypto";
import { initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { createCanvas, CanvasRenderingContext2D } from 'canvas';
import GIFEncoder from 'gifencoder';
import { generateStory } from './story_generator.js';
import type { StoryInput, StoryConfig } from './story_generator.js';
import {
  muxTokenId,
  muxTokenSecret,
  muxWebhookSecret,
  leonardoApiKey,
  leonardoWebhookSecret
} from './config.js';
import { LeonardoAPI } from './leonardo_api.js';
import type { LeonardoStyle } from './schemas.js';

// Initialize Firebase Admin
initializeApp();

// Initialize Firestore
const db = getFirestore();

interface UploadRequest {
  filename: string;
  fileSize: number;
  contentType: string;
  description: string;
}

// Function to get Mux client (initialized at runtime)
function getMuxClient(): Mux {
  return new Mux({
    tokenId: muxTokenId.value(),
    tokenSecret: muxTokenSecret.value()
  });
}

// Function to generate a presigned URL for direct uploads to Mux
export const getVideoUploadUrl = onCall({
    maxInstances: 1,
    enforceAppCheck: false,  // You can enable this later for additional security
    region: 'us-central1'
}, async (request) => {
    logger.info("Starting getVideoUploadUrl function", {data: request.data});

    try {
        if (!request.auth) {
            throw new HttpsError(
                "unauthenticated",
                "The function must be called while authenticated."
            );
        }

        // Validate request data
        const data = request.data as UploadRequest;
        if (!data.filename || !data.fileSize || !data.contentType || !data.description) {
            throw new HttpsError(
                "invalid-argument",
                "Required fields: filename, fileSize, contentType, and description"
            );
        }

        // Validate file type
        if (!data.contentType.startsWith("video/")) {
            throw new HttpsError(
                "invalid-argument",
                "Only video files are allowed"
            );
        }

        // Initialize Mux client with credentials at runtime
        const muxClient = getMuxClient();

        logger.info("Creating direct upload URL", {
            filename: data.filename,
            fileSize: data.fileSize,
            contentType: data.contentType,
            description: data.description,
        });

        // Create a direct upload URL
        const upload = await muxClient.video.uploads.create({
            new_asset_settings: {
                playback_policy: ["public"],
                mp4_support: "capped-1080p"
            },
            cors_origin: "*", // For testing. In production, specify your domain
            timeout: 3600, // 1 hour to complete the upload
        });

        logger.info("Upload URL created successfully", {
            uploadId: upload.id,
            filename: data.filename
        });

        // Return the upload URL and ID
        return {
            uploadUrl: upload.url,
            uploadId: upload.id,
            filename: data.filename,
            contentType: data.contentType,
            fileSize: data.fileSize,
        };
    } catch (error) {
        logger.error("Error generating upload URL:", error);
        const msg = error instanceof Error ? error.message : "Unknown error";
        throw new HttpsError("internal", `Failed to generate upload URL: ${msg}`);
    }
});

// Webhook endpoint to handle Mux notifications
export const muxWebhook = onRequest(
    {
        cors: false,
        maxInstances: 100,
        invoker: 'public'
    },
    async (req, res) => {
    try {
        // Verify webhook signature
        const signatureHeader = req.headers['mux-signature'] as string;
        logger.info("Received signature:", { signatureHeader });

        if (!signatureHeader) {
            logger.error("No Mux signature found in webhook request");
            res.status(401).json({ error: 'No signature provided' });
            return;
        }

        // Parse the signature header
        const [timestamp, signature] = signatureHeader.split(',').reduce((acc, curr) => {
            const [key, value] = curr.split('=');
            if (key === 't') acc[0] = value;
            if (key === 'v1') acc[1] = value;
            return acc;
        }, ['', '']);

        if (!timestamp || !signature) {
            logger.error("Invalid signature format");
            res.status(401).json({ error: 'Invalid signature format' });
            return;
        }

        // Get the raw body as a string
        const rawBody = JSON.stringify(req.body);
        
        // Create HMAC using webhook secret
        const secret = muxWebhookSecret.value();
        logger.info("Secret check", { 
            prefix: secret.substring(0, 3),
            length: secret.length 
        });
        const signatureData = `${timestamp}.${rawBody}`;
        logger.info("Data to sign:", { timestamp, bodyLength: rawBody.length });

        const hmac = crypto.createHmac('sha256', secret);
        hmac.update(signatureData);
        const digest = hmac.digest('hex');
        logger.info("Calculated digest:", { digest });

        if (signature !== digest) {
            logger.error("Invalid Mux webhook signature", { 
                received: signature,
                calculated: digest
            });
            res.status(401).json({ error: 'Invalid signature' });
            return;
        }

        const event = req.body;
        logger.info("Received Mux webhook", { type: event.type, data: event.data });

        // Handle asset.ready event
        if (event.type === 'video.asset.ready') {
            const assetId = event.data.id;
            const playbackId = event.data.playback_ids?.[0]?.id;
            const uploadId = event.data.upload_id;

            // Check if this is a video or audio asset
            // More precise check: if it has video tracks, it's a video asset. If it only has audio tracks, it's an audio asset.
            const hasVideoTracks = event.data.tracks?.some((track: any) => track.type === 'video');
            const hasAudioTracks = event.data.tracks?.some((track: any) => track.type === 'audio');
            const isAudioOnly = !hasVideoTracks && hasAudioTracks;

            if (isAudioOnly) {
                // Get the input info to extract the download URL
                const muxClient = getMuxClient();
                const inputInfo = await muxClient.video.assets.retrieveInputInfo(assetId);
                const downloadUrl = inputInfo[0]?.settings?.url;

                // Find the audio record by uploadId
                const audioQuery = await db.collection('audio')
                    .where('uploadId', '==', uploadId)
                    .limit(1)
                    .get();

                if (audioQuery.empty) {
                    logger.warn("No audio record found with uploadId", { uploadId });
                    res.status(404).json({ error: 'Audio record not found' });
                    return;
                }

                const audioDoc = audioQuery.docs[0];
                await audioDoc.ref.update({
                    status: 'ready',
                    assetId,
                    playbackId,
                    download_url: downloadUrl,
                    updated_at: new Date().toISOString()
                });

                logger.info("Updated audio status to ready", {
                    audioId: audioDoc.id,
                    storyId: audioDoc.data().storyId,
                    sceneNumber: audioDoc.data().sceneNumber,
                    uploadId,
                    assetId,
                    playbackId,
                    downloadUrl
                });
            } else if (hasVideoTracks) {
                // Handle video assets
                const videoRef = db.collection('videos').doc(uploadId);
                const videoDoc = await videoRef.get();

                if (!videoDoc.exists) {
                    logger.error("No video found with ID", { uploadId });
                    res.status(404).json({ error: 'Video not found' });
                    return;
                }

                await videoRef.update({
                    status: 'ready',
                    asset_id: assetId,
                    playback_id: playbackId,
                    updated_at: new Date().toISOString()
                });

                logger.info("Updated video status to ready", {
                    docId: videoDoc.id,
                    assetId,
                    playbackId
                });
            } else {
                logger.warn("Asset has neither video nor audio tracks", { 
                    assetId,
                    uploadId,
                    tracks: event.data.tracks
                });
                res.status(400).json({ error: 'Invalid asset type' });
                return;
            }
        }

        // Handle asset.errored event
        if (event.type === 'video.asset.errored') {
            const uploadId = event.data.upload_id;
            const error = event.data.errors?.messages?.[0] || 'Unknown error';

            // Check if this is a video or audio asset using the same logic
            const hasVideoTracks = event.data.tracks?.some((track: any) => track.type === 'video');
            const hasAudioTracks = event.data.tracks?.some((track: any) => track.type === 'audio');
            const isAudioOnly = !hasVideoTracks && hasAudioTracks;

            if (isAudioOnly) {
                // Find the audio record by uploadId
                const audioQuery = await db.collection('audio')
                    .where('uploadId', '==', uploadId)
                    .limit(1)
                    .get();

                if (audioQuery.empty) {
                    logger.warn("No audio record found with uploadId", { uploadId });
                    res.status(404).json({ error: 'Audio record not found' });
                    return;
                }

                const audioDoc = audioQuery.docs[0];
                await audioDoc.ref.update({
                    status: 'error',
                    error,
                    updated_at: new Date().toISOString()
                });

                logger.error("Audio processing failed", {
                    audioId: audioDoc.id,
                    storyId: audioDoc.data().storyId,
                    sceneNumber: audioDoc.data().sceneNumber,
                    uploadId,
                    error
                });
            } else if (hasVideoTracks) {
                // Handle video errors
                const videoRef = db.collection('videos').doc(uploadId);
                const videoDoc = await videoRef.get();

                if (!videoDoc.exists) {
                    logger.error("No video found with ID", { uploadId });
                    res.status(404).json({ error: 'Video not found' });
                    return;
                }

                await videoRef.update({
                    status: 'error',
                    error: error,
                    updated_at: new Date().toISOString()
                });

                logger.error("Video processing failed", {
                    docId: videoDoc.id,
                    error
                });
            }
        }

        res.status(200).json({ message: 'Webhook processed' });
        return;
    } catch (error) {
        logger.error("Error processing webhook:", error);
        res.status(500).json({ error: 'Webhook processing failed' });
    }
});

// Webhook endpoint to handle Leonardo.ai notifications
export const leonardoWebhook = onRequest(
  {
    cors: false,
    maxInstances: 100,
    invoker: 'public'
  },
  async (req, res) => {
    try {
      // Verify webhook authorization
      const authHeader = req.headers.authorization;
      if (!authHeader || !authHeader.startsWith('Bearer ')) {
        logger.error("No Leonardo authorization found in webhook request");
        res.status(401).json({ error: 'No authorization provided' });
        return;
      }

      const webhookApiKey = authHeader.split(' ')[1];
      if (webhookApiKey !== leonardoWebhookSecret.value()) {
        logger.error("Invalid Leonardo webhook API key");
        res.status(401).json({ error: 'Invalid authorization' });
        return;
      }

      // Add detailed payload logging
      logger.info("Leonardo webhook full payload:", {
        body: JSON.stringify(req.body, null, 2),
        timestamp: new Date().toISOString()
      });

      const event = req.body;
      logger.info("Received Leonardo webhook", { 
        type: event.type,
        generationId: event.data?.object?.id
      });

      // Handle image generation completion
      if (event.type === 'image_generation.complete') {
        const generation = event.data.object;
        const generationId = generation.id;
        const status = generation.status;
        const images = generation.images;

        // Find the image record by generationId
        const imageQuery = await db.collection('images')
          .where('generationId', '==', generationId)
          .limit(1)
          .get();

        if (imageQuery.empty) {
          logger.warn("No image record found with generationId", { generationId });
          res.status(404).json({ error: 'Image record not found' });
          return;
        }

        const imageDoc = imageQuery.docs[0];
        const imageData = imageDoc.data();
        
        if (status === 'COMPLETE' && images?.length > 0) {
          // Update the image record with the URL and status
          await imageDoc.ref.update({
            status: 'complete',
            url: images[0].url,
            nsfw: images[0].nsfw,
            updated_at: new Date().toISOString()
          });

          logger.info("Updated image status to complete", {
            imageId: imageDoc.id,
            storyId: imageData.storyId,
            sceneNumber: imageData.sceneNumber,
            generationId,
            url: images[0].url
          });

          // If motion is enabled, start motion generation
          if (imageData.motion) {
            try {
              // Check if motion video record already exists
              const existingMotionQuery = await db.collection('motion_videos')
                .where('imageId', '==', imageDoc.id)
                .limit(1)
                .get();

              if (existingMotionQuery.empty) {
                const leonardoApi = new LeonardoAPI(leonardoApiKey.value());
                const motionGenerationId = await leonardoApi.generateMotion(images[0].id);

                if (motionGenerationId) {
                  // Create motion video record
                  await db.collection('motion_videos').add({
                    imageId: imageDoc.id,
                    storyId: imageData.storyId,
                    sceneNumber: imageData.sceneNumber,
                    generationId: motionGenerationId,
                    status: 'generating',
                    created_at: new Date().toISOString()
                  });

                  logger.info("Motion generation started", {
                    imageId: imageDoc.id,
                    storyId: imageData.storyId,
                    sceneNumber: imageData.sceneNumber,
                    motionGenerationId
                  });
                } else {
                  logger.error("Failed to start motion generation", {
                    imageId: imageDoc.id,
                    storyId: imageData.storyId
                  });
                }
              } else {
                logger.info("Motion generation already exists for image", {
                  imageId: imageDoc.id,
                  storyId: imageData.storyId,
                  sceneNumber: imageData.sceneNumber
                });
              }
            } catch (error) {
              logger.error("Error starting motion generation:", error);
            }
          }
        } else {
          // Handle failed generation
          await imageDoc.ref.update({
            status: 'error',
            error: `Generation failed with status: ${status}`,
            updated_at: new Date().toISOString()
          });

          logger.error("Image generation failed", {
            imageId: imageDoc.id,
            storyId: imageData.storyId,
            sceneNumber: imageData.sceneNumber,
            generationId,
            status
          });
        }
      }

      // Handle motion video generation completion
      if (event.type === 'video_generation.complete') {
        const generation = event.data.object;
        const generationId = generation.id;
        const status = generation.status;
        const isMotionVideo = generation.imageToVideo === true;
        
        logger.info("Processing video generation webhook", {
          generationId,
          status,
          isMotionVideo,
          hasImages: !!generation.images?.length
        });

        if (!isMotionVideo) {
          logger.info("Skipping non-motion video generation", { generationId });
          res.status(200).json({ message: 'Webhook processed' });
          return;
        }

        // Find the motion video record by generationId
        const motionQuery = await db.collection('motion_videos')
          .where('generationId', '==', generationId)
          .limit(1)
          .get();

        if (motionQuery.empty) {
          logger.warn("No motion video record found with generationId", { generationId });
          res.status(404).json({ error: 'Motion video record not found' });
          return;
        }

        const motionDoc = motionQuery.docs[0];
        const motionData = motionDoc.data();

        if (status === 'COMPLETE' && generation.images?.length > 0) {
          const motionMP4URL = generation.images[0].motionMP4URL;

          if (motionMP4URL) {
            // Update the motion video record with the URL and status
            await motionDoc.ref.update({
              status: 'ready',
              url: motionMP4URL,
              playbackId: motionMP4URL,
              updated_at: new Date().toISOString()
            });

            logger.info("Updated motion video status to ready", {
              motionId: motionDoc.id,
              imageId: motionData.imageId,
              storyId: motionData.storyId,
              sceneNumber: motionData.sceneNumber,
              url: motionMP4URL
            });
          } else {
            // Handle case where motion URL is missing
            await motionDoc.ref.update({
              status: 'error',
              error: 'Video generation completed but no motion MP4 URL provided',
              updated_at: new Date().toISOString()
            });

            logger.error("Motion video URL missing", {
              motionId: motionDoc.id,
              imageId: motionData.imageId,
              storyId: motionData.storyId,
              sceneNumber: motionData.sceneNumber
            });
          }
        } else {
          // Handle failed generation
          await motionDoc.ref.update({
            status: 'error',
            error: `Video generation failed with status: ${status}`,
            updated_at: new Date().toISOString()
          });

          logger.error("Motion video generation failed", {
            motionId: motionDoc.id,
            imageId: motionData.imageId,
            storyId: motionData.storyId,
            sceneNumber: motionData.sceneNumber,
            status
          });
        }
      }

      res.status(200).json({ message: 'Webhook processed' });
      return;
    } catch (error) {
      logger.error("Error processing Leonardo webhook:", error);
      res.status(500).json({ error: 'Webhook processing failed' });
    }
  }
);

/**
 * A simple linear congruential generator seeded with a number.
 */
function seededRandom(seed: number): () => number {
  return function () {
    seed = (seed * 9301 + 49297) % 233280;
    return seed / 233280;
  };
}

/**
 * Convert a string (e.g. a user hash) into a numeric seed.
 */
function hashToSeed(hash: string): number {
  let seed = 0;
  for (let i = 0; i < hash.length; i++) {
    seed += hash.charCodeAt(i);
  }
  return seed;
}

/**
 * Draw a filled hexagon.
 */
function drawHexagon(
  ctx: CanvasRenderingContext2D,
  x: number,
  y: number,
  radius: number,
  rotation: number,
  fillStyle: string
): void {
  ctx.save();
  ctx.translate(x, y);
  ctx.rotate(rotation);
  ctx.beginPath();
  for (let i = 0; i < 6; i++) {
    const angle = (Math.PI / 3) * i;
    const px = radius * Math.cos(angle);
    const py = radius * Math.sin(angle);
    if (i === 0) {
      ctx.moveTo(px, py);
    } else {
      ctx.lineTo(px, py);
    }
  }
  ctx.closePath();
  ctx.fillStyle = fillStyle;
  ctx.fill();
  ctx.restore();
}

// The main GIF generation function, now as a helper
function generateAnimatedProfileGif(
  userHash: string,
  width: number = 200,
  height: number = 200,
  frameCount: number = 30,
  delay: number = 100
): Buffer {
  if (frameCount < 2) {
    throw new Error('frameCount must be at least 2');
  }

  // Create and start the GIF encoder
  const encoder = new GIFEncoder(width, height);
  encoder.start();
  encoder.setRepeat(0); // loop indefinitely
  encoder.setDelay(delay);
  encoder.setQuality(10);

  // Create a canvas
  const canvas = createCanvas(width, height);
  const ctx = canvas.getContext('2d');

  // Seed the random generator
  const seed = hashToSeed(userHash);
  const random = seededRandom(seed);

  // Curated color palettes inspired by modern design trends
  const colorPalettes = [
    {
      name: 'sunset',
      background: { h: 232, s: 47, l: 6 }, // Deep blue-black
      colors: [
        { h: 350, s: 80, l: 60 }, // Coral pink
        { h: 20, s: 85, l: 65 },  // Warm orange
        { h: 45, s: 90, l: 70 },  // Golden yellow
      ]
    },
    {
      name: 'ocean',
      background: { h: 200, s: 45, l: 8 }, // Deep sea blue
      colors: [
        { h: 190, s: 90, l: 65 }, // Aqua
        { h: 210, s: 85, l: 60 }, // Ocean blue
        { h: 170, s: 80, l: 55 }, // Teal
      ]
    },
    {
      name: 'forest',
      background: { h: 150, s: 40, l: 7 }, // Dark forest
      colors: [
        { h: 135, s: 75, l: 55 }, // Leaf green
        { h: 90, s: 70, l: 60 },  // Spring green
        { h: 160, s: 80, l: 45 }, // Deep emerald
      ]
    },
    {
      name: 'cosmic',
      background: { h: 270, s: 45, l: 7 }, // Deep space purple
      colors: [
        { h: 280, s: 85, l: 65 }, // Bright purple
        { h: 320, s: 80, l: 60 }, // Pink
        { h: 260, s: 75, l: 55 }, // Deep violet
      ]
    },
    {
      name: 'candy',
      background: { h: 300, s: 40, l: 8 }, // Dark magenta
      colors: [
        { h: 340, s: 90, l: 65 }, // Hot pink
        { h: 280, s: 85, l: 70 }, // Bright purple
        { h: 315, s: 80, l: 60 }, // Magenta
      ]
    }
  ];

  // Select a palette based on the hash
  const selectedPalette = colorPalettes[Math.floor(random() * colorPalettes.length)];
  
  // Helper function to generate a color variation within the palette theme
  const generateThematicColor = () => {
    // Pick a base color from the palette
    const baseColor = selectedPalette.colors[Math.floor(random() * selectedPalette.colors.length)];
    
    // Create a variation of the base color
    const hueVariation = -10 + random() * 20; // ±10 degrees
    const saturationVariation = -5 + random() * 10; // ±5%
    const lightnessVariation = -10 + random() * 20; // ±10%
    
    return `hsl(${
      Math.floor(baseColor.h + hueVariation)
    }, ${
      Math.max(40, Math.min(100, baseColor.s + saturationVariation))
    }%, ${
      Math.max(30, Math.min(85, baseColor.l + lightnessVariation))
    }%)`;
  };

  // Decide how many shapes to draw
  const numShapes = 8 + Math.floor(random() * 8); // between 8 and 16 shapes

  // Precalculate properties for each shape
  type ShapeParams = {
    x: number;
    y: number;
    radius: number;
    rotationSpeed: number; // per frame increment (radians)
    initialRotation: number;
    color: string;
  };

  const shapes: ShapeParams[] = [];
  for (let i = 0; i < numShapes; i++) {
    // For hexagons, one "visual revolution" is actually 1/6th of a full rotation
    // due to 6-fold symmetry. So we'll work with smaller numbers to keep motion gentle
    
    // Choose a base number of visual revolutions (1/6 to 4/6 of a full rotation)
    const baseRevolutions = (Math.floor(random() * 4) + 1) / 6;
    
    // Add some smaller fractional variation while keeping it compatible with hexagonal symmetry
    // This adds either 0, 1/6, or 2/6 additional revolutions
    const extraRevolutions = Math.floor(random() * 3) / 6;
    const revolutions = baseRevolutions + extraRevolutions;
    
    const sign = random() < 0.5 ? -1 : 1;
    // Calculate the actual rotation speed in radians per frame
    const rotationSpeed = sign * ((revolutions * 2 * Math.PI) / (frameCount - 1));

    shapes.push({
      x: width * random(),
      y: height * random(),
      radius: width / 20 + random() * (width / 10),
      rotationSpeed,
      initialRotation: (random() * Math.PI) / 3, // Start at one of the 6 symmetric positions
      color: generateThematicColor(),
    });
  }

  // Generate each frame
  for (let frame = 0; frame < frameCount; frame++) {
    // Clear the canvas with the background color
    const bg = selectedPalette.background;
    ctx.fillStyle = `hsl(${bg.h}, ${bg.s}%, ${bg.l}%)`;
    ctx.fillRect(0, 0, width, height);

    // Draw each hexagon with its current rotation
    for (const shape of shapes) {
      const rotation = shape.initialRotation + frame * shape.rotationSpeed;
      drawHexagon(ctx, shape.x, shape.y, shape.radius, rotation, shape.color);
    }

    // Draw a pulsating circle in the center with a color from the palette
    const centerX = width / 2;
    const centerY = height / 2;
    const pulsateRadius =
      (width / 10) *
      (0.5 + 0.5 * Math.sin((frame * 2 * Math.PI) / (frameCount - 1)));

    ctx.beginPath();
    ctx.arc(centerX, centerY, pulsateRadius, 0, Math.PI * 2);
    // Use a bright variant from the palette for the center circle
    const centerColor = selectedPalette.colors[Math.floor(frame / frameCount * selectedPalette.colors.length)];
    ctx.strokeStyle = `hsl(${centerColor.h}, ${centerColor.s}%, ${Math.min(75, centerColor.l + 10)}%)`;
    ctx.lineWidth = 3;
    ctx.stroke();

    // Add the current canvas as a frame to the GIF
    encoder.addFrame(ctx as any);
  }

  encoder.finish();
  return encoder.out.getData();
}

interface GenerateGifRequest {
  width?: number;
  height?: number;
  frameCount?: number;
  delay?: number;
}

// Helper function to get user identifier following the same logic as iOS app
function getUserIdentifier(auth: any): string {
  const providerId = auth.token?.firebase?.sign_in_provider;
  
  if (providerId === 'apple.com') {
    return auth.token.email || auth.token.name || 'Anonymous';
  }
  
  return auth.token.name || auth.token.email || 'Anonymous';
}

// Cloud function to generate profile GIFs
export const generateProfileGif = onCall({
  maxInstances: 10,
  memory: "512MiB", // Canvas operations can be memory-intensive
  timeoutSeconds: 30,
  region: "us-central1",
  enforceAppCheck: false, // You can enable this later for additional security
}, async (request) => {
  try {
    // Ensure the user is authenticated
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "The function must be called while authenticated."
      );
    }

    // Get the user identifier using the same logic as iOS app
    const userIdentifier = getUserIdentifier(request.auth);
    
    // Validate request data
    const data = request.data as GenerateGifRequest;

    // Validate dimensions
    const width = data.width || 200;
    const height = data.height || 200;
    if (width > 800 || height > 800) {
      throw new HttpsError(
        "invalid-argument",
        "Maximum dimensions are 800x800"
      );
    }

    // Validate frame count
    const frameCount = data.frameCount || 30;
    if (frameCount > 120) {
      throw new HttpsError(
        "invalid-argument",
        "Maximum frame count is 120"
      );
    }

    // Validate delay
    const delay = data.delay || 100;
    if (delay < 20 || delay > 1000) {
      throw new HttpsError(
        "invalid-argument",
        "Delay must be between 20ms and 1000ms"
      );
    }

    // Log the request for monitoring
    logger.info("Generating profile GIF", {
      uid: request.auth.uid,
      userIdentifier,
      width,
      height,
      frameCount,
      delay
    });

    // Generate the GIF using the user identifier as the seed
    const gifBuffer = generateAnimatedProfileGif(
      userIdentifier,
      width,
      height,
      frameCount,
      delay
    );

    // Return the GIF as base64
    return {
      gif: gifBuffer.toString('base64'),
      contentType: 'image/gif'
    };
  } catch (error) {
    logger.error("Error generating profile GIF:", error);
    const msg = error instanceof Error ? error.message : "Unknown error";
    throw new HttpsError("internal", `Failed to generate profile GIF: ${msg}`);
  }
});

// Story generation function
export const generateStoryFunction = onCall({
  maxInstances: 2, // Limit concurrent executions due to resource intensity
  timeoutSeconds: 540, // 9 minutes (max is 540s for HTTP functions)
  memory: "2GiB", // Story generation can be memory intensive
  region: "us-central1",
  enforceAppCheck: false, // Enable in production
  invoker: "public"
}, async (request) => {
  try {
    // Ensure user is authenticated
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "The function must be called while authenticated."
      );
    }

    // Validate request data
    const data = request.data as {
      keywords: string[];
      config?: StoryConfig;
    };

    if (!data.keywords || !Array.isArray(data.keywords) || data.keywords.length === 0) {
      throw new HttpsError(
        "invalid-argument",
        "Keywords array is required and must not be empty"
      );
    }

    // Set up story input
    const storyInput: StoryInput = {
      keywords: data.keywords
    };

    // Set up configuration
    const config = {
      configurable: {
        extract_chars: data.config?.extract_chars ?? true,
        generate_voiceover: data.config?.generate_voiceover ?? true,
        generate_images: data.config?.generate_images ?? true,
        generate_motion: data.config?.generate_motion ?? false,
        save_script: data.config?.save_script ?? true,
        num_keyframes: data.config?.num_keyframes ?? 4,
        output_dir: `/tmp/story_${request.auth.uid}_${Date.now()}`,
        thread_id: `${request.auth.uid}_${Date.now()}`
      }
    };

    logger.info("Starting story generation", {
      uid: request.auth.uid,
      keywords: data.keywords,
      config: config.configurable
    });

    // Generate the story
    const result = await generateStory.invoke(storyInput, config);

    if (!result) {
      throw new HttpsError("internal", "Story generation failed");
    }

    const [story, , scripts] = result;  // Get the scripts tuple from the result
    const script = scripts?.[0] ?? '';  // Get the original script or empty string if null

    // Calculate total number of scenes
    const sceneCount = story.reduce((total, [_, scenes]) => total + scenes.length, 0);

    // Save story data to Firestore
    const storyDoc = await db.collection('stories').add({
      userId: request.auth.uid,
      keywords: data.keywords,
      sceneCount,
      script,  // Store the original script string
      created_at: new Date().toISOString(),
      status: 'completed'
    });

    // Initialize Leonardo API if image generation is enabled
    let leonardoApi: LeonardoAPI | null = null;
    if (config.configurable.generate_images) {
      leonardoApi = new LeonardoAPI(leonardoApiKey.value());
    }

    // Create audio records
    const audioPromises = story.flatMap(([_, scenes], keyframeIndex) => 
      scenes.map(async (scene, sceneIndex) => {
        if (scene.audio) {
          const sceneNumber = (keyframeIndex * 2) + sceneIndex;
          await db.collection('audio').add({
            storyId: storyDoc.id,
            sceneNumber,
            uploadId: scene.audio.muxUploadId,
            status: 'processing',
            created_at: new Date().toISOString()
          });
        }
      })
    );

    // Create image records and generate images if enabled
    const imagePromises = story.flatMap(([_, scenes, style], keyframeIndex) => 
      scenes.map(async (scene, sceneIndex) => {
        // Only proceed if we have a prompt and image generation is enabled
        if (scene.leonardo_prompt && leonardoApi && config.configurable.generate_images) {
          const sceneNumber = (keyframeIndex * 2) + sceneIndex;
          
          try {
            const result = await leonardoApi.generateImageForKeyframe(
              scene.leonardo_prompt,
              style || 'CREATIVE' as LeonardoStyle
            );

            if (result) {
              const [generationId] = result;
              // Create the image record only after successful generation start
              await db.collection('images').add({
                storyId: storyDoc.id,
                sceneNumber,
                status: 'generating',
                prompt: scene.leonardo_prompt,
                generationId,
                motion: config.configurable.generate_motion, // Add motion flag
                created_at: new Date().toISOString()
              });

              logger.info("Image generation started", {
                storyId: storyDoc.id,
                sceneNumber,
                generationId,
                motion: config.configurable.generate_motion
              });
            } else {
              logger.error("Failed to generate image", {
                storyId: storyDoc.id,
                sceneNumber
              });
            }
          } catch (error) {
            logger.error("Error generating image:", error);
          }
        }
      })
    );

    // Wait for all records to be created
    await Promise.all([...audioPromises, ...imagePromises]);

    logger.info("Story generation completed", {
      uid: request.auth.uid,
      storyId: storyDoc.id
    });

    // Return the story data and document ID
    return {
      storyId: storyDoc.id
    };

  } catch (error) {
    logger.error("Error in story generation:", error);
    const msg = error instanceof Error ? error.message : "Unknown error";
    throw new HttpsError("internal", `Story generation failed: ${msg}`);
  }
});

