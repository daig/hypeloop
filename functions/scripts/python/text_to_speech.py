import argparse
import os
import json
from pathlib import Path
from tts_core import generate_speech_from_text

def read_text_file(file_path):
    """Read content from a text file, supporting both plain text and JSON."""
    with open(file_path, 'r', encoding='utf-8') as file:
        content = file.read()
        try:
            # Try to parse as JSON
            return json.loads(content)
        except json.JSONDecodeError:
            # If not JSON, return as plain text with default character
            return {'text': content, 'character': 'narrator'}

def save_audio_response(response, output_path):
    """Save the audio response to a file."""
    # Create output directory if it doesn't exist
    output_dir = os.path.dirname(output_path)
    if output_dir:
        os.makedirs(output_dir, exist_ok=True)
        
    # Save to file using the streaming response
    with open(output_path, 'wb') as file:
        for chunk in response.iter_bytes():
            file.write(chunk)
            
    print(f"Successfully generated audio file: {output_path}")

def main():
    parser = argparse.ArgumentParser(description='Convert text file to speech using OpenAI TTS API')
    parser.add_argument('input_file', type=str, help='Path to the input text/JSON file')
    parser.add_argument('--output', '-o', type=str, help='Path to the output audio file (default: input_file_name.mp3)',
                      default=None)
    parser.add_argument('--character', '-c', type=str, 
                      choices=['narrator', 'child', 'elder', 'fairy', 'hero', 'villain'],
                      default='narrator', help='Character voice to use (default: narrator)')
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
        # Read input content
        content = read_text_file(args.input_file)
        
        # Use command line character if specified, otherwise use from JSON
        character = args.character if args.character != 'narrator' else content.get('character', 'narrator')
        text = content['text'] if isinstance(content, dict) else content
        
        # Generate speech
        response = generate_speech_from_text(text, character.lower(), args.model)
        
        # Save the audio
        save_audio_response(response, args.output)
        
    except Exception as e:
        print(f"Error: {str(e)}")

if __name__ == "__main__":
    main() 