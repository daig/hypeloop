"""
Command-line interface for generating stories using the story generator.
"""

import argparse
import logging
from pathlib import Path
from story_generator import generate_story, logger

def main():
    parser = argparse.ArgumentParser(description="Generate a story based on theme keywords.")
    parser.add_argument("keywords", nargs="+", help='Theme keywords for the story (e.g., "adventure" "mystical forest")')
    parser.add_argument("--thread-id", default="default_thread", help="Thread ID for the story generation")
    parser.add_argument("--debug", action="store_true", help="Enable debug logging")
    parser.add_argument("--output-dir", default="output", help="Directory to save the generated files")
    
    args = parser.parse_args()
    
    if args.debug:
        logger.setLevel(logging.DEBUG)
        logger.debug("Debug logging enabled")
    
    # Create output directory if it doesn't exist.
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    logger.info("Writing output to directory: %s", output_dir)
    
    config = {
        "configurable": {
            "thread_id": args.thread_id
        }
    }
    
    logger.info("Starting story generation with thread ID: %s", args.thread_id)
    story = generate_story.invoke({"keywords": args.keywords}, config=config)
    
    print("\nGenerating story with keywords:", ", ".join(args.keywords))
    print("=" * 80 + "\n")
    
    # Write each keyframe and dialog to separate files.
    for idx, (desc, dialog) in enumerate(story, start=1):
        # Write keyframe description.
        keyframe_file = output_dir / f"keyframe_{idx}.txt"
        with open(keyframe_file, "w", encoding="utf-8") as f:
            f.write(desc)
        logger.info("Wrote keyframe %d to %s", idx, keyframe_file)
        
        # Write dialog/narration.
        dialog_file = output_dir / f"dialog_{idx}.txt"
        with open(dialog_file, "w", encoding="utf-8") as f:
            f.write(dialog)
        logger.info("Wrote dialog %d to %s", idx, dialog_file)
        
        # Print to console for immediate feedback.
        print(f"Keyframe {idx} Description:\n{desc}\n")
        print(f"Keyframe {idx} Dialog/Narration:\n{dialog}\n")
        print("=" * 80)

if __name__ == "__main__":
    main()