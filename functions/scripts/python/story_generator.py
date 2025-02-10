"""
Core functionality for generating stories using OpenAI and LangGraph.
"""

import os
from dotenv import load_dotenv
from typing import List, Dict, Tuple
from openai import OpenAI
from langgraph.func import task, entrypoint
from langgraph.checkpoint.memory import MemorySaver
import logging
import time
import textwrap
from pydantic import BaseModel
from prompts import (
    SCRIPT_GENERATION_PROMPT,
    KEYFRAME_EXTRACTION_PROMPT,
    DIALOG_EXTRACTION_PROMPT,
    VISUAL_STYLE_PROMPT
)
from enum import Enum

class LeonardoStyles(str, Enum):
    RENDER_3D = "RENDER_3D"
    ACRYLIC = "ACRYLIC"
    ANIME_GENERAL = "ANIME_GENERAL"
    CREATIVE = "CREATIVE"
    DYNAMIC = "DYNAMIC"
    FASHION = "FASHION"
    GAME_CONCEPT = "GAME_CONCEPT"
    GRAPHIC_DESIGN_3D = "GRAPHIC_DESIGN_3D"
    ILLUSTRATION = "ILLUSTRATION"
    NONE = "NONE"
    PORTRAIT = "PORTRAIT"
    PORTRAIT_CINEMATIC = "PORTRAIT_CINEMATIC"
    RAY_TRACED = "RAY_TRACED"
    STOCK_PHOTO = "STOCK_PHOTO"
    WATERCOLOR = "WATERCOLOR"


class VisualStyleResponse(BaseModel):
    style: LeonardoStyles

# Set up logging configuration
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S"
)
logger = logging.getLogger(__name__)

# Load environment variables from specified path
env_path = os.path.join(os.path.dirname(__file__), "../../.env")
load_dotenv(env_path)

# Initialize OpenAI client
client = OpenAI()

# Define response schema classes
class Keyframe(BaseModel):
    title: str
    description: str

class KeyframeResponse(BaseModel):
    keyframes: List[Keyframe]

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
        "model": "gpt-4o-mini",
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
def extract_keyframes(script: str) -> List[Dict[str, str]]:
    """
    Breaks the screenplay into key visual moments ("keyframes") optimized for prompting an image generator.
    Returns the keyframes directly as a list of dictionaries.
    """
    logger.info("Extracting keyframes from script")
    start_time = time.time()
    
    prompt = KEYFRAME_EXTRACTION_PROMPT.format(script=script)
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
def extract_dialog(script: str, keyframe_description: str) -> str:
    """
    Combines the full screenplay and a keyframe description to extract dialogue and narration.
    """
    logger.debug("Extracting dialog for keyframe: %s", keyframe_description[:100] + "...")
    start_time = time.time()
    
    prompt = DIALOG_EXTRACTION_PROMPT.format(
        keyframe_description=keyframe_description,
        script=script
    )
    response = invoke_chat_completion(prompt)
    dialog = response.content if hasattr(response, "content") else response

    log_prompt_and_response(prompt, dialog, f"Dialog Extraction (Keyframe: {keyframe_description[:50]}...)")
    
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

@entrypoint(checkpointer=MemorySaver())
def generate_story(inputs: Dict[str, List[str]]) -> List[Tuple[str, str, str]]:
    """
    Public interface function that ties the OpenAI steps together.

    Input:
      - inputs: Dictionary containing 'keywords' list

    Output:
      - A list of tuples, where each tuple is (keyframe description, keyframe dialog/narration, visual style).
    """
    logger.info("Starting story generation process")
    start_time = time.time()
    
    keywords = inputs["keywords"]
    logger.info("Processing keywords: %s", ", ".join(keywords))
    
    # Generate the initial script
    script = generate_script(keywords).result()
    
    # Parallel tasks: Extract keyframes and determine visual style
    keyframes = extract_keyframes(script).result()
    visual_style = determine_visual_style(script).result()
    
    logger.info("Processing dialog for %d keyframes", len(keyframes))
    results: List[Tuple[str, str, str]] = []
    for i, kf in enumerate(keyframes, 1):
        logger.debug("Processing dialog for keyframe %d/%d", i, len(keyframes))
        dialog = extract_dialog(script, kf["description"]).result()
        # Include the visual style with each keyframe
        results.append((kf["description"], dialog, visual_style))
    
    total_time = time.time() - start_time
    logger.info("Story generation completed in %.2f seconds", total_time)
    
    return results 