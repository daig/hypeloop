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
import {defineString} from "firebase-functions/params";
import { initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";

// Initialize Firebase Admin
initializeApp();

// Initialize Firestore
const db = getFirestore();

const muxTokenId = defineString("MUX_TOKEN_ID");
const muxTokenSecret = defineString("MUX_TOKEN_SECRET");
const muxWebhookSecret = defineString("MUX_WEBHOOK_SECRET");

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

// Webhook endpoint to handle Mux notifications
export const muxWebhook = onRequest(
    {
        cors: false,
        maxInstances: 1,
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

            if (!playbackId) {
                logger.error("No playback ID found in ready event", { assetId });
                res.status(400).json({ error: 'No playback ID' });
                return;
            }

            // Get the video document directly by ID
            const videoRef = db.collection('videos').doc(uploadId);
            const videoDoc = await videoRef.get();

            if (!videoDoc.exists) {
                logger.error("No video found with ID", { uploadId });
                res.status(404).json({ error: 'Video not found' });
                return;
            }
            // Update only the necessary fields while preserving others
            await videoRef.update({
                status: 'ready',
                playback_id: playbackId,
                asset_id: assetId,
                updated_at: new Date().toISOString()
            });

            logger.info("Updated video status to ready", { 
                docId: videoDoc.id, 
                playbackId, 
                assetId 
            });
        }

        // Handle asset.errored event
        if (event.type === 'video.asset.errored') {
            const uploadId = event.data.upload_id;
            const error = event.data.errors?.messages?.[0] || 'Unknown error';

            const videosRef = db.collection('videos');
            const videoQuery = await videosRef.where('uploadId', '==', uploadId).get();

            if (!videoQuery.empty) {
                const videoDoc = videoQuery.docs[0];
                await videoDoc.ref.update({
                    status: 'error',
                    error: error,
                    updatedAt: new Date().toISOString()
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

