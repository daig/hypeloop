import os
from dotenv import load_dotenv
from typing import List, Dict, Tuple
from openai import OpenAI
from langgraph.func import task, entrypoint
from langgraph.checkpoint.memory import MemorySaver
import argparse
import logging
import time
import textwrap
from pathlib import Path

# Set up logging configuration
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger(__name__)

# Load environment variables from specified path
env_path = os.path.join(os.path.dirname(__file__), '../../.env')
load_dotenv(env_path)

# Initialize OpenAI client
client = OpenAI()

# ---------- Helper Function to Parse Keyframe Output ----------

def parse_keyframes(text: str) -> List[Dict[str, str]]:
    """
    Parses the keyframe output text into a list of dictionaries.
    Expected format:
      Keyframe [Number]:
      Title: <Title>
      Description: <Detailed visual description>
    """
    logger.debug("Starting to parse keyframes from text of length: %d", len(text))
    keyframes = []
    blocks = text.split("Keyframe")
    logger.debug("Found %d raw keyframe blocks", len(blocks))
    
    for block in blocks:
        block = block.strip()
        if not block:
            continue
        title = ""
        description = ""
        for line in block.splitlines():
            if line.startswith("Title:"):
                title = line.replace("Title:", "").strip()
            elif line.startswith("Description:"):
                description = line.replace("Description:", "").strip()
        if title and description:
            keyframes.append({"title": title, "description": description})
    
    logger.debug("Successfully parsed %d keyframes", len(keyframes))
    return keyframes

def log_prompt_and_response(prompt: str, response: str, context: str = ""):
    """Helper function to log prompts and responses in a readable format"""
    if context:
        logger.debug("\n=== %s ===", context)
    logger.debug("\n----- Prompt -----\n%s", textwrap.indent(prompt, '> '))
    logger.debug("\n----- Response -----\n%s", textwrap.indent(response, '< '))
    logger.debug("-" * 60)

def invoke_chat_completion(prompt: str) -> str:
    """
    Helper function to invoke OpenAI chat completion API.
    """
    response = client.chat.completions.create(
        model="gpt-4o-mini",
        messages=[{"role": "user", "content": prompt}],
        temperature=0.7
    )
    return response.choices[0].message.content

# ---------- OpenAI Pipeline Tasks using LangGraph ----------

@task
def generate_script(keywords: List[str]) -> str:
    """
    Generates a full screenplay script from a list of theme keywords.
    """
    logger.info("Generating script with keywords: %s", ", ".join(keywords))
    start_time = time.time()
    
    prompt = f"""You are an expert screenwriter tasked with creating an engaging, cinematic screenplay.
Theme Keywords: {', '.join(keywords)}.

Requirements:
- Write a short screenplay (approximately 800-1000 words) with clear scene headings (e.g., "Scene 1", "Scene 2", etc.).
- Introduce key characters and provide vivid descriptions of settings, moods, and actions.
- Include both narration and dialogue that evoke strong visual imagery and emotion.
- Ensure the script flows logically and builds an engaging story arc.

Please produce the complete screenplay in a structured format.
"""
    logger.debug("Sending prompt to OpenAI (length: %d characters)", len(prompt))
    response = invoke_chat_completion(prompt)
    
    elapsed_time = time.time() - start_time
    logger.info("Script generation completed in %.2f seconds", elapsed_time)
    logger.debug("Generated script length: %d characters", len(response))
    
    log_prompt_and_response(prompt, response, "Script Generation")
    return response

@task
def extract_keyframes(script: str) -> List[Dict[str, str]]:
    """
    Breaks the screenplay into key visual moments ("keyframes") optimized for prompting an image generator.
    """
    logger.info("Extracting keyframes from script")
    start_time = time.time()
    
    prompt = f"""You are a visual storyteller and scene director.
Below is a complete screenplay. Your task is to break it down into a series of key visual moments or "keyframes".

For each keyframe, please provide:
1. A concise title (e.g., "Keyframe 1: The Enchanted Forest Entrance").
2. A vivid description of the scene that captures:
   - The setting (location, time of day, atmosphere).
   - Key actions and events.
   - Mood and visual details (colors, lighting, textures).
   - Any notable visual effects or cinematic style cues.
Ensure that each keyframe description is detailed and evocative, optimized for use as a prompt in an image-generation API.

Script:
{script}

Format your output as follows:
Keyframe [Number]:
Title: [Your title]
Description: [Detailed visual description]
"""
    logger.debug("Sending keyframe extraction prompt to OpenAI")
    response = invoke_chat_completion(prompt)
    keyframe_text = response
    
    log_prompt_and_response(prompt, keyframe_text, "Keyframe Extraction")
    
    keyframes = parse_keyframes(keyframe_text)
    elapsed_time = time.time() - start_time
    logger.info("Extracted %d keyframes in %.2f seconds", len(keyframes), elapsed_time)
    
    return keyframes

@task
def extract_dialog(script: str, keyframe_description: str) -> str:
    """
    Combines the full screenplay and a keyframe description to extract dialogue and narration.
    """
    logger.debug("Extracting dialog for keyframe: %s", keyframe_description[:100] + "...")
    start_time = time.time()
    
    prompt = f"""You are a narrative editor. Given the complete screenplay and a specific keyframe description, extract or rewrite the dialogue and narration that best correspond to that keyframe.

Keyframe Description:
{keyframe_description}

Script:
{script}

For this keyframe, please provide:
- A "Narration" section that describes the overall scene context.
- A "Dialogue" section that includes any character lines, clearly indicating the speaker for each line.

Output Format:
Narration: [Narrative text]
Dialogue:
  - [Character Name]: [Dialogue text]
  - [Character Name]: [Dialogue text] (if applicable)
"""
    response = invoke_chat_completion(prompt)
    
    log_prompt_and_response(prompt, response, f"Dialog Extraction (Keyframe: {keyframe_description[:50]}...)")
    
    elapsed_time = time.time() - start_time
    logger.debug("Dialog extraction completed in %.2f seconds", elapsed_time)
    
    return response

@entrypoint(checkpointer=MemorySaver())
def generate_story(inputs: Dict[str, List[str]]) -> List[Tuple[str, str]]:
    """
    Public interface function that ties the OpenAI steps together.
    
    Input:
      - inputs: Dictionary containing 'keywords' list
    
    Output:
      - A list of pairs, where each pair is (keyframe description, keyframe dialog/narration).
    """
    logger.info("Starting story generation process")
    start_time = time.time()
    
    keywords = inputs["keywords"]
    logger.info("Processing keywords: %s", ", ".join(keywords))
    
    script = generate_script(keywords).result()
    keyframes = extract_keyframes(script).result()
    
    logger.info("Processing dialog for %d keyframes", len(keyframes))
    results: List[Tuple[str, str]] = []
    for i, kf in enumerate(keyframes, 1):
        logger.debug("Processing dialog for keyframe %d/%d", i, len(keyframes))
        dialog = extract_dialog(script, kf["description"]).result()
        results.append((kf["description"], dialog))
    
    total_time = time.time() - start_time
    logger.info("Story generation completed in %.2f seconds", total_time)
    
    return results

# ---------- Example Usage ----------

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Generate a story based on theme keywords.')
    parser.add_argument('keywords', nargs='+', help='Theme keywords for the story (e.g., "adventure" "mystical forest")')
    parser.add_argument('--thread-id', default='default_thread', help='Thread ID for the story generation')
    parser.add_argument('--debug', action='store_true', help='Enable debug logging')
    parser.add_argument('--output-dir', default='output', help='Directory to save the generated files')
    
    args = parser.parse_args()
    
    if args.debug:
        logger.setLevel(logging.DEBUG)
        logger.debug("Debug logging enabled")
    
    # Create output directory if it doesn't exist
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
    
    # Write each keyframe and dialog to separate files
    for idx, (desc, dialog) in enumerate(story, start=1):
        # Write keyframe description
        keyframe_file = output_dir / f"keyframe_{idx}.txt"
        with open(keyframe_file, 'w', encoding='utf-8') as f:
            f.write(desc)
        logger.info("Wrote keyframe %d to %s", idx, keyframe_file)
        
        # Write dialog/narration
        dialog_file = output_dir / f"dialog_{idx}.txt"
        with open(dialog_file, 'w', encoding='utf-8') as f:
            f.write(dialog)
        logger.info("Wrote dialog %d to %s", idx, dialog_file)
        
        # Still print to console for immediate feedback
        print(f"Keyframe {idx} Description:\n{desc}\n")
        print(f"Keyframe {idx} Dialog/Narration:\n{dialog}\n")
        print("=" * 80)