import * as admin from 'firebase-admin';
import Mux from '@mux/mux-node';
import * as dotenv from 'dotenv';
import * as path from 'path';

// Define interface for passthrough data
interface PassthroughData {
  creator?: string;
  description?: string;
}

// Load environment variables
dotenv.config({ path: path.resolve(__dirname, '../.env') });

// Initialize Firebase Admin
const serviceAccount = require('../serviceAccountKey.json');
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

// Initialize Mux client
const muxClient = new Mux({
  tokenId: process.env.MUX_TOKEN_ID,
  tokenSecret: process.env.MUX_TOKEN_SECRET,
});

async function migrateAssets() {
  try {
    console.log('🔍 Fetching assets from Mux...');
    
    // Get all assets from Mux
    const assets = await muxClient.video.assets.list();
    console.log(`📊 Found ${assets.data.length} assets in Mux`);

    // Process each asset
    for (const asset of assets.data) {
      console.log(`\n🎥 Processing asset: ${asset.id}`);
      
      // Get the playback ID
      const playbackId = asset.playback_ids?.[0]?.id;
      if (!playbackId) {
        console.log(`⚠️ No playback ID found for asset ${asset.id}, skipping...`);
        continue;
      }

      // Parse the passthrough data which contains our metadata
      let passthroughData: PassthroughData = {};
      try {
        if (asset.passthrough) {
          passthroughData = JSON.parse(asset.passthrough) as PassthroughData;
        }
      } catch (e) {
        console.log(`⚠️ Error parsing passthrough data for asset ${asset.id}:`, e);
      }

      // Extract metadata
      const metadata = {
        id: asset.id,
        playback_id: playbackId,
        creator: passthroughData.creator || 'Unknown Creator',
        description: passthroughData.description || 'No description available',
        created_at: asset.created_at ? new Date(parseInt(asset.created_at) * 1000).getTime() : Date.now(),
        status: asset.status === 'ready' ? 'ready' : 'processing'
      };

      // Create or update document in Firestore
      await db.collection('videos').doc(asset.id).set(metadata, { merge: true });
      console.log(`✅ Created/updated Firestore document for asset ${asset.id}`);
      
      // Log the metadata for verification
      console.log('📝 Metadata:', metadata);
      console.log('📦 Original passthrough:', asset.passthrough);
    }

    console.log('\n✨ Migration completed successfully!');
    process.exit(0);
  } catch (error) {
    console.error('❌ Error during migration:', error);
    process.exit(1);
  }
}

// Run the migration
migrateAssets(); 