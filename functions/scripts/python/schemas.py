"""
Pydantic models for story generation data structures.
"""

from pydantic import BaseModel
from typing import List
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

class KeyframeResponse(BaseModel):
    keyframes: List[Keyframe] 