import {defineString} from "firebase-functions/params";

// OpenAI configuration
export const openAiKey = defineString("OPENAI_API_KEY");

// Mux configuration
export const muxTokenId = defineString("MUX_TOKEN_ID");
export const muxTokenSecret = defineString("MUX_TOKEN_SECRET");
export const muxWebhookSecret = defineString("MUX_WEBHOOK_SECRET");

// Leonardo configuration
export const leonardoApiKey = defineString("LEONARDO_API_KEY");
export const leonardoUserId = defineString("LEONARDO_USER_ID"); 