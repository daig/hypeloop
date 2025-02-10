import requests
import time
from enum import Enum
from typing import Dict, Optional
from dataclasses import dataclass

class LeonardoStyles(Enum):
    RENDER_3D = "render_3d"
    ACRYLIC = "acrylic"
    ANIME_GENERAL = "anime_general"
    CREATIVE = "creative"
    DYNAMIC = "dynamic"
    FASHION = "fashion"
    GAME_CONCEPT = "game_concept"
    GRAPHIC_DESIGN_3D = "graphic_design_3d"
    ILLUSTRATION = "illustration"
    NONE = "none"
    PORTRAIT = "portrait"
    PORTRAIT_CINEMATIC = "portrait_cinematic"
    RAY_TRACED = "ray_traced"
    STOCK_PHOTO = "stock_photo"
    WATERCOLOR = "watercolor"

LEONARDO_STYLE_IDS: Dict[LeonardoStyles, str] = {
    LeonardoStyles.RENDER_3D: "debdf72a-91a4-467b-bf61-cc02bdeb69c6",
    LeonardoStyles.ACRYLIC: "3cbb655a-7ca4-463f-b697-8a03ad67327c",
    LeonardoStyles.ANIME_GENERAL: "b2a54a51-230b-4d4f-ad4e-8409bf58645f",
    LeonardoStyles.CREATIVE: "6fedbf1f-4a17-45ec-84fb-92fe524a29ef",
    LeonardoStyles.DYNAMIC: "111dc692-d470-4eec-b791-3475abac4c46",
    LeonardoStyles.FASHION: "594c4a08-a522-4e0e-b7ff-e4dac4b6b622",
    LeonardoStyles.GAME_CONCEPT: "09d2b5b5-d7c5-4c02-905d-9f84051640f4",
    LeonardoStyles.GRAPHIC_DESIGN_3D: "7d7c2bc5-4b12-4ac3-81a9-630057e9e89f",
    LeonardoStyles.ILLUSTRATION: "645e4195-f63d-4715-a3f2-3fb1e6eb8c70",
    LeonardoStyles.NONE: "556c1ee5-ec38-42e8-955a-1e82dad0ffa1",
    LeonardoStyles.PORTRAIT: "8e2bc543-6ee2-45f9-bcd9-594b6ce84dcd",
    LeonardoStyles.PORTRAIT_CINEMATIC: "4edb03c9-8a26-4041-9d01-f85b5d4abd71",
    LeonardoStyles.RAY_TRACED: "b504f83c-3326-4947-82e1-7fe9e839ec0f",
    LeonardoStyles.STOCK_PHOTO: "5bdc3f2a-1be6-4d1c-8e77-992a30824a2c",
    LeonardoStyles.WATERCOLOR: "1db308ce-c7ad-4d10-96fd-592fa6b75cc4"
}

class LeonardoAPI:
    @dataclass(frozen=True)
    class GenerationId:
        """A type-safe wrapper for Leonardo generation IDs."""
        id: str

        def __str__(self) -> str:
            return self.id

    def __init__(self, api_key: str):
        self.api_key = api_key
        self.base_url = "https://cloud.leonardo.ai/api/rest/v1"
        self.headers = {
            "accept": "application/json",
            "authorization": f"Bearer {api_key}",
            "content-type": "application/json"
        }

    def generate_image_for_keyframe(self, prompt: str, style: LeonardoStyles) -> Optional[tuple["LeonardoAPI.GenerationId", str]]:
        """
        Generate an image using the Leonardo API.
        Returns tuple of (generation_id, image_id) if successful, None otherwise.
        """
        data = {
            "prompt": prompt,
            "modelId": "1dd50843-d653-4516-a8e3-f0238ee453ff",  # Flux Schnell model
            "width": 512,
            "height": 512,
            "num_images": 1,
            "guidance_scale": 7,
            "styleUUID": LEONARDO_STYLE_IDS[style]
        }

        response = requests.post(
            f"{self.base_url}/generations",
            headers=self.headers,
            json=data
        )

        if response.status_code != 200:
            print(f"Error generating image: {response.text}")
            return None

        generation_id = response.json().get("sdGenerationJob", {}).get("generationId")
        return (self.GenerationId(generation_id), None) if generation_id else None

    def poll_generation_status(self, generation_id: "LeonardoAPI.GenerationId") -> Optional[tuple[dict, str]]:
        """Poll the generation status until complete or failed. Returns (generation_data, image_id)."""
        url = f"{self.base_url}/generations/{generation_id.id}"
        
        while True:
            response = requests.get(url, headers=self.headers)
            if response.status_code != 200:
                print(f"Error checking status: {response.text}")
                return None
                
            data = response.json()
            generation_data = data.get("generations_by_pk", {})
            status = generation_data.get("status")
            print(f"Generation status: {status}")
            
            if status == "COMPLETE":
                # Get the image ID from the first generated image
                generated_images = generation_data.get("generated_images", [])
                if generated_images:
                    image_id = generated_images[0].get("id")
                    return generation_data, image_id
                return generation_data, None
            elif status in ["FAILED", "DELETED"]:
                print(f"Generation failed with status: {status}")
                return None
                
            time.sleep(5)  # Wait 5 seconds before polling again

    def generate_motion(self, image_id: str) -> Optional["LeonardoAPI.GenerationId"]:
        """
        Generate a motion video using the Leonardo API's SVD motion endpoint.
        Returns the generation ID if successful, None otherwise.
        """
        data = {
            "imageId": image_id,
            "motionStrength": 5,
            "isPublic": False
        }

        response = requests.post(
            f"{self.base_url}/generations-motion-svd",
            headers=self.headers,
            json=data
        )

        if response.status_code != 200:
            print(f"Error generating motion: {response.text}")
            return None

        generation_id = response.json().get("motionSvdGenerationJob", {}).get("generationId")
        return self.GenerationId(generation_id) if generation_id else None

    def poll_motion_status(self, generation_id: "LeonardoAPI.GenerationId") -> Optional[dict]:
        """Poll the motion generation status until complete or failed."""
        url = f"{self.base_url}/generations-motion-svd/{generation_id.id}"
        
        while True:
            response = requests.get(url, headers=self.headers)
            if response.status_code != 200:
                print(f"Error checking motion status: {response.text}")
                return None
                
            data = response.json()
            generation_data = data.get("generations_motion_by_pk", {})
            status = generation_data.get("status")
            print(f"Motion generation status: {status}")
            
            if status == "COMPLETE":
                return generation_data
            elif status in ["FAILED", "DELETED"]:
                print(f"Motion generation failed with status: {status}")
                return None
                
            time.sleep(5)  # Wait 5 seconds before polling again 