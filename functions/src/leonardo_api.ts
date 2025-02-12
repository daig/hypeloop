import { LeonardoStyle } from './schemas.js';

// Leonardo style IDs mapping
const LEONARDO_STYLE_IDS: Record<LeonardoStyle, string> = {
  RENDER_3D: "debdf72a-91a4-467b-bf61-cc02bdeb69c6",
  ACRYLIC: "3cbb655a-7ca4-463f-b697-8a03ad67327c",
  ANIME_GENERAL: "b2a54a51-230b-4d4f-ad4e-8409bf58645f",
  CREATIVE: "6fedbf1f-4a17-45ec-84fb-92fe524a29ef",
  DYNAMIC: "111dc692-d470-4eec-b791-3475abac4c46",
  FASHION: "594c4a08-a522-4e0e-b7ff-e4dac4b6b622",
  GAME_CONCEPT: "09d2b5b5-d7c5-4c02-905d-9f84051640f4",
  GRAPHIC_DESIGN_3D: "7d7c2bc5-4b12-4ac3-81a9-630057e9e89f",
  ILLUSTRATION: "645e4195-f63d-4715-a3f2-3fb1e6eb8c70",
  NONE: "556c1ee5-ec38-42e8-955a-1e82dad0ffa1",
  PORTRAIT: "8e2bc543-6ee2-45f9-bcd9-594b6ce84dcd",
  PORTRAIT_CINEMATIC: "4edb03c9-8a26-4041-9d01-f85b5d4abd71",
  RAY_TRACED: "b504f83c-3326-4947-82e1-7fe9e839ec0f",
  STOCK_PHOTO: "5bdc3f2a-1be6-4d1c-8e77-992a30824a2c",
  WATERCOLOR: "1db308ce-c7ad-4d10-96fd-592fa6b75cc4"
};

// Item types enum and IDs
export enum ItemType {
  POTION = "potion",
  WEAPON = "weapon",
  ARMOR = "armor",
  CRYSTAL = "crystal",
  EQUIPMENT = "equipment"
}

const LEONARDO_ITEM_TYPE_IDS: Record<ItemType, string> = {
  [ItemType.POTION]: "45ab2421-87de-44c8-a07c-3b87e3bfdf84",  // Magic Potions model
  [ItemType.WEAPON]: "47a6232a-1d49-4c95-83c3-2cc5342f82c7",  // Battle Axes model
  [ItemType.ARMOR]: "302e258f-29b5-4dd8-9a7c-0cd898cb2143",   // Chest Armor model
  [ItemType.CRYSTAL]: "102a8ee0-cf16-477c-8477-c76963a0d766", // Crystal Deposits model
  [ItemType.EQUIPMENT]: "2d18c0af-374e-4391-9ca2-639f59837c85" // Magic Items model
};

// Type for generation response
interface GenerationResponse {
  sdGenerationJob?: {
    generationId: string;
  };
  motionSvdGenerationJob?: {
    generationId: string;
  };
  generations_by_pk?: {
    status: string;
    generated_images?: Array<{
      id: string;
      motionMP4URL?: string;
    }>;
  };
}

export class LeonardoAPI {
  private readonly baseUrl = "https://cloud.leonardo.ai/api/rest/v1";
  private readonly headers: Record<string, string>;

  constructor(apiKey: string) {
    this.headers = {
      "accept": "application/json",
      "authorization": `Bearer ${apiKey}`,
      "content-type": "application/json"
    };
  }

  /**
   * Generate an image for a specific item type
   * @returns Tuple of [generationId, imageId] if successful, null otherwise
   */
  async generateImageForItem(
    prompt: string,
    style: LeonardoStyle,
    itemType: ItemType
  ): Promise<[string, string | null] | null> {
    const data = {
      prompt,
      modelId: LEONARDO_ITEM_TYPE_IDS[itemType],
      width: 512,
      height: 512,
      num_images: 1,
      guidance_scale: 7
    };

    try {
      const response = await fetch(`${this.baseUrl}/generations`, {
        method: 'POST',
        headers: this.headers,
        body: JSON.stringify(data)
      });

      if (!response.ok) {
        console.error('Error generating image:', await response.text());
        return null;
      }

      const json = await response.json() as GenerationResponse;
      const generationId = json.sdGenerationJob?.generationId;
      return generationId ? [generationId, null] : null;
    } catch (error) {
      console.error('Error generating image:', error);
      return null;
    }
  }

  /**
   * Generate an image for a keyframe
   * @returns Tuple of [generationId, imageId] if successful, null otherwise
   */
  async generateImageForKeyframe(
    prompt: string,
    style: LeonardoStyle
  ): Promise<[string, string | null] | null> {
    const data = {
      prompt,
      modelId: "1dd50843-d653-4516-a8e3-f0238ee453ff", // Flux Schnell model
      width: 512,
      height: 512,
      num_images: 1,
      guidance_scale: 7,
      styleUUID: LEONARDO_STYLE_IDS[style]
    };

    try {
      const response = await fetch(`${this.baseUrl}/generations`, {
        method: 'POST',
        headers: this.headers,
        body: JSON.stringify(data)
      });

      if (!response.ok) {
        console.error('Error generating image:', await response.text());
        return null;
      }

      const json = await response.json() as GenerationResponse;
      const generationId = json.sdGenerationJob?.generationId;
      return generationId ? [generationId, null] : null;
    } catch (error) {
      console.error('Error generating image:', error);
      return null;
    }
  }

  /**
   * Poll the generation status until complete or failed
   * @returns Tuple of [generationData, imageId] if successful, null otherwise
   */
  async pollGenerationStatus(generationId: string): Promise<[GenerationResponse, string | null] | null> {
    const url = `${this.baseUrl}/generations/${generationId}`;
    
    while (true) {
      try {
        const response = await fetch(url, {
          headers: this.headers
        });

        if (!response.ok) {
          console.error('Error checking status:', await response.text());
          return null;
        }

        const data = await response.json() as GenerationResponse;
        const generationData = data.generations_by_pk;
        const status = generationData?.status;
        console.log('Generation status:', status);

        if (status === 'COMPLETE') {
          const generatedImages = generationData?.generated_images;
          if (generatedImages?.length) {
            const imageId = generatedImages[0].id;
            return [data, imageId];
          }
          return [data, null];
        } else if (status === 'FAILED' || status === 'DELETED') {
          console.error('Generation failed with status:', status);
          return null;
        }

        // Wait 5 seconds before polling again
        await new Promise(resolve => setTimeout(resolve, 5000));
      } catch (error) {
        console.error('Error polling generation status:', error);
        return null;
      }
    }
  }

  /**
   * Generate a motion video using the Leonardo API's SVD motion endpoint
   * @returns Generation ID if successful, null otherwise
   */
  async generateMotion(imageId: string): Promise<string | null> {
    const data = {
      imageId,
      motionStrength: 2,
      isPublic: true
    };

    try {
      const response = await fetch(`${this.baseUrl}/generations-motion-svd`, {
        method: 'POST',
        headers: this.headers,
        body: JSON.stringify(data)
      });

      if (!response.ok) {
        console.error('Error generating motion:', await response.text());
        return null;
      }

      const json = await response.json() as GenerationResponse;
      return json.motionSvdGenerationJob?.generationId ?? null;
    } catch (error) {
      console.error('Error generating motion:', error);
      return null;
    }
  }

  /**
   * Poll the motion generation status until complete or failed
   * @returns Object with video URL if successful, null otherwise
   */
  async pollMotionStatus(generationId: string): Promise<{ url: string } | null> {
    const url = `${this.baseUrl}/generations/${generationId}`;
    
    while (true) {
      try {
        const response = await fetch(url, {
          headers: this.headers
        });

        if (!response.ok) {
          console.error('Error checking motion status:', await response.text());
          return null;
        }

        const data = await response.json() as GenerationResponse;
        console.log('Full motion status response:', JSON.stringify(data, null, 2));

        const generationData = data.generations_by_pk;
        const status = generationData?.status;
        console.log('Motion generation status:', status);

        if (status === 'COMPLETE') {
          const generatedImages = generationData?.generated_images;
          if (generatedImages?.length && generatedImages[0].motionMP4URL) {
            return { url: generatedImages[0].motionMP4URL };
          }
          console.error('No video URL found in completed generation');
          return null;
        } else if (status === 'FAILED' || status === 'DELETED') {
          console.error('Motion generation failed with status:', status);
          return null;
        }

        // Wait 5 seconds before polling again
        await new Promise(resolve => setTimeout(resolve, 5000));
      } catch (error) {
        console.error('Error polling motion status:', error);
        return null;
      }
    }
  }
} 