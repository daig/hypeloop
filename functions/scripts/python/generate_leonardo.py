#!/usr/bin/env python3
import os
import sys
import json
import requests
from dotenv import load_dotenv
from leonardo_api import LeonardoAPI, LeonardoStyles

def download_image(image_url: str, output_path: str) -> bool:
    """Download an image from a URL to disk."""
    try:
        response = requests.get(image_url)
        if response.status_code == 200:
            with open(output_path, 'wb') as f:
                f.write(response.content)
            print(f"Image downloaded successfully to: {output_path}")
            return True
        else:
            print(f"Failed to download image: {response.status_code}")
            return False
    except Exception as e:
        print(f"Error downloading image: {e}")
        return False

def main():
    # Load environment variables from .env file
    load_dotenv()
    leonardo_api_key = os.getenv("LEONARDO_API_KEY")
    if not leonardo_api_key:
        print("Error: LEONARDO_API_KEY not found in .env file.")
        sys.exit(1)

    # Check for required arguments
    if len(sys.argv) != 3:
        print("Usage: python generate_image.py <prompt_text_file> <visual_style_json_path>")
        sys.exit(1)

    prompt_file_path = sys.argv[1]
    visual_style_path = sys.argv[2]

    # Load prompt text
    try:
        with open(prompt_file_path, 'r') as f:
            prompt_text = f.read().strip()
        if not prompt_text:
            print("Error: Prompt file is empty")
            sys.exit(1)
    except FileNotFoundError:
        print(f"Error: Prompt file not found: {prompt_file_path}")
        sys.exit(1)

    # Load and validate visual style
    try:
        with open(visual_style_path, 'r') as f:
            style_data = json.load(f)
            visual_style = style_data.get('visual_style')
            if not visual_style:
                print("Error: JSON file must contain a 'visual_style' key")
                sys.exit(1)
            style = LeonardoStyles(visual_style)
    except FileNotFoundError:
        print(f"Error: Visual style file not found: {visual_style_path}")
        sys.exit(1)
    except json.JSONDecodeError:
        print(f"Error: Invalid JSON in file: {visual_style_path}")
        sys.exit(1)
    except ValueError:
        print(f"Error: Invalid visual style value: {visual_style}")
        print("Valid styles:", ", ".join(style.value for style in LeonardoStyles))
        sys.exit(1)

    # Initialize the Leonardo API client
    leonardo = LeonardoAPI(leonardo_api_key)

    # Generate the image
    generation_id = leonardo.generate_image(prompt_text, style)
    if not generation_id:
        print("Failed to start image generation")
        sys.exit(1)

    print(f"\nPolling generation status for ID: {generation_id}")
    generation_result = leonardo.poll_generation_status(generation_id)
    
    if generation_result:
        # Get the first generated image URL
        generated_images = generation_result.get("generated_images", [])
        if generated_images:
            image_url = generated_images[0].get("url")
            if image_url:
                # Create output filename based on generation ID and extract extension from URL
                output_dir = "output/images"
                os.makedirs(output_dir, exist_ok=True)
                extension = image_url.split(".")[-1]  # Get extension from URL (jpeg, png, etc)
                output_path = os.path.join(output_dir, f"{str(generation_id)}.{extension}")
                download_image(image_url, output_path)
            else:
                print("No image URL in response")
        else:
            print("No generated images in response")

if __name__ == "__main__":
    main()