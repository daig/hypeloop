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
  description: string;
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

        // Prepare metadata for passthrough
        // Ensure total length is under 255 characters
        const metadata = {
            creator: request.auth.token.name || request.auth.token.email || "Anonymous",
            description: data.description.length > 200 ? 
                data.description.substring(0, 197) + "..." : 
                data.description
        };

        // Create a direct upload URL
        const upload = await muxClient.video.uploads.create({
            new_asset_settings: {
                playback_policy: ["public"],
                mp4_support: "capped-1080p",
                passthrough: JSON.stringify(metadata)
            },
            cors_origin: "*", // For testing. In production, specify your domain
            timeout: 3600, // 1 hour to complete the upload
        });

        logger.info("Upload URL created successfully", {
            uploadId: upload.id,
            filename: data.filename,
            metadata
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
    enforceAppCheck: false,
    region: 'us-central1'
}, async (request) => {
    const debug = request.data?.debug === true;
    const client = request.data?.client || 'unknown';
    const timestamp = request.data?.timestamp || Date.now();
    const requestId = request.data?.requestId || 'no-id';

    // Log initial request details
    logger.info("🚀 Starting listMuxAssets function", {
        debug,
        client,
        timestamp,
        requestId,
        auth: !!request.auth,
        requestData: request.data
    });

    try {
        // Check if the user is authenticated
        if (!request.auth) {
            logger.warn("❌ Authentication missing", { requestId });
            throw new HttpsError(
                "unauthenticated",
                "The function must be called while authenticated."
            );
        }

        logger.info("✅ Authentication verified", { 
            requestId,
            uid: request.auth.uid 
        });

        // Initialize Mux client with credentials at runtime
        if (!muxTokenId.value() || !muxTokenSecret.value()) {
            logger.error("❌ Missing Mux credentials", { 
                requestId,
                hasMuxTokenId: !!muxTokenId.value(),
                hasMuxTokenSecret: !!muxTokenSecret.value()
            });
            throw new HttpsError(
                "failed-precondition",
                "Mux credentials not configured"
            );
        }

        const muxClient = new Mux({
            tokenId: muxTokenId.value(),
            tokenSecret: muxTokenSecret.value(),
        });

        logger.info("✅ Mux client initialized", { requestId });

        try {
            // List all assets with a timeout
            logger.info("📡 Making Mux API request", { requestId });
            
            const assetsPromise = muxClient.video.assets.list({
                limit: 50,
                page: 1
            });

            // Add a timeout to the request
            const timeoutPromise = new Promise((_, reject) => {
                setTimeout(() => reject(new Error('Request timeout')), 10000);
            });

            const { data: assets } = await Promise.race([assetsPromise, timeoutPromise]) as { data: any[] };

            logger.info("✅ Received Mux API response", { 
                requestId,
                assetCount: assets.length,
                responseType: typeof assets,
                isArray: Array.isArray(assets),
                sampleAsset: assets[0] ? {
                    id: assets[0].id,
                    hasPlaybackIds: !!assets[0].playback_ids,
                    playbackIdsCount: assets[0].playback_ids?.length,
                    status: assets[0].status
                } : null
            });

            // Transform and filter the assets
            const videos = assets
                .filter(asset => 
                    asset.status === 'ready' && 
                    asset.playback_ids && 
                    asset.playback_ids.length > 0
                )
                .map(asset => {
                    // Parse the Unix timestamp (seconds) to milliseconds
                    const timestamp = parseInt(asset.created_at) * 1000;
                    
                    // Parse the passthrough data
                    let creator = "User";
                    let description = "A cool video";
                    try {
                        if (asset.passthrough) {
                            const metadata = JSON.parse(asset.passthrough);
                            creator = metadata.creator || creator;
                            description = metadata.description || description;
                        }
                    } catch (error) {
                        logger.warn("Failed to parse passthrough data", { 
                            requestId, 
                            assetId: asset.id, 
                            passthrough: asset.passthrough 
                        });
                    }
                    
                    return {
                        id: asset.id,
                        playback_id: asset.playback_ids[0].id,
                        creator,
                        description,
                        created_at: timestamp,
                        status: asset.status
                    };
                });

            logger.info("✅ Processed videos", { 
                requestId,
                totalAssets: assets.length,
                filteredCount: videos.length,
                firstProcessedVideo: videos[0] || null,
                responseStructure: {
                    type: 'object',
                    keys: ['videos'],
                    videosType: 'array'
                }
            });

            const response = { videos };
            
            // Log the final response structure
            logger.info("📤 Returning response", {
                requestId,
                responseType: typeof response,
                hasVideosKey: 'videos' in response,
                videosIsArray: Array.isArray(response.videos),
                videosCount: response.videos.length,
                responseKeys: Object.keys(response),
                stringified: JSON.stringify(response).slice(0, 200) + '...' // First 200 chars
            });

            return response;

        } catch (muxError) {
            logger.error("❌ Mux API error:", { 
                error: muxError, 
                requestId,
                errorType: typeof muxError,
                errorIsError: muxError instanceof Error,
                errorMessage: muxError instanceof Error ? muxError.message : String(muxError),
                errorStack: muxError instanceof Error ? muxError.stack : undefined,
                errorKeys: Object.keys(muxError as object)
            });
            throw new HttpsError(
                "internal",
                "Error fetching videos from Mux",
                {
                    muxError: muxError instanceof Error ? muxError.message : String(muxError),
                    timestamp,
                    requestId
                }
            );
        }

    } catch (error) {
        logger.error("❌ Error in listMuxAssets:", {
            error,
            errorType: typeof error,
            errorIsError: error instanceof Error,
            errorIsHttpsError: error instanceof HttpsError,
            errorMessage: error instanceof Error ? error.message : String(error),
            errorStack: error instanceof Error ? error.stack : undefined,
            errorKeys: Object.keys(error as object),
            debug,
            client,
            timestamp,
            requestId
        });
        
        if (error instanceof HttpsError) {
            throw error;
        }
        
        throw new HttpsError(
            "internal",
            "Failed to list videos",
            {
                originalError: error instanceof Error ? error.message : String(error),
                timestamp,
                requestId
            }
        );
    }
});
