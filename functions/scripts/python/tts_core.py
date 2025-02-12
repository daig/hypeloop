import os
from openai import OpenAI
from dotenv import load_dotenv
from schemas import Role

def get_voice_for_character(character):
    """Map character types to appropriate voices."""
    character_voices : Dict[Role, str] = {
        Role.NARRATOR: 'fable',  # Warm, engaging narrator voice
        Role.CHILD: 'nova',      # Youthful, bright voice
        Role.ELDER: 'onyx',      # Deep, authoritative voice
        Role.FAE: 'shimmer',   # Light, whimsical voice
        Role.HERO: 'alloy',      # Balanced, confident voice
        Role.VILLAIN: 'ash',     # Dramatic, resonant voice
        Role.SAGE: 'sage',
        Role.SIDEKICK: 'coral'
    }
    return character_voices.get(character.lower(), 'fable')  # Default to fable if character not found

def generate_speech_from_text(text, character="narrator", model="tts-1"):
    """Generate speech from text using OpenAI's TTS API."""
    # Load environment variables from two directories up
    env_path = os.path.join(os.path.dirname(__file__), '..', '..', '.env')
    load_dotenv(env_path)
    
    # Initialize OpenAI client
    client = OpenAI(api_key=os.getenv('OPENAI_API_KEY'))
    
    try:
        voice = get_voice_for_character(character)
        
        # Generate speech with streaming response
        response = client.audio.speech.create(
            model=model,
            voice=voice,
            input=text
        )
        
        return response
        
    except Exception as e:
        print(f"Error generating speech: {str(e)}")
        raise 