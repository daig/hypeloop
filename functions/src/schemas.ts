import { z } from 'zod';

// Enums
export const LeonardoStyles = {
  RENDER_3D: 'RENDER_3D',
  ACRYLIC: 'ACRYLIC',
  ANIME_GENERAL: 'ANIME_GENERAL',
  CREATIVE: 'CREATIVE',
  DYNAMIC: 'DYNAMIC',
  FASHION: 'FASHION',
  GAME_CONCEPT: 'GAME_CONCEPT',
  GRAPHIC_DESIGN_3D: 'GRAPHIC_DESIGN_3D',
  ILLUSTRATION: 'ILLUSTRATION',
  NONE: 'NONE',
  PORTRAIT: 'PORTRAIT',
  PORTRAIT_CINEMATIC: 'PORTRAIT_CINEMATIC',
  RAY_TRACED: 'RAY_TRACED',
  STOCK_PHOTO: 'STOCK_PHOTO',
  WATERCOLOR: 'WATERCOLOR',
} as const;

export const Role = {
  NARRATOR: 'narrator',
  CHILD: 'child',
  ELDER: 'elder',
  FAE: 'fairy',
  HERO: 'hero',
  VILLAIN: 'villain',
  SAGE: 'sage',
  SIDEKICK: 'sidekick',
} as const;

// Zod schemas
export const leonardoStylesSchema = z.enum([
  'RENDER_3D',
  'ACRYLIC',
  'ANIME_GENERAL',
  'CREATIVE',
  'DYNAMIC',
  'FASHION',
  'GAME_CONCEPT',
  'GRAPHIC_DESIGN_3D',
  'ILLUSTRATION',
  'NONE',
  'PORTRAIT',
  'PORTRAIT_CINEMATIC',
  'RAY_TRACED',
  'STOCK_PHOTO',
  'WATERCOLOR',
]);

export const roleSchema = z.enum([
  'narrator',
  'child',
  'elder',
  'fairy',
  'hero',
  'villain',
  'sage',
  'sidekick',
]);

export const characterSchema = z.object({
  role: roleSchema,
  name: z.string(),
  backstory: z.string(),
  physical_description: z.string(),
  personality: z.string(),
});

export const charactersSchema = z.object({
  characters: z.array(characterSchema),
});

export const visualStyleResponseSchema = z.object({
  style: leonardoStylesSchema,
});

export const dialogResponseSchema = z.object({
  character: characterSchema,
  text: z.string(),
});

export const keyframeSchema = z.object({
  title: z.string(),
  description: z.string(),
  characters_in_scene: z.array(z.string()),
});

export const keyframeResponseSchema = z.object({
  keyframes: z.array(keyframeSchema),
});

export const keyframeSceneSchema = z.object({
  character: characterSchema,
  dialog: z.string(),
  title: z.string(),
  description: z.string(),
  characters_in_scene: z.array(z.string()),
  leonardo_prompt: z.string().optional(),
});

export const keyframesWithDialogSchema = z.object({
  scenes: z.array(keyframeSceneSchema),
});

// Type inference
export type LeonardoStyle = z.infer<typeof leonardoStylesSchema>;
export type Role = z.infer<typeof roleSchema>;
export type Character = z.infer<typeof characterSchema>;
export type Characters = z.infer<typeof charactersSchema>;
export type VisualStyleResponse = z.infer<typeof visualStyleResponseSchema>;
export type DialogResponse = z.infer<typeof dialogResponseSchema>;
export type Keyframe = z.infer<typeof keyframeSchema>;
export type KeyframeResponse = z.infer<typeof keyframeResponseSchema>;
export type KeyframeScene = z.infer<typeof keyframeSceneSchema>;
export type KeyframesWithDialog = z.infer<typeof keyframesWithDialogSchema>;