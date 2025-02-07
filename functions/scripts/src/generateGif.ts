import { writeFileSync } from 'fs';
import { generateAnimatedProfileGif } from './index';

function printUsage() {
    console.log(`
Usage: generate-gif.sh <userHash> [options]

Options:
    --width     <pixels>  Width of the GIF (default: 200)
    --height    <pixels>  Height of the GIF (default: 200)
    --frames    <number>  Number of frames (default: 30)
    --delay     <ms>      Delay between frames in ms (default: 100)
    --output    <path>    Output file path (default: output.gif)
    --help                Show this help message
`);
}

function main() {
    const args = process.argv.slice(2);
    
    if (args.length === 0 || args.includes('--help')) {
        printUsage();
        process.exit(0);
    }

    const userHash = args[0];
    let width = 200;
    let height = 200;
    let frames = 30;
    let delay = 100;
    let outputPath = 'output.gif';

    // Parse named arguments
    for (let i = 1; i < args.length; i += 2) {
        switch (args[i]) {
            case '--width':
                width = parseInt(args[i + 1]);
                break;
            case '--height':
                height = parseInt(args[i + 1]);
                break;
            case '--frames':
                frames = parseInt(args[i + 1]);
                break;
            case '--delay':
                delay = parseInt(args[i + 1]);
                break;
            case '--output':
                outputPath = args[i + 1];
                break;
            default:
                console.error(`Unknown option: ${args[i]}`);
                printUsage();
                process.exit(1);
        }
    }

    try {
        const gifBuffer = generateAnimatedProfileGif(userHash, width, height, frames, delay);
        writeFileSync(outputPath, gifBuffer);
        console.log(`Generated GIF saved to: ${outputPath}`);
    } catch (error) {
        console.error('Error generating GIF:', error);
        process.exit(1);
    }
}

main(); 