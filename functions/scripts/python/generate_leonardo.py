#!/usr/bin/env python3
import os
import sys
import json
import requests
import argparse
import logging
from pathlib import Path
from dotenv import load_dotenv
from leonardo_api import LeonardoAPI, LeonardoStyles

# Set up logging
logging.basicConfig(
    level=logging.ERROR,  # Default to ERROR level
    format="%(asctime)s - %(levelname)s - %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S"
)
logger = logging.getLogger(__name__)

def download_image(image_url: str, output_path: str) -> bool:
    """Download an image from a URL to disk."""
    try:
        response = requests.get(image_url)
        if response.status_code == 200:
            with open(output_path, 'wb') as f:
                f.write(response.content)
            logger.info(f"Image downloaded successfully to: {output_path}")
            return True
        else:
            logger.error(f"Failed to download image: {response.status_code}")
            return False
    except Exception as e:
        logger.error(f"Error downloading image: {e}")
        return False

def generate_and_save_motion(leonardo_client: LeonardoAPI, image_id: str, output_dir: Path) -> None:
    """Generate a motion video for an image using the Leonardo API."""
    try:
        # Generate motion using the SVD endpoint
        motion_generation_id = leonardo_client.generate_motion(image_id)
        if not motion_generation_id:
            logger.error("Failed to start motion generation")
            return

        # Poll for completion and get result
        motion_result = leonardo_client.poll_motion_status(motion_generation_id)
        if motion_result:
            video_url = motion_result.get("url")
            if video_url:
                logger.info(f"Got video URL: {video_url}")
                # Download video
                video_path = output_dir / f"{image_id}_motion.mp4"
                
                response = requests.get(video_url)
                logger.info(f"Download response status: {response.status_code}")
                
                if response.status_code == 200 and len(response.content) > 0:
                    with open(video_path, "wb") as f:
                        f.write(response.content)
                    logger.info(f"Saved motion video to {video_path}")
                else:
                    logger.error(f"Failed to download motion video: Empty response or bad status {response.status_code}")
            else:
                logger.error("No video URL in motion generation response")
        else:
            logger.error("Motion generation failed")
    except Exception as e:
        logger.error(f"Error generating motion: {e}", exc_info=True)

def main():
    parser = argparse.ArgumentParser(description="Generate images and motion videos using Leonardo API")
    parser.add_argument("prompt_file", help="Path to text file containing the image prompt")
    parser.add_argument("style_file", help="Path to JSON file containing the visual style")
    parser.add_argument("--motion", action="store_true", help="Generate motion video for the generated image")
    parser.add_argument("--output-dir", default="output/images", help="Directory to save generated files")
    parser.add_argument("--debug", action="store_true", help="Enable debug logging")
    
    args = parser.parse_args()

    # Set debug logging if flag is provided
    if args.debug:
        logger.setLevel(logging.DEBUG)
        logger.debug("Debug logging enabled")

    # Load environment variables from .env file
    load_dotenv()
    leonardo_api_key = os.getenv("LEONARDO_API_KEY")
    if not leonardo_api_key:
        logger.error("Error: LEONARDO_API_KEY not found in .env file.")
        sys.exit(1)

    # Load prompt text
    try:
        with open(args.prompt_file, 'r') as f:
            prompt_text = f.read().strip()
        if not prompt_text:
            logger.error("Error: Prompt file is empty")
            sys.exit(1)
    except FileNotFoundError:
        logger.error(f"Error: Prompt file not found: {args.prompt_file}")
        sys.exit(1)

    # Load and validate visual style
    try:
        with open(args.style_file, 'r') as f:
            style_data = json.load(f)
            visual_style = style_data.get('visual_style')
            if not visual_style:
                logger.error("Error: JSON file must contain a 'visual_style' key")
                sys.exit(1)
            style = LeonardoStyles(visual_style)
    except FileNotFoundError:
        logger.error(f"Error: Visual style file not found: {args.style_file}")
        sys.exit(1)
    except json.JSONDecodeError:
        logger.error(f"Error: Invalid JSON in file: {args.style_file}")
        sys.exit(1)
    except ValueError:
        logger.error(f"Error: Invalid visual style value: {visual_style}")
        logger.error("Valid styles: %s", ", ".join(style.value for style in LeonardoStyles))
        sys.exit(1)

    # Create output directory
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    # Initialize the Leonardo API client
    leonardo = LeonardoAPI(leonardo_api_key)

    # Generate the image
    generation_result = leonardo.generate_image_for_keyframe(prompt_text, style)
    if not generation_result:
        logger.error("Failed to start image generation")
        sys.exit(1)

    generation_id, _ = generation_result
    logger.info(f"\nPolling generation status for ID: {generation_id}")
    
    poll_result = leonardo.poll_generation_status(generation_id)
    if poll_result:
        generation_data, image_id = poll_result
        generated_images = generation_data.get("generated_images", [])
        if generated_images:
            image_url = generated_images[0].get("url")
            if image_url:
                # Create output filename based on generation ID
                extension = image_url.split(".")[-1]
                output_path = output_dir / f"{str(generation_id)}.{extension}"
                if download_image(image_url, output_path):
                    # Generate motion if requested
                    if args.motion and image_id:
                        logger.info("Generating motion video...")
                        generate_and_save_motion(leonardo, image_id, output_dir)
            else:
                logger.error("No image URL in response")
        else:
            logger.error("No generated images in response")

if __name__ == "__main__":
    main()