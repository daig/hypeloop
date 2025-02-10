"""
Command-line interface for generating stories using the story generator.
"""

import argparse
import logging
import json
import os
from pathlib import Path
from story_generator import generate_story, logger
from leonardo_api import LeonardoAPI, LeonardoStyles
from dotenv import load_dotenv

def generate_image_for_keyframe(leonardo_client: LeonardoAPI, 
                              keyframe_desc: str, 
                              visual_style: str,
                              output_dir: Path,
                              keyframe_num: int) -> None:
    """Generate an image for a keyframe using the Leonardo API."""
    try:
        # Convert string style to enum
        style = LeonardoStyles(visual_style.lower())
        
        # Generate the image
        generation_id = leonardo_client.generate_image(keyframe_desc, style)
        if not generation_id:
            logger.error(f"Failed to generate image for keyframe {keyframe_num}")
            return

        # Poll for completion and get result
        generation_result = leonardo_client.poll_generation_status(generation_id)
        if generation_result:
            generated_images = generation_result.get("generated_images", [])
            if generated_images:
                image_url = generated_images[0].get("url")
                if image_url:
                    # Download image
                    image_filename = f"keyframe_{keyframe_num}.jpg"
                    image_path = output_dir / image_filename
                    
                    # Use requests to download the image
                    import requests
                    response = requests.get(image_url)
                    if response.status_code == 200:
                        with open(image_path, "wb") as f:
                            f.write(response.content)
                        logger.info(f"Saved image for keyframe {keyframe_num} to {image_path}")
                    else:
                        logger.error(f"Failed to download image for keyframe {keyframe_num}: {response.status_code}")
                else:
                    logger.error(f"No image URL in response for keyframe {keyframe_num}")
            else:
                logger.error(f"No generated images in response for keyframe {keyframe_num}")
        else:
            logger.error(f"Generation failed for keyframe {keyframe_num}")
    except Exception as e:
        logger.error(f"Error generating image for keyframe {keyframe_num}: {e}")

def main():
    parser = argparse.ArgumentParser(description="Generate a story based on theme keywords.")
    parser.add_argument("keywords", nargs="+", help='Theme keywords for the story (e.g., "adventure" "mystical forest")')
    parser.add_argument("--thread-id", default="default_thread", help="Thread ID for the story generation")
    parser.add_argument("--debug", action="store_true", help="Enable debug logging")
    parser.add_argument("--output-dir", default="output", help="Directory to save the generated files")
    parser.add_argument("--images", help="Generate images for keyframes and save to specified directory")
    
    args = parser.parse_args()
    
    if args.debug:
        logger.setLevel(logging.DEBUG)
        logger.debug("Debug logging enabled")
    
    # Create output directory if it doesn't exist
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    logger.info("Writing output to directory: %s", output_dir)
    
    # Initialize Leonardo API if image generation is requested
    leonardo_client = None
    if args.images:
        # Load environment variables
        env_path = os.path.join(os.path.dirname(__file__), "../../.env")
        load_dotenv(env_path)
        
        leonardo_api_key = os.getenv("LEONARDO_API_KEY")
        if not leonardo_api_key:
            logger.error("LEONARDO_API_KEY not found in environment variables")
            return
            
        leonardo_client = LeonardoAPI(leonardo_api_key)
        
        # Create images directory
        image_dir = Path(args.images)
        image_dir.mkdir(parents=True, exist_ok=True)
        logger.info("Will generate images in directory: %s", image_dir)
    
    config = {
        "configurable": {
            "thread_id": args.thread_id
        }
    }
    
    logger.info("Starting story generation with thread ID: %s", args.thread_id)
    story = generate_story.invoke({"keywords": args.keywords}, config=config)
    
    print("\nGenerating story with keywords:", ", ".join(args.keywords))
    print("=" * 80 + "\n")
    
    # Write metadata file with visual style
    if story:
        visual_style = story[0][2]  # Get style from first tuple (it's the same for all)
        metadata_file = output_dir / "metadata.json"
        with open(metadata_file, "w", encoding="utf-8") as f:
            json.dump({"visual_style": visual_style}, f, indent=2)
        logger.info("Wrote metadata to %s", metadata_file)
        print(f"\nSelected Visual Style: {visual_style}\n")
        print("=" * 80 + "\n")
    
    # Write each keyframe and dialog to separate files, and generate images if requested
    for idx, (desc, dialog, _) in enumerate(story, start=1):
        # Write keyframe description
        keyframe_file = output_dir / f"keyframe_{idx}.txt"
        with open(keyframe_file, "w", encoding="utf-8") as f:
            f.write(desc)
        logger.info("Wrote keyframe %d to %s", idx, keyframe_file)
        
        # Write dialog/narration
        dialog_file = output_dir / f"dialog_{idx}.txt"
        with open(dialog_file, "w", encoding="utf-8") as f:
            f.write(dialog)
        logger.info("Wrote dialog %d to %s", idx, dialog_file)
        
        # Generate image if requested
        if leonardo_client and args.images:
            print(f"\nGenerating image for keyframe {idx}...")
            generate_image_for_keyframe(
                leonardo_client,
                desc,
                visual_style,
                Path(args.images),
                idx
            )
        
        # Print to console for immediate feedback
        print(f"Keyframe {idx} Description:\n{desc}\n")
        print(f"Keyframe {idx} Dialog/Narration:\n{dialog}\n")
        print("=" * 80)

if __name__ == "__main__":
    main()