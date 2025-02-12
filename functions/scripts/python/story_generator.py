"""
Core functionality for generating stories using OpenAI and LangGraph.
"""

import os
from dotenv import load_dotenv
from typing import List, Dict, Tuple, Optional, Any
from openai import OpenAI
from langgraph.func import task, entrypoint
from langgraph.checkpoint.memory import MemorySaver
import logging
import time
import textwrap
from pathlib import Path
from prompts import (
    SCRIPT_GENERATION_PROMPT,
    KEYFRAME_EXTRACTION_PROMPT,
    DIALOG_EXTRACTION_PROMPT,
    VISUAL_STYLE_PROMPT,
    CHARACTER_EXTRACTION_PROMPT,
    SCRIPT_ENHANCEMENT_PROMPT,
    LEONARDO_PROMPT_OPTIMIZATION,
    WORDS_PER_KEYFRAME
)
from schemas import (
    LeonardoStyles,
    Role,
    VisualStyleResponse,
    DialogResponse,
    Keyframe,
    KeyframeResponse,
    Character,
    Characters
)
from tts_core import generate_speech_from_text

# Set up logging configuration
logging.basicConfig(
    level=logging.ERROR,  # Default to ERROR level
    format="%(asctime)s - %(levelname)s - %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S"
)
logger = logging.getLogger(__name__)

# Load environment variables from specified path
env_path = os.path.join(os.path.dirname(__file__), "../../.env")
load_dotenv(env_path)

# Initialize OpenAI client
client = OpenAI()

# ---------- Helper Functions ----------

def log_prompt_and_response(prompt: str, response: str, context: str = ""):
    """Helper function to log prompts and responses in a readable format."""
    if context:
        logger.debug("\n=== %s ===", context)
    logger.debug("\n----- Prompt -----\n%s", textwrap.indent(prompt, "> "))
    logger.debug("\n----- Response -----\n%s", textwrap.indent(response, "< "))
    logger.debug("-" * 60)

def invoke_chat_completion(prompt: str, response_format=None):
    """
    Helper function to invoke OpenAI chat completion API.

    Args:
        prompt: The prompt to send to the API.
        response_format: Optional Pydantic class specifying the response format (for structured outputs).

    Returns:
        If response_format is provided, returns the response object from the beta.parse() method.
        Otherwise, returns the message object from a standard completion.
    """
    params = {
        "model": "gpt-4o",
        "messages": [{"role": "user", "content": prompt}],
        "temperature": 0.7,
    }
    if response_format:
        # Use the beta parsing method which enforces structured outputs based on the provided Pydantic model.
        response = client.beta.chat.completions.parse(
            model=params["model"],
            messages=params["messages"],
            temperature=params["temperature"],
            response_format=response_format,
        )
        return response
    else:
        response = client.chat.completions.create(**params)
        return response.choices[0].message

# ---------- OpenAI Pipeline Tasks using LangGraph ----------

@task
def generate_script(keywords: List[str]) -> str:
    """
    Generates a full screenplay script from a list of theme keywords.
    """
    logger.info("Generating script with keywords: %s", ", ".join(keywords))
    start_time = time.time()
    
    prompt = SCRIPT_GENERATION_PROMPT.format(keywords=", ".join(keywords))
    logger.debug("Sending prompt to OpenAI (length: %d characters)", len(prompt))
    
    response = invoke_chat_completion(prompt)
    # For standard completions, response is a message object with a 'content' attribute.
    script = response.content if hasattr(response, "content") else response

    elapsed_time = time.time() - start_time
    logger.info("Script generation completed in %.2f seconds", elapsed_time)
    logger.debug("Generated script length: %d characters", len(script))
    
    log_prompt_and_response(prompt, script, "Script Generation")
    return script

@task
def extract_keyframes(script: str, num_keyframes: int) -> List[Dict[str, str]]:
    """
    Breaks the screenplay into key visual moments ("keyframes") optimized for prompting an image generator.
    Returns the keyframes directly as a list of dictionaries.
    """
    logger.info("Extracting keyframes from script")
    start_time = time.time()
    
    prompt = KEYFRAME_EXTRACTION_PROMPT.format(
        script=script,
        num_keyframes=num_keyframes
    )
    logger.debug("Sending keyframe extraction prompt to OpenAI")
    
    # Use beta parsing with our Pydantic schema.
    response = invoke_chat_completion(prompt, response_format=KeyframeResponse)
    # Access the parsed result from the beta response.
    parsed_message = response.choices[0].message.parsed
    keyframes = parsed_message.keyframes
    log_prompt_and_response(prompt, str(parsed_message), "Keyframe Extraction")
    
    elapsed_time = time.time() - start_time
    logger.info("Extracted %d keyframes in %.2f seconds", len(keyframes), elapsed_time)
    
    # Convert each Pydantic model instance to a dict.
    return [kf.model_dump() for kf in keyframes]

@task
def extract_dialog(script: str, keyframe_description: str, characters: List[Character]) -> DialogResponse:
    """
    Combines the full screenplay, keyframe description, and character profiles to extract dialogue and narration.
    Returns a DialogResponse containing the speaking character and text.
    """
    logger.debug("Extracting dialog for keyframe: %s", keyframe_description[:100] + "...")
    start_time = time.time()
    
    # Create a narrator character that can be used if needed
    narrator = Character(
        role=Role.NARRATOR,
        name="Narrator",
        backstory="An omniscient storyteller who guides the audience through the narrative.",
        physical_description="A disembodied voice with gravitas and warmth.",
        personality="Wise, neutral, and observant, with a clear and engaging speaking style."
    )
    
    prompt = DIALOG_EXTRACTION_PROMPT.format(
        keyframe_description=keyframe_description,
        script=script,
        characters="\n".join(f"- {char.name} ({char.role}): {char.personality}" for char in characters)
    )
    response = invoke_chat_completion(prompt, response_format=DialogResponse)
    dialog = response.choices[0].message.parsed
    
    # If the model chose to use a narrator voice, replace with our narrator character
    if dialog.character.role == Role.NARRATOR:
        dialog.character = narrator
    
    # Create a JSON-compatible dict for logging
    dialog_dict = {
        "character": {
            "name": dialog.character.name,
            "role": dialog.character.role,
            "personality": dialog.character.personality[:50] + "..."
        },
        "text": dialog.text
    }
    log_prompt_and_response(prompt, str(dialog_dict), 
                          f"Dialog Extraction (Keyframe: {keyframe_description[:50]}...)")
    
    elapsed_time = time.time() - start_time
    logger.debug("Dialog extraction completed in %.2f seconds", elapsed_time)
    
    return dialog

@task
def determine_visual_style(script: str) -> LeonardoStyles:
    """
    Analyzes the script and determines the most appropriate visual style for the scenes.
    Returns one of the predefined LeonardoStyles.
    """
    logger.info("Determining visual style for the script")
    start_time = time.time()
    
    prompt = VISUAL_STYLE_PROMPT.format(script=script)
    logger.debug("Sending visual style prompt to OpenAI")
    
    response = invoke_chat_completion(prompt, response_format=VisualStyleResponse)
    # Access the parsed result from the beta response
    style = response.choices[0].message.parsed.style
    
    log_prompt_and_response(prompt, str(style), "Visual Style Determination")
    
    elapsed_time = time.time() - start_time
    logger.info("Visual style determined in %.2f seconds: %s", elapsed_time, style)
    
    return style

@task
def generate_voiceover(dialog: DialogResponse) -> bytes:
    """
    Generates audio voiceover for the given dialog using TTS.
    
    Args:
        dialog: The DialogResponse containing character and text
        
    Returns:
        Audio data as bytes
    """
    logger.info(f"Generating voiceover for {dialog.character.name} ({dialog.character.role}): {dialog.text[:50]}...")
    start_time = time.time()
    
    try:
        # Extract role from character for TTS
        response = generate_speech_from_text(dialog.text, character=dialog.character.role.value)
        audio_data = response.read()
        
        elapsed_time = time.time() - start_time
        logger.info(f"Voiceover generation completed in {elapsed_time:.2f} seconds")
        
        return audio_data
        
    except Exception as e:
        logger.error(f"Failed to generate voiceover: {str(e)}")
        raise

@task
def extract_characters(script: str) -> List[Character]:
    """
    Analyzes the script and extracts/generates character profiles.
    Returns a list of Character objects.
    """
    logger.info("Extracting characters from script")
    start_time = time.time()
    
    prompt = CHARACTER_EXTRACTION_PROMPT.format(script=script)
    logger.debug("Sending character extraction prompt to OpenAI")
    
    # Use beta parsing with our Pydantic schema
    response = invoke_chat_completion(prompt, response_format=Characters)
    # Access the parsed result from the beta response
    characters = response.choices[0].message.parsed.characters
    
    log_prompt_and_response(prompt, str(characters), "Character Extraction")
    
    elapsed_time = time.time() - start_time
    logger.info("Extracted %d characters in %.2f seconds", len(characters), elapsed_time)
    
    return characters

@task
def enhance_script(script: str, characters: List[Character], num_keyframes: int) -> str:
    """
    Takes the original script and extracted characters and generates an enhanced version
    that incorporates the characters more naturally into the narrative.
    """
    logger.info("Enhancing script with character details")
    start_time = time.time()
    
    # Format character information for the prompt
    char_info = "\n\n".join([
        f"Character: {char.name} ({char.role})\n"
        f"Backstory: {char.backstory}\n"
        f"Personality: {char.personality}"
        for char in characters
    ])
    
    # Calculate total target word count based on number of keyframes
    total_words = num_keyframes * WORDS_PER_KEYFRAME
    
    prompt = SCRIPT_ENHANCEMENT_PROMPT.format(
        script=script,
        characters=char_info,
        total_words=total_words
    )
    
    response = invoke_chat_completion(prompt)
    enhanced_script = response.content
    
    log_prompt_and_response(prompt, enhanced_script, "Script Enhancement")
    
    elapsed_time = time.time() - start_time
    logger.info("Script enhancement completed in %.2f seconds", elapsed_time)
    
    return enhanced_script

@task
def optimize_leonardo_prompts(keyframes: List[Dict[str, str]], visual_style: LeonardoStyles, output_dir: str) -> List[str]:
    """
    Optimizes all keyframe descriptions together into prompts specifically crafted for Leonardo's Flux Schnell model.
    This ensures visual consistency across all generated images.
    
    Args:
        keyframes: List of keyframe dictionaries containing descriptions
        visual_style: The chosen visual style for the story
        output_dir: Directory to save the prompt files
        
    Returns:
        List of optimized prompt strings for Leonardo
    """
    logger.info("Optimizing all keyframes for Leonardo prompts")
    start_time = time.time()
    
    # Format all keyframe descriptions
    keyframe_descriptions = "\n\n".join(
        f"Keyframe {idx + 1}:\n{kf['description']}"
        for idx, kf in enumerate(keyframes)
    )
    
    prompt = LEONARDO_PROMPT_OPTIMIZATION.format(
        keyframe_descriptions=keyframe_descriptions,
        visual_style=visual_style
    )
    
    response = invoke_chat_completion(prompt)
    full_response = response.content.strip()
    
    # Parse the numbered responses
    optimized_prompts = []
    current_prompt = []
    current_number = 1
    
    for line in full_response.split('\n'):
        line = line.strip()
        if not line:
            continue
            
        # Check if this line starts a new prompt
        if line.startswith(f"{current_number}:"):
            if current_prompt:  # Save the previous prompt
                optimized_prompts.append('\n'.join(current_prompt))
                current_prompt = []
            current_prompt.append(line[len(f"{current_number}:"):].strip())
            current_number += 1
        else:
            current_prompt.append(line)
    
    # Add the last prompt
    if current_prompt:
        optimized_prompts.append('\n'.join(current_prompt))
    
    # Save each prompt to a file
    output_path = Path(output_dir)
    output_path.mkdir(parents=True, exist_ok=True)
    
    logger.info(f"Saving optimized prompts to directory: {output_path}")
    for idx, prompt_text in enumerate(optimized_prompts, 1):
        prompt_file = output_path / f"keyframe_prompt_{idx}.txt"
        try:
            prompt_file.write_text(prompt_text)
            logger.info(f"Saved prompt {idx} to {prompt_file}")
            # Print the first few characters of the prompt for verification
            logger.debug(f"Prompt {idx} preview: {prompt_text[:100]}...")
        except Exception as e:
            logger.error(f"Failed to save prompt {idx} to {prompt_file}: {e}")
    
    log_prompt_and_response(prompt, full_response, "Leonardo Prompt Optimization (All Keyframes)")
    
    elapsed_time = time.time() - start_time
    logger.info(f"Prompt optimization completed in {elapsed_time:.2f} seconds. Generated {len(optimized_prompts)} prompts.")
    
    return optimized_prompts

@entrypoint(checkpointer=MemorySaver())
def generate_story(inputs: Dict[str, List[str]], config: Dict[str, Any] = None) -> Tuple[List[Tuple[str, DialogResponse, str, bytes | None]], Optional[List[Character]], Optional[Tuple[str, str]]]:
    """
    Public interface function that ties the OpenAI steps together.

    Input:
      - inputs: Dictionary containing 'keywords' list
      - config: Configuration dictionary containing:
        - thread_id: ID for the story generation thread
        - extract_chars: Whether to extract character profiles
        - generate_voiceover: Whether to generate voiceover audio
        - generate_images: Whether to generate images using Leonardo
        - num_keyframes: Number of keyframes to generate (default: 4)
        - output_dir: Directory to save generated files (default: "output")

    Output:
      - A tuple of:
        - List of tuples (keyframe description, dialog response, visual style, audio_data)
          Note: audio_data will be None if voiceover generation is disabled
        - Optional list of Character objects if extract_chars is True
        - Optional tuple of (original_script, enhanced_script) if script output is requested
    """
    logger.info("Starting story generation process")
    start_time = time.time()
    
    keywords = inputs["keywords"]
    logger.info("Processing keywords: %s", ", ".join(keywords))
    
    # Get config options
    extract_chars = config.get("configurable", {}).get("extract_chars", False) if config else False
    should_generate_voiceover = config.get("configurable", {}).get("generate_voiceover", False) if config else False
    should_generate_images = config.get("configurable", {}).get("generate_images", False) if config else False
    save_script = config.get("configurable", {}).get("save_script", False) if config else False
    num_keyframes = config.get("configurable", {}).get("num_keyframes", 4) if config else 4
    output_dir = config.get("configurable", {}).get("output_dir", "output") if config else "output"
    
    logger.info(f"Using output directory: {output_dir}")
    
    # Create output directory if it doesn't exist
    Path(output_dir).mkdir(parents=True, exist_ok=True)
    
    # Generate the initial script
    script = generate_script(keywords).result()
    logger.debug("Original script generated (%d chars):\n%s", len(script), script)
    
    # Always extract characters since we need them for dialog
    characters = extract_characters(script).result()
    
    # Enhance the script with character details
    enhanced_script = enhance_script(script, characters, num_keyframes).result()
    logger.debug("Enhanced script generated (%d chars):\n%s", len(enhanced_script), enhanced_script)
    
    # Continue with the enhanced script
    tasks = {
        'keyframes': extract_keyframes(enhanced_script, num_keyframes),
        'visual_style': determine_visual_style(enhanced_script),
    }
    
    # Wait for all initial tasks to complete
    results = {name: task.result() for name, task in tasks.items()}
    keyframes = results['keyframes']
    visual_style = results['visual_style']
    
    # If image generation is enabled, optimize all keyframe descriptions together for Leonardo
    if should_generate_images:
        logger.info("Optimizing all keyframe descriptions together for Leonardo")
        optimized_prompts = optimize_leonardo_prompts(keyframes, visual_style, output_dir).result()
        # Update keyframe descriptions with optimized prompts for Leonardo
        for kf, optimized_prompt in zip(keyframes, optimized_prompts):
            kf["leonardo_prompt"] = optimized_prompt
    
    # First, launch all dialog extraction tasks in parallel
    logger.info("Launching parallel dialog extraction for %d keyframes", len(keyframes))
    # Use original descriptions for dialog, not the optimized prompts
    dialog_tasks = [extract_dialog(enhanced_script, kf["description"], characters) for kf in keyframes]
    
    # Wait for all dialogs to complete
    dialogs = [task.result() for task in dialog_tasks]
    
    # Generate voiceovers only if requested
    voiceovers = []
    if should_generate_voiceover:
        logger.info("Launching parallel voiceover generation for %d keyframes", len(keyframes))
        voiceover_tasks = [generate_voiceover(dialog) for dialog in dialogs]
        voiceovers = [task.result() for task in voiceover_tasks]
    else:
        voiceovers = [None] * len(dialogs)
    
    # Combine results - ALWAYS use original description for the story output
    # The leonardo_prompt is only used by the image generation pipeline
    story_results = [
        (kf["description"], dialog, visual_style, voiceover)
        for kf, dialog, voiceover in zip(keyframes, dialogs, voiceovers)
    ]
    
    total_time = time.time() - start_time
    logger.info("Story generation completed in %.2f seconds", total_time)
    
    # Return scripts if requested
    scripts = (script, enhanced_script) if save_script else None
    
    # Return the story results, characters (if requested), and scripts (if requested)
    return story_results, (characters if extract_chars else None), scripts 