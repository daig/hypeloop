import argparse
import os
from pathlib import Path
from openai import OpenAI
from dotenv import load_dotenv

def read_text_file(file_path):
    """Read content from a text file."""
    with open(file_path, 'r', encoding='utf-8') as file:
        return file.read()

def generate_speech(text, output_path, voice="alloy", model="tts-1"):
    """Generate speech from text using OpenAI's TTS API."""
    # Load environment variables from two directories up
    env_path = os.path.join(os.path.dirname(__file__), '..', '..', '.env')
    load_dotenv(env_path)
    
    # Initialize OpenAI client
    client = OpenAI(api_key=os.getenv('OPENAI_API_KEY'))
    
    try:
        # Create output directory if it doesn't exist
        output_dir = os.path.dirname(output_path)
        if output_dir:
            os.makedirs(output_dir, exist_ok=True)
            
        # Generate speech with streaming response
        response = client.audio.speech.create(
            model=model,
            voice=voice,
            input=text
        )
        
        # Save to file using the streaming response
        with open(output_path, 'wb') as file:
            for chunk in response.iter_bytes():
                file.write(chunk)
                
        print(f"Successfully generated audio file: {output_path}")
        
    except Exception as e:
        print(f"Error generating speech: {str(e)}")
        raise

def main():
    parser = argparse.ArgumentParser(description='Convert text file to speech using OpenAI TTS API')
    parser.add_argument('input_file', type=str, help='Path to the input text file')
    parser.add_argument('--output', '-o', type=str, help='Path to the output audio file (default: input_file_name.mp3)',
                      default=None)
    parser.add_argument('--voice', '-v', type=str, choices=['alloy', 'echo', 'fable', 'onyx', 'nova', 'shimmer'],
                      default='alloy', help='Voice to use for TTS (default: alloy)')
    parser.add_argument('--model', '-m', type=str, choices=['tts-1', 'tts-1-hd'],
                      default='tts-1', help='Model to use for TTS (default: tts-1)')

    args = parser.parse_args()

    # Validate input file
    if not os.path.exists(args.input_file):
        print(f"Error: Input file '{args.input_file}' does not exist")
        return

    # Set default output path if not provided
    if args.output is None:
        input_path = Path(args.input_file)
        args.output = str(input_path.with_suffix('.mp3'))

    try:
        # Read input text
        text = read_text_file(args.input_file)
        
        # Generate speech
        generate_speech(text, args.output, args.voice, args.model)
        
    except Exception as e:
        print(f"Error: {str(e)}")

if __name__ == "__main__":
    main() 