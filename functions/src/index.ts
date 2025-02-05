/**
 * Import function triggers from their respective submodules:
 *
 * import {onCall} from "firebase-functions/v2/https";
 * import {onDocumentWritten} from "firebase-functions/v2/firestore";
 *
 * See a full list of supported triggers at https://firebase.google.com/docs/functions
 */

import {onCall, HttpsError} from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import Mux from "@mux/mux-node";
import {defineString} from "firebase-functions/params";

const muxTokenId = defineString("MUX_TOKEN_ID");
const muxTokenSecret = defineString("MUX_TOKEN_SECRET");

interface UploadRequest {
  filename: string;
  fileSize: number;
  contentType: string;
}

// Start writing functions
// https://firebase.google.com/docs/functions/typescript

// export const helloWorld = onRequest((request, response) => {
//   logger.info("Hello logs!", {structuredData: true});
//   response.send("Hello from Firebase!");
// });

// Function to generate a presigned URL for direct uploads to Mux
export const getVideoUploadUrl = onCall({
    maxInstances: 1,
    enforceAppCheck: false,  // You can enable this later for additional security
    region: 'us-central1'
}, async (request) => {
    logger.info("Starting getVideoUploadUrl function", {data: request.data});

    try {
        // Check if the user is authenticated
        if (!request.auth) {
            throw new HttpsError(
                "unauthenticated",
                "The function must be called while authenticated."
            );
        }

        // Validate request data
        const data = request.data as UploadRequest;
        if (!data.filename || !data.fileSize || !data.contentType) {
            throw new HttpsError(
                "invalid-argument",
                "Required fields: filename, fileSize, and contentType"
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
        });

        // Create a direct upload URL
        const upload = await muxClient.video.uploads.create({
            new_asset_settings: {
                playback_policy: ["public"],
                mp4_support: "capped-1080p",
            },
            cors_origin: "*", // For testing. In production, specify your domain
            timeout: 3600, // 1 hour to complete the upload
        });

        logger.info("Upload URL created successfully", {
            uploadId: upload.id,
            filename: data.filename,
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

// Function to list all videos from Mux
export const listMuxAssets = onCall({
    maxInstances: 1,
    enforceAppCheck: false,  // You can enable this later for additional security
    region: 'us-central1'
}, async (request) => {
    const debug = request.data?.debug === true;
    const client = request.data?.client || 'unknown';
    const timestamp = request.data?.timestamp || Date.now();

    logger.info("Starting listMuxAssets function", {
        debug,
        client,
        timestamp,
        auth: !!request.auth
    });

    try {
        // Check if the user is authenticated
        if (!request.auth) {
            throw new HttpsError(
                "unauthenticated",
                "The function must be called while authenticated."
            );
        }

        // Initialize Mux client with credentials at runtime
        const muxClient = new Mux({
            tokenId: muxTokenId.value(),
            tokenSecret: muxTokenSecret.value(),
        });

        logger.info("Mux client initialized, fetching assets...");

        try {
            // List all assets
            const {data: assets} = await muxClient.video.assets.list({
                limit: 50, // Adjust this value based on your needs
                page: 1
            });

            logger.info(`Successfully fetched ${assets.length} assets from Mux`);

            if (debug) {
                logger.debug("First asset sample:", {
                    sample: assets[0] ? {
                        id: assets[0].id,
                        playback_ids: assets[0].playback_ids,
                        status: assets[0].status,
                        created_at: assets[0].created_at
                    } : null
                });
            }

            // Transform the assets into the format we need
            const videos = assets.map((asset: any) => {
                const video = {
                    id: asset.id,
                    playback_id: asset.playback_ids?.[0]?.id,
                    creator: asset.metadata?.creator || "User",
                    description: asset.metadata?.description || "A cool video",
                    created_at: new Date(asset.created_at).getTime()
                };

                if (debug) {
                    logger.debug(`Processed asset ${asset.id}:`, {
                        hasPlaybackId: !!video.playback_id,
                        metadata: asset.metadata
                    });
                }

                return video;
            });

            logger.info(`Successfully processed ${videos.length} videos`);
            return videos;

        } catch (muxError) {
            logger.error("Mux API error:", muxError);
            throw new HttpsError(
                "internal",
                "Error fetching videos from Mux",
                {
                    muxError: muxError instanceof Error ? muxError.message : String(muxError),
                    timestamp
                }
            );
        }

    } catch (error) {
        logger.error("Error in listMuxAssets:", {
            error,
            debug,
            client,
            timestamp
        });
        
        if (error instanceof HttpsError) {
            throw error;
        }
        
        throw new HttpsError(
            "internal",
            "Failed to list videos",
            {
                originalError: error instanceof Error ? error.message : String(error),
                timestamp
            }
        );
    }
});
