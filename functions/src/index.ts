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
import {defineString} from "firebase-functions/params";
import { initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";

// Initialize Firebase Admin
initializeApp();

// Initialize Firestore
const db = getFirestore();

const muxTokenId = defineString("MUX_TOKEN_ID");
const muxTokenSecret = defineString("MUX_TOKEN_SECRET");

interface UploadRequest {
  filename: string;
  fileSize: number;
  contentType: string;
  description: string;
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
        const muxClient = new Mux({
            tokenId: muxTokenId.value(),
            tokenSecret: muxTokenSecret.value(),
        });

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

// Mux webhook handler
export const muxWebhook = onRequest({
    region: 'us-central1',
    cors: true,
    timeoutSeconds: 60,
    minInstances: 0,
    maxInstances: 100
}, async (request, response) => {
    // Set CORS headers
    response.set('Access-Control-Allow-Origin', '*');
    response.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
    response.set('Access-Control-Allow-Headers', 'Content-Type');

    // Handle preflight requests
    if (request.method === 'OPTIONS') {
        response.status(204).send('');
        return;
    }

    // Only allow POST requests
    if (request.method !== 'POST') {
        response.status(405).send('Method not allowed');
        return;
    }

    try {
        const event = request.body;
        logger.info("Received Mux webhook", { type: event.type });

        // Verify this is a video.asset.ready event
        if (event.type === 'video.asset.ready') {
            const assetId = event.data.id;
            const playbackId = event.data.playback_ids?.[0]?.id;
            const uploadId = event.data.upload_id;

            if (!playbackId) {
                logger.error("No playback ID found in event data", { event });
                response.status(400).send('No playback ID found in event data');
                return;
            }

            logger.info("Processing video.asset.ready event", {
                assetId,
                playbackId,
                uploadId
            });

            // Find the video document using the upload ID
            const videosRef = db.collection('videos');
            const querySnapshot = await videosRef.where('id', '==', uploadId).get();

            if (!querySnapshot.empty) {
                const videoDoc = querySnapshot.docs[0];
                await videoDoc.ref.update({
                    status: 'ready',
                    playback_id: playbackId,
                    mux_asset_id: assetId
                });
                logger.info("Updated video document with playback ID", { docId: videoDoc.id });
                response.status(200).send('Webhook processed successfully');
            } else {
                logger.error("No matching video document found for upload ID", { uploadId });
                response.status(404).send('No matching video document found');
            }
        } else {
            // For non-video.asset.ready events, just acknowledge receipt
            response.status(200).send('Event type acknowledged');
        }
    } catch (error) {
        logger.error("Error processing webhook:", error);
        const msg = error instanceof Error ? error.message : "Unknown error";
        response.status(500).send(`Error processing webhook: ${msg}`);
    }
});

