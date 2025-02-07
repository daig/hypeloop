import { createCanvas, CanvasRenderingContext2D } from 'canvas';
import GIFEncoder from 'gifencoder';

/**
 * A simple linear congruential generator seeded with a number.
 */
function seededRandom(seed: number): () => number {
  return function () {
    // LCG parameters: these numbers are chosen arbitrarily.
    seed = (seed * 9301 + 49297) % 233280;
    return seed / 233280;
  };
}

/**
 * Convert a string (e.g. a user hash) into a numeric seed.
 */
function hashToSeed(hash: string): number {
  let seed = 0;
  for (let i = 0; i < hash.length; i++) {
    seed += hash.charCodeAt(i);
  }
  return seed;
}

/**
 * Draw a filled hexagon.
 *
 * @param ctx - Canvas rendering context.
 * @param x - Center x coordinate.
 * @param y - Center y coordinate.
 * @param radius - Radius of the hexagon.
 * @param rotation - Rotation angle in radians.
 * @param fillStyle - Fill color.
 */
function drawHexagon(
  ctx: CanvasRenderingContext2D,
  x: number,
  y: number,
  radius: number,
  rotation: number,
  fillStyle: string
): void {
  ctx.save();
  ctx.translate(x, y);
  ctx.rotate(rotation);
  ctx.beginPath();
  for (let i = 0; i < 6; i++) {
    const angle = (Math.PI / 3) * i;
    const px = radius * Math.cos(angle);
    const py = radius * Math.sin(angle);
    if (i === 0) {
      ctx.moveTo(px, py);
    } else {
      ctx.lineTo(px, py);
    }
  }
  ctx.closePath();
  ctx.fillStyle = fillStyle;
  ctx.fill();
  ctx.restore();
}

/**
 * Generate an animated GIF based on a user hash. The GIF features several
 * rotating hexagons (in a style inspired by Bees & Bombs) over a dark background.
 * The rotation speeds are chosen so that the animation loops gracefully.
 *
 * @param userHash - A string (e.g. a user ID hash) used to deterministically seed the animation.
 * @param width - Width of the generated GIF in pixels.
 * @param height - Height of the generated GIF in pixels.
 * @param frameCount - Total number of frames in the animation.
 * @param delay - Delay (in ms) between each frame.
 * @returns A Buffer containing the binary GIF data.
 */
export function generateAnimatedProfileGif(
  userHash: string,
  width: number = 200,
  height: number = 200,
  frameCount: number = 30,
  delay: number = 100
): Buffer {
  if (frameCount < 2) {
    throw new Error('frameCount must be at least 2');
  }

  // Create and start the GIF encoder.
  const encoder = new GIFEncoder(width, height);
  encoder.start();
  encoder.setRepeat(0); // loop indefinitely
  encoder.setDelay(delay);
  encoder.setQuality(10);

  // Create a canvas.
  const canvas = createCanvas(width, height);
  const ctx = canvas.getContext('2d');

  // Seed the random generator.
  const seed = hashToSeed(userHash);
  const random = seededRandom(seed);

  // Curated color palettes inspired by modern design trends
  const colorPalettes = [
    {
      name: 'sunset',
      background: { h: 232, s: 47, l: 6 }, // Deep blue-black
      colors: [
        { h: 350, s: 80, l: 60 }, // Coral pink
        { h: 20, s: 85, l: 65 },  // Warm orange
        { h: 45, s: 90, l: 70 },  // Golden yellow
      ]
    },
    {
      name: 'ocean',
      background: { h: 200, s: 45, l: 8 }, // Deep sea blue
      colors: [
        { h: 190, s: 90, l: 65 }, // Aqua
        { h: 210, s: 85, l: 60 }, // Ocean blue
        { h: 170, s: 80, l: 55 }, // Teal
      ]
    },
    {
      name: 'forest',
      background: { h: 150, s: 40, l: 7 }, // Dark forest
      colors: [
        { h: 135, s: 75, l: 55 }, // Leaf green
        { h: 90, s: 70, l: 60 },  // Spring green
        { h: 160, s: 80, l: 45 }, // Deep emerald
      ]
    },
    {
      name: 'cosmic',
      background: { h: 270, s: 45, l: 7 }, // Deep space purple
      colors: [
        { h: 280, s: 85, l: 65 }, // Bright purple
        { h: 320, s: 80, l: 60 }, // Pink
        { h: 260, s: 75, l: 55 }, // Deep violet
      ]
    },
    {
      name: 'candy',
      background: { h: 300, s: 40, l: 8 }, // Dark magenta
      colors: [
        { h: 340, s: 90, l: 65 }, // Hot pink
        { h: 280, s: 85, l: 70 }, // Bright purple
        { h: 315, s: 80, l: 60 }, // Magenta
      ]
    }
  ];

  // Select a palette based on the hash
  const selectedPalette = colorPalettes[Math.floor(random() * colorPalettes.length)];
  
  // Helper function to generate a color variation within the palette theme
  const generateThematicColor = () => {
    // Pick a base color from the palette
    const baseColor = selectedPalette.colors[Math.floor(random() * selectedPalette.colors.length)];
    
    // Create a variation of the base color
    const hueVariation = -10 + random() * 20; // ±10 degrees
    const saturationVariation = -5 + random() * 10; // ±5%
    const lightnessVariation = -10 + random() * 20; // ±10%
    
    return `hsl(${
      Math.floor(baseColor.h + hueVariation)
    }, ${
      Math.max(40, Math.min(100, baseColor.s + saturationVariation))
    }%, ${
      Math.max(30, Math.min(85, baseColor.l + lightnessVariation))
    }%)`;
  };

  // Decide how many shapes to draw.
  const numShapes = 8 + Math.floor(random() * 8); // between 8 and 16 shapes

  // Precalculate properties for each shape.
  type ShapeParams = {
    x: number;
    y: number;
    radius: number;
    rotationSpeed: number; // per frame increment (radians)
    initialRotation: number;
    color: string;
  };

  const shapes: ShapeParams[] = [];
  for (let i = 0; i < numShapes; i++) {
    // For hexagons, one "visual revolution" is actually 1/6th of a full rotation
    // due to 6-fold symmetry. So we'll work with smaller numbers to keep motion gentle.
    
    // Choose a base number of visual revolutions (1/6 to 4/6 of a full rotation)
    const baseRevolutions = (Math.floor(random() * 4) + 1) / 6;
    
    // Add some smaller fractional variation while keeping it compatible with hexagonal symmetry
    // This adds either 0, 1/6, or 2/6 additional revolutions
    const extraRevolutions = Math.floor(random() * 3) / 6;
    const revolutions = baseRevolutions + extraRevolutions;
    
    const sign = random() < 0.5 ? -1 : 1;
    // Calculate the actual rotation speed in radians per frame
    const rotationSpeed = sign * ((revolutions * 2 * Math.PI) / (frameCount - 1));

    shapes.push({
      x: width * random(),
      y: height * random(),
      radius: width / 20 + random() * (width / 10),
      rotationSpeed,
      initialRotation: (random() * Math.PI) / 3, // Start at one of the 6 symmetric positions
      color: generateThematicColor(),
    });
  }

  // Generate each frame.
  for (let frame = 0; frame < frameCount; frame++) {
    // Clear the canvas with the background color.
    const bg = selectedPalette.background;
    ctx.fillStyle = `hsl(${bg.h}, ${bg.s}%, ${bg.l}%)`;
    ctx.fillRect(0, 0, width, height);

    // Draw each hexagon with its current rotation.
    for (const shape of shapes) {
      const rotation = shape.initialRotation + frame * shape.rotationSpeed;
      drawHexagon(ctx, shape.x, shape.y, shape.radius, rotation, shape.color);
    }

    // Draw a pulsating circle in the center with a color from the palette
    const centerX = width / 2;
    const centerY = height / 2;
    const pulsateRadius =
      (width / 10) *
      (0.5 + 0.5 * Math.sin((frame * 2 * Math.PI) / (frameCount - 1)));

    ctx.beginPath();
    ctx.arc(centerX, centerY, pulsateRadius, 0, Math.PI * 2);
    // Use a bright variant from the palette for the center circle
    const centerColor = selectedPalette.colors[Math.floor(frame / frameCount * selectedPalette.colors.length)];
    ctx.strokeStyle = `hsl(${centerColor.h}, ${centerColor.s}%, ${Math.min(75, centerColor.l + 10)}%)`;
    ctx.lineWidth = 3;
    ctx.stroke();

    // Add the current canvas as a frame to the GIF.
    encoder.addFrame(ctx as any);
  }

  encoder.finish();
  return encoder.out.getData();
}

// === Example usage ===
// (In an async context you might write the buffer to a file.)
// import { writeFileSync } from 'fs';
// const gifBuffer = generateAnimatedProfileGif('user123hash');
// writeFileSync('profile.gif', gifBuffer);