"""
Command-line interface for generating stories using the story generator.
"""

import argparse
import logging
import json
import os
from pathlib import Path
from story_generator import generate_story, logger, Role
from leonardo_api import LeonardoAPI, LeonardoStyles
from schemas import DialogResponse
from dotenv import load_dotenv
from typing import Tuple, Dict, Any, List, Optional
import subprocess
import asyncio
import aiohttp
import aiofiles
from tts_core import generate_speech_from_text
import time

async def generate_image_for_keyframe(leonardo_client: LeonardoAPI, 
                              keyframe_desc: str, 
                              visual_style: str,
                              output_dir: Path,
                              keyframe_num: int) -> tuple[Path | None, str | None, str | None]:
    """
    Generate an image for a keyframe using the Leonardo API.
    Returns tuple of (image_path, generation_id, image_id) if successful, (None, None, None) otherwise.
    """
    try:
        # Convert string style to enum
        style = LeonardoStyles(visual_style.lower())
        
        # Generate the image - run in executor since it's not async
        loop = asyncio.get_event_loop()
        generation_result = await loop.run_in_executor(
            None, 
            lambda: leonardo_client.generate_image_for_keyframe(keyframe_desc, style)
        )
        
        if not generation_result:
            logger.error(f"Failed to generate image for keyframe {keyframe_num}")
            return None, None, None

        generation_id, _ = generation_result

        # Poll for completion and get result - run in executor since it's not async
        while True:
            poll_result = await loop.run_in_executor(
                None,
                lambda: leonardo_client.poll_generation_status(generation_id)
            )
            
            if poll_result:
                generation_data, image_id = poll_result
                if generation_data.get("status") == "COMPLETE":
                    generated_images = generation_data.get("generated_images", [])
                    if generated_images:
                        image_url = generated_images[0].get("url")
                        if image_url:
                            # Download image
                            image_filename = f"keyframe_{keyframe_num}.jpg"
                            image_path = output_dir / image_filename
                            
                            # Use aiohttp to download the image asynchronously
                            async with aiohttp.ClientSession() as session:
                                async with session.get(image_url) as response:
                                    if response.status == 200:
                                        content = await response.read()
                                        async with aiofiles.open(image_path, "wb") as f:
                                            await f.write(content)
                                        logger.info(f"Saved image for keyframe {keyframe_num} to {image_path}")
                                        return image_path, str(generation_id), image_id
                                    else:
                                        logger.error(f"Failed to download image for keyframe {keyframe_num}: {response.status}")
                        else:
                            logger.error(f"No image URL in response for keyframe {keyframe_num}")
                    else:
                        logger.error(f"No generated images in response for keyframe {keyframe_num}")
                    break
                elif generation_data.get("status") in ["FAILED", "DELETED"]:
                    logger.error(f"Generation failed for keyframe {keyframe_num} with status: {generation_data.get('status')}")
                    break
                # If still pending, wait a bit before polling again
                await asyncio.sleep(2)
            else:
                logger.error(f"Poll failed for keyframe {keyframe_num}")
                break
                
    except Exception as e:
        logger.error(f"Error generating image for keyframe {keyframe_num}: {e}")
    
    return None, None, None

async def generate_motion_for_image(leonardo_client: LeonardoAPI,
                            image_id: str,
                            output_dir: Path,
                            keyframe_num: int) -> None:
    """Generate a motion video for an image using the Leonardo API."""
    try:
        # Generate motion using the SVD endpoint - run in executor since it's not async
        loop = asyncio.get_event_loop()
        motion_generation_id = await loop.run_in_executor(
            None,
            lambda: leonardo_client.generate_motion(image_id)
        )
        
        if not motion_generation_id:
            logger.error(f"Failed to start motion generation for keyframe {keyframe_num}")
            return

        # Poll for completion and get result
        while True:
            motion_result = await loop.run_in_executor(
                None,
                lambda: leonardo_client.poll_motion_status(motion_generation_id)
            )
            
            if motion_result:
                if motion_result.get("status") == "COMPLETE":
                    video_url = motion_result.get("url")
                    if video_url:
                        logger.info(f"Got video URL for keyframe {keyframe_num}: {video_url}")
                        video_path = output_dir / f"keyframe_{keyframe_num}.mp4"
                        
                        # Download video asynchronously
                        async with aiohttp.ClientSession() as session:
                            async with session.get(video_url) as response:
                                if response.status == 200:
                                    content = await response.read()
                                    async with aiofiles.open(video_path, "wb") as f:
                                        await f.write(content)
                                    logger.info(f"Saved motion video for keyframe {keyframe_num} to {video_path}")
                                else:
                                    logger.error(f"Failed to download motion video for keyframe {keyframe_num}: {response.status}")
                    else:
                        logger.error(f"No video URL in motion generation response for keyframe {keyframe_num}")
                    break
                elif motion_result.get("status") in ["FAILED", "DELETED"]:
                    logger.error(f"Motion generation failed for keyframe {keyframe_num}")
                    break
                # If still pending, wait a bit before polling again
                await asyncio.sleep(2)
        else:
            logger.error(f"Motion generation failed for keyframe {keyframe_num}")
    except Exception as e:
        logger.error(f"Error generating motion for keyframe {keyframe_num}: {e}", exc_info=True)

def write_dialog_to_file(dialog: DialogResponse, output_path: str):
    """Write dialog to JSON file."""
    dialog_dict = {
        "character": dialog.character,  # Role enum value
        "text": dialog.text
    }
    with open(output_path, 'w') as f:
        json.dump(dialog_dict, f, indent=2)

def write_voiceover_to_file(audio_data: bytes, output_path: Path) -> None:
    """Write voiceover audio data to an MP3 file."""
    try:
        with open(output_path, 'wb') as f:
            f.write(audio_data)
        logger.info(f"Saved voiceover to {output_path}")
    except Exception as e:
        logger.error(f"Failed to save voiceover to {output_path}: {e}")

async def generate_static_video_from_image(image_path: Path, output_dir: Path, keyframe_num: int) -> None:
    """
    Generate a 5-second static video from an image, matching Leonardo's motion video settings.
    Video settings: 512x512, 24fps, h264 codec, 5 seconds duration.
    """
    try:
        video_path = output_dir / f"keyframe_{keyframe_num}.mp4"
        
        # FFmpeg command to create static video
        cmd = [
            'ffmpeg', '-y',
            '-loop', '1',
            '-i', str(image_path),
            '-c:v', 'libx264',
            '-t', '5',
            '-vf', 'scale=512:512:force_original_aspect_ratio=decrease,pad=512:512:(ow-iw)/2:(oh-ih)/2',
            '-r', '24',
            '-pix_fmt', 'yuv420p',
            str(video_path)
        ]
        
        # Run FFmpeg command asynchronously
        process = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )
        
        stdout, stderr = await process.communicate()
        
        if process.returncode == 0:
            logger.info(f"Generated static video for keyframe {keyframe_num} at {video_path}")
        else:
            logger.error(f"Failed to generate static video for keyframe {keyframe_num}: {stderr.decode()}")
            
    except Exception as e:
        logger.error(f"Error generating static video for keyframe {keyframe_num}: {e}", exc_info=True)

async def process_keyframe(
    leonardo_client: LeonardoAPI,
    desc: str,
    dialog: DialogResponse,
    audio_data: bytes | None,
    visual_style: str,
    keyframe_num: int,
    output_dir: Path,
    images_dir: Path | None,
    generate_video: bool,
    use_motion: bool
) -> None:
    """Process a single keyframe including image generation and video creation"""
    try:
        # Write keyframe description
        keyframe_file = output_dir / f"keyframe_{keyframe_num}.txt"
        async with aiofiles.open(keyframe_file, "w", encoding="utf-8") as f:
            await f.write(desc)
        logger.info("Wrote keyframe %d to %s", keyframe_num, keyframe_file)
        
        # Write dialog - convert to dict for JSON serialization
        dialog_path = output_dir / f"dialog_{keyframe_num}.json"
        dialog_dict = {
            "character": dialog.character.model_dump(),
            "text": dialog.text
        }
        async with aiofiles.open(dialog_path, "w", encoding="utf-8") as f:
            await f.write(json.dumps(dialog_dict, indent=2))
        logger.info("Wrote dialog %d to %s", keyframe_num, dialog_path)
        
        # Write voiceover if generated
        if audio_data:
            voiceover_path = output_dir / f"voiceover_{keyframe_num}.mp3"
            async with aiofiles.open(voiceover_path, "wb") as f:
                await f.write(audio_data)
            logger.info("Wrote voiceover %d to %s", keyframe_num, voiceover_path)
        
        # Only attempt image/video generation if we have a leonardo client and images directory
        if leonardo_client and images_dir:
            # Read the optimized prompt if it exists
            prompt_file = output_dir / f"keyframe_prompt_{keyframe_num}.txt"
            try:
                async with aiofiles.open(prompt_file, "r", encoding="utf-8") as f:
                    optimized_prompt = await f.read()
                logger.info(f"Using optimized prompt from {prompt_file}")
                # Generate image using the optimized prompt
                print(f"\nStarting image generation for keyframe {keyframe_num} using optimized prompt...")
                image_result = await generate_image_for_keyframe(
                    leonardo_client,
                    optimized_prompt,
                    visual_style,
                    images_dir,
                    keyframe_num
                )
            except FileNotFoundError:
                logger.warning(f"No optimized prompt found at {prompt_file}, using original description")
                print(f"\nStarting image generation for keyframe {keyframe_num} using original description...")
                image_result = await generate_image_for_keyframe(
                    leonardo_client,
                    desc,
                    visual_style,
                    images_dir,
                    keyframe_num
                )
            
            # Generate video if requested
            if generate_video and image_result[0]:  # image_path exists
                if use_motion:
                    print(f"\nStarting motion generation for keyframe {keyframe_num}...")
                    await generate_motion_for_image(
                        leonardo_client,
                        image_result[2],  # image_id
                        images_dir,
                        keyframe_num
                    )
                else:
                    print(f"\nGenerating static video for keyframe {keyframe_num}...")
                    await generate_static_video_from_image(
                        image_result[0],  # image_path
                        images_dir,
                        keyframe_num
                    )
        
        # Print feedback
        print(f"Keyframe {keyframe_num} Description:\n{desc}\n")
        print(f"Keyframe {keyframe_num} Dialog/Narration:\n{dialog.text}\n")
        if audio_data:
            print(f"Voiceover saved to: {voiceover_path}\n")
        print("=" * 80)
        
    except Exception as e:
        logger.error(f"Error processing keyframe {keyframe_num}: {e}", exc_info=True)

async def async_main(args: argparse.Namespace) -> None:
    """Async main function to handle parallel processing"""
    # Create output directory
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    logger.info("Writing output to directory: %s", output_dir)
    
    # Initialize Leonardo API if needed
    leonardo_client = None
    if args.images:
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
            "thread_id": args.thread_id,
            "extract_chars": args.characters,
            "generate_voiceover": args.voiceover,
            "generate_images": bool(args.images),  # Convert to bool since args.images will be a string path
            "save_script": args.script,
            "num_keyframes": args.keyframes,
            "output_dir": args.output_dir
        }
    }
    
    logger.info("Starting story generation with thread ID: %s", args.thread_id)
    logger.debug("Config values: %s", config["configurable"])
    story_result = generate_story.invoke({"keywords": args.keywords}, config=config)
    
    if not story_result:
        logger.error("Story generation failed")
        return
        
    story, characters, scripts = story_result
    logger.debug("Story result unpacked - scripts type: %s", type(scripts))
    if scripts:
        logger.debug("Scripts tuple contents: %s", scripts)
    
    print("\nGenerating story with keywords:", ", ".join(args.keywords))
    print("=" * 80 + "\n")
    
    if story:
        # Write metadata
        visual_style = story[0][2]
        metadata_file = output_dir / "metadata.json"
        async with aiofiles.open(metadata_file, "w", encoding="utf-8") as f:
            await f.write(json.dumps({"visual_style": visual_style}, indent=2))
        logger.info("Wrote metadata to %s", metadata_file)
        print(f"\nSelected Visual Style: {visual_style}\n")
        print("=" * 80 + "\n")
        
        # Write character profiles if requested
        if args.characters and characters:
            characters_file = output_dir / "characters.json"
            async with aiofiles.open(characters_file, "w", encoding="utf-8") as f:
                # Convert characters to dict for JSON serialization
                characters_data = [char.model_dump() for char in characters]
                await f.write(json.dumps({"characters": characters_data}, indent=2))
            logger.info("Wrote character profiles to %s", characters_file)
            print("\nGenerated Character Profiles:")
            for char in characters:
                print(f"- {char.name} ({char.role})")
            print("=" * 80 + "\n")
        
        # Write full script if requested
        if args.script and scripts:
            original_script, enhanced_script = scripts
            logger.debug("Unpacking scripts for writing to file:")
            logger.debug("Original script length: %d", len(original_script))
            logger.debug("Enhanced script length: %d", len(enhanced_script))
            
            script_file = output_dir / "script.txt"
            async with aiofiles.open(script_file, "w", encoding="utf-8") as f:
                logger.debug("Writing original script to file...")
                # Write original script
                await f.write("# Original Story Script\n\n")
                await f.write(original_script)
                await f.write("\n\n" + "=" * 80 + "\n\n")
                
                logger.debug("Writing enhanced script to file...")
                # Write enhanced script with character details
                await f.write("# Enhanced Story Script\n")
                await f.write("(Incorporating character details and backgrounds)\n\n")
                await f.write(enhanced_script)
                await f.write("\n\n" + "=" * 80 + "\n\n")
                
                logger.debug("Writing scene breakdown to file...")
                # Write scene breakdown
                await f.write("# Scene Breakdown\n\n")
                for idx, (desc, dialog, _, _) in enumerate(story, start=1):
                    await f.write(f"Scene {idx}:\n")
                    await f.write(f"Description: {desc}\n")
                    await f.write(f"Narration: {dialog.text}\n")
                    await f.write(f"Spoken by: {dialog.character.name} ({dialog.character.role})\n\n")
            logger.info("Wrote full script to %s", script_file)
            print("\nFull script (original and enhanced versions) saved to:", script_file)
            print("=" * 80 + "\n")
        
        # Generate voiceovers if requested
        voiceovers = None
        if args.voiceover:
            logger.info("Launching parallel voiceover generation for %d keyframes", len(story))
            async def generate_voiceover_async(dialog: DialogResponse) -> bytes:
                """Generate voiceover for a single dialog"""
                try:
                    response = generate_speech_from_text(dialog.text, character=dialog.character.role.value)
                    return response.read()
                except Exception as e:
                    logger.error(f"Failed to generate voiceover: {str(e)}")
                    raise
            
            voiceover_tasks = [generate_voiceover_async(dialog) for _, dialog, _, _ in story]
            voiceovers = await asyncio.gather(*voiceover_tasks)
        
        # Process all keyframes in parallel
        tasks = []
        for idx, (desc, dialog, _, _) in enumerate(story, start=1):
            task = process_keyframe(
                leonardo_client,
                desc,
                dialog,
                voiceovers[idx-1] if voiceovers else None,
                visual_style,
                idx,
                output_dir,
                Path(args.images) if args.images else None,
                args.motion or args.static_vid,
                args.motion
            )
            tasks.append(task)
        
        # Wait for all tasks to complete
        await asyncio.gather(*tasks)

def main():
    parser = argparse.ArgumentParser(description="Generate a story based on theme keywords.")
    parser.add_argument("keywords", nargs="+", help='Theme keywords for the story (e.g., "adventure" "mystical forest")')
    parser.add_argument("--thread-id", default="default_thread", help="Thread ID for the story generation")
    parser.add_argument("--debug", action="store_true", help="Enable debug logging")
    parser.add_argument("--output-dir", default="output", help="Directory to save the generated files")
    parser.add_argument("--images", help="Generate images for keyframes and save to specified directory")
    parser.add_argument("--motion", action="store_true", help="Generate motion video for the first keyframe image")
    parser.add_argument("--static-vid", action="store_true", help="Generate static videos (5 seconds) from keyframe images")
    parser.add_argument("--characters", action="store_true", help="Extract and save character profiles to characters.json")
    parser.add_argument("--voiceover", action="store_true", help="Generate voiceover audio for each keyframe")
    parser.add_argument("--script", action="store_true", help="Save the full story script to script.txt")
    parser.add_argument("--keyframes", type=int, default=4, help="Number of keyframes to generate (default: 4)")
    
    args = parser.parse_args()
    
    # Set debug logging if flag is provided
    if args.debug:
        logger.setLevel(logging.DEBUG)
        logger.debug("Debug logging enabled")
    
    # Run async main
    asyncio.run(async_main(args))

if __name__ == "__main__":
    main()