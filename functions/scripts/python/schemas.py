"""
Pydantic models for story generation data structures.
"""

from pydantic import BaseModel
from typing import List, Optional
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

class Role(str, Enum):
    NARRATOR = "narrator"
    CHILD = "child"
    ELDER = "elder"
    FAE = "fairy"
    HERO = "hero"
    VILLAIN = "villain"
    SAGE = "sage"
    SIDEKICK = "sidekick"

class Character(BaseModel):
    role: Role
    name: str
    backstory: str
    physical_description: str
    personality: str

class Characters(BaseModel):
    characters: List[Character]

class VisualStyleResponse(BaseModel):
    style: LeonardoStyles

class DialogResponse(BaseModel):
    character: Character
    text: str

class Keyframe(BaseModel):
    title: str
    description: str
    characters_in_scene: List[str]  # List of character names present in this keyframe

class KeyframeResponse(BaseModel):
    keyframes: List[Keyframe]

class KeyframeScene(BaseModel):
    character: Character
    dialog: str  # The spoken text for this scene
    title: str
    description: str
    characters_in_scene: List[str]
    leonardo_prompt: Optional[str] = None  # The optimized prompt for Leonardo image generation

class KeyframesWithDialog(BaseModel):
    scenes: List[KeyframeScene] 